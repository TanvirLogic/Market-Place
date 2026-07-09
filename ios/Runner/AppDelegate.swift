import Flutter
import UIKit
import AVFoundation
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // background_downloader shows upload notifications; set the delegate so they
    // are handled while the app is in the foreground.
    UNUserNotificationCenter.current().delegate = self

    // Register for remote notifications (required for background URLSession events).
    application.registerForRemoteNotifications()

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// Called when the system delivers a background URLSession event and the app
  /// is woken from a suspended/killed state to handle it.
  override func application(
    _ application: UIApplication,
    handleEventsForBackgroundURLSession identifier: String,
    completionHandler: @escaping () -> Void
  ) {
    if identifier == BackgroundUploadManager.sessionIdentifier {
      // Pass the completion handler to the manager so it can call it when
      // `urlSessionDidFinishEvents(forBackgroundURLSession:)` fires.
      BackgroundUploadManager.shared.setCompletionHandler(completionHandler)
    }
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // Video metadata channel — used by VideoMetadataHelper on the Dart side.
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

    // Native upload bridge — identical contract to the Android side.
    // Dart calls the same `eduverse/native_upload` channel; on iOS the native
    // `BackgroundUploadManager` (URLSession daemon) handles the pipeline.
    let uploadChannel = FlutterMethodChannel(
      name: "eduverse/native_upload",
      binaryMessenger: engineBridge.pluginRegistry.messenger()
    )
    uploadChannel.setMethodCallHandler { [weak self] call, result in
      guard self != nil else { return }

      let mgr = BackgroundUploadManager.shared

      switch call.method {
      case "syncTokens":
        // iOS doesn't need token storage (API calls use ephemeral session);
        // future: store in Keychain if auth headers are needed.
        result(true)

      case "enqueueUpload":
        guard let args = call.arguments as? [String: Any],
              let jobDataStr = args["jobData"] as? String,
              let jobData = try? JSONSerialization.jsonObject(with: jobDataStr.data(using: .utf8)!) as? [String: Any]
        else {
          result(FlutterError(code: "INVALID_ARG", message: "jobData required", details: nil))
          return
        }
        mgr.enqueue(jobData: jobData)
        result(true)

      case "getCompletedJobs":
        let jobs = mgr.getCompletedJobs()
        let encoded = jobs.compactMap { d -> String? in
          guard let data = try? JSONSerialization.data(withJSONObject: d) else { return nil }
          return String(data: data, encoding: .utf8)
        }
        result(encoded)

      case "clearResult":
        guard let args = call.arguments as? [String: Any],
              let jobId = args["jobId"] as? String else {
          result(FlutterError(code: "INVALID_ARG", message: "jobId required", details: nil))
          return
        }
        mgr.clearResult(jobId: jobId)
        result(true)

      case "cancelAll":
        mgr.cancelAll()
        result(true)

      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
