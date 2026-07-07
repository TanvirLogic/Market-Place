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
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
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
  }
}
