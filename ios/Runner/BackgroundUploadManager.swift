import Foundation
import UIKit
import os.log

/// iOS native upload pipeline that runs entirely in the background using a
/// `URLSession` background configuration, surviving app kill and device reboot.
///
/// Architecture (mirrors Android's `UploadWorker`):
/// ── 1. init      → ask backend for presigned URL(s) (direct or multipart)
/// ── 2. transfer  → sequential PUT of each 5 MB chunk to S3 via background URLSession
/// ── 3. complete  → (multipart only) send ETags, get final fileUrl
/// ── 4. callback  → notify the backend the asset is ready
///
/// Each phase is a `URLSessionUploadTask` so the OS owns the networking even
/// when the app is suspended or killed. Delegate callbacks chain the next
/// operation (part → part → complete → callback) without waking the Flutter UI.
@objc final class BackgroundUploadManager: NSObject {
    
    // MARK: - Singleton
    
    @objc static let shared = BackgroundUploadManager()
    
    // MARK: - Constants
    
    /// Exposed so `AppDelegate` can match background session identifier.
    static let sessionIdentifier = "net.eduverseapp.upload.session"
    private static let tag = "BGUploadManager"
    
    /// S3 presigned URLs typically expire in 1–6 hours; refresh if queued > 30 min.
    private static let presignedRefreshInterval: TimeInterval = 30 * 60
    
    /// Size of each multipart chunk in bytes (5 MB).
    private static let partSize: Int64 = 5 * 1024 * 1024
    
    // MARK: - Dependencies
    
    private let store = UploadStore()
    private let log = OSLog(subsystem: "net.eduverseapp", category: tag)
    
    /// Background URLSession — all upload/data tasks go through this.
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        config.isDiscretionary = false
        config.shouldUseExtendedBackgroundIdleMode = true
        config.sessionSendsLaunchEvents = true
        // Allow ample time for large 5 MB PUTs
        config.timeoutIntervalForResource = 3600 // 1 hour per part
        config.timeoutIntervalForRequest = 300    // 5 min per request
        config.waitsForConnectivity = true
        // Shared container for app group if needed (extension compatibility)
        config.sharedContainerIdentifier = nil
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()
    
    /// Ephemeral session for lightweight API calls that don't need background
    /// resurrection (init, complete, callback). Swift's async/await makes this clean.
    private lazy var apiSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        config.waitsForConnectivity = true
        return URLSession(configuration: config)
    }()
    
    // MARK: - State
    
    private var _currentJob: UploadJobData?
    private var _currentInit: InitResult?
    private var _currentPartIndex: Int = 0
    private var _etags: [[String: Any]] = []
    private var _completionHandler: (() -> Void)?
    
    /// Tracks taskId → (jobId, partNumber) for delegate routing.
    private var _taskMap: [Int: (jobId: String, partNumber: Int?)] = [:]
    private let _taskMapLock = NSLock()
    
    /// Current job ID being processed (to avoid concurrent jobs stomping state).
    private var _activeJobId: String?
    private let _stateLock = NSLock()
    
    // MARK: - Public API (called from Flutter MethodChannel)
    
    /// Enqueue a new upload job. Returns immediately; processing runs asynchronously.
    @objc func enqueue(jobData: [String: Any]) {
        let job = UploadJobData(from: jobData)
        store.savePending(job)
        os_log("📦 Enqueued job %{public}@", log: log, type: .info, job.jobId)
        processNext()
    }
    
    /// Return all terminal results, encoded as JSON strings (same format as Android bridge).
    @objc func getCompletedJobs() -> [[String: Any]] {
        return store.allResults()
    }
    
    /// Clear a terminal result after Dart has reconciled it.
    @objc func clearResult(jobId: String) {
        store.clearResult(jobId)
    }
    
    /// Cancel all pending uploads.
    @objc func cancelAll() {
        _stateLock.lock()
        _activeJobId = nil
        _currentJob = nil
        _currentInit = nil
        _stateLock.unlock()
        session.invalidateAndCancel()
        // The next call to enqueue will create a new session.
    }
    
    /// Set the background completion handler (called from AppDelegate).
    @objc func setCompletionHandler(_ handler: @escaping () -> Void) {
        _completionHandler = handler
    }
    
    // MARK: - Job Processing Pipeline
    
    /// Attempt to process the next pending job. Runs on a background queue.
    private func processNext() {
        guard store.pendingCount > 0 else {
            os_log("✅ No pending jobs", log: log, type: .info)
            return
        }
        
        _stateLock.lock()
        guard _activeJobId == nil else {
            _stateLock.unlock()
            os_log("⏳ Already processing a job", log: log, type: .debug)
            return // already busy
        }
        _stateLock.unlock()
        
        // Find the oldest pending job (FIFO order).
        let pendingDir = FileManager.default.urls(
            for: .cachesDirectory, in: .userDomainMask
        ).first!.appendingPathComponent("eduverse_upload/pending")
        
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: pendingDir, includingPropertiesForKeys: [.creationDateKey]
        ) else { return }
        
        let sorted = files
            .filter { $0.pathExtension == "json" }
            .sorted { a, b in
                let da = (try? a.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
                let db = (try? b.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
                return da < db
            }
        
        guard let first = sorted.first else { return }
        let jobId = first.deletingPathExtension().lastPathComponent
        guard let job = store.loadPending(jobId) else { return }
        
        _stateLock.lock()
        _activeJobId = job.jobId
        _currentJob = job
        _currentPartIndex = 0
        _etags = []
        _stateLock.unlock()
        
        os_log("▶️ Starting job %{public}@", log: log, type: .info, job.jobId)
        runPipeline(job: job)
    }
    
    /// Full pipeline: init → transfer → complete → callback.
    /// Runs each step via async/await on a background serial queue.
    private func runPipeline(job: UploadJobData) {
        // Dispatch to a background serial queue so we don't block the main thread.
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self = self else { return }
            
            // ── Step 1: Init ──
            guard let initResult = self.callInit(job: job) else {
                self.failJob(job: job, error: "Init failed")
                return
            }
            
            var init = initResult
            var fileUrl = init.fileUrl
            
            // ── Proactive presigned URL refresh ──
            let age = Date().timeIntervalSince1970 - TimeInterval(job.createdAt) / 1000
            if init.isMultipart && age > Self.presignedRefreshInterval {
                os_log("🔄 Proactive URL refresh for %{public}@ (age=%.0fs)",
                       log: self.log, type: .info, job.jobId, age)
                if let freshInit = self.callInit(job: job) {
                    if freshInit.isMultipart && freshInit.parts.count == init.parts.count {
                        for i in init.parts.indices {
                            init.parts[i].uploadUrl = freshInit.parts[i].uploadUrl
                        }
                    }
                }
            }
            
            // Capture the init result for the delegate callbacks.
            self._stateLock.lock()
            self._currentInit = init
            self._currentPartIndex = 0
            self._etags = init.parts.map { ["partNumber": $0.partNumber, "eTag": ""] }
            self._stateLock.unlock()
            
            // ── Step 2: Transfer (sequential) ──
            if init.isMultipart {
                // Start uploading the first part. Subsequent parts are triggered
                // by the URLSession delegate when each part completes.
                self.uploadNextPart(job: job, init: init)
                
                // Wait here until all parts are done (signalled via semaphore).
                // The delegate callbacks drive the sequential upload.
                // We use a runloop-spin approach since we're on a background thread
                // and the delegate runs on the URLSession's delegate queue.
                self.waitForTransferCompletion(job: job, init: init)
                
                // ── Step 3: Complete (multipart only) ──
                guard let completeResult = self.callComplete(job: job, init: init) else {
                    self.abortS3(job: job, init: init)
                    self.failJob(job: job, error: "Complete failed")
                    return
                }
                fileUrl = completeResult
            } else {
                // Direct upload — upload the whole file.
                guard let url = init.uploadUrl else {
                    self.failJob(job: job, error: "Missing direct upload URL")
                    return
                }
                guard self.uploadDirect(job: job, uploadUrl: url) else {
                    // Retry once with fresh URL.
                    if let freshInit = self.callInit(job: job),
                       let freshUrl = freshInit.uploadUrl,
                       self.uploadDirect(job: job, uploadUrl: freshUrl) {
                        // succeeded on retry
                    } else {
                        self.failJob(job: job, error: "Direct upload failed")
                        return
                    }
                }
            }
            
            // ── Step 4: Callback ──
            if !self.callCallback(job: job, fileUrl: fileUrl) {
                // Bytes are on S3 but callback failed. Save as completed with
                // fileUrl so Dart can retry the idempotent callback.
                self.store.saveResult(UploadResult(
                    jobId: job.jobId, status: "failed", fileUrl: fileUrl,
                    error: "Callback failed"
                ))
                self.store.deletePending(job.jobId)
                self.finishJob(jobId: job.jobId)
                return
            }
            
            self.store.saveResult(UploadResult(
                jobId: job.jobId, status: "completed", fileUrl: fileUrl, error: nil
            ))
            self.store.deletePending(job.jobId)
            self.finishJob(jobId: job.jobId)
            os_log("✅ Job %{public}@ completed", log: self.log, type: .info, job.jobId)
        }
    }
    
    // MARK: - Transfer Helpers (sequential part uploads)
    
    /// Upload the next unfinished part via the background URLSession.
    private func uploadNextPart(job: UploadJobData, init: InitResult) {
        let idx: Int
        _stateLock.lock()
        idx = _currentPartIndex
        _stateLock.unlock()
        
        guard idx < `init`.parts.count else {
            os_log("✅ All %d parts done for %{public}@",
                   log: log, type: .info, `init`.parts.count, job.jobId)
            signalTransferComplete(jobId: job.jobId)
            return
        }
        
        let part = `init`.parts[idx]
        let start = Int64(idx) * Self.partSize
        let isLast = idx == `init`.parts.count - 1
        let end = isLast ? -1 : (start + Self.partSize - 1)
        
        os_log("📤 Uploading part %d/%d for %{public}@ (bytes %lld-%lld)",
               log: log, type: .info, idx + 1, `init`.parts.count, job.jobId, start, end)
        
        // Read the byte range from the file into memory.
        let fileURL = URL(fileURLWithPath: job.filePath)
        guard let fileHandle = try? FileHandle(forReadingFrom: fileURL) else {
            failJob(job: job, error: "Cannot open file: \(job.filePath)")
            return
        }
        defer { try? fileHandle.close() }
        
        try? fileHandle.seek(toOffset: UInt64(start))
        let length: Int
        if end < 0 {
            // Last part: read to end of file.
            let totalSize = (try? fileHandle.seekToEnd()) ?? UInt64(start)
            length = Int(totalSize - UInt64(start))
            try? fileHandle.seek(toOffset: UInt64(start))
        } else {
            length = Int(end - start + 1)
        }
        let data = fileHandle.readData(ofLength: length)
        guard data.count > 0 else {
            failJob(job: job, error: "Empty data for part \(idx + 1)")
            return
        }
        
        // Create the upload task.
        var request = URLRequest(url: URL(string: part.uploadUrl)!)
        request.httpMethod = "PUT"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        
        let task = session.uploadTask(with: request, from: data)
        _taskMapLock.lock()
        _taskMap[task.taskIdentifier] = (job.jobId, idx)
        _taskMapLock.unlock()
        task.resume()
    }
    
    /// Upload an entire file (direct, non-multipart).
    private func uploadDirect(job: UploadJobData, uploadUrl: String) -> Bool {
        let fileURL = URL(fileURLWithPath: job.filePath)
        guard let data = try? Data(contentsOf: fileURL) else { return false }
        
        let semaphore = DispatchSemaphore(value: 0)
        var success = false
        
        var request = URLRequest(url: URL(string: uploadUrl)!)
        request.httpMethod = "PUT"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        
        let task = session.uploadTask(with: request, from: data) { _, response, error in
            success = (response as? HTTPURLResponse)?.statusCode == 200 && error == nil
            semaphore.signal()
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 300)
        return success
    }
    
    // MARK: - API Call Helpers
    
    private func callInit(job: UploadJobData) -> InitResult? {
        let semaphore = DispatchSemaphore(value: 0)
        var result: InitResult?
        
        var request = URLRequest(url: URL(string: job.initUrl)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = job.initBody.data(using: .utf8)
        
        let task = apiSession.dataTask(with: request) { data, response, error in
            if let data = data,
               let body = String(data: data, encoding: .utf8),
               (response as? HTTPURLResponse)?.statusCode == 200 {
                result = InitParser.parse(body, courseAssetKey: job.courseAssetKey)
            } else {
                os_log("❌ Init failed for %{public}@: %{public}@",
                       log: self.log, type: .error, job.jobId,
                       error?.localizedDescription ?? "unknown")
            }
            semaphore.signal()
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 60)
        return result
    }
    
    private func callComplete(job: UploadJobData, init: InitResult) -> String? {
        guard let key = `init`.key, let uploadId = `init`.s3UploadId else { return nil }
        
        let semaphore = DispatchSemaphore(value: 0)
        var fileUrl: String?
        
        let body: [String: Any] = [
            "key": key,
            "uploadId": uploadId,
            "parts": _etags,
        ]
        
        var request = URLRequest(url: URL(string: job.completeUrl)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        let task = apiSession.dataTask(with: request) { data, response, error in
            if let data = data,
               let body = String(data: data, encoding: .utf8) {
                fileUrl = InitParser.extractFileUrl(body)
            }
            semaphore.signal()
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 60)
        return fileUrl
    }
    
    private func callCallback(job: UploadJobData, fileUrl: String) -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        var success = false
        
        let bodyStr = job.callbackBodyTemplate.replacingOccurrences(of: "__FILE_URL__", with: fileUrl)
        
        var request = URLRequest(url: URL(string: job.callbackUrl)!)
        request.httpMethod = job.callbackMethod.uppercased()
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyStr.data(using: .utf8)
        
        let task = apiSession.dataTask(with: request) { _, response, error in
            if let httpResp = response as? HTTPURLResponse {
                success = httpResp.statusCode == 200 || httpResp.statusCode == 409
            }
            semaphore.signal()
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 60)
        return success
    }
    
    private func abortS3(job: UploadJobData, init: InitResult) {
        guard let key = `init`.key, let uploadId = `init`.s3UploadId else { return }
        
        var request = URLRequest(url: URL(string: job.abortUrl)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["key": key, "uploadId": uploadId]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        apiSession.dataTask(with: request).resume()
    }
    
    // MARK: - Transfer Completion Coordination
    
    /// Semaphore that blocks the pipeline thread until all parts are done.
    private let _transferSemaphore = DispatchSemaphore(value: 0)
    private let _transferLock = NSLock()
    private var _transferDone = false
    
    private func waitForTransferCompletion(job: UploadJobData, init: InitResult) {
        _transferLock.lock()
        _transferDone = false
        _transferLock.unlock()
        _ = _transferSemaphore.wait(timeout: .now() + 86400) // 24 hour timeout
    }
    
    private func signalTransferComplete(jobId: String) {
        _transferLock.lock()
        if !_transferDone {
            _transferDone = true
            _transferLock.unlock()
            _transferSemaphore.signal()
        } else {
            _transferLock.unlock()
        }
    }
    
    // MARK: - Job Lifecycle
    
    private func failJob(job: UploadJobData, error: String) {
        os_log("❌ Job %{public}@ failed: %{public}@",
               log: log, type: .error, job.jobId, error)
        store.saveResult(UploadResult(
            jobId: job.jobId, status: "failed", fileUrl: nil, error: error
        ))
        store.deletePending(job.jobId)
        finishJob(jobId: job.jobId)
    }
    
    private func finishJob(jobId: String) {
        _stateLock.lock()
        _activeJobId = nil
        _currentJob = nil
        _currentInit = nil
        _currentPartIndex = 0
        _etags = []
        _stateLock.unlock()
        
        // Process the next job in the queue.
        processNext()
    }
}

// MARK: - URLSessionDelegate

extension BackgroundUploadManager: URLSessionDelegate {
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        os_log("🏁 Background session finished events", log: log, type: .info)
        DispatchQueue.main.async {
            self._completionHandler?()
            self._completionHandler = nil
        }
    }
}

// MARK: - URLSessionTaskDelegate

extension BackgroundUploadManager: URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let httpResp = task.response as? HTTPURLResponse else {
            if let error = error {
                os_log("❌ Task %d failed: %{public}@",
                       log: log, type: .error, task.taskIdentifier, error.localizedDescription)
            }
            return
        }
        
        // Route to the appropriate handler.
        _taskMapLock.lock()
        let info = _taskMap.removeValue(forKey: task.taskIdentifier)
        _taskMapLock.unlock()
        
        guard let (jobId, partNumber) = info else {
            os_log("⚠️ Unknown task %d completed", log: log, type: .debug, task.taskIdentifier)
            return
        }
        
        if let partNum = partNumber {
            // This was a part upload task.
            handlePartCompletion(jobId: jobId, partNumber: partNum, response: httpResp, error: error)
        }
        // Direct upload tasks don't need part-specific handling.
    }
    
    private func handlePartCompletion(
        jobId: String,
        partNumber: Int,
        response: HTTPURLResponse,
        error: Error?
    ) {
        guard error == nil, response.statusCode == 200 else {
            let errMsg = error?.localizedDescription ?? "HTTP \(response.statusCode)"
            os_log("❌ Part %d failed for %{public}@: %{public}@",
                   log: log, type: .error, partNumber + 1, jobId, errMsg)
            
            if response.statusCode == 403 {
                // Presigned URL expired — re-init and retry the remaining parts.
                _stateLock.lock()
                let job = _currentJob
                _stateLock.unlock()
                guard let job = job else { return }
                
                DispatchQueue.global(qos: .background).async { [weak self] in
                    guard let self = self else { return }
                    os_log("🔄 Re-initing after 403 for %{public}@", log: self.log, type: .info, jobId)
                    if let freshInit = self.callInit(job: job) {
                        self._stateLock.lock()
                        self._currentInit = freshInit
                        self._stateLock.unlock()
                        // Retry this part with the fresh URL.
                        self._stateLock.lock()
                        let curInit = self._currentInit
                        self._stateLock.unlock()
                        if let init = curInit {
                            self.uploadNextPart(job: job, init: init)
                        }
                    }
                }
            }
            return
        }
        
        // Extract ETag from response headers.
        let etag = response.allHeaderFields["ETag"] as? String ?? ""
        os_log("✅ Part %d done for %{public}@ — ETag: %{public}@",
               log: log, type: .info, partNumber + 1, jobId, etag)
        
        // Save the ETag.
        _stateLock.lock()
        if partNumber < _etags.count {
            _etags[partNumber] = ["partNumber": partNumber + 1, "eTag": etag]
        }
        _currentPartIndex += 1
        let nextIndex = _currentPartIndex
        let init = _currentInit
        let job = _currentJob
        _stateLock.unlock()
        
        // Schedule the next part.
        if let init = init, let job = job {
            if nextIndex < init.parts.count {
                uploadNextPart(job: job, init: init)
            } else {
                signalTransferComplete(jobId: jobId)
            }
        }
    }
}
