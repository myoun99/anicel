import 'app_tooltip.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart'
    show DragGestureRecognizer, DragStartBehavior, kDoubleTapTimeout;

import '../theme/app_theme.dart';
import 'owning_axis_grip.dart';

/// A draggable divider between two areas that share an extent.
///
/// It began as the workspace dock's edge grip and is now the app's ONE
/// splitter: the layer rails use it too (the rail-window round), which is
/// why it lives beside the other shared widgets instead of inside the dock
/// host. [onDragDelta] receives the raw pointer delta along the splitter's
/// axis; the owner applies the sign for which side grows and REPORTS BACK
/// how much of it actually moved the edge.
///
/// ★THE SPLITTER HOLDS THE TRAVEL ITS OWNER COULD NOT USE (유저, R4 #13:
/// 왼쪽 끝까지 이동하고 돌아갈 때, 커서가 스플리터까지 오고 나서 오른쪽으로
/// 가야 이동되는 게 맞는데 지금은 바로 오른쪽으로 이동해버려서 어긋난다).
///
/// Every owner clamps. Push an edge past its floor and the surplus was
/// simply dropped, so the return trip began at the first pixel back and the
/// edge ran out ahead of the hand for the rest of the drag. The cure is not
/// per-owner memory — it was tried that way, and only the ONE owner that
/// remembered got it (R3 #2's detent fix, which is this same defect wearing
/// a magnet instead of a wall). Unusable travel is a fact about the DRAG,
/// so the drag keeps it: what the owner refuses accumulates here and must
/// be paid back before the edge moves again.
///
/// The contract is therefore: **return the delta you actually applied.**
/// An owner that returns the delta it was handed opts out and behaves as
/// this widget always did.
///
/// THE SPLITTER IS THE PANEL'S OWN EDGE, LIT. It paints nothing at rest and
/// fills its whole [thickness] when the pointer arrives, climbing the same
/// four-state ladder every grip in the app climbs (invisible ->
/// hairlineStrong -> gripHover -> accent).
///
/// ★It does NOT round itself. It is laid inside the panel's own ClipPath,
/// so the panel's silhouette cuts the band's outer corners and the lit edge
/// follows the curve exactly — which a shape of its own could never do,
/// because a 5px-wide band cannot carry a 14px corner (유저, R2 #11: 패널의
/// 옆부분을 형태그대로 색만 바꾸는 느낌). Whoever positions one is therefore
/// responsible for putting it inside the clip.
///
/// It used to paint an opaque [ColorScheme.surfaceContainerLow] band the
/// whole time, OUTSIDE the clip. That band is what covered the floating
/// region's rounded corners and drew two grey bars down its sides, which is
/// why the region read as square no matter how good its silhouette was: the
/// shape was right and something opaque was parked on top of it. The
/// hairline that replaced it was the other half of the mistake — a line is
/// not an edge.
class DockEdgeSplitter extends StatefulWidget {
  const DockEdgeSplitter({
    super.key,
    required this.axis,
    required this.onDragDelta,
    this.onDragStart,
    this.onDragEnd,
    this.onDoubleTap,
    this.tooltip,
  });

  /// [Axis.vertical] separates side-by-side areas (drag left-right);
  /// [Axis.horizontal] separates stacked ones (drag up-down).
  final Axis axis;

  /// Applies one frame of travel and returns HOW MUCH OF IT WAS USED.
  ///
  /// Returning less than it was given (because a floor, a ceiling or a
  /// detent got in the way) parks the difference in the drag, where the
  /// next frame in the opposite direction has to spend it first.
  final double Function(double delta) onDragDelta;

  /// The drag's BOUNDARIES, for owners that accumulate across it.
  ///
  /// [onDragDelta] alone cannot tell "a new drag" from "another frame of
  /// the same one", and an owner that snaps its result to a detent has to
  /// keep the un-snapped total somewhere or the snap eats the travel.
  final VoidCallback? onDragStart;
  final VoidCallback? onDragEnd;

  /// Double-click action, when the owner has a meaningful "back to the
  /// natural size" (the rails do; the docks do not).
  final VoidCallback? onDoubleTap;

  final String? tooltip;

  /// The hit extent, and the band's extent: they are the same thing now.
  static const double thickness = 5;

  @override
  State<DockEdgeSplitter> createState() => _DockEdgeSplitterState();
}

class _DockEdgeSplitterState extends State<DockEdgeSplitter> {
  bool _hovered = false;
  bool _dragging = false;

  /// Travel the owner could not use, in pointer pixels, signed.
  ///
  /// It is the distance the hand has run past the edge — so it is also
  /// exactly the distance the hand must come back before the edge is
  /// entitled to move, which is what makes the return trip line up.
  double _owed = 0;

  void _applyDelta(double delta) {
    final wanted = _owed + delta;
    // A debt of the SAME sign as the new travel is the hand going further
    // out; it is not repaid by going further out.
    final used = widget.onDragDelta(wanted);
    _owed = wanted - used;
  }

  /// 🚨★ THE POINTER PATH — 유저 확정 2026-08-14, ⛔재론 금지.
  ///
  /// ⑧ 유저 2026-08-12: 「펜 갖다대면 5번중 1번만 성공함. 뭔가 펜을 스플리터
  /// 위에 두고 멈추고 조작해야 먹히는거같음.」
  /// T30 유저 2026-08-14: 「스플리터가 도중에 그립이 풀려서 멈춤. **마우스
  /// 여전히 클릭도중인데도.** 빠르게 드래그하다보면 풀리는거같음.」
  ///
  /// Those two reports are the same mechanism seen from both ends, and both
  /// come from the grip trying to live OUTSIDE the arena.
  ///
  /// It started on `GestureDetector`'s axis drags, which must WIN AN ARENA
  /// before they see a single update — and a desktop `Scrollable` enters that
  /// arena for touch and stylus alone. A pen leaving the grip on any diagonal
  /// let the scroller cross its threshold first, so the drag never started.
  /// The answer taken then was to stop needing the arena: read the pointer
  /// raw, and ask afterwards whether the rival had *earned* the gesture by
  /// crossing this grip's axis.
  ///
  /// 🚨That question is what T30 is. A fast drag puts more travel in each
  /// event, so the cross-axis component clears the rival's slop sooner — and
  /// the grip answered by letting go, mid-drag, with the button still down.
  /// It was never robbed; it resigned.
  ///
  /// ★So the grip wins the arena instead, on the FIRST MOVEMENT
  /// (`OwningHorizontalDragGestureRecognizer`). Hit testing runs
  /// deepest-first, so it has accepted before any scrollable reaches its own
  /// threshold — which fixes ⑧ (no diagonal can lose a race that is over) and
  /// T30 together (there is no rival left to resign to).
  Axis get _dragAxis =>
      widget.axis == Axis.vertical ? Axis.horizontal : Axis.vertical;

  void _handleDragDown(DragDownDetails details) => _setDragging(true);

  void _handleDragUpdate(DragUpdateDetails details) {
    if (!_dragging) {
      return;
    }
    _applyDelta(
      _dragAxis == Axis.horizontal ? details.delta.dx : details.delta.dy,
    );
  }

  /// Wires one drag recogniser. Both axes take the same handlers, so the
  /// vertical and horizontal factories cannot drift apart.
  void _configureDrag(DragGestureRecognizer recognizer) {
    // Down, not start: the grip goes accent the moment it is pressed, which
    // is R9 #12's rule — a press is an answer the affordance owes
    // immediately, and there is no slop left to wait through anyway.
    recognizer
      ..dragStartBehavior = DragStartBehavior.down
      ..onDown = _handleDragDown
      ..onUpdate = _handleDragUpdate
      ..onEnd = (_) {
        _setDragging(false);
      }
      ..onCancel = () {
        _setDragging(false);
      };
  }

  Color get _lineColor {
    if (_dragging) {
      return AppColors.accent;
    }
    if (_hovered) {
      return AppColors.gripHover;
    }
    return Colors.transparent;
  }

  void _setDragging(bool value) {
    if (_dragging == value) {
      return;
    }
    setState(() => _dragging = value);
    // The debt belongs to ONE drag. Carrying it into the next one would
    // make a fresh grab start dead — the hand would have to pay off travel
    // it never made.
    _owed = 0;
    if (value) {
      widget.onDragStart?.call();
    } else {
      widget.onDragEnd?.call();
    }
  }

  /// 🚨THE DOUBLE TAP IS READ OFF THE POINTER, like every press in this app
  /// (F-120's sweep, 유저 2026-09-13: 「그런 커서 위치따라 판정하는거
  /// 없도록」).
  ///
  /// It was a `DoubleTapGestureRecognizer` beside the drag, on the reading
  /// that a tap 「has nothing to lose by waiting for the arena」. It had
  /// everything to lose: the drag accepts on the FIRST movement (T30's fix,
  /// not up for trade), and whatever wins the arena rejects the double tap.
  /// 🧪Measured: two presses that each moved two pixels reset nothing, on a
  /// pen, a finger and a mouse alike; held perfectly still, they did.
  ///
  /// ⇒ A press that lands on the grip while the previous one's
  /// [kDoubleTapTimeout] is still running IS the second tap, and its lift
  /// fires. No distance is compared — a press that wandered is still the
  /// press it was, the same answer the claim gives a button.
  Timer? _secondPressWindow;
  bool _secondPress = false;

  void _pressDown(PointerDownEvent event) {
    _secondPress = _secondPressWindow?.isActive ?? false;
    _secondPressWindow?.cancel();
  }

  void _pressUp(PointerUpEvent event) {
    final onDoubleTap = widget.onDoubleTap;
    if (onDoubleTap == null) {
      return;
    }
    if (_secondPress) {
      _secondPress = false;
      onDoubleTap();
      return;
    }
    _secondPressWindow = Timer(kDoubleTapTimeout, () {});
  }

  void _pressCancel(PointerCancelEvent event) {
    _secondPress = false;
    _secondPressWindow?.cancel();
  }

  @override
  void dispose() {
    _secondPressWindow?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vertical = widget.axis == Axis.vertical;
    Widget grip = MouseRegion(
      cursor: vertical
          ? SystemMouseCursors.resizeLeftRight
          : SystemMouseCursors.resizeUpDown,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      // The grip is a drag verb like a slider's — [OwningAxisGrip], the pair
      // this splitter wrote by hand first and the comma grips and the cut end
      // now share. ⛔The hand copy stayed here after the pair was lifted out
      // (F-163) — two copies of one law, which is the day one of them learns
      // something the other does not.
      child: OwningAxisGrip(
        axis: _dragAxis,
        configure: _configureDrag,
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _pressDown,
          onPointerUp: _pressUp,
          onPointerCancel: _pressCancel,
          child: SizedBox(
            width: vertical ? DockEdgeSplitter.thickness : null,
            height: vertical ? null : DockEdgeSplitter.thickness,
            child: ColoredBox(color: _lineColor),
          ),
        ),
      ),
    );
    final tooltip = widget.tooltip;
    if (tooltip != null) {
      grip = AppTooltip(message: tooltip, child: grip);
    }
    return grip;
  }
}
