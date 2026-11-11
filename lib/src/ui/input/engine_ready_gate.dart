import 'package:flutter/widgets.dart';

import '../../native/app_kernels_ahead.dart';
import '../shortcuts/editor_key_funnel.dart';

/// 🚨THE EDITOR TAKES NO INPUT WHILE THE APP GETS ITS ENGINE READY
/// ([appEngineGetsReady]).
///
/// 🗣️gpu-canonical-store-Q15 (유저 2026-11-11): 「준비가 끝난 뒤에 그림을
/// 띄운다 — 그때까지 고리」 · 「애초에 타임라인같은거도 포함해서 고리띄우고
/// 모든 조작 막음」 — till the kernels a hand needs are compiled, a press
/// that needed one stopped the whole app for as long as its compile took
/// (🔬Surface Pro 11, 11-11: a lift 0.47–1.03 s, a blur stroke 0.78 s).
///
/// One law with one home, as playback's is (`PlaybackActuationGate`): the
/// editor is wrapped once and nothing under it asks 「준비됐나」. Its two
/// halves stand here — every bound key and held key stands down ([road],
/// [EditorKeyFunnel.enabled]) and no pointer reaches what is under it, a
/// touch shortcut's fingers included — and what runs into the action funnel
/// past both, the pencil's double tap, is turned back there by the same
/// fact (`HomePage._invokeAction`).
///
/// ⛔Not the windows the app opens over the editor — a launch's first
/// settings, its notice, a file handed to it: a route is no child of this,
/// and each is the app's own question, answered meanwhile.
///
/// The tree it stands in keeps one shape: both halves are always mounted
/// and only their flags move (`PlaybackActuationGate` has why).
class EngineReadyGate extends StatelessWidget {
  const EngineReadyGate({super.key, required this.road, required this.child});

  /// The shell's key road, laid here ([EditorKeyFunnel]).
  final EditorKeyRoad road;

  final Widget child;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: appEngineGetsReady,
    builder: (context, getsReady, child) => EditorKeyFunnel(
      road: road,
      enabled: !getsReady,
      child: AbsorbPointer(absorbing: getsReady, child: child),
    ),
    child: child,
  );
}
