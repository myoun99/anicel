import '../models/brush_dab.dart';
import '../models/brush_pixel_coverage.dart';
import '../models/rgba_color.dart';
import '../models/stroke_pixel.dart';
import 'brush_dab_share.dart';
import 'brush_dab_tip_geometry.dart';
import 'rgba_blend.dart';

double effectiveBrushPixelOpacity({
  required BrushDab dab,
  required BrushPixelCoverage coverage,
}) {
  return dab.opacity * coverage.coverage;
}

/// What [dab] leaves on one pixel of its stroke at [coverage] — the
/// reference for the tile kernel's pixel (`blendDabTilesDart`): what is
/// under the dab comes off [destination]'s
/// 16-bit plane and the result lands on both planes (ABI 40), the dab
/// laying its share of what it would lay whole (`stampShareOf`, ABI 41).
StrokePixel blendBrushDabStrokePixel({
  required BrushDab dab,
  required BrushPixelCoverage coverage,
  required StrokePixel destination,
}) {
  final evening = eveningTableOf(dab);
  if (dab.erase) {
    return strokeDestinationOut(
      source: RgbaColor.fromArgbInt(dab.color),
      destination: destination,
      opacity: effectiveBrushPixelOpacity(dab: dab, coverage: coverage),
      flow: dab.flow,
      evening: evening,
    );
  }
  // The tip's edge does not pile: it scales the level the dab settles at,
  // and what the dab lays toward it is the share that piles (Q4 — the law
  // beside the tile kernel's ceiling).
  final ceiling = coverage.ceiling;
  if (dab.opacity >= 1.0 && ceiling >= 1.0) {
    return strokeSourceOver(
      source: RgbaColor.fromArgbInt(dab.color),
      destination: destination,
      opacity: effectiveBrushPixelOpacity(dab: dab, coverage: coverage),
      flow: dab.flow,
      evening: evening,
    );
  }
  final source = RgbaColor.fromArgbInt(dab.color);
  final whole = effectiveSourceAlpha(
    source: source,
    opacity: edgePiledShare(coverage.coverage, ceiling),
    flow: dab.flow,
  );
  final sourceAlpha = settledDabAlpha(
    laid: evening == null ? whole : evenedLaid(evening, whole),
    opacity: dab.opacity * ceiling,
    destinationAlpha: destination.a / 65535.0,
  );
  if (sourceAlpha == null || sourceAlpha == 0.0) {
    return destination;
  }
  return strokeSourceOverAt(
    source: source,
    destination: destination,
    sourceAlpha: sourceAlpha,
  );
}

/// What a dab whose opacity is under one lays over [destinationAlpha]:
/// [laid] — what it would lay over nothing — scaled by how much of the way
/// to its [opacity] is left, or null where the pixel already stands there.
///
/// 🚨★★★A DAB'S OPACITY IS THE LEVEL IT SETTLES AT (F-205, 유저 2026-09-28:
/// 「최대 100%로 해두더라도 필압 약하게하면 해당 선들 겹쳐도 필압에맞춰서
/// 10%만큼만 진해진다」). A dab raises what is under it TOWARDS its opacity,
/// at its flow, and never past it: the ink its coverage and flow would lay
/// over nothing, scaled by how much of the way to the ceiling is left —
/// (o - d) / (1 - d). Over nothing that is exactly the old alpha, so a first
/// dab lands what it always did; where dabs pile up they settle at o, not at
/// opaque. ↩️Opacity multiplied the dab's alpha like flow did, and a light
/// press piled up to the full slider wherever a stroke crossed itself.
///
/// ⚠️What is under the dab is its STROKE's own buffer: a stroke of brush dabs
/// never lands on artwork dab by dab — it piles up on an empty buffer and
/// composites once (brush_commit_builder, erase-live-and-dab-route-round-
/// apart) — so d is how far the stroke itself has got, never the paint below.
///
/// An opacity of 1 settles at opaque, which is plain source-over — the old
/// arithmetic, kept byte for byte, so a brush whose opacity no dynamic moves
/// lands exactly what it did. An ERASE dab keeps the multiplier: a brush
/// eraser piles up coverage on its buffer (where this applies) and erases
/// once, and nothing else raises an alpha.
///
/// What the dab would lay whole goes through its share first ([evenedLaid]).
///
/// 🚨★★★AN EDGE SETTLES LOWER (board a-one-pixel-dab-drops-out-by-where-it-
/// lies Q4, 유저 2026-10-25 「AA 가장자리는 쌓이지 않는다」): where the tip's
/// coverage is part edge, the share of it that does not pile
/// (`edgeCeiling`) scales the level it settles at, and what it lays toward
/// it is the share that piles ([edgePiledShare]). At a ceiling of 1 both
/// are the numbers above to the bit; an erase keeps its multiplier.
///
/// This is the law's arithmetic for the reference blend above and the brush
/// swatch (`rasterizeBrushStrokeSample`), which piled its dabs by the old
/// multiplied opacity until 2026-10-01. The tile kernel
/// (`blendDabTilesDart`) writes the same grouping out inline, and the
/// engine's is `dab.wgsl`'s. ↩️Till 2026-11-12 this text stood beside the C
/// kernel's `qa_dab_source_alpha`, which went with the C.
double? settledDabAlpha({
  required double laid,
  required double opacity,
  required double destinationAlpha,
}) {
  if (destinationAlpha >= opacity) {
    return null;
  }
  return laid * (opacity - destinationAlpha) / (1.0 - destinationAlpha);
}
