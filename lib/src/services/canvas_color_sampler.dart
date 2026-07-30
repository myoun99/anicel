import '../core/color_matrix.dart';
import '../core/floor_math.dart';
import '../models/bitmap_surface.dart';
import '../models/canvas_point.dart';
import '../models/canvas_size.dart';
import '../models/cut.dart';
import '../models/layer.dart';
import '../models/layer_effect.dart';
import '../models/layer_id.dart';
import '../models/layer_kind.dart';
import '../models/pasteboard_bounds.dart';
import '../models/project_background.dart';
import '../models/tile_coord.dart';
import '../ui/canvas/composite_effect_paint.dart'
    show resolveColorMatrixIgnoringSpatial;
import '../ui/canvas/layer_pose_paint.dart' show layerPoseMatrix;
import 'cut_frame_composite_plan.dart';

/// The default blend base when the caller does not thread the project
/// background (R10-⑥: production passes the project's paper; a
/// transparent background blends over its opaque export-fallback color).
///
/// R28 #9: aliases the ONE paper constant rather than repeating a
/// literal — the near-white the user caught was spelled out separately in
/// five files, so they could drift.
const int canvasPaperColor = ProjectBackground.defaultPaperArgb;

/// The straight-alpha RGBA of [surface] at integer canvas coords, or null
/// beyond the PASTEBOARD wall (missing tiles are fully transparent).
/// Off-canvas coordinates are real pixels — the eyedropper picks them
/// like Flash does; floorDiv keeps negative coords on the right tile.
int? surfacePixelRgba(BitmapSurface surface, int x, int y) {
  if (!surface.canvasSize.containsPasteboardPixel(x: x, y: y)) {
    return null;
  }
  final tileSize = surface.tileSize;
  final tile = surface.tiles[TileCoord(
    x: floorDiv(x, tileSize),
    y: floorDiv(y, tileSize),
  )];
  if (tile == null) {
    return 0;
  }
  final index = ((y % tileSize) * tileSize + (x % tileSize)) * 4;
  final pixels = tile.pixels;
  return (pixels[index] << 24) |
      (pixels[index + 1] << 16) |
      (pixels[index + 2] << 8) |
      pixels[index + 3];
}

/// An ADJUSTMENT row's colour matrix as the eyedropper should apply it, or
/// null when the row filters nothing this walk can answer (hidden,
/// bypassed, mix 0, or a chain with no colour in it).
///
/// The MIX folds into the matrix exactly as it does on the paint routes
/// ([resolveAdjustmentScopePass]), so the number the eyedropper reports and
/// the pixel on screen come from the same arithmetic.
///
/// ⚠️ The row's SCOPE is approximated by "everything accumulated so far",
/// which is this sampler's existing flat-path fidelity: it already ignores
/// group buffers and blend modes. An adjustment inside a buffering folder
/// therefore reads as if it applied to the whole stack below.
List<double>? _adjustmentColorMatrix({
  required Layer adjustment,
  required Cut cut,
  required int frameIndex,
}) {
  if (!adjustment.isVisible) {
    return null;
  }
  final mix = adjustment.opacity.clamp(0.0, 1.0).toDouble();
  if (mix <= 0) {
    return null;
  }
  if (!resolveFolderChainAt(
    cut: cut,
    layer: adjustment,
    frameIndex: frameIndex,
  ).visible) {
    return null;
  }
  final effects = resolveLayerEffectsAt(
    effects: adjustment.effects,
    frameIndex: frameIndex,
  );
  final matrix = resolveColorMatrixIgnoringSpatial(effects);
  if (matrix == null) {
    return null;
  }
  return lerpColorMatrixFromIdentity(matrix, mix);
}

/// Where the eyedropper reads its color from (R28 #6, the PS/CSP setting).
enum CanvasColorSampleSource {
  /// Every visible layer, blended bottom-up over the paper — "pick what
  /// you SEE". The user's default.
  display,

  /// The ACTIVE layer's own pixels only. Transparent artwork reads as the
  /// paper beneath it, which is what Photoshop's "current layer" does once
  /// there is nothing to pick.
  layer,
}

/// The canvas point mapped into [entry]'s ARTWORK space — the inverse of
/// the pose [applyLayerPoseTransform] paints with. Null when the pose is
/// singular (a zero zoom collapses the layer to nothing, so there is no
/// pixel under the pointer).
///
/// R28 #7: posed layers used to be SKIPPED here, which meant any layer
/// carrying a transform — or merely sitting inside a folder that did —
/// contributed nothing and the pick fell through to the paper. That is the
/// "그림이 있는 레이어인데도 뭐든 #EDEDED" report, and it came and went with
/// whether a transform key happened to exist at the time.
CanvasPoint? _artworkPointFor(
  CutFrameCompositeEntry entry,
  CanvasSize canvasSize,
  CanvasPoint point,
) {
  final pose = entry.pose;
  if (pose == null) {
    return point;
  }
  final matrix = layerPoseMatrix(
    pose,
    canvasSize,
    anchorPoint: entry.anchorPoint,
  );
  if (matrix.invert() == 0) {
    return null;
  }
  final mapped = matrix.storage;
  return CanvasPoint(
    x: mapped[0] * point.x + mapped[4] * point.y + mapped[12],
    y: mapped[1] * point.x + mapped[5] * point.y + mapped[13],
  );
}

/// Samples the color at [point] (P5 eyedropper); returns opaque ARGB.
///
/// [source] picks the reference (R28 #6): `display` blends the shared
/// composite visit's entries bottom-up over the paper with each entry's
/// effective opacity, `layer` reads [activeLayerId]'s pixels alone. Either
/// way a POSED layer samples through the inverse of its pose, so the pick
/// matches what the screen shows.
///
/// Works in every section and on every layer kind by construction: a row
/// with no artwork simply contributes nothing and the paper shows through
/// (an SE row picks the canvas color, which is the behaviour the user
/// described).
int sampleCompositeColor({
  required Cut cut,
  required int frameIndex,
  required LayerFrameSurfaceResolver surfaceResolver,
  required CanvasPoint point,
  int paperColor = canvasPaperColor,
  CanvasColorSampleSource source = CanvasColorSampleSource.display,
  LayerId? activeLayerId,
}) {
  // The LAYER STACK accumulates on its own, PREMULTIPLIED, with its own
  // coverage — the paper joins once at the end.
  //
  // ★ It used to start at the paper, which made an adjustment row compute
  // `filter(stack over paper)` while every paint route computes
  // `filter(stack) over paper` (the adjustment's saveLayer wraps the scope;
  // the background is drawn outside it). The two agree only where the stack
  // is fully opaque, so a grade over a half-covered cel — or over nothing
  // at all — read a colour no route would ever paint.
  var r = 0.0;
  var g = 0.0;
  var b = 0.0;
  var coverage = 0.0;

  final entryByLayerId = {
    for (final entry in resolveCutFrameCompositeEntries(
      cut: cut,
      frameIndex: frameIndex,
    ))
      entry.layer.id: entry,
  };

  // Walked in STACK order so the R6 effects land where they do on screen:
  // a row's own chain filters its pixel before it blends, and an
  // ADJUSTMENT row (which resolves no entry of its own) filters everything
  // accumulated below it.
  //
  // COLOUR only. A blur is a spatial filter — it answers "what colour is
  // at this point" by reading its neighbours, which a one-pixel byte walk
  // cannot do — so a blurred picture samples as its unblurred self. Same
  // class of honest gap as this sampler's blend modes and group buffers,
  // and named here so it is not mistaken for a bug.
  for (final layer in cut.layers) {
    if (layerKindFiltersBelow(layer.kind)) {
      // "Pick from the current layer" is the what-ink-is-this mode: it
      // reads the row as DRAWN and no adjustment applies to it.
      if (source == CanvasColorSampleSource.layer) {
        continue;
      }
      // Nothing accumulated = nothing to grade, which is exactly when the
      // composite tree emits no adjustment node either.
      if (coverage <= 0) {
        continue;
      }
      final matrix = _adjustmentColorMatrix(
        adjustment: layer,
        cut: cut,
        frameIndex: frameIndex,
      );
      if (matrix == null) {
        continue;
      }
      // The matrix works on STRAIGHT colour, so un-premultiply, filter,
      // re-premultiply. Coverage is untouched: a colour matrix leaves alpha
      // alone by construction.
      final filtered = applyColorMatrixToStraightColor(
        matrix,
        r / coverage,
        g / coverage,
        b / coverage,
        coverage * 255,
      );
      r = filtered.r * coverage;
      g = filtered.g * coverage;
      b = filtered.b * coverage;
      continue;
    }
    final entry = entryByLayerId[layer.id];
    if (entry == null) {
      continue;
    }
    if (source == CanvasColorSampleSource.layer &&
        entry.layer.id != activeLayerId) {
      continue;
    }
    final surface = surfaceResolver(entry.layer, entry.frame);
    if (surface == null) {
      continue;
    }
    final artworkPoint = _artworkPointFor(entry, cut.canvasSize, point);
    if (artworkPoint == null) {
      continue;
    }
    final rgba = surfacePixelRgba(
      surface,
      artworkPoint.x.floor(),
      artworkPoint.y.floor(),
    );
    if (rgba == null || rgba == 0) {
      continue;
    }
    final alpha = (rgba & 0xFF) / 255.0 * entry.opacity;
    if (alpha <= 0) {
      continue;
    }
    var sourceR = ((rgba >> 24) & 0xFF).toDouble();
    var sourceG = ((rgba >> 16) & 0xFF).toDouble();
    var sourceB = ((rgba >> 8) & 0xFF).toDouble();
    // The row's own chain filters its pixel BEFORE its opacity meets the
    // stack — the same order the paint routes use. `display` only: the
    // layer mode reads the ink as drawn.
    if (source == CanvasColorSampleSource.display) {
      // The LENIENT resolver: a chain of [brightness, blur] still reports
      // the brightness. The strict one exists so a PAINT route can never
      // mistake a colour matrix for the whole chain.
      final matrix = resolveColorMatrixIgnoringSpatial(entry.effects);
      if (matrix != null) {
        final filtered = applyColorMatrixToStraightColor(
          matrix,
          sourceR,
          sourceG,
          sourceB,
          (rgba & 0xFF).toDouble(),
        );
        sourceR = filtered.r;
        sourceG = filtered.g;
        sourceB = filtered.b;
      }
    }
    // Premultiplied src-over, coverage tracked alongside.
    r = sourceR * alpha + r * (1 - alpha);
    g = sourceG * alpha + g * (1 - alpha);
    b = sourceB * alpha + b * (1 - alpha);
    coverage = alpha + coverage * (1 - alpha);
  }
  // The paper joins LAST, under the graded stack — the order the routes
  // paint in.
  final paperR = ((paperColor >> 16) & 0xFF).toDouble();
  final paperG = ((paperColor >> 8) & 0xFF).toDouble();
  final paperB = (paperColor & 0xFF).toDouble();
  final outR = r + paperR * (1 - coverage);
  final outG = g + paperG * (1 - coverage);
  final outB = b + paperB * (1 - coverage);
  return 0xFF000000 |
      (outR.round().clamp(0, 255) << 16) |
      (outG.round().clamp(0, 255) << 8) |
      outB.round().clamp(0, 255);
}
