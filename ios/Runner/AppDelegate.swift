import Flutter
import UIKit

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
      default:
        result(FlutterMethodNotImplemented)
      }
    }
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
