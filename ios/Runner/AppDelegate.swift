import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    // Manual registration of the in-app native import/export bridge
    // (ios/Runner/MediaImport/MediaImportPlugin.swift).
    if let controller = window?.rootViewController as? FlutterViewController {
      MediaImportPlugin.register(messenger: controller.binaryMessenger, presenter: controller)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
