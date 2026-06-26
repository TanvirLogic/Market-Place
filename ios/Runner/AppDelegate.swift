import Flutter
import UIKit
import AVFoundation
import BackgroundTasks
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let uploadChannel = "eduverse/upload_bridge"
  private var backgroundSessionCompletionHandler: (() -> Void)?

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
    // Store completion handler for URLSession delegate callback
    backgroundSessionCompletionHandler = completionHandler
    BackgroundUploadManager.shared.setCompletionHandler(completionHandler)
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

    // Upload bridge channel (enhanced with URLSession background transfers)
    let uploadBridge = FlutterMethodChannel(
      name: uploadChannel,
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
