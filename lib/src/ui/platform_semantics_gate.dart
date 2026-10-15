import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../native/windows_screen_reader.dart';

/// The channel the Windows runner says a screen reader came or went on
/// (`windows/runner/flutter_window.cpp`, `WM_SETTINGCHANGE` for
/// `SPI_SETSCREENREADER`) — what [PlatformSemanticsGate] asks again on.
const String screenReaderChannel = 'anicel/screen_reader';

/// 🚨★★★**ON WINDOWS THE PLATFORM'S ACCESSIBILITY REQUEST IS TAKEN ONLY
/// WHILE A SCREEN READER RUNS** — in every build (유저 2026-10-15, I-57-Q3:
/// 「스크린리더가 켜져 있을 때만 받는다 — 릴리즈도」), and in a debug build
/// not even then (유저 2026-09-24, `debug-frames-pay-a-semantics-walk-Q1`:
/// 「디버그에서는 받지 않는다」).
///
/// Windows turns the tree on for any Flutter window whatever speaks UI
/// Automation asks — an IME does, on this machine and on the Surface Pro
/// 11, with no screen reader anywhere — and a tree that is on is rebuilt
/// wherever a frame changed it and sent to Windows, read or not. 🔬In
/// release (10-15, the user's project): 0.72ms of a drawn playback frame's
/// 1.3–1.7ms of UI work, 1.4–3ms of a cut crossing's 6.8–8.6ms. A debug
/// build pays far more: `PipelineOwner.flushSemantics`'s asserts walk the
/// whole tree every frame — 116.6ms over twelve pen moves against 3.5ms in
/// profile (09-24), 8.4ms of a playback frame on the Surface Pro 11 (10-10).
/// Every other platform asks only for the assistive technology it runs, and
/// is answered as it always was.
///
/// What counts as a screen reader is the flag Narrator, NVDA and JAWS raise
/// ([windowsScreenReaderRunning]); it is asked again whenever the runner
/// says it changed ([screenReaderChannel]). ⚠️Voice Access, Magnifier's
/// focus following and UI Automation tools do not read the app — the cost
/// the answer took. To read a debug build with a screen reader, start it
/// with `ANICEL_DEBUG_SEMANTICS=1`.
///
/// 🚨**THE GATE IS THE QUESTION THE FRAMEWORK ASKS, NOT THE PLATFORM'S
/// CALLBACK.** A pipeline owner keeps a semantics owner only while
/// [semanticsEnabled] answers yes, so the request is refused whenever it
/// came. ↩️Until 2026-10-10 the binding emptied `onSemanticsEnabledChanged`
/// as it started (19e0bab1c), on the belief that no request could come
/// sooner — the runner shows the window after the first frame. But the
/// framework reads the platform's flag AS THE BINDING IS MADE, and on the
/// Surface Pro 11 the flag is up at the first line of `main` (the real app,
/// 2026-10-10: platform on at start · binding on · callback empty).
mixin PlatformSemanticsGate on ServicesBinding, SemanticsBinding {
  @override
  bool get semanticsEnabled => !_refuses && super.semanticsEnabled;

  /// Decided the first time the framework asks — which it does while the
  /// binding is still being made, before any `initInstances` body runs —
  /// and again each time a screen reader comes or goes.
  late bool _refuses = _decide();

  /// What the request is taken by ([refusesPlatformSemantics]): this
  /// build, this platform, and whether a screen reader runs. A test binding
  /// hands its own.
  @protected
  SemanticsGateInputs get semanticsGateInputs => (
    debugBuild: kDebugMode,
    onWindows: Platform.isWindows,
    environment: Platform.environment,
    screenReader: windowsScreenReaderRunning,
  );

  bool _decide() {
    final inputs = semanticsGateInputs;
    return refusesPlatformSemantics(
      debugBuild: inputs.debugBuild,
      onWindows: inputs.onWindows,
      environment: inputs.environment,
      screenReader: inputs.screenReader(),
    );
  }

  /// Everything that follows [semanticsEnabled] — the pipeline owners, and
  /// the binding's own word to the engine — told again when the gate turns:
  /// the framework tells them only when its own handles change.
  final List<VoidCallback> _followers = <VoidCallback>[];

  @override
  void addSemanticsEnabledListener(VoidCallback listener) {
    _followers.add(listener);
    super.addSemanticsEnabledListener(listener);
  }

  @override
  void removeSemanticsEnabledListener(VoidCallback listener) {
    _followers.remove(listener);
    super.removeSemanticsEnabledListener(listener);
  }

  @override
  void initInstances() {
    super.initInstances();
    defaultBinaryMessenger.setMessageHandler(screenReaderChannel, (_) async {
      screenReaderChanged();
      return null;
    });
  }

  /// A screen reader came or went: whether the platform's request is taken
  /// is decided again, and whatever follows [semanticsEnabled] is told when
  /// the answer turned.
  void screenReaderChanged() {
    final refused = _refuses;
    _refuses = _decide();
    if (_refuses == refused) {
      return;
    }
    for (final follower in List<VoidCallback>.of(_followers)) {
      follower();
    }
  }
}

/// What [refusesPlatformSemantics] decides from — see
/// [PlatformSemanticsGate.semanticsGateInputs].
typedef SemanticsGateInputs = ({
  bool debugBuild,
  bool onWindows,
  Map<String, String> environment,
  bool Function() screenReader,
});

/// Whether a build turns the platform's accessibility request away — see
/// [PlatformSemanticsGate].
bool refusesPlatformSemantics({
  required bool debugBuild,
  required bool onWindows,
  required Map<String, String> environment,
  required bool screenReader,
}) =>
    onWindows &&
    (debugBuild
        ? environment['ANICEL_DEBUG_SEMANTICS'] != '1'
        : !screenReader);
