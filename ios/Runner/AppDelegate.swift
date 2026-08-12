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
  private var pickerDelegate: DocumentPickerDelegate?
  private var pendingPickResult: FlutterResult?

  /// Items this process currently holds a security scope on, keyed by
  /// path — FILES as well as folders since PICK-5. Nothing removes entries:
  /// a scope is cheap, the app grants a handful per session, and stopping
  /// one mid-session would pull the floor out from under an open project's
  /// autosave — which writes a sidecar beside the file every five minutes.
  private var scopedItems: [String: URL] = [:]

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
      case "pickFiles":
        let arguments = call.arguments as? [String: Any]
        self.pickFiles(
          utis: arguments?["utis"] as? [String] ?? [],
          allowMultiple: arguments?["allowMultiple"] as? Bool ?? false,
          result: result)
      case "resolveBookmark":
        let arguments = call.arguments as? [String: Any]
        self.resolveBookmark(
          base64: arguments?["bookmark"] as? String, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  // MARK: - PICK-2/PICK-5: path grants

  /// Presents the system document picker in FOLDER mode.
  ///
  /// A folder rather than a file because the security scope lands on exactly
  /// what was picked, and a project is a file plus a sibling `.assets/`
  /// directory plus an autosave sidecar. Picking the file would grant the one
  /// item that cannot be saved.
  ///
  /// This is also the only surface on iPadOS through which Dropbox and other
  /// providers are reachable at all: they are File Provider extensions, and
  /// no API lets a third-party app enumerate them. (Google Drive declines
  /// folder mode outright — measured on iOS 26.5.2 — which is why file mode
  /// below is the one that reaches it.)
  private func pickProjectFolder(result: @escaping FlutterResult) {
    let picker: UIDocumentPickerViewController
    if #available(iOS 14.0, *) {
      picker = UIDocumentPickerViewController(
        forOpeningContentTypes: [UTType.folder], asCopy: false)
    } else {
      // iOS 13 predates UTType. kUTTypeFolder's identifier is this string.
      picker = UIDocumentPickerViewController(
        documentTypes: ["public.folder"], in: .open)
    }
    present(picker: picker, allowMultiple: false, result: result)
  }

  /// PICK-5: presents the picker in FILE mode, **in place**.
  ///
  /// The whole reason this exists rather than `file_selector`: that plugin
  /// opens the picker in `.import` mode, which COPIES the chosen file into
  /// the app sandbox and hands back the copy's path. A media asset imported
  /// "by reference" would then reference a temporary duplicate — the
  /// original is never touched, no bookmark can be minted for it (the app
  /// never sees its URL), and the copy is swept when the OS reclaims tmp.
  ///
  /// `asCopy: false` is the whole fix: the file stays where the user put it,
  /// the app receives its real URL, and a security-scoped bookmark can be
  /// minted from that URL so the reference survives a relaunch.
  private func pickFiles(
    utis: [String], allowMultiple: Bool, result: @escaping FlutterResult
  ) {
    // An empty filter means "anything a document can be". `public.data` is
    // the conformance every file answers to; without it iOS greys out the
    // entire browser and the user cannot pick at all.
    let identifiers = utis.isEmpty ? ["public.data"] : utis
    let picker: UIDocumentPickerViewController
    if #available(iOS 14.0, *) {
      // An identifier the system does not know maps to nil rather than
      // throwing — and a picker built from an EMPTY type list shows nothing,
      // so the fallback matters more than it looks.
      let types = identifiers.compactMap { UTType($0) }
      picker = UIDocumentPickerViewController(
        forOpeningContentTypes: types.isEmpty ? [UTType.data] : types,
        asCopy: false)
    } else {
      picker = UIDocumentPickerViewController(documentTypes: identifiers, in: .open)
    }
    present(picker: picker, allowMultiple: allowMultiple, result: result)
  }

  /// The one place a picker reaches the screen. Shared so the folder and file
  /// modes cannot drift apart on the two things that are easy to get wrong:
  /// refusing a concurrent request, and reporting a presentation that never
  /// took.
  private func present(
    picker: UIDocumentPickerViewController, allowMultiple: Bool,
    result: @escaping FlutterResult
  ) {
    // REFUSE a second request rather than replacing the first. Replacing it
    // would drop the only strong reference to delegate #1 — the picker's own
    // `delegate` is weak — leaving picker #1 on screen, unable to report
    // anything, and `topViewController()` would then try to present picker #2
    // ON TOP of it. On the realistic trigger (a fast double-tap while #1 is
    // still animating in) UIKit refuses the presentation, no callback ever
    // fires, and the Dart future never completes for the life of the process.
    if pendingPickResult != nil {
      result(["status": "cancelled"])
      return
    }
    pendingPickResult = result

    let delegate = DocumentPickerDelegate(owner: self)
    pickerDelegate = delegate
    picker.delegate = delegate
    picker.allowsMultipleSelection = allowMultiple

    guard let presenter = topViewController(), presenter.presentedViewController == nil
    else {
      finishPick(["status": "unavailable"])
      return
    }
    // A non-nil completion so a presentation that never took is an ERROR
    // rather than a future that hangs. UIKit calls this after the animation;
    // if the picker is not on screen by then, nothing else will report.
    presenter.present(picker, animated: true) { [weak self, weak picker] in
      guard let self, picker?.presentingViewController == nil else { return }
      self.finishPick(["status": "unavailable"])
    }
  }

  /// Called by the delegate. Central so both the pick and the cancel paths
  /// clear the same two properties.
  fileprivate func finishPick(_ payload: [String: Any?]) {
    let pending = pendingPickResult
    pendingPickResult = nil
    pickerDelegate = nil
    pending?(payload)
  }

  /// Takes the scope, mints a bookmark, and reports the POSIX path.
  ///
  /// The path is the point. Once the scope is open the sandbox extension
  /// applies to the underlying vnode for the whole process, so Dart's
  /// `dart:io` writes inside this tree with no further ceremony — the save
  /// stack does not learn a new API, it just works where it did not before.
  fileprivate func grantPayload(for url: URL, requiringScope: Bool = false)
    -> [String: Any?]
  {
    let opened = url.startAccessingSecurityScopedResource()
    // A bookmark for a provider that signed out, or a volume no longer
    // mounted, RESOLVES without throwing and then refuses to open its scope.
    // Reporting that as "granted" hands Dart a path every write will bounce:
    // the project opens, the sidecar fires five minutes later, and each
    // `dart:io` write dies inside a try that was written for a folder that
    // was supposed to be writable. The status vocabulary already has the
    // right word for it.
    if requiringScope && !opened {
      return ["status": "unavailable"]
    }
    // Recorded whether or not a scope was needed — holding the URL is what
    // keeps a real scope alive, and a picked (as opposed to resolved) URL
    // does not always report one.
    scopedItems[url.path] = url
    var bookmark: String?
    do {
      // `.minimalBookmark` is the iOS spelling; `.withSecurityScope` is
      // macOS-only and throws here.
      let data = try url.bookmarkData(
        options: .minimalBookmark, includingResourceValuesForKeys: nil,
        relativeTo: nil)
      bookmark = data.base64EncodedString()
    } catch {
      // An item with no bookmark still works for this session; only the
      // stored grant is poorer for it.
      bookmark = nil
    }
    // ONE shape for one and for many. A picker that can return several URLs
    // and one that cannot would otherwise hand Dart two payload dialects,
    // and the channel has no compiler to notice when one of the three
    // platform runners is left speaking the old one.
    return ["status": "granted", "items": [["path": url.path, "bookmark": bookmark]]]
  }

  /// The same, for a pick that may have returned several URLs.
  ///
  /// A URL that fails to grant is DROPPED rather than failing the batch: the
  /// user picked five files and four of them work, so importing four beats
  /// reporting nothing. All five failing is still `unavailable`.
  fileprivate func grantPayload(for urls: [URL]) -> [String: Any?] {
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

  /// Reopens a granted item from a stored bookmark — a file since PICK-5,
  /// a folder before it. `URL(resolvingBookmarkData:)` does not distinguish
  /// them, so neither does this.
  ///
  /// The resolved path may DIFFER from the one that was bookmarked — that is
  /// the feature. A bookmark tracks the item, so a project the user moved
  /// or renamed is followed rather than lost.
  private func resolveBookmark(base64: String?, result: @escaping FlutterResult) {
    guard let base64, let data = Data(base64Encoded: base64) else {
      result(["status": "unavailable"])
      return
    }
    var isStale = false
    do {
      let url = try URL(
        resolvingBookmarkData: data, options: [], relativeTo: nil,
        bookmarkDataIsStale: &isStale)
      // A stale bookmark still resolves; it just wants reminting. The payload
      // carries the FRESH bookmark and `_openRecent` stores it, so an entry
      // that keeps being opened keeps its token young.
      result(grantPayload(for: url, requiringScope: true))
    } catch {
      // Provider reinstalled, account changed, folder deleted. The caller
      // keeps the row and offers to reconnect rather than dropping it.
      result(["status": "unavailable"])
    }
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
    // Reaches for `topViewController()` rather than `window` because this
    // app declares a `UIApplicationSceneManifest`: under the scene lifecycle
    // the window belongs to the scene delegate and `FlutterAppDelegate.window`
    // is nil, so the old `window?.rootViewController` guard never passed and
    // the Pencil double-tap silently never installed. The picker code needed
    // the same fallback, so they now share it.
    guard !pencilInteractionInstalled,
      let view = topViewController()?.view
    else { return }
    let interaction = UIPencilInteraction()
    interaction.delegate = self
    view.addInteraction(interaction)
    pencilInteractionInstalled = true
  }

  /// Pencil double-tap: forward the SYSTEM preference so Dart maps it
  /// the way the user configured the Pencil globally.
  func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
    let preferred = UIPencilInteraction.preferredTapAction
    let action: String
    // `.showInkAttributes` arrived with Apple Pencil Pro and is declared
    // `API_AVAILABLE(ios(17.5))`. Naming an unavailable enum element in a
    // switch PATTERN is a compile ERROR in Swift, not a warning, and the
    // deployment target here is 13.0 — so this case has to be tested
    // outside the switch or `AppDelegate.swift` does not build at all.
    if #available(iOS 17.5, *), preferred == .showInkAttributes {
      action = "showInkAttributes"
    } else {
      switch preferred {
      case .switchEraser: action = "switchEraser"
      case .switchPrevious: action = "switchPrevious"
      case .showColorPalette: action = "showColorPalette"
      case .ignore: action = "ignore"
      @unknown default: action = "switchEraser"
      }
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
private final class DocumentPickerDelegate: NSObject, UIDocumentPickerDelegate {
  init(owner: AppDelegate) {
    self.owner = owner
  }

  private weak var owner: AppDelegate?

  func documentPicker(
    _ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]
  ) {
    guard let owner else { return }
    // Every URL, not just the first: file mode allows multiple selection and
    // dropping the rest here would look like the picker ignoring the user.
    owner.finishPick(owner.grantPayload(for: urls))
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    owner?.finishPick(["status": "cancelled"])
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
