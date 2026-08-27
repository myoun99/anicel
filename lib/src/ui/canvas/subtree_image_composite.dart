import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

/// What [drawSubtreeAsImage] actually rasterised, so a test can read the
/// GEOMETRY rather than infer it from pixels. The arithmetic there decides
/// whether a group resamples twice, and a scene where the difference happens
/// to land on transparent margin would report "same pixels" about a grid that
/// had already drifted.
@visibleForTesting
class SubtreeRaster {
  const SubtreeRaster({
    required this.destination,
    required this.pixelWidth,
    required this.pixelHeight,
    required this.scale,
    required this.filterQuality,
  });

  /// The rect the image was blitted into — the bounds snapped OUTWARD to the
  /// raster grid, never the bounds themselves.
  final Rect destination;
  final int pixelWidth;
  final int pixelHeight;

  /// The raster scale as asked for, unless the cap had to clamp it.
  final double scale;
  final FilterQuality filterQuality;
}

/// ⚠️Written under `assert`, so it costs a release build nothing and a test
/// everything it needs.
@visibleForTesting
SubtreeRaster? debugLastSubtreeRaster;

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
///  · the clip reproduces the saveLayer's bounds clip, which is what keeps
///    "a group never paints outside its bounds" true — the property the
///    stack's containment assert leans on. It matters because the two things
///    that can push past [bounds] do not know about each other: the outward
///    snap widens the destination by up to a device pixel, and a filter on
///    [paint] spreads past the image it is given (`saveLayer` blurred the
///    children INSIDE the layer and cut the result; a filter on
///    `drawImageRect` blurs the finished image and spreads again).
///    ⚠️Today's only filter arrives with [bounds] already inflated by its
///    spread (`effectBufferBounds`), so the clip cuts nothing — it is what
///    makes the guarantee hold for the next filter that does not.
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
  // 🚨THE SNAP IS PART OF THE CAP. Clamping the scale alone left the cap off
  // by one: `side * scale` landed exactly on the cap and then the OUTWARD
  // snap widened it, so the image came back one pixel over the limit it was
  // clamped to. The snap can add up to a whole device pixel at each edge, so
  // the room for both has to come out of the scale.
  final headroom = maxPixelSide - 2;
  if (side * scale > headroom) {
    // A view so magnified the sub-tree alone overflows the cap: shrink, the
    // way the display buffer does one level up. Still one uniform resample —
    // softer, never seamed, and never a second code path an effect could
    // miss.
    scale = headroom / side;
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
  assert(() {
    debugLastSubtreeRaster = SubtreeRaster(
      destination: snapped,
      pixelWidth: width,
      pixelHeight: height,
      scale: scale,
      filterQuality: paint.filterQuality,
    );
    return true;
  }());
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
