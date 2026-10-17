import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../../core/point_bounds.dart';
import '../../models/bitmap_surface.dart';
import '../../models/bitmap_tile.dart';
import '../../models/brush_frame_key.dart';
import '../../models/canvas_point.dart';
import '../../models/canvas_size.dart';
import '../../models/dirty_region.dart';
import '../../models/media_asset.dart' show MediaFitMode;
import '../../models/media_reference.dart';
import '../../models/pasteboard_bounds.dart';
import '../../models/placed_tile.dart';
import '../../models/tile_coord.dart';
import '../../models/transform_pose.dart';
import '../brush_frame_store.dart';
import '../guide_geometry.dart' show GuideTransform;
import '../layer_pose_matrix.dart';
import '../photoshop/psd_image.dart';
import '../photoshop/psd_reader.dart';

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
///
/// A Photoshop document takes the one detour: no platform decodes it (iOS
/// appearing to was an accident of Apple's picker and Apple's codec), so it
/// is read here and arrives as the one frame its composite makes.
Future<List<DecodedImageFrame>> decodeImageFrames(Uint8List bytes) async {
  if (looksLikePsdBytes(bytes)) {
    return [
      DecodedImageFrame(
        image: await decodePsdCompositeImage(bytes),
        duration: Duration.zero,
      ),
    ];
  }
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

/// Where [fit] stands a picture of [picture]'s size on [canvas] (§6-q: fit
/// is a placement decision): its centre on the canvas's, scaled over its
/// own pixels — stretch fills the canvas, contain letterboxes inside it,
/// none is 1:1 (the pasteboard keeps the overflow), its pixels on the
/// canvas's own.
///
/// ↩️It was a RECT (`placementRectFor`), which says where a picture lies
/// and not how it stands: a reference's pose is a transform's (I-68), and a
/// fit is only where one starts. ONE fit, read as a pose everywhere.
///
/// 1:1 stands half a pixel off the centre where the picture and the canvas
/// differ by an odd number of pixels: a picture laid 1:1 is COPIED, never
/// resampled ([rasterizeImageToSurface]) — what F-374-Q1's 「놓을때 100%인걸
/// 놓기만」 asks of every reference's file — as a canvas resize moves its
/// content by whole pixels (`ResizeCutCanvasCommand`). ↩️It stood on the
/// centre exactly, and such a picture was resampled half a pixel over.
///
/// A picture with no pixels has no size to fit and stands 1:1.
TransformPose fitPose({
  required CanvasSize picture,
  required CanvasSize canvas,
  required MediaFitMode fit,
}) {
  final center = CanvasPoint(x: canvas.width / 2, y: canvas.height / 2);
  if (picture.width <= 0 || picture.height <= 0) {
    return TransformPose(center: center);
  }
  final across = canvas.width / picture.width;
  final down = canvas.height / picture.height;
  return switch (fit) {
    MediaFitMode.stretch => TransformPose(
      center: center,
      scaleX: across,
      scaleY: down,
    ),
    MediaFitMode.contain => TransformPose.uniform(
      center: center,
      zoom: math.min(across, down),
    ),
    MediaFitMode.none => TransformPose(
      center: CanvasPoint(
        x: ((canvas.width - picture.width) / 2).roundToDouble() +
            picture.width / 2,
        y: ((canvas.height - picture.height) / 2).roundToDouble() +
            picture.height / 2,
      ),
    ),
  };
}

/// The reference a placement makes to SHOW [path]: the picture's own size
/// ([picture]), its pixels laid on the cels as they are — 1:1, its centre
/// on the canvas's ([MediaReference.laid]) — and the pose [fit] starts its
/// reference fx at on [canvas], where it then stands until it is moved
/// (I-68: 「배치된 값, 원본값 유지」).
///
/// 🗣️F-374-Q1 (유저 2026-10-17): 「놓을때 100%인걸 놓기만 하면 됨.
/// 비율유지맞춤같은걸 하면 거기서 변형값을 바꾸는식으로 하는느낌」 — the fit
/// is the fx's value, and the canvas shows the cel by it. Q4: 「100% 그대로
/// — 셀 밖은 잘린다」; Q5: a PDF's page at its own size. ↩️The file was
/// laid at the fit, so the fit was in the cel's pixels.
MediaReference placedReference(
  String path,
  CanvasSize picture,
  CanvasSize canvas,
  MediaFitMode fit,
) => MediaReference(
  assetPath: path,
  pose: fitPose(picture: picture, canvas: canvas, fit: fit),
  pictureSize: picture,
  laid: fitPose(picture: picture, canvas: canvas, fit: MediaFitMode.none),
);

/// Where [fit] lays [image] on [canvas] ([fitPose] as a placement).
LayerPlacement fitPlacement(
  ui.Image image,
  CanvasSize canvas,
  MediaFitMode fit,
) {
  final picture = CanvasSize(width: image.width, height: image.height);
  return picturePlacement(
    fitPose(picture: picture, canvas: canvas, fit: fit),
    picture,
  );
}

/// A picture [width] × [height] laid over [rect] — for a caller that already
/// knows exactly where the image goes (the text bake renders its own
/// bounds; an expanded PSD layer carries its document's fit).
LayerPlacement rectPlacement(
  ui.Rect rect, {
  required int width,
  required int height,
}) => GuideTransform(
  rect.width / width,
  0,
  0,
  rect.height / height,
  rect.left,
  rect.top,
);

/// Rasterizes [image] into a [BitmapSurface] at [canvas]'s exact size
/// (the store's hard gate: a cel sized for another canvas is invisible
/// everywhere), laid by [placement] — the image's own pixels → the canvas.
/// The raster covers what the placed picture covers, clipped to the
/// pasteboard — fit=none overflow lives on the pasteboard exactly like an
/// oversized selection drop.
///
/// [whole]: a FILE's picture, laid all of it, past the pasteboard where it
/// is larger than the wall — the surface says where it lies
/// ([BitmapSurface.laidBounds]). 🗣️F-374-Q8 (유저 2026-10-17): 「맞춘다 —
/// 참조 그림은 벽 밖까지 통째로」. ⚠️What a tool draws (a text's letters) is
/// cut at the wall as ever.
Future<BitmapSurface> rasterizeImageToSurface({
  required ui.Image image,
  required CanvasSize canvas,
  required LayerPlacement placement,
  int tileSize = defaultCelTileSize,
  bool whole = false,
}) async {
  final placed = _placedBounds(placement, image);
  // The pasteboard wall (tiles beyond it are refused by the surface) — or,
  // laid whole, the picture's own rect on whole pixels, which the surface
  // keeps tiles over.
  final laid = whole && !placed.isEmpty
      ? DirtyRegion.wholePixelsOf(placed)
      : null;
  final clipped = laid == null
      ? placed.intersect(canvas.pasteboardRect)
      : laid.rect;
  if (clipped.isEmpty) {
    return BitmapSurface(canvasSize: canvas, tileSize: tileSize);
  }

  // Tile span covered by the placement.
  final (
    firstX: tileX0,
    lastX: tileX1,
    firstY: tileY0,
    lastY: tileY1,
  ) = tileRangeCovering(
    left: clipped.left,
    top: clipped.top,
    right: clipped.right,
    bottom: clipped.bottom,
    tileSize: tileSize,
  );

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
      placement.isPureTranslation &&
      placement.tx == placement.tx.truncateToDouble() &&
      placement.ty == placement.ty.truncateToDouble();
  paintCanvas
    ..transform(placementMatrix(placement).storage)
    ..drawImage(
      image,
      ui.Offset.zero,
      ui.Paint()
        ..filterQuality = identityPlacement
            ? ui.FilterQuality.none
            : ui.FilterQuality.high
        ..isAntiAlias = true,
    );
  final picture = recorder.endRecording();
  // 🚨THE `finally` IS THE POINT. `toImage` is the awaited call, and an await
  // that throws skips every statement after it — so a dispose written on the
  // line below runs on the landing arm ONLY, and a raster that failed took
  // the picture's native memory with it. The law: what the start took is
  // given back on ALL THREE arms — landing, overtaking, refusal — and the
  // place that gives it back has to be structural.
  final ui.Image raster;
  try {
    raster = await picture.toImage(blockWidth, blockHeight);
  } finally {
    picture.dispose();
  }
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

    final tiles = <PlacedTile>[];
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
        tiles.add((
          coord: TileCoord(x: tx, y: ty),
          tile: BitmapTile(

            size: tileSize,
            pixels: tilePixels,
          ),
        ));
      }
    }
    return BitmapSurface(
      canvasSize: canvas,
      tileSize: tileSize,
      laidBounds: laid,
    ).putTiles(tiles);
  } finally {
    raster.dispose();
  }
}

/// The canvas rect [placement] lays [image]'s pixels over — its four
/// corners' bounds, so a turned picture is covered whole.
ui.Rect _placedBounds(LayerPlacement placement, ui.Image image) =>
    pointsBounds([
      for (final corner in placedCorners(
        placement,
        ui.Offset.zero &
            ui.Size(image.width.toDouble(), image.height.toDouble()),
      ))
        ui.Offset(corner.x, corner.y),
    ]);

/// Bakes [tiles] — a decoded picture already cut into cel tiles of
/// [defaultCelTileSize], straight RGBA, by their place in tiles — as [key]'s
/// cel on a [canvas]-size picture. The picture they begin as: the doors
/// that decode a file's own cels (a .tvpp, a .clip) hand theirs here.
void bakeCelTiles(
  BrushFrameStore store,
  BrushFrameKey key,
  CanvasSize canvas,
  List<({int x, int y, Uint8List pixels})> tiles,
) => bakeCelSurface(
  store,
  key,
  BitmapSurface(canvasSize: canvas, tiles: celTilesOf(tiles)),
);

/// [tiles] — cut as [bakeCelTiles] takes them — as a cel's own tiles: the
/// picture of a cel, or a text's plate (`CelText.plate`) that a file drew.
Map<TileCoord, BitmapTile> celTilesOf(
  List<({int x, int y, Uint8List pixels})> tiles,
) => {
  for (final tile in tiles)
    TileCoord(x: tile.x, y: tile.y): BitmapTile(
      size: defaultCelTileSize,
      pixels: tile.pixels,
    ),
};

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
