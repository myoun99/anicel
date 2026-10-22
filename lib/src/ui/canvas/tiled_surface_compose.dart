import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../models/bitmap_surface.dart';
import '../../models/bitmap_tile.dart';
import '../../models/dirty_region.dart';
import '../../models/pasteboard_bounds.dart';
import '../../models/playback_quality.dart';
import '../../models/tile_coord.dart';
import '../../models/tiles_covering.dart';
import '../../core/dev_profile.dart';
import '../../core/sync_image_upload.dart';
import '../../native/qa_native_engine.dart';
import '../../services/bitmap_surface_geometry.dart'
    show bitmapSurfaceContentBounds;
import '../../services/cel_text_laying.dart';
import '../../services/import/cel_picture.dart'
    show pictureSideLimit, pictureSideLimitIfMeasured;
import '../../services/straight_rgba_image.dart' show uploadRawRgba;
import 'bitmap_tile_image_cache.dart';
import 'display_resample.dart';
import 'image_pieces.dart';
import 'level_image.dart';
import 'raster_picture.dart';
import 'surface_region_picture.dart';
import 'tile_blocks.dart';
import 'tile_origin.dart';

/// A composed surface image plus the CANVAS-SPACE rect it covers — in
/// [pieces], each with the rect it covers: ONE, over the whole rect, inside
/// the side this device's engine holds, and side by side past it
/// ([piecesOver] says why).
///
/// For a surface whose tiles all sit inside the canvas, [worldRect] is
/// exactly the canvas rect and the image is canvas-sized — byte-identical
/// to [composeTiledSurfaceImage]. Pasteboard content grows the rect (and
/// the image) only as far as the stored tiles reach, so layers without
/// off-canvas artwork pay nothing.
class PositionedSurfaceImage {
  const PositionedSurfaceImage({required this.pieces, required this.worldRect});

  final List<ImagePiece> pieces;
  final ui.Rect worldRect;
}

/// [rect] as the pieces a compose made inside a build makes it in
/// ([piecesOver]) — whole while the side this engine holds is still unread
/// (`pictureSideLimitIfMeasured`: it is read after the first frame), as
/// every compose was.
List<ui.Rect> _piecesNow(ui.Rect rect, {double texelsPerUnit = 1}) =>
    switch (pictureSideLimitIfMeasured) {
      final side? => piecesOver(rect, side: side, texelsPerUnit: texelsPerUnit),
      null => [rect],
    };

/// [rect] as the pieces an asynchronous compose makes it in ([piecesOver]).
Future<List<ui.Rect>> _piecesOf(
  ui.Rect rect, {
  double texelsPerUnit = 1,
}) async => piecesOver(
  rect,
  side: pictureSideLimitIfMeasured ?? await pictureSideLimit(),
  texelsPerUnit: texelsPerUnit,
);

/// Each of [rects] made into its image by [make], in turn, as [worldRect]'s
/// pieces — or null, the ones made let go, where one is not made.
Future<PositionedSurfaceImage?> _inPieces(
  ui.Rect worldRect,
  List<ui.Rect> rects,
  Future<ui.Image?> Function(ui.Rect piece) make,
) async {
  final pieces = <ImagePiece>[];
  for (final rect in rects) {
    final image = await make(rect);
    if (image == null) {
      pieces.disposeAll();
      return null;
    }
    pieces.add((image: image, worldRect: rect));
  }
  return PositionedSurfaceImage(pieces: pieces, worldRect: worldRect);
}

/// [_inPieces] made now: each of [rects] by [make], deferred, with — where
/// [make] snapshots — every piece's plain snapshot, in order, once all have
/// landed. Null, the ones made let go, where one is not made.
({PositionedSurfaceImage deferred, Future<List<ui.Image>>? real})?
_inPiecesNow(
  ui.Rect worldRect,
  List<ui.Rect> rects,
  ({ui.Image deferred, Future<ui.Image>? real})? Function(ui.Rect piece) make,
) {
  final made = <({ui.Image deferred, Future<ui.Image>? real})>[];
  for (final rect in rects) {
    final one = make(rect);
    if (one == null) {
      for (final each in made) {
        each.deferred.dispose();
        unawaited(each.real?.then((image) => image.dispose()));
      }
      return null;
    }
    made.add(one);
  }
  final reals = [for (final each in made) each.real];
  return (
    deferred: PositionedSurfaceImage(
      pieces: [
        for (var index = 0; index < rects.length; index += 1)
          (image: made[index].deferred, worldRect: rects[index]),
      ],
      worldRect: worldRect,
    ),
    real: reals.contains(null)
        ? null
        : Future.wait(
            [for (final real in reals) real!],
            cleanUp: (image) => image.dispose(),
          ),
  );
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
BitmapSurface _shownBy(BitmapSurface surface) =>
    celSurfaceWithTextsLaid(surface);

Map<TileCoord, BitmapTile> _tilesShownBy(BitmapSurface surface) =>
    _shownBy(surface).tiles;

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
/// none. Either way a picture is a block's ([tileBlocksOf]), comes through
/// the one door ([surfaceRegionPicture]), is the compose's own, and is let
/// go right after it; what differs is whether the compose gives way while
/// it makes them. Past the wall a compose makes no pictures: it
/// premultiplies its tiles' bytes ([_composedFromBytes]), and gives way
/// between runs of them the same way.
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
  /// where the door makes a picture in 0.04 ms. The two roads taken turn
  /// about in one run of the app, three times each: a cut of 40 pictures
  /// warmed in 0.51 s by rounds and 0.42 s by this road at full quality,
  /// 0.92 and 0.69 s at half, and for the first time off the file in 1.12
  /// and 0.72 s. With other work loading the machine — a round waits its
  /// turn on two busy threads, three times a tile — a cut of 35 pictures
  /// took 6.6 s by rounds and 1.9 s by this road at full, 9.2 and 2.8 s at
  /// half. What is left of a warm is its rasters.
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

/// How long [MissingTilePictures.madeInTurn] makes pictures before it gives
/// way: the bound the decode rounds kept — 「an interactive input stops an
/// opportunistic compose within ~one tile (1–2ms)」 (R13-4).
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

/// How many composes set out from their tiles' bytes
/// ([_composedFromBytes], [_composedFromBytesNow]) — a test's count.
@visibleForTesting
int debugComposesFromBytes = 0;

/// A test's hatch: a compose past the wall rastered as one inside it is,
/// for the pins that hold the two roads to the same picture.
@visibleForTesting
bool debugRastersPastTheWall = false;

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
/// cost scales with the changed tiles, not the canvas. A block with a tile
/// that has none is pictured transiently, whole ([tileBlocksOf], [missing]
/// says how), and disposed right after the compose — cold frames pay one
/// upload a block without pinning GPU copies of every frame's artwork.
///
/// Byte-parity with the CPU assembly path ([bitmapSurfaceToImage]): tile
/// bytes premultiply through the SAME mul-div-255 rounding
/// ([SurfaceRegionBytes]) and are drawn 1:1 at integer offsets with
/// [ui.FilterQuality.none] over a transparent base, so srcOver passes the
/// premultiplied bytes through unchanged.
///
/// The caller owns (and must dispose) the returned image.
///
/// [shouldAbort] (R13-4, abandonable work only): checked before every
/// block's picture and before the final full-canvas raster — the two cost
/// centers — so an interactive input stops an opportunistic compose within
/// one run of pictures ([tilePictureRun]), not one canvas. Aborts return
/// null with nothing cached and the transient pictures disposed; without
/// [shouldAbort] the result is never null.
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
  deferred: false,
);

/// How a compose lays each tile on its recording over the canvas-space rect
/// [over]: 1:1 at its integer offset, or — [halved] — halved at its place
/// through the one halving law ([drawHalvings]), the first level of the
/// surface made from the tiles themselves.
///
/// ⚠️A halved compose is exact only on the halving grid: [over]'s corners
/// even, as every tile's are, so each 2×2 block lies inside one tile.
class _TileLaying {
  _TileLaying(this.canvas, this.over, {required this.halved})
    : assert(
        !halved ||
            [over.left, over.top, over.width, over.height].every(
              (edge) => edge.round().isEven && edge == edge.roundToDouble(),
            ),
        'a halved compose lies on the halving grid (got $over)',
      ) {
    if (!halved) {
      canvas.translate(-over.left, -over.top);
    }
  }

  final ui.Canvas canvas;
  final ui.Rect over;
  final bool halved;
  final ui.Paint _paint = ui.Paint()..filterQuality = ui.FilterQuality.none;
  final List<LevelSource> _halvings = [];

  /// Lays [picture] with its top-left at the canvas-space [origin] — a
  /// tile's ([tileOriginOffset]) or a block's.
  void lay(ui.Offset origin, ui.Image picture) {
    if (halved) {
      _halvings.add((image: picture, at: (origin - over.topLeft) / 2));
    } else {
      canvas.drawImage(picture, origin, _paint);
    }
  }

  /// Draws what was laid for a halving, once every tile is in.
  void finish() {
    if (halved) {
      drawHalvings(canvas, _halvings);
    }
  }

  int get width => (over.width / (halved ? 2 : 1)).round();
  int get height => (over.height / (halved ? 2 : 1)).round();
}

/// THE tile compose, async: draw every tile at its place ([_TileLaying]) —
/// a block of them in one picture where a tile has none ([tileBlocksOf]) —
/// and raster the canvas-space rect [over] (the canvas, the content grown
/// by the pasteboard, or the part of it that holds the ink).
///
/// Four functions in this file used to carry this loop — canvas-size and
/// positioned, each async and sync — and they differed only in the origin,
/// the extent, and whether the raster awaits. Four copies of a recorder
/// lifetime is four chances to leak one.
///
/// [deferred] is how the recording is rastered: false waits for its plain
/// snapshot — what a holder keeps; true rasters it deferred on the GPU and
/// waits for nothing — a step of a chain whose LAST step is the snapshot
/// ([composePositionedSurfaceImage] says when).
Future<ui.Image?> _composeAsync(
  BitmapSurface surface, {
  required BitmapTileImageCache? reuse,
  required bool Function()? shouldAbort,
  required MissingTilePictures missing,
  required ui.Rect over,
  required bool deferred,
  bool halved = false,
}) async {
  final recorder = ui.PictureRecorder();
  final laying = _TileLaying(ui.Canvas(recorder), over, halved: halved);
  final transient = <ui.Image>[];
  var recorderClosed = false;
  final watch = Stopwatch()..start();
  int now() => debugTilePictureClock?.call() ?? watch.elapsedMicroseconds;
  var runBegan = now();

  try {
    final shown = _shownBy(surface);
    for (final block in _blocksOver(shown, over)) {
      if (_layHeldPictures(laying, block, reuse)) {
        continue;
      }
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
      final image = surfaceRegionPicture(shown, block.region);
      transient.add(image);
      laying.lay(
        ui.Offset(block.region.left.toDouble(), block.region.top.toDouble()),
        image,
      );
    }
    laying.finish();

    final picture = recorder.endRecording();
    recorderClosed = true;
    try {
      if (shouldAbort?.call() ?? false) {
        return null;
      }
      final width = laying.width;
      final height = laying.height;
      return deferred
          ? picture.toImageSync(width, height)
          : await waitedSnapshot(picture, width, height);
    } finally {
      picture.dispose();
    }
  } finally {
    if (!recorderClosed) {
      recorder.endRecording().dispose();
    }
    // After the snapshot has landed — or, for a deferred raster, at once:
    // the deferred image keeps the recording, and the recording keeps every
    // picture it drew (`raster_picture.dart`), so only the handles go here.
    for (final image in transient) {
      image.dispose();
    }
  }
}

/// Lays every tile of [block] from the picture [reuse] holds for it, and
/// answers true — or lays nothing and answers false when a tile has none,
/// and the block is pictured whole.
///
/// ⚠️WHOLE, the tiles that have a picture with the rest: a block's picture
/// is the surface's pixels over its region ([surfaceRegionPicture]), and a
/// tile drawn from both would be laid over itself — a translucent pixel
/// twice is not the pixel.
bool _layHeldPictures(
  _TileLaying laying,
  TileBlock block,
  BitmapTileImageCache? reuse,
) {
  if (reuse == null) {
    return false;
  }
  final held = <ui.Image>[];
  for (final placed in block.tiles) {
    final image = reuse.imageFor(placed.tile);
    if (image == null) {
      return false;
    }
    held.add(image);
  }
  for (var index = 0; index < held.length; index += 1) {
    laying.lay(tileOriginOffset(block.tiles[index]), held[index]);
  }
  return true;
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
  bool halved = false,
}) {
  final recorder = ui.PictureRecorder();
  final laying = _TileLaying(ui.Canvas(recorder), over, halved: halved);

  final tileSize = surface.tileSize;
  for (final entry in _tilesShownBy(surface).entries) {
    final tile = entry.value;
    final origin = tileOriginOffset((coord: entry.key, tile: tile));
    if (!(origin & ui.Size.square(tileSize.toDouble())).overlaps(over)) {
      // Another piece's ([piecesOver]): nothing of it lands on this one.
      continue;
    }
    final image = makePictures ? reuse.pictureFor(tile) : reuse.imageFor(tile);
    if (image == null) {
      recorder.endRecording().dispose();
      return null;
    }
    laying.lay(origin, image);
  }
  laying.finish();
  return rasterPictureAndSnapshot(
    recorder,
    laying.width,
    laying.height,
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
/// pixels that holds all of its ink — every tile ([surfaceInkWorldRect]),
/// or where a file's picture lies on a cel that holds nothing else
/// ([BitmapSurface.laidBounds], F-374-Q8). Each tile lands
/// texel for texel where it lands in the whole image, so what comes back is
/// that image's pixels over [over] — without the rest being drawn first.
///
/// A file's picture laid past the wall ([_laidPastTheWall]) is made from
/// its tiles' bytes ([_composedFromBytes]).
Future<PositionedSurfaceImage?> composePositionedSurfaceImage(
  BitmapSurface surface, {
  BitmapTileImageCache? reuse,
  bool Function()? shouldAbort,
  MissingTilePictures missing = MissingTilePictures.madeInTurn,
  ui.Rect? over,
}) async {
  final worldRect = _composedOver(surface, over);
  return _inPieces(worldRect, await _piecesOf(worldRect), (piece) {
    Future<ui.Image?> rastered() => _composeAsync(
      surface,
      reuse: reuse,
      shouldAbort: shouldAbort,
      missing: missing,
      over: piece,
      deferred: false,
    );
    return _madeFromBytes(surface)
        ? _composedFromBytes(
            _bytesShownOver(surface, piece),
            shouldAbort: shouldAbort,
            missing: missing,
            rastered: rastered,
          )
        : rastered();
  });
}

/// [shown]'s blocks that land on [over]: of a picture in pieces, another
/// piece's ([piecesOver]) land nothing on this one.
Iterable<TileBlock> _blocksOver(BitmapSurface shown, ui.Rect over) =>
    tileBlocksOf(shown).where(
      (block) =>
          block.region.left < over.right &&
          block.region.rightExclusive > over.left &&
          block.region.top < over.bottom &&
          block.region.bottomExclusive > over.top,
    );

/// Whether [surface] holds a file's picture laid whole past its wall
/// ([BitmapSurface.pasteboard]) — the one thing that lies there
/// ([BitmapSurface.laidBounds], F-374-Q8).
///
/// ⚠️NOT WHETHER A COMPOSE'S RECT REACHES PAST IT: a cel's tiles poke past
/// the wall where they straddle it, and so does its ink pushed out to the
/// halving grid ([surfaceInkWorldRect]) — nothing lies there, and such a
/// cel rasters as it always did. Read off the rect, a stroke near a small
/// picture's wall took the bytes road (a conte's cell,
/// `a_conte_stroke_keeps_to_the_cell_it_starts_in_test`).
bool _laidPastTheWall(BitmapSurface surface) {
  final laid = surface.laidBounds;
  if (laid == null) {
    return false;
  }
  final wall = surface.pasteboard.rect;
  return wall.expandToInclude(laid.rect) != wall;
}

/// Whether a compose of [surface] is made from its bytes: a file's picture
/// laid past the wall ([_laidPastTheWall]), but for the test's hatch.
bool _madeFromBytes(BitmapSurface surface) =>
    _laidPastTheWall(surface) && !debugRastersPastTheWall;

/// [surface]'s bytes over [over], as shown ([_shownBy]) — what a compose
/// past the wall is made from — halved through [halving] when it is given.
_BytesFill _bytesShownOver(
  BitmapSurface surface,
  ui.Rect over, {
  Uint8List? halving,
}) => _BytesFill(
  SurfaceRegionBytes(_shownBy(surface), DirtyRegion.wholePixelsOf(over)),
  halving: halving,
);

/// How a compose from bytes writes each tile's part of [bytes]: as it is,
/// or — given [halving], the engine's measured halving
/// ([measuredHalving]) — halved at its place, the first level made from the
/// bytes themselves as a halved raster makes it from the tiles' pictures
/// ([composeHalvedSurfaceImage]).
///
/// ⚠️A halved fill is exact only on the halving grid — the region's corners
/// even, as every tile's are — so each 2×2 block lies inside one tile's
/// part, as a halved raster's does ([_TileLaying]).
class _BytesFill {
  _BytesFill(this.bytes, {this.halving})
    : assert(
        halving == null ||
            [
              bytes.region.left,
              bytes.region.top,
              bytes.width,
              bytes.height,
            ].every((edge) => edge.isEven),
        'a halved fill lies on the halving grid (got ${bytes.region})',
      );

  final SurfaceRegionBytes bytes;
  final Uint8List? halving;

  int get width => halving == null ? bytes.width : bytes.width ~/ 2;
  int get height => halving == null ? bytes.height : bytes.height ~/ 2;
  int get byteLength => width * height * 4;

  /// The tiles whose parts [fill] writes, row by row.
  Iterable<CoveredTile> get tiles =>
      tilesCovering(bytes.surface, bytes.region);

  /// A tile's part premultiplied before it is halved — one tile big, made
  /// once a fill and let go by [dispose].
  Pointer<Uint8>? _part;

  /// [tile]'s part premultiplied by [native] into [target] where it lies —
  /// or, halved, where its half lies.
  void fill(QaNativeEngine native, CoveredTile tile, Pointer<Uint8> target) {
    final table = halving;
    if (table == null) {
      bytes.premultiplyInto(native, tile, target);
      return;
    }
    final part = SurfaceRegionBytes(
      bytes.surface,
      DirtyRegion(
        left: tile.left,
        top: tile.top,
        rightExclusive: tile.rightExclusive,
        bottomExclusive: tile.bottomExclusive,
      ),
    );
    final tileSize = bytes.surface.tileSize;
    final scratch = _part ??= calloc<Uint8>(tileSize * tileSize * 4);
    part.premultiplyInto(native, tile, scratch);
    halveRgbaWords(
      table,
      from: (
        rows: (
          words: scratch.cast<Uint32>().asTypedList(part.width * part.height),
          start: 0,
          stride: part.width,
        ),
        width: part.width,
        height: part.height,
      ),
      into: (
        words: target.cast<Uint32>().asTypedList(width * height),
        start:
            (tile.top - bytes.region.top) ~/ 2 * width +
            (tile.left - bytes.region.left) ~/ 2,
        stride: width,
      ),
    );
  }

  /// Every part at once where there is no engine: the door's bytes in one
  /// read, halved after through [halving] when it is given. Copied out, as
  /// they are the door's only while it reads them.
  Uint8List readAll() {
    final table = halving;
    if (table == null) {
      return bytes.readPremultiplied(Uint8List.fromList);
    }
    return bytes.readPremultiplied((whole) {
      final half = Uint8List(byteLength);
      halveRgbaWords(
        table,
        from: (
          rows: (
            words: whole.buffer.asUint32List(
              whole.offsetInBytes,
              whole.length ~/ 4,
            ),
            start: 0,
            stride: bytes.width,
          ),
          width: bytes.width,
          height: bytes.height,
        ),
        into: (words: half.buffer.asUint32List(), start: 0, stride: width),
      );
      return half;
    });
  }

  void dispose() {
    final part = _part;
    if (part != null) {
      calloc.free(part);
      _part = null;
    }
  }
}

/// The picture of [bytes] — the bytes the door reads — made from them, not
/// rastered: premultiplied into memory of this compose's own a tile at a
/// time — [missing] says whether it gives way between runs of them, as a
/// raster does — and uploaded off this thread ([uploadRawRgba]). Null when
/// [shouldAbort] stood it down.
///
/// ⚠️THE SECOND OF ITS KIND: [_composeAsync] paces its pictures the same
/// way — the same run, the same turn, the same ask before each. Not shared
/// under the rule of three (CLAUDE.md 절대명령 1).
///
/// 🚨★★★PAST THE WALL A CEL'S IMAGE IS ITS BYTES, NOT A RASTER (F-374-Q8
/// ⑦, 2026-10-18). Until a file's picture could be laid whole, the wall
/// bounded every compose; past it the picture is as big as its file, and
/// a raster of it held 9–15 times the image while it ran. 🔬Measured on
/// the Windows app (Surface Pro 11, profile build, a throwaway probe): an
/// A3 600dpi scan laid whole (7040×9984) rastered in 0.56–3.7 s at
/// +2.6–3.7 GB, and a raster past 16384 a side came back smaller without a
/// word (20480×1024 asked, 16384×819 made). Its bytes uploaded: +1.7 GB,
/// the raster thread free, and the SAME image — 0 bytes apart, and 0 apart
/// drawn small at `none`, `low`, `medium` and `high`: the decoder makes the
/// mip chain a snapshot makes. (The synchronous door makes none, and a
/// `medium` draw of its picture came out up to 125/255 apart.)
/// ⛔NOT INSIDE THE WALL: there the raster draws the pictures the canvas
/// keeps for its tiles, so a rebuild costs what changed (F-296) — an
/// upload would cost the whole cel every time.
///
/// An upload that comes back another size — past what this device's
/// decoder holds: 20000 wide came back 16384, its height kept — is let go,
/// and the picture [rastered] as it always was.
Future<ui.Image?> _composedFromBytes(
  _BytesFill bytes, {
  required bool Function()? shouldAbort,
  required MissingTilePictures missing,
  required Future<ui.Image?> Function() rastered,
}) async {
  debugComposesFromBytes += 1;
  final native = QaNativeEngine.instance;
  if (native == null) {
    // No engine — a load that failed: every build the app ships carries
    // one. The door's bytes in one read, not paced: what this road keeps
    // is the memory, one image where a raster held 9–15.
    return _uploadedOrRastered(bytes.readAll(), bytes, shouldAbort, rastered);
  }
  final byteLength = bytes.byteLength;
  final target = calloc<Uint8>(byteLength);
  try {
    final watch = Stopwatch()..start();
    int now() => debugTilePictureClock?.call() ?? watch.elapsedMicroseconds;
    var runBegan = now();
    for (final tile in bytes.tiles) {
      if (missing == MissingTilePictures.madeInTurn &&
          now() - runBegan >= tilePictureRun.inMicroseconds) {
        await _giveWay();
        runBegan = now();
      }
      if (shouldAbort?.call() ?? false) {
        return null;
      }
      bytes.fill(native, tile, target);
    }
    return await _uploadedOrRastered(
      target.asTypedList(byteLength),
      bytes,
      shouldAbort,
      rastered,
    );
  } finally {
    bytes.dispose();
    calloc.free(target);
  }
}

/// [premultiplied] — [bytes]'s pixels — uploaded, unless [shouldAbort]
/// stands it down first; or [rastered] when the upload comes back another
/// size than [bytes] is.
Future<ui.Image?> _uploadedOrRastered(
  Uint8List premultiplied,
  _BytesFill bytes,
  bool Function()? shouldAbort,
  Future<ui.Image?> Function() rastered,
) async {
  if (shouldAbort?.call() ?? false) {
    return null;
  }
  final image = await uploadRawRgba(
    premultiplied,
    width: bytes.width,
    height: bytes.height,
  );
  if (image.width == bytes.width && image.height == bytes.height) {
    return image;
  }
  image.dispose();
  return rastered();
}

/// The picture of [bytes] made from them inside the call —
/// [_composedFromBytes]'s synchronous twin, for a row that was on screen
/// and may not go blank (`_composeSync`): premultiplied into memory of its
/// own ([_BytesOfItsOwn]) and uploaded now ([wholePictureUploadedOrNull]).
/// Null where this engine has no upload of that kind (Skia), refuses this
/// one, or hands back another size — the caller rasters, as it always did.
///
/// 🚨★★★PAST THE WALL A ROW ON SCREEN IS MADE FROM ITS BYTES TOO (F-374-Q8
/// ⑦, 2026-10-18). 🔬Measured on the Windows app (Surface Pro 11, profile
/// build, a throwaway probe), an A3 600dpi scan laid whole (7040×9984,
/// 4290 tiles): the raster made in the call took 155 ms there and 772 ms
/// more to be shown, at +3.7 GB — and left 268 MB of tile pictures behind
/// it, one a tile; made from its bytes, 261 ms and 520 ms at +0.8 GB, with
/// no tile pictured, the same bytes.
/// ⚠️IT HAS NO MIP CHAIN — a raster's snapshot has one — and is KEPT as it
/// is: a cel's picture is drawn at `none` or `low` alone
/// ([filterQualityForDisplayScale]: the stack, the camera, a group's raster
/// — `medium` and `high` draw sheets and files' images, never a cel's), and
/// there the two are the same pixels. A cel's picture drawn at `medium`
/// would show the difference: make that one from [_composedFromBytes].
/// ⛔NOT ON THE FREE ROAD ([composePositionedSurfaceImageSync]'s
/// `makePictures` false): a picture this big is no free compose — its
/// bytes in the call, or a raster of every tile's picture at 9–15 times
/// the image — so a row that was not on screen arrives from the
/// asynchronous road, as such rows always have.
ui.Image? _composedFromBytesNow(_BytesFill bytes) {
  debugComposesFromBytes += 1;
  try {
    final image = wholePictureUploadedOrNull(_BytesOfItsOwn(bytes));
    if (image == null ||
        image.width == bytes.width && image.height == bytes.height) {
      return image;
    }
    image.dispose();
    return null;
  } finally {
    bytes.dispose();
  }
}

/// A compose made now ([_composeSync]'s answer) past the wall
/// ([_madeFromBytes]): nothing on the free road ([makePictures] false —
/// [_composedFromBytesNow] says why), the picture made from [bytes] — a
/// plain picture already, and [snapshot]'s a handle of its own on it — or,
/// where [bytes] is null or the upload is refused, [rastered]. Inside the
/// wall it is [rastered].
({ui.Image deferred, Future<ui.Image>? real})? _madeNow(
  BitmapSurface surface, {
  required bool makePictures,
  required bool snapshot,
  required _BytesFill? Function() bytes,
  required ({ui.Image deferred, Future<ui.Image>? real})? Function() rastered,
}) {
  if (!_madeFromBytes(surface)) {
    return rastered();
  }
  if (!makePictures) {
    return null;
  }
  final fill = bytes();
  final now = fill == null ? null : _composedFromBytesNow(fill);
  if (now == null) {
    return rastered();
  }
  return (deferred: now, real: snapshot ? Future.value(now.clone()) : null);
}

/// [bytes] premultiplied into memory of this read's own where the engine
/// premultiplies them — not into its scratch ([SurfaceRegionBytes]'s),
/// which grows to the biggest picture it ever held and keeps that much.
class _BytesOfItsOwn implements PictureBytes {
  _BytesOfItsOwn(this.bytes);

  final _BytesFill bytes;

  @override
  int get width => bytes.width;

  @override
  int get height => bytes.height;

  /// ⛔Not of a halved fill: a halving is of premultiplied texels, and
  /// straight bytes made back from it are not the picture's. Nothing asks —
  /// the upload made now reads premultiplied bytes alone
  /// ([wholePictureUploadedOrNull]).
  @override
  T readStraight<T>(T Function(Uint8List straight) use) {
    if (bytes.halving != null) {
      throw UnsupportedError('a halving has no straight bytes');
    }
    return bytes.bytes.readStraight(use);
  }

  @override
  T readPremultiplied<T>(T Function(Uint8List premultiplied) use) {
    final native = QaNativeEngine.instance;
    if (native == null) {
      return use(bytes.readAll());
    }
    final byteLength = bytes.byteLength;
    final target = calloc<Uint8>(byteLength);
    try {
      for (final tile in bytes.tiles) {
        bytes.fill(native, tile, target);
      }
      return use(target.asTypedList(byteLength));
    } finally {
      calloc.free(target);
    }
  }
}

/// The synchronous positioned compose — the layer stack's, for the frame a
/// row changes route or content ([_composeSync] says what [makePictures]
/// and [snapshot] mean; [over] is the async twin's). Null when
/// [makePictures] is false and a tile has no picture — and, for a file's
/// picture laid past the wall ([_laidPastTheWall]), whenever it is false.
///
/// Such a picture is made from its tiles' bytes
/// ([_composedFromBytesNow]): no recording is rastered, so what comes back
/// as "deferred" is a plain picture already, and [snapshot]'s is a handle
/// of its own on the same picture — the holder's swap retires the handle it
/// replaces, and nothing else was pinned.
({PositionedSurfaceImage deferred, Future<List<ui.Image>>? real})?
composePositionedSurfaceImageSync(
  BitmapSurface surface, {
  required BitmapTileImageCache reuse,
  required bool makePictures,
  required bool snapshot,
  ui.Rect? over,
}) {
  final worldRect = _composedOver(surface, over);
  return _inPiecesNow(
    worldRect,
    _piecesNow(worldRect),
    (piece) => _madeNow(
      surface,
      makePictures: makePictures,
      snapshot: snapshot,
      bytes: () => _bytesShownOver(surface, piece),
      rastered: () => _composeSync(
        surface,
        reuse: reuse,
        makePictures: makePictures,
        snapshot: snapshot,
        over: piece,
      ),
    ),
  );
}

/// The FIRST LEVEL of [surface] over [over] — every tile halved at its
/// place through the one halving law ([drawHalvings]) — so a level of the
/// display's pyramid begins at half size instead of as the whole image at
/// full size, halved after ([LayerFrameImageCache] says what follows).
///
/// The same bytes the full-size image halved holds, wherever [over] lies on
/// the halving grid (corners even, as every tile's are): each 2×2 block is
/// inside one tile, and halving it there or in the whole image is the same
/// mean of the same four texels.
///
/// [deferred] hands back the recording rastered DEFERRED, with nothing
/// waited for — for a caller that draws it into the next step of a chain
/// and keeps only the chain's last step, a plain snapshot. ⛔Never an image
/// to keep: a deferred image pins every tile picture it drew for as long as
/// it lives (`raster_picture.dart`).
///
/// The tiles' pictures are the shared ones the canvas keeps
/// ([BitmapTileImageCache.instance]); a block with a tile that lacks one is
/// pictured whole, in turn ([MissingTilePictures.madeInTurn]) — a level is
/// made off the frame, by the warm or for a row the canvas fills in.
///
/// 🚨★★★PAST THE WALL IT IS MADE FROM THE BYTES, HALVED BY THE ENGINE'S OWN
/// TABLE ([measuredHalving]; board a-big-reference-picture-still-costs-
/// when-zoomed-out, 🗣️유저 2026-10-18 「엔진과 같은 바이트를 내는 CPU 반감을
/// 찾는다」). A full-size picture past the wall is its bytes
/// ([_composedFromBytes]); its first level was still a raster of every
/// tile's picture — the cost the bytes road had taken away, at a quarter of
/// the pixels. Halved on the CPU through the table the engine's own
/// halving gave, it is the raster's picture byte for byte; an engine whose
/// halving is not the sum's has no table, and its level is rastered as it
/// always was. 🔬Measured on the Windows app (Surface Pro 11, profile
/// build, 2026-10-21, a throwaway probe), an A3 600dpi scan laid whole
/// (7040×9984), its level 3520×4992: from its bytes 0.45–1.04 s at +170 MB
/// (peak 0.8 GB), rastered 0.67–2.2 s at +1.0–1.5 GB (peak 2.4–2.6 GB), 0
/// bytes apart; made now 0.31–0.34 s in the call, the raster 0.43–0.50 s.
/// (Read back with `toByteData` the instant it is made, the picture made
/// now is not there yet — 「Image was null」, as the full-size one made now
/// — and drawn, or a frame on, it is the raster's.)
Future<PositionedSurfaceImage?> composeHalvedSurfaceImage(
  BitmapSurface surface, {
  bool Function()? shouldAbort,
  required ui.Rect over,
  bool deferred = false,
}) async {
  final halvedOver = _composedOver(surface, over);
  final halving = _madeFromBytes(surface) ? await measuredHalving() : null;
  return _inPieces(
    halvedOver,
    await _piecesOf(halvedOver, texelsPerUnit: 0.5),
    (piece) {
      Future<ui.Image?> rastered() => _composeAsync(
        surface,
        reuse: BitmapTileImageCache.instance,
        shouldAbort: shouldAbort,
        missing: MissingTilePictures.madeInTurn,
        over: piece,
        deferred: deferred,
        halved: true,
      );
      return halving == null
          ? rastered()
          : _composedFromBytes(
              _bytesShownOver(surface, piece, halving: halving),
              shouldAbort: shouldAbort,
              missing: MissingTilePictures.madeInTurn,
              rastered: rastered,
            );
    },
  );
}

/// [composeHalvedSurfaceImage] made now — [_composeSync] says what
/// [makePictures] and [snapshot] mean, and [_madeNow] what is made past the
/// wall: from the bytes once the engine's halving has been read
/// ([measuredHalvingIfRead]), rastered before.
({PositionedSurfaceImage deferred, Future<List<ui.Image>>? real})?
composeHalvedSurfaceImageSync(
  BitmapSurface surface, {
  required bool makePictures,
  required bool snapshot,
  required ui.Rect over,
}) {
  final halvedOver = _composedOver(surface, over);
  return _inPiecesNow(
    halvedOver,
    _piecesNow(halvedOver, texelsPerUnit: 0.5),
    (piece) => _madeNow(
      surface,
      makePictures: makePictures,
      snapshot: snapshot,
      bytes: () => switch (measuredHalvingIfRead) {
        final halving? => _bytesShownOver(surface, piece, halving: halving),
        null => null,
      },
      rastered: () => _composeSync(
        surface,
        reuse: BitmapTileImageCache.instance,
        makePictures: makePictures,
        snapshot: snapshot,
        over: piece,
        halved: true,
      ),
    ),
  );
}

/// The rect a positioned compose rasters: [over], or the whole content.
ui.Rect _composedOver(BitmapSurface surface, ui.Rect? over) {
  if (over == null) {
    return surfaceContentWorldRect(surface);
  }
  assert(() {
    final shown = _shownBy(surface);
    final tiles = tileCoordsWorldRect(shown.tiles.keys, surface.tileSize);
    if (tiles == null || over.expandToInclude(tiles) == over) {
      return true;
    }
    // Past a tile's edge only its ink counts: a file's picture composed
    // over where it lies (`_celMoved`, F-374-Q8) cuts through the clear
    // pixels its edge tiles hold.
    final ink = bitmapSurfaceContentBounds(shown);
    return ink == null ||
        ink.left >= over.left &&
            ink.top >= over.top &&
            ink.rightExclusive <= over.right &&
            ink.bottomExclusive <= over.bottom;
  }(), 'a part of the content composed on its own must hold all of its ink');
  return over;
}
