import Foundation
import UIKit

struct QueueItem: Codable {
    let id: Int64
    let filePath: String
    let title: String
    let uploadUrl: String?
    let fileUrl: String?
    let contentType: String?
    let uploadType: String
    let metadata: String?
    let callbackUrl: String?
    let callbackBody: String?
    let authToken: String?
    var status: String
    var errorMessage: String?
    var progress: Double?

    enum CodingKeys: String, CodingKey {
        case id, filePath, title, uploadUrl, fileUrl, contentType, uploadType
        case metadata, callbackUrl, callbackBody, authToken
        case status, errorMessage, progress
    }
}

struct UploadState: Codable {
    var items: [QueueItem]
    var activeIndex: Int
    var isUploading: Bool
    var lastUpdated: TimeInterval
}

@objc class BackgroundUploadManager: NSObject, URLSessionTaskDelegate, URLSessionDelegate {

    static let shared = BackgroundUploadManager()
    private let sessionIdentifier = "net.eduverseapp.upload.background"
    private var backgroundSession: URLSession!
    private var completionHandler: (() -> Void)?

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
        config.timeoutIntervalForResource = 86400
        config.waitsForConnectivity = true
        backgroundSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    @objc func setCompletionHandler(_ handler: @escaping () -> Void) {
        completionHandler = handler
    }

    @objc func loadQueueState() -> UploadState? {
        guard FileManager.default.fileExists(atPath: stateFileURL.path),
              let data = try? Data(contentsOf: stateFileURL) else {
            return nil
        }
        return try? JSONDecoder().decode(UploadState.self, from: data)
    }

    @objc func saveQueueState(_ state: UploadState) {
        let dir = stateFileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: stateFileURL, options: .atomic)
    }

    @objc func syncQueueFromFlutter(_ itemsJson: String) {
        guard let data = itemsJson.data(using: .utf8),
              let newItems = try? JSONDecoder().decode([QueueItem].self, from: data) else { return }

        // Preserve any in-flight (uploading) items from the existing state.
        // iOS background URLSession tasks survive app kills — their completion
        // callbacks will fire even if the state file is overwritten. Keeping
        // 'uploading' items ensures didCompleteWithError can find them.
        var mergedItems = newItems
        if let existingState = loadQueueState() {
            for existingItem in existingState.items {
                if existingItem.status == "uploading" || existingItem.status == "pending" {
                    if !mergedItems.contains(where: { $0.id == existingItem.id }) {
                        mergedItems.append(existingItem)
                    }
                }
            }
        }
        // Sort by ID to maintain FIFO order
        mergedItems.sort { $0.id < $1.id }

        let state = UploadState(items: mergedItems, activeIndex: 0, isUploading: false, lastUpdated: Date().timeIntervalSince1970)
        saveQueueState(state)
    }

    @objc func getQueueItemsJson() -> String {
        guard let state = loadQueueState(),
              let data = try? JSONEncoder().encode(state.items) else { return "[]" }
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    @objc func getNativeQueueItemsJson() -> String {
        guard let state = loadQueueState() else {
            return "{\"items\":[],\"isUploading\":false}"
        }
        let dict: [String: Any] = [
            "items": state.items.map { item -> [String: Any] in
                var d: [String: Any] = [
                    "id": item.id,
                    "status": item.status,
                    "progress": Int((item.progress ?? 0) * 100),
                ]
                if let fileUrl = item.fileUrl {
                    d["fileUrl"] = fileUrl
                }
                return d
            },
            "isUploading": state.isUploading,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else {
            return "{\"items\":[],\"isUploading\":false}"
        }
        return String(data: data, encoding: .utf8) ?? "{\"items\":[],\"isUploading\":false}"
    }

    @objc func getQueueStateJson() -> String {
        guard let state = loadQueueState(),
              let data = try? JSONEncoder().encode(state) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    @objc func clearState() {
        try? FileManager.default.removeItem(at: stateFileURL)
    }

    @objc func processNextInQueue() {
        guard var state = loadQueueState() else { return }
        guard let index = state.items.firstIndex(where: { $0.status == "pending" }) else {
            clearState()
            return
        }

        guard let uploadUrl = state.items[index].uploadUrl,
              let url = URL(string: uploadUrl) else {
            state.items[index].status = "failed"
            state.items[index].errorMessage = "No upload URL"
            saveQueueState(state)
            processNextInQueue()
            return
        }

        let fileURL = URL(fileURLWithPath: state.items[index].filePath)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            state.items[index].status = "failed"
            state.items[index].errorMessage = "File not found"
            saveQueueState(state)
            processNextInQueue()
            return
        }

        state.items[index].status = "uploading"
        state.isUploading = true
        state.activeIndex = index
        saveQueueState(state)

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(state.items[index].contentType ?? "application/octet-stream", forHTTPHeaderField: "Content-Type")
        if let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
           let fileSize = attrs[.size] as? Int64 {
            request.setValue("\(fileSize)", forHTTPHeaderField: "Content-Length")
        }

        let task = backgroundSession.uploadTask(with: request, fromFile: fileURL)
        let metaParts = [
            "\(state.items[index].id)",
            state.items[index].callbackUrl ?? "",
            state.items[index].callbackBody ?? "",
            state.items[index].authToken ?? "",
            state.items[index].fileUrl ?? "",
        ]
        task.taskDescription = metaParts.joined(separator: "|||")

        let total = state.items.count
        scheduleLocalNotification(title: "Uploading", body: "\(state.items[index].title) (\(index + 1)/\(total))")
        task.resume()
    }

    @objc func processQueue() {
        processNextInQueue()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard totalBytesExpectedToSend > 0 else { return }
        let progress = Double(totalBytesSent) / Double(totalBytesExpectedToSend)
        let pct = Int(progress * 100)

        let itemId = resolveItemId(from: task.taskDescription)
        guard let resolvedId = itemId else {
            // Try to find uploading item from state file (app was killed and restarted)
            if let state = loadQueueState(),
               let uploading = state.items.first(where: { $0.status == "uploading" }) {
                var updated = state
                if let idx = updated.items.firstIndex(where: { $0.id == uploading.id }) {
                    updated.items[idx].progress = progress
                    saveQueueState(updated)
                }
            }
            return
        }
        guard var state = loadQueueState(),
              let idx = state.items.firstIndex(where: { $0.id == resolvedId }) else { return }
        state.items[idx].progress = progress
        saveQueueState(state)

        updateLocalNotificationProgress(pct: pct)
    }

    private func resolveItemId(from taskDescription: String?) -> Int64? {
        guard let description = taskDescription else { return nil }
        let parts = description.components(separatedBy: "|||")
        guard parts.count >= 1, let id = Int64(parts[0]), id > 0 else { return nil }
        return id
    }

    private func resolveTaskParts(from taskDescription: String?) -> [String] {
        guard let description = taskDescription else { return [] }
        return description.components(separatedBy: "|||")
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let parts = resolveTaskParts(from: task.taskDescription)

        // Resolve itemId from taskDescription or state file (survives app kill)
        var resolvedItemId: Int64?
        if let id = resolveItemId(from: task.taskDescription) {
            resolvedItemId = id
        } else if let state = loadQueueState(),
                  let uploading = state.items.first(where: { $0.status == "uploading" }) {
            resolvedItemId = uploading.id
        }

        guard let itemId = resolvedItemId else {
            defer {
                DispatchQueue.main.async {
                    self.completionHandler?()
                    self.completionHandler = nil
                }
            }
            return
        }

        defer {
            DispatchQueue.main.async {
                self.completionHandler?()
                self.completionHandler = nil
            }
        }

        guard var state = loadQueueState() else { return }
        guard let index = state.items.firstIndex(where: { $0.id == itemId }) else {
            return
        }

        if let error = error {
            state.items[index].status = "failed"
            state.items[index].errorMessage = error.localizedDescription
            saveQueueState(state)
            scheduleLocalNotification(title: "Upload Failed", body: state.items[index].title)
            processNextInQueue()
            return
        }

        let statusCode = (task.response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(statusCode) else {
            state.items[index].status = "failed"
            state.items[index].errorMessage = "HTTP \(statusCode)"
            saveQueueState(state)
            scheduleLocalNotification(title: "Upload Failed", body: "\(state.items[index].title) (HTTP \(statusCode))")
            processNextInQueue()
            return
        }

        let callbackUrl = parts.count >= 2 ? parts[1] : ""
        let callbackBody = parts.count >= 3 ? parts[2] : ""
        let authToken = parts.count >= 4 ? parts[3] : ""
        let fileUrl = parts.count >= 5 ? parts[4] : ""

        if !callbackUrl.isEmpty, !callbackBody.isEmpty {
            let updatedBody = injectFileUrl(callbackBody, fileUrl: fileUrl)

            performServerCallback(
                url: callbackUrl,
                body: updatedBody,
                authToken: authToken,
                completion: { success in
                    var updatedState = self.loadQueueState() ?? state
                    if let idx = updatedState.items.firstIndex(where: { $0.id == itemId }) {
                        if success {
                            updatedState.items[idx].status = "completed"
                        } else {
                            updatedState.items[idx].status = "failed"
                            updatedState.items[idx].errorMessage = "Server callback failed"
                        }
                        updatedState.isUploading = false
                        self.saveQueueState(updatedState)

                        let title = updatedState.items[idx].title
                        if success {
                            self.scheduleLocalNotification(title: "Upload Complete", body: title)
                        } else {
                            self.scheduleLocalNotification(title: "Upload Failed", body: "\(title) - callback error")
                        }
                    }
                    self.processNextInQueue()
                }
            )
        } else {
            state.items[index].status = "completed"
            state.isUploading = false
            saveQueueState(state)
            scheduleLocalNotification(title: "Upload Complete", body: state.items[index].title)
            processNextInQueue()
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async {
            self.completionHandler?()
            self.completionHandler = nil
        }
    }

    private func injectFileUrl(_ body: String, fileUrl: String) -> String {
        guard !fileUrl.isEmpty else { return body }
        guard let data = body.data(using: .utf8),
              var dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return body
        }
        if dict["videoUrl"] as? String == nil && dict["fileUrl"] as? String == nil {
            dict["fileUrl"] = fileUrl
            if let updated = try? JSONSerialization.data(withJSONObject: dict) {
                return String(data: updated, encoding: .utf8) ?? body
            }
        }
        return body
    }

    private func performServerCallback(url callbackUrl: String, body callbackBody: String, authToken: String, completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: callbackUrl) else {
            completion(false)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !authToken.isEmpty {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = callbackBody.data(using: .utf8)
        request.timeoutInterval = 60

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Server callback failed: \(error.localizedDescription)")
                completion(false)
                return
            }
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                print("Server callback failed with HTTP \(statusCode)")
                if let data = data, let body = String(data: data, encoding: .utf8) {
                    print("Response: \(body.prefix(500))")
                }
                completion(false)
                return
            }
            completion(true)
        }
        task.resume()
    }

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

extension URL {
    var fileSize: Int64? {
        let attrs = try? resourceValues(forKeys: [.fileSizeKey])
        return attrs?.fileSize.map(Int64.init)
    }
}
