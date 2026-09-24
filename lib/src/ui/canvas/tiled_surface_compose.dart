import 'dart:math' as math;
import 'dart:ui' as ui;

import '../../models/bitmap_surface.dart';
import '../../models/bitmap_tile.dart';
import '../../models/pasteboard_bounds.dart';
import '../../models/playback_quality.dart';
import '../../core/dev_profile.dart';
import '../../services/straight_rgba_image.dart';
import 'bitmap_tile_image_cache.dart';
import 'raster_picture.dart';
import 'tile_origin.dart';

/// A composed surface image plus the CANVAS-SPACE rect it covers.
///
/// For a surface whose tiles all sit inside the canvas, [worldRect] is
/// exactly the canvas rect and the image is canvas-sized — byte-identical
/// to [composeTiledSurfaceImage]. Pasteboard content grows the rect (and
/// the image) only as far as the stored tiles reach, so layers without
/// off-canvas artwork pay nothing.
class PositionedSurfaceImage {
  const PositionedSurfaceImage({required this.image, required this.worldRect});

  final ui.Image image;
  final ui.Rect worldRect;

  /// Whether this is the plain canvas-extent case (consumers keep their
  /// exact legacy draw path for it — byte parity).
  bool isCanvasExtent(BitmapSurface surface) =>
      worldRect == surface.canvasSize.canvasRect;
}

/// The canvas rect UNIONED with every stored tile's rect — the extent a
/// positioned compose rasters. Integer-aligned by construction.
ui.Rect surfaceContentWorldRect(BitmapSurface surface) {
  final canvas = surface.canvasSize.canvasRect;
  final tiles = tileCoordsWorldRect(surface.tiles.keys, surface.tileSize);
  return tiles == null ? canvas : canvas.expandToInclude(tiles);
}

/// The part of [surfaceContentWorldRect] that holds the stored tiles —
/// where every pixel of the composed image that is not transparent sits.
///
/// On the halving grid of the whole image: the tiles' rect pushed out to
/// multiples of 2^[PlaybackQuality.deepestLevel] counted from the content's
/// origin, and cut back to the content. So at every level of the display's
/// pyramid its edges fall on whole texels of the whole content's level, and
/// the part of that level it covers can be cut out as it is.
ui.Rect surfaceInkWorldRect(BitmapSurface surface) {
  final content = surfaceContentWorldRect(surface);
  final tiles = tileCoordsWorldRect(surface.tiles.keys, surface.tileSize);
  if (tiles == null) {
    return content;
  }
  final grid = (1 << PlaybackQuality.deepestLevel).toDouble();
  double outward(double value, double origin, {required bool up}) {
    final blocks = (value - origin) / grid;
    return origin +
        (up ? blocks.ceilToDouble() : blocks.floorToDouble()) * grid;
  }

  return ui.Rect.fromLTRB(
    outward(tiles.left, content.left, up: false),
    outward(tiles.top, content.top, up: false),
    math.min(content.right, outward(tiles.right, content.left, up: true)),
    math.min(content.bottom, outward(tiles.bottom, content.top, up: true)),
  );
}

/// Composes a tiled [BitmapSurface] into one full-resolution [ui.Image] by
/// drawing per-tile GPU images — the editing canvas's display route, reused
/// for playback/preview rendering.
///
/// Tiles already decoded in [reuse] (typically [BitmapTileImageCache.instance],
/// which the editing canvas keeps warm for the frame on screen) are drawn
/// as-is, so rebuilding the ACTIVE frame after a stroke uploads nothing:
/// cost scales with the changed tiles, not the canvas. Missing tiles decode
/// transiently and are disposed right after the compose — cold frames pay
/// one upload per stored tile without pinning GPU copies of every frame's
/// artwork.
///
/// Byte-parity with the CPU assembly path ([bitmapSurfaceToImage]): tile
/// bytes premultiply through the SAME mul-div-255 rounding
/// ([BitmapTileImageCache.premultipliedTileUpload]) and are drawn 1:1 at
/// integer offsets with [ui.FilterQuality.none] over a transparent base, so
/// srcOver passes the premultiplied bytes through unchanged.
///
/// The caller owns (and must dispose) the returned image.
///
/// [shouldAbort] (R13-4, the warm path only): checked before every tile
/// decode and before the final full-canvas raster — the two cost centers —
/// so an interactive input stops an opportunistic compose within ~one tile
/// (1–2ms), not one canvas. Aborts return null with nothing cached and the
/// transient decodes disposed; without [shouldAbort] the result is never
/// null.
Future<ui.Image?> composeTiledSurfaceImage(
  BitmapSurface surface, {
  BitmapTileImageCache? reuse,
  bool Function()? shouldAbort,
}) => _composeAsync(
  surface,
  reuse: reuse,
  shouldAbort: shouldAbort,
  over: surface.canvasSize.canvasRect,
);

/// THE tile compose, async: draw every tile 1:1 at its integer offset and
/// raster the canvas-space rect [over] (the canvas, the content grown by
/// the pasteboard, or the part of it that holds the ink).
///
/// Four functions in this file used to carry this loop — canvas-size and
/// positioned, each async and sync — and they differed only in the origin,
/// the extent, and whether the raster awaits. Four copies of a recorder
/// lifetime is four chances to leak one.
Future<ui.Image?> _composeAsync(
  BitmapSurface surface, {
  required BitmapTileImageCache? reuse,
  required bool Function()? shouldAbort,
  required ui.Rect over,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.translate(-over.left, -over.top);
  final paint = ui.Paint()..filterQuality = ui.FilterQuality.none;
  final transient = <ui.Image>[];
  var recorderClosed = false;

  try {
    for (final entry in surface.tiles.entries) {
      final tile = entry.value;
      var image = reuse?.imageFor(tile);
      if (image == null) {
        if (shouldAbort?.call() ?? false) {
          recorder.endRecording().dispose();
          recorderClosed = true;
          return null;
        }
        image = await _decodeTile(tile);
        transient.add(image);
      }
      canvas.drawImage(
        image,
        tileOriginOffset((coord: entry.key, tile: tile)),
        paint,
      );
    }

    final picture = recorder.endRecording();
    recorderClosed = true;
    try {
      if (shouldAbort?.call() ?? false) {
        return null;
      }
      return await picture.toImage(
        over.width.round(),
        over.height.round(),
      );
    } finally {
      picture.dispose();
    }
  } finally {
    if (!recorderClosed) {
      recorder.endRecording().dispose();
    }
    for (final image in transient) {
      image.dispose();
    }
  }
}

/// THE tile compose, sync: the same draw, rastered deferred on the GPU —
/// plus, when [snapshot], the plain snapshot of the same recording
/// ([rasterPictureAndSnapshot]: what a holder keeps INSTEAD once it lands,
/// because the deferred image pins every tile picture it drew for as long
/// as it lives).
///
/// 🚨★★★[makePictures] IS WHETHER THE CEL WAS ON SCREEN. A tile that has no
/// picture gets one made now, through the one door
/// ([BitmapTileImageCache.pictureFor]) — so the compose cannot miss, and a
/// row that was showing this cel a frame ago (as the layer being drawn on,
/// or as its picture before an edit) shows it on THIS frame too: 유저 절대규칙
/// 「보이는 중이랑 결과랑 절대로 다르면 안 되」, and a row that goes blank for
/// the frames an asynchronous compose takes is neither. False is for a cel
/// that was NOT on screen (a frame scrubbed to, a project just opened):
/// making a whole cel's pictures inside a build, for every cold row at
/// once, is a stall nobody asked for — so there a missing picture answers
/// null and the caller takes the asynchronous road, as it always has.
///
/// 🪦Until 2026-09-17 there was only the second kind, and it stood on a
/// premise the one door retired: 「the on-screen frame's tiles are always
/// decoded」. They were while a background pass pre-warmed every committed
/// tile; with a tile picturing itself inside the paint that shows it, a
/// cel the paint reached only part of (the direct walk past the display
/// buffer's cap paints the screen, not the cel) has pictures for that part
/// only — and the layer you had just been drawing on vanished on the frame
/// you switched away (measured on the walk: 0 of 32 columns on the first
/// frame after the switch).
({ui.Image deferred, Future<ui.Image>? real})? _composeSync(
  BitmapSurface surface, {
  required BitmapTileImageCache reuse,
  required bool makePictures,
  required bool snapshot,
  required ui.Rect over,
}) {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.translate(-over.left, -over.top);
  final paint = ui.Paint()..filterQuality = ui.FilterQuality.none;

  for (final entry in surface.tiles.entries) {
    final tile = entry.value;
    final image = makePictures ? reuse.pictureFor(tile) : reuse.imageFor(tile);
    if (image == null) {
      recorder.endRecording().dispose();
      return null;
    }
    canvas.drawImage(
      image,
      tileOriginOffset((coord: entry.key, tile: tile)),
      paint,
    );
  }
  return rasterPictureAndSnapshot(
    recorder,
    over.width.round(),
    over.height.round(),
    snapshot: snapshot,
  );
}

/// [surface]'s picture NOW, canvas-sized: every tile's own picture, made
/// here if it has none — the sheets' display image, which shows a surface
/// the moment it is the surface (a stroke's pen-up, an undo, a redo). Byte
/// parity with [composeTiledSurfaceImage]: the same tile pictures, the same
/// 1:1 integer-offset draws. The caller owns the returned image.
ui.Image composeTiledSurfaceImageNow(
  BitmapSurface surface, {
  required BitmapTileImageCache reuse,
}) {
  return labProbe(
    'composeSync(${surface.tiles.length}t '
    '${surface.canvasSize.width}x${surface.canvasSize.height})',
    () => _composeSync(
      surface,
      reuse: reuse,
      makePictures: true,
      snapshot: false,
      over: surface.canvasSize.canvasRect,
    )!.deferred,
  );
}

/// The pasteboard-aware sibling of [composeTiledSurfaceImage]: rasters the
/// surface over [surfaceContentWorldRect] and returns the image WITH that
/// rect, so the editing layer stack can show off-canvas artwork at its
/// true position. Same tile pipeline, same premultiply, same 1:1 integer
/// offsets — only the raster origin/extent differ (and only when
/// pasteboard tiles exist).
///
/// [over] rasters part of the content instead: a rect on whole canvas
/// pixels that holds every tile ([surfaceInkWorldRect]). Each tile lands
/// texel for texel where it lands in the whole image, so what comes back is
/// that image's pixels over [over] — without the rest being drawn first.
Future<PositionedSurfaceImage?> composePositionedSurfaceImage(
  BitmapSurface surface, {
  BitmapTileImageCache? reuse,
  bool Function()? shouldAbort,
  ui.Rect? over,
}) async {
  final worldRect = _composedOver(surface, over);
  final image = await _composeAsync(
    surface,
    reuse: reuse,
    shouldAbort: shouldAbort,
    over: worldRect,
  );
  return image == null
      ? null
      : PositionedSurfaceImage(image: image, worldRect: worldRect);
}

/// The synchronous positioned compose — the layer stack's, for the frame a
/// row changes route or content ([_composeSync] says what [makePictures]
/// and [snapshot] mean; [over] is the async twin's). Null only when
/// [makePictures] is false and a tile has no picture.
({PositionedSurfaceImage deferred, Future<ui.Image>? real})?
composePositionedSurfaceImageSync(
  BitmapSurface surface, {
  required BitmapTileImageCache reuse,
  required bool makePictures,
  required bool snapshot,
  ui.Rect? over,
}) {
  final worldRect = _composedOver(surface, over);
  final composed = _composeSync(
    surface,
    reuse: reuse,
    makePictures: makePictures,
    snapshot: snapshot,
    over: worldRect,
  );
  if (composed == null) {
    return null;
  }
  return (
    deferred: PositionedSurfaceImage(
      image: composed.deferred,
      worldRect: worldRect,
    ),
    real: composed.real,
  );
}

/// The rect a positioned compose rasters: [over], or the whole content.
ui.Rect _composedOver(BitmapSurface surface, ui.Rect? over) {
  if (over == null) {
    return surfaceContentWorldRect(surface);
  }
  assert(() {
    final tiles = tileCoordsWorldRect(surface.tiles.keys, surface.tileSize);
    return tiles == null || over.expandToInclude(tiles) == over;
  }(), 'a part of the content composed on its own must hold every tile');
  return over;
}

Future<ui.Image> _decodeTile(BitmapTile tile) async {
  // 🚨Through [uploadRawRgba], not `ui.decodeImageFromPixels`: the SDK
  // function tells nobody when a decode fails, so the `Completer` that stood
  // here could only ever succeed — and the `upload.free()` it carried lived
  // in the same success-only callback. A refused tile therefore leaked its
  // native staging buffer AND left this future pending. The `finally` frees
  // on both roads; see [uploadRawRgba] for the SDK's two dropped chains.
  final upload = BitmapTileImageCache.premultipliedTileUpload(tile);
  try {
    return await uploadRawRgba(
      upload.view,
      width: tile.size,
      height: tile.size,
    );
  } finally {
    upload.free();
  }
}
