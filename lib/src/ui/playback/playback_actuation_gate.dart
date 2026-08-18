import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show BoxHitTestResult, RenderProxyBox;
import 'package:flutter/services.dart'
    show HardwareKeyboard, KeyDownEvent, KeyEvent;

import 'canvas_playback_controller.dart';

/// 🚨★★★ T28-c — WHILE PLAYING, THE FIRST ACTUATION IS STOP, AND ONLY STOP.
/// D13 (2026-08-17) amends exactly ONE carve-out: a pointer actuation whose
/// TOPMOST hit surface belongs to the canvas panel NAVIGATES (pan/zoom keep
/// working during playback); every other actuation stops and is consumed,
/// unchanged.
///
/// 유저 2026-08-13: 「재생중에 **뭘 누르든 입력이 존재하면 정지**. 키보드든
/// 터치든 펜이든 **어떤식으로든** 입력 들어오면 정지」 · 「뭘 하든 정지만.
/// **입력 일 안함**」. 유저 2026-08-17 (D13): 「재생 중 팬·줌 가능」.
///
/// ★It is one law and it has one home. Asking each surface to check
/// "am I playing?" before doing its job is the shape D and T5/T13 each spent
/// a round removing: the surface added tomorrow forgets, and the rule quietly
/// becomes "most places". Here the editor is wrapped once and nothing
/// downstream knows this exists — the D13 hole is likewise the GATE's
/// (it asks whose surface the pointer actually lands on), never a
/// surface's own check.
///
/// 📐The D13 hole is decided by the HIT PATH, not by a rectangle: the
/// floating timeline overlaps the canvas panel's rect, so 「캔버스 위 좌표」
/// would have let a timeline press act during playback. The absorber
/// hit-tests the subtree and passes the event ONLY when the topmost target
/// sits inside [navigationRegionKey]'s subtree — the canvas panel: its
/// viewport gestures, zoom buttons and panbars (the chrome the playback
/// view renders inside on purpose, "so the panel chrome keeps working
/// during playback"). Drawing cannot leak through the hole: playback swaps
/// the panel's content, so the drawing surface is not mounted at all. A
/// plain TAP on the canvas picture stops playback — that is
/// `CanvasPlaybackView`'s own tap handler, awake again now that pointers
/// reach it (the pre-T28-c stop it always carried). KEYBOARD actuations
/// keep the stop law everywhere — bound zoom keys included: the hole is
/// pointer navigation only.
///
/// ✅유저 확정 — the two questions this had, both answered (⛔재론 금지):
/// 1. **「입력」 = actuation only**: key DOWN, pointer DOWN, wheel/zoom.
///    ⛔Hover and plain mouse movement are not: 「커서만 움직여도 재생이
///    죽으면 데스크톱에서 못 쓴다」. Nothing here listens to move or hover.
/// 2. **The actuation is CONSUMED.** A pen touching the timeline leaves no
///    seek; `,` and `.` move no frame. That is what the absorber and
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
/// all. The region verdict is computed per EVENT HIT TEST (a press, a wheel
/// notch, a hover test while playing) — never per played frame, and nothing
/// subscribes to layout.
///
/// 🚨🚨★★★AND THE SHAPE OF THIS TREE NEVER CHANGES, which is a second and
/// stronger requirement than not rebuilding (UI 08-14 #11). The gate used to
/// return the bare `child` when idle and wrap it in two widgets when playing.
/// Holding the same `child` INSTANCE is not enough: inserting ancestors moves
/// the subtree to a different position, Flutter finds a `Listener` where an
/// editor used to be, and it discards the whole element tree and inflates a
/// fresh one. Every [State] under this gate died on the first frame of
/// playback — the workspace's own included, which is why a folded timeline
/// sprang open the instant play was pressed and then folded again when the
/// saved layout was restored over the new state.
///
/// ⇒ The wrapper is ALWAYS mounted and only its flags move. A `Listener`
/// with null callbacks defers to its child, and the absorber that is not
/// absorbing is transparent, so the idle cost is two inert nodes and the
/// playing cost is a flag flip.
class PlaybackActuationGate extends StatefulWidget {
  const PlaybackActuationGate({
    super.key,
    required this.controller,
    required this.child,
    this.navigationRegionKey,
  });

  final CanvasPlaybackController controller;
  final Widget child;

  /// D13: the canvas panel's subtree key — pointer actuations whose
  /// topmost hit target lives inside it NAVIGATE instead of stopping.
  /// Null keeps the pure T28-c law (every actuation stops).
  final GlobalKey? navigationRegionKey;

  @override
  State<PlaybackActuationGate> createState() => _PlaybackActuationGateState();
}

class _PlaybackActuationGateState extends State<PlaybackActuationGate> {
  /// The absorber's per-event verdict, read by the stop handlers in the
  /// SAME event dispatch (hit test runs first, listeners after — single
  /// threaded, so the pair can never tear). One object for the widget's
  /// whole life: the render object writes it, the listeners read it.
  final _NavigationVerdict _verdict = _NavigationVerdict();

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

  RenderBox? _regionBox() {
    final render = widget.navigationRegionKey?.currentContext
        ?.findRenderObject();
    return render is RenderBox && render.attached ? render : null;
  }

  void _stopUnlessNavigated() {
    if (!widget.controller.isPlaying) {
      return;
    }
    if (_verdict.navigated) {
      // D13: the event's topmost surface was the canvas panel — it
      // navigates; the panel's own tap-to-stop covers the plain tap.
      return;
    }
    widget.controller.stop();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: widget.controller.isActiveListenable,
      child: widget.child,
      builder: (context, playing, child) => Listener(
        onPointerDown: playing ? (_) => _stopUnlessNavigated() : null,
        // Wheel and pinch-zoom arrive as signals, not downs, and the user
        // named them: 「휠/줌」.
        onPointerSignal: playing ? (_) => _stopUnlessNavigated() : null,
        // ★This is the 「입력 일 안함」 half. Without it the press would
        // stop playback AND land on whatever was under it. The D13 hole
        // and the stop above read ONE verdict — the absorber's — so
        // navigate-and-stop can never disagree about the same event.
        child: _NavigationHoleAbsorbPointer(
          absorbing: playing,
          regionBoxOf: _regionBox,
          verdict: _verdict,
          child: child,
        ),
      ),
    );
  }
}

/// The absorber's per-event answer: whether the last hit test (while
/// absorbing) passed the event through to the canvas panel.
class _NavigationVerdict {
  bool navigated = false;
}

/// [AbsorbPointer] with the D13 hole: while absorbing, an event whose
/// TOPMOST hit target sits inside the navigation region's subtree
/// hit-tests normally (the canvas panel navigates); everywhere else it
/// behaves exactly like an absorbing [AbsorbPointer] (claims the
/// position, reaches no descendant). The hit PATH decides, not a rect —
/// the floating timeline overlaps the canvas panel's rectangle, and a
/// press on it must keep the stop-and-consume law. Always mounted — only
/// the flag flips (the tree-shape law above).
class _NavigationHoleAbsorbPointer extends SingleChildRenderObjectWidget {
  const _NavigationHoleAbsorbPointer({
    required this.absorbing,
    required this.regionBoxOf,
    required this.verdict,
    super.child,
  });

  final bool absorbing;
  final RenderBox? Function() regionBoxOf;
  final _NavigationVerdict verdict;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderNavigationHoleAbsorbPointer(
        absorbing: absorbing,
        regionBoxOf: regionBoxOf,
        verdict: verdict,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderNavigationHoleAbsorbPointer renderObject,
  ) {
    renderObject
      ..absorbing = absorbing
      ..regionBoxOf = regionBoxOf
      ..verdict = verdict;
  }
}

class _RenderNavigationHoleAbsorbPointer extends RenderProxyBox {
  _RenderNavigationHoleAbsorbPointer({
    required this.absorbing,
    required this.regionBoxOf,
    required this.verdict,
  });

  /// Plain fields, like [RenderAbsorbPointer]'s flag: they only change
  /// hit-test behaviour — no markNeedsPaint/layout on update.
  bool absorbing;
  RenderBox? Function() regionBoxOf;
  _NavigationVerdict verdict;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!absorbing) {
      return super.hitTest(result, position: position);
    }
    verdict.navigated = false;
    final region = regionBoxOf();
    if (region != null) {
      final probe = BoxHitTestResult();
      if (super.hitTest(probe, position: position) &&
          _topTargetInside(probe, region)) {
        verdict.navigated = true;
        return super.hitTest(result, position: position);
      }
    }
    // RenderAbsorbPointer's exact shape: claim the position without
    // visiting descendants — the ancestor Listener still hears the down
    // (that is the stop), the editor below never does (that is the
    // 「입력 일 안함」 half).
    return size.contains(position);
  }

  /// Whether the probe's TOPMOST target (its first path entry — the
  /// deepest surface under the pointer) is the region box or one of its
  /// descendants. A bounded parent-chain walk per event, never per frame.
  static bool _topTargetInside(BoxHitTestResult probe, RenderBox region) {
    if (probe.path.isEmpty) {
      return false;
    }
    final target = probe.path.first.target;
    if (target is! RenderObject) {
      return false;
    }
    for (RenderObject? node = target; node != null; node = node.parent) {
      if (identical(node, region)) {
        return true;
      }
    }
    return false;
  }
}
