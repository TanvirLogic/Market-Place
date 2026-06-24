import Foundation
import UIKit

// MARK: - Queue Item Model

struct QueueItem: Codable {
    let id: Int64
    let filePath: String
    let title: String
    let uploadUrl: String?
    let contentType: String?
    let uploadType: String
    let metadata: String?
    var status: String
    var errorMessage: String?
}

// MARK: - Queue State

struct UploadState: Codable {
    var items: [QueueItem]
    var activeIndex: Int
    var isUploading: Bool
    var lastUpdated: TimeInterval
}

// MARK: - Background Upload Manager

@objc class BackgroundUploadManager: NSObject, URLSessionTaskDelegate, URLSessionDelegate {

    static let shared = BackgroundUploadManager()
    private let sessionIdentifier = "net.eduverseapp.upload.background"
    private var backgroundSession: URLSession!
    private var completionHandler: (() -> Void)?
    private var progressHandlers: [Int64: (Double) -> Void] = [:]

    private var stateFileURL: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsPath.appendingPathComponent("native_uploads.json")
    }

    private override init() {
        super.init()
        let config = URLSessionConfiguration.background(withIdentifier: sessionIdentifier)
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        config.shouldUseExtendedBackgroundIdleMode = true
        config.timeoutIntervalForResource = 86400 // 24 hours
        config.waitsForConnectivity = true
        backgroundSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    // MARK: - Public API

    @objc func setCompletionHandler(_ handler: @escaping () -> Void) {
        completionHandler = handler
    }

    /// Load the current queue state from the shared JSON file
    @objc func loadQueueState() -> UploadState? {
        guard FileManager.default.fileExists(atPath: stateFileURL.path),
              let data = try? Data(contentsOf: stateFileURL) else {
            return nil
        }
        return try? JSONDecoder().decode(UploadState.self, from: data)
    }

    /// Save queue state to the shared JSON file (accessible from Flutter via MethodChannel)
    @objc func saveQueueState(_ state: UploadState) {
        try? stateFileURL.deletingLastPathComponent().createDirectory()
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: stateFileURL, options: .atomic)
    }

    /// Sync queue from Flutter (called via MethodChannel)
    @objc func syncQueueFromFlutter(_ itemsJson: String) {
        guard let data = itemsJson.data(using: .utf8),
              let items = try? JSONDecoder().decode([QueueItem].self, from: data) else { return }
        let state = UploadState(items: items, activeIndex: 0, isUploading: false, lastUpdated: Date().timeIntervalSince1970)
        saveQueueState(state)
    }

    /// Get current queue state as JSON string (for Flutter MethodChannel)
    @objc func getQueueStateJson() -> String {
        guard let state = loadQueueState(),
              let data = try? JSONEncoder().encode(state) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    /// Clear the queue state file
    @objc func clearState() {
        try? FileManager.default.removeItem(at: stateFileURL)
    }

    /// Start uploading the next pending item in the queue sequentially
    @objc func processNextInQueue() {
        guard var state = loadQueueState() else { return }

        // Find the first pending item
        guard let index = state.items.firstIndex(where: { $0.status == "pending" }) else {
            // Queue is fully processed
            clearState()
            return
        }

        let item = state.items[index]
        guard let uploadUrl = item.uploadUrl, let url = URL(string: uploadUrl) else {
            // Skip items without upload URL
            state.items[index].status = "failed"
            state.items[index].errorMessage = "No upload URL"
            saveQueueState(state)
            processNextInQueue()
            return
        }

        let fileURL = URL(fileURLWithPath: item.filePath)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            state.items[index].status = "failed"
            state.items[index].errorMessage = "File not found"
            saveQueueState(state)
            processNextInQueue()
            return
        }

        // Mark as uploading
        state.items[index].status = "uploading"
        state.isUploading = true
        state.activeIndex = index
        saveQueueState(state)

        // Create URLSession upload task (background-compatible)
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(item.contentType ?? "application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue("\(fileURL.fileSize ?? 0)", forHTTPHeaderField: "Content-Length")

        // Use uploadTask with file URL for background support
        let task = backgroundSession.uploadTask(with: request, fromFile: fileURL)
        task.taskDescription = "\(item.id)"

        // Schedule local notification to inform user
        scheduleLocalNotification(title: "Uploading", body: "\(item.title) (\(index + 1)/\(state.items.count))")

        task.resume()
    }

    /// Start processing all pending items in the queue sequentially
    @objc func processQueue() {
        processNextInQueue()
    }

    // MARK: - URLSessionDelegate

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard totalBytesExpectedToSend > 0 else { return }
        let progress = Double(totalBytesSent) / Double(totalBytesExpectedToSend)
        let pct = Int(progress * 100)
        progressHandlers[task.taskIdentifier]?(progress)

        // Update local notification with progress
        updateLocalNotificationProgress(pct: pct)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let description = task.taskDescription, let itemId = Int64(description) else { return }

        defer {
            completionHandler?()
            completionHandler = nil
        }

        guard var state = loadQueueState() else { return }
        guard let index = state.items.firstIndex(where: { $0.id == itemId }) else { return }

        if let error = error {
            state.items[index].status = "failed"
            state.items[index].errorMessage = error.localizedDescription
            saveQueueState(state)
            scheduleLocalNotification(title: "Upload Failed", body: state.items[index].title)
        } else {
            let statusCode = (task.response as? HTTPURLResponse)?.statusCode ?? 0
            if (200...299).contains(statusCode) {
                state.items[index].status = "completed"
                state.isUploading = false
                saveQueueState(state)
                scheduleLocalNotification(title: "Upload Complete", body: state.items[index].title)
            } else {
                state.items[index].status = "failed"
                state.items[index].errorMessage = "HTTP \(statusCode)"
                saveQueueState(state)
                scheduleLocalNotification(title: "Upload Failed", body: "\(state.items[index].title) (HTTP \(statusCode))")
            }
        }

        // Process the next item in the queue
        processNextInQueue()
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async {
            self.completionHandler?()
            self.completionHandler = nil
        }
    }

    // MARK: - Notifications

    private func scheduleLocalNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = nil

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func updateLocalNotificationProgress(pct: Int) {
        let content = UNMutableNotificationContent()
        content.title = "Uploading..."
        content.body = "\(pct)%"
        content.sound = nil

        let request = UNNotificationRequest(
            identifier: "eduverse_upload_progress",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}

// MARK: - File Size Helper

extension URL {
    var fileSize: Int64? {
        let attrs = try? resourceValues(forKeys: [.fileSizeKey])
        return attrs?.fileSize.map(Int64.init)
    }
}
