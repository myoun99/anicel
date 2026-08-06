import 'package:flutter/widgets.dart';

/// The part of the canvas the artist can actually SEE, in layout coordinates.
///
/// The canvas is laid out as one box, but it is not all visible: the app is
/// moving to a full-bleed canvas with surfaces floating ON it — an always-open
/// timeline along one edge, a panel opened from a rail, a view-control cluster
/// in a corner. Those cover the artwork without shrinking the box.
///
/// That split matters because every verb that FRAMES the artwork — fit, fit to
/// a rect, zoom around the centre, rotate and flip around the centre, reveal a
/// rect — asks "where should the picture sit so I can see it", and the box is
/// the wrong answer to that question. Fit against the box puts the bottom of
/// the drawing under the timeline; zoom around the box's centre walks the
/// picture toward the covered edge one press at a time.
///
/// The other half of the split is just as load-bearing: the things that
/// describe the SURFACE rather than the framing — the pan bars' own geometry,
/// the gesture layer's hit area, the shell's memo token — keep taking the
/// layout box, because they are about the surface you touch, not the window
/// you look through.
///
/// [insets] are the edges covered by whatever floats over the canvas. At
/// [EdgeInsets.zero] this returns the whole box and every framing verb reduces
/// to exactly the arithmetic it had before the concept existed, which is why
/// introducing it changes nothing until something actually floats.
Rect canvasVisibleRect(Size layoutSize, EdgeInsets insets) {
  final width = layoutSize.width;
  final height = layoutSize.height;
  if (width <= 0 || height <= 0) {
    return Offset.zero & layoutSize;
  }
  // A cover wider than the box is not an error — a tablet in portrait with a
  // panel open can reach it — and it must not produce a negative or zero
  // window, because every consumer divides by these extents. The floor keeps
  // the rect inside the box and non-degenerate, and it deliberately keeps the
  // LEADING edge: what you were looking at stays where it was.
  const minExtent = 1.0;
  final left = insets.left.clamp(0.0, (width - minExtent).clamp(0.0, width));
  final top = insets.top.clamp(0.0, (height - minExtent).clamp(0.0, height));
  final right = insets.right.clamp(0.0, (width - left - minExtent).clamp(0.0, width));
  final bottom = insets.bottom.clamp(
    0.0,
    (height - top - minExtent).clamp(0.0, height),
  );
  return Rect.fromLTRB(left, top, width - right, height - bottom);
}
