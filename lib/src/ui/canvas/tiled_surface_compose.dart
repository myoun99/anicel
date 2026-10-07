import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../models/bitmap_surface.dart';
import '../../models/bitmap_tile.dart';
import '../../models/pasteboard_bounds.dart';
import '../../models/playback_quality.dart';
import '../../models/tile_coord.dart';
import '../../core/dev_profile.dart';
import '../../services/cel_text_laying.dart';
import 'bitmap_tile_image_cache.dart';
import 'display_resample.dart';
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

/// The tiles a compose DRAWS for [surface], and the tiles every rect here
/// is measured from: the picture as shown — its drawing with the texts it
/// carries laid over it (`celSurfaceWithTextsLaid`).
///
/// 🚨★★★A COMPOSE CANNOT BE HANDED A PICTURE'S DRAWING WITHOUT ITS TEXTS
/// (R9-rest, 유저 2026-10-06: 「셀의 그림이랑 정확히 동일」). Every function in
/// this file reads its tiles through here, so no caller is the one that
/// forgot — and a text that reaches past the drawing grows the rect a
/// compose rasters exactly as a stroke there would. A surface that carries
/// no text comes back as the object it was.
Map<TileCoord, BitmapTile> _tilesShownBy(BitmapSurface surface) =>
    celSurfaceWithTextsLaid(surface).tiles;

/// The canvas rect UNIONED with every stored tile's rect — the extent a
/// positioned compose rasters. Integer-aligned by construction.
ui.Rect surfaceContentWorldRect(BitmapSurface surface) {
  final canvas = surface.canvasSize.canvasRect;
  final tiles = tileCoordsWorldRect(
    _tilesShownBy(surface).keys,
    surface.tileSize,
  );
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
  final tiles = tileCoordsWorldRect(
    _tilesShownBy(surface).keys,
    surface.tileSize,
  );
  if (tiles == null) {
    return content;
  }
  final grid = rectOutwardOnGrid(
    tiles,
    1.0 / (1 << PlaybackQuality.deepestLevel),
    origin: content.topLeft,
  );
  return ui.Rect.fromLTRB(
    grid.left,
    grid.top,
    math.min(content.right, grid.right),
    math.min(content.bottom, grid.bottom),
  );
}

/// How an asynchronous compose makes the pictures of the tiles that have
/// none. Either way a picture comes through the one door
/// ([BitmapTileImageCache.pictureOfTile]), is the compose's own, and is let
/// go right after it; what differs is whether the compose gives way while
/// it makes them.
enum MissingTilePictures {
  /// A run of them at a time ([tilePictureRun]), the event queue given its
  /// turn between runs ([_giveWay]) — which is what lets a pen that comes
  /// down be heard, and an opportunistic compose be stood down
  /// ([shouldAbort]), within a run. The road of everything that builds a
  /// layer's image off the frame: the warm, a row the canvas fills in, a
  /// cut the track stack asks for.
  ///
  /// 🪦Until 2026-10-07 this was `decodedInTurn`: every tile DECODED BY THE
  /// ENGINE AND AWAITED, one at a time, and the giving way was that wait.
  /// 🔬Measured on the Windows app (debug build, a user's project, cuts of
  /// 2340×1654 and 2540×1654 — board F-296): the decode rounds were 55–78%
  /// of a whole cut's warm with its cels in memory and over 90% of its
  /// first warm off the file — 0.3–1.3 ms a tile, 500–3,700 tiles a cut —
  /// where the door makes a picture in 0.04 ms. A cut of 35 pictures warmed
  /// in 0.96 s by rounds and 0.65 s through the door at full quality, 1.59
  /// and 0.90 s at half; with other work loading the machine, 5–8 s and
  /// 2–3 s — a round waits its turn on two busy threads, three times a tile.
  madeInTurn,

  /// All of them at once — for a render somebody is WAITING for and nobody
  /// can stand down: an export's frame, a panel's picture.
  ///
  /// ↩️Those renders took the warm path's road, and it was nine tenths of a
  /// video export (F-289, measured 2026-10-07 on the Windows app, profile
  /// build, a cut of two rows at 2340×1654): 395 tiles a frame, each
  /// waiting a decode round of 1.3–2.9 ms on a busy machine, in a frame of
  /// 1.15 s — where the door makes a picture in a few hundredths of a
  /// millisecond. Giving way between tiles buys such a render nothing: no
  /// one can stand it down, and the one waiting for it waits longer.
  madeAtOnce,
}

/// How long [MissingTilePictures.madeInTurn] makes tile pictures before it
/// gives way: the bound the decode rounds kept — 「an interactive input
/// stops an opportunistic compose within ~one tile (1–2ms)」 (R13-4).
///
/// ⛔A LENGTH OF TIME, NOT A COUNT OF PICTURES. A count is a different
/// length on every machine — 0.04 ms a picture on the desk it was measured
/// on (debug build), several times that on an old tablet — and the turn it
/// buys is not free: 🔬0.5–0.7 ms each on the Windows app (2026-10-07), so
/// sixteen pictures a run spent as long giving way as making them. Most
/// cels never reach the end of a run: the raster after a layer's tiles is a
/// turn of its own.
@visibleForTesting
const Duration tilePictureRun = Duration(milliseconds: 2);

/// A test's clock for [tilePictureRun], in microseconds — the time a run
/// has taken is read off the wall when this is null.
@visibleForTesting
int Function()? debugTilePictureClock;

/// One turn of the event queue: whatever was waiting in it when this is
/// called — a pen coming down, a frame — is handled before it completes.
///
/// A message to this isolate's own port: it joins the queue behind what is
/// already there and is answered in its turn.
///
/// 🚨★★★NOT A TIMER, though a zero `Timer` is the same turn. A compose is
/// nobody's to cancel — it belongs to no widget and no scheduler — so a
/// timer it left pending outlives whatever asked for the picture, and a
/// widget test that ends with one pending fails on the binding's timer
/// invariant (the reason `PlaybackPrerenderScheduler` keeps every wait of
/// its own in a list it can flush). ⛔Not an engine call that happens to
/// answer later either: `ImmutableBuffer.fromUint8List` answers inside the
/// call, and a wait for it is a wait for microtasks — the pen is not let in.
Future<void> _giveWay() {
  final turn = Completer<void>();
  final port = RawReceivePort();
  port.handler = (Object? _) {
    port.close();
    turn.complete();
  };
  port.sendPort.send(null);
  return turn.future;
}

/// Composes a tiled [BitmapSurface] into one full-resolution [ui.Image] by
/// drawing per-tile GPU images — the editing canvas's display route, reused
/// for playback/preview rendering.
///
/// Tiles already pictured in [reuse] (typically [BitmapTileImageCache.instance],
/// which the editing canvas keeps warm for the frame on screen) are drawn
/// as-is, so rebuilding the ACTIVE frame after a stroke uploads nothing:
/// cost scales with the changed tiles, not the canvas. Missing tiles are
/// pictured transiently ([missing] says how) and disposed right after the
/// compose — cold frames pay one upload per stored tile without pinning GPU
/// copies of every frame's artwork.
///
/// Byte-parity with the CPU assembly path ([bitmapSurfaceToImage]): tile
/// bytes premultiply through the SAME mul-div-255 rounding
/// ([BitmapTileImageCache.premultipliedTileUpload]) and are drawn 1:1 at
/// integer offsets with [ui.FilterQuality.none] over a transparent base, so
/// srcOver passes the premultiplied bytes through unchanged.
///
/// The caller owns (and must dispose) the returned image.
///
/// [shouldAbort] (R13-4, abandonable work only): checked before every
/// tile picture and before the final full-canvas raster — the two cost
/// centers — so an interactive input stops an opportunistic compose within
/// one run of tile pictures ([tilePictureRun]), not one canvas. Aborts
/// return null with nothing cached and the transient pictures disposed;
/// without [shouldAbort] the result is never null.
Future<ui.Image?> composeTiledSurfaceImage(
  BitmapSurface surface, {
  BitmapTileImageCache? reuse,
  bool Function()? shouldAbort,
  MissingTilePictures missing = MissingTilePictures.madeInTurn,
}) => _composeAsync(
  surface,
  reuse: reuse,
  shouldAbort: shouldAbort,
  missing: missing,
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
  required MissingTilePictures missing,
  required ui.Rect over,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.translate(-over.left, -over.top);
  final paint = ui.Paint()..filterQuality = ui.FilterQuality.none;
  final transient = <ui.Image>[];
  var recorderClosed = false;
  final watch = Stopwatch()..start();
  int now() => debugTilePictureClock?.call() ?? watch.elapsedMicroseconds;
  var runBegan = now();

  try {
    for (final entry in _tilesShownBy(surface).entries) {
      final tile = entry.value;
      var image = reuse?.imageFor(tile);
      if (image == null) {
        if (missing == MissingTilePictures.madeInTurn &&
            now() - runBegan >= tilePictureRun.inMicroseconds) {
          await _giveWay();
          runBegan = now();
        }
        if (shouldAbort?.call() ?? false) {
          recorder.endRecording().dispose();
          recorderClosed = true;
          return null;
        }
        image = BitmapTileImageCache.pictureOfTile(tile);
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

  for (final entry in _tilesShownBy(surface).entries) {
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
  MissingTilePictures missing = MissingTilePictures.madeInTurn,
  ui.Rect? over,
}) async {
  final worldRect = _composedOver(surface, over);
  final image = await _composeAsync(
    surface,
    reuse: reuse,
    shouldAbort: shouldAbort,
    missing: missing,
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
    final tiles = tileCoordsWorldRect(
      _tilesShownBy(surface).keys,
      surface.tileSize,
    );
    return tiles == null || over.expandToInclude(tiles) == over;
  }(), 'a part of the content composed on its own must hold every tile');
  return over;
}
