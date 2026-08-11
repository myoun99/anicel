import Flutter
import UIKit
import UniformTypeIdentifiers

/// Anicel pen features (pen program, PEN-5 — iPadOS).
///
/// Apple Pencil classification/pressure already arrive natively through
/// Flutter (UITouch .pencil → stylus, hover included on M2/Pro); the
/// reinforcement here is the FEATURE layer the embedder has no channel
/// for: **UIPencilInteraction** — the Pencil double-tap — forwarded to
/// Dart on 'qa_pen/ios' with the SYSTEM-preferred action, so the app
/// honors the user's global Pencil setting.
///
/// UNVERIFIED-ON-DEVICE: authored on the Windows workstation; needs one
/// iPad build + a Pencil pass. Runner-owned — no plugin registrant
/// churn.
@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate,
  UIPencilInteractionDelegate
{
  private var penChannel: FlutterMethodChannel?
  private var pencilInteractionInstalled = false

  /// PICK-2 state. All three of these have to be PROPERTIES rather than
  /// locals: `UIDocumentPickerViewController` keeps only a weak reference to
  /// its delegate, the Flutter result outlives the call that created it, and
  /// a security scope stops the moment its URL is released.
  private var folderPickerDelegate: FolderPickerDelegate?
  private var pendingFolderResult: FlutterResult?

  /// Folders this process currently holds a security scope on, keyed by
  /// path. Nothing removes entries: a scope is cheap, the app grants a
  /// handful per session, and stopping one mid-session would pull the floor
  /// out from under an open project's autosave — which writes a sidecar
  /// beside the file every five minutes.
  private var scopedFolders: [String: URL] = [:]

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let result = super.application(
      application, didFinishLaunchingWithOptions: launchOptions)
    installPencilInteractionIfPossible()
    return result
  }

  override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)
    // The root view can attach after launch — retry until installed.
    installPencilInteractionIfPossible()
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "QaPen")
    penChannel = FlutterMethodChannel(
      name: "qa_pen/ios", binaryMessenger: registrar!.messenger())
    // SAVE-1d: the storage channel (compile-unverified on this machine,
    // like the pen sidecars): the app documents home for the save/open
    // surfaces. Folder security-scope bookmarks join with the real iPad
    // validation pass.
    let storageRegistrar = engineBridge.pluginRegistry.registrar(forPlugin: "QaStorage")
    let storageChannel = FlutterMethodChannel(
      name: "qa_storage", binaryMessenger: storageRegistrar!.messenger())
    storageChannel.setMethodCallHandler { call, result in
      switch call.method {
      case "appDocumentsPath":
        let documents = FileManager.default.urls(
          for: .documentDirectory, in: .userDomainMask
        ).first!
        result(documents.appendingPathComponent("Anicel").path)
      case "isAllFilesAccessGranted":
        // iOS sandboxing: the app folder is always writable; foreign
        // folders arrive per-document via pickers.
        result(true)
      case "requestAllFilesAccess":
        result(nil)
      case "pickProjectFolder":
        self.pickProjectFolder(result: result)
      case "resolveFolderBookmark":
        let arguments = call.arguments as? [String: Any]
        self.resolveFolderBookmark(
          base64: arguments?["bookmark"] as? String, result: result)
      case "ensureFolderAccess":
        let arguments = call.arguments as? [String: Any]
        result(self.ensureFolderAccess(path: arguments?["path"] as? String))
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  // MARK: - PICK-2: folder grants

  /// Presents the system document picker in FOLDER mode.
  ///
  /// A folder rather than a file because the security scope lands on exactly
  /// what was picked, and a project is a file plus a sibling `.assets/`
  /// directory plus an autosave sidecar. Picking the file would grant the one
  /// item that cannot be saved.
  ///
  /// This is also the only surface on iPadOS through which Google Drive and
  /// Dropbox are reachable at all: they are File Provider extensions, and no
  /// API lets a third-party app enumerate them.
  private func pickProjectFolder(result: @escaping FlutterResult) {
    // A second request while one is open answers the first rather than
    // leaking it — the same discipline MainActivity uses for the microphone.
    if let stale = pendingFolderResult {
      stale(["status": "cancelled"])
    }
    pendingFolderResult = result

    let picker: UIDocumentPickerViewController
    if #available(iOS 14.0, *) {
      picker = UIDocumentPickerViewController(
        forOpeningContentTypes: [UTType.folder], asCopy: false)
    } else {
      // iOS 13 predates UTType. kUTTypeFolder's identifier is this string.
      picker = UIDocumentPickerViewController(
        documentTypes: ["public.folder"], in: .open)
    }
    let delegate = FolderPickerDelegate(owner: self)
    folderPickerDelegate = delegate
    picker.delegate = delegate
    picker.allowsMultipleSelection = false

    guard let presenter = topViewController() else {
      finishFolderPick(["status": "unavailable"])
      return
    }
    presenter.present(picker, animated: true, completion: nil)
  }

  /// Called by the delegate. Central so both the pick and the cancel paths
  /// clear the same two properties.
  fileprivate func finishFolderPick(_ payload: [String: Any?]) {
    let pending = pendingFolderResult
    pendingFolderResult = nil
    folderPickerDelegate = nil
    pending?(payload)
  }

  /// Takes the scope, mints a bookmark, and reports the POSIX path.
  ///
  /// The path is the point. Once the scope is open the sandbox extension
  /// applies to the underlying vnode for the whole process, so Dart's
  /// `dart:io` writes inside this tree with no further ceremony — the save
  /// stack does not learn a new API, it just works where it did not before.
  fileprivate func grantPayload(for url: URL) -> [String: Any?] {
    let opened = url.startAccessingSecurityScopedResource()
    if opened {
      scopedFolders[url.path] = url
    }
    var bookmark: String?
    do {
      // `.minimalBookmark` is the iOS spelling; `.withSecurityScope` is
      // macOS-only and throws here.
      let data = try url.bookmarkData(
        options: .minimalBookmark, includingResourceValuesForKeys: nil,
        relativeTo: nil)
      bookmark = data.base64EncodedString()
    } catch {
      // A folder with no bookmark still works for this session; only the
      // recent-projects entry is poorer for it.
      bookmark = nil
    }
    return ["status": "granted", "path": url.path, "bookmark": bookmark]
  }

  /// Reopens a folder from a stored bookmark.
  ///
  /// The resolved path may DIFFER from the one that was bookmarked — that is
  /// the feature. A bookmark tracks the folder, so a project the user moved
  /// or renamed is followed rather than lost.
  private func resolveFolderBookmark(base64: String?, result: @escaping FlutterResult) {
    guard let base64, let data = Data(base64Encoded: base64) else {
      result(["status": "unavailable"])
      return
    }
    var isStale = false
    do {
      let url = try URL(
        resolvingBookmarkData: data, options: [], relativeTo: nil,
        bookmarkDataIsStale: &isStale)
      // A stale bookmark still resolves; it just wants reminting. Report the
      // grant and let the caller store the fresh bookmark from the payload.
      result(grantPayload(for: url))
    } catch {
      // Provider reinstalled, account changed, folder deleted. The caller
      // keeps the row and offers to reconnect rather than dropping it.
      result(["status": "unavailable"])
    }
  }

  private func ensureFolderAccess(path: String?) -> Bool {
    guard let path else { return false }
    if let url = scopedFolders[path] {
      return FileManager.default.fileExists(atPath: url.path)
    }
    return false
  }

  /// The presenting view controller.
  ///
  /// `window` is unreliable under the UIScene lifecycle this app adopts, so
  /// the connected scenes are the fallback rather than the other way round.
  private func topViewController() -> UIViewController? {
    var root = window?.rootViewController
    if root == nil {
      for scene in UIApplication.shared.connectedScenes {
        guard let windowScene = scene as? UIWindowScene else { continue }
        for candidate in windowScene.windows where candidate.isKeyWindow {
          root = candidate.rootViewController
          break
        }
        if root != nil { break }
      }
    }
    while let presented = root?.presentedViewController {
      root = presented
    }
    return root
  }

  private func installPencilInteractionIfPossible() {
    guard !pencilInteractionInstalled,
      let view = window?.rootViewController?.view
    else { return }
    let interaction = UIPencilInteraction()
    interaction.delegate = self
    view.addInteraction(interaction)
    pencilInteractionInstalled = true
  }

  /// Pencil double-tap: forward the SYSTEM preference so Dart maps it
  /// the way the user configured the Pencil globally.
  func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
    let action: String
    switch UIPencilInteraction.preferredTapAction {
    case .switchEraser: action = "switchEraser"
    case .switchPrevious: action = "switchPrevious"
    case .showColorPalette: action = "showColorPalette"
    case .showInkAttributes: action = "showInkAttributes"
    case .ignore: action = "ignore"
    @unknown default: action = "switchEraser"
    }
    penChannel?.invokeMethod("pencilTap", arguments: ["action": action])
  }
}

/// PICK-2: the document picker's delegate.
///
/// A separate object rather than a conformance on `AppDelegate` because
/// `UIDocumentPickerViewController.delegate` is WEAK — an inline conformance
/// would work by accident (the app delegate happens to live forever) and stop
/// working the day this moves. The owner holds it for exactly as long as a
/// pick is open.
///
/// It lives in this file rather than its own for the reason spelled out
/// below `AnicelViewController`: the Xcode project lists its sources
/// explicitly, so a new .swift would compile-silently-not-exist.
///
/// UNVERIFIED-ON-DEVICE: authored on the Windows workstation like the Pencil
/// interaction. Needs one iPad pass — and the load-bearing question that pass
/// answers is whether `dart:io` can write inside the granted scope, because
/// the entire folder-grant design rests on it.
private final class FolderPickerDelegate: NSObject, UIDocumentPickerDelegate {
  init(owner: AppDelegate) {
    self.owner = owner
  }

  private weak var owner: AppDelegate?

  func documentPicker(
    _ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]
  ) {
    guard let owner else { return }
    guard let url = urls.first else {
      owner.finishFolderPick(["status": "cancelled"])
      return
    }
    owner.finishFolderPick(owner.grantPayload(for: url))
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    owner?.finishFolderPick(["status": "cancelled"])
  }
}

/// The app's Flutter view controller, subclassed for one reason: to give
/// up the home indicator.
///
/// `SystemChrome.setEnabledSystemUIMode(.immersiveSticky)` hides the status
/// bar on iOS but cannot touch the home indicator — that answer belongs to
/// UIKit, and only a view controller can give it. Procreate and Callipeg
/// both take this band back; on a drawing app the bottom of the screen is
/// the bottom dock, not a place to leave a system affordance sitting over
/// the work.
///
/// `prefersHomeIndicatorAutoHidden` is a REQUEST, not a removal: iOS fades
/// the indicator once the hand rests and brings it straight back when the
/// user reaches for it. Apple allows no more than that, so this is the
/// whole of what "hide the bottom bar" can mean on iPadOS.
///
/// It lives in this file rather than its own because the Xcode project
/// lists sources explicitly (no synchronized folder group) — a new .swift
/// would need a hand-written pbxproj entry to be compiled at all.
///
/// UNVERIFIED-ON-DEVICE: authored on the Windows workstation like the
/// Pencil interaction above; needs one iPad build to confirm the
/// storyboard picks this class up.
class AnicelViewController: FlutterViewController {
  override var prefersHomeIndicatorAutoHidden: Bool {
    return true
  }

  /// The Dart-side immersive mode is the primary switch for the status
  /// bar; saying it here too keeps the two from arguing across rotations
  /// and app switches.
  override var prefersStatusBarHidden: Bool {
    return true
  }
}
