import 'dart:ui' as ui;

import '../../models/bitmap_surface.dart';
import '../../models/pasteboard_bounds.dart';
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
  /// The SKELETON both flattens are: resolve the operand tiles, find the
  /// world rect they cover, record [place] into a canvas already
  /// translated into that rect's space, and rasterize.
  ///
  /// ⛔NULL IS THE LAW, and it was written twice: the strict subset must
  /// hold and the tiles must have a rect, or the caller falls back to the
  /// walk. Two guards in two places is two chances for one of them to
  /// start answering differently.
  ///
  /// [place] is the one step that differs — full assembly versus
  /// incremental replace/clear — and it is a value, not a mode. It is
  /// called ONCE per flatten (per dab batch), never per tile and never
  /// per pixel; the tile loop inside it stays a plain for/drawImage.
  static ActiveLayerFlatImage? _flattenOrNull({
    required BitmapSurface surface,
    required BitmapTileImageCache tileImages,
    ActiveStrokeOverlayModel? overlay,
    required void Function(ui.Canvas canvas, Map<TileCoord, ui.Image> operands)
    place,
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
    final canvas = ui.Canvas(recorder)
      ..translate(-worldRect.left, -worldRect.top);
    place(canvas, operands);
    return _rasterize(recorder, worldRect);
  }

  /// Raw pixels, placed and never resampled: the flat is the layer's own
  /// bytes at 1:1, so any filtering or antialiasing here would be a
  /// second interpretation of them.
  static ui.Paint _placementPaint() => ui.Paint()
    ..filterQuality = ui.FilterQuality.none
    ..isAntiAlias = false;

  /// The full flatten, or null when the strict subset does not hold.
  static ActiveLayerFlatImage? buildOrNull({
    required BitmapSurface surface,
    required BitmapTileImageCache tileImages,
    ActiveStrokeOverlayModel? overlay,
  }) => _flattenOrNull(
    surface: surface,
    tileImages: tileImages,
    overlay: overlay,
    place: (canvas, operands) {
      final paint = _placementPaint();
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
    },
  );

  /// Re-flattens only [changedCoords] over [previous] — the per-dab-batch
  /// step. Each changed coordinate is REPLACED wholesale
  /// ([ui.BlendMode.src]): replacement is the semantics the pre-blended
  /// tiles carry (an erasing tile already HAS its hole), and srcOver over
  /// the previous flat would be the R14-④ dark-line family.
  ///
  /// Null when the subset breaks or a changed coordinate's image is not
  /// ready — the caller falls back to [buildOrNull] or the walk.
  ///
  /// 🚨★★★NOT WIRED YET (⏸5b), AND WHOEVER WIRES IT OWES A BYTE BUDGET.
  /// Drawing `previous.image` into the recording that becomes the next
  /// image is the SAME SHAPE as the display buffer's patch, and that shape
  /// pins a chain: the deferred image keeps its display list for its whole
  /// life, and the list holds the image before it, one flat per link —
  /// rasterization releases nothing (`rasterPicture` has the engine fact).
  /// Unbounded it cost the user 17GB (2026-09-12) — see
  /// `DisplayBufferCache._maxChainBytes` and `_maxDerivedDepth`, the two
  /// budgets THAT chain answers to.
  ///
  /// ⛔Do not reach over and share that field. They are two chains with
  /// two lifetimes, and one number answering both is the trap
  /// ([[make-the-invariant-unrepresentable]]); if a third appears, THEN
  /// they have earned a common home (3의 규칙).
  static ActiveLayerFlatImage? patchOrNull({
    required ActiveLayerFlatImage previous,
    required Set<TileCoord> changedCoords,
    required BitmapSurface surface,
    required BitmapTileImageCache tileImages,
    ActiveStrokeOverlayModel? overlay,
  }) => _flattenOrNull(
    surface: surface,
    tileImages: tileImages,
    overlay: overlay,
    place: (canvas, operands) {
      // The previous flat lands first, srcOver on transparent = byte
      // pass-through, at ITS OWN placement — the extent may have grown.
      canvas.drawImage(
        previous.image,
        ui.Offset(previous.worldRect.left, previous.worldRect.top),
        _placementPaint(),
      );
      final replace = _placementPaint()..blendMode = ui.BlendMode.src;
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
    },
  );

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
    if (overlay != null) {
      // The arbitration windows are per-coordinate REGARDLESS of whether
      // stroke images are currently held: settling and stand-ins cover
      // COMMITTED tiles through a transition the walk arbitrates tile by
      // tile, and a fill stamp is its own geometry. Gating these on
      // hasStrokeContent left them unreachable the moment the stroke
      // map emptied — the probe caught the knee path composing straight
      // through a settling window.
      if (overlay.stampImage != null ||
          overlay.settling ||
          overlay.hasStandIns) {
        return null;
      }
      if (overlay.hasStrokeContent &&
          (!overlay.preBlended || overlay.tileSize != surface.tileSize)) {
        return null;
      }
    }
    final overlayOwns =
        overlay != null && overlay.hasStrokeContent
        ? overlay.tileImages
        : const <TileCoord, ui.Image>{};
    final operands = <TileCoord, ui.Image>{};
    for (final entry in overlayOwns.entries) {
      operands[entry.key] = entry.value;
    }
    for (final entry in surface.tiles.entries) {
      if (operands.containsKey(entry.key)) {
        continue; // The overlay REPLACES its coordinate.
      }
      final image = tileImages.imageFor(entry.value);
      if (image == null) {
        // A visible truth this flatten cannot carry — refusing beats
        // baking a hole or a stand-in in permanently.
        return null;
      }
      operands[entry.key] = image;
    }
    return operands;
  }

  /// The ink's tile-aligned bounds, clipped at the pasteboard wall
  /// ([PasteboardBounds.pasteboardRect] — the same wall the painter clips
  /// to). Null when there is no ink at all.
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
    final clipped = union.intersect(surface.canvasSize.pasteboardRect);
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
