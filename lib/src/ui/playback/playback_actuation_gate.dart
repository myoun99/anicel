import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show HardwareKeyboard, KeyDownEvent, KeyEvent;

import 'canvas_playback_controller.dart';

/// 🚨★★★ T28-c — WHILE PLAYING, THE FIRST ACTUATION IS STOP, AND ONLY STOP.
///
/// 유저 2026-08-13: 「재생중에 **뭘 누르든 입력이 존재하면 정지**. 키보드든
/// 터치든 펜이든 **어떤식으로든** 입력 들어오면 정지」 · 「뭘 하든 정지만.
/// **입력 일 안함**」.
///
/// ★It is one law and it has one home. Asking each surface to check
/// "am I playing?" before doing its job is the shape D and T5/T13 each spent
/// a round removing: the surface added tomorrow forgets, and the rule quietly
/// becomes "most places". Here the editor is wrapped once and nothing
/// downstream knows this exists.
///
/// ✅유저 확정 — the two questions this had, both answered (⛔재론 금지):
/// 1. **「입력」 = actuation only**: key DOWN, pointer DOWN, wheel/zoom.
///    ⛔Hover and plain mouse movement are not: 「커서만 움직여도 재생이
///    죽으면 데스크톱에서 못 쓴다」. Nothing here listens to move or hover.
/// 2. **The actuation is CONSUMED.** A pen touching the canvas leaves no
///    stroke; `,` and `.` move no frame. That is what [AbsorbPointer] and
///    the handled key result are for — without them this would be "stop AND
///    do the thing", which is a different rule on every surface.
///
/// 📐Stopping stands where it stopped ([CanvasPlaybackController.stop]);
/// 「재생아닌상태가 일시정지상태나 다름없음」 only holds if it does.
///
/// 🚨KEY EVENTS DO NOT GO THROUGH THE TREE HERE, and that is not a shortcut
/// — a `Focus(onKeyEvent:)` cannot do this job. Key events dispatch from the
/// PRIMARY FOCUS outward, so a widget only sees them if it is an ancestor of
/// whatever holds focus. This gate is mounted inside the editor's own
/// `FocusScope`, and with no field focused the scope IS the primary focus —
/// an ancestor of the gate, which would therefore never be consulted at all.
/// Anything nested deeper (a text field, a canvas focus node) would also
/// beat it. [HardwareKeyboard]'s handler list runs BEFORE focus dispatch and
/// returning true stops the message there, which is the only position from
/// which the actuation can be EATEN rather than merely followed.
///
/// ⚠️PERFORMANCE: it listens to [CanvasPlaybackController.isActiveListenable]
/// and NOT to the controller itself. The controller notifies once per played
/// frame; rebuilding a wrapper around the whole editor at fps is the exact
/// mistake the playback view's own comments were written to prevent. The
/// editor subtree rides through as `child`, so it is never rebuilt here at
/// all.
class PlaybackActuationGate extends StatefulWidget {
  const PlaybackActuationGate({
    super.key,
    required this.controller,
    required this.child,
  });

  final CanvasPlaybackController controller;
  final Widget child;

  @override
  State<PlaybackActuationGate> createState() => _PlaybackActuationGateState();
}

class _PlaybackActuationGateState extends State<PlaybackActuationGate> {
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  /// Registered for the gate's whole life, with the guard INSIDE.
  /// Subscribing and unsubscribing as playback comes and goes would make
  /// the handler's presence a second piece of state to keep true.
  ///
  /// ⚠️Returning true does NOT stop the key reaching the focus tree —
  /// measured, not assumed: Flutter dispatches the key message either way.
  /// So this handler owns only half the law, the STOP; the app's action
  /// funnel owns the other half by declining to run a bound action in the
  /// same beat. A key with no binding has nothing to eat.
  bool _onKey(KeyEvent event) {
    if (!widget.controller.isPlaying) {
      return false;
    }
    if (event is! KeyDownEvent) {
      // ⛔Key UP and repeat are not actuations. Eating the up of a key whose
      // down started playback would swallow half of an event the app never
      // saw the beginning of.
      return false;
    }
    widget.controller.stop();
    return true;
  }

  void _stop() {
    if (widget.controller.isPlaying) {
      widget.controller.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: widget.controller.isActiveListenable,
      child: widget.child,
      builder: (context, playing, child) {
        if (!playing) {
          return child!;
        }
        return Listener(
          onPointerDown: (_) => _stop(),
          // Wheel and pinch-zoom arrive as signals, not downs, and the user
          // named them: 「휠/줌」.
          onPointerSignal: (_) => _stop(),
          // ★This is the 「입력 일 안함」 half. Without it the press would
          // stop playback AND land on whatever was under it.
          child: AbsorbPointer(child: child),
        );
      },
    );
  }
}
