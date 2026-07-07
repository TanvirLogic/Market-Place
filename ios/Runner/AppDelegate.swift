import Flutter
import UIKit
import AVFoundation
import BackgroundTasks
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let uploadBridgeChannel = "eduverse/upload_bridge"
  private let uploadEngineChannel = "eduverse/upload_engine"
  private let uploadProgressEvent = "eduverse/upload_progress"

  // Maps background session identifiers → completion handlers
  private var sessionCompletionHandlers: [String: () -> Void] = [:]
  // Maps taskId → reference to result closure so completed upload can report back
  private var pendingDirectUploadResults: [Int: FlutterResult] = [:]
  // Maps taskId → pending FlutterResult for scheduleCallback / scheduleCompleteAndCallback
  private var pendingCallbackResults: [Int: FlutterResult] = [:]
  // Maps taskId → callback body/url for background callback execution
  private var pendingCallbackRequests: [Int: (url: String, body: String, authToken: String, idempotencyKey: String?)] = [:]
  // Multipart part trackers keyed by taskId
  private var multipartTrackers: [Int: PartUploadTracker] = [:]

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Register background task
    BGTaskScheduler.shared.register(
      forTaskWithIdentifier: "net.eduverseapp.upload.refresh",
      using: nil
    ) { task in
      self.handleAppRefresh(task as! BGAppRefreshTask)
    }

    // Request notification permission
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ application: UIApplication,
    handleEventsForBackgroundURLSession identifier: String,
    completionHandler: @escaping () -> Void
  ) {
    sessionCompletionHandlers[identifier] = completionHandler

    if identifier == "net.eduverseapp.upload.background" {
      // Legacy BackgroundUploadManager session
      BackgroundUploadManager.shared.setCompletionHandler(completionHandler)
    } else if identifier.hasPrefix("eduverse_direct_") {
      // New engine direct upload session — create lightweight handler
      let config = URLSessionConfiguration.background(withIdentifier: identifier)
      config.isDiscretionary = false
      config.sessionSendsLaunchEvents = true
      config.shouldUseExtendedBackgroundIdleMode = true
      config.timeoutIntervalForResource = 86400
      config.waitsForConnectivity = true
      let delegate = DirectUploadSessionDelegate(
        identifier: identifier,
        onCompletion: { [weak self] result in
          if let handler = self?.sessionCompletionHandlers[identifier] {
            handler()
            self?.sessionCompletionHandlers.removeValue(forKey: identifier)
          }
        }
      )
      _ = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // Video metadata channel (existing)
    let videoChannel = FlutterMethodChannel(
      name: "eduverse/video_metadata",
      binaryMessenger: engineBridge.pluginRegistry.messenger()
    )
    videoChannel.setMethodCallHandler { call, result in
      if call.method == "getVideoInfo" {
        guard let args = call.arguments as? [String: Any],
              let path = args["path"] as? String else {
          result(FlutterError(code: "INVALID_ARG", message: "path required", details: nil))
          return
        }

        let url: URL
        if path.hasPrefix("/") {
          url = URL(fileURLWithPath: path)
        } else {
          url = URL(string: path) ?? URL(fileURLWithPath: path)
        }

        let asset = AVAsset(url: url)
        let duration = CMTimeGetSeconds(asset.duration)
        let durationSec = duration.isNaN ? 1 : Int(duration)

        var fileSize: Int64 = 0
        if let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey]) {
          fileSize = Int64(resourceValues.fileSize ?? 0)
        }

        result([
          "duration": durationSec,
          "fileSize": fileSize
        ])
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    // Upload bridge channel (existing — for BackgroundUploadManager)
    let uploadBridge = FlutterMethodChannel(
      name: uploadBridgeChannel,
      binaryMessenger: engineBridge.pluginRegistry.messenger()
    )
    uploadBridge.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "syncQueueToNative":
        if let itemsJson = call.arguments as? String {
          BackgroundUploadManager.shared.syncQueueFromFlutter(itemsJson)
          result(true)
        } else {
          result(FlutterError(code: "INVALID_ARG", message: "itemsJson required", details: nil))
        }

      case "startNativeUpload":
        guard let args = call.arguments as? [String: Any],
              let filePath = args["filePath"] as? String,
              let uploadUrl = args["uploadUrl"] as? String else {
          result(FlutterError(code: "INVALID_ARG", message: "filePath and uploadUrl required", details: nil))
          return
        }
        let title = args["title"] as? String ?? "Upload"
        let contentType = args["contentType"] as? String
        let uploadType = args["uploadType"] as? String ?? "video_post"
        let metadata = args["metadata"] as? String
        let fileUrl = args["fileUrl"] as? String
        let authToken = args["authToken"] as? String
        let callbackUrl = args["callbackUrl"] as? String
        let callbackBody = args["callbackBody"] as? String
        let itemId = (args["itemId"] as? NSNumber)?.int64Value ?? -1

        var state = BackgroundUploadManager.shared.loadQueueState() ?? UploadState(items: [], activeIndex: 0, isUploading: false, lastUpdated: Date().timeIntervalSince1970)
        let newItem = QueueItem(
          id: itemId, filePath: filePath, title: title,
          uploadUrl: uploadUrl, fileUrl: fileUrl,
          contentType: contentType, uploadType: uploadType,
          metadata: metadata,
          callbackUrl: callbackUrl, callbackBody: callbackBody, authToken: authToken,
          status: "pending", errorMessage: nil, progress: 0
        )
        state.items.removeAll { $0.id == itemId }
        state.items.append(newItem)
        BackgroundUploadManager.shared.saveQueueState(state)
        result(true)

      case "startQueueProcessing":
        BackgroundUploadManager.shared.processQueue()
        result(true)

      case "getNativePendingUploads":
        let json = BackgroundUploadManager.shared.getQueueItemsJson()
        result(json)

      case "getNativeQueueItems":
        let json = BackgroundUploadManager.shared.getNativeQueueItemsJson()
        result(json)

      case "startServiceForUpload":
        BackgroundUploadManager.shared.processQueue()
        result(true)

      case "getNativeQueueStatus":
        let state = BackgroundUploadManager.shared.loadQueueState()
        if let s = state {
          let pending = s.items.filter { $0.status == "pending" }.count
          let uploading = s.items.filter { $0.status == "uploading" }.count
          let completed = s.items.filter { $0.status == "completed" }.count
          let failed = s.items.filter { $0.status == "failed" }.count
          let dict: [String: Any] = [
            "totalItems": s.items.count,
            "pending": pending,
            "uploading": uploading,
            "completed": completed,
            "failed": failed,
            "isUploading": s.isUploading,
          ]
          if let data = try? JSONSerialization.data(withJSONObject: dict),
             let json = String(data: data, encoding: .utf8) {
            result(json)
          } else {
            result("{}")
          }
        } else {
          result("{\"totalItems\":0,\"pending\":0,\"uploading\":0,\"completed\":0,\"failed\":0,\"isUploading\":false}")
        }

      case "clearNativeState":
        BackgroundUploadManager.shared.clearState()
        result(true)

      case "processPendingQueue":
        BackgroundUploadManager.shared.processQueue()
        result(true)

      case "cancelNativeUpload":
        BackgroundUploadManager.shared.clearState()
        result(true)

      case "openNotificationSettings":
        if let url = URL(string: UIApplication.openSettingsURLString) {
          DispatchQueue.main.async {
            UIApplication.shared.open(url)
          }
        }
        result(true)

      case "scheduleWorkManager":
        self?.scheduleBackgroundUploadTask()
        result(true)

      default:
        result(FlutterMethodNotImplemented)
      }
    }

    // Upload engine channel — survives app kill via Background URLSession
    let uploadEngine = FlutterMethodChannel(
      name: uploadEngineChannel,
      binaryMessenger: engineBridge.pluginRegistry.messenger()
    )
    uploadEngine.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      switch call.method {
      case "directUpload":
        guard let args = call.arguments as? [String: Any],
              let taskId = args["taskId"] as? Int,
              let filePath = args["filePath"] as? String,
              let uploadUrl = args["uploadUrl"] as? String else {
          result(FlutterError(code: "INVALID_ARG", message: "taskId, filePath, uploadUrl required", details: nil))
          return
        }

        let fileURL = URL(fileURLWithPath: filePath)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
          result(["success": false, "errorMessage": "File not found"])
          return
        }

        // Store result so background session can report back
        pendingDirectUploadResults[taskId] = result

        // Create background URLSession — survives app kill
        let sessionId = "eduverse_direct_\(taskId)"
        let config = URLSessionConfiguration.background(withIdentifier: sessionId)
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        config.shouldUseExtendedBackgroundIdleMode = true
        config.timeoutIntervalForResource = 86400
        config.waitsForConnectivity = true

        var request = URLRequest(url: URL(string: uploadUrl)!)
        request.httpMethod = "PUT"
        if let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
           let fileSize = attrs[.size] as? Int64 {
          request.setValue("\(fileSize)", forHTTPHeaderField: "Content-Length")
        }

        let delegate = DirectUploadSessionDelegate(
          identifier: sessionId,
          taskId: taskId,
          onCompletion: { [weak self] resultDict in
            if let storedResult = self?.pendingDirectUploadResults.removeValue(forKey: taskId) {
              storedResult(resultDict)
            }
          },
          onBackgroundEventsFinished: { [weak self] identifier in
            if let handler = self?.sessionCompletionHandlers.removeValue(forKey: identifier) {
              handler()
            }
          }
        )
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        let uploadTask = session.uploadTask(with: request, fromFile: fileURL)
        uploadTask.taskDescription = "eduverse_engine_\(taskId)"
        uploadTask.resume()

      case "uploadParts":
        guard let args = call.arguments as? [String: Any],
              let taskId = args["taskId"] as? Int,
              let filePath = args["filePath"] as? String,
              let parts = args["parts"] as? [[String: Any]],
              let partSize = args["partSize"] as? Int else {
          result(FlutterError(code: "INVALID_ARG", message: "taskId, filePath, parts, partSize required", details: nil))
          return
        }

        let fileURL = URL(fileURLWithPath: filePath)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
          result([])
          return
        }

        // Use background URLSession for each part (survives app kill)
        let tracker = PartUploadTracker(
          taskId: taskId,
          totalParts: parts.count,
          onAllDone: { resultsArray in
            // FlutterResult may already be gone — use pendingDirectUploadResults
            if let storedResult = self.pendingDirectUploadResults.removeValue(forKey: taskId) {
              storedResult(resultsArray)
            }
          }
        )
        self.multipartTrackers[taskId] = tracker

        // Store FlutterResult so background delegate can reply
        pendingDirectUploadResults[taskId] = result

        // Launch each part as a background upload task
        for partArg in parts {
          guard let partNumber = partArg["partNumber"] as? Int,
                let uploadUrl = partArg["uploadUrl"] as? String else {
            tracker.recordFailure(partNumber: partArg["partNumber"] as? Int ?? -1, error: "Invalid part args")
            continue
          }
          let startByte = Int64(partNumber - 1) * Int64(partSize)
          let endByte = min(startByte + Int64(partSize), Int64(
            (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int64) ?? 0
          ))
          let partLength = endByte - startByte

          let sessionId = "eduverse_part_\(taskId)_\(partNumber)"
          let config = URLSessionConfiguration.background(withIdentifier: sessionId)
          config.isDiscretionary = false
          config.sessionSendsLaunchEvents = true
          config.shouldUseExtendedBackgroundIdleMode = true
          config.timeoutIntervalForResource = 3600
          config.waitsForConnectivity = true

          var request = URLRequest(url: URL(string: uploadUrl)!)
          request.httpMethod = "PUT"
          request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
          request.setValue("\(partLength)", forHTTPHeaderField: "Content-Length")

          let delegate = PartUploadDelegate(
            sessionId: sessionId,
            taskId: taskId,
            partNumber: partNumber,
            onCompletion: { [weak self] resultDict in
              tracker.recordCompletion(partNumber: partNumber, result: resultDict)
            },
            onBackgroundEventsFinished: { [weak self] sessionId in
              if let handler = self?.sessionCompletionHandlers.removeValue(forKey: sessionId) {
                handler()
              }
            }
          )
          let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
          let uploadTask = session.uploadTask(with: request, fromFile: fileURL)
          uploadTask.taskDescription = "eduverse_part_\(taskId)_\(partNumber)"
          uploadTask.resume()
        }

      case "scheduleCallback":
        guard let args = call.arguments as? [String: Any],
              let callbackUrl = args["callbackUrl"] as? String,
              let callbackBody = args["callbackBody"] as? String,
              let authToken = args["authToken"] as? String else {
          result(FlutterError(code: "INVALID_ARG", message: "callbackUrl, callbackBody, authToken required", details: nil))
          return
        }
        let taskId = (args["taskId"] as? NSNumber)?.intValue ?? Int(Date().timeIntervalSince1970)
        let idempotencyKey = args["idempotencyKey"] as? String

        // Run the callback via a background URLSession task
        Task {
          let success = await self.performCallbackInBackground(
            callbackUrl: callbackUrl,
            callbackBody: callbackBody,
            authToken: authToken,
            idempotencyKey: idempotencyKey
          )
          await MainActor.run {
            result(["success": success, "errorMessage": success ? nil : "Callback failed"])
          }
        }

      case "scheduleCompleteAndCallback":
        guard let args = call.arguments as? [String: Any],
              let completeUrl = args["completeUrl"] as? String,
              let completeBody = args["completeBody"] as? String,
              let callbackUrl = args["callbackUrl"] as? String,
              let callbackBody = args["callbackBody"] as? String,
              let authToken = args["authToken"] as? String else {
          result(FlutterError(code: "INVALID_ARG", message: "completeUrl, completeBody, callbackUrl, callbackBody, authToken required", details: nil))
          return
        }
        let idempotencyKey = args["idempotencyKey"] as? String
        let taskId = (args["taskId"] as? NSNumber)?.intValue ?? Int(Date().timeIntervalSince1970)

        // Chain: POST complete-multipart → then POST callback
        Task {
          // Step 1: Complete multipart
          let fileUrl = await self.performCompleteMultipartInBackground(
            completeUrl: completeUrl,
            completeBody: completeBody,
            authToken: authToken
          )

          guard let fileUrl = fileUrl, !fileUrl.isEmpty else {
            await MainActor.run {
              result(["success": false, "fileUrl": "", "errorMessage": "Complete multipart failed"])
            }
            return
          }

          // Step 2: Send callback with fileUrl injected
          var callbackBodyMap: [String: Any] = [:]
          if let data = callbackBody.data(using: .utf8),
             let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            callbackBodyMap = json
          }
          callbackBodyMap["videoUrl"] = fileUrl
          let updatedBody = (try? JSONSerialization.data(withJSONObject: callbackBodyMap)).flatMap { String(data: $0, encoding: .utf8) } ?? callbackBody

          let cbSuccess = await self.performCallbackInBackground(
            callbackUrl: callbackUrl,
            callbackBody: updatedBody,
            authToken: authToken,
            idempotencyKey: idempotencyKey
          )

          await MainActor.run {
            result([
              "success": cbSuccess,
              "fileUrl": fileUrl,
              "errorMessage": cbSuccess ? nil : "Callback failed",
            ])
          }
        }

      case "getUploadStatus":
        guard let taskId = call.arguments as? Int else {
          result(FlutterError(code: "INVALID_ARG", message: "taskId required", details: nil))
          return
        }
        let sessionId = "eduverse_direct_\(taskId)"
        // Check if a background session completed by looking for its state file
        let statusFile = self.uploadStatusFileURL(for: taskId)
        if FileManager.default.fileExists(atPath: statusFile.path),
           let data = try? Data(contentsOf: statusFile),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
          result(json)
        } else {
          result(["completed": [], "failed": [], "allDone": false, "totalParts": 0])
        }

      case "cancelTask":
        if let taskId = call.arguments as? Int {
          let sessionId = "eduverse_direct_\(taskId)"
          URLSession.shared.getAllTasks { tasks in
            for task in tasks where task.taskDescription == "eduverse_engine_\(taskId)" {
              task.cancel()
            }
          }
          // Also cancel any background sessions
          let config = URLSessionConfiguration.background(withIdentifier: sessionId)
          config.isDiscretionary = false
          config.sessionSendsLaunchEvents = false
          let invalidSession = URLSession(configuration: config, delegate: nil, delegateQueue: nil)
          invalidSession.invalidateAndCancel()
          // Clean up status file
          try? FileManager.default.removeItem(at: self.uploadStatusFileURL(for: taskId))
        }
        result(true)

      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  // ── Helper: status file for tracking background upload completion ──

  private func uploadStatusFileURL(for taskId: Int) -> URL {
    let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
    return caches.appendingPathComponent("eduverse_upload_\(taskId).json")
  }

  // ── Multipart parts — foreground URLSession (parts 5-10MB, fast) ──

  /// POST the complete-multipart endpoint via a background URLSession data task.
  /// Returns the fileUrl on success, or nil on failure.
  private func performCompleteMultipartInBackground(
    completeUrl: String, completeBody: String, authToken: String
  ) async -> String? {
    var request = URLRequest(url: URL(string: completeUrl)!)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
    request.httpBody = completeBody.data(using: .utf8)

    do {
      let (data, response) = try await URLSession.shared.data(for: request)
      guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
        return nil
      }
      let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
      if let dataDict = json?["data"] as? [String: Any] {
        return dataDict["fileUrl"] as? String
      }
      return json?["fileUrl"] as? String
    } catch {
      return nil
    }
  }

  /// POST the server callback via a background URLSession data task.
  /// Returns true on 2xx or 409 (idempotent).
  private func performCallbackInBackground(
    callbackUrl: String, callbackBody: String, authToken: String,
    idempotencyKey: String? = nil
  ) async -> Bool {
    var request = URLRequest(url: URL(string: callbackUrl)!)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
    request.httpBody = callbackBody.data(using: .utf8)
    if let key = idempotencyKey {
      request.setValue(key, forHTTPHeaderField: "Idempotency-Key")
    }

    for attempt in 0..<3 {
      do {
        let (_, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse {
          if (200...299).contains(httpResponse.statusCode) || httpResponse.statusCode == 409 {
            return true
          }
        }
      } catch {}
      if attempt < 2 {
        try? await Task.sleep(nanoseconds: UInt64(2_000_000_000 * (attempt + 1)))
      }
    }
    return false
  }

  private func scheduleBackgroundUploadTask() {
    let request = BGAppRefreshTaskRequest(identifier: "net.eduverseapp.upload.refresh")
    request.earliestBeginDate = Date(timeIntervalSinceNow: 3 * 60) // 3 minutes
    do {
      try BGTaskScheduler.shared.submit(request)
    } catch {
      print("Failed to schedule BGTask: \(error)")
    }
  }

  private func handleAppRefresh(_ task: BGAppRefreshTask) {
    scheduleBackgroundUploadTask()

    let queue = OperationQueue()
    queue.maxConcurrentOperationCount = 1

    task.expirationHandler = {
      queue.cancelAllOperations()
    }

    // Check for pending uploads in shared state file
    let state = BackgroundUploadManager.shared.loadQueueState()
    if let s = state, !s.items.isEmpty {
      let pendingCount = s.items.filter { $0.status == "pending" }.count
      if pendingCount > 0 {
        BackgroundUploadManager.shared.processQueue()
      }
      task.setTaskCompleted(success: true)
    } else {
      BackgroundUploadManager.shared.clearState()
      task.setTaskCompleted(success: true)
    }
  }
}

// ── Background URLSession delegate for new engine directUpload ──

private class DirectUploadSessionDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate {
  let identifier: String
  let taskId: Int
  let onCompletion: ([String: Any]) -> Void
  let onBackgroundEventsFinished: (String) -> Void

  init(
    identifier: String,
    taskId: Int = 0,
    onCompletion: @escaping ([String: Any]) -> Void = { _ in },
    onBackgroundEventsFinished: @escaping (String) -> Void = { _ in }
  ) {
    self.identifier = identifier
    self.taskId = taskId
    self.onCompletion = onCompletion
    self.onBackgroundEventsFinished = onBackgroundEventsFinished
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    var result: [String: Any] = ["success": false]

    if let error = error {
      result["errorMessage"] = error.localizedDescription
    } else if let response = task.response as? HTTPURLResponse {
      let eTag = (response.allHeaderFields["ETag"] as? String ?? response.allHeaderFields["Etag"] as? String)?
        .replacingOccurrences(of: "\"", with: "")
      result["success"] = (200...299).contains(response.statusCode)
      if eTag != nil { result["eTag"] = eTag }
      if response.statusCode != 200 {
        result["errorMessage"] = "HTTP \(response.statusCode)"
      }
    }

    // Write status file for getUploadStatus to read after app relaunch
    if let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
      let statusFile = caches.appendingPathComponent("eduverse_upload_\(taskId).json")
      if let data = try? JSONSerialization.data(withJSONObject: result) {
        try? data.write(to: statusFile)
      }
    }

    onCompletion(result)
  }

  func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
    onBackgroundEventsFinished(identifier)
  }
}

// ── Part upload tracker — accumulates results across background sessions ──

private class PartUploadTracker {
  let taskId: Int
  let totalParts: Int
  private let onAllDone: ([[String: Any]]) -> Void
  private var results: [Int: [String: Any]] = [:]
  private let lock = NSLock()

  init(taskId: Int, totalParts: Int, onAllDone: @escaping ([[String: Any]]) -> Void) {
    self.taskId = taskId
    self.totalParts = totalParts
    self.onAllDone = onAllDone
  }

  func recordCompletion(partNumber: Int, result: [String: Any]) {
    lock.lock()
    results[partNumber] = result
    let complete = results.count
    lock.unlock()

    if complete >= totalParts {
      let sorted = lock.synchronized {
        results.sorted { $0.key < $1.key }.map { $0.value }
      }
      onAllDone(sorted)
    }
  }

  func recordFailure(partNumber: Int, error: String) {
    recordCompletion(partNumber: partNumber, result: [
      "partNumber": partNumber, "success": false, "errorMessage": error
    ])
  }
}

private extension NSLock {
  func synchronized<T>(_ block: () -> T) -> T {
    lock(); defer { unlock() }; return block()
  }
}

// ── Background URLSession delegate for individual part uploads ──

private class PartUploadDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate {
  let sessionId: String
  let taskId: Int
  let partNumber: Int
  let onCompletion: ([String: Any]) -> Void
  let onBackgroundEventsFinished: (String) -> Void

  init(
    sessionId: String,
    taskId: Int,
    partNumber: Int,
    onCompletion: @escaping ([String: Any]) -> Void,
    onBackgroundEventsFinished: @escaping (String) -> Void
  ) {
    self.sessionId = sessionId
    self.taskId = taskId
    self.partNumber = partNumber
    self.onCompletion = onCompletion
    self.onBackgroundEventsFinished = onBackgroundEventsFinished
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    var result: [String: Any] = [
      "partNumber": partNumber,
      "success": false,
    ]

    if let error = error {
      result["errorMessage"] = error.localizedDescription
    } else if let response = task.response as? HTTPURLResponse {
      let eTag = (response.allHeaderFields["ETag"] as? String ?? response.allHeaderFields["Etag"] as? String)?
        .replacingOccurrences(of: "\"", with: "")
      result["success"] = (200...299).contains(response.statusCode)
      if eTag != nil { result["eTag"] = eTag }
      result["isUrlExpired"] = response.statusCode == 403
      if response.statusCode != 200 {
        result["errorMessage"] = "HTTP \(response.statusCode)"
      }
    }

    onCompletion(result)
  }

  func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
    onBackgroundEventsFinished(sessionId)
  }
}
