import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../../models/bitmap_surface.dart';
import '../../models/brush_stamp_image.dart';
import '../../models/pasteboard_bounds.dart';
import '../../models/tile_coord.dart';
import 'bitmap_tile_image_cache.dart';
import 'tile_origin.dart';
import 'tiles_under_rect.dart';

/// Draws, in CANVAS coordinates, the picture the screen is ALREADY showing
/// over [region] — the float being dragged, the held resample, a fill's
/// stamp.
///
/// Returns false when it cannot draw all of what belongs there. A piece
/// missing from a composed tile is a hole in the artwork, which is worse
/// than the answer that coordinate has today, so the caller leaves it
/// alone rather than seeding half a picture.
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
/// selection layer's float and held resample — rather than at the commit
/// funnel, which holds only bytes. Turning bytes into an image
/// synchronously is `decodeImageFromPixelsSync`, and that is Impeller
/// only while Windows runs Skia in every build.
///
/// ⚠️ PRECONDITION: the INK owns the operator, and it must be the one the
/// commit composites with — nothing here can check it. This draws the base
/// and hands the canvas over; what the ink paints on top is the whole
/// claim. Two commits, two operators, each matched by its ink:
///  · a lift/move LANDING commits a stamp dab at the default
///    [BrushBlendMode.color], which is `srcOver` (`brush_blend_mode.dart`),
///    and its inks ([inkFromImage], the float) draw srcOver;
///  · a LIFT commits its erase destination-out from the mask's own bytes,
///    and [inkCutByMask] draws exactly that (F-68 ②).
/// A `behind`, or any separable brush blend, would need an ink of its own:
/// drawn as srcOver it would publish a picture the commit never wrote.
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
  final pasteboard = Rect.fromLTRB(
    canvasSize.pasteboardLeft.toDouble(),
    canvasSize.pasteboardTop.toDouble(),
    canvasSize.pasteboardRightExclusive.toDouble(),
    canvasSize.pasteboardBottomExclusive.toDouble(),
  );
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
    final picture = recorder.endRecording();
    if (!complete) {
      picture.dispose();
      skipped += 1;
      continue;
    }
    // ⚠️`toImageSync` THROWS — `static_raster.dart` says so where it wraps the
    // same call. A dispose on the next line runs only when it did not, so the
    // refusal arm kept the picture. The refusal above already disposes; this
    // makes the two arms agree by structure instead of by remembering.
    final ui.Image image;
    try {
      image = picture.toImageSync(tileSize, tileSize);
    } finally {
      picture.dispose();
    }
    images.putProvisional(tile, image);
    seeded += 1;
  }
  return (seeded: seeded, adopted: adopted, skipped: skipped);
}

/// Ink that is ONE image already sitting at [placement] in canvas space —
/// a held resample, a fill's stamp.
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

/// Ink that CUTS the picture under it by a coverage mask laid at
/// ([left], [top]) in canvas space — destination-out, so what it draws is
/// what goes.
///
/// [mask] is the erase stamp; only byte 3 of each pixel, the coverage, is
/// read. [keepInside] says which side of the mask survives:
///  · false — what a lift's ERASE leaves behind: the coverage is cut out,
///    exactly as `buildSelectionLiftDabs` commits it (destination-out from
///    these very bytes);
///  · true — what the lift CARRIES: everything the coverage did not take is
///    cut, the tile outside the mask's rect included.
///
/// Each run of equal coverage along a row becomes ONE rect at whole pixels
/// with no anti-aliasing, so every pixel is cut by exactly its own coverage
/// — what the image inks get from `FilterQuality.none`, reached without an
/// image. ⛔Not an image: the mask is bytes, and turning bytes into a
/// picture synchronously is Impeller-only while Windows runs Skia.
ProvisionalInkPainter inkCutByMask(
  BrushStampImage mask, {
  required int left,
  required int top,
  required bool keepInside,
}) {
  final rgba = mask.rgba;
  final width = mask.width;
  final height = mask.height;
  final paint = Paint()
    ..blendMode = BlendMode.dstOut
    ..isAntiAlias = false;
  void cut(ui.Canvas canvas, int coverage, Rect rect) {
    if (coverage == 0 || rect.isEmpty) {
      return;
    }
    paint.color = Color.fromARGB(coverage, 0, 0, 0);
    canvas.drawRect(rect, paint);
  }

  final maskRect = Rect.fromLTWH(
    left.toDouble(),
    top.toDouble(),
    width.toDouble(),
    height.toDouble(),
  );
  return (canvas, region) {
    if (keepInside) {
      // Outside the mask's rect the lift took nothing.
      for (final band in <Rect>[
        Rect.fromLTRB(region.left, region.top, region.right, maskRect.top),
        Rect.fromLTRB(
          region.left,
          maskRect.bottom,
          region.right,
          region.bottom,
        ),
        Rect.fromLTRB(region.left, maskRect.top, maskRect.left, maskRect.bottom),
        Rect.fromLTRB(
          maskRect.right,
          maskRect.top,
          region.right,
          maskRect.bottom,
        ),
      ]) {
        cut(canvas, 255, band.intersect(region));
      }
    }
    final fromX = math.max(left, region.left.floor());
    final toX = math.min(left + width, region.right.ceil());
    final fromY = math.max(top, region.top.floor());
    final toY = math.min(top + height, region.bottom.ceil());
    int removalAt(int row, int x) {
      final coverage = rgba[(row + x) * 4 + 3];
      return keepInside ? 255 - coverage : coverage;
    }

    for (var y = fromY; y < toY; y += 1) {
      final row = (y - top) * width - left;
      var x = fromX;
      while (x < toX) {
        final removal = removalAt(row, x);
        var end = x + 1;
        while (end < toX && removalAt(row, end) == removal) {
          end += 1;
        }
        cut(
          canvas,
          removal,
          Rect.fromLTRB(x.toDouble(), y.toDouble(), end.toDouble(), y + 1),
        );
        x = end;
      }
    }
    return true;
  };
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
  final floatPasteboard = Rect.fromLTRB(
    floatCanvas.pasteboardLeft.toDouble(),
    floatCanvas.pasteboardTop.toDouble(),
    floatCanvas.pasteboardRightExclusive.toDouble(),
    floatCanvas.pasteboardBottomExclusive.toDouble(),
  );
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
