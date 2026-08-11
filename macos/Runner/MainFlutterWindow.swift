import Cocoa
import FlutterMacOS

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

/// PICK-2: folder grants on macOS.
///
/// macOS looks like Windows and behaves like iPadOS. It runs sandboxed
/// (`com.apple.security.app-sandbox` in both entitlement files), so a panel
/// selection extends the sandbox to EXACTLY the item picked and to nothing
/// beside it. A project is `<name>.anicel` plus a sibling `<name>.assets/`
/// directory plus an autosave sidecar written every five minutes — so
/// picking the file grants the one item that cannot be saved, and the folder
/// is the unit of permission here exactly as it is on iPad.
///
/// The two entitlements this needs are `files.user-selected.read-write` (or
/// the panel opens and every read of its result fails) and
/// `files.bookmarks.app-scope` (or a granted folder dies at relaunch).
///
/// UNVERIFIED-ON-DEVICE: authored on the Windows workstation like the pen
/// sidecar above. Needs one macOS build.
final class FolderGrantHandler {
  /// Folders this process holds a scope on, keyed by path. Nothing removes
  /// entries — see the iOS twin for why: stopping a scope mid-session would
  /// pull the floor out from under an open project's autosave.
  private var scopedFolders: [String: URL] = [:]

  func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    switch call.method {
    case "pickProjectFolder":
      pick(
        initialDirectory: (call.arguments as? [String: Any])?["initialDirectory"]
          as? String, result: result)
    case "resolveFolderBookmark":
      resolve(
        base64: (call.arguments as? [String: Any])?["bookmark"] as? String,
        result: result)
    case "ensureFolderAccess":
      let path = (call.arguments as? [String: Any])?["path"] as? String
      result(path.map { scopedFolders[$0] != nil } ?? false)
    default:
      // Only the three folder-grant methods live here. The channel's other
      // methods are mobile-only on the Dart side — `ensureInitialized` early
      // -returns for every non-mobile platform and the two all-files methods
      // short-circuit for non-Android — so answering them here would be
      // unreachable code pretending to be a contract.
      result(FlutterMethodNotImplemented)
    }
  }

  private func pick(initialDirectory: String?, result: @escaping FlutterResult) {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = true
    if let initialDirectory, !initialDirectory.isEmpty {
      panel.directoryURL = URL(fileURLWithPath: initialDirectory)
    }
    panel.begin { [weak self] response in
      guard let self else { return }
      guard response == .OK, let url = panel.url else {
        result(["status": "cancelled"])
        return
      }
      result(self.grantPayload(for: url))
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
      result(grantPayload(for: url))
    } catch {
      result(["status": "unavailable"])
    }
  }

  /// Takes the scope and mints a bookmark. The path it reports is an
  /// ordinary POSIX path — once the scope is open the sandbox extension
  /// applies process-wide, so the Dart save stack keeps using `dart:io`.
  private func grantPayload(for url: URL) -> [String: Any?] {
    if url.startAccessingSecurityScopedResource() {
      scopedFolders[url.path] = url
    }
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
    return ["status": "granted", "path": url.path, "bookmark": bookmark]
  }
}

class MainFlutterWindow: NSWindow {
  private let penStreamHandler = PenSidecarStreamHandler()

  /// Held as a property for the same reason `penStreamHandler` is: the
  /// channel keeps no strong reference, and this object owns the open
  /// security scopes.
  private let folderGrantHandler = FolderGrantHandler()

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
    storageChannel.setMethodCallHandler { [weak self] call, result in
      self?.folderGrantHandler.handle(call, result)
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
