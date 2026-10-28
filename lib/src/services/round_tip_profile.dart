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
///
/// 🚨★★A SMALL CIRCLE IS READ BY ITS SQUARE'S WHOLE AREA (board
/// a-one-pixel-dab-drops-out-by-where-it-lies Q6, 유저 2026-10-25 「클튜 점
/// 표본을 보고 정한다」 → b 「작은 붓은 픽셀 면적을 정확히」): up to a radius of
/// [squareReadRadius], a circle's tables are SQUARE ([rowLength]) — what a
/// pixel's square covers of the profile, the square's whole area, read at
/// its centre's (|dx|, |dy|) ([readSquareAt]) — so a dot lays the same ink
/// wherever its centre falls. 📏Clip Studio's G펜 taps do (1px: 22 dots
/// 0.526±0.024, centred 0.515 · off by over 0.3 px 0.530; 0.7 · 1.5 · 2px
/// alike); read along the radius a 1px dot laid 0.48 at a pixel's centre
/// and 0.31 at its corner. Its EDGE is re-solved for the read
/// ([_RampPair.readByArea]): its rim kept, how hard it is chosen so a
/// level line's column lays the radial read's ink — the fit's (Q4 · Q5) —
/// since the same edge read by area laid a 1px line half of it.
/// ⛔The edge does not widen past the nib to make that ink: the dab's dirty
/// region is its radius box, and Clip Studio's small dots are compact (a
/// 2px dot centred in a pixel lays it 245/255).
/// A bigger circle and every ellipse stay radial: past a few pixels the
/// two reads part by less than a hundredth of a pixel of a line's ink, and
/// a square table grows with the square of the radius.
/// ⛔So does a circle under 없음, whose cut is half coverage at the pixel's
/// centre along the radius (`onItsPixel`, 2026-10-24 「AA 없음은 중심이 든
/// 픽셀 하나」): read by area, a 1.5px hard dot on a pixel's corner covered
/// each of the four pixels round it under half and laid none, and a 1px
/// dot at hardness 0.5 laid none anywhere (measured).
class RoundTipProfile {
  RoundTipProfile._({
    required this.coverage,
    required this.pile,
    required this.scale,
    required this.reach,
    required this.inner,
    this.rowLength = 0,
  });

  /// What a pixel at `entry / scale` from the centre lays, entry by entry —
  /// two entries past [reach], so a read never runs off the end. A square
  /// table ([rowLength]) holds a pixel at (`column / scale`, `row / scale`)
  /// row by row, two entries past [reach] each way.
  final Float64List coverage;

  /// What of [coverage] piles, entry by entry.
  final Float64List pile;

  /// Entries a row of [coverage] and [pile] holds where they are SQUARE —
  /// a small circle's, read at (|dx|, |dy|) ([readSquareAt]) — or 0 where
  /// they run along the radius ([readAt]).
  final int rowLength;

  /// Entries per canvas pixel.
  final double scale;

  /// Nothing at or past this distance — along each axis, where the tables
  /// are square.
  final double reach;

  /// At or within this distance a pixel's square lies inside both ramps'
  /// tops: it lays 1, and all of it piles. Negative where none does, and
  /// for square tables, which hold their 1s themselves.
  final double inner;

  /// The profile of a round tip of [radius] at [hardness] under [edge] —
  /// built once per such tip; an [antiAliasedCircle] (roundness 1, not
  /// 없음) up to [squareReadRadius] is read by area.
  static RoundTipProfile of({
    required double radius,
    required double hardness,
    required BrushTipEdge edge,
    required bool antiAliasedCircle,
  }) {
    final square = antiAliasedCircle && radius <= squareReadRadius;
    return _profiles.resolve(
      (radius: radius, hardness: hardness, edge: edge, square: square),
      () => square
          ? _buildSquare(_RampPair(radius, hardness, edge))
          : _build(radius, hardness, edge),
    );
  }

  /// [table] at [distance], between its two nearest entries — the one read
  /// every route makes, operation by operation (`qa_round_profile_at`).
  @pragma('vm:prefer-inline')
  double readAt(Float64List table, double distance) {
    final x = distance * scale;
    final i = x.toInt();
    final low = table[i];
    return low + (table[i + 1] - low) * (x - i);
  }

  /// A square [table] ([rowLength]) at ([across], [down]) — both at or
  /// past 0 and short of [reach] — between its four nearest entries: along
  /// the row, then down — the one read every route makes, operation by
  /// operation (`qa_round_square_at`).
  @pragma('vm:prefer-inline')
  double readSquareAt(Float64List table, double across, double down) {
    final x = across * scale;
    final y = down * scale;
    final i = x.toInt();
    final j = y.toInt();
    final alongRow = x - i;
    final above = j * rowLength + i;
    final below = above + rowLength;
    final top = table[above] + (table[above + 1] - table[above]) * alongRow;
    final bottom = table[below] + (table[below + 1] - table[below]) * alongRow;
    return top + (bottom - top) * (y - j);
  }
}

/// The largest radius a circle is read by its square's whole area at
/// ([RoundTipProfile]) — a 5px nib.
const double squareReadRadius = 2.5;

/// Entries per canvas pixel, and the most a table holds — past a reach of
/// 256 the entries spread so a 1000px brush keeps 4096 of them.
const double _entriesPerPixel = 16.0;
const double _mostEntries = 4096.0;

/// A stroke at a few sizes builds a few profiles; a pressure sweep through
/// the stamp cache's size steps builds one per step.
final BoundedMemo<
  ({double radius, double hardness, BrushTipEdge edge, bool square}),
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

/// A small circle's SQUARE tables ([RoundTipProfile.rowLength]): what each
/// pixel's whole square covers of [radial]'s profile, its edge re-solved
/// for the read ([_RampPair.readByArea]), and what of it piles — the
/// hardness at the square's nearest point.
RoundTipProfile _buildSquare(_RampPair radial) {
  final shape = radial.readByArea();
  final pieces = shape.pieces();
  final reach = shape.edgeRim + roundTipReachPastRim;
  const scale = _entriesPerPixel;
  final count = (reach * scale).ceil() + 2;
  // Half a pixel in entries: a square's sides lie on the grid.
  const half = 8;
  // The profile over [0, a / scale] × [0, b / scale], grid point by grid
  // point — a square's area is four of them.
  final n = count + half;
  final quarter = Float64List(n * n);
  for (var b = 1; b < n; b += 1) {
    final yTop = b / scale;
    var running = 0.0;
    for (var a = 1; a < n; a += 1) {
      running += _cellArea(pieces, (a - 1) / scale, a / scale, yTop);
      quarter[b * n + a] = running;
    }
  }
  // The profile is even along both axes, so a corner across one is the
  // mirror's, signed.
  double corner(int a, int b) =>
      (a.sign * b.sign) * quarter[b.abs() * n + a.abs()];
  final coverage = Float64List(count * count);
  final pile = Float64List(count * count);
  for (var j = 0; j < count; j += 1) {
    final nearestDown = math.max(0.0, j / scale - 0.5);
    for (var i = 0; i < count; i += 1) {
      final covered =
          corner(i + half, j + half) -
          corner(i - half, j + half) -
          corner(i + half, j - half) +
          corner(i - half, j - half);
      coverage[j * count + i] = covered <= 0.0
          ? 0.0
          : (covered >= 1.0 ? 1.0 : covered);
      final nearestAcross = math.max(0.0, i / scale - 0.5);
      pile[j * count + i] = shape.hardnessAt(
        math.sqrt(nearestAcross * nearestAcross + nearestDown * nearestDown),
      );
    }
  }
  return RoundTipProfile._(
    coverage: coverage,
    pile: pile,
    scale: scale,
    reach: reach,
    inner: -1.0,
    rowLength: count,
  );
}

/// A stretch of a round tip's profile along its radius: `a + b·ρ` from
/// [from] to [to].
typedef _Piece = ({double from, double to, double a, double b});

/// Gauss–Legendre's four nodes on [-1, 1] and their weights.
const _nodes = [
  -0.8611363115940526,
  -0.3399810435848563,
  0.3399810435848563,
  0.8611363115940526,
];
const _weights = [
  0.3478548451374538,
  0.6521451548625461,
  0.6521451548625461,
  0.3478548451374538,
];

/// The profile [pieces] lay over [x0, x1] × [0, yTop] — Gauss along x,
/// closed form along y.
double _cellArea(List<_Piece> pieces, double x0, double x1, double yTop) {
  final middle = (x0 + x1) / 2;
  final halfWidth = (x1 - x0) / 2;
  var sum = 0.0;
  for (var k = 0; k < 4; k += 1) {
    sum +=
        _weights[k] *
        _columnArea(pieces, middle + halfWidth * _nodes[k], yTop);
  }
  return sum * halfWidth;
}

/// `∫₀^yTop` of the profile [pieces] at `√(x² + y²)` along y.
double _columnArea(List<_Piece> pieces, double x, double yTop) {
  final xx = x * x;
  var sum = 0.0;
  for (final piece in pieces) {
    if (piece.to <= x) {
      continue;
    }
    final y0 = piece.from <= x
        ? 0.0
        : math.sqrt(piece.from * piece.from - xx);
    final y1 = math.min(yTop, math.sqrt(piece.to * piece.to - xx));
    if (y1 <= y0) {
      continue;
    }
    sum += piece.a * (y1 - y0) + piece.b * (_root(x, y1) - _root(x, y0));
  }
  return sum;
}

/// `∫₀ʸ √(x² + t²) dt`.
double _root(double x, double y) {
  if (x == 0.0) {
    return y * y * 0.5;
  }
  final r = math.sqrt(x * x + y * y);
  return 0.5 * (y * r + x * x * math.log((y + r) / x.abs()));
}

/// What a level line's pixel column holds of the profile [pieces] read by
/// AREA: the strip |x| < ½ of it, whole.
double _stripArea(List<_Piece> pieces) {
  var sum = 0.0;
  for (var cell = 0; cell < 8; cell += 1) {
    sum += _cellArea(pieces, cell / 16, (cell + 1) / 16, double.infinity);
  }
  return 4 * sum;
}

/// The two ramps of a round tip, and the closed form of what a pixel's
/// square covers of the lower of them.
class _RampPair {
  _RampPair(this.radius, double hardness, BrushTipEdge edge)
    : hardRadius = radius * hardness,
      edgeRim = radius - edge.inset * math.min(1.0, radius / edge.insetReach) {
    final width =
        edge.width + edge.widthPerRadius * math.min(radius, edge.widthReach);
    edgeHard = math.max(0.0, edgeRim - width);
    turn = _turn();
  }

  /// [radius]'s hardness ramp under an edge hard to [edgeHard] and gone at
  /// [edgeRim] ([readByArea]).
  _RampPair._edged(this.radius, this.hardRadius, this.edgeRim, double hard) {
    edgeHard = hard;
    turn = _turn();
  }

  /// This pair with its EDGE re-solved for a read by area (Q6 b): its rim
  /// kept and its hard part chosen so a level line's column lays what the
  /// radial read lays it — `∫` of the profile across the line, the fit's
  /// ink. A cone to the rim never over-inks — a column across a profile
  /// that falls from its centre holds at most that profile's line ink, and
  /// the cone's is the least of any hard part — so the solve starts there;
  /// where even a hard disc to the rim under-inks, the rim goes out, as far
  /// as the radius (the solve's bound).
  _RampPair readByArea() {
    final want = 2.0 * _integral(radius);
    double strip(double hard, double rim) =>
        _stripArea(_RampPair._edged(radius, hardRadius, rim, hard).pieces());
    double solve(double Function(double) inkAt, double low, double high) {
      var lo = low;
      var hi = high;
      for (var i = 0; i < 30; i += 1) {
        final mid = (lo + hi) / 2;
        if (inkAt(mid) < want) {
          lo = mid;
        } else {
          hi = mid;
        }
      }
      return (lo + hi) / 2;
    }

    if (strip(edgeRim, edgeRim) < want) {
      final rim = solve((rim) => strip(rim, rim), edgeRim, radius);
      return _RampPair._edged(radius, hardRadius, rim, rim);
    }
    final hard = solve((hard) => strip(hard, edgeRim), 0.0, edgeRim);
    return _RampPair._edged(radius, hardRadius, edgeRim, hard);
  }

  /// The profile along the radius, stretch by stretch — each straight
  /// between two of the ramps' corners (and their crossing, [turn]), and
  /// nothing past the edge's rim, which lies within the radius.
  List<_Piece> pieces() {
    final corners = <double>{
      0.0,
      for (final corner in [hardRadius, radius, edgeHard, turn])
        if (corner > 0.0 && corner < edgeRim) corner,
      if (edgeRim > 0.0) edgeRim,
    }.toList()..sort();
    return [
      for (var k = 1; k < corners.length; k += 1)
        _pieceOver(corners[k - 1], corners[k]),
    ];
  }

  _Piece _pieceOver(double from, double to) {
    // Read inside the stretch, clear of a step at either end.
    final near = from + (to - from) / 3;
    final far = from + 2 * (to - from) / 3;
    final atNear = _profileAt(near);
    final b = (_profileAt(far) - atNear) / (far - near);
    return (from: from, to: to, a: atNear - b * near, b: b);
  }

  /// The lower of the two ramps at [distance].
  double _profileAt(double distance) =>
      math.min(hardnessAt(distance), _ramp(distance, edgeHard, edgeRim));

  /// The hardness ramp at [distance].
  double hardnessAt(double distance) => _ramp(distance, hardRadius, radius);

  static double _ramp(double distance, double from, double to) {
    if (distance <= from) {
      return 1.0;
    }
    if (distance >= to) {
      return 0.0;
    }
    return (to - distance) / (to - from);
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
  double pileAt(double distance) => hardnessAt(distance - 0.5);
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
