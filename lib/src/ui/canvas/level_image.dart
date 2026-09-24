import 'dart:ui' as ui;

/// A source of one level picture: an image and where its halved self lands
/// in the level — the origin for a cel's single image, a quadrant for each
/// of the four pictures under a level tile.
typedef LevelSource = ({ui.Image image, ui.Offset at});

/// One level of the display's pyramid: the picture that draws each of
/// [sources] at half size at its place, each level pixel the exact mean of
/// a 2×2 block of its source (render round, 안 1 「선명」, 2026-09-16).
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
/// 🚨★★★A TEXTURE DRAW, NOT AN IMAGE SHADER (2026-09-24, measured on the
/// real Windows app, Impeller GLES): a bilinear `drawImageRect` at 0.5 IS
/// the halving an image-shader rect was — the same bytes, a tile's four
/// quadrants and a cel's 70 tiles alike, and the old whole-then-halve too —
/// but the shader rect is the dear way to draw it. A level tile rastered in
/// 2.43 ms against 4.25, and 70 halved tiles in one picture in 3.23 ms
/// against 111.8 ([_drawHalved] says how the odd edge keeps its bytes).
///
/// 🪦An image shader stood here from the render round (2026-09-16) "for the
/// edge": it CLAMPS past the source, so an odd edge's last texel filled its
/// level pixel whole ([halvedSize]). The edge is drawn on its own now, 1:1
/// across it, which is the same mean — the texel and its clamped self.
///
/// ONE PLACE for the cel images' levels (`LayerFrameImageCache`) and the
/// active layer's level tiles (`TilePyramid`, 4c): the same halving, so
/// the two cannot drift by a rounding. The caller rasterises: `toImageSync`
/// where the level is needed in the frame (a tile's), `toImage` where a
/// frame of latency is fine (a cel's).
ui.Picture halvingPicture(Iterable<LevelSource> sources) {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  // Bilinear: at exactly 0.5 the box mean, at 1:1 across an odd edge the
  // texel itself. Never `medium` (above).
  final paint = ui.Paint()
    ..filterQuality = ui.FilterQuality.low
    ..isAntiAlias = false;
  for (final source in sources) {
    _drawHalved(canvas, source, paint);
  }
  return recorder.endRecording();
}

/// [source] drawn onto [canvas] at half size at its place.
///
/// The even part of the image in one bilinear draw at exactly 0.5: every
/// level pixel's centre lands on the middle of its 2×2 block, the box mean.
/// An odd edge's last column (row) is its own level column (row), drawn 1:1
/// across it and halved along it — the mean of the texel and itself — and
/// an odd corner is its texel. Every draw samples inside its own source, so
/// a tile's quadrant never reads the tile beside it. (An image one texel
/// wide has no even part: that draw is empty, and so draws nothing.)
void _drawHalved(ui.Canvas canvas, LevelSource source, ui.Paint paint) {
  final image = source.image;
  final evenWidth = (image.width & ~1).toDouble();
  final evenHeight = (image.height & ~1).toDouble();
  final x = source.at.dx;
  final y = source.at.dy;
  final middle = ui.Offset(x + evenWidth / 2, y + evenHeight / 2);
  void blit(ui.Rect from, ui.Rect to) =>
      canvas.drawImageRect(image, from, to, paint);

  blit(
    ui.Rect.fromLTWH(0, 0, evenWidth, evenHeight),
    ui.Rect.fromLTRB(x, y, middle.dx, middle.dy),
  );
  if (image.width.isOdd) {
    blit(
      ui.Rect.fromLTWH(evenWidth, 0, 1, evenHeight),
      ui.Rect.fromLTRB(middle.dx, y, middle.dx + 1, middle.dy),
    );
  }
  if (image.height.isOdd) {
    blit(
      ui.Rect.fromLTWH(0, evenHeight, evenWidth, 1),
      ui.Rect.fromLTRB(x, middle.dy, middle.dx, middle.dy + 1),
    );
  }
  if (image.width.isOdd && image.height.isOdd) {
    blit(
      ui.Rect.fromLTWH(evenWidth, evenHeight, 1, 1),
      ui.Rect.fromLTWH(middle.dx, middle.dy, 1, 1),
    );
  }
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
