import Cocoa
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
/// beside it. A project is `<name>.anicel` plus a sibling `<name>.assets/`
/// directory plus an autosave sidecar written every five minutes — so
/// picking the project FILE grants the one item that cannot be saved, and
/// the folder is the unit of permission for a PROJECT exactly as on iPad.
///
/// A referenced MEDIA file is the other case and it wants the opposite: the
/// file is the whole of what the project needs, it is not written to, and
/// asking the user to grant its containing folder would be asking for more
/// than the job needs. Hence two modes over one grant vocabulary.
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
  /// an open project's autosave.
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
