import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'device_grid.dart';
import 'render_shifted_child.dart';

/// Lands a scrollable's CONTENT on the device-pixel grid without touching
/// the scroll position.
///
/// 🎯**The largest remaining source of soft edges.** Measured on the real
/// workspace at an effective 1.35: of the 356 painted boxes whose edges are
/// off the device grid, **224 sit inside a `SingleChildScrollView`** — and
/// that count sees only single-child viewports, so the true population is
/// larger. A panel that scrolls carries its whole subtree at whatever
/// fractional offset the last gesture left, so without this every other
/// quantization in the round is correct at exactly one scroll position.
///
/// What it buys, measured over 60 scroll steps at 1.35: the blit phase goes
/// from **60 distinct phases to 1**, worst residue `4.995e-1` → `3.6e-15`.
/// Zero extra bakes (`RenderStaticRaster.captureCount` delta is 0 either
/// way — the viewport is its own repaint boundary and a baked child is
/// composited at a new layer offset rather than repainted), and no layer:
/// the child is painted at the corrected offset, on the viewport's own.
///
/// ## ⛔ Why the POSITION is not snapped
///
/// A `ScrollPosition` that rounds `pixels` on the way in stops scrolling
/// working. A drag step of 0.37 logical is 0.4995 device px at 1.35, which
/// rounds to **zero**: every step lands back where it started. Measured on
/// the first draft — 111 logical px of finger travel produced an offset of
/// 0.0. Flooring instead trades that for the content walking behind the
/// finger, which is the defect this codebase already records for the region
/// detent.
///
/// ⛔The other tempting alternative, snapping only when a drag settles via
/// `ScrollPhysics.createBallisticSimulation`, was built and measured: it
/// accumulates **23.4 device px** in the timeline's own auto-pan, because
/// a programmatic scroll never produces the settle the snap hangs off.
///
/// So the position stays EXACT — physics, ballistics and the scrollbar keep
/// the number they had — and only the paint is corrected, read from the
/// position AS IT PAINTS: after every layout of the frame, so a position
/// the viewport pulled back in its own layout (F-95) is the one the content
/// lands by, and the one what follows it lands by ([ScrollFollower]).
/// ↩️It was read as the body BUILT, and a pull in layout tells no listener:
/// the cells kept the old nudge while the ruler beside them took the new
/// one, 1/6 px apart at 1.5 (10-11), and off the grid until something built
/// them again.
///
/// ⚠️It needs no listener because it stands INSIDE the viewport it
/// corrects: the viewport repaints at every change of its position — a
/// scroll, and its own layout's pull — and paints this with it. Outside a
/// viewport nothing would; that is [ScrollFollower].
///
/// ## ⚠️ It stabilises the phase; it does not always LAND the content
///
/// The correction cancels the scroll offset's fraction and nothing else.
/// An off-grid ancestor or an unquantized padding inside the viewport keeps
/// its own fraction: measured at 1.35, a body padding of 8 leaves `2.0e-1`
/// and one of 10 leaves `5.0e-1`, against `7.1e-15` at zero padding. That
/// is still worth having — one phase instead of sixty — but quantize the
/// padding at a site before quoting a residue for it.
///
/// ⚠️And correct OUTERMOST FIRST. A leaf scroller corrected under an
/// uncorrected one measured `4.985e-1`; both corrected, `1.4e-14`. This is
/// [DeviceGrid]'s "every anchor is already on the grid" one level up.
class DeviceGridScrollBody extends StatelessWidget {
  const DeviceGridScrollBody({
    super.key,
    required this.controller,
    required this.axisDirection,
    required this.child,
  }) : assert(
         axisDirection == AxisDirection.down ||
             axisDirection == AxisDirection.right,
         'A reverse viewport needs the OPPOSITE correction, and it cannot be '
         'made exact from the scroll position alone: its paint offset also '
         'carries (viewportExtent - contentExtent), which is off the grid on '
         'its own and is unrecoverable when the content does not overflow '
         '(maxScrollExtent clamps to 0). Quantize that extent instead — it is '
         'a layout problem, not a scroll-offset one.',
       );

  /// The controller of the scrollable this body sits inside.
  final ScrollController controller;

  /// 🚨The DIRECTION, not the axis. `_RenderSingleChildViewport` computes
  /// its paint offset with a four-way switch, and the position term carries
  /// the OPPOSITE sign for `up`/`left`. Measured at 1.35: applying the
  /// forward correction to a reverse viewport leaves `1.19e-1` instead of
  /// `9.1e-13` — it doubles the error rather than cancelling it. `Axis`
  /// cannot tell the two apart, which is why this parameter is not one.
  final AxisDirection axisDirection;

  final Widget child;

  /// ⛔ALWAYS mounts the correction, even at zero. Mounting it
  /// conditionally changes the widget type at that slot, so element
  /// reconciliation deactivates the entire scrolled subtree — every `State`,
  /// `AnimationController`, text selection, focus node and nested
  /// `ScrollPosition` below it. Measured: 7 `State` inits across 7 scroll
  /// jumps with the early-out, 1 without. And the resting offset is 0,
  /// which IS on the grid, so the first sub-pixel scroll of every panel in
  /// the app would have destroyed it.
  @override
  Widget build(BuildContext context) => _LandedOnTheGrid(
    controller: controller,
    axis: axisDirectionToAxis(axisDirection),
    grid: DeviceGrid.of(context),
    landing: _Landing.scrolled,
    child: child,
  );
}

/// The nudge that lands content scrolled [pixels] along a forward axis on
/// [grid] — the content inside the scrollable ([DeviceGridScrollBody]) and
/// what follows it from outside ([ScrollFollower]) take the same one, so
/// the two halves land on the same device pixel. Zero on a grid that does
/// not quantize.
///
/// 🚨THE SIGN. A forward viewport paints the content at MINUS the position,
/// so the number that has to land on the grid is `-d`, and the nudge is
/// `round(-d) - (-d)`, i.e. `d - round(d)`. The first draft had this
/// negated, which does not cancel the fraction — it DOUBLES it: the painted
/// position becomes `round(d) - 2d`, so the residue is
/// `dist(2·offset·ratio, ℤ)`. That closed form was confirmed to within
/// 1.4e-14 over 240 steps at five ratios.
double deviceGridScrollCorrection(double pixels, DeviceGrid grid) {
  if (!grid.isActive) {
    return 0;
  }
  final device = pixels * grid.ratio;
  return (device - device.roundToDouble()) / grid.ratio;
}

/// The pixels of the ONE scroll position [controller] drives — null when it
/// drives none or several, or holds no finite pixels yet.
///
/// ⛔`positions.length == 1` before the pixels, because `offset` asserts
/// otherwise. On mobile every controller-less vertical scroll view under a
/// route inherits that route's PrimaryScrollController, so two open panels
/// is enough to bring the frame down.
double? singleScrollPixelsOf(ScrollController controller) {
  final positions = controller.positions;
  if (positions.length != 1) {
    return null;
  }
  final position = positions.single;
  if (!position.hasPixels || !position.pixels.isFinite) {
    return null;
  }
  return position.pixels;
}

/// Content that stands OUTSIDE a scrollable and moves with it — a ruler
/// pinned over the frame cells, a rail beside them. It is moved by the
/// scroll position and landed as the scrolled content itself is
/// ([deviceGridScrollCorrection], F-32).
///
/// 🚨F-95 (유저 2026-09-12): 「패널의 스플리터로 좌우 길이 바꾸면 타임라인
/// 룰러랑 내부 프레임 영역이랑 위치가 좌우 방향으로 어긋남.
/// 근본/구조적으로 어긋나지 않도록」. The three rulers moved by an offset
/// NOTIFIER fed from the controller's listeners, and a viewport that grows
/// past the end of its content pulls its position back during layout
/// (`correctBy`) without calling one. 🧪Measured on the timeline: scrolled
/// to 2635 and widened from 700 to 1300, the cells went to 2035 and the
/// ruler stayed at 2635 — 600px apart, and still apart once settled.
///
/// So the move reads the POSITION as each frame is composited, after every
/// layout that frame did and the paint that placed the cells beside it: a
/// correction made in this frame's layout reaches both halves, and neither
/// can hold an older one.
class ScrollFollower extends StatelessWidget {
  const ScrollFollower({
    super.key,
    required this.controller,
    required this.axisDirection,
    required this.child,
  }) : assert(
         axisDirection == AxisDirection.down ||
             axisDirection == AxisDirection.right,
         'A reverse scroll lands the other way ([DeviceGridScrollBody]).',
       );

  /// The controller of the scrollable this content follows.
  final ScrollController controller;

  /// See [DeviceGridScrollBody.axisDirection].
  final AxisDirection axisDirection;

  final Widget child;

  @override
  Widget build(BuildContext context) => _LandedOnTheGrid(
    controller: controller,
    axis: axisDirectionToAxis(axisDirection),
    grid: DeviceGrid.of(context),
    landing: _Landing.follows,
    child: child,
  );
}

/// Content INSIDE a scrolled body that stands still in its view while the
/// rest scrolls under it — a header graph's tools and guest tags in the
/// view's corners (I-89 ③). [ScrollFollower] the other way round: moved back by the
/// scroll position, read as the frame is composited, less the nudge the
/// content lands by — so it neither trails a position a viewport corrects
/// in its own layout (F-95) nor walks a fraction of a device pixel against
/// the view with every step (F-32).
///
/// 🧪The tags were first laid out from the offset NOTIFIER: laid out again
/// every pixel, and 0.06px off the sheet's view scrolled to 5305.06.
class ScrollStill extends StatelessWidget {
  const ScrollStill({
    super.key,
    required this.controller,
    required this.axisDirection,
    required this.child,
  }) : assert(
         axisDirection == AxisDirection.down ||
             axisDirection == AxisDirection.right,
         'A reverse scroll lands the other way ([DeviceGridScrollBody]).',
       );

  /// The controller of the scrollable whose body this stands in.
  final ScrollController controller;

  /// See [DeviceGridScrollBody.axisDirection].
  final AxisDirection axisDirection;

  final Widget child;

  @override
  Widget build(BuildContext context) => _LandedOnTheGrid(
    controller: controller,
    axis: axisDirectionToAxis(axisDirection),
    grid: DeviceGrid.of(context),
    landing: _Landing.standsStill,
    child: child,
  );
}

/// Where what a [_LandedOnTheGrid] holds stands against its scroll.
enum _Landing {
  /// Inside the scrollable, carried by it ([DeviceGridScrollBody]).
  scrolled,

  /// Outside it, following it ([ScrollFollower]) — then nothing carries it
  /// along, and nothing paints it as the position changes.
  follows,

  /// Inside it, standing still in its view ([ScrollStill]) — carried, and
  /// moved back as far.
  standsStill,
}

/// The halves of a scroll — what is scrolled ([DeviceGridScrollBody]), what
/// follows it from outside ([ScrollFollower]) and what stands still inside
/// it ([ScrollStill]) — landed by the one object, so they read the one
/// position at the one moment.
class _LandedOnTheGrid extends SingleChildRenderObjectWidget {
  const _LandedOnTheGrid({
    required this.controller,
    required this.axis,
    required this.grid,
    required this.landing,
    required Widget super.child,
  });

  final ScrollController controller;
  final Axis axis;
  final DeviceGrid grid;
  final _Landing landing;

  @override
  RenderObject createRenderObject(BuildContext context) => switch (landing) {
    _Landing.scrolled => _RenderLandedOnTheGrid(
      controller: controller,
      axis: axis,
      grid: grid,
    ),
    _Landing.follows => _RenderFollowingTheScroll(
      controller: controller,
      axis: axis,
      grid: grid,
    ),
    _Landing.standsStill => _RenderStandingStill(
      controller: controller,
      axis: axis,
      grid: grid,
    ),
  };

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderLandedOnTheGrid renderObject,
  ) {
    renderObject
      ..controller = controller
      ..axis = axis
      ..grid = grid;
  }
}

/// Paints its child landed on the device grid at the position of
/// [controller] — read as it paints and never kept, since a kept value is
/// the copy F-95 was — and hit-tests it there.
class _RenderLandedOnTheGrid extends RenderProxyBox
    with RenderShiftedChildHitTest {
  _RenderLandedOnTheGrid({
    required this.controller,
    required this.axis,
    required this.grid,
  });

  /// What it lands by, along which axis, on which grid — a change needs no
  /// marking. A new position comes with the viewport's repaint, and so does
  /// a new grid: it is a new ratio, and at a new ratio the scrollable makes
  /// itself a new position (`ScrollableState.didChangeDependencies`), which
  /// lays the viewport out again. What follows from outside reads them as
  /// the frame is composited. ↩️The follower listened, and a new grid
  /// repainted this; the mutants that took each away lived.
  ScrollController controller;
  Axis axis;
  DeviceGrid grid;

  /// How far along [axis] the child is moved, with the position at
  /// [pixels].
  double movedAt(double pixels) => deviceGridScrollCorrection(pixels, grid);

  Offset get _translation {
    final moved = movedAt(singleScrollPixelsOf(controller) ?? 0.0);
    return axis == Axis.horizontal ? Offset(moved, 0) : Offset(0, moved);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child != null) {
      context.paintChild(child, offset + _translation);
    }
  }

  /// ⛔Hit-tested where it is painted. Left out, a tap within half a device
  /// pixel of a row boundary selects the neighbour — invisibly, and only at
  /// some scroll positions. Measured with it in: 360 boundary taps at a
  /// worst correction of 0.4995 device px, zero mismatches.
  @override
  Offset get childPaintOffset => _translation;

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    final translation = _translation;
    transform.translateByDouble(translation.dx, translation.dy, 0, 1);
  }
}

/// What follows a scroll from outside it: moved by minus the position's
/// pixels as well, since nothing carries it.
///
/// 🚨A SCROLL MOVES A LAYER; IT REPAINTS NOTHING
/// (playback-page-turn-repaints-the-whole-timeline, 10-11). The move is this
/// object's own layer's ([_FollowingLayer]), and the child is painted once
/// under it. ↩️It repainted on every pixel of scroll, and being no repaint
/// boundary that repaint climbed to the panel's: 🔬379 of the timeline's
/// render objects for a one-pixel scroll of its frame axis — the same 379 at
/// every page a running playhead turned.
class _RenderFollowingTheScroll extends _RenderLandedOnTheGrid {
  _RenderFollowingTheScroll({
    required super.controller,
    required super.axis,
    required super.grid,
  });

  @override
  double movedAt(double pixels) => super.movedAt(pixels) - pixels;

  @override
  bool get isRepaintBoundary => true;

  @override
  OffsetLayer updateCompositedLayer({
    required covariant _FollowingLayer? oldLayer,
  }) => oldLayer ?? _FollowingLayer(() => _translation);

  /// Painted where it was laid out — its layer moves it.
  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child != null) {
      context.paintChild(child, offset);
    }
  }
}

/// What stands still inside a scroll: carried by the position like all the
/// content, and moved back as far — the follower's move, the other way
/// round. Its layer moves it as the follower's does, so a scroll repaints
/// nothing of it.
class _RenderStandingStill extends _RenderFollowingTheScroll {
  _RenderStandingStill({
    required super.controller,
    required super.axis,
    required super.grid,
  });

  @override
  double movedAt(double pixels) => -super.movedAt(pixels);
}

/// The layer of a [_RenderFollowingTheScroll]: where the framework put it,
/// moved by where the scroll stands as the frame is composited — so it is
/// added to every frame's scene afresh, never retained, and what it holds
/// is retained under it.
class _FollowingLayer extends OffsetLayer {
  _FollowingLayer(this._moveBy);

  final Offset Function() _moveBy;

  /// Where the framework put it.
  Offset _placed = Offset.zero;

  @override
  Offset get offset => _placed + _moveBy();

  /// ⚠️Kept here rather than passed up: the inherited setter marks the layer
  /// for the scene when the place changes, and a layer that is always added
  /// must never be marked (an assertion says so).
  @override
  set offset(Offset value) => _placed = value;

  @override
  bool get alwaysNeedsAddToScene => true;
}
