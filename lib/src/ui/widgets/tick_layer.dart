import 'package:flutter/widgets.dart';

/// Where what a tick moves is laid out and painted — ALONE.
///
/// 🚨I-22 ③: a tick has to be kept in on both halves, and each half leaks
/// its own way. PAINT: without a boundary the move repaints the region
/// around it (R12-⑥ kept the storyboard's strips out of the playhead's way
/// with one). LAYOUT is Flutter's: a rebuild inside a `LayoutBuilder`'s
/// subtree lays THAT LayoutBuilder out again — it owns the rebuild's build
/// scope — and a layout ends by asking for a paint of everything up to the
/// nearest boundary above it. So a tick rebuilt under a big LayoutBuilder
/// relaid it out and repainted what it holds on every playback frame, a
/// boundary of the tick's own notwithstanding. Measured at the ten-minute
/// zoom (09-27): the transport's readouts relaid out the workspace floor and
/// repainted the PAGE; the frame counters, the dock's panel scroller; the
/// timeline's cursor layer, its frame grid area — and the storyboard's
/// playhead tint and standing ring, its body. This LayoutBuilder takes the
/// rebuild's scope for itself.
///
/// ⚠️It keeps the layout in only where its size is decided from above —
/// TIGHT constraints: a `Positioned.fill`, a box sized on both axes. Handed
/// loose ones it lays its parent out again on every tick, and the boundary
/// holds nothing back.
class TickLayer extends StatelessWidget {
  const TickLayer({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: LayoutBuilder(
      builder: (context, constraints) {
        assert(
          constraints.isTight,
          'A TickLayer keeps its layout in only under tight constraints '
          '(got $constraints).',
        );
        return child;
      },
    ),
  );
}
