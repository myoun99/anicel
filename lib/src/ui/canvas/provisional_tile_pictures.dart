import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../../models/bitmap_surface.dart';
import '../../models/pasteboard_bounds.dart';
import '../../models/placed_tile.dart';
import '../../models/tile_coord.dart';
import 'bitmap_tile_image_cache.dart';
import 'raster_picture.dart';
import 'tile_origin.dart';
import 'tile_predecessors.dart';
import 'tiles_under_rect.dart';

/// Draws, in CANVAS coordinates, the picture the screen is ALREADY showing
/// over [region] — the float being dragged, the decoded resample, a fill's
/// stamp.
///
/// Returns false when it cannot draw all of what belongs there. A piece
/// missing from a composed tile is a hole in the artwork, which is worse
/// than the answer that coordinate has today, so the caller leaves it
/// alone rather than seeding half a picture. (The one ink that draws a
/// PART of the picture, [inkFromWindow], vouches for a region only where
/// the part is everything on screen.)
typedef ProvisionalInkPainter = bool Function(ui.Canvas canvas, Rect region);

final Paint _tilePaint = Paint()
  ..filterQuality = FilterQuality.none
  ..isAntiAlias = false;

/// Gives the tiles a commit just created a picture they can draw on the
/// VERY NEXT frame, composed from pictures already on the GPU.
///
/// A committed tile is a new object with no decoded image, and for the
/// frame or two before its decode lands the painter answers for it with
/// the previous generation's picture at that coordinate (the artwork that
/// was there before the edit) or, past its four-tile per-pixel budget,
/// with nothing. Both are the stale-tile family. This composes the answer
/// instead: `srcOver(what was here, what the user was looking at)`,
/// rasterized synchronously with `Picture.toImageSync` — 26-38 us for a
/// 256 px tile, and no engine feature beyond what Skia already does.
///
/// The result is PROVISIONAL, never adopted. The commit kernel blends in
/// straight alpha and premultiplies once; this composition premultiplies
/// both operands and blends in premultiplied space, and the two 8-bit
/// rounding orders disagree by up to TWO channel steps, at middling alpha
/// on both operands (`tile_image_sync_compose_parity_test` sweeps it —
/// and note that an earlier, coarser sweep said one step and blamed the
/// faintest ink, so trust the test rather than this sentence). A frame
/// off by two along the FIDELITY axis is what this program's invariant
/// says to trade; coverage is the axis it says never to trade.
///
/// ⚠️ Composition, not upload. Every operand has to be a `ui.Image`
/// already, which is why this is called where the picture lives — the
/// selection layer's float and decoded resample — rather than at the
/// commit funnel, which holds only bytes. Turning bytes into an image
/// synchronously is `decodeImageFromPixelsSync`, which is Impeller only —
/// and since Flutter 3.47 made Impeller the desktop default (this repo
/// moved 2026-09-16) that route exists on every platform we ship. It is
/// still asked rather than assumed: see [syncImageUploadSupported].
///
/// ⚠️ PRECONDITION: the INK owns the operator, and it must be the one the
/// commit composites with — nothing here can check it. This draws the base
/// and hands the canvas over; what the ink paints on top is the whole
/// claim. A lift/move LANDING commits a stamp dab at the default
/// [BrushBlendMode.color], which is `srcOver` (`brush_blend_mode.dart`),
/// and its inks ([inkFromImage], [inkFromWindow], the float) draw srcOver.
/// A `behind`, or any separable brush blend, would need an ink of its own:
/// drawn as srcOver it would publish a picture the commit never wrote.
///
/// 🪦A LIFT's erase had an ink here too (`inkCutByMask`, destination-out
/// from the mask's own bytes) until 2026-09-11, when the commit funnel
/// began announcing both surfaces and the painter composed the erased
/// tiles from their predecessors — the lift needs no ink of its own.
///
/// Returns what it did: coordinates it could not answer for keep today's
/// behaviour, and the count is how a caller (or a test) sees that without
/// guessing.
({int seeded, int adopted, int skipped}) seedProvisionalTilePictures({
  required BitmapSurface preSurface,
  required BitmapSurface postSurface,
  required Iterable<TileCoord> coords,
  required ProvisionalInkPainter ink,
  Object? staleScope,
  BitmapTileImageCache? cache,
}) {
  final images = cache ?? BitmapTileImageCache.instance;
  final tileSize = postSurface.tileSize;
  final tileExtent = tileSize.toDouble();
  // The commit clips at the pasteboard wall, so the composition has to as
  // well — ink past the edge would show for a frame and then vanish when
  // the real decode landed without it.
  final canvasSize = postSurface.canvasSize;
  final pasteboard = canvasSize.pasteboardRect;
  var seeded = 0;
  var adopted = 0;
  var skipped = 0;
  for (final coord in coords) {
    final tile = postSurface.tileAt(coord);
    if (tile == null || images.displayImageFor(tile) != null) {
      // Nothing there, or it can already draw itself.
      skipped += 1;
      continue;
    }
    // N4 ⑤: where the engine uploads bytes synchronously, the tile's OWN
    // bytes are right here and they are EXACT. Composing an approximation
    // of a picture we can simply have would be strictly worse, and it
    // would leave a provisional lifecycle running for nothing.
    if (images.adoptSyncUpload(
          (coord: coord, tile: tile),
          staleScope: staleScope,
        ) !=
        null) {
      adopted += 1;
      continue;
    }
    final preTile = preSurface.tileAt(coord);
    if (identical(preTile, tile)) {
      // Structural sharing hands back the SAME object for a coordinate
      // the commit did not touch. Nothing changed here, so there is
      // nothing to stand in for — and composing ink onto it would be
      // inventing a change the commit did not make.
      skipped += 1;
      continue;
    }
    ui.Image? preImage;
    if (preTile != null) {
      // `displayImageFor`: what the SCREEN held is the honest base to
      // compose on, and it keeps a second commit inside one decode round
      // from falling back to nothing. The chain cannot run away — a
      // stand-in never blocks its tile's own decode, so every generation
      // is being replaced by truth while the next one composes.
      //
      // ⚠️THAT REPLACEMENT IS THE ONLY THING THAT SHORTENS IT. This is the
      // same shape as the display buffer's chain (2026-09-13, `rasterPicture`
      // has the engine fact): the stand-in is a deferred image and holds
      // `preImage` for its whole life, so until the real decode lands and
      // retires it, every generation behind it stays resident — 64KB a
      // link, one chain per tile. Bounded by decode latency, not by a
      // budget; a decode that never landed would be the leak.
      preImage = images.displayImageFor(preTile);
      if (preImage == null && preTile.hasInk) {
        // Pixels were here and we have no picture of them: composing now
        // would publish a tile with the base missing.
        skipped += 1;
        continue;
      }
    }

    final origin = tileOriginOffset((coord: coord, tile: tile));
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(
      recorder,
      Rect.fromLTWH(0, 0, tileExtent, tileExtent),
    );
    if (preImage != null) {
      canvas.drawImage(preImage, Offset.zero, _tilePaint);
    }
    canvas.save();
    canvas.translate(-origin.dx, -origin.dy);
    canvas.clipRect(pasteboard);
    final complete = ink(canvas, origin & Size.square(tileExtent));
    canvas.restore();
    if (!complete) {
      recorder.endRecording().dispose();
      skipped += 1;
      continue;
    }
    // The raster and its `finally` are [rasterPicture]'s: the refusal arm
    // above disposes, the raster arm disposes inside the helper, and the two
    // agree by structure instead of by remembering.
    final image = rasterPicture(recorder, tileSize, tileSize);
    images.putProvisional((coord: coord, tile: tile), image);
    seeded += 1;
  }
  return (seeded: seeded, adopted: adopted, skipped: skipped);
}

/// Ink that is ONE image already sitting at [placement] in canvas space —
/// a decoded resample, a fill's stamp.
ProvisionalInkPainter inkFromImage(ui.Image image, Rect placement) {
  final source = Rect.fromLTWH(
    0,
    0,
    image.width.toDouble(),
    image.height.toDouble(),
  );
  return (canvas, region) {
    canvas.drawImageRect(image, source, placement, _tilePaint);
    return true;
  };
}

/// Ink that is the on-screen WINDOW of a picture, sitting at [placement]
/// in canvas space — the resample a confirm in the middle of a handle drag
/// finds decoded, which holds only the viewport's part of the landing
/// (ABI 26).
///
/// Complete for what is on screen, and it says so only there: the window
/// was cut at the visible rect, so every visible pixel of a region it
/// touches is in it, and what such a region lacks is off screen until its
/// own decode lands a frame or two later. A region it does not touch is
/// refused — nothing there is visible, and a picture composed there would
/// be the pre-landing one under a tile the landing changed.
ProvisionalInkPainter inkFromWindow(ui.Image image, Rect placement) {
  final whole = inkFromImage(image, placement);
  return (canvas, region) =>
      region.overlaps(placement) && whole(canvas, region);
}

/// Ink that is a TILED surface drawn [canvasDelta] away from where its
/// pixels were materialized — the selection float, which is built once and
/// then translated rather than rebuilt (a rebuild is new tile objects with
/// no pictures, which is the thing this exists to avoid).
///
/// Answers false for a region a float tile covers without a picture of its
/// own: the composition would be missing exactly the artwork it is there
/// to carry.
///
/// ⚠️ And false for a region that falls outside the float's OWN pasteboard,
/// which is a different wall from the landing's. The float was
/// materialized through the same clipping stamp kernel, at
/// `_floatSurfaceCentre` — so a selection dragged off-stage and then
/// picked up again lost that band from the float permanently, while the
/// commit writes it at the LANDED position. There, an absent float tile
/// does not mean "nothing belongs here", it means "the wall ate it", and
/// the two are indistinguishable once you are only looking at tiles.
/// Answering true would publish a stand-in with that band of the landing
/// missing AND take those coordinates out of the hold, since a successful
/// compose is what makes the base look paintable.
ProvisionalInkPainter inkFromSurface(
  BitmapSurface surface,
  Offset canvasDelta, {
  BitmapTileImageCache? cache,
}) {
  final images = cache ?? BitmapTileImageCache.instance;
  final floatCanvas = surface.canvasSize;
  final floatPasteboard = floatCanvas.pasteboardRect;
  return (canvas, region) {
    // The region read in the float's OWN coordinates.
    final local = region.shift(-canvasDelta);
    if (local.left < floatPasteboard.left ||
        local.top < floatPasteboard.top ||
        local.right > floatPasteboard.right ||
        local.bottom > floatPasteboard.bottom) {
      return false;
    }
    for (final under in tilesUnderRect(surface, local)) {
      final tile = under.tile;
      final image = images.displayImageFor(tile);
      if (image == null) {
        // A tile with no picture and no pixels covers nothing, so its
        // absence costs nothing; one with pixels is the answer going
        // missing.
        if (!tile.hasInk) {
          continue;
        }
        return false;
      }
      canvas.drawImage(
        image,
        tileOriginOffset((coord: under.coord, tile: tile)) + canvasDelta,
        _tilePaint,
      );
    }
    return true;
  };
}

/// 🚨★★★THE TRUTHFUL STAND-IN: the predecessor's picture plus the byte
/// difference (F-68 root fix, 2026-09-11).
///
/// A tile that has no picture yet is drawn, until its decode lands, from
/// something else — and what that something else IS was the whole family
/// of one-frame ghosts. The coordinate fallback drew the last picture
/// DECODED at the coordinate, a previous generation picked by timing:
/// right when the edit added ink, wrong when it removed any. This draws
/// the tile the commit replaced (its picture is on screen already) and
/// then, over it, every pixel the new tile disagrees on — as runs of equal
/// colour, one whole-pixel rect each, `BlendMode.src` so a pixel that
/// became transparent becomes transparent. Exact whichever way the edit
/// went, and cheap in proportion to the CHANGE, not the tile: 🧪measured on
/// brush-made tiles, an erase over 500×300 px was 1,044 rects across six
/// tiles, a 120 px stroke 34, a hard hatch 666 — and a soft gradient laid
/// on nothing was 46k per tile, which is why [rectBudget] exists and why
/// exceeding it composes nothing (the caller keeps today's answer).
///
/// The predecessor's own picture may itself be a stand-in; the chain
/// cannot run away, because every tile's real decode is already in
/// flight and replaces its stand-in when it lands.
///
/// ⚠️STRAIGHT ALPHA IN, PREMULTIPLIED OUT. Tile bytes are straight RGBA
/// (the app's storage convention); `Paint.color` takes straight ARGB and
/// the engine premultiplies at the draw — the same conversion the decode
/// path makes, so the composed pixel is the decoded pixel.
///
/// Returns the stand-in it put in [cache] for [placed]'s tile (ownership
/// transferred there), and the rects it spent, or null image and zero rects
/// when it declined: predecessor missing, its picture missing, or over
/// budget.
({ui.Image? image, int rects}) composePredecessorStandIn({
  required BitmapTileImageCache cache,
  required PlacedTile placed,
  required TilePredecessor predecessor,
  required int rectBudget,
}) {
  final tile = placed.tile;
  final before = predecessor.tile;
  ui.Image? beforeImage;
  if (before != null) {
    beforeImage = cache.displayImageFor(before);
    if (beforeImage == null && before.hasInk) {
      // Pixels stood here and nothing on screen shows them: composing now
      // would publish the difference over nothing, a tile missing its base.
      return (image: null, rects: 0);
    }
  }
  final size = tile.size;
  final pixels = size * size;
  // One pass over both tiles, as 32-bit words: each run of consecutive
  // pixels that differ from the predecessor AND share one colour becomes
  // a rect. Recorded first, drawn only if the whole tile fits the budget —
  // a tile drawn by halves would be exactly the kind of picture this
  // exists to replace.
  final runX = <int>[];
  final runY = <int>[];
  final runW = <int>[];
  final runArgb = <int>[];
  final complete = tile.readPixels((_, afterView) {
    final after = afterView.buffer.asUint32List(afterView.offsetInBytes, pixels);
    bool walk(Uint32List? beforeWords) {
      for (var y = 0; y < size; y++) {
        final row = y * size;
        var x = 0;
        while (x < size) {
          final word = after[row + x];
          final previous = beforeWords == null ? 0 : beforeWords[row + x];
          if (word == previous) {
            x++;
            continue;
          }
          final start = x;
          x++;
          while (x < size &&
              after[row + x] == word &&
              (beforeWords == null ? 0 : beforeWords[row + x]) != word) {
            x++;
          }
          if (runX.length >= rectBudget) {
            return false;
          }
          runX.add(start);
          runY.add(y);
          runW.add(x - start);
          runArgb.add(word);
        }
      }
      return true;
    }

    if (before == null) {
      return walk(null);
    }
    return before.readPixels(
      (_, beforeView) => walk(
        beforeView.buffer.asUint32List(beforeView.offsetInBytes, pixels),
      ),
    );
  });
  if (!complete) {
    return (image: null, rects: 0);
  }
  final extent = size.toDouble();
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder, Rect.fromLTWH(0, 0, extent, extent));
  if (beforeImage != null) {
    canvas.drawImage(beforeImage, Offset.zero, _tilePaint);
  }
  final paint = Paint()
    ..blendMode = BlendMode.src
    ..isAntiAlias = false;
  for (var i = 0; i < runX.length; i++) {
    // Little-endian RGBA word: r is the low byte, a the high one.
    final word = runArgb[i];
    paint.color = Color.fromARGB(
      (word >> 24) & 0xFF,
      word & 0xFF,
      (word >> 8) & 0xFF,
      (word >> 16) & 0xFF,
    );
    canvas.drawRect(
      Rect.fromLTWH(
        runX[i].toDouble(),
        runY[i].toDouble(),
        runW[i].toDouble(),
        1,
      ),
      paint,
    );
  }
  final image = rasterPicture(recorder, size, size);
  cache.putProvisional(placed, image);
  TilePredecessors.instance.drop(tile);
  return (image: image, rects: runX.length);
}
