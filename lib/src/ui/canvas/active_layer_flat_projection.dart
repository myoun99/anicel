import 'dart:ui' as ui;

import '../../models/bitmap_surface.dart';
import '../../models/tile_coord.dart';
import 'active_stroke_overlay.dart';
import 'bitmap_tile_image_cache.dart';

/// ⓔ 4단계 — THE ACTIVE LAYER AS ONE IMAGE, ASSEMBLED, NEVER RE-BLENDED.
///
/// Below the clamp knee the display buffer will draw every layer as ONE
/// image under one uniform filter — that is what closes T21 down there.
/// Every non-active layer already IS one image; this is the active
/// layer's projection to the same shape.
///
/// ★ASSEMBLY, NOT BLENDING. The blend law makes "composite the new dab
/// into the previous flat image" wrong for every mode but plain color:
/// erase and the brush blends are f(ORIGINAL base, ACCUMULATED stroke),
/// never f(previous result, dab). But that math already ran — the
/// overlay's pre-blended replacement tiles carry the COMMIT's own
/// finished bytes per coordinate. This projection only PLACES finished
/// per-coordinate images (committed truth or overlay replacement) at
/// integer offsets with [ui.FilterQuality.none] over a transparent base,
/// which passes premultiplied bytes through unchanged — the byte-parity
/// contract the tile compose path already pins.
///
/// ★NULL IS AN ANSWER, NEVER A BUG. The projection is only AVAILABLE in
/// the strict common case: aligned pre-blended replacement route, no
/// fill stamp, no settling, no stand-ins, and truth images for every
/// committed tile. Anything else returns null and the caller keeps the
/// tile walk — correctness never depends on this existing (the same
/// contract as the bake and the display buffer). Flattening a
/// stand-in/provisional would bake fidelity-traded pixels past the
/// moment the real decode lands; refusing is the "coverage never trades"
/// invariant.
///
/// ★RAW LAYER PIXELS ONLY. No paper, no opacity, no effects, no pose —
/// the flatten sits BELOW the node machinery, which keeps applying those
/// exactly as it does to every other layer's single image.
///
/// The caller owns the returned image (retire replaced ones through the
/// deferred disposer in display code; tests may dispose directly).
class ActiveLayerFlatImage {
  const ActiveLayerFlatImage({required this.image, required this.worldRect});

  /// The flattened raw pixels.
  final ui.Image image;

  /// Where [image] sits in CANVAS space — the ink's own tile-aligned
  /// bounds clipped at the pasteboard wall, never the canvas rect: live
  /// and parked ink displays past the canvas edge, and rendering to the
  /// canvas rect would drop it (the projection pattern's "render to your
  /// own ink bounds, carry placement" rule).
  final ui.Rect worldRect;
}

abstract final class ActiveLayerFlatProjection {
  /// The full flatten, or null when the strict subset does not hold.
  static ActiveLayerFlatImage? buildOrNull({
    required BitmapSurface surface,
    required BitmapTileImageCache tileImages,
    ActiveStrokeOverlayModel? overlay,
  }) {
    final operands = _operandsOrNull(
      surface: surface,
      tileImages: tileImages,
      overlay: overlay,
    );
    if (operands == null) {
      return null;
    }
    final worldRect = _worldRectOf(operands.keys, surface);
    if (worldRect == null) {
      return null;
    }
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.translate(-worldRect.left, -worldRect.top);
    final paint = ui.Paint()
      ..filterQuality = ui.FilterQuality.none
      ..isAntiAlias = false;
    for (final entry in operands.entries) {
      canvas.drawImage(
        entry.value,
        ui.Offset(
          (entry.key.x * surface.tileSize).toDouble(),
          (entry.key.y * surface.tileSize).toDouble(),
        ),
        paint,
      );
    }
    return _rasterize(recorder, worldRect);
  }

  /// Re-flattens only [changedCoords] over [previous] — the per-dab-batch
  /// step. Each changed coordinate is REPLACED wholesale
  /// ([ui.BlendMode.src]): replacement is the semantics the pre-blended
  /// tiles carry (an erasing tile already HAS its hole), and srcOver over
  /// the previous flat would be the R14-④ dark-line family.
  ///
  /// Null when the subset breaks or a changed coordinate's image is not
  /// ready — the caller falls back to [buildOrNull] or the walk.
  static ActiveLayerFlatImage? patchOrNull({
    required ActiveLayerFlatImage previous,
    required Set<TileCoord> changedCoords,
    required BitmapSurface surface,
    required BitmapTileImageCache tileImages,
    ActiveStrokeOverlayModel? overlay,
  }) {
    final operands = _operandsOrNull(
      surface: surface,
      tileImages: tileImages,
      overlay: overlay,
    );
    if (operands == null) {
      return null;
    }
    final worldRect = _worldRectOf(operands.keys, surface);
    if (worldRect == null) {
      return null;
    }
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.translate(-worldRect.left, -worldRect.top);
    // The previous flat lands first, srcOver on transparent = byte
    // pass-through, at ITS OWN placement — the extent may have grown.
    canvas.drawImage(
      previous.image,
      ui.Offset(previous.worldRect.left, previous.worldRect.top),
      ui.Paint()
        ..filterQuality = ui.FilterQuality.none
        ..isAntiAlias = false,
    );
    final replace = ui.Paint()
      ..filterQuality = ui.FilterQuality.none
      ..isAntiAlias = false
      ..blendMode = ui.BlendMode.src;
    final clear = ui.Paint()
      ..isAntiAlias = false
      ..blendMode = ui.BlendMode.clear;
    final tileSize = surface.tileSize.toDouble();
    for (final coord in changedCoords) {
      final origin = ui.Offset(coord.x * tileSize, coord.y * tileSize);
      final image = operands[coord];
      if (image != null) {
        canvas.drawImage(image, origin, replace);
        continue;
      }
      // A coordinate that no longer exists (undo took its tile): the
      // patch must CLEAR it, or yesterday's ink survives in the flat.
      canvas.drawRect(
        ui.Rect.fromLTWH(origin.dx, origin.dy, tileSize, tileSize),
        clear,
      );
    }
    return _rasterize(recorder, worldRect);
  }

  /// The per-coordinate finished images, or null when the strict subset
  /// does not hold. Arbitration is deliberately the TRIVIAL case of the
  /// painter's: overlay replacement image if the coordinate is owned,
  /// else the committed tile's TRUTH image ([BitmapTileImageCache.imageFor]
  /// — never a stand-in, never a stale borrow).
  static Map<TileCoord, ui.Image>? _operandsOrNull({
    required BitmapSurface surface,
    required BitmapTileImageCache tileImages,
    ActiveStrokeOverlayModel? overlay,
  }) {
    final overlayOwns =
        overlay != null && overlay.hasStrokeContent
        ? overlay.tileImages
        : const <TileCoord, ui.Image>{};
    if (overlay != null && overlay.hasStrokeContent) {
      final aligned =
          overlay.preBlended && overlay.tileSize == surface.tileSize;
      if (!aligned ||
          overlay.stampImage != null ||
          overlay.settling ||
          overlay.hasStandIns) {
        return null;
      }
    }
    final operands = <TileCoord, ui.Image>{};
    for (final entry in overlayOwns.entries) {
      operands[entry.key] = entry.value;
    }
    for (final tile in surface.tiles.values) {
      if (operands.containsKey(tile.coord)) {
        continue; // The overlay REPLACES its coordinate.
      }
      final image = tileImages.imageFor(tile);
      if (image == null) {
        // A visible truth this flatten cannot carry — refusing beats
        // baking a hole or a stand-in in permanently.
        return null;
      }
      operands[tile.coord] = image;
    }
    return operands;
  }

  /// The ink's tile-aligned bounds, clipped at the pasteboard wall
  /// (canvas plus one canvas size in every direction — the same wall the
  /// painter clips to). Null when there is no ink at all.
  static ui.Rect? _worldRectOf(Iterable<TileCoord> coords, BitmapSurface surface) {
    ui.Rect? union;
    final tileSize = surface.tileSize.toDouble();
    for (final coord in coords) {
      final rect = ui.Rect.fromLTWH(
        coord.x * tileSize,
        coord.y * tileSize,
        tileSize,
        tileSize,
      );
      union = union == null ? rect : union.expandToInclude(rect);
    }
    if (union == null) {
      return null;
    }
    final width = surface.canvasSize.width.toDouble();
    final height = surface.canvasSize.height.toDouble();
    final pasteboard = ui.Rect.fromLTRB(
      -width,
      -height,
      width * 2,
      height * 2,
    );
    final clipped = union.intersect(pasteboard);
    if (clipped.isEmpty) {
      return null;
    }
    return ui.Rect.fromLTRB(
      clipped.left.floorToDouble(),
      clipped.top.floorToDouble(),
      clipped.right.ceilToDouble(),
      clipped.bottom.ceilToDouble(),
    );
  }

  static ActiveLayerFlatImage _rasterize(
    ui.PictureRecorder recorder,
    ui.Rect worldRect,
  ) {
    final picture = recorder.endRecording();
    try {
      return ActiveLayerFlatImage(
        image: picture.toImageSync(
          worldRect.width.round(),
          worldRect.height.round(),
        ),
        worldRect: worldRect,
      );
    } finally {
      picture.dispose();
    }
  }
}
