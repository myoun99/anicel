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
/// `RenderTransform.paint` takes the pure-translation branch, so
/// `debugLayer` stays null.
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
/// offset the widget already holds in the same build. Nothing is a frame
/// late and nothing is measured from the render tree.
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

  @override
  Widget build(BuildContext context) {
    final grid = DeviceGrid.of(context);
    return AnimatedBuilder(
      animation: controller,
      // ⚠️`child` is passed through rather than rebuilt: the correction
      // changes on every scroll frame and the subtree must not.
      child: child,
      builder: (context, body) {
        return Transform.translate(
          offset: _correction(grid),
          // ⛔Must stay true. With it false a tap within half a device
          // pixel of a row boundary selects the neighbour — invisibly, and
          // only at some scroll positions. Measured with it on: 360
          // boundary taps at a worst correction of 0.4995 device px, zero
          // mismatches.
          transformHitTests: true,
          child: body,
        );
      },
    );
  }

  /// ⛔ALWAYS returns a Transform, even at zero. Mounting it conditionally
  /// changes the widget type at that slot, so element reconciliation
  /// deactivates the entire scrolled subtree — every `State`,
  /// `AnimationController`, text selection, focus node and nested
  /// `ScrollPosition` below it. Measured: 7 `State` inits across 7 scroll
  /// jumps with the early-out, 1 without. And the resting offset is 0,
  /// which IS on the grid, so the first sub-pixel scroll of every panel in
  /// the app would have destroyed it.
  Offset _correction(DeviceGrid grid) {
    if (!grid.isActive) {
      return Offset.zero;
    }
    final offset = singleScrollPixelsOf(controller);
    if (offset == null) {
      return Offset.zero;
    }
    // 🚨THE SIGN. A forward viewport paints the content at MINUS the
    // position, so the number that has to land on the grid is `-d`, and the
    // nudge is `round(-d) - (-d)`, i.e. `d - round(d)`. The first draft had
    // this negated, which does not cancel the fraction — it DOUBLES it:
    // the painted position becomes `round(d) - 2d`, so the residue is
    // `dist(2·offset·ratio, ℤ)`. That closed form was confirmed to within
    // 1.4e-14 over 240 steps at five ratios.
    final device = offset * grid.ratio;
    final correction = (device - device.roundToDouble()) / grid.ratio;
    return axisDirection == AxisDirection.down
        ? Offset(0, correction)
        : Offset(correction, 0);
  }
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
/// pinned over the frame cells, a rail beside them. It is translated by the
/// scroll position and landed by [DeviceGridScrollBody], the correction the
/// scrolled content itself wears (F-32).
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
/// So the translate reads the POSITION when it paints, which is when the
/// viewport beside it reads the same number to place its cells: a
/// correction made in this frame's layout reaches both halves, and neither
/// can hold an older one.
class ScrollFollower extends StatelessWidget {
  const ScrollFollower({
    super.key,
    required this.controller,
    required this.axisDirection,
    required this.child,
  });

  /// The controller of the scrollable this content follows.
  final ScrollController controller;

  /// See [DeviceGridScrollBody.axisDirection].
  final AxisDirection axisDirection;

  final Widget child;

  @override
  Widget build(BuildContext context) => DeviceGridScrollBody(
    controller: controller,
    axisDirection: axisDirection,
    child: _ScrollPositionTranslate(
      controller: controller,
      axis: axisDirectionToAxis(axisDirection),
      child: child,
    ),
  );
}

class _ScrollPositionTranslate extends SingleChildRenderObjectWidget {
  const _ScrollPositionTranslate({
    required this.controller,
    required this.axis,
    required Widget super.child,
  });

  final ScrollController controller;
  final Axis axis;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderScrollPositionTranslate(controller: controller, axis: axis);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderScrollPositionTranslate renderObject,
  ) {
    renderObject
      ..controller = controller
      ..axis = axis;
  }
}

/// Paints and hit-tests its child at minus the position's pixels, read AT
/// THAT MOMENT and never kept — a kept value is the copy F-95 was.
class _RenderScrollPositionTranslate extends RenderProxyBox
    with RenderShiftedChildHitTest {
  _RenderScrollPositionTranslate({
    required ScrollController controller,
    required Axis axis,
  }) : _controller = controller,
       _axis = axis;

  ScrollController get controller => _controller;
  ScrollController _controller;
  set controller(ScrollController value) {
    if (identical(value, _controller)) {
      return;
    }
    if (attached) {
      _controller.removeListener(markNeedsPaint);
      value.addListener(markNeedsPaint);
    }
    _controller = value;
    markNeedsPaint();
  }

  Axis get axis => _axis;
  Axis _axis;
  set axis(Axis value) {
    if (value == _axis) {
      return;
    }
    _axis = value;
    markNeedsPaint();
  }

  Offset get _translation {
    final pixels = singleScrollPixelsOf(_controller) ?? 0.0;
    return _axis == Axis.horizontal ? Offset(-pixels, 0) : Offset(0, -pixels);
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _controller.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _controller.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child != null) {
      context.paintChild(child, offset + _translation);
    }
  }

  @override
  Offset get childPaintOffset => _translation;

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    final translation = _translation;
    transform.translateByDouble(translation.dx, translation.dy, 0, 1);
  }
}
