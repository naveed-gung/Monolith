import AVFoundation
import Flutter
import MediaPlayer
import UIKit

/// Native import/export bridge for Monolith 2.0.
///
/// Channel: `monolith/media_import`
///
/// Methods:
/// - `pickFromMusicLibrary` → presents `MPMediaPickerController` and copies
///   readable local audio into `Documents/Monolith/Music/Imports`. Returns an
///   array of dicts:
///   `{status: copied|protected|unavailable|failed, path?, title, artist, reason?, durationMs?}`
/// - `exportToFiles` `{paths: [String]}` → presents a Save-to-Files document
///   picker (`asCopy: true`) so the user chooses the destination in Files /
///   iCloud Drive. Returns `{canceled: Bool}`.
/// - `getDocumentsMusicPath` → absolute path of `Documents/Monolith/Music`.
///
/// Deliberately conservative: main-thread UI, long-stable UIKit/MediaPlayer
/// APIs, async AVFoundation loading (deployment target is iOS 16.4).
final class MediaImportPlugin: NSObject {
  private static let channelName = "monolith/media_import"

  /// Keeps the instance (and its delegate conformances) alive for the app's
  /// lifetime so a presented sheet always has a live delegate.
  private static var activeInstance: MediaImportPlugin?

  private let channel: FlutterMethodChannel
  private weak var presenter: UIViewController?

  private var pendingImportResult: FlutterResult?
  private var pendingExportResult: FlutterResult?

  private init(messenger: FlutterBinaryMessenger, presenter: UIViewController?) {
    channel = FlutterMethodChannel(name: Self.channelName, binaryMessenger: messenger)
    self.presenter = presenter
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call: call, result: result)
    }
  }

  /// Called from AppDelegate after `GeneratedPluginRegistrant.register`.
  static func register(messenger: FlutterBinaryMessenger, presenter: UIViewController?) {
    guard activeInstance == nil else { return }
    activeInstance = MediaImportPlugin(messenger: messenger, presenter: presenter)
  }

  // MARK: - Method dispatch

  private func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "pickFromMusicLibrary":
      pickFromMusicLibrary(result: result)
    case "exportToFiles":
      exportToFiles(arguments: call.arguments, result: result)
    case "getDocumentsMusicPath":
      getDocumentsMusicPath(result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Music-app import

  private func pickFromMusicLibrary(result: @escaping FlutterResult) {
    DispatchQueue.main.async { [weak self] in
      guard let self = self, let presenter = self.presenter else {
        result([])
        return
      }
      guard self.pendingImportResult == nil && self.pendingExportResult == nil else {
        result(FlutterError(code: "busy", message: "A picker is already open.", details: nil))
        return
      }
      self.pendingImportResult = result
      MPMediaLibrary.requestAuthorization { [weak self] status in
        DispatchQueue.main.async {
          guard let self = self else { return }
          guard status == .authorized else {
            self.pendingImportResult = nil
            result(FlutterError(code: "permission_denied", message: "Allow Music access in iPhone Settings, then try again.", details: nil))
            return
          }
          let picker = MPMediaPickerController(mediaTypes: .music)
          picker.showsCloudItems = false
          picker.showsItemsWithProtectedAssets = false
          picker.allowsPickingMultipleItems = true
          picker.delegate = self
          var top = presenter
          while let presented = top.presentedViewController { top = presented }
          top.present(picker, animated: true)
        }
      }
    }
  }

  /// Copies one selected media item into the app sandbox and reports an
  /// honest per-item status. Runs off the UI thread via async/await; the
  /// caller replies on the main actor once every item is processed.
  private static func process(item: MPMediaItem) async -> [String: Any] {
    let title = item.value(forProperty: MPMediaItemPropertyTitle) as? String ?? "Unknown Title"
    let artist = item.value(forProperty: MPMediaItemPropertyArtist) as? String ?? "Unknown Artist"

    var payload: [String: Any] = ["title": title, "artist": artist]
    if let seconds = item.value(forProperty: MPMediaItemPropertyPlaybackDuration) as? Double {
      payload["durationMs"] = Int(seconds * 1000)
    }

    guard let assetURL = item.value(forProperty: MPMediaItemPropertyAssetURL) as? URL else {
      payload["status"] = "unavailable"
      payload["reason"] =
        "No local audio file for this item (cloud-only, or Apple prevents app access)."
      return payload
    }

    let asset = AVURLAsset(url: assetURL)
    if item.hasProtectedAsset {
      payload["status"] = "protected"
      payload["reason"] = "This song is DRM-protected. Import an unprotected original audio file instead."
      return payload
    }
    do {
      let destination: URL
      if assetURL.isFileURL {
        destination = try destinationURL(for: assetURL, title: title)
        try FileManager.default.copyItem(at: assetURL, to: destination)
      } else {
        // ipod-library URLs are AVFoundation assets, not filesystem paths.
        destination = try importsDirectory().appendingPathComponent("\(sanitizedFileName(title))-\(UUID().uuidString).m4a")
        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
          throw NSError(domain: "Monolith", code: 1, userInfo: [NSLocalizedDescriptionKey: "This library asset cannot be exported."])
        }
        exporter.outputURL = destination
        exporter.outputFileType = .m4a
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
          exporter.exportAsynchronously { continuation.resume() }
        }
        guard exporter.status == .completed else {
          try? FileManager.default.removeItem(at: destination)
          throw exporter.error ?? NSError(domain: "Monolith", code: 2, userInfo: [NSLocalizedDescriptionKey: "Music export did not complete."])
        }
      }
      // Ensure file exists, is non-empty, and has FileProtectionType.none so AVPlayer
      // can always read it even if screen is locked or across app sessions without (-11829) error.
      let attrs = try FileManager.default.attributesOfItem(atPath: destination.path)
      let fileSize = (attrs[.size] as? NSNumber)?.int64Value ?? 0
      guard fileSize > 1024 else {
        try? FileManager.default.removeItem(at: destination)
        throw NSError(domain: "Monolith", code: 3, userInfo: [NSLocalizedDescriptionKey: "Imported audio file is empty or unreadable."])
      }
      try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.none], ofItemAtPath: destination.path)
      if let image = item.artwork?.image(at: CGSize(width: 600, height: 600)),
         let data = image.jpegData(compressionQuality: 0.85) {
        let artURL = destination.deletingPathExtension().appendingPathExtension("jpg")
        try? data.write(to: artURL, options: .atomic)
        try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.none], ofItemAtPath: artURL.path)
      }
      payload["status"] = "copied"
      payload["path"] = destination.path
    } catch {
      payload["status"] = "failed"
      payload["reason"] = error.localizedDescription
    }
    return payload
  }

  // MARK: - Save-to-Files export

  private func exportToFiles(arguments: Any?, result: @escaping FlutterResult) {
    let args = arguments as? [String: Any]
    let paths = args?["paths"] as? [String] ?? []

    DispatchQueue.main.async { [weak self] in
      guard let self = self, let presenter = self.presenter else {
        result(["canceled": true])
        return
      }
      let urls = paths
        .map { URL(fileURLWithPath: $0) }
        .filter { FileManager.default.fileExists(atPath: $0.path) }
      guard !urls.isEmpty else {
        result(["canceled": true])
        return
      }
      guard self.pendingImportResult == nil && self.pendingExportResult == nil else {
        result(FlutterError(code: "busy", message: "A picker is already open.", details: nil))
        return
      }
      let picker = UIDocumentPickerViewController(forExporting: urls, asCopy: true)
      picker.delegate = self
      self.pendingExportResult = result
      var top = presenter
      while let presented = top.presentedViewController { top = presented }
      top.present(picker, animated: true)
    }
  }

  private func finishExport(canceled: Bool) {
    guard let result = pendingExportResult else { return }
    pendingExportResult = nil
    result(["canceled": canceled])
  }

  // MARK: - Paths

  private func getDocumentsMusicPath(result: @escaping FlutterResult) {
    let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let dir = documents.appendingPathComponent("Monolith/Music", isDirectory: true)
    do {
      try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    } catch {
      // Still report the path; creation failures surface when files are written.
    }
    result(dir.path)
  }

  // MARK: - Copy helpers

  private static func importsDirectory() throws -> URL {
    let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let dir = documents.appendingPathComponent("Monolith/Music/Imports", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.none], ofItemAtPath: dir.path)
    return dir
  }

  private static func destinationURL(for assetURL: URL, title: String) throws -> URL {
    let ext = assetURL.pathExtension.isEmpty ? "m4a" : assetURL.pathExtension
    let stamp = Int(Date().timeIntervalSince1970 * 1000)
    let fileName = "\(sanitizedFileName(title))-\(stamp).\(ext)"
    return try importsDirectory().appendingPathComponent(fileName)
  }

  static func sanitizedFileName(_ raw: String) -> String {
    let invalidCharacters = CharacterSet(charactersIn: "/\\:*?\"<>|'`’[]{}()^%#@!&$+=;")
    let scalars = raw.unicodeScalars.map { scalar -> Character in
      (invalidCharacters.contains(scalar) || scalar.value < 32 || scalar.value > 126) ? "_" : Character(scalar)
    }
    var name = String(scalars)
      .replacingOccurrences(of: "_+", with: "_", options: .regularExpression)
      .trimmingCharacters(in: CharacterSet(charactersIn: "_ ").union(.whitespacesAndNewlines))
    if name.isEmpty { name = "audio" }
    if name.count > 60 { name = String(name.prefix(60)) }
    return name
  }
}

// MARK: - MPMediaPickerControllerDelegate

extension MediaImportPlugin: MPMediaPickerControllerDelegate {
  func mediaPicker(
    _ mediaPicker: MPMediaPickerController,
    didPickMediaItems mediaItemCollection: MPMediaItemCollection
  ) {
    mediaPicker.dismiss(animated: true)
    let items = mediaItemCollection.items
    guard let result = pendingImportResult else { return }
    pendingImportResult = nil

    Task { @MainActor in
      var payloads: [[String: Any]] = []
      payloads.reserveCapacity(items.count)
      for item in items {
        payloads.append(await MediaImportPlugin.process(item: item))
      }
      result(payloads)
    }
  }

  func mediaPickerDidCancel(_ mediaPicker: MPMediaPickerController) {
    mediaPicker.dismiss(animated: true)
    if let result = pendingImportResult {
      pendingImportResult = nil
      result([])
    }
  }
}

// MARK: - UIDocumentPickerDelegate

extension MediaImportPlugin: UIDocumentPickerDelegate {
  func documentPicker(
    _ controller: UIDocumentPickerViewController,
    didPickDocumentsAt urls: [URL]
  ) {
    finishExport(canceled: false)
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    finishExport(canceled: true)
  }
}
