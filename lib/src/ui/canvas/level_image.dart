import 'dart:typed_data';
import 'dart:ui' as ui;

/// One level of the display's pyramid: the picture that draws [source] at
/// half size, each pixel the exact mean of a 2×2 block of the source
/// (render round, 안 1 「선명」, 2026-09-16).
///
/// 🚨★★★A HALVING, NEVER A ONE-STEP REDUCTION. Bilinear at exactly 0.5
/// samples the midpoint of every 2×2 block, which IS the box filter —
/// exact, on every engine. One bilinear step to a quarter samples 2×2 of
/// each 4×4 block and aliases; `FilterQuality.medium` mipmaps on Skia and,
/// on Impeller, only where the texture was uploaded with mip levels — a
/// deferred `toImageSync` image has none — so a picture reduced that way
/// is sharp on one machine and shimmers on another. Two halvings are the
/// same bytes everywhere. Deeper levels are made from the level above, one
/// halving at a time.
///
/// An image shader rather than `drawImageRect`, for the edge: the shader
/// CLAMPS past the source, so an odd edge's last texel fills its level
/// pixel whole ([halvedSize]) instead of leaving a half-covered column the
/// pixel-centre rule would drop.
///
/// The caller rasterises: `toImageSync` where the level is needed in the
/// frame (a tile's), `toImage` where a frame of latency is fine (a cel's).
ui.Picture halvingPicture(ui.Image source) {
  final size = halvedSize(source.width, source.height);
  final recorder = ui.PictureRecorder();
  final half = Float64List(16)
    ..[0] = 0.5
    ..[5] = 0.5
    ..[10] = 1
    ..[15] = 1;
  final paint = ui.Paint()
    ..shader = ui.ImageShader(
      source,
      ui.TileMode.clamp,
      ui.TileMode.clamp,
      half,
      filterQuality: ui.FilterQuality.low,
    )
    ..isAntiAlias = false;
  ui.Canvas(recorder).drawRect(
    ui.Rect.fromLTWH(0, 0, size.width.toDouble(), size.height.toDouble()),
    paint,
  );
  return recorder.endRecording();
}

/// The size of [width] × [height] halved: ⌈w/2⌉ × ⌈h/2⌉.
///
/// An odd edge keeps its last texel as a whole level pixel (the mean of
/// that texel and its clamped neighbour), so the level maps back onto the
/// artwork at EXACTLY half — twice its own size, one texel past an odd
/// edge. A level of ⌊w/2⌋ would map at w/(2⌊w/2⌋) instead, a hair off 1:1,
/// and nearest sampling of it would double a column somewhere in every
/// row.
({int width, int height}) halvedSize(int width, int height) =>
    (width: (width + 1) ~/ 2, height: (height + 1) ~/ 2);

/// The size of [width] × [height] at [level]: halved [level] times.
({int width, int height}) sizeAtLevel(int width, int height, int level) {
  var size = (width: width, height: height);
  for (var i = 0; i < level; i += 1) {
    size = halvedSize(size.width, size.height);
  }
  return size;
}
