import Cocoa
import FileProvider
import FlutterMacOS
import UniformTypeIdentifiers

/// Anicel pen sidecar (pen program, PEN-4 — macOS).
///
/// Flutter's macOS embedder does not deliver tablet pressure/tilt from
/// external tablets (flutter/flutter#146387): Wacom-style drivers
/// synthesize mouse events whose NSEvent carries `.tabletPoint` data the
/// embedder drops. This monitor restores it: a LOCAL event monitor (this
/// app's events only — no accessibility permission involved) forwards
/// pressure/tilt onto the 'qa_pen/macos' event channel, the same
/// pressure-sidecar contract as the Windows Wintab bridge.
///
/// UNVERIFIED-ON-DEVICE: authored on the Windows workstation; needs one
/// macOS build + a tablet pass (the input inspector's 'mac p=' line is
/// the check). Runner-owned so no plugin registrant churn.
class PenSidecarStreamHandler: NSObject, FlutterStreamHandler {
  private var sink: FlutterEventSink?
  private var monitor: Any?

  func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    sink = events
    // Tablet-capable events: dedicated tabletPoint events AND the mouse
    // events that carry a tablet subtype (how most drivers deliver).
    let mask: NSEvent.EventTypeMask = [
      .tabletPoint, .leftMouseDown, .leftMouseDragged,
    ]
    monitor = NSEvent.addLocalMonitorForEvents(matching: mask) {
      [weak self] event in
      self?.forward(event)
      return event
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    if let monitor = monitor {
      NSEvent.removeMonitor(monitor)
    }
    monitor = nil
    sink = nil
    return nil
  }

  private func forward(_ event: NSEvent) {
    guard let sink = sink else { return }
    let isTablet =
      event.type == .tabletPoint || event.subtype == .tabletPoint
    guard isTablet else { return }
    sink([
      "pressure": Double(event.pressure),
      "tiltX": Double(event.tilt.x),
      "tiltY": Double(event.tilt.y),
      "timeMs": event.timestamp * 1000.0,
      "eraser": false,
    ])
  }
}

/// PICK-2/PICK-5: path grants on macOS.
///
/// macOS looks like Windows and behaves like iPadOS. It runs sandboxed
/// (`com.apple.security.app-sandbox` in both entitlement files), so a panel
/// selection extends the sandbox to EXACTLY the item picked and to nothing
/// beside it. Since the single-file format a project is ONE `.anicel` and
/// its recovery overlay lives in the app container, so the file itself is
/// the unit of permission for a PROJECT (PICK-6) — every save appends into
/// exactly the item picked. Folder mode remains for the folder-shaped picks
/// (cut-folder import, sequence export, the recordings directory, relink).
///
/// A referenced MEDIA file wants the same file-shaped grant for the
/// opposite reason: it is not written to, and asking the user to grant its
/// containing folder would be asking for more than the job needs. Hence two
/// modes over one grant vocabulary.
///
/// The two entitlements this needs are `files.user-selected.read-write` (or
/// the panel opens and every read of its result fails) and
/// `files.bookmarks.app-scope` (or a granted folder dies at relaunch).
///
/// UNVERIFIED-ON-DEVICE: authored on the Windows workstation like the pen
/// sidecar above. Needs one macOS build.
final class PathGrantHandler {
  /// Items this process holds a scope on, keyed by path — FILES as well as
  /// folders since PICK-5. Nothing removes entries — see the iOS twin for
  /// why: stopping a scope mid-session would pull the floor out from under
  /// the open project's own saves and carried-media reads.
  private var scopedItems: [String: URL] = [:]

  func handle(
    _ call: FlutterMethodCall, host: NSWindow?, _ result: @escaping FlutterResult
  ) {
    let arguments = call.arguments as? [String: Any]
    switch call.method {
    case "pickProjectFolder":
      pick(
        initialDirectory: arguments?["initialDirectory"] as? String, host: host,
        result: result)
    case "pickFiles":
      pickFiles(
        utis: arguments?["utis"] as? [String] ?? [],
        allowMultiple: arguments?["allowMultiple"] as? Bool ?? false,
        host: host, result: result)
    case "exportFile":
      exportFile(
        sourcePath: arguments?["sourcePath"] as? String,
        suggestedName: arguments?["suggestedName"] as? String,
        host: host, result: result)
    case "resolveBookmark":
      resolve(base64: arguments?["bookmark"] as? String, result: result)
    case "replaceFileCoordinated":
      // The iOS twin's coordinated replace, verbatim: a sandboxed macOS
      // app writing into a File Provider location meets the same refusal,
      // and the same coordinator is the sanctioned way through it.
      PathGrantHandler.replaceFileCoordinated(
        sourcePath: arguments?["sourcePath"] as? String,
        destinationPath: arguments?["destinationPath"] as? String,
        result: result)
    case "readFileCoordinated":
      PathGrantHandler.readFileCoordinated(
        sourcePath: arguments?["sourcePath"] as? String,
        destinationPath: arguments?["destinationPath"] as? String,
        result: result)
    case "requestFileDownload":
      PathGrantHandler.requestFileDownload(
        sourcePath: arguments?["sourcePath"] as? String, result: result)
    case "readInPlaceCoordinated":
      PathGrantHandler.readInPlaceCoordinated(
        sourcePath: arguments?["sourcePath"] as? String, result: result)
    case "touchFileCoordinated":
      PathGrantHandler.touchFileCoordinated(
        sourcePath: arguments?["sourcePath"] as? String, result: result)
    default:
      // Only the two folder-grant methods live here. The channel's other
      // methods are mobile-only on the Dart side — `ensureInitialized` early
      // -returns for every non-mobile platform and the two all-files methods
      // short-circuit for non-Android — so answering them here would be
      // unreachable code pretending to be a contract.
      result(FlutterMethodNotImplemented)
    }
  }

  func pick(
    initialDirectory: String?, host: NSWindow?, result: @escaping FlutterResult
  ) {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = true
    if let initialDirectory, !initialDirectory.isEmpty {
      panel.directoryURL = URL(fileURLWithPath: initialDirectory)
    }
    present(panel: panel, host: host, result: result)
  }

  /// PICK-5: files, in place, with a scope on each.
  ///
  /// macOS reaches this through `file_selector_macos` today and that works —
  /// NSOpenPanel hands back the real URL, no copy involved. What it does NOT
  /// hand back is a bookmark, so a reference recorded from it dies at the
  /// next launch inside the sandbox. Same panel, one extra step.
  func pickFiles(
    utis: [String], allowMultiple: Bool, host: NSWindow?,
    result: @escaping FlutterResult
  ) {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    panel.allowsMultipleSelection = allowMultiple
    panel.canCreateDirectories = false
    // Left unset when the list is empty or none of it resolves — an empty
    // `allowedContentTypes` would grey out every file in the panel, which
    // reads as a broken dialog rather than as "no filter".
    if #available(macOS 11.0, *), !utis.isEmpty {
      let types = utis.compactMap { UTType($0) }
      if !types.isEmpty {
        panel.allowedContentTypes = types
      }
    }
    present(panel: panel, host: host, result: result)
  }

  /// PICK-6: hands a finished file to the user's chosen location.
  ///
  /// macOS DOES have a save panel, so the inversion iOS forces is not needed
  /// here — but the CONTRACT is shared: Dart writes into the app container
  /// and asks for the file to be placed. Keeping one contract means Dart
  /// never has to know that one platform hands over a file and another hands
  /// back a path.
  ///
  /// The move happens here rather than in Dart because the sandbox extends
  /// to the panel's answer, and doing it while that answer is fresh is the
  /// simplest way to be sure the write is inside it.
  func exportFile(
    sourcePath: String?, suggestedName: String?, host: NSWindow?,
    result: @escaping FlutterResult
  ) {
    guard let sourcePath, !sourcePath.isEmpty else {
      result(["status": "unavailable"])
      return
    }
    let source = URL(fileURLWithPath: sourcePath)
    let panel = NSSavePanel()
    panel.nameFieldStringValue = suggestedName ?? source.lastPathComponent
    panel.canCreateDirectories = true
    let complete: (NSApplication.ModalResponse) -> Void = { [weak self] response in
      guard response == .OK, let destination = panel.url else {
        result(["status": "cancelled"])
        return
      }
      guard let self else {
        result(["status": "unavailable"])
        return
      }
      do {
        // The panel already asked about overwriting; `moveItem` refuses a
        // destination that exists, so the yes it collected has to be acted
        // on here.
        if FileManager.default.fileExists(atPath: destination.path) {
          try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: source, to: destination)
      } catch {
        result(["status": "unavailable"])
        return
      }
      result(self.grantPayload(for: destination))
    }
    if let host {
      panel.beginSheetModal(for: host, completionHandler: complete)
    } else {
      panel.begin(completionHandler: complete)
    }
  }

  private func present(
    panel: NSOpenPanel, host: NSWindow?, result: @escaping FlutterResult
  ) {
    let complete: (NSApplication.ModalResponse) -> Void = { [weak self] response in
      // The cancel reply comes FIRST and does not need self — a dropped
      // reply is an unkillable hang on the Dart side, not a visible error.
      guard response == .OK, !panel.urls.isEmpty else {
        result(["status": "cancelled"])
        return
      }
      guard let self else {
        result(["status": "unavailable"])
        return
      }
      result(self.grantPayload(for: panel.urls))
    }
    // A SHEET, not `begin`'s modeless panel. Modeless, it leaves the canvas
    // fully clickable underneath and can be sent behind a full-screen drawing
    // window — the user sees "nothing happened" and opens a second one.
    if let host {
      panel.beginSheetModal(for: host, completionHandler: complete)
    } else {
      panel.begin(completionHandler: complete)
    }
  }

  private func resolve(base64: String?, result: @escaping FlutterResult) {
    guard let base64, let data = Data(base64Encoded: base64) else {
      result(["status": "unavailable"])
      return
    }
    var isStale = false
    do {
      let url = try URL(
        resolvingBookmarkData: data, options: .withSecurityScope,
        relativeTo: nil, bookmarkDataIsStale: &isStale)
      // The payload carries a FRESH bookmark; `_openRecent` stores it, which
      // is what stops an app-scoped bookmark decaying until it one day
      // refuses and drops the user into the reconnect flow for no visible
      // reason. That is also why `isStale` needs no separate channel field.
      result(grantPayload(for: url, requiringScope: true))
    } catch {
      result(["status": "unavailable"])
    }
  }

  /// Takes the scope and mints a bookmark. The path it reports is an
  /// ordinary POSIX path — once the scope is open the sandbox extension
  /// applies process-wide, so the Dart save stack keeps using `dart:io`.
  private func grantPayload(for url: URL, requiringScope: Bool = false)
    -> [String: Any?]
  {
    let opened = url.startAccessingSecurityScopedResource()
    // See the iOS twin: a bookmark that resolves but will not open its scope
    // is not a grant.
    if requiringScope && !opened {
      return ["status": "unavailable"]
    }
    // Recorded unconditionally. A URL handed back by NSOpenPanel is NOT a
    // security-scoped URL — Powerbox extends the sandbox to the process
    // directly and `startAccessingSecurityScopedResource` returns false for
    // it — so keying the insert on that flag left `scopedItems` empty after
    // every fresh pick.
    scopedItems[url.path] = url
    var bookmark: String?
    do {
      // `.withSecurityScope` is the macOS spelling — the iOS runner uses
      // `.minimalBookmark`, and each throws on the other platform.
      let data = try url.bookmarkData(
        options: .withSecurityScope, includingResourceValuesForKeys: nil,
        relativeTo: nil)
      bookmark = data.base64EncodedString()
    } catch {
      bookmark = nil
    }
    // One payload shape for one item and for many — see the iOS twin.
    return ["status": "granted", "items": [["path": url.path, "bookmark": bookmark]]]
  }

  /// The same, for a pick that may have returned several URLs. A URL that
  /// fails to grant is dropped rather than failing the batch.
  private func grantPayload(for urls: [URL]) -> [String: Any?] {
    if urls.isEmpty {
      return ["status": "cancelled"]
    }
    var items: [[String: Any?]] = []
    for url in urls {
      let payload = grantPayload(for: url)
      if let granted = payload["items"] as? [[String: Any?]] {
        items.append(contentsOf: granted)
      }
    }
    return items.isEmpty
      ? ["status": "unavailable"] : ["status": "granted", "items": items]
  }

  /// Overwrites [destinationPath] with [sourcePath]'s bytes through an
  /// `NSFileCoordinator` — see the iOS twin for the whole story (실측
  /// 08-26, iPhone + Google Drive: plain writes into a provider file are
  /// refused; the coordinated replace is the sanctioned way through).
  static func replaceFileCoordinated(
    sourcePath: String?, destinationPath: String?,
    result: @escaping FlutterResult
  ) {
    guard let sourcePath, let destinationPath else {
      result(["status": "unavailable"])
      return
    }
    DispatchQueue.global(qos: .userInitiated).async {
      let source = URL(fileURLWithPath: sourcePath)
      let destination = URL(fileURLWithPath: destinationPath)
      let coordinator = NSFileCoordinator(filePresenter: nil)
      var coordinationError: NSError?
      var writeError: Error?
      // Both items are coordinated: the source is MOVING, the destination
      // is being REPLACED — which is what tells a provider「the same item,
      // new content」rather than「one deleted, another created」.
      coordinator.coordinate(
        writingItemAt: source, options: .forMoving,
        writingItemAt: destination, options: .forReplacing,
        error: &coordinationError
      ) { from, to in
        do {
          // A MOVE first. Beside the destination (the save's own temp) it
          // is the rename a direct save costs — no second copy of the
          // archive. The copy is the road for a source on another volume
          // (this run's staging room, under a file-scoped grant), where a
          // move would be a copy anyway.
          if FileManager.default.fileExists(atPath: to.path) {
            _ = try FileManager.default.replaceItemAt(to, withItemAt: from)
          } else {
            try FileManager.default.moveItem(at: from, to: to)
          }
        } catch {
          do {
            let data = try Data(contentsOf: from, options: .mappedIfSafe)
            try data.write(to: to, options: .atomic)
          } catch {
            writeError = error
          }
        }
      }
      let failure = coordinationError ?? (writeError as NSError?)
      DispatchQueue.main.async {
        if let failure {
          result([
            "status": "unavailable", "message": failure.localizedDescription,
          ])
        } else {
          // The ONE payload dialect: `items`, for one and for many alike.
          // Speaking `path` here made every coordinated call decode as
          // UNAVAILABLE in Dart — the replace ran, the file landed, and
          // the app told the user the location had refused it.
          result(["status": "granted", "items": [["path": destinationPath]]])
        }
      }
    }
  }

  /// The READ twin: a File Provider document can be a non-materialised
  /// placeholder, and a plain read of one fails even inside an open
  /// security scope. Coordinated reading tells the provider to download;
  /// the bytes are staged into [destinationPath] for Dart to read.
  /// Asks the provider to bring a file's bytes down, and COPIES NOTHING.
  ///
  /// 유저 2026-08-27: 「사본은 왠만하면 만들고싶지않아」. The request used
  /// to live inside [readFileCoordinated], which meant the only way to
  /// trigger a download was to stage a second copy of a file the cloud
  /// client is already keeping locally — the same bytes twice, and a
  /// temp file whose lifetime nobody owned. Asked on its own, the open
  /// can simply WAIT for the item the user picked and then read it where
  /// it lies.
  ///
  /// Best-effort by design: this is the documented request for iCloud and
  /// File Provider items and it throws for a plain local file, where
  /// there was nothing to fetch in the first place. Either way the answer
  /// is the same — ask, then let the caller's own reads decide when the
  /// file is ready, which is the one signal every platform agrees on.
  static func requestFileDownload(
    sourcePath: String?, result: @escaping FlutterResult
  ) {
    guard let sourcePath else {
      result(["status": "unavailable"])
      return
    }
    DispatchQueue.global(qos: .userInitiated).async {
      let source = URL(fileURLWithPath: sourcePath)
      try? FileManager.default.startDownloadingUbiquitousItem(at: source)
      DispatchQueue.main.async {
        result(["status": "granted", "items": [["path": sourcePath]]])
      }
    }
  }

  /// The iOS twin's in-place coordinated read, verbatim: the item is
  /// opened inside a coordinated read and closed again — the ask a File
  /// Provider actually answers with its current content — and nothing is
  /// copied. A `~/Library/CloudStorage` document under Drive for desktop
  /// meets the same provider discipline a sandboxed app meets on iOS.
  static func readInPlaceCoordinated(
    sourcePath: String?, result: @escaping FlutterResult
  ) {
    guard let sourcePath else {
      result(["status": "unavailable"])
      return
    }
    DispatchQueue.global(qos: .userInitiated).async {
      let source = URL(fileURLWithPath: sourcePath)
      try? FileManager.default.startDownloadingUbiquitousItem(at: source)
      let coordinator = NSFileCoordinator(filePresenter: nil)
      var coordinationError: NSError?
      var readError: Error?
      coordinator.coordinate(
        readingItemAt: source, options: [],
        error: &coordinationError
      ) { url in
        do {
          let handle = try FileHandle(forReadingFrom: url)
          try handle.close()
        } catch {
          readError = error
        }
      }
      let failure = coordinationError ?? (readError as NSError?)
      DispatchQueue.main.async {
        if let failure {
          result([
            "status": "unavailable", "message": failure.localizedDescription,
          ])
        } else {
          result(["status": "granted", "items": [["path": sourcePath]]])
        }
      }
    }
  }

  /// The iOS twin's coordinated touch, verbatim: a coordinated write whose
  /// block only sets the modification date, after an append the app made
  /// in place — the coordination is what a File Provider hears (M-1).
  static func touchFileCoordinated(
    sourcePath: String?, result: @escaping FlutterResult
  ) {
    guard let sourcePath else {
      result(["status": "unavailable"])
      return
    }
    DispatchQueue.global(qos: .userInitiated).async {
      let url = URL(fileURLWithPath: sourcePath)
      let coordinator = NSFileCoordinator(filePresenter: nil)
      var coordinationError: NSError?
      coordinator.coordinate(
        writingItemAt: url, options: [], error: &coordinationError
      ) { url in
        try? FileManager.default.setAttributes(
          [.modificationDate: Date()], ofItemAtPath: url.path)
      }
      DispatchQueue.main.async {
        if let failure = coordinationError {
          result([
            "status": "unavailable", "message": failure.localizedDescription,
          ])
        } else {
          result(["status": "granted", "items": [["path": sourcePath]]])
        }
      }
    }
  }

  static func readFileCoordinated(
    sourcePath: String?, destinationPath: String?,
    result: @escaping FlutterResult
  ) {
    guard let sourcePath, let destinationPath else {
      result(["status": "unavailable"])
      return
    }
    DispatchQueue.global(qos: .userInitiated).async {
      let source = URL(fileURLWithPath: sourcePath)
      let destination = URL(fileURLWithPath: destinationPath)
      // Say out loud what the coordinated read below only implies: BRING
      // THE BYTES DOWN. Best-effort by design — this is the documented
      // request for iCloud and File Provider items, and it throws for a
      // plain local file, where the read that follows needs nothing. It
      // does not make the fetch instant, which is why the Dart caller
      // waits rather than treating one refusal as the answer.
      try? FileManager.default.startDownloadingUbiquitousItem(at: source)
      let coordinator = NSFileCoordinator(filePresenter: nil)
      var coordinationError: NSError?
      var readError: Error?
      coordinator.coordinate(
        readingItemAt: source, options: [],
        error: &coordinationError
      ) { url in
        do {
          let data = try Data(contentsOf: url, options: .mappedIfSafe)
          try data.write(to: destination, options: .atomic)
        } catch {
          readError = error
        }
      }
      let failure = coordinationError ?? (readError as NSError?)
      DispatchQueue.main.async {
        if let failure {
          result([
            "status": "unavailable", "message": failure.localizedDescription,
          ])
        } else {
          // The ONE payload dialect: `items`, for one and for many alike.
          // Speaking `path` here made every coordinated call decode as
          // UNAVAILABLE in Dart — the replace ran, the file landed, and
          // the app told the user the location had refused it.
          result(["status": "granted", "items": [["path": destinationPath]]])
        }
      }
    }
  }
}

class MainFlutterWindow: NSWindow {
  private let penStreamHandler = PenSidecarStreamHandler()

  /// Held as a property for the same reason `penStreamHandler` is: the
  /// channel keeps no strong reference, and this object owns the open
  /// security scopes.
  private let pathGrantHandler = PathGrantHandler()

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // The pen sidecar stream (PEN-4).
    let penChannel = FlutterEventChannel(
      name: "qa_pen/macos",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    penChannel.setStreamHandler(penStreamHandler)

    // PICK-2: the storage channel. macOS had none — `AppStorage` early
    // -returned for every non-mobile platform — so this is the first time
    // the desktop Apple build can be asked for anything.
    let storageChannel = FlutterMethodChannel(
      name: "qa_storage",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    // The HANDLER is captured, not the window. `[weak self]` here meant a
    // closed window (NSWindow.isReleasedWhenClosed defaults to true) would
    // return without ever invoking `result`, and a method call that is never
    // replied to leaves the Dart future pending for good — a hang, not an
    // error. PathGrantHandler holds no reference back, so there is no cycle.
    let handler = pathGrantHandler
    storageChannel.setMethodCallHandler { [weak self] call, result in
      handler.handle(call, host: self, result)
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
