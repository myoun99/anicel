import 'dart:math' as math;
import 'dart:typed_data';

import '../core/bounded_memo.dart';
import '../models/brush_anti_alias.dart';

/// How far past its rim a round tip reaches: the half of a pixel its
/// square covers beyond the point it is measured at.
const double roundTipReachPastRim = 0.5;

/// 🚨★★★A ROUND TIP IS TWO RAMPS AND A PIXEL'S SQUARE, READ ALONG ITS RADIUS
/// (board a-one-pixel-dab-drops-out-by-where-it-lies Q4, 유저 2026-10-25
/// 「AA 가장자리는 쌓이지 않는다」).
///
/// Its hardness ramp falls from `radius × hardness` to the rim; its
/// anti-alias step's edge ([BrushAntiAlias.edge]) falls over the step's
/// width to a rim a little inside; at a point it is the lower of the two.
/// What a pixel lays is what its square — a pixel across, along the radius —
/// covers of that ([coverage]); what of it PILES where dabs overlap is the
/// hardness alone, as the nearest of the square reads it ([pile]). The rest
/// is edge, and sets how high a stroke may come there instead
/// (`edgeCeiling`) — so a line's cross-section is one dab's, as Clip
/// Studio's is.
///
/// 🚨THE TABLES ARE THE LAW, not a cache of it: the kernels (Dart and C) and
/// the reference all read these two tables the same way ([readAt]), and
/// the closed form below only fills them — so they agree to the byte.
/// 🔬Read off a 2D stamp instead (the stamp cache's mask, a texel a pixel,
/// sampled bilinearly) the profile blurred a second time: the 1px line came
/// out 15% under the law and the 10px edge half as wide again (2026-10-25,
/// measured through the stroke path). A circle is the same along every
/// radius, so one row of it is all there is to keep.
///
/// ↩️I-50 (2026-09-30): ONE ramp, from the nearer of the two radii to the
/// rim, sampled at the pixel's centre and baked into a 2D stamp — the edge
/// ended at the rim and piled with every dab, and a 1px dab between pixel
/// centres drew nothing.
class RoundTipProfile {
  RoundTipProfile._({
    required this.coverage,
    required this.pile,
    required this.scale,
    required this.reach,
    required this.inner,
  });

  /// What a pixel at `entry / scale` from the centre lays, entry by entry —
  /// two entries past [reach], so a read never runs off the end.
  final Float64List coverage;

  /// What of [coverage] piles, entry by entry.
  final Float64List pile;

  /// Entries per canvas pixel.
  final double scale;

  /// Nothing at or past this distance.
  final double reach;

  /// At or within this distance a pixel's square lies inside both ramps'
  /// tops: it lays 1, and all of it piles. Negative where none does.
  final double inner;

  /// The profile of a round tip of [radius] at [hardness] under [edge] —
  /// built once per such tip.
  static RoundTipProfile of({
    required double radius,
    required double hardness,
    required BrushTipEdge edge,
  }) => _profiles.resolve(
    (radius: radius, hardness: hardness, edge: edge),
    () => _build(radius, hardness, edge),
  );

  /// [table] at [distance], between its two nearest entries — the one read
  /// every route makes, operation by operation (`qa_round_profile_at`).
  @pragma('vm:prefer-inline')
  double readAt(Float64List table, double distance) {
    final x = distance * scale;
    final i = x.toInt();
    final low = table[i];
    return low + (table[i + 1] - low) * (x - i);
  }
}

/// Entries per canvas pixel, and the most a table holds — past a reach of
/// 256 the entries spread so a 1000px brush keeps 4096 of them.
const double _entriesPerPixel = 16.0;
const double _mostEntries = 4096.0;

/// A stroke at a few sizes builds a few profiles; a pressure sweep through
/// the stamp cache's size steps builds one per step.
final BoundedMemo<
  ({double radius, double hardness, BrushTipEdge edge}),
  RoundTipProfile
>
_profiles = BoundedMemo(256);

RoundTipProfile _build(double radius, double hardness, BrushTipEdge edge) {
  final shape = _RampPair(radius, hardness, edge);
  final reach = radius + roundTipReachPastRim;
  final scale = math.min(_entriesPerPixel, _mostEntries / reach);
  final count = (reach * scale).ceil() + 2;
  final coverage = Float64List(count);
  final pile = Float64List(count);
  final inner = math.min(shape.hardRadius, shape.edgeHard) - 0.5;
  for (var entry = 0; entry < count; entry += 1) {
    final distance = entry / scale;
    if (distance >= reach) {
      continue;
    }
    if (distance <= inner) {
      coverage[entry] = 1.0;
      pile[entry] = 1.0;
      continue;
    }
    coverage[entry] = shape.coverageAt(distance);
    pile[entry] = shape.pileAt(distance);
  }
  return RoundTipProfile._(
    coverage: coverage,
    pile: pile,
    scale: scale,
    reach: reach,
    inner: inner,
  );
}

/// The two ramps of a round tip, and the closed form of what a pixel's
/// square covers of the lower of them.
class _RampPair {
  _RampPair(this.radius, double hardness, BrushTipEdge edge)
    : hardRadius = radius * hardness,
      edgeRim = radius - edge.inset * math.min(1.0, radius / edge.insetReach) {
    final width =
        edge.width +
        edge.widthPerRadius * math.min(radius, edgeSampledRadius);
    edgeHard = math.max(0.0, edgeRim - width);
    turn = _turn();
  }

  final double radius;
  final double hardRadius;
  final double edgeRim;
  late final double edgeHard;

  /// Where the lower of the two passes from the hardness ramp to the
  /// edge's: the edge ends first (its rim lies inside), so past their
  /// crossing it is the edge's — and from the centre on when the edge
  /// starts falling first.
  late final double turn;

  double _turn() {
    if (hardRadius >= edgeHard) {
      return 0.0;
    }
    // (radius − t) / (radius − hardRadius) = (edgeRim − t) / (edgeRim −
    // edgeHard), between edgeHard and edgeRim.
    final hardSpan = radius - hardRadius;
    final edgeSpan = edgeRim - edgeHard;
    return (edgeRim * hardSpan - radius * edgeSpan) / (hardSpan - edgeSpan);
  }

  /// `∫₀ˣ` of the profile — the hardness ramp up to [turn], the edge's
  /// past it.
  double _integral(double x) {
    if (x <= turn) {
      return _rampIntegral(x, hardRadius, radius);
    }
    return _rampIntegral(turn, hardRadius, radius) +
        _rampIntegral(x, edgeHard, edgeRim) -
        _rampIntegral(turn, edgeHard, edgeRim);
  }

  /// What a pixel at [distance] lays: the profile across its square.
  double coverageAt(double distance) {
    final covered = distance >= 0.5
        ? _integral(distance + 0.5) - _integral(distance - 0.5)
        : _integral(distance + 0.5) + _integral(0.5 - distance);
    return covered <= 0.0 ? 0.0 : (covered >= 1.0 ? 1.0 : covered);
  }

  /// What of it piles: the hardness, as the nearest of the square reads it.
  double pileAt(double distance) {
    final nearest = distance - 0.5;
    if (nearest <= hardRadius) {
      return 1.0;
    }
    if (nearest >= radius) {
      return 0.0;
    }
    return (radius - nearest) / (radius - hardRadius);
  }
}

/// `∫₀ˣ ramp(t)` for a ramp at 1 up to [from] and 0 from [to] on.
double _rampIntegral(double x, double from, double to) {
  if (x <= from) {
    return x;
  }
  if (x >= to) {
    return (from + to) * 0.5;
  }
  final span = to - from;
  final left = to - x;
  return from + (span - left * left / span) * 0.5;
}
