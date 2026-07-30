import 'dart:typed_data';
import 'dart:ui' as ui;

import '../../models/bitmap_surface.dart';
import '../../models/bitmap_tile.dart';
import '../../models/brush_frame_key.dart';
import '../../models/canvas_size.dart';
import '../../models/media_asset.dart' show MediaFitMode;
import '../../models/pasteboard_bounds.dart';
import '../../models/tile_coord.dart';
import '../brush_frame_store.dart';

/// Decode-and-bake for the import system: an image FILE becomes a cel's
/// [BitmapSurface] — the same store shape a drawn cel has, so every
/// display/export/thumbnail path works untouched (the "one seam" rule:
/// pixels only ever come from the store). The REFERENCE field on the
/// layer is provenance; the pixels live here either way, which is what
/// makes "rasterize = null the field, nothing else" true.

/// One decoded source frame (GIF frames carry their delay; stills have
/// [duration] zero).
class DecodedImageFrame {
  const DecodedImageFrame({required this.image, required this.duration});

  final ui.Image image;
  final Duration duration;
}

/// Decodes every frame of [bytes] (PNG/JPEG = one, GIF = many) through
/// the platform codec — the repo's established recipe
/// (decodeBrushTipImage does the single-frame version).
Future<List<DecodedImageFrame>> decodeImageFrames(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  try {
    final frames = <DecodedImageFrame>[];
    for (var i = 0; i < codec.frameCount; i += 1) {
      final frame = await codec.getNextFrame();
      frames.add(
        DecodedImageFrame(image: frame.image, duration: frame.duration),
      );
    }
    return frames;
  } finally {
    codec.dispose();
  }
}

/// The placement rect [fit] gives [source] on [canvas] (§6-q: fit is a
/// placement decision): stretch fills the canvas, contain letterboxes
/// inside it, none centers 1:1 (the pasteboard keeps the overflow).
ui.Rect placementRectFor({
  required int sourceWidth,
  required int sourceHeight,
  required CanvasSize canvas,
  required MediaFitMode fit,
}) {
  final canvasWidth = canvas.width.toDouble();
  final canvasHeight = canvas.height.toDouble();
  switch (fit) {
    case MediaFitMode.stretch:
      return ui.Rect.fromLTWH(0, 0, canvasWidth, canvasHeight);
    case MediaFitMode.contain:
      final scale = (canvasWidth / sourceWidth) < (canvasHeight / sourceHeight)
          ? canvasWidth / sourceWidth
          : canvasHeight / sourceHeight;
      final width = sourceWidth * scale;
      final height = sourceHeight * scale;
      return ui.Rect.fromLTWH(
        (canvasWidth - width) / 2,
        (canvasHeight - height) / 2,
        width,
        height,
      );
    case MediaFitMode.none:
      return ui.Rect.fromLTWH(
        (canvasWidth - sourceWidth) / 2,
        (canvasHeight - sourceHeight) / 2,
        sourceWidth.toDouble(),
        sourceHeight.toDouble(),
      );
  }
}

/// Rasterizes [image] into a [BitmapSurface] at [canvas]'s exact size
/// (the store's hard gate: a cel sized for another canvas is invisible
/// everywhere). The raster covers the canvas rect UNION the placement
/// rect clipped to the pasteboard — fit=none overflow lives on the
/// pasteboard exactly like an oversized selection drop.
///
/// [placement] overrides the [fit] math when the caller already knows
/// exactly where the image goes (the text bake renders its own bounds);
/// the wall clip and tile slice below treat it like any other placement.
Future<BitmapSurface> rasterizeImageToSurface({
  required ui.Image image,
  required CanvasSize canvas,
  required MediaFitMode fit,
  ui.Rect? placement,
  int tileSize = 256,
}) async {
  placement ??= placementRectFor(
    sourceWidth: image.width,
    sourceHeight: image.height,
    canvas: canvas,
    fit: fit,
  );
  // The pasteboard wall (tiles beyond it are refused by the surface).
  final wall = ui.Rect.fromLTRB(
    canvas.pasteboardLeft.toDouble(),
    canvas.pasteboardTop.toDouble(),
    canvas.pasteboardRightExclusive.toDouble(),
    canvas.pasteboardBottomExclusive.toDouble(),
  );
  final clipped = placement.intersect(wall);
  if (clipped.isEmpty) {
    return BitmapSurface(canvasSize: canvas, tileSize: tileSize);
  }

  // Tile span covered by the placement.
  int floorDiv(int a, int b) => (a / b).floor();
  final left = clipped.left.floor();
  final top = clipped.top.floor();
  final right = clipped.right.ceil();
  final bottom = clipped.bottom.ceil();
  final tileX0 = floorDiv(left, tileSize);
  final tileY0 = floorDiv(top, tileSize);
  final tileX1 = floorDiv(right - 1, tileSize);
  final tileY1 = floorDiv(bottom - 1, tileSize);

  // Raster the placed image ONCE over the covered tile block, then slice
  // into tiles. The recorder canvas is translated so the block's origin
  // is (0,0).
  final blockWidth = (tileX1 - tileX0 + 1) * tileSize;
  final blockHeight = (tileY1 - tileY0 + 1) * tileSize;
  final recorder = ui.PictureRecorder();
  final paintCanvas = ui.Canvas(recorder);
  paintCanvas.translate(
    -(tileX0 * tileSize).toDouble(),
    -(tileY0 * tileSize).toDouble(),
  );
  // A 1:1 integer-aligned placement must copy bytes, not resample:
  // bicubic (high) blurs even at identity — a hard black line came back
  // 28/255 gray through the cubic kernel — and the text bake's whole
  // contract is that the store pixels ARE the engine render.
  final identityPlacement =
      placement.width == image.width.toDouble() &&
      placement.height == image.height.toDouble() &&
      placement.left == placement.left.truncateToDouble() &&
      placement.top == placement.top.truncateToDouble();
  paintCanvas.drawImageRect(
    image,
    ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
    placement,
    ui.Paint()
      ..filterQuality = identityPlacement
          ? ui.FilterQuality.none
          : ui.FilterQuality.high
      ..isAntiAlias = true,
  );
  final picture = recorder.endRecording();
  final raster = await picture.toImage(blockWidth, blockHeight);
  picture.dispose();
  try {
    final data = await raster.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    if (data == null) {
      throw StateError('Image rasterization produced no bytes.');
    }
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    final rowStride = blockWidth * 4;

    final tiles = <BitmapTile>[];
    final tilePixels = Uint8List(tileSize * tileSize * 4);
    for (var ty = tileY0; ty <= tileY1; ty += 1) {
      for (var tx = tileX0; tx <= tileX1; tx += 1) {
        final blockX = (tx - tileX0) * tileSize;
        final blockY = (ty - tileY0) * tileSize;
        var any = false;
        for (var row = 0; row < tileSize; row += 1) {
          final srcStart = (blockY + row) * rowStride + blockX * 4;
          final dstStart = row * tileSize * 4;
          tilePixels.setRange(
            dstStart,
            dstStart + tileSize * 4,
            bytes,
            srcStart,
          );
          if (!any) {
            for (var i = dstStart + 3; i < dstStart + tileSize * 4; i += 4) {
              if (tilePixels[i] != 0) {
                any = true;
                break;
              }
            }
          }
        }
        if (!any) {
          continue; // Fully transparent tile — the surface stays sparse.
        }
        tiles.add(
          BitmapTile(
            coord: TileCoord(x: tx, y: ty),
            size: tileSize,
            pixels: tilePixels,
          ),
        );
      }
    }
    return BitmapSurface(
      canvasSize: canvas,
      tileSize: tileSize,
    ).putTiles(tiles);
  } finally {
    raster.dispose();
  }
}

/// Bakes [surface] as [key]'s cel — the exact donation pair the drawing
/// commit uses (display cache seeds the frame state, then the baked
/// truth + the edit mark), so playback/thumbnails see the cel
/// immediately and the tint flips through the store's own crossing
/// signal.
void bakeCelSurface(
  BrushFrameStore store,
  BrushFrameKey key,
  BitmapSurface surface,
) {
  // Mark-edited FIRST, then donate — the drawing commit's order, which
  // leaves the donated display cache VALID (the reverse order dirtied
  // the cache it had just stored, wasting the donation on first paint).
  store.markCelEdited(key);
  store.storeRebuiltDisplayCache(key: key, previewSurface: surface);
  store.storeBakedSurface(key, surface);
}

/// A change-detection stamp for [lengthBytes] + [modifiedMillis] — the
/// "original changed" badge's comparison key (§6-g). Cheap on purpose
/// (no hashing a 100MB file).
String mediaSourceStamp({
  required int lengthBytes,
  required int modifiedMillis,
}) => '$modifiedMillis:$lengthBytes';
