import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../../models/canvas_viewport.dart';
import '../../models/app_input_settings.dart';
import '../input/control_press_claim.dart';
import '../input/value_control_pointers.dart';
import '../input/wheel_law.dart';
import '../../models/viewport_point.dart';
import 'canvas_press.dart';
import 'canvas_touch_contacts.dart';
import 'canvas_zoom_scale.dart';
import 'flip_hud_controller.dart';

/// Viewport pan/zoom input for the canvas panel, independent of what the
/// viewport currently shows (interactive canvas, blank paper, playback).
/// Living at the panel level is what keeps navigation working on timeline
/// positions without an editable frame.
///
/// - A press [canvasPressPans] calls a pan drags the view: the primary
///   button while the 「이동」 key is held (I-15 — Space by default), or a
///   button mapped to the pan (PEN-7a) — one pan, held from a key or a
///   button.
/// - Scroll wheel zooms around the cursor — no modifier key by design.
/// - Trackpad pinch/pan gestures zoom around the focal point and pan
///   (mouse-less desktops; the same events arrive from some touchpads).
/// - Two touch fingers pinch-zoom around the focal point and pan
///   (tablet/touch-screen navigation). One finger stays reserved for
///   drawing — the interactive canvas cancels its stroke when the second
///   finger lands, so a quick pinch never leaves marks.
///
/// While a brush stroke is in progress ([strokeActive]) new pans and wheel
/// zooms are ignored so a stray wheel tick cannot re-anchor the stroke
/// mid-draw. Two-finger touch navigation deliberately bypasses that gate:
/// the second finger IS the cancel-and-navigate signal.
class CanvasViewportGestureLayer extends StatefulWidget {
  /// One flip step per this many pixels along the locked axis — and, since
  /// H30, the distance a one-finger group must travel before it is DECIDED.
  ///
  /// Public because a test that drives a real flip has to reach it, and a
  /// literal in the test would go stale the moment this moves.
  static const double flipStepExtent = 48;

  const CanvasViewportGestureLayer({
    super.key,
    required this.viewport,
    required this.onViewportChanged,
    this.strokeActive = false,
    this.touchLocked = false,
    this.rotationEnabled = true,
    this.oneFingerAction,
    this.onInvokeAction,
    this.onBrushSizeDragStart,
    this.onBrushSizeDragUpdate,
    this.onBrushSizeDragEnd,
    this.flipHud,
    required this.child,
  });

  final CanvasViewport viewport;
  final ValueChanged<CanvasViewport> onViewportChanged;

  /// PEN-7b: the FLIP slot dispatches registry actions (drawing/frame
  /// steps, layer up/down) through the shell's one action funnel — the
  /// same ids the arrow keys fire.
  final void Function(String actionId)? onInvokeAction;

  /// PEN-7b: the BRUSH-SIZE slot (vertical drag; [snap] while the
  /// modifier finger is down). The host owns the actual size math — the
  /// layer only reports the cumulative upward delta.
  final VoidCallback? onBrushSizeDragStart;
  final void Function(double upwardDelta, {required bool snap})?
  onBrushSizeDragUpdate;
  final VoidCallback? onBrushSizeDragEnd;

  /// The flip HUD's state, if the host shows one. This layer only REPORTS
  /// to it — when the axis locked, that a step has landed, when the
  /// gesture ended. Where the step landed is the session's answer, which
  /// the HUD reads for itself; deciding it here would make the HUD a
  /// second movement rule.
  final FlipHudController? flipHud;

  /// True while the user is drawing; blocks new viewport gestures.
  final bool strokeActive;

  /// True while a transform handle is being dragged: touch is inert, so a
  /// palm landing mid-transform neither pans nor pinches.
  ///
  /// Separate from [strokeActive] because touch deliberately bypasses that
  /// one — the second finger IS the cancel-and-navigate signal for a
  /// stroke. A transform is the exception, and an exception needs its own
  /// name or the next reader will delete it as a duplicate.
  final bool touchLocked;

  /// False disables the two-finger/trackpad ROTATION gestures (P8) while
  /// pan/zoom keep working — for hosts whose content cannot rotate (the
  /// timesheet).
  final bool rotationEnabled;

  /// What ONE finger does here when this host answers the slot itself —
  /// null follows the user's slot ([AppInput.touchDragActionFor]). Two and
  /// three fingers keep the user's slots.
  ///
  /// 🗣️I-14 (유저 2026-09-11): 「뷰어패널은 기본적으로 드로잉모드
  /// 존재안하니 한손가락 핑거시 팬」 — the media viewer passes navigate.
  final CanvasTouchDragAction? oneFingerAction;

  final Widget child;

  @override
  State<CanvasViewportGestureLayer> createState() =>
      _CanvasViewportGestureLayerState();
}

class _CanvasViewportGestureLayerState
    extends State<CanvasViewportGestureLayer> {
  /// Two-finger/trackpad rotation engages only past this angle (P8): a
  /// plain pinch-zoom must not wobble the canvas.
  static const double rotationDeadzoneDegrees = 5;

  /// A resulting view angle inside this window snaps back to 0° — easy
  /// return to straight.
  static const double rotationZeroSnapDegrees = 5;

  int? _panPointer;
  Offset? _panStartLocalPosition;
  CanvasViewport? _panStartViewport;
  CanvasViewport? _panZoomStartViewport;

  /// Non-null once the trackpad rotation crossed the deadzone: the fixed
  /// compensation (±deadzone, the crossing side) subtracted from the raw
  /// delta so the engagement is seamless AND stays continuous when the
  /// gesture later swings back through zero.
  double? _panZoomRotationCompensation;

  /// Live touch contacts (pointer id → local position). The first two form
  /// the two-finger navigation gesture.
  final Map<int, Offset> _touchPositions = <int, Offset>{};

  static double _wrapDegrees(double degrees) {
    var wrapped = degrees;
    while (wrapped > 180) {
      wrapped -= 360;
    }
    while (wrapped < -180) {
      wrapped += 360;
    }
    return wrapped;
  }

  /// Snaps a candidate view angle to 0° when it lands near straight.
  static double _snappedRotation(double degrees) {
    final normalized = _wrapDegrees(degrees);
    if (normalized.abs() <= rotationZeroSnapDegrees) {
      return degrees - normalized;
    }
    return degrees;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      key: const ValueKey<String>('canvas-viewport-gesture-layer'),
      // Translucent: receive events over the whole viewport (the blank
      // canvas paints without hit-testable render objects) while the
      // interactive canvas below keeps receiving its drawing input.
      behavior: HitTestBehavior.translucent,
      onPointerDown: _handlePointerDown,
      onPointerMove: _handlePointerMove,
      onPointerUp: _handlePointerLift,
      onPointerCancel: _handlePointerLift,
      onPointerSignal: _handlePointerSignal,
      onPointerPanZoomStart: _handlePanZoomStart,
      onPointerPanZoomUpdate: _handlePanZoomUpdate,
      onPointerPanZoomEnd: _handlePanZoomEnd,
      // 🚨★★★H24 — A DRAG THAT STARTS HERE IS THIS CANVAS'S, and no scroller
      // around the panel moves with it (유저 2026-09-15: 「스페이스바+클릭이나
      // 터치조작이나 뷰어패널 내부에 대한 조작이 다중패널의 스크롤바가
      // 활성되있을때 … 동시적용되버리니까 스크롤바 절대 적용안되게
      // 강한클레임으로 잡아줘. 캔버스 베이스패널은 전부 다 똑같이」). This
      // layer reads raw pointers and never enters the arena, so an ancestor
      // `Scrollable` won every drag that began on the canvas and scrolled
      // under it. 🧪Measured with the dock's kind of scroller around a sheet
      // panel: every device's drag scrolled it 144px, and two fingers did not
      // even reach the pinch (12 viewports without the scroller, 0 with it).
      //
      // The claim sits INSIDE this Listener, and that is load-bearing: it is
      // offered each down before this layer is, so it can tell a deeper
      // widget's own drag verb from the pointers this layer is about to make
      // into its gestures ([SurfaceDragClaim]).
      child: SurfaceDragClaim(child: widget.child),
    );
  }

  /// Pointers this layer has made into ITS gestures, held under the strong
  /// claim until each one lifts.
  ///
  /// What the claim is for is the press BELOW: a claimed control on the
  /// canvas — the playback view's stop, a conte cell — does not fire when a
  /// pan or a pinch that ran across it lifts inside it
  /// ([ControlPressClaim]). Released per pointer on its OWN lift, never all
  /// at once: the finger still down after its partner lifts is still part
  /// of a gesture, not the start of a tap.
  final Set<int> _gesturePointers = <int>{};

  void _holdForTheGesture(int pointer) {
    if (_gesturePointers.add(pointer)) {
      claimPointerForValueControl(pointer);
    }
  }

  void _releaseFromTheGesture(int pointer) {
    if (_gesturePointers.remove(pointer)) {
      releasePointerForValueControl(pointer);
    }
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (event.kind == PointerDeviceKind.touch) {
      // The one place touch does NOT get to override a busy canvas. Two
      // fingers cancel a stroke because a stroke can be redrawn; they may
      // not cancel a transform, so the finger has to stop short of
      // navigating too — otherwise the box would sit still while the view
      // slid out from under it.
      if (widget.touchLocked) {
        return;
      }
      _touchPositions[event.pointer] = event.localPosition;
      // PEN-12 #4: ONE touch engine — the old draw MODE's legacy pinch
      // path retired; a draw-assigned one-finger slot simply makes the
      // engine stand down for that group (the brush view draws).
      _controlTouchDown(event);
      return;
    }

    if (!canvasPressPans(event.buttons) ||
        _panPointer != null ||
        widget.strokeActive) {
      return;
    }
    _panPointer = event.pointer;
    _panStartLocalPosition = event.localPosition;
    _panStartViewport = _liveViewport;
    // A pan press is this canvas's gesture from its down: the held key or
    // the mapped button said so before anything moved.
    _holdForTheGesture(event.pointer);
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (_touchPositions.containsKey(event.pointer)) {
      _touchPositions[event.pointer] = event.localPosition;
      _controlTouchMove(event);
      return;
    }

    if (event.pointer != _panPointer) {
      return;
    }
    final startPosition = _panStartLocalPosition;
    final startViewport = _panStartViewport;
    if (startPosition == null || startViewport == null) {
      return;
    }
    final delta = event.localPosition - startPosition;
    _emit(startViewport.translated(dx: delta.dx, dy: delta.dy));
  }

  /// UP and CANCEL say the same thing to this layer — **this pointer left**
  /// — so one handler answers both. Only [PointerEvent.pointer] is read.
  void _handlePointerLift(PointerEvent event) {
    // ⚠️Released here and not earlier: pointer-up reaches a claimed control
    // on the canvas BEFORE this ancestor, so the control has already seen
    // that this press was a gesture by the time the claim is let go.
    _releaseFromTheGesture(event.pointer);
    if (_touchPositions.remove(event.pointer) != null) {
      _controlTouchLift(event.pointer);
      return;
    }
    if (event.pointer == _panPointer) {
      _clearPan();
    }
  }

  // --- PEN-7b: the CONTROL-mode touch engine ------------------------------
  //
  // Slot model: fingers landing BEFORE the lock form the BASE group;
  // its size picks the user-assigned drag action (flip/navigate/
  // brush size). Once the group LOCKS (any finger crosses the slop) later
  // fingers become the +1 MODIFIER (never a re-classification — the
  // Callipeg-confusion fix); the modifier constrains the action (snap/
  // lock/fine-step). Any BASE finger lifting ends the gesture; a modifier
  // lifting just releases the constraint. Speed never decides anything.

  static const double _touchSlop = 18;

  /// One flip step per this many pixels along the locked axis.
  ///
  /// ⚠️Reads the WIDGET's constant rather than holding its own: a flip's
  /// step distance is also its LOCK distance (H30), and a test that has to
  /// reach that point needs to name the same number. Two spellings would
  /// let a moved lock slip past a test that still walked the old distance —
  /// 🧪which is exactly what happened when the lock moved and four HUD
  /// tests stopped reaching it.
  static const double flipStepExtent =
      CanvasViewportGestureLayer.flipStepExtent;

  final List<int> _groupPointers = <int>[];
  final Map<int, Offset> _groupDownPositions = <int, Offset>{};
  bool _groupLocked = false;
  CanvasTouchDragAction _groupAction = CanvasTouchDragAction.none;
  final Set<int> _modifierPointers = <int>{};

  // Flip state: axis locks to the dominant direction at group lock.
  bool? _flipAxisHorizontal;
  int _flipEmittedSteps = 0;

  // Navigate state (group-form anchors — reset when the modifier
  // engages/releases so constraints never jump the view).
  Offset? _navStartFocal;
  double? _navStartDistance;
  double? _navStartAngle;
  double? _navRotationCompensation;
  CanvasViewport? _navStartViewport;
  bool _navModifierActive = false;
  double? _navModifierLockRotation;

  // Brush-size state.
  bool _brushSizeActive = false;

  /// PEN-14: the viewport as the engine last EMITTED it. Mid-gesture,
  /// `widget.viewport` lags the emissions by however long the parent
  /// takes to rebuild — re-anchoring off the stale prop (the modifier
  /// engage/release path) snapped the zoom back to the GESTURE-START
  /// scale ("추가 핑거를 올리면 줌이 50%로 초기화"). Cleared whenever the
  /// parent catches up or an external change lands (didUpdateWidget).
  CanvasViewport? _lastEmittedViewport;

  CanvasViewport get _liveViewport => _lastEmittedViewport ?? widget.viewport;

  @override
  void dispose() {
    // A panel torn down mid-flip must not leave the window on screen.
    if (_groupAction == CanvasTouchDragAction.flip) {
      widget.flipHud?.end();
    }
    // Nor its claims: a claim that outlives its gesture deafens whichever
    // later press is handed the same pointer id.
    for (final pointer in _gesturePointers) {
      releasePointerForValueControl(pointer);
    }
    _gesturePointers.clear();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant CanvasViewportGestureLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // An exact catch-up (prop == our latest emission) keeps the cache; any
    // OTHER prop change is external and wins.
    if (widget.viewport != oldWidget.viewport &&
        widget.viewport != _lastEmittedViewport) {
      _lastEmittedViewport = null;
    }
  }

  void _controlTouchDown(PointerDownEvent event) {
    if (_groupPointers.isEmpty) {
      _groupPointers.add(event.pointer);
      _groupDownPositions[event.pointer] = event.localPosition;
      return;
    }
    // PEN-8 #3: before the LOCK, every new finger JOINS the group — a
    // slightly staggered pinch (fingers landing 100–300ms apart, or
    // close together) must still become the two-finger gesture. The
    // fixed simultaneity window silently dropped the late finger, which
    // read as "two-finger gestures randomly don't take". Only once the
    // group is locked does a late finger become the MODIFIER (the
    // lock-then-modify rule — still never a re-classification).
    if (!_groupLocked && _groupPointers.length < 3) {
      _groupPointers.add(event.pointer);
      _groupDownPositions[event.pointer] = event.localPosition;
      return;
    }
    if (_groupLocked &&
        // PEN-12 #4: a locked DRAW group takes no modifier at all — the
        // stroke is the brush view's; a late finger (palm, habit) must
        // change nothing.
        _groupAction != CanvasTouchDragAction.draw &&
        AppInput.settings.value.extraFingerModifier) {
      _modifierPointers.add(event.pointer);
      _holdForTheGesture(event.pointer);
      _engageModifier();
    }
  }

  void _controlTouchMove(PointerMoveEvent event) {
    if (!_groupPointers.contains(event.pointer)) {
      return;
    }
    if (!_groupLocked) {
      final down = _groupDownPositions[event.pointer];
      if (down == null) {
        return;
      }
      final moved = event.localPosition - down;
      // Past the slop the press is a GESTURE, whichever action the group
      // turns out to be — so a claimed control under it will not take its
      // lift as a tap. The flip still classifies at its own distance (H30);
      // this decides only that it is no longer a tap, with the slop every
      // other group already locks at, not a number of its own.
      if (moved.distance >= _touchSlop) {
        _holdForTheGesture(event.pointer);
      }
      if (moved.distance < _lockDistanceFor(_groupPointers.length)) {
        return;
      }
      _lockGroup(firstMovedDelta: moved);
    }
    _scheduleGroupUpdate();
  }

  /// 🚨★★★F-11 (유저): 「터치 확대축소 **떨림** … 확대율이 튀어 **1프레임
  /// 확대됐다 돌아오는** 현상」.
  ///
  /// 🧪Measured, not guessed. A pinch's two fingers move in the SAME frame
  /// but arrive as SEPARATE events, and the update ran on each one — so
  /// between finger A's event and finger B's, the distance was computed
  /// from A's new position and B's OLD one. On a pure pan (distance
  /// constant) the emitted zoom read `1.05 → 1.00 → 1.05` inside one
  /// batch: a full step out and back, every frame, which is the shimmer.
  ///
  /// ⇒ One update per BATCH, off the freshest position of every finger.
  /// A microtask rather than a frame callback, because 「**반응성 최우선 —
  /// 느려지면 안 된다**」: the pointer queue drains synchronously, so this
  /// runs the instant the batch ends and still inside the same frame. A
  /// `scheduleFrameCallback` would have cost a frame of latency to fix a
  /// one-frame wobble.
  ///
  /// ⚠️It changes WHEN the update runs, never what it computes — the
  /// arithmetic below is untouched, and a batch carrying one finger's
  /// event behaves exactly as before.
  bool _groupUpdateScheduled = false;

  void _scheduleGroupUpdate() {
    if (_groupUpdateScheduled) {
      return;
    }
    _groupUpdateScheduled = true;
    scheduleMicrotask(() {
      _groupUpdateScheduled = false;
      if (!mounted || !_groupLocked) {
        return;
      }
      _dispatchGroupUpdate();
    });
  }

  /// How far a finger must travel before a group of [fingers] is DECIDED.
  ///
  /// 🚨★★★H30 (유저): 「지인이 아이패드로 작업중인데, 두손핑거로 캔버스
  /// 컨트롤하려다 **레이어이동, 즉 1핑거로 인식하는경우**가 종종 있는거같아.
  /// 아마 두손가락을 **동시에 착지안하고 따로따로 착지**하는게 버릇인거같은데」.
  ///
  /// ⛔A staggered LAND was already fine — PEN-8 #3 removed the simultaneity
  /// window, so a finger arriving 400ms later still joins. What was not fine
  /// is a finger arriving after the first one MOVED: the group locked the
  /// instant anything crossed the slop, and from then on late fingers could
  /// only be modifiers. A twitch of 20px had decided the gesture.
  ///
  /// ★THE LAW IS ONE SENTENCE AND EACH ACTION ANSWERS IT: lock when this
  /// gesture would first DO something. ⛔Not 「flip is special」 — flip is
  /// simply the only action whose first effect is not its first pixel. A
  /// navigate pans by that pixel, a brush-size drag resizes by it, and a
  /// draw inks it; for those the slop already IS the first effect, so they
  /// are unchanged.
  ///
  /// ⚠️Until the lock the group is 「분류 전」, not misclassified — a late
  /// finger JOINS (the `_controlTouchDown` branch above already allows it
  /// while unlocked). The lock-then-modify rule itself is untouched.
  double _lockDistanceFor(int fingers) {
    return _actionFor(fingers) == CanvasTouchDragAction.flip
        ? flipStepExtent
        : _touchSlop;
  }

  /// The slot a group of [fingers] answers to HERE — the user's, or this
  /// host's own for one finger ([CanvasViewportGestureLayer.oneFingerAction]).
  CanvasTouchDragAction _actionFor(int fingers) =>
      AppInput.touchDragActionFor(fingers, oneFinger: widget.oneFingerAction);

  void _lockGroup({required Offset firstMovedDelta}) {
    _groupLocked = true;
    // Every finger of a locked group is the gesture's — the one that stood
    // still through a pinch included — so none of them lifts as a tap.
    for (final pointer in _groupPointers) {
      _holdForTheGesture(pointer);
    }
    // 🚨★★★H24 (유저 2026-08-25): 「터치 제스처가 패널을 통과」 — two fingers
    // on the glass, one of them over the timeline, and the canvas ran a
    // ONE-finger gesture: the timeline flipped frames while the user was
    // trying to pinch.
    //
    // ★THE LAW: a gesture you do not hold ALL of is not your gesture.
    // This layer counts the fingers IT received. When the app is holding
    // more than that, the rest are somewhere else — and what is happening
    // is not the N-finger gesture this count names. Standing down is the
    // only honest answer: reclassifying would be a guess about a finger
    // this layer cannot see.
    //
    // ⚠️It reads the APP-WIDE census, never [CanvasTouchContacts.count] —
    // that one counts fingers on INK and has its own job (a second finger
    // stands a running stroke down). Two questions, two counters, and the
    // note on `appWideCount` says why widening either is wrong.
    //
    // 🧪The card asked for the census to be MEASURED before trusting it,
    // because an over-count would kill canvas gestures outright. It cannot
    // over-count from the promoted-mouse path this file already documents:
    // `noteAppWide` filters to `PointerDeviceKind.touch`, and Windows
    // promotes a pinch to MOUSE hover/scroll. `panel_touch_is_whole_test`
    // drives that case and the leak paths (cancel, a panel disposed
    // mid-touch) through the real observer.
    _groupAction = CanvasTouchContacts.appWideCount > _groupPointers.length
        ? CanvasTouchDragAction.none
        : _actionFor(_groupPointers.length);
    switch (_groupAction) {
      case CanvasTouchDragAction.flip:
        final horizontal = firstMovedDelta.dx.abs() >= firstMovedDelta.dy.abs();
        _flipAxisHorizontal = horizontal;
        _flipEmittedSteps = 0;
        // The HUD appears on the LOCK, not on touchdown: a tap or a plain
        // pan must never flash it.
        widget.flipHud?.begin(
          axis: _flipsFrames(horizontal) ? FlipHudAxis.frame : FlipHudAxis.row,
          anchor: _groupCentroid(_groupDownPositions),
          frameStep: _flipFrameStep,
        );
      case CanvasTouchDragAction.navigate:
        // Anchor at the DOWN positions: the whole travel since touchdown
        // counts (the legacy pinch contract — nothing swallowed by the
        // lock slop, and a single-event jump still navigates in full).
        _anchorNavigate(fromDownPositions: true);
      case CanvasTouchDragAction.brushSize:
        _brushSizeActive = true;
        widget.onBrushSizeDragStart?.call();
      // The brush view owns a DRAW group's stroke; the engine stands by.
      case CanvasTouchDragAction.draw:
      case CanvasTouchDragAction.none:
        break;
    }
  }

  void _dispatchGroupUpdate() {
    switch (_groupAction) {
      case CanvasTouchDragAction.flip:
        _updateFlip();
      case CanvasTouchDragAction.navigate:
        _updateNavigate();
      case CanvasTouchDragAction.brushSize:
        _updateBrushSize();
      case CanvasTouchDragAction.draw:
      case CanvasTouchDragAction.none:
        break;
    }
  }

  Offset _groupCentroid(Map<int, Offset> positions) {
    var sum = Offset.zero;
    for (final pointer in _groupPointers) {
      sum += positions[pointer] ?? Offset.zero;
    }
    return sum / _groupPointers.length.toDouble();
  }

  /// Whether a gesture locked to this screen direction walks FRAMES.
  ///
  /// F-28: the frame axis is sideways on the timeline and downward on the
  /// X-sheet, and the flip follows the sheet the user is reading — 「타임라인
  /// 패널 x시트일 경우 … 세로가 프레임이동 가로가 레이어이동 되도록. 그게
  /// 직관적임」. One question, asked in both places that need it.
  bool _flipsFrames(bool horizontal) =>
      widget.flipHud?.framesRunAlong(horizontal: horizontal) ?? horizontal;

  void _updateFlip() {
    final horizontal = _flipAxisHorizontal;
    if (horizontal == null) {
      return;
    }
    final downCentroid = _groupCentroid(_groupDownPositions);
    final nowCentroid = _groupCentroid(_touchPositions);
    final along = horizontal
        ? nowCentroid.dx - downCentroid.dx
        : nowCentroid.dy - downCentroid.dy;
    final steps = (along / flipStepExtent).truncate();
    if (_flipEmittedSteps == steps) {
      return;
    }
    while (_flipEmittedSteps != steps) {
      final forward = steps > _flipEmittedSteps;
      _flipEmittedSteps += forward ? 1 : -1;
      final fine = _flipModifierActive;
      final actionId = _flipsFrames(horizontal)
          ? (forward
                // Along the frame axis, forward = next; the modifier steps
                // ONE FRAME (the Ctrl+arrow mapping) instead of one drawing.
                ? (fine ? 'frame-next' : 'drawing-next')
                : (fine ? 'frame-previous' : 'drawing-previous'))
          // Across it, the flip walks the ROW STACK (the arrow-key
          // arbitration path).
          : (forward ? 'selection-nudge-down' : 'selection-nudge-up');
      widget.onInvokeAction?.call(actionId);
    }
    // The action has LANDED by now (the funnel is synchronous), so the
    // HUD reads where the session actually went rather than guessing.
    widget.flipHud?.refresh(frameStep: _flipFrameStep);
  }

  void _anchorNavigate({bool fromDownPositions = false}) {
    final source = fromDownPositions ? _groupDownPositions : _touchPositions;
    final positions = {
      for (final pointer in _groupPointers)
        pointer: source[pointer] ?? Offset.zero,
    };
    _navStartFocal = _groupCentroid(positions);
    if (_groupPointers.length >= 2) {
      final first = positions[_groupPointers[0]]!;
      final second = positions[_groupPointers[1]]!;
      _navStartDistance = (second - first).distance;
      _navStartAngle = _touchAngleDegrees(first, second);
    } else {
      _navStartDistance = null;
      _navStartAngle = null;
    }
    _navRotationCompensation = null;
    _navStartViewport = _liveViewport;
  }

  /// Whether the +1-finger modifier is engaged at all.
  bool get _flipModifierActive =>
      _modifierPointers.isNotEmpty &&
      AppInput.settings.value.extraFingerModifier;

  /// Whether the flip is stepping single FRAMES. Only the horizontal axis
  /// has a finer unit to drop to — the vertical walk is rows either way,
  /// so reporting the modifier there would make the HUD claim a mode
  /// change that did not happen.
  bool get _flipFrameStep {
    final horizontal = _flipAxisHorizontal;
    // F-28: "the frame mode" is a fact about the LOCKED AXIS meaning frames,
    // not about the finger having gone sideways.
    return horizontal != null && _flipsFrames(horizontal) && _flipModifierActive;
  }

  void _engageModifier() {
    if (_groupAction == CanvasTouchDragAction.flip) {
      // Frame steps are the OTHER mode, not a finer version of this one —
      // the HUD re-rules itself so the eye sees the change first.
      widget.flipHud?.refresh(frameStep: _flipFrameStep);
    }
    if (_groupAction == CanvasTouchDragAction.navigate) {
      // Re-anchor so the constraint takes over from HERE, not from the
      // gesture start — the view never jumps when the finger lands.
      _navModifierActive = true;
      _navModifierLockRotation = _liveViewport.rotationDegrees;
      _anchorNavigate();
    }
  }

  void _releaseModifier() {
    if (_groupAction == CanvasTouchDragAction.flip) {
      widget.flipHud?.refresh(frameStep: _flipFrameStep);
    }
    if (_groupAction == CanvasTouchDragAction.navigate) {
      _navModifierActive = false;
      _navModifierLockRotation = null;
      _anchorNavigate();
    }
  }

  void _updateNavigate() {
    final startFocal = _navStartFocal;
    final startViewport = _navStartViewport;
    if (startFocal == null || startViewport == null) {
      return;
    }
    final settings = AppInput.settings.value;
    final modifier = _navModifierActive && settings.extraFingerModifier;
    final focal = _groupCentroid(_touchPositions);
    final focalAnchor = ViewportPoint(x: startFocal.dx, y: startFocal.dy);
    var next = startViewport;

    final startDistance = _navStartDistance;
    if (_groupPointers.length >= 2 && startDistance != null) {
      final first = _touchPositions[_groupPointers[0]];
      final second = _touchPositions[_groupPointers[1]];
      if (first != null && second != null) {
        final distance = (second - first).distance;
        if (startDistance > 0 && distance > 0) {
          next = _pinchZoomed(startViewport, distance, startDistance, modifier, settings, next, focalAnchor);
        }
        next = _twistRotated(settings, first, second, startViewport, modifier, next, focalAnchor);
      }
    }
    _emit(
      next.translated(
        dx: focal.dx - startFocal.dx,
        dy: focal.dy - startFocal.dy,
      ),
    );
  }

  CanvasViewport _twistRotated(AppInputSettings settings, Offset first, Offset second, CanvasViewport startViewport, bool modifier, CanvasViewport next, ViewportPoint focalAnchor) {
    final rotationOn =
        widget.rotationEnabled && settings.navigationRotationEnabled;
    final startAngle = rotationOn ? _navStartAngle : null;
    if (startAngle != null) {
      final rawDelta = _wrapDegrees(
        _touchAngleDegrees(first, second) - startAngle,
      );
      if (_navRotationCompensation == null &&
          rawDelta.abs() >= rotationDeadzoneDegrees) {
        _navRotationCompensation = rawDelta.sign * rotationDeadzoneDegrees;
      }
      final compensation = _navRotationCompensation;
      if (compensation != null) {
        var nextRotation =
            startViewport.rotationDegrees + rawDelta - compensation;
        if (modifier) {
          final lockAngle = _navModifierLockRotation;
          if (settings.navigationModifierRotationLock &&
              lockAngle != null) {
            // Constrain: rotation LOCKED at the modifier-engage angle
            // (pure pan + snapped zoom).
            nextRotation = lockAngle;
          } else {
            // Constrain: rotation snaps to the degree grid.
            final snap = settings.rotationSnapDegrees;
            if (snap > 0) {
              nextRotation = (nextRotation / snap).round() * snap;
            }
          }
        } else {
          nextRotation = _snappedRotation(nextRotation);
        }
        next = next.rotatedAround(
          nextRotationDegrees: nextRotation,
          anchor: focalAnchor,
        );
      }
    }
    return next;
  }

  CanvasViewport _pinchZoomed(CanvasViewport startViewport, double distance, double startDistance, bool modifier, AppInputSettings settings, CanvasViewport next, ViewportPoint focalAnchor) {
    var nextZoom = startViewport.zoom * (distance / startDistance);
    if (modifier) {
      // Constrain: zoom snaps to the user's percent list — read in DISPLAY
      // percent, the unit the list is written in and the one the ± buttons
      // step through (`_zoomStep`). Snapped as the RENDER zoom it is here,
      // a constrained pinch landed on list × effective ratio: a 150% stop
      // read 225% on a 150% monitor (audit 2026-09-15).
      final scale = CanvasZoomScale.of(context);
      nextZoom = scale.render(
        AppInput.snapToList(
              scale.display(nextZoom) * 100,
              settings.zoomSnapPercents,
            ) /
            100,
      );
    }
    return next.zoomedAround(nextZoom: nextZoom, anchor: focalAnchor);
  }

  void _updateBrushSize() {
    final downCentroid = _groupCentroid(_groupDownPositions);
    final nowCentroid = _groupCentroid(_touchPositions);
    // Vertical only (가로축은 의도적으로 비움): up = bigger.
    widget.onBrushSizeDragUpdate?.call(
      downCentroid.dy - nowCentroid.dy,
      snap:
          _modifierPointers.isNotEmpty &&
          AppInput.settings.value.extraFingerModifier,
    );
  }

  void _controlTouchLift(int pointer) {
    if (_modifierPointers.remove(pointer)) {
      _releaseModifier();
      return;
    }
    if (!_groupPointers.contains(pointer)) {
      return;
    }
    // Any BASE finger lifting ends the gesture whole.
    if (_brushSizeActive) {
      widget.onBrushSizeDragEnd?.call();
    }
    _resetControlEngine();
  }

  void _resetControlEngine() {
    if (_groupAction == CanvasTouchDragAction.flip) {
      widget.flipHud?.end();
    }
    _groupPointers.clear();
    _groupDownPositions.clear();
    _groupLocked = false;
    _groupAction = CanvasTouchDragAction.none;
    _modifierPointers.clear();
    _flipAxisHorizontal = null;
    _flipEmittedSteps = 0;
    _navStartFocal = null;
    _navStartDistance = null;
    _navStartAngle = null;
    _navRotationCompensation = null;
    _navStartViewport = null;
    _navModifierActive = false;
    _navModifierLockRotation = null;
    _brushSizeActive = false;
  }

  static double _touchAngleDegrees(Offset first, Offset second) {
    final vector = second - first;
    return math.atan2(vector.dy, vector.dx) * 180 / math.pi;
  }

  /// H23: REGISTERED, not handled — see [handleWheelExclusively]. A notch
  /// over a control that sits inside this layer used to move the control AND
  /// zoom the view, because a `Listener` does not consume a pointer signal.
  void _handlePointerSignal(PointerSignalEvent event) =>
      handleWheelExclusively(event, _zoomByWheel);

  void _zoomByWheel(PointerScrollEvent event) {
    if (event.scrollDelta.dy == 0 || widget.strokeActive) {
      return;
    }
    final factor = event.scrollDelta.dy < 0 ? 1.1 : 1 / 1.1;
    _emit(
      _liveViewport.zoomedAround(
        nextZoom: _liveViewport.zoom * factor,
        anchor: ViewportPoint(
          x: event.localPosition.dx,
          y: event.localPosition.dy,
        ),
      ),
    );
  }

  void _handlePanZoomStart(PointerPanZoomStartEvent event) {
    if (widget.strokeActive) {
      return;
    }
    _panZoomStartViewport = _liveViewport;
    _panZoomRotationCompensation = null;
  }

  void _handlePanZoomUpdate(PointerPanZoomUpdateEvent event) {
    final base = _panZoomStartViewport;
    if (base == null) {
      return;
    }
    final anchor = ViewportPoint(
      x: event.localPosition.dx,
      y: event.localPosition.dy,
    );
    // Pan, scale and rotation are all cumulative since the gesture start,
    // so each update recomputes from the start viewport instead of
    // accumulating.
    var next = base;
    if (event.scale != 1.0) {
      next = base.zoomedAround(
        nextZoom: base.zoom * event.scale,
        anchor: anchor,
      );
    }
    // Trackpad rotation gesture (P8) — same deadzone/snap as two fingers.
    final rawDelta = widget.rotationEnabled
        ? event.rotation * 180 / math.pi
        : 0.0;
    if (_panZoomRotationCompensation == null &&
        rawDelta.abs() >= rotationDeadzoneDegrees) {
      _panZoomRotationCompensation = rawDelta.sign * rotationDeadzoneDegrees;
    }
    final compensation = _panZoomRotationCompensation;
    if (compensation != null) {
      next = next.rotatedAround(
        nextRotationDegrees: _snappedRotation(
          base.rotationDegrees + rawDelta - compensation,
        ),
        anchor: anchor,
      );
    }
    _emit(next.translated(dx: event.pan.dx, dy: event.pan.dy));
  }

  void _handlePanZoomEnd(PointerPanZoomEndEvent event) {
    _panZoomStartViewport = null;
    _panZoomRotationCompensation = null;
  }

  void _clearPan() {
    _panPointer = null;
    _panStartLocalPosition = null;
    _panStartViewport = null;
  }

  void _emit(CanvasViewport viewport) {
    final clamped = viewport.clamped();
    _lastEmittedViewport = clamped;
    widget.onViewportChanged(clamped);
  }
}
