import 'package:flutter/widgets.dart';

import 'device_grid.dart';

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
    // ⛔`positions.length == 1` before `offset`, which asserts otherwise.
    // On mobile every controller-less vertical scroll view under a route
    // inherits that route's PrimaryScrollController, so two open panels is
    // enough to bring the frame down.
    if (controller.positions.length != 1) {
      return Offset.zero;
    }
    final offset = controller.offset;
    if (!offset.isFinite) {
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
