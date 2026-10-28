import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../models/bitmap_surface.dart';
import '../../models/bitmap_tile.dart';
import '../../models/dirty_region.dart';
import '../../models/pasteboard_bounds.dart';
import '../../models/tile_coord.dart';
import '../../models/tiles_covering.dart';
import '../../core/dev_profile.dart';
import '../../native/qa_native_engine.dart';
import '../../services/bitmap_surface_geometry.dart'
    show bitmapSurfaceContentBounds;
import '../../services/cel_text_laying.dart';
import '../../services/import/cel_picture.dart'
    show pictureSideLimit, pictureSideLimitIfMeasured;
import '../../services/straight_rgba_image.dart' show uploadRawRgba;
import 'bitmap_tile_image_cache.dart';
import 'chained_picture.dart';
import 'image_pieces.dart';
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

/// [rect] as the pieces an asynchronous compose makes it in ([piecesOver]).
Future<List<ui.Rect>> _piecesOf(ui.Rect rect) async => piecesOver(
  rect,
  side: pictureSideLimitIfMeasured ?? await pictureSideLimit(),
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
/// where every pixel of the composed image that is not transparent sits:
/// the tiles' rect, which the content holds.
///
/// ↩️It was pushed out to multiples of 4 counted from the content's
/// origin (the deepest playback level), so that at every level of the
/// display's pyramid its edges fell on whole texels of the whole content's
/// level — until no picture was halved (one-picture-per-frame ②-5b-3).
ui.Rect surfaceInkWorldRect(BitmapSurface surface) =>
    tileCoordsWorldRect(_tilesShownBy(surface).keys, surface.tileSize) ??
    surfaceContentWorldRect(surface);

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
/// ([_composedFromBytes]) — a test's count.
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
/// Byte-parity with the tiles' own bytes where they stand: tile bytes
/// premultiply through the app's one mul-div-255 rounding
/// ([SurfaceRegionBytes]) and are drawn 1:1 at integer offsets with
/// [ui.FilterQuality.none] over a transparent base, so srcOver passes the
/// premultiplied bytes through unchanged. ↩️Pinned against the CPU
/// assembly until it left the app (card `cpu-assembly-has-no-caller`).
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
);

/// How a compose lays each tile on its recording over the canvas-space rect
/// [over]: 1:1 at its integer offset.
///
/// ↩️Or halved at its place through the one halving law, the first level of
/// the surface made from the tiles themselves — until no picture was made
/// at a level (one-picture-per-frame ②-5b-1).
class _TileLaying {
  _TileLaying(this.canvas, this.over) {
    canvas.translate(-over.left, -over.top);
  }

  final ui.Canvas canvas;
  final ui.Rect over;
  final ui.Paint _paint = ui.Paint()..filterQuality = ui.FilterQuality.none;

  /// Lays [picture] with its top-left at the canvas-space [origin] — a
  /// tile's ([tileOriginOffset]) or a block's.
  void lay(ui.Offset origin, ui.Image picture) =>
      canvas.drawImage(picture, origin, _paint);

  int get width => over.width.round();
  int get height => over.height.round();
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
/// The recording is rastered as its plain snapshot, waited for — what a
/// holder keeps. ↩️Or deferred on the GPU, a step of a chain whose last
/// step was the snapshot, until no picture was made at a level
/// (one-picture-per-frame ②-5b-1).
Future<ui.Image?> _composeAsync(
  BitmapSurface surface, {
  required BitmapTileImageCache? reuse,
  required bool Function()? shouldAbort,
  required MissingTilePictures missing,
  required ui.Rect over,
}) async {
  final recorder = ui.PictureRecorder();
  final laying = _TileLaying(ui.Canvas(recorder), over);
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

    final picture = recorder.endRecording();
    recorderClosed = true;
    try {
      if (shouldAbort?.call() ?? false) {
        return null;
      }
      return await waitedSnapshot(picture, laying.width, laying.height);
    } finally {
      picture.dispose();
    }
  } finally {
    if (!recorderClosed) {
      recorder.endRecording().dispose();
    }
    // After the snapshot has landed: only the handles go here.
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

/// [surface]'s picture NOW, canvas-sized: every tile's own picture, made
/// here if it has none — the sheets' display image, which shows a surface
/// the moment it is the surface (a stroke's pen-up, an undo, a redo). Byte
/// parity with [composeTiledSurfaceImage]: the same tile pictures, the same
/// 1:1 integer-offset draws, rastered deferred on the GPU. The caller owns
/// the returned image.
///
/// 🚨★★★A TILE THAT HAS NO PICTURE GETS ONE MADE NOW, through the one door
/// ([BitmapTileImageCache.pictureFor]) — so the compose cannot miss, and a
/// surface shown a frame ago shows on THIS frame too: 유저 절대규칙 「보이는
/// 중이랑 결과랑 절대로 다르면 안 되」. ↩️The layer stack's row images were made
/// so as well — now for a cel on screen a frame ago, asynchronously for one
/// that was not — until no screen drew a row's image (one-picture-per-frame
/// ②-5b-1).
ui.Image composeTiledSurfaceImageNow(
  BitmapSurface surface, {
  required BitmapTileImageCache reuse,
}) {
  return labProbe(
    'composeSync(${surface.tiles.length}t '
    '${surface.canvasSize.width}x${surface.canvasSize.height})',
    () {
      final over = surface.canvasSize.canvasRect;
      final recorder = ui.PictureRecorder();
      final laying = _TileLaying(ui.Canvas(recorder), over);
      final tileSize = surface.tileSize;
      for (final entry in _tilesShownBy(surface).entries) {
        final tile = entry.value;
        final origin = tileOriginOffset((coord: entry.key, tile: tile));
        if (!(origin & ui.Size.square(tileSize.toDouble())).overlaps(over)) {
          // A pasteboard tile: nothing of it lands on the canvas.
          continue;
        }
        laying.lay(origin, reuse.pictureFor(tile));
      }
      return rasterPicture(recorder, laying.width, laying.height);
    },
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
/// the wall where they straddle it, and so does their ink rect
/// ([surfaceInkWorldRect]) — nothing lies there, and such a
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
/// past the wall is made from.
_BytesFill _bytesShownOver(BitmapSurface surface, ui.Rect over) => _BytesFill(
  SurfaceRegionBytes(_shownBy(surface), DirtyRegion.wholePixelsOf(over)),
);

/// How a compose from bytes writes each tile's part of [bytes]: as it is,
/// premultiplied where it lies.
///
/// ↩️Or halved at its place through the engine's measured halving — the
/// first level of a picture past the wall made from its bytes — until no
/// picture was made at a level (one-picture-per-frame ②-5b-1).
class _BytesFill {
  _BytesFill(this.bytes);

  final SurfaceRegionBytes bytes;

  int get width => bytes.width;
  int get height => bytes.height;
  int get byteLength => width * height * 4;

  /// The tiles whose parts [fill] writes, row by row.
  Iterable<CoveredTile> get tiles =>
      tilesCovering(bytes.surface, bytes.region);

  /// [tile]'s part premultiplied by [native] into [target] where it lies.
  void fill(QaNativeEngine native, CoveredTile tile, Pointer<Uint8> target) =>
      bytes.premultiplyInto(native, tile, target);

  /// Every part at once where there is no engine: the door's bytes in one
  /// read. Copied out, as they are the door's only while it reads them.
  Uint8List readAll() => bytes.readPremultiplied(Uint8List.fromList);
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
    calloc.free(target);
  }
}

/// [premultiplied] — [bytes]'s pixels — uploaded, unless [shouldAbort]
/// stands it down first; or [rastered] when the upload comes back another
/// size than [bytes] is.
///
/// Handed back as a render of the upload, which the engine gives its mip
/// chain ([chainedPictureOf]) — the picture every other compose hands back
/// is a render too: a camera's render draws a row reduced from its own
/// chain, and an upload carries none (one-picture-per-frame ②-5b-3).
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
    try {
      return chainedPictureOf(image);
    } finally {
      // Safe once drawn into the render: the draw holds its own claim.
      image.dispose();
    }
  }
  image.dispose();
  return rastered();
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
