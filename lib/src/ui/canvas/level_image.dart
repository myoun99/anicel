import 'dart:typed_data';
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
/// An image shader rather than `drawImageRect`, for the edge: the shader
/// CLAMPS past the source, so an odd edge's last texel fills its level
/// pixel whole ([halvedSize]) instead of leaving a half-covered column the
/// pixel-centre rule would drop — and a tile's quadrant never samples the
/// tile beside it.
///
/// ONE PLACE for the cel images' levels (`LayerFrameImageCache`) and the
/// active layer's level tiles (`TilePyramid`, 4c): the same halving, so
/// the two cannot drift by a rounding. The caller rasterises: `toImageSync`
/// where the level is needed in the frame (a tile's), `toImage` where a
/// frame of latency is fine (a cel's).
ui.Picture halvingPicture(Iterable<LevelSource> sources) {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  for (final source in sources) {
    final half = Float64List(16)
      ..[0] = 0.5
      ..[5] = 0.5
      ..[10] = 1
      ..[12] = source.at.dx
      ..[13] = source.at.dy
      ..[15] = 1;
    final size = halvedSize(source.image.width, source.image.height);
    canvas.drawRect(
      ui.Rect.fromLTWH(
        source.at.dx,
        source.at.dy,
        size.width.toDouble(),
        size.height.toDouble(),
      ),
      ui.Paint()
        ..shader = ui.ImageShader(
          source.image,
          ui.TileMode.clamp,
          ui.TileMode.clamp,
          half,
          filterQuality: ui.FilterQuality.low,
        )
        ..isAntiAlias = false,
    );
  }
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
