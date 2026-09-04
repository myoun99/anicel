import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Where the frame axis should sit after a zoom step (Premiere-style
/// zoom-around-playhead), shared by every frame-axis surface — the
/// horizontal timeline, the X-sheet (transposed) and the storyboard.
///
/// The playhead frame anchors when it is inside the viewport: its on-screen
/// position stays put while the cells stretch around it. When the playhead
/// is off screen (or the surface has none) the viewport's leading-edge
/// content anchors instead — the previous behavior — so zooming far away
/// from the playhead never yanks the view across the track.
double zoomAnchoredScrollOffset({
  required double oldOffset,
  required double oldPixelsPerFrame,
  required double newPixelsPerFrame,
  required double viewportExtent,
  int? anchorFrame,
}) {
  if (anchorFrame != null && viewportExtent > 0) {
    // Anchor on the frame CELL's center, matching the playhead tint.
    final anchorOnScreen = (anchorFrame + 0.5) * oldPixelsPerFrame - oldOffset;
    if (anchorOnScreen >= 0 && anchorOnScreen <= viewportExtent) {
      return math.max(
        0,
        (anchorFrame + 0.5) * newPixelsPerFrame - anchorOnScreen,
      );
    }
  }
  return math.max(0, oldOffset * (newPixelsPerFrame / oldPixelsPerFrame));
}

/// Re-anchors [controller] after the frame cell changed size, if it did.
///
/// ⛔BOTH GRIDS DID THIS IN `didUpdateWidget` — the horizontal timeline and
/// the transposed x-sheet — down to reading the viewport extent off the
/// controller's own position. The AXIS is the only difference, and an axis
/// is not a reason to write a policy twice: the x-sheet's copy already
/// carried a comment saying it was the same policy.
void applyZoomAnchoredScroll(
  ScrollController controller, {
  required double oldPixelsPerFrame,
  required double newPixelsPerFrame,
  int? anchorFrame,
}) {
  if (oldPixelsPerFrame == newPixelsPerFrame || !controller.hasClients) {
    return;
  }
  controller.jumpTo(
    zoomAnchoredScrollOffset(
      oldOffset: controller.offset,
      oldPixelsPerFrame: oldPixelsPerFrame,
      newPixelsPerFrame: newPixelsPerFrame,
      viewportExtent: controller.position.viewportDimension,
      anchorFrame: anchorFrame,
    ),
  );
}
