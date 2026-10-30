import 'dart:math' as math;

import '../core/turn_trig.dart';
import '../models/brush_anti_alias.dart';
import '../models/brush_dab.dart';
import '../models/brush_tip_mask.dart';
import '../models/brush_tip_shape.dart';
import 'brush_tip_mask_sampling.dart';

import 'round_tip_profile.dart';

/// The per-dab tip constants a dab rasterizer derives once before its pixel
/// loop: the radii, which shape branch applies, and the rotation terms.
/// [reach] is how far from the centre the tip lays anything; [profile] is
/// an analytic round tip's ([RoundTipProfile]).
typedef BrushDabTipGeometry = ({
  double radius,
  double minorRadius,
  double reach,
  RoundTipProfile? profile,
  bool isRound,
  BrushTipMask? tipMask,
  bool isEllipse,
  double tipCos,
  double tipSin,
  double inverseRoundness,
});

/// The numbers a tip is made of, however the caller came by them: a dab
/// carries them as fields, the stamp cache as a quantized cache key.
/// [edge] is the anti-alias step's ([BrushAntiAlias.edge]); [threshold],
/// whether 없음's cut follows the sampling ([brushDabEdgeLaw]).
typedef BrushTipNumbers = ({
  double size,
  double hardness,
  double roundness,
  double angleDegrees,
  BrushTipShape tipShape,
  BrushTipMask? tipMask,
  BrushTipEdge edge,
  bool threshold,
});

/// 🚨ONE derivation for the coverage list, the kernel plan and the stamp
/// cache (the audit's clone scan, 2026-09-03).
///
/// An analytic round tip is its [RoundTipProfile] — two ramps and a pixel's
/// square, read along its radius, the law and its reasons written there.
BrushDabTipGeometry brushTipGeometry(BrushTipNumbers tip) {
  final radius = tip.size / 2.0;
  final isRound = tip.tipShape == BrushTipShape.round;
  final tipMask = tip.tipMask;
  final isEllipse = tipMask == null && isRound && tip.roundness < 1.0;
  final profile = isRound && tipMask == null
      ? RoundTipProfile.of(
          radius: radius,
          hardness: tip.hardness,
          edge: tip.edge,
          antiAliasedCircle: !isEllipse && !tip.threshold,
        )
      : null;
  // A circle and a square do not turn; the others take their cosine and
  // sine from the one table, exact at the quarter turns ([turnCos]).
  final turns = isEllipse || tipMask != null;
  final degrees = turns ? tip.angleDegrees : 0.0;
  return (
    radius: radius,
    minorRadius: radius * tip.roundness,
    reach: profile?.reach ?? radius,
    profile: profile,
    isRound: isRound,
    tipMask: tipMask,
    isEllipse: isEllipse,
    tipCos: turnCos(degrees),
    tipSin: turnSin(degrees),
    inverseRoundness: turns ? 1.0 / tip.roundness : 1.0,
  );
}

BrushDabTipGeometry brushDabTipGeometry(BrushDab dab) => brushTipGeometry((
  size: dab.size,
  hardness: dab.hardness,
  roundness: dab.roundness,
  angleDegrees: dab.angleDegrees,
  tipShape: dab.tipShape,
  tipMask: dab.tipMask,
  edge: dab.antiAlias.edge,
  threshold: brushDabEdgeLaw(dab).threshold,
));

/// What a dab's coverage goes through AFTER its tip is sampled — the
/// anti-alias step's last word.
typedef BrushEdgeLaw = ({bool threshold, double contrast});

/// 🚨★★★ONE answer for the kernel plan and the coverage reference (I-50).
///
/// 없음 cuts at half coverage whatever the tip. Any other step: an ANALYTIC
/// round tip already carries its edge in its profile ([RoundTipProfile])
/// and takes its coverage as it is, and so does a raster tip, whose greys
/// are its picture and not its edge. Only a square keeps the contrast
/// ladder ([BrushAntiAlias.contrast]) — its edge was never made wider by
/// the step.
///
/// 🚨★★★A RASTER TIP LEFT THE LADDER (board
/// imported-water-blend-lays-almost-nothing, 2026-10-30, 유저 「표본을
/// 넣는다」). The ladder pivots on half coverage, so 1단계 wiped every grey
/// under 0.375: Clip Studio's 수채 섞기, at 1단계 with a tip that peaks at
/// 0.63 and averages 0.05, drew next to nothing. The user's stroke of that
/// brush holds the tip's coverage as it is, row for row.
/// ↩️I-50 left raster tips on the ladder for want of a distance to widen;
/// nothing measured had put them there (`f28307f54`: 4 and 2 are 「a
/// geometric placing, not a measurement」).
BrushEdgeLaw brushDabEdgeLaw(BrushDab dab) {
  final contrast = dab.antiAlias.contrast;
  if (contrast == null) {
    return (threshold: true, contrast: 1.0);
  }
  final isSquare = dab.tipShape == BrushTipShape.square;
  return (threshold: false, contrast: isSquare ? contrast : 1.0);
}

/// Whether [tip] holds an EDGE that does not pile under [law] — an analytic
/// round tip ([RoundTipProfile]); 없음's cut leaves none. The kernels and
/// the reference ask it here.
bool tipHoldsAnEdge(BrushDabTipGeometry tip, BrushEdgeLaw law) =>
    !law.threshold && tip.profile != null;

/// How high, as a share of the dab's opacity, a stroke may come where the
/// tip covers [coverage] and [pile] of it piles ([tipPileAt]): what is not
/// pile is edge. 1 where all of it piles.
@pragma('vm:prefer-inline')
double edgeCeiling(double coverage, double pile) =>
    pile > coverage ? coverage / pile : 1.0;

/// What a dab lays toward its edge's [ceiling] ([edgeCeiling]) where it
/// covers [coverage] after its whole cascade: the share that piles — and
/// no more than whole, where a dual tip or the paper raised the coverage
/// past the tip's own. [coverage] itself where the ceiling is 1.
@pragma('vm:prefer-inline')
double edgePiledShare(double coverage, double ceiling) {
  final share = coverage / ceiling;
  return share < 1.0 ? share : 1.0;
}

/// [coverage] through [law] — the definition the tile and native kernels
/// inline against hoisted values.
double brushEdgeApplied(BrushEdgeLaw law, double coverage) {
  if (law.threshold) {
    return coverage >= 0.5 ? 1.0 : 0.0;
  }
  if (law.contrast == 1.0) {
    return coverage;
  }
  return ((coverage - 0.5) * law.contrast + 0.5).clamp(0.0, 1.0).toDouble();
}

/// What [tip] covers at ([dx], [dy]) from the dab centre, whatever kind of
/// tip it is — 0.0 where it does not reach, so a caller skips on `<= 0.0`
/// exactly as it did when it wrote the cascade out.
///
/// ⛔THE THREE ROUTES DISAGREEING HERE IS A SILENT REPAINT: the stamp cache
/// BAKES this into a mask, and a stroke picks the baked route or the direct
/// one by cache state alone — so a falloff changed in one place would make
/// the same brush paint two different edges depending on what was cached.
/// 🚨That goes for WHICH law a tip takes as much as for the law: the cache
/// and the coverage list each picked raster, round or square themselves
/// until 2026-10-01, and this is now the one place the choice is made. The
/// three are one body so the per-pixel loop still makes one call.
/// ↩️The tile kernel's loop (`blendDabTilesDart`) wrote the cascade out a
/// fourth time; it calls this now wherever it does not read an unrotated
/// raster tip off its lattices (board
/// `the-brush-kernel-turns-a-pixel-into-tip-space-in-two-places`).
@pragma('vm:prefer-inline')
double tipCoverageAt(BrushDabTipGeometry tip, double dx, double dy) =>
    _tipAt(tip, dx, dy, pile: false);

/// What of [tipCoverageAt] PILES at ([dx], [dy]) where dabs overlap — at
/// least the coverage, and the coverage itself where all of it piles (a
/// square, a raster tip). The rest of the coverage is the tip's edge and
/// sets how high a stroke may come there: `coverage / pile` of the dab's
/// opacity (board a-one-pixel-dab-drops-out-by-where-it-lies Q4, 유저
/// 2026-10-25 「AA 가장자리는 쌓이지 않는다」).
@pragma('vm:prefer-inline')
double tipPileAt(BrushDabTipGeometry tip, double dx, double dy) =>
    _tipAt(tip, dx, dy, pile: true);

/// [tipCoverageAt] or, given [pile], [tipPileAt] — one turn into the tip's
/// space for both.
@pragma('vm:prefer-inline')
double _tipAt(
  BrushDabTipGeometry tip,
  double dx,
  double dy, {
  required bool pile,
}) {
  final mask = tip.tipMask;
  if (mask == null && !tip.isRound) {
    // A square dab is the fill and stamp verbs' "cover exactly this rect",
    // and the dab constructor refuses to build one that is squashed or
    // rotated — so there is no rotated-rect case to test.
    return 1.0;
  }
  // Into the tip's own space: turned by its angle ([turnedX]), pressed
  // along its minor axis by its roundness. A circle's turn is the identity
  // to the bit (cosine 1 and sine 0 from the table, roundness 1), so its
  // distance is the plain one.
  // 🔬A circle takes the turn too, and must: the debug JIT cannot inline a
  // leaf that has never run, so a loop warmed on circles alone, with their
  // own branch, kept [turnedX] a call — ellipse and raster tips then cost
  // 30 → 66 and 79 → 104 ns a pixel (2026-10-23).
  final tipU = turnedX(dx, dy, tip.tipCos, tip.tipSin);
  final tipV = turnedY(dx, dy, tip.tipCos, tip.tipSin) * tip.inverseRoundness;
  if (mask != null) {
    // A raster tip: nothing outside the mask's square, and all of what it
    // covers piles.
    if (tipU.abs() > tip.radius || tipV.abs() > tip.radius) {
      return 0.0;
    }
    return sampleBrushTipMaskCoverage(
      mask: mask,
      tipU: tipU,
      tipV: tipV,
      radius: tip.radius,
    );
  }
  final profile = tip.profile!;
  if (profile.rowLength > 0) {
    // A small circle: its square tables, read at the pixel's (|dx|, |dy|)
    // — a circle's turn is the identity, so these are the canvas offsets.
    final across = tipU.abs();
    final down = tipV.abs();
    if (across >= profile.reach || down >= profile.reach) {
      return 0.0;
    }
    return profile.readSquareAt(
      pile ? profile.pile : profile.coverage,
      across,
      down,
    );
  }
  final distance = math.sqrt(tipU * tipU + tipV * tipV);
  if (distance >= profile.reach) {
    return 0.0;
  }
  if (distance <= profile.inner) {
    return 1.0;
  }
  return profile.readAt(pile ? profile.pile : profile.coverage, distance);
}
