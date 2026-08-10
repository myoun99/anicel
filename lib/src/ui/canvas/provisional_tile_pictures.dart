import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../../core/floor_math.dart';
import '../../models/bitmap_surface.dart';
import '../../models/pasteboard_bounds.dart';
import '../../models/tile_coord.dart';
import 'bitmap_tile_image_cache.dart';

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
/// rounding orders disagree by one channel step at the faintest ink over
/// the faintest base (`tile_image_sync_compose_parity_test` sweeps it).
/// One frame off by one along the FIDELITY axis is what this program's
/// invariant says to trade; coverage is the axis it says never to trade.
///
/// ⚠️ Composition, not upload. Every operand has to be a `ui.Image`
/// already, which is why this is called where the picture lives — the
/// selection layer's float and held resample — rather than at the commit
/// funnel, which holds only bytes. Turning bytes into an image
/// synchronously is `decodeImageFromPixelsSync`, and that is Impeller
/// only while Windows runs Skia in every build.
///
/// Returns what it did: coordinates it could not answer for keep today's
/// behaviour, and the count is how a caller (or a test) sees that without
/// guessing.
({int seeded, int skipped}) seedProvisionalTilePictures({
  required BitmapSurface preSurface,
  required BitmapSurface postSurface,
  required Iterable<TileCoord> coords,
  required ProvisionalInkPainter ink,
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
  var skipped = 0;
  for (final coord in coords) {
    final tile = postSurface.tileAt(coord);
    if (tile == null || images.displayImageFor(tile) != null) {
      // Nothing there, or it can already draw itself.
      skipped += 1;
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
      if (preImage == null && !preTile.isFullyTransparent) {
        // Pixels were here and we have no picture of them: composing now
        // would publish a tile with the base missing.
        skipped += 1;
        continue;
      }
    }

    final originX = (coord.x * tileSize).toDouble();
    final originY = (coord.y * tileSize).toDouble();
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(
      recorder,
      Rect.fromLTWH(0, 0, tileExtent, tileExtent),
    );
    if (preImage != null) {
      canvas.drawImage(preImage, Offset.zero, _tilePaint);
    }
    canvas.save();
    canvas.translate(-originX, -originY);
    canvas.clipRect(pasteboard);
    final complete = ink(
      canvas,
      Rect.fromLTWH(originX, originY, tileExtent, tileExtent),
    );
    canvas.restore();
    final picture = recorder.endRecording();
    if (!complete) {
      picture.dispose();
      skipped += 1;
      continue;
    }
    final image = picture.toImageSync(tileSize, tileSize);
    picture.dispose();
    images.putProvisional(tile, image);
    seeded += 1;
  }
  return (seeded: seeded, skipped: skipped);
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

/// Ink that is a TILED surface drawn [canvasDelta] away from where its
/// pixels were materialized — the selection float, which is built once and
/// then translated rather than rebuilt (a rebuild is new tile objects with
/// no pictures, which is the thing this exists to avoid).
///
/// Answers false for a region a float tile covers without a picture of its
/// own: the composition would be missing exactly the artwork it is there
/// to carry.
ProvisionalInkPainter inkFromSurface(
  BitmapSurface surface,
  Offset canvasDelta, {
  BitmapTileImageCache? cache,
}) {
  final images = cache ?? BitmapTileImageCache.instance;
  final tileSize = surface.tileSize;
  final tileExtent = tileSize.toDouble();
  return (canvas, region) {
    // The region read in the float's OWN coordinates.
    final local = region.shift(-canvasDelta);
    final firstX = floorDiv(local.left.floor(), tileSize);
    final lastX = floorDiv(local.right.ceil() - 1, tileSize);
    final firstY = floorDiv(local.top.floor(), tileSize);
    final lastY = floorDiv(local.bottom.ceil() - 1, tileSize);
    for (var y = firstY; y <= lastY; y += 1) {
      for (var x = firstX; x <= lastX; x += 1) {
        final tile = surface.tileAt(TileCoord(x: x, y: y));
        if (tile == null) {
          continue;
        }
        final image = images.displayImageFor(tile);
        if (image == null) {
          // A tile with no picture and no pixels covers nothing, so its
          // absence costs nothing; one with pixels is the answer going
          // missing.
          if (tile.isFullyTransparent) {
            continue;
          }
          return false;
        }
        canvas.drawImage(
          image,
          Offset(x * tileExtent, y * tileExtent) + canvasDelta,
          _tilePaint,
        );
      }
    }
    return true;
  };
}
