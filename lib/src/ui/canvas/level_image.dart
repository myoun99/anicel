import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show visibleForTesting;

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
/// ONE PLACE for the cel images' levels (`LayerFrameImageCache`) and the
/// active layer's level tiles (`TilePyramid`, 4c): the same halving, so
/// the two cannot drift by a rounding. The caller rasterises: `toImageSync`
/// where the level is needed in the frame (a tile's), `toImage` where a
/// frame of latency is fine (a cel's).
ui.Picture halvingPicture(Iterable<LevelSource> sources) {
  final recorder = ui.PictureRecorder();
  drawHalvings(ui.Canvas(recorder), sources);
  return recorder.endRecording();
}

/// Draws each of [sources] onto [canvas] halved at its place — the body of
/// [halvingPicture], open so a spy canvas can read which draw each source
/// took (no picture can: the two draws below make the same bytes).
///
/// 🚨★★★AN EVEN IMAGE IS ONE TEXTURE DRAW, not a rect under an image shader
/// (2026-09-24, measured on the real Windows app, Impeller GLES): a bilinear
/// `drawImageRect` at exactly 0.5 IS the halving the shader rect was, the
/// same bytes on the device, the tester's Skia and its Vulkan alike — but
/// the shader rect is the dear way to draw it. A level tile rastered in
/// 2.43 ms against 4.25, and 70 halved tiles in one picture in 3.23 ms
/// against 111.8. Every tile is even, so every level tile goes this way.
///
/// ⛔AN IMAGE WITH AN ODD EDGE KEEPS THE SHADER RECT, for the render
/// round's reason (2026-09-16), which once held for every image: "An image
/// shader rather than `drawImageRect`, for the edge: the shader CLAMPS past
/// the source, so an odd edge's last texel fills its level pixel whole
/// ([halvedSize]) instead of leaving a half-covered column the pixel-centre
/// rule would drop — and a tile's quadrant never samples the tile beside
/// it." An even image has no such edge, and a tile is its own texture drawn
/// whole, so its quadrant cannot reach the tile beside it either. Drawing
/// an odd image as its even part plus the odd column, row and corner by
/// texture draws was tried on 2026-09-24 — the same bytes on the device and
/// on Skia, but up to 4/255 apart at the second level on the tester's
/// Vulkan, whose addressing of a sub-rectangle rounds differently from the
/// whole. An odd image is only ever a whole cel, one rect in its picture,
/// so the shader is paid once per level there, not once per tile.
@visibleForTesting
void drawHalvings(ui.Canvas canvas, Iterable<LevelSource> sources) {
  // Bilinear: at exactly 0.5 the box mean. Never `medium` (above).
  final paint = ui.Paint()
    ..filterQuality = ui.FilterQuality.low
    ..isAntiAlias = false;
  for (final source in sources) {
    final image = source.image;
    if (image.width.isOdd || image.height.isOdd) {
      _drawHalvedUnderShader(canvas, source);
      continue;
    }
    canvas.drawImageRect(
      image,
      ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      ui.Rect.fromLTWH(
        source.at.dx,
        source.at.dy,
        image.width / 2,
        image.height / 2,
      ),
      paint,
    );
  }
}

void _drawHalvedUnderShader(ui.Canvas canvas, LevelSource source) {
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
