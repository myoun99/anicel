import 'dart:ffi';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:gpu_engine/gpu_engine.dart'
    show GpuBlend, GpuCompositedReader, GpuPlan, gpuTileBytes, gpuTileSide;

import '../../core/floor_math.dart';
import '../../core/on_a_worker.dart';
import '../../models/bitmap_surface.dart';
import '../../models/bitmap_tile.dart';
import '../../models/brush_frame_key.dart';
import '../../models/canvas_point.dart';
import '../../models/canvas_size.dart';
import '../../models/cut_content_translation.dart' show resizeWalk;
import '../../models/dirty_region.dart';
import '../../models/media_asset.dart' show MediaFitMode;
import '../../models/media_reference.dart';
import '../../models/pasteboard_bounds.dart';
import '../../models/tile_coord.dart';
import '../../models/tiles_covering.dart';
import '../../models/transform_pose.dart';
import '../../native/app_gpu_engine.dart' show appGpuComposite;
import '../../native/engine_row_pose.dart';
import '../../native/engine_tile_ledger.dart';
import '../../native/tile_blocks.dart';
import '../bitmap_surface_geometry.dart'
    show CelFit, CelTextSetter, celPhotosCarried, celTextsFitted;
import '../brush_frame_store.dart';
import '../guide_geometry.dart' show GuideTransform;
import '../layer_pose_matrix.dart';
import '../media/colour_profile.dart' show readsTheColoursOf;
import '../media/image_viewer_document.dart' show ImageViewerDocument;
import '../persistence/brush_drawing_binary_codec.dart'
    show AnicelLaidCel, LaidPixels, laidCelSurface;
import '../photoshop/psd_image.dart';
import '../photoshop/psd_reader.dart';
import '../straight_rgba_image.dart';
import '../tile_origin.dart' show surfaceContentWorldRect;
import 'cel_picture.dart';
import 'tile_cutter.dart';

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
///
/// Nor does a still PNG or JPEG, at any size ([readsTheColoursOf]): its
/// colours turned as the engine turns them (`colour_profile.dart`), it is
/// laid where its file is read ([FilePicture]) and the isolate that paints
/// holds none of its pixels. 🗣️유저 2026-11-14
/// (a-raster-import-goes-gpu-cpu-gpu-cpu-Q1): 「프로파일대로 바꿔 읽는다
/// (크기 상관없이)」 — the one law the engine's road and the app's were
/// split on, by size. ↩️One within the side was the engine's: decoded,
/// rastered back and cut on the isolate that paints ([_cutEngineImage]).
/// ⚠️The image package decodes a JPEG several times slower than the engine
/// (🔬12 MP on the Surface, 2026-11-14: 750–940 ms against 110–210 ms) —
/// on a worker, so nothing stops, but such an import ends later.
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
    if (readsTheColoursOf(bytes) && await _isAStill(descriptor)) {
      return [_stillAsItsFile(bytes, descriptor)];
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

/// [bytes]' frames, a picture past the engine's side: a still as its file
/// ([_stillAsItsFile]); an animation's frames read now, on a worker
/// ([readFramesInWorker]).
Future<List<DecodedImageFrame>> _framesPastTheSide(
  Uint8List bytes,
  ui.ImageDescriptor descriptor,
) async {
  if (await _isAStill(descriptor)) {
    return [_stillAsItsFile(bytes, descriptor)];
  }
  return [
    for (final frame in await readFramesInWorker(bytes))
      DecodedImageFrame(picture: frame.picture, duration: frame.duration),
  ];
}

/// Whether [descriptor]'s picture is one frame. How many it has is the
/// codec's to say, from the file's head — nothing is decoded to count them.
Future<bool> _isAStill(ui.ImageDescriptor descriptor) async =>
    await ImageViewerDocument.picturesIn(descriptor) <= 1;

/// The still picture [bytes] as its file, read when it is laid
/// ([FilePicture]) — at the size [descriptor] says.
DecodedImageFrame _stillAsItsFile(
  Uint8List bytes,
  ui.ImageDescriptor descriptor,
) => DecodedImageFrame(
  picture: FilePicture(
    bytes,
    width: descriptor.width,
    height: descriptor.height,
  ),
  duration: Duration.zero,
);

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
/// Laid 1:1 on whole pixels — a reference's file always is (F-374-Q1) — a
/// picture is copied into the cel's tiles byte for byte where its pixels
/// are, never held whole ([_copied]). Every other lay is the engine's, by
/// the law the canvas lays a row by ([_laidOnEngine]).
Future<BitmapSurface> layCelPicture({
  required CelPicture picture,
  required CanvasSize canvas,
  required LayerPlacement placement,
  int tileSize = defaultCelTileSize,
  bool whole = false,
}) async {
  final lay = celLayOf(
    picture: picture.size,
    canvas: canvas,
    placement: placement,
    tileSize: tileSize,
    whole: whole,
  );
  if (lay == null) {
    return nothingLaid(canvas, tileSize: tileSize);
  }
  if (picture case EnginePicture(:final image) when !lay.copies) {
    return _laidOnEngine(_EngineSource(image), placement, lay.layout);
  }
  return layCut(lay, await _copied(picture, lay.cut));
}

/// The cel a lay that puts nothing on a [canvas]-sized cel of [tileSize]
/// tiles makes ([celLayOf] is null).
BitmapSurface nothingLaid(
  CanvasSize canvas, {
  int tileSize = defaultCelTileSize,
}) => BitmapSurface(canvasSize: canvas, tileSize: tileSize);

/// A lay of a picture on a cel ([layCelPicture]) before any of its pixels:
/// where it goes and the cut its pixels are taken by. Records and plain
/// values only — the isolate that holds a picture's pixels works it out
/// and cuts them there (an expanded Photoshop layer's).
final class CelLay {
  const CelLay._({
    required this.placement,
    required this.picture,
    required this.layout,
    required this.cut,
    required this.copies,
  });

  /// The picture's own pixels → the canvas.
  final LayerPlacement placement;

  /// The picture's own size.
  final CanvasSize picture;

  /// What the lay puts on the cel.
  final CelLayout layout;

  /// What is cut of the picture: the cel's own tiles where the lay
  /// [copies]; else tiles of the picture's own, at its origin, which the
  /// engine reads where they lie ([layCut]).
  final PictureCut cut;

  /// Whether the lay is 1:1 on whole pixels — a copy.
  final bool copies;
}

/// How a [picture]-sized picture is laid by [placement] on a
/// [canvas]-sized cel of [tileSize] tiles ([layCelPicture]) — null where it
/// puts nothing there.
CelLay? celLayOf({
  required CanvasSize picture,
  required CanvasSize canvas,
  required LayerPlacement placement,
  int tileSize = defaultCelTileSize,
  bool whole = false,
}) {
  final layout = _layoutOf(picture, canvas, placement, tileSize, whole);
  if (layout == null) {
    return null;
  }
  final copies = _copiesPixels(placement);
  return CelLay._(
    placement: placement,
    picture: picture,
    layout: layout,
    cut: copies ? _cutAt(placement, layout) : _ownCut(picture),
    copies: copies,
  );
}

/// [lay]'s cel, of [tiles] — the cut it asked of its picture: those tiles
/// themselves where it [CelLay.copies]; else read where they lie and laid
/// on the engine ([_RegionSource]), never composed into one picture here.
///
/// ↩️(2026-11-14, card a-raster-import-goes-gpu-cpu-gpu-cpu) a file was
/// read whole on a worker and handed here, a movie's frame read here, and
/// either cut a part at a time on the isolate that paints.
Future<BitmapSurface> layCut(CelLay lay, AnicelLaidCel tiles) async {
  final cut = laidCelSurface(tiles);
  if (lay.copies) {
    return cut;
  }
  return _laidOnEngine(
    _RegionSource(cut, _ownRegion(lay.picture)),
    lay.placement,
    lay.layout,
  );
}

/// All of a [picture]-sized picture, at its own origin.
DirtyRegion _ownRegion(CanvasSize picture) => DirtyRegion.fromXYWH(
  x: 0,
  y: 0,
  width: picture.width,
  height: picture.height,
);

/// A [picture]-sized picture cut into tiles of its own, at its origin —
/// what a lay that resamples it reads ([layCut]).
PictureCut _ownCut(CanvasSize picture) => (
  left: 0,
  top: 0,
  layout: (
    canvas: picture,
    tileSize: gpuTileSide,
    tiles: _ownRegion(picture).tileRange(tileSize: gpuTileSide),
    laid: null,
  ),
);

/// [picture] cut by [cut] — a [CelLay]'s: its rows cut into the tiles
/// where they are — a file's on a worker ([cutFileInWorker]),
/// pixels in hand here ([cutPixels]), a movie's frame where it is decoded
/// ([MovieFramePicture.cut]), the engine's a block at a time
/// ([_cutEngineImage]).
Future<AnicelLaidCel> _copied(CelPicture picture, PictureCut cut) async =>
    switch (picture) {
      final FilePicture file => await cutFileInWorker(file, cut),
      final PixelsPicture pixels => cutPixels(pixels, cut),
      final MovieFramePicture frame => await frame.cut(cut),
      EnginePicture(:final image) => await _cutEngineImage(image, cut),
    };

/// [image] — a picture the engine holds — laid 1:1 on whole pixels by
/// [cut], a block of the cel's tiles at a time ([_layBlocks], so no raster
/// passes [layRasterSide]): what of it a block covers rastered 1:1
/// ([_rasterOver]) and its rows cut into that block's tiles. A copy, as
/// every 1:1 lay is — no run of the engine.
///
/// ↩️It was laid as a picture laid otherwise is (2026-11-14, card
/// a-raster-import-goes-gpu-cpu-gpu-cpu): each raster cut into tiles of its
/// own on the isolate that paints, uploaded, laid on the engine, read back
/// and searched for ink again — six runs for a 4000×3000 picture placed as
/// a reference.
Future<AnicelLaidCel> _cutEngineImage(ui.Image image, PictureCut cut) async {
  final side = cut.layout.tileSize;
  final picture = DirtyRegion.fromXYWH(
    x: cut.left,
    y: cut.top,
    width: image.width,
    height: image.height,
  );
  final tiles = <({int x, int y, LaidPixels pixels})>[];
  try {
    for (final block in _layBlocks(cut.layout.tiles, side)) {
      final over = _areaOf(block, side).intersection(picture);
      if (over == null) {
        continue;
      }
      final rows = await _rasterOver(
        image,
        DirtyRegion.fromXYWH(
          x: over.left - cut.left,
          y: over.top - cut.top,
          width: over.width,
          height: over.height,
        ),
      );
      tiles.addAll(
        cutRgbaRows(
          rows.rgba,
          width: over.width,
          height: over.height,
          cut: (left: over.left, top: over.top, tileSize: side, tiles: block),
        ),
      );
    }
  } on Object {
    giveBackCut(tiles);
    rethrow;
  }
  return laidCelOf(cut.layout, tiles);
}

/// [region] of [cel] — where its file lies — laid by [placement], the
/// region's own pixels → the canvas, as [layCelPicture] lays a picture: the
/// picture the cel's tiles already are, laid from them where they lie on
/// the engine, never composed into one image or read back first. Laid on a
/// cel of [canvas] — the cel's own, unless a resize gives it another.
Future<BitmapSurface> layCelRegion({
  required BitmapSurface cel,
  required DirtyRegion region,
  required LayerPlacement placement,
  bool whole = false,
  CanvasSize? canvas,
}) async {
  final laidOn = canvas ?? cel.canvasSize;
  final layout = _layoutOf(
    CanvasSize(width: region.width, height: region.height),
    laidOn,
    placement,
    cel.tileSize,
    whole,
  );
  if (layout == null) {
    return BitmapSurface(canvasSize: laidOn, tileSize: cel.tileSize);
  }
  return _laidOnEngine(_RegionSource(cel, region), placement, layout);
}

/// [cel]'s picture where [move] — a canvas pixel of the cel to one of the
/// cel it is laid on — carries it, on a cel of [canvas] (the cel's own
/// unless given): laid from the cel's own tiles as every picture a door
/// bakes is laid ([layCelRegion]), whole (F-374-Q8).
///
/// 🚨Laid from where its FILE lies, not from the cel: the clear canvas
/// round a small picture is no part of it, and a move that grows the
/// picture grows that too — an 8×8 still fitted ×206 to its canvas asked
/// ONE raster 590080×538240 for its 8×8 of ink, and the raster failed. No
/// brush reaches a reference row, so where its file lies is all it holds.
/// A cel that does not know where its file lies (an older build's, cut at
/// the wall) is moved as the picture it is, cut at the wall.
///
/// ↩️The reference doors' own (`ProjectImportDoors._celMoved`), moved in
/// here for a canvas resize that fits its picture (I-180) — one lay of a
/// cel anew, two callers.
Future<BitmapSurface> celLaidAnew(
  BitmapSurface cel,
  LayerPlacement move, {
  CanvasSize? canvas,
}) {
  final laid = cel.laidBounds;
  final region =
      laid ?? DirtyRegion.wholePixelsOf(surfaceContentWorldRect(cel));
  return layCelRegion(
    cel: cel,
    region: region,
    placement: move.compose(
      GuideTransform(
        1,
        0,
        0,
        1,
        region.left.toDouble(),
        region.top.toDouble(),
      ),
    ),
    whole: laid != null,
    canvas: canvas,
  );
}

/// [cel] as a canvas resize's [fit] leaves it (I-180): its drawing laid
/// anew where the fit carries it ([celLaidAnew]) — by the sampler the
/// canvas shows it with, as an import's picture is laid (🗣️I-180-Q1 a) —
/// its photos carried by the same map ([celPhotosCarried]), and its texts
/// set again by [setText] from numbers that grew with it, behind the cel's
/// own wall on the new canvas ([celTextsFitted], 🗣️I-180-Q7 a).
Future<BitmapSurface> celFitted(
  BitmapSurface cel,
  CelFit fit, {
  CelTextSetter? setText,
}) async {
  final GuideTransform(:a, :d, :tx, :ty) = fit.move;
  final walk = resizeWalk(
    sx: a,
    sy: d,
    dx: tx,
    dy: ty,
    centreDx: tx,
    centreDy: ty,
  );
  final texts = await celTextsFitted(
    cel.texts,
    walk,
    wall: fit.canvasSize.pasteboardAt(cel.pasteboardReach),
    setText: setText,
  );
  final laid = await celLaidAnew(cel, fit.move, canvas: fit.canvasSize);
  return laid.copyWith(
    photos: celPhotosCarried(cel.photos, walk),
    texts: texts,
  );
}

/// Where a lay of a [picture]-sized picture by [placement] puts it on a
/// [canvas]-sized cel of [tileSize] tiles ([layCelPicture]) — null where
/// it puts nothing there.
CelLayout? _layoutOf(
  CanvasSize picture,
  CanvasSize canvas,
  LayerPlacement placement,
  int tileSize,
  bool whole,
) {
  final placed = placedBounds(placement, picture);
  final laid = whole && !placed.isEmpty
      ? DirtyRegion.wholePixelsOf(placed)
      : null;
  final clipped = laid == null
      ? placed.intersect(canvas.pasteboardAt(PasteboardReach.whole).rect)
      : laid.rect;
  if (clipped.isEmpty) {
    return null;
  }
  return (
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
}

/// Where [placement], standing a picture 1:1 on whole pixels, cuts it into
/// [layout]'s tiles.
PictureCut _cutAt(LayerPlacement placement, CelLayout layout) =>
    (left: placement.tx.toInt(), top: placement.ty.toInt(), layout: layout);

/// [source] laid by [placement] over [layout]'s tiles on the engine, by
/// the law the canvas lays a row by — its pose's inverse as the row's
/// ([gpuRowInverse]), sampled at the canvas's own resolution
/// ([canvasResolutionSampling]) — so a picture baked where it shows is the
/// picture shown, byte for byte: a run of the composite a part of a block
/// ([_partsFitting]), read back a tile at a time.
///
/// 🗣️I-120-Q26 (유저 2026-11-07 「굽기를 화면에 맞춘다 — 확대된 그림은 계단
/// 그대로 굽는다」) · Q28 (「축소도 같은 법 — 화면처럼 최근접으로 굽는다」) ·
/// gpu-export-path 1b ② (관제 2026-11-11 18:47: 「굽기를 화면과 같은 R1 ·
/// 같은 샘플러 고르기로 옮기는 것이 곧 I-120-Q26」). ↩️The lay drew the
/// picture into a Flutter raster a block at a time, by Flutter's sampler,
/// uploaded premultiplied by the C engine, while the canvas lays its rows
/// on the engine: 🔬2026-11-11, a 64² checker baked in place came out
/// 54–1,992 pixels apart from the frame it was, at every pose but a halving
/// — its edge, which Flutter antialiased and the engine does not, and every
/// centre on a texel's edge, where each read the other texel.
Future<BitmapSurface> _laidOnEngine(
  _Source source,
  LayerPlacement placement,
  CelLayout layout,
) async {
  if (layout.tileSize != gpuTileSide) {
    throw ArgumentError(
      'the engine lays tiles of $gpuTileSide, not ${layout.tileSize}',
    );
  }
  final back = canvasToArtwork(placement);
  if (back == null) {
    return laidCelSurface(laidCelOf(layout, const []));
  }
  final tiles = <({int x, int y, LaidPixels pixels})>[];
  try {
    for (final block in _layBlocks(layout.tiles, layout.tileSize)) {
      for (final part in _partsFitting(block, source.size, back, layout)) {
        tiles.addAll(
          await _laidArea(
            source,
            back,
            part,
            _areaOf(part, layout.tileSize),
            layout.canvas,
          ),
        );
      }
    }
  } on Object {
    giveBackCut(tiles);
    rethrow;
  }
  return laidCelSurface(laidCelOf(layout, tiles));
}

/// [area]'s pixels — all of [part]'s tiles, or a piece of its one tile —
/// laid from what of [source] they reach: each of [part]'s tiles, row by
/// row, with nothing outside [area] — none where they reach none of it.
///
/// A part of ONE tile that reaches past one raster ([_partsFitting]) is
/// laid as the halves of its area, each from what IT reaches, and put back
/// together: a pixel reads the one texel its centre lands on, so the
/// halves are the whole to the byte. 🔬2026-11-08 (I-120-Q28): read from
/// what it reached decoded smaller, such a tile came out with 6,630 grey
/// pixels of black-and-white line art laid at 0.15.
///
/// Its tiles come as [CutTiles]: only those with ink, each a block of its
/// own ([_ran]).
Future<CutTiles> _laidArea(
  _Source source,
  GuideTransform back,
  TileRange part,
  DirtyRegion area,
  CanvasSize canvas,
) async {
  final reached = _reachedBy(area, source.size, back);
  if (reached == null) {
    return const [];
  }
  final oneTile = part.firstX == part.lastX && part.firstY == part.lastY;
  if (oneTile && !_fitsOneRaster(reached) && area.width + area.height > 2) {
    final (first, second) = _halvesOf(area);
    final one = await _laidArea(source, back, part, first, canvas);
    final CutTiles other;
    try {
      other = await _laidArea(source, back, part, second, canvas);
    } on Object {
      giveBackCut(one);
      rethrow;
    }
    return laidTogether(one, other);
  }
  final held = await source.tilesOver(reached);
  if (held.tiles.isEmpty) {
    return const [];
  }
  return _ran(held, back, part, area, canvas);
}

/// [area] in two along its longer side.
(DirtyRegion, DirtyRegion) _halvesOf(DirtyRegion area) {
  if (area.width >= area.height) {
    final half = area.width >> 1;
    return (
      DirtyRegion.fromXYWH(
        x: area.left,
        y: area.top,
        width: half,
        height: area.height,
      ),
      DirtyRegion.fromXYWH(
        x: area.left + half,
        y: area.top,
        width: area.width - half,
        height: area.height,
      ),
    );
  }
  final half = area.height >> 1;
  return (
    DirtyRegion.fromXYWH(
      x: area.left,
      y: area.top,
      width: area.width,
      height: half,
    ),
    DirtyRegion.fromXYWH(
      x: area.left,
      y: area.top + half,
      width: area.width,
      height: area.height - half,
    ),
  );
}

/// The tiles two runs over apart areas of them laid, as one: each byte is
/// one run's, the other's nothing there — a tile both laid is [one]'s
/// block, the [other]'s bytes put into it and its own block given back.
///
/// The tile the two made is asked its colour again ([LaidPixels.keeping]):
/// two halves of one opaque colour are a tile of one colour, which neither
/// half was.
@visibleForTesting
CutTiles laidTogether(CutTiles one, CutTiles other) {
  final together = {for (final tile in one) (tile.x, tile.y): tile};
  for (final tile in other) {
    final laid = together[(tile.x, tile.y)];
    if (laid == null) {
      together[(tile.x, tile.y)] = tile;
      continue;
    }
    final into = laid.pixels.inABlock(gpuTileSide);
    final from = tile.pixels.inABlock(gpuTileSide);
    final bytes = into.asTypedList(gpuTileBytes);
    final rgba = from.asTypedList(gpuTileBytes);
    for (var at = 0; at < bytes.length; at += 1) {
      bytes[at] |= rgba[at];
    }
    TileBlocks.free(from);
    together[(tile.x, tile.y)] = (
      x: tile.x,
      y: tile.y,
      pixels: LaidPixels.keeping(into, bytes),
    );
  }
  return [...together.values];
}

/// The pixels [part]'s tiles cover.
DirtyRegion _areaOf(TileRange part, int tileSize) => DirtyRegion.fromXYWH(
  x: part.firstX * tileSize,
  y: part.firstY * tileSize,
  width: (part.lastX - part.firstX + 1) * tileSize,
  height: (part.lastY - part.firstY + 1) * tileSize,
);

/// [held] laid by [back] — a canvas pixel to the picture's — over [part]'s
/// tiles of a [canvas]-sized cel, nothing outside [area]: ONE run of the
/// composite, its one row the canvas's own ([_laidOnEngine]), submitted
/// here and read where a worker waits for the GPU ([_inkedTilesOf]).
///
/// ↩️(2026-11-14, card a-raster-import-goes-gpu-cpu-gpu-cpu) the run was
/// read here: the isolate that paints waited for the GPU, then searched
/// every tile for ink and copied each into a tile of its own.
Future<CutTiles> _ran(
  _HeldTiles held,
  GuideTransform back,
  TileRange part,
  DirtyRegion area,
  CanvasSize canvas,
) async {
  final coords = [
    for (var y = part.firstY; y <= part.lastY; y += 1)
      for (var x = part.firstX; x <= part.lastX; x += 1) (x: x, y: y),
  ];
  final ledger = EngineTileLedger.instance;
  final run = ledger.held((hold) {
    final plan = GpuPlan(appGpuComposite.engine);
    try {
      final grid = hold.gridOf(BrushFrameKey.noCel, held.tiles);
      final GuideTransform(:a, :b, :c, :d, :tx, :ty) = back;
      final laid = plan.row(
        set: plan.set(grid.x0, grid.y0, grid.columns, grid.rows, grid.tiles),
        inverse: gpuRowInverse(
          GuideTransform(a, b, c, d, tx + held.dx, ty + held.dy),
        ),
        sampling: canvasResolutionSampling,
        columns: canvas.width,
        rows: canvas.height,
        mode: GpuBlend.normal,
      );
      if (!laid) {
        return null;
      }
      debugLayRuns += 1;
      return appGpuComposite.run(
        ledger.pool,
        plan,
        [for (final (:x, :y) in coords) (x, y)],
        (area.left, area.top, area.rightExclusive, area.bottomExclusive),
      );
    } finally {
      // Submitted, the run keeps what it reads of the plan — as a frame's
      // composite lets its plan go once it has run (`layer_stack_engine_
      // screen.dart`).
      plan.free();
    }
  });
  if (run == null) {
    return const [];
  }
  try {
    return await _inkedTilesOf(run.reader, coords);
  } finally {
    run.free();
  }
}

/// The tiles [reader]'s run put — at [coords], in the order asked — read
/// on a worker, whose the wait for the GPU then is
/// ([GpuCompositedReader]): each one with ink cut into a block of its own
/// there ([_cutInked]), so the isolate that paints is handed the blocks
/// and none of their bytes. ⚠️Its own function, so all the worker is sent
/// is [reader] and [coords]: a closure in [_ran] would carry what that
/// one's other closure holds — the tile ledger.
Future<CutTiles> _inkedTilesOf(
  GpuCompositedReader reader,
  List<({int x, int y})> coords,
) => onAWorker(() => _cutInked(reader, coords));

/// [_inkedTilesOf]'s tiles, cut where they are read.
CutTiles _cutInked(
  GpuCompositedReader reader,
  List<({int x, int y})> coords,
) {
  final bytes = reader.read();
  final side = gpuTileSide;
  final tiles = <({int x, int y, LaidPixels pixels})>[];
  try {
    for (final (at, (:x, :y)) in coords.indexed) {
      tiles.addAll(
        cutRgbaRows(
          Uint8List.sublistView(
            bytes,
            at * gpuTileBytes,
            (at + 1) * gpuTileBytes,
          ),
          width: side,
          height: side,
          cut: (
            left: x * side,
            top: y * side,
            tileSize: side,
            tiles: (firstX: x, lastX: x, firstY: y, lastY: y),
          ),
        ),
      );
    }
  } on Object {
    giveBackCut(tiles);
    rethrow;
  }
  return tiles;
}

/// What a lay reads its picture from: tiles of it, a part at a time
/// ([tilesOver]).
sealed class _Source {
  const _Source();

  /// The picture's size: its pixels from (0, 0).
  CanvasSize get size;

  /// The tiles that hold [reached] — pixels of the picture — and where
  /// they lie past the picture's own.
  Future<_HeldTiles> tilesOver(_Reached reached);
}

/// Tiles of a picture — in a space a whole number of pixels from its own,
/// [dx] across and [dy] down — keyed where they lie in that space.
typedef _HeldTiles = ({Map<TileCoord, BitmapTile> tiles, int dx, int dy});

/// A picture the engine holds, cut into tiles where a part reaches it:
/// rastered 1:1 over that part first — at no more than a lay's raster a
/// side ([layRasterSide]), which every engine holds.
final class _EngineSource extends _Source {
  const _EngineSource(this.image);

  final ui.Image image;

  @override
  CanvasSize get size => CanvasSize(width: image.width, height: image.height);

  @override
  Future<_HeldTiles> tilesOver(_Reached reached) async {
    final over = _onTheGrid(reached, size);
    final cut = cutPixels(await _rasterOver(image, over), (
      left: over.left,
      top: over.top,
      layout: (
        canvas: size,
        tileSize: gpuTileSide,
        tiles: over.tileRange(tileSize: gpuTileSide),
        laid: null,
      ),
    ));
    return (tiles: laidCelSurface(cut).tiles, dx: 0, dy: 0);
  }
}

/// [image]'s pixels over [over], straight, row after row — drawn 1:1 on
/// whole pixels, which copies.
Future<PixelsPicture> _rasterOver(ui.Image image, DirtyRegion over) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawImageRect(
    image,
    over.rect,
    ui.Rect.fromLTWH(0, 0, over.width.toDouble(), over.height.toDouble()),
    ui.Paint()
      ..filterQuality = ui.FilterQuality.none
      ..isAntiAlias = false,
  );
  final picture = recorder.endRecording();
  // 🚨THE `finally` IS THE POINT. `toImage` is the awaited call, and an
  // await that throws skips every statement after it — so a dispose written
  // on the line below runs on the landing arm ONLY, and a raster that
  // failed took the picture's native memory with it.
  final ui.Image raster;
  try {
    raster = await picture.toImage(over.width, over.height);
  } finally {
    picture.dispose();
  }
  try {
    return PixelsPicture(
      await straightRgbaOf(raster),
      width: over.width,
      height: over.height,
    );
  } finally {
    raster.dispose();
  }
}

/// [region] of [cel] — where its file lies — as the picture a lay reads:
/// the cel's own tiles, on the canvas, [region]'s top-left the picture's.
final class _RegionSource extends _Source {
  const _RegionSource(this.cel, this.region);

  final BitmapSurface cel;
  final DirtyRegion region;

  @override
  CanvasSize get size => CanvasSize(width: region.width, height: region.height);

  @override
  Future<_HeldTiles> tilesOver(_Reached reached) async {
    final over = DirtyRegion.fromXYWH(
      x: region.left + reached.left,
      y: region.top + reached.top,
      width: reached.width,
      height: reached.height,
    );
    return (
      tiles: {
        for (final covered in tilesCovering(cel, over))
          covered.coord: covered.tile,
      },
      dx: region.left,
      dy: region.top,
    );
  }
}

/// [reached] out to the tiles it lies in, inside the picture: what a part
/// cuts of a picture.
DirtyRegion _onTheGrid(_Reached reached, CanvasSize picture) {
  final side = gpuTileSide;
  final left = floorDiv(reached.left, side) * side;
  final top = floorDiv(reached.top, side) * side;
  final right = math.min(
    picture.width,
    -floorDiv(-(reached.left + reached.width), side) * side,
  );
  final bottom = math.min(
    picture.height,
    -floorDiv(-(reached.top + reached.height), side) * side,
  );
  return DirtyRegion.fromXYWH(
    x: left,
    y: top,
    width: right - left,
    height: bottom - top,
  );
}

/// Whether what a raster reaches ([_reachedBy]) is no longer a side than
/// one lay's raster ([layRasterSide]).
bool _fitsOneRaster(_Reached reached) {
  final side = debugLayRasterSide ?? layRasterSide;
  return reached.width <= side && reached.height <= side;
}

/// [block], cut into the parts whose reach into the picture
/// ([_reachedBy]) fits one raster ([_fitsOneRaster]) — a block of one tile
/// however far it reaches, which is laid in halves ([_laidArea]).
Iterable<TileRange> _partsFitting(
  TileRange block,
  CanvasSize picture,
  GuideTransform back,
  CelLayout layout,
) sync* {
  final reached = _reachedBy(_areaOf(block, layout.tileSize), picture, back);
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
  yield* _partsFitting(halves.$1, picture, back, layout);
  yield* _partsFitting(halves.$2, picture, back, layout);
}

/// Pixels of a picture, from its own top-left.
typedef _Reached = ({int left, int top, int width, int height});

/// The pixels of a [picture]-sized picture that [area]'s pixels sample
/// where [back] takes a canvas pixel to the picture's — what [area] covers,
/// taken back into the picture to whole texels — or null where it reaches
/// none of the picture.
_Reached? _reachedBy(DirtyRegion area, CanvasSize picture, GuideTransform back) {
  final over = placedRectBounds(back, area.rect);
  // A pixel reads the one texel its centre lands on, and a centre lies half
  // a pixel inside the area, so it lands inside what the area covers taken
  // back — on a texel's edge, either texel of it.
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

/// The longest side, in pixels, of ONE part of a picture a lay reads at a
/// time — the tiles it cuts of it, the raster of it a picture the engine
/// holds is copied out of ([_rasterOver]) — and of one run's block of
/// tiles: a picture that covers more is laid a block of tiles at a time
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

/// How many runs of the engine the lays have asked for, counted for the
/// tests that see a picture laid in blocks.
@visibleForTesting
int debugLayRuns = 0;

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

/// Bakes [tiles] — a picture as a cel's own tiles, by their place on the
/// grid — as [key]'s cel behind [wall]: a .clip's vector layer, its tiles
/// the engine's as it landed them (`clipVectorTiles`) inside that wall.
void bakeCelTiles(
  BrushFrameStore store,
  BrushFrameKey key,
  PasteboardWall wall,
  Map<TileCoord, BitmapTile> tiles,
) => bakeCelSurface(
  store,
  key,
  BitmapSurface(
    canvasSize: wall.canvas,
    pasteboardReach: wall.reach,
    tiles: tiles,
  ),
);

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
