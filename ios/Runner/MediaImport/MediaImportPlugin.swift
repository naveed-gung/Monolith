import AVFoundation
import Flutter
import MediaPlayer
import UIKit
import UserNotifications

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

  private var isImportCancelled = false
  private var cancelCurrentImport: (() -> Void)?

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
    DispatchQueue.global(qos: .background).async {
      Self.cleanupTempFiles()
    }
  }

  private static func cleanupTempFiles() {
    guard let dir = try? importsDirectory() else { return }
    let fileManager = FileManager.default
    if let files = try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
      for file in files where file.pathExtension.lowercased() == "tmp" {
        try? fileManager.removeItem(at: file)
      }
    }
  }

  // MARK: - Method dispatch

  private func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "cancelMusicImport":
      isImportCancelled = true
      cancelCurrentImport?()
      result(nil)
    case "requestNotificationPermission":
      UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
        DispatchQueue.main.async { result(granted) }
      }
    case "updateDownloadNotification":
      guard let args = call.arguments as? [String: Any],
            let id = args["id"] as? String,
            let title = args["title"] as? String,
            let body = args["body"] as? String else {
        result(nil)
        return
      }
      let content = UNMutableNotificationContent()
      content.title = title
      content.body = body
      content.sound = (args["isComplete"] as? Bool ?? false) ? .default : nil
      let request = UNNotificationRequest(identifier: "download_\(id)", content: content, trigger: nil)
      UNUserNotificationCenter.current().add(request) { _ in
        DispatchQueue.main.async { result(nil) }
      }
    case "cancelDownloadNotification":
      if let args = call.arguments as? [String: Any], let id = args["id"] as? String {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["download_\(id)"])
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["download_\(id)"])
      }
      result(nil)
    case "readAudioMetadata":
      guard let args = call.arguments as? [String: Any], let path = args["path"] as? String else {
        result(FlutterError(code: "invalid_path", message: "Missing audio path", details: nil)); return
      }
      DispatchQueue.global(qos: .utility).async {
        let url = URL(fileURLWithPath: path)
        // Existing imports may have inherited protection incompatible with locked playback.
        try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.none], ofItemAtPath: path)
        let asset = AVURLAsset(url: url)
        asset.loadValuesAsynchronously(forKeys: ["duration", "tracks", "playable"]) {
          let seconds = CMTimeGetSeconds(asset.duration)
          let duration = seconds.isFinite && seconds > 0 ? Int(seconds * 1000) : 0
          DispatchQueue.main.async {
            result(["durationMs": duration, "playable": asset.isPlayable && !asset.tracks(withMediaType: .audio).isEmpty])
          }
        }
      }
    case "pickFromMusicLibrary":
      pickFromMusicLibrary(result: result)
    case "importAllFromMusicLibrary":
      importAllFromMusicLibrary(result: result)
    case "exportToFiles":
      exportToFiles(arguments: call.arguments, result: result)
    case "getDocumentsMusicPath":
      getDocumentsMusicPath(result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Music-app import

  private func importAllFromMusicLibrary(result: @escaping FlutterResult) {
    DispatchQueue.main.async { [weak self] in
      guard let self = self else {
        result([])
        return
      }
      guard self.pendingImportResult == nil && self.pendingExportResult == nil else {
        result(FlutterError(code: "busy", message: "An import is already in progress.", details: nil))
        return
      }
      self.pendingImportResult = result
      self.isImportCancelled = false
      MPMediaLibrary.requestAuthorization { [weak self] status in
        DispatchQueue.main.async {
          guard let self = self else { return }
          if self.isImportCancelled {
            self.pendingImportResult = nil
            result([])
            return
          }
          guard status == .authorized else {
            self.pendingImportResult = nil
            result(FlutterError(code: "permission_denied", message: "Allow Music access in iPhone Settings, then try again.", details: nil))
            return
          }
          DispatchQueue.global(qos: .userInitiated).async {
            let query = MPMediaQuery.songs()
            query.addFilterPredicate(MPMediaPropertyPredicate(value: false, forProperty: MPMediaItemPropertyIsCloudItem))
            let items = query.items ?? []
            guard !items.isEmpty else {
              DispatchQueue.main.async {
                self.pendingImportResult = nil
                result([])
              }
              return
            }
            Task { @MainActor in
              await self.processItems(items)
            }
          }
        }
      }
    }
  }

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
      self.isImportCancelled = false
      MPMediaLibrary.requestAuthorization { [weak self] status in
        DispatchQueue.main.async {
          guard let self = self else { return }
          if self.isImportCancelled {
            self.pendingImportResult = nil
            result([])
            return
          }
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

  @MainActor
  private func processItems(_ items: [MPMediaItem]) async {
    guard let result = pendingImportResult else { return }
    // Keep this lock through export, validation and cancellation cleanup.
    var payloads: [[String: Any]] = []
    for (index, item) in items.enumerated() {
      if isImportCancelled { break }
      channel.invokeMethod("onImportProgress", arguments: [
        "current": index, "total": items.count, "title": item.title ?? "Song"
      ])
      payloads.append(await process(item: item))
      channel.invokeMethod("onImportProgress", arguments: [
        "current": index + 1, "total": items.count, "title": item.title ?? "Song"
      ])
    }
    cancelCurrentImport = nil
    pendingImportResult = nil
    result(payloads)
  }

  /// Finish exactly once even if AVFoundation calls back after timeout/cancel.
  /// All state transitions occur on the main queue; file IO is dispatched out.
  @MainActor
  private func importStep<T>(
    timeout: TimeInterval,
    cancel: @escaping () -> Void = {},
    start: (@escaping (Result<T, Error>) -> Void) -> Void
  ) async throws -> T {
    if isImportCancelled { throw importError("Import cancelled.") }
    return try await withCheckedThrowingContinuation { continuation in
      var finished = false
      var deadline: DispatchWorkItem?
      func finish(_ outcome: Result<T, Error>) {
        guard !finished else { return }
        finished = true
        deadline?.cancel()
        self.cancelCurrentImport = nil
        continuation.resume(with: outcome)
      }
      let timer = DispatchWorkItem {
        cancel()
        finish(.failure(self.importError("Music took too long to export or read this song. Try importing the original file.")))
      }
      deadline = timer
      cancelCurrentImport = {
        cancel()
        finish(.failure(self.importError("Import cancelled.")))
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: timer)
      start { outcome in DispatchQueue.main.async { finish(outcome) } }
    }
  }

  private func importError(_ message: String) -> NSError {
    NSError(domain: "Monolith.MusicImport", code: 1,
            userInfo: [NSLocalizedDescriptionKey: message])
  }

  @MainActor
  private func process(item: MPMediaItem) async -> [String: Any] {
    let title = item.title ?? "Unknown Title"
    let artist = item.artist ?? "Unknown Artist"
    var payload: [String: Any] = ["title": title, "artist": artist]
    if item.playbackDuration.isFinite && item.playbackDuration > 0 {
      payload["durationMs"] = Int(item.playbackDuration * 1000)
    }
    if item.hasProtectedAsset {
      payload["status"] = "protected"
      payload["reason"] = "Music marks this song as protected. Import its unprotected original from Files."
      return payload
    }
    guard let assetURL = item.assetURL else {
      payload["status"] = "unavailable"
      payload["reason"] = "Music did not provide readable audio. Download the original in Music, or import from Files."
      return payload
    }
    var staging: URL?
    defer { if let staging = staging { try? FileManager.default.removeItem(at: staging) } }
    do {
      let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
      // Outside Music, so startup recovery cannot treat an unfinished export as a song.
      let work = documents.appendingPathComponent("Monolith/ImportStaging/\(UUID().uuidString)", isDirectory: true)
      staging = work
      try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
      let ext = assetURL.isFileURL && !assetURL.pathExtension.isEmpty ? assetURL.pathExtension : "m4a"
      let temp = work.appendingPathComponent("audio").appendingPathExtension(ext)
      let destination = try Self.importsDirectory().appendingPathComponent("\(Self.sanitizedFileName(title))-\(UUID().uuidString).\(ext)")
      if assetURL.isFileURL {
        let _: Bool = try await importStep(timeout: 60) { done in
          DispatchQueue.global(qos: .utility).async {
            do { try FileManager.default.copyItem(at: assetURL, to: temp); done(.success(true)) }
            catch { done(.failure(error)) }
          }
        }
      } else {
        let asset = AVURLAsset(url: assetURL)
        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
          throw importError("Music cannot export this asset. Try importing the original file.")
        }
        exporter.outputURL = temp
        exporter.outputFileType = .m4a
        let _: Bool = try await importStep(timeout: 300, cancel: { exporter.cancelExport() }) { done in
          exporter.exportAsynchronously {
            if exporter.status == .completed { done(.success(true)) }
            else { done(.failure(exporter.error ?? self.importError("Music export did not complete."))) }
          }
        }
      }
      try FileManager.default.setAttributes([.protectionKey: FileProtectionType.none], ofItemAtPath: temp.path)
      let attrs = try FileManager.default.attributesOfItem(atPath: temp.path)
      guard ((attrs[.size] as? NSNumber)?.int64Value ?? 0) > 0 else {
        throw importError("Music produced an empty audio file.")
      }
      let exported = AVURLAsset(url: temp)
      let _: Bool = try await importStep(timeout: 20, cancel: { exported.cancelLoading() }) { done in
        exported.loadValuesAsynchronously(forKeys: ["tracks", "duration", "playable"]) {
          var loadError: NSError?
          for key in ["tracks", "duration", "playable"] {
            guard exported.statusOfValue(forKey: key, error: &loadError) == .loaded else {
              done(.failure(loadError ?? self.importError("Could not read exported audio metadata.")))
              return
            }
          }
          done(.success(true))
        }
      }
      guard exported.isPlayable, !exported.tracks(withMediaType: .audio).isEmpty else {
        throw importError("Music returned audio that cannot be played. Import the original file instead.")
      }
      if isImportCancelled { throw importError("Import cancelled.") }
      let seconds = CMTimeGetSeconds(exported.duration)
      if seconds.isFinite && seconds > 0 { payload["durationMs"] = Int(seconds * 1000) }
      try FileManager.default.moveItem(at: temp, to: destination)
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
      let nativeError = error as NSError
      payload["reason"] = "\(error.localizedDescription) (\(nativeError.domain) \(nativeError.code))"
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
    Task { @MainActor in
      await processItems(items)
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
