import 'dart:ui' as ui;

import '../../models/bitmap_surface.dart';
import '../../models/bitmap_tile.dart';
import '../../core/dev_profile.dart';
import '../../services/straight_rgba_image.dart';
import 'bitmap_tile_image_cache.dart';
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
      worldRect ==
      ui.Rect.fromLTWH(
        0,
        0,
        surface.canvasSize.width.toDouble(),
        surface.canvasSize.height.toDouble(),
      );
}

/// The canvas rect UNIONED with every stored tile's rect — the extent a
/// positioned compose rasters. Integer-aligned by construction.
ui.Rect surfaceContentWorldRect(BitmapSurface surface) {
  final canvas = ui.Rect.fromLTWH(
    0,
    0,
    surface.canvasSize.width.toDouble(),
    surface.canvasSize.height.toDouble(),
  );
  final tiles = tileCoordsWorldRect(surface.tiles.keys, surface.tileSize);
  return tiles == null ? canvas : canvas.expandToInclude(tiles);
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
  width: surface.canvasSize.width,
  height: surface.canvasSize.height,
);

/// THE tile compose, async: draw every tile 1:1 at its integer offset and
/// raster the result at [width]x[height], with [origin] subtracted first
/// (the positioned variants raster over the pasteboard rect instead of the
/// canvas).
///
/// Four functions in this file used to carry this loop — canvas-size and
/// positioned, each async and sync — and they differed only in the origin,
/// the extent, and whether the raster awaits. Four copies of a recorder
/// lifetime is four chances to leak one.
Future<ui.Image?> _composeAsync(
  BitmapSurface surface, {
  required BitmapTileImageCache? reuse,
  required bool Function()? shouldAbort,
  required int width,
  required int height,
  ui.Offset origin = ui.Offset.zero,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.translate(-origin.dx, -origin.dy);
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
      return await picture.toImage(width, height);
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

/// THE tile compose, sync: the same draw, but every tile must ALREADY be
/// decoded in [reuse] — a miss returns null so the caller falls back to
/// the async path. Rasterization stays deferred on the GPU
/// ([ui.Picture.toImageSync]).
ui.Image? _composeSync(
  BitmapSurface surface, {
  required BitmapTileImageCache reuse,
  required int width,
  required int height,
  ui.Offset origin = ui.Offset.zero,
}) {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.translate(-origin.dx, -origin.dy);
  final paint = ui.Paint()..filterQuality = ui.FilterQuality.none;

  for (final entry in surface.tiles.entries) {
    final tile = entry.value;
    final image = reuse.imageFor(tile);
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

  final picture = recorder.endRecording();
  try {
    return picture.toImageSync(width, height);
  } finally {
    picture.dispose();
  }
}

/// Synchronous variant for latency-critical swaps (the layer-switch
/// handoff): composes ONLY when every tile is already decoded in [reuse] —
/// the on-screen frame's tiles always are — via [ui.Picture.toImageSync]
/// (rasterization stays deferred on the GPU). Returns null when any tile
/// is missing so the caller falls back to the async path; byte parity
/// matches [composeTiledSurfaceImage] (same tile images, same 1:1
/// integer-offset draws). The caller owns the returned image.
ui.Image? composeTiledSurfaceImageSyncOrNull(
  BitmapSurface surface, {
  required BitmapTileImageCache reuse,
}) {
  return labProbe(
    'composeSync(${surface.tiles.length}t '
    '${surface.canvasSize.width}x${surface.canvasSize.height})',
    () => _composeTiledSurfaceImageSyncOrNull(surface, reuse: reuse),
  );
}

ui.Image? _composeTiledSurfaceImageSyncOrNull(
  BitmapSurface surface, {
  required BitmapTileImageCache reuse,
}) => _composeSync(
  surface,
  reuse: reuse,
  width: surface.canvasSize.width,
  height: surface.canvasSize.height,
);

/// The pasteboard-aware sibling of [composeTiledSurfaceImage]: rasters the
/// surface over [surfaceContentWorldRect] and returns the image WITH that
/// rect, so the editing layer stack can show off-canvas artwork at its
/// true position. Same tile pipeline, same premultiply, same 1:1 integer
/// offsets — only the raster origin/extent differ (and only when
/// pasteboard tiles exist).
Future<PositionedSurfaceImage?> composePositionedSurfaceImage(
  BitmapSurface surface, {
  BitmapTileImageCache? reuse,
  bool Function()? shouldAbort,
}) async {
  final worldRect = surfaceContentWorldRect(surface);
  final image = await _composeAsync(
    surface,
    reuse: reuse,
    shouldAbort: shouldAbort,
    width: worldRect.width.round(),
    height: worldRect.height.round(),
    origin: worldRect.topLeft,
  );
  return image == null
      ? null
      : PositionedSurfaceImage(image: image, worldRect: worldRect);
}

/// Synchronous positioned variant (the layer-switch handoff): composes
/// ONLY when every tile is already decoded in [reuse]; null otherwise.
PositionedSurfaceImage? composePositionedSurfaceImageSyncOrNull(
  BitmapSurface surface, {
  required BitmapTileImageCache reuse,
}) {
  final worldRect = surfaceContentWorldRect(surface);
  final image = _composeSync(
    surface,
    reuse: reuse,
    width: worldRect.width.round(),
    height: worldRect.height.round(),
    origin: worldRect.topLeft,
  );
  return image == null
      ? null
      : PositionedSurfaceImage(image: image, worldRect: worldRect);
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
