import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

/// 🚨★★★A SUB-TREE IS AN IMAGE — and it is the same pixels `saveLayer` made.
///
/// A folder used to composite through `canvas.saveLayer(bounds, paint)`. That
/// offscreen belongs to Skia: nobody can sample it, so a fragment shader on a
/// FOLDER is impossible and a per-group cache has nothing to keep. Rasterising
/// the sub-tree here makes a group the same kind of thing every other route
/// already hands around — an image — so ONE implementation of an effect can
/// attach at any depth instead of one for cels and another for folders.
///
/// 📐WHY THIS IS THE SAME PIXELS, not merely similar:
///  · the image grid is the LOCAL space at [rasterScale] snapped OUTWARD, and
///    the destination is exactly `pixels / scale`. A src/dst pair that
///    disagreed by a fraction would resample the sub-tree a second time.
///  · the clip reproduces the saveLayer's bounds clip. It is load-bearing
///    WITH A BLUR: saveLayer blurred the children and cut the result at
///    [bounds], while a paint filter on `drawImageRect` would spread a second
///    radius past the image. Same input, same output, same extent.
///
/// ⛔One function, called by the paint AND by the test that certifies it
/// against `saveLayer` — a second copy of this arithmetic in a test would
/// certify the copy and let the original drift.
void drawSubtreeAsImage({
  required Canvas canvas,
  required Rect bounds,
  required Paint paint,
  required double rasterScale,
  required int maxPixelSide,
  required void Function(Canvas into, double rasterScale) paintSubtree,
}) {
  var scale = rasterScale;
  final side = bounds.width > bounds.height ? bounds.width : bounds.height;
  if (side * scale > maxPixelSide) {
    // A view so magnified the sub-tree alone overflows the cap: shrink, the
    // way the display buffer does one level up. Still one uniform resample —
    // softer, never seamed, and never a second code path an effect could
    // miss.
    scale = maxPixelSide / side;
  }
  final snapped = Rect.fromLTRB(
    (bounds.left * scale).floorToDouble() / scale,
    (bounds.top * scale).floorToDouble() / scale,
    (bounds.right * scale).ceilToDouble() / scale,
    (bounds.bottom * scale).ceilToDouble() / scale,
  );
  final width = (snapped.width * scale).round();
  final height = (snapped.height * scale).round();
  if (width <= 0 || height <= 0) {
    return;
  }
  final recorder = ui.PictureRecorder();
  final into = Canvas(recorder);
  into.scale(scale);
  into.translate(-snapped.left, -snapped.top);
  paintSubtree(into, scale);
  final picture = recorder.endRecording();
  final image = picture.toImageSync(width, height);
  picture.dispose();
  // `none` because the blit below is 1:1 by construction. It stops being 1:1
  // only when the cap clamped the scale, and that is a magnification — the
  // one case that wants a filter.
  paint.filterQuality = scale == rasterScale
      ? FilterQuality.none
      : FilterQuality.low;
  canvas.save();
  canvas.clipRect(bounds, doAntiAlias: false);
  try {
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      snapped,
      paint,
    );
  } finally {
    // ⚠️Safe HERE and nowhere earlier: the draw put the image into this
    // frame's display list and the engine holds its own claim from that
    // moment. What `dispose` releases is this handle, not the pixels the
    // list is going to replay.
    image.dispose();
    canvas.restore();
  }
}
