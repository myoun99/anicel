import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../../models/canvas_viewport.dart';
import '../input/app_input_settings.dart';
import '../../models/viewport_point.dart';
import 'flip_hud_controller.dart';

/// Viewport pan/zoom input for the canvas panel, independent of what the
/// viewport currently shows (interactive canvas, blank paper, playback).
/// Living at the panel level is what keeps navigation working on timeline
/// positions without an editable frame.
///
/// - Middle-mouse drag pans.
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
  const CanvasViewportGestureLayer({
    super.key,
    required this.viewport,
    required this.onViewportChanged,
    this.strokeActive = false,
    this.touchLocked = false,
    this.rotationEnabled = true,
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
      onPointerUp: _handlePointerUp,
      onPointerCancel: _handlePointerCancel,
      onPointerSignal: _handlePointerSignal,
      onPointerPanZoomStart: _handlePanZoomStart,
      onPointerPanZoomUpdate: _handlePanZoomUpdate,
      onPointerPanZoomEnd: _handlePanZoomEnd,
      child: widget.child,
    );
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

    if (!_startsMappedPan(event.buttons) ||
        _panPointer != null ||
        widget.strokeActive) {
      return;
    }
    _panPointer = event.pointer;
    _panStartLocalPosition = event.localPosition;
    _panStartViewport = _liveViewport;
  }

  /// Whether this button chord starts a viewport PAN (PEN-7a): any
  /// pressed secondary bit whose CANVAS mapping says pan — the wheel/
  /// middle bit (default mapping) or the right bit when assigned. The
  /// pen tip's contact bit rides along on stylus presses, so the check
  /// is per-bit, not equality.
  bool _startsMappedPan(int buttons) {
    final settings = AppInput.settings.value;
    if ((buttons & kTertiaryButton) != 0 &&
        settings.canvasWheelClick.action == CanvasPointerAction.pan) {
      return true;
    }
    if ((buttons & kSecondaryButton) != 0 &&
        settings.canvasRightClick.action == CanvasPointerAction.pan) {
      return true;
    }
    return false;
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

  void _handlePointerUp(PointerUpEvent event) {
    if (_touchPositions.remove(event.pointer) != null) {
      _controlTouchLift(event.pointer);
      return;
    }
    if (event.pointer == _panPointer) {
      _clearPan();
    }
  }

  void _handlePointerCancel(PointerCancelEvent event) {
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
  static const double flipStepExtent = 48;

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
      _engageModifier();
    }
  }

  void _controlTouchMove(PointerMoveEvent event) {
    if (!_groupPointers.contains(event.pointer)) {
      return;
    }
    if (!_groupLocked) {
      final down = _groupDownPositions[event.pointer];
      if (down == null || (event.localPosition - down).distance < _touchSlop) {
        return;
      }
      _lockGroup(firstMovedDelta: event.localPosition - down);
    }
    _dispatchGroupUpdate();
  }

  void _lockGroup({required Offset firstMovedDelta}) {
    _groupLocked = true;
    _groupAction = AppInput.touchDragActionFor(_groupPointers.length);
    switch (_groupAction) {
      case CanvasTouchDragAction.flip:
        final horizontal = firstMovedDelta.dx.abs() >= firstMovedDelta.dy.abs();
        _flipAxisHorizontal = horizontal;
        _flipEmittedSteps = 0;
        // The HUD appears on the LOCK, not on touchdown: a tap or a plain
        // pan must never flash it.
        widget.flipHud?.begin(
          axis: horizontal ? FlipHudAxis.frame : FlipHudAxis.row,
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
      final actionId = horizontal
          ? (forward
                // Drag right = next, drag left = previous; the modifier
                // steps ONE FRAME (the Ctrl+arrow mapping) instead of one
                // drawing.
                ? (fine ? 'frame-next' : 'drawing-next')
                : (fine ? 'frame-previous' : 'drawing-previous'))
          // Drag up = layer up (the arrow-key arbitration path).
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
  bool get _flipFrameStep =>
      (_flipAxisHorizontal ?? false) && _flipModifierActive;

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
          var nextZoom = startViewport.zoom * (distance / startDistance);
          if (modifier) {
            // Constrain: zoom snaps to the user's percent list.
            nextZoom =
                AppInput.snapToList(nextZoom * 100, settings.zoomSnapPercents) /
                100;
          }
          next = next.zoomedAround(nextZoom: nextZoom, anchor: focalAnchor);
        }
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
      }
    }
    _emit(
      next.translated(
        dx: focal.dx - startFocal.dx,
        dy: focal.dy - startFocal.dy,
      ),
    );
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

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent ||
        event.scrollDelta.dy == 0 ||
        widget.strokeActive) {
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
