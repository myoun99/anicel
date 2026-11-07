import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../core/display_filter.dart';
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
import '../brush_stroke_blend.dart' show bitmapSurfaceRegionPixels;
import '../guide_geometry.dart' show GuideTransform;
import '../layer_pose_matrix.dart';
import '../persistence/brush_drawing_binary_codec.dart' show laidCelSurface;
import '../photoshop/psd_image.dart';
import '../photoshop/psd_reader.dart';
import '../straight_rgba_image.dart';
import 'cel_picture.dart';

/// Decode-and-bake for the import system: an image FILE becomes a cel's
/// [BitmapSurface] — the same store shape a drawn cel has, so every
/// display/export/thumbnail path works untouched (the "one seam" rule:
/// pixels only ever come from the store). The REFERENCE field on the
/// layer is provenance; the pixels live here either way, which is what
/// makes "rasterize = null the field, nothing else" true.

/// One decoded source frame (GIF frames carry their delay; stills have
/// [duration] zero).
class DecodedImageFrame {
  const DecodedImageFrame({required this.picture, required this.duration});

  final CelPicture picture;
  final Duration duration;
}

/// Decodes every frame of [bytes] (PNG/JPEG = one, GIF = many) through
/// the platform codec — the repo's established recipe
/// (decodeBrushTipImage does the single-frame version).
///
/// A Photoshop document takes the one detour: no platform decodes it (iOS
/// appearing to was an accident of Apple's picker and Apple's codec), so it
/// is read here and arrives as the one frame its composite makes.
///
/// A picture longer on a side than this device's engine hands back
/// ([pictureSideLimit]) never reaches the codec: it is the app's to read,
/// at its own size ([_framesPastTheSide]).
Future<List<DecodedImageFrame>> decodeImageFrames(Uint8List bytes) async {
  if (looksLikePsdBytes(bytes)) {
    return [
      DecodedImageFrame(
        picture: await decodePsdCompositePicture(bytes),
        duration: Duration.zero,
      ),
    ];
  }
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  final ui.ImageDescriptor descriptor;
  try {
    descriptor = await ui.ImageDescriptor.encoded(buffer);
  } finally {
    buffer.dispose();
  }
  try {
    final side = await pictureSideLimit();
    if (isPastTheSide(descriptor.width, descriptor.height, side)) {
      return await _framesPastTheSide(bytes, descriptor);
    }
    return await _framesDecoded(descriptor);
  } finally {
    descriptor.dispose();
  }
}

/// Every frame of [descriptor]'s picture through the engine's codec, at its
/// own size.
Future<List<DecodedImageFrame>> _framesDecoded(
  ui.ImageDescriptor descriptor,
) async {
  final codec = await descriptor.instantiateCodec();
  try {
    final frames = <DecodedImageFrame>[];
    for (var i = 0; i < codec.frameCount; i += 1) {
      final frame = await codec.getNextFrame();
      frames.add(
        DecodedImageFrame(
          picture: EnginePicture(frame.image),
          duration: frame.duration,
        ),
      );
    }
    return frames;
  } finally {
    codec.dispose();
  }
}

/// [bytes]' frames, a picture past the engine's side: a still as its file,
/// read when it is laid ([FilePicture]); an animation's frames read now, on
/// a worker ([readFramesInWorker]). How many it has is the codec's to say,
/// from the file's head — nothing is decoded to count them.
Future<List<DecodedImageFrame>> _framesPastTheSide(
  Uint8List bytes,
  ui.ImageDescriptor descriptor,
) async {
  final counting = await descriptor.instantiateCodec(
    targetWidth: 1,
    targetHeight: 1,
  );
  final int count;
  try {
    count = counting.frameCount;
  } finally {
    counting.dispose();
  }
  if (count <= 1) {
    return [
      DecodedImageFrame(
        picture: FilePicture(
          bytes,
          width: descriptor.width,
          height: descriptor.height,
        ),
        duration: Duration.zero,
      ),
    ];
  }
  return [
    for (final frame in await readFramesInWorker(bytes))
      DecodedImageFrame(picture: frame.picture, duration: frame.duration),
  ];
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
/// resampled ([layCelPicture]) — what F-374-Q1's 「놓을때 100%인걸
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

/// Where [fit] lays a picture of [picture]'s size on [canvas] ([fitPose] as
/// a placement).
LayerPlacement fitPlacement(
  CanvasSize picture,
  CanvasSize canvas,
  MediaFitMode fit,
) => picturePlacement(
  fitPose(picture: picture, canvas: canvas, fit: fit),
  picture,
);

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

/// [picture] laid on a cel by [placement] — the picture's own pixels → the
/// canvas — as a [BitmapSurface] at [canvas]'s exact size (the store's hard
/// gate: a cel sized for another canvas is invisible everywhere). The lay
/// covers what the placed picture covers, clipped to the pasteboard —
/// fit=none overflow lives on the pasteboard exactly like an oversized
/// selection drop — a block of tiles at a time ([layRasterSide]). Laid at
/// the widest wall, as every surface is born
/// ([BitmapSurface.pasteboardReach]); the frame store cuts what it keeps to
/// the project's ([surfaceBehindReach]).
///
/// [whole]: a FILE's picture, laid all of it, past the pasteboard where it
/// is larger than the wall — the surface says where it lies
/// ([BitmapSurface.laidBounds]). 🗣️F-374-Q8 (유저 2026-10-17): 「맞춘다 —
/// 참조 그림은 벽 밖까지 통째로」. ⚠️What a tool draws (a text's letters) is
/// cut at the wall as ever.
///
/// A picture the engine holds is rastered ([_rastered]). One held off it
/// ([pictureSideLimit]) never becomes one GPU image: laid 1:1 on whole
/// pixels — a reference's file always is (F-374-Q1) — its rows are cut into
/// the cel's tiles byte for byte ([cutFileInWorker], [cutPixels]); laid
/// otherwise it is resampled a block at a time from the part of it each
/// block reaches ([_resampled]).
Future<BitmapSurface> layCelPicture({
  required CelPicture picture,
  required CanvasSize canvas,
  required LayerPlacement placement,
  int tileSize = defaultCelTileSize,
  bool whole = false,
}) async {
  final placed = placedBounds(placement, picture.size);
  final laid = whole && !placed.isEmpty
      ? DirtyRegion.wholePixelsOf(placed)
      : null;
  final clipped = laid == null
      ? placed.intersect(canvas.pasteboardAt(PasteboardReach.whole).rect)
      : laid.rect;
  if (clipped.isEmpty) {
    return BitmapSurface(canvasSize: canvas, tileSize: tileSize);
  }
  final layout = (
    canvas: canvas,
    tileSize: tileSize,
    tiles: tileRangeCovering(
      left: clipped.left,
      top: clipped.top,
      right: clipped.right,
      bottom: clipped.bottom,
      tileSize: tileSize,
    ),
    laid: laid,
  );
  return switch (picture) {
    EnginePicture(:final image) => await _rastered(image, placement, layout),
    _ when !_copiesPixels(placement) => await _resampled(
      picture,
      placement,
      layout,
    ),
    final FilePicture file => laidCelSurface(
      await cutFileInWorker(file, _cutAt(placement, layout)),
    ),
    final PixelsPicture pixels => laidCelSurface(
      cutPixels(pixels, _cutAt(placement, layout)),
    ),
  };
}

/// Where [placement], standing a picture 1:1 on whole pixels, cuts it into
/// [layout]'s tiles.
PictureCut _cutAt(LayerPlacement placement, CelLayout layout) =>
    (left: placement.tx.toInt(), top: placement.ty.toInt(), layout: layout);

BitmapSurface _surfaceOf(CelLayout layout, List<PlacedTile> tiles) =>
    BitmapSurface(
      canvasSize: layout.canvas,
      tileSize: layout.tileSize,
      laidBounds: layout.laid,
    ).putTiles(tiles);

/// [image], a picture the engine holds, laid by [placement] over [layout]'s
/// tiles — ONE raster a block.
Future<BitmapSurface> _rastered(
  ui.Image image,
  LayerPlacement placement,
  CelLayout layout,
) async {
  final drawn = (
    image: image,
    inPicture: const GuideTransform.identity(),
    owned: false,
  );
  final tiles = <PlacedTile>[];
  for (final block in _layBlocks(layout.tiles, layout.tileSize)) {
    tiles.addAll(await _laidBlock(drawn, placement, block, layout.tileSize));
  }
  return _surfaceOf(layout, tiles);
}

/// A picture held off the engine, laid where [placement] resamples it: read
/// whole, and drawn a block at a time from the part of it each block
/// reaches, which is all that is ever uploaded ([_partUploaded]) — by the
/// engine's own sampler, as a picture it holds is laid ([_layPaint]).
///
/// ⛔Not halved first to hold a quarter of it, as a mip chain is read: 🔬a
/// lay at 0.3 came out up to 86/255 apart in `flutter test` from the same
/// picture laid by the engine, which reads it whole (2026-10-20). A picture
/// past the side is laid by the law a picture within it is.
Future<BitmapSurface> _resampled(
  CelPicture picture,
  LayerPlacement placement,
  CelLayout layout,
) async {
  final pixels = switch (picture) {
    final FilePicture file => await readFileInWorker(file),
    final PixelsPicture held => held,
    EnginePicture() => throw StateError('The engine holds it: rastered.'),
  };
  final tiles = <PlacedTile>[];
  for (final block in _layBlocks(layout.tiles, layout.tileSize)) {
    for (final part in _partsFitting(block, pixels.size, placement, layout)) {
      tiles.addAll(await _laidPart(pixels, placement, part, layout));
    }
  }
  return _surfaceOf(layout, tiles);
}

/// [part]'s tiles, laid from the part of [pixels] it reaches
/// ([_partUploaded]) — or, a part of ONE tile that reaches past one raster
/// ([_partsFitting]), as the tiles half its side, laid alike and put back
/// together where they lie ([_laidInHalves]).
Future<List<PlacedTile>> _laidPart(
  PixelsPicture pixels,
  LayerPlacement placement,
  TileRange part,
  CelLayout layout,
) async {
  final reached = _reachedBy(part, pixels.size, placement, layout.tileSize);
  if (reached != null &&
      !_fitsOneRaster(reached) &&
      layout.tileSize.isEven) {
    return [?await _laidInHalves(pixels, placement, part, layout)];
  }
  final drawn = await _partUploaded(pixels, placement, part, layout);
  return drawn == null
      ? const []
      : await _laidBlock(drawn, placement, part, layout.tileSize);
}

/// [tile], laid as the four tiles half its side — cut as any block is
/// ([_partsFitting]) and each laid as a part is ([_laidPart]) — and read
/// back as the one tile they cover. Null where none of them took ink.
///
/// 🔬2026-11-08 (I-120-Q28): a tile that reached past one raster was drawn
/// from what it reached decoded smaller, by the decoder's own smooth
/// filter — 6,630 grey pixels of a lay at 0.15 of black-and-white line art
/// in `flutter test`, where the engine laying the picture whole by its
/// nearest texel ([_layPaint]) made none. Halved, every pixel is read from
/// the file's own texels; only a tile of one pixel reaching past a raster
/// (a lay below 1/[layRasterSide]) is still read from fewer.
Future<PlacedTile?> _laidInHalves(
  PixelsPicture pixels,
  LayerPlacement placement,
  TileRange tile,
  CelLayout layout,
) async {
  final size = layout.tileSize;
  final halves = (
    canvas: layout.canvas,
    tileSize: size >> 1,
    tiles: (
      firstX: tile.firstX * 2,
      lastX: tile.firstX * 2 + 1,
      firstY: tile.firstY * 2,
      lastY: tile.firstY * 2 + 1,
    ),
    laid: layout.laid,
  );
  final laid = <PlacedTile>[];
  for (final part in _partsFitting(
    halves.tiles,
    pixels.size,
    placement,
    halves,
  )) {
    laid.addAll(await _laidPart(pixels, placement, part, halves));
  }
  if (laid.isEmpty) {
    return null;
  }
  final rgba = bitmapSurfaceRegionPixels(
    _surfaceOf(halves, laid),
    DirtyRegion.fromXYWH(
      x: tile.firstX * size,
      y: tile.firstY * size,
      width: size,
      height: size,
    ),
  );
  return (
    coord: TileCoord(x: tile.firstX, y: tile.firstY),
    tile: BitmapTile(size: size, pixels: rgba),
  );
}

/// Whether what a raster reaches ([_reachedBy]) is no longer a side than
/// one lay's raster ([layRasterSide]).
bool _fitsOneRaster(({int left, int top, int width, int height}) reached) {
  final side = debugLayRasterSide ?? layRasterSide;
  return reached.width <= side && reached.height <= side;
}

/// [block], cut into the parts whose reach into the picture
/// ([_reachedBy]) fits one raster ([_fitsOneRaster]) — a block of one tile
/// however far it reaches, which is laid in halves ([_laidPart]).
Iterable<TileRange> _partsFitting(
  TileRange block,
  CanvasSize picture,
  LayerPlacement placement,
  CelLayout layout,
) sync* {
  final reached = _reachedBy(block, picture, placement, layout.tileSize);
  if (reached == null) {
    return;
  }
  final wide = block.lastX - block.firstX;
  final tall = block.lastY - block.firstY;
  if (_fitsOneRaster(reached) || wide + tall == 0) {
    yield block;
    return;
  }
  final halves = wide >= tall
      ? (
          (
            firstX: block.firstX,
            lastX: (block.firstX + block.lastX) >> 1,
            firstY: block.firstY,
            lastY: block.lastY,
          ),
          (
            firstX: ((block.firstX + block.lastX) >> 1) + 1,
            lastX: block.lastX,
            firstY: block.firstY,
            lastY: block.lastY,
          ),
        )
      : (
          (
            firstX: block.firstX,
            lastX: block.lastX,
            firstY: block.firstY,
            lastY: (block.firstY + block.lastY) >> 1,
          ),
          (
            firstX: block.firstX,
            lastX: block.lastX,
            firstY: ((block.firstY + block.lastY) >> 1) + 1,
            lastY: block.lastY,
          ),
        );
  yield* _partsFitting(halves.$1, picture, placement, layout);
  yield* _partsFitting(halves.$2, picture, placement, layout);
}

/// The pixels of a [picture]-sized picture that [block]'s raster samples
/// where [placement] lays it — what the block covers, taken back into the
/// picture to whole texels — or null where it reaches none of the picture.
({int left, int top, int width, int height})? _reachedBy(
  TileRange block,
  CanvasSize picture,
  LayerPlacement placement,
  int tileSize,
) {
  final back = canvasToArtwork(placement);
  if (back == null) {
    return null;
  }
  final over = placedRectBounds(
    back,
    ui.Rect.fromLTRB(
      (block.firstX * tileSize).toDouble(),
      (block.firstY * tileSize).toDouble(),
      ((block.lastX + 1) * tileSize).toDouble(),
      ((block.lastY + 1) * tileSize).toDouble(),
    ),
  );
  // A pixel reads the one texel its centre lands on ([_layPaint]), and a
  // centre lies half a pixel inside the block, so it lands inside what the
  // block covers taken back — on a texel's edge, either texel of it.
  // ↩️It reached two texels and more past that, 「farther the more the lay
  // shrinks it」, and out to a mip grid, while a lay resampled smoothly;
  // and one texel, while it went nearest, which no pixel read (I-120-Q28,
  // its mutant lived).
  final left = math.max(0, over.left.floor());
  final top = math.max(0, over.top.floor());
  final right = math.min(picture.width, over.right.ceil());
  final bottom = math.min(picture.height, over.bottom.ceil());
  if (left >= right || top >= bottom) {
    return null;
  }
  return (left: left, top: top, width: right - left, height: bottom - top);
}

/// The part of [pixels] that [part]'s raster reaches ([_reachedBy]),
/// uploaded for that raster alone — at no more than a lay's raster a side
/// ([layRasterSide]), which every engine holds; a part that still reaches
/// farther — a tile of one pixel ([_laidInHalves]) — is drawn from fewer
/// pixels than it reaches, still more than the tile shows. Null where it
/// reaches none of the picture.
Future<_BlockPicture?> _partUploaded(
  PixelsPicture pixels,
  LayerPlacement placement,
  TileRange part,
  CelLayout layout,
) async {
  final reached = _reachedBy(part, pixels.size, placement, layout.tileSize);
  if (reached == null) {
    return null;
  }
  final side = debugLayRasterSide ?? layRasterSide;
  final image = await decodeStraightRgbaImage(
    rgba: _rowsReached(pixels, reached),
    width: reached.width,
    height: reached.height,
    targetWidth: math.min(reached.width, side),
    targetHeight: math.min(reached.height, side),
  );
  return (
    image: image,
    inPicture: GuideTransform(
      reached.width / image.width,
      0,
      0,
      reached.height / image.height,
      reached.left.toDouble(),
      reached.top.toDouble(),
    ),
    owned: true,
  );
}

/// [pixels]' rows over [reached], one after another — a view where they
/// already lie so.
Uint8List _rowsReached(
  PixelsPicture pixels,
  ({int left, int top, int width, int height}) reached,
) {
  final stride = pixels.width * 4;
  if (reached.left == 0 && reached.width == pixels.width) {
    return Uint8List.sublistView(
      pixels.rgba,
      reached.top * stride,
      (reached.top + reached.height) * stride,
    );
  }
  final rowBytes = reached.width * 4;
  final out = Uint8List(rowBytes * reached.height);
  for (var y = 0; y < reached.height; y += 1) {
    out.setRange(
      y * rowBytes,
      (y + 1) * rowBytes,
      pixels.rgba,
      (reached.top + y) * stride + reached.left * 4,
    );
  }
  return out;
}

/// The longest side, in pixels, of ONE raster a lay asks the GPU for: a
/// picture that covers more is laid a block of tiles at a time
/// ([layCelPicture]).
///
/// Since F-374-Q8 (유저 2026-10-17: 「맞춘다 — 참조 그림은 벽 밖까지
/// 통째로」) a file's picture is laid as big as the file (A3 at 600dpi,
/// 7016×9921), and a bake as seen that turns or grows it bigger still: ONE
/// raster of it could pass the largest image a device makes, and held the
/// picture three times over at its peak — the raster, its bytes, the tiles
/// (⑦ of the plan on the board's F-374).
///
/// 2048: the largest texture GLES 3.0 promises on every GPU (its
/// MAX_TEXTURE_SIZE floor). ⛔A FOURTH limit, beside the three the decision
/// on `CanvasSizeDialog.maxDimension` keeps apart, with a remedy of its
/// own — a SPLIT, which a cel already is: its tiles.
const int layRasterSide = 2048;

/// The side a test lays its blocks at instead of [layRasterSide] — so a
/// small picture is laid in many — or null.
@visibleForTesting
int? debugLayRasterSide;

/// How many rasters the lays have asked the GPU for, counted for the tests
/// that see a picture laid in blocks.
@visibleForTesting
int debugLayRasters = 0;

/// [covered] in blocks of at most [layRasterSide] a side, row by row.
Iterable<TileRange> _layBlocks(TileRange covered, int tileSize) sync* {
  final step = math.max(1, (debugLayRasterSide ?? layRasterSide) ~/ tileSize);
  for (var y = covered.firstY; y <= covered.lastY; y += step) {
    for (var x = covered.firstX; x <= covered.lastX; x += step) {
      yield (
        firstX: x,
        lastX: math.min(x + step - 1, covered.lastX),
        firstY: y,
        lastY: math.min(y + step - 1, covered.lastY),
      );
    }
  }
}

/// Whether [placement] stands a picture's pixels 1:1 on whole pixels —
/// where a lay copies them, never resamples.
bool _copiesPixels(LayerPlacement placement) =>
    placement.isPureTranslation &&
    placement.tx == placement.tx.truncateToDouble() &&
    placement.ty == placement.ty.truncateToDouble();

/// How a lay samples a picture's pixels: as the display does a picture it
/// draws into a raster at the canvas's own resolution — the scale a cel is
/// at, one of its pixels a canvas pixel.
///
/// 🗣️I-120-Q26 (유저 2026-11-07 「굽기를 화면에 맞춘다 — 확대된 그림은 계단
/// 그대로 굽는다」) · Q28 (「축소도 같은 법 — 화면처럼 최근접으로 굽는다」):
/// the canvas lays a row's picture where its pose stands it into its frame
/// picture, at that resolution, by the display's one law
/// ([filterQualityForDisplayScale]) asked of that picture's scale, never of
/// the pose's — so the lay asks it the same, and a picture baked where it
/// shows is the picture shown, grown, shrunk or turned. At 1:1 on whole
/// pixels the answer copies the bytes, which the text bake's contract
/// needs: the store pixels ARE the engine render.
///
/// ↩️It resampled at `high` — bicubic, from the picture's mips when it
/// shrank — wherever it did not copy, so a rasterize softened the picture
/// the canvas had shown hard-edged (I-120-Q26: 1,664–31,102 px a frame, up
/// to 163/255 on the Surface, 11-07); and each part of a picture held off
/// the engine was read on the grid of the deepest mip the shrink sampled
/// (`_mipGrid`, 2026-10-20), which nothing samples now.
ui.Paint _layPaint() => ui.Paint()
  ..filterQuality = filterQualityForDisplayScale(_celScale)
  ..isAntiAlias = true;

/// A cel's pixels a canvas pixel: a cel is at the canvas's resolution.
const double _celScale = 1;

/// What one block of a lay draws: an image, where it lies among the
/// picture's own pixels — the picture whole at its origin, or the part of a
/// picture held off the engine that the block reaches, uploaded for it
/// ([_partUploaded]) — and whether the block lets go of it.
typedef _BlockPicture = ({
  ui.Image image,
  LayerPlacement inPicture,
  bool owned,
});

/// The tiles of [block] that [drawn], laid by [placement], puts any ink on
/// — ONE raster of the block, sliced into its tiles. The recorder canvas
/// is translated so the block's origin is (0,0).
Future<List<PlacedTile>> _laidBlock(
  _BlockPicture drawn,
  LayerPlacement placement,
  TileRange block,
  int tileSize,
) async {
  try {
    return await _laidBlockOf(
      drawn.image,
      placement.compose(drawn.inPicture),
      block,
      tileSize,
    );
  } finally {
    if (drawn.owned) {
      drawn.image.dispose();
    }
  }
}

Future<List<PlacedTile>> _laidBlockOf(
  ui.Image image,
  LayerPlacement placement,
  TileRange block,
  int tileSize,
) async {
  final (firstX: tileX0, lastX: tileX1, firstY: tileY0, lastY: tileY1) =
      block;
  final blockWidth = (tileX1 - tileX0 + 1) * tileSize;
  final blockHeight = (tileY1 - tileY0 + 1) * tileSize;
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder)
    ..translate(
      -(tileX0 * tileSize).toDouble(),
      -(tileY0 * tileSize).toDouble(),
    )
    ..transform(placementMatrix(placement).storage)
    ..drawImage(image, ui.Offset.zero, _layPaint());
  final picture = recorder.endRecording();
  // 🚨THE `finally` IS THE POINT. `toImage` is the awaited call, and an await
  // that throws skips every statement after it — so a dispose written on the
  // line below runs on the landing arm ONLY, and a raster that failed took
  // the picture's native memory with it. The law: what the start took is
  // given back on ALL THREE arms — landing, overtaking, refusal — and the
  // place that gives it back has to be structural.
  final ui.Image raster;
  debugLayRasters += 1;
  try {
    raster = await picture.toImage(blockWidth, blockHeight);
  } finally {
    picture.dispose();
  }
  try {
    final bytes = await straightRgbaOf(raster);
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
          tile: BitmapTile(size: tileSize, pixels: tilePixels),
        ));
      }
    }
    return tiles;
  } finally {
    raster.dispose();
  }
}

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
///
/// [revision]: the one that named [surface], where it is a picture the cel
/// is given back ([BrushFrameStore.markCelEdited]'s `backTo`).
void bakeCelSurface(
  BrushFrameStore store,
  BrushFrameKey key,
  BitmapSurface surface, {
  int? revision,
}) {
  // Mark-edited FIRST, then donate — the drawing commit's order, which
  // leaves the donated display cache VALID (the reverse order dirtied
  // the cache it had just stored, wasting the donation on first paint).
  store.markCelEdited(key, backTo: revision);
  store.storeRebuiltDisplayCache(key: key, previewSurface: surface);
  store.storeBakedSurface(key, surface);
}
