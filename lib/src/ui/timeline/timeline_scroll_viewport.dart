import 'package:flutter/material.dart';

import '../layout/device_grid_scroll_controller.dart';

/// THE scrollable a timeline axis is made of — the timeline's rows and
/// frames, the x-sheet's frames and layers, the storyboard's two.
///
/// 🚨★★★**A SINGLE-CHILD VIEWPORT CLAMPS AN OVERSCROLL ON EVERY LAYOUT, AND
/// THAT IS WHAT F-4 IS** (유저 2026-08-31): 「왼쪽 최대치 넘어서 드래그하면
/// 타임라인이 오른쪽으로 쭉 밀려서 왼쪽이랑 갭 발생하는 애니메이션이 존재해.
/// 거기서 손 떼면 원래위치로 돌아가고, **이거 마음에 드는데 레이어쪽 드래그
/// 스크롤은 그렇지 않단거야**」.
///
/// `_RenderSingleChildViewport.performLayout` pulls an out-of-range
/// `offset.pixels` back into range every time it runs, through `correctBy` —
/// the one writer that does not pass through `correctPixels`, so nothing an
/// overridden `ScrollPosition` can watch ever fires. `RenderViewport` has no
/// such step: its corrections are the ones a sliver asked for.
///
/// 🧪**Measured, four cells** (`the_axis_that_relayouts_keeps_its_overscroll`):
/// with no relayout both viewports hold the bounce; with a relayout each
/// frame, the single-child one snaps to the edge and the sliver one does
/// not. Exactly one cell is red, and it was the row axis — which re-plans
/// its window every time the finger crosses a row, while the frame axis
/// simply never laid out mid-drag and kept its bounce by luck.
///
/// ⛔**TWO AXES SIT HERE, AND THE OTHER FOUR CANNOT — measured, not chosen.**
/// A sliver viewport EXPANDS across its axis to fill its container, where
/// the single-child one took its child's size. The timeline's rows and
/// frames have a bounded cross extent (the frame axis computes its height
/// already); the x-sheet's two and the storyboard's two sit inside an outer
/// scrollable whose content is intrinsically tall — a `Row` whose height
/// comes from its children — so there is no number to give them, and
/// swapping the viewport there throws 「Horizontal viewport was given
/// unbounded height」 (56 of them on the first run).
///
/// ⚠️**So those four keep the latent bug**: they hold their bounce only
/// because their build does not run during a drag, and the day one of them
/// re-plans mid-drag it will snap to the edge exactly as the rows did.
/// Closing that needs a computed cross extent in those panels — a change to
/// their vertical layout, not to this widget. The board card carries it.
///
/// The content's own device-grid correction ([DeviceGridScrollBody]) stays
/// exactly where it was — inside, wearing the axis's direction.
class TimelineScrollViewport extends StatelessWidget {
  const TimelineScrollViewport({
    super.key,
    required this.viewportKey,
    required this.controller,
    required this.axis,
    required this.child,
  });

  /// The key tests and panels find this axis by — `timeline-frame-scroll-
  /// viewport`, `xsheet-layer-horizontal-viewport`, and the rest.
  final Key viewportKey;

  final ScrollController controller;

  /// Which way it scrolls. The device-grid correction needs the DIRECTION,
  /// and a reverse viewport is refused there for a reason it states, so
  /// this takes the axis and hands over the forward direction.
  final Axis axis;

  final Widget child;

  @override
  Widget build(BuildContext context) => CustomScrollView(
    key: viewportKey,
    controller: controller,
    scrollDirection: axis,
    slivers: <Widget>[
      SliverToBoxAdapter(
        child: DeviceGridScrollBody(
          controller: controller,
          axisDirection: axis == Axis.horizontal
              ? AxisDirection.right
              : AxisDirection.down,
          child: child,
        ),
      ),
    ],
  );
}
