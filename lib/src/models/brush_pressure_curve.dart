/// BB-3 (R26 #11): per-setting pen-pressure response curves.
///
/// A curve maps normalized input pressure (0..1) to a multiplier (0..1)
/// applied to one brush setting's base value — the CSP 筆圧設定 model.
/// `null` curve = the setting ignores pressure (no allocation on the
/// no-pressure hot path), replacing the old pressureSize/pressureOpacity
/// booleans. The old minimum-size floor is now simply the curve's left
/// endpoint: the legacy `min + (1 - min) * pressure` formula IS the
/// two-point line (0, min)-(1, 1).
library;

import 'dart:math' as math;

/// Which brush setting a pressure curve drives (the v1 four).
enum BrushPressureTarget { size, opacity, flow, hardness }

/// One control point of a [BrushPressureCurve]; both coordinates in [0, 1].
class BrushCurvePoint {
  const BrushCurvePoint(this.x, this.y);

  final double x;
  final double y;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BrushCurvePoint && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'BrushCurvePoint($x, $y)';
}

/// An editable pressure→multiplier curve through control points.
///
/// Interpolation is monotone cubic Hermite (Fritsch–Carlson): smooth like
/// the CSP editor's spline, but it never overshoots the control points'
/// range — the multiplier stays inside [0, 1] by construction — and a
/// two-point curve evaluates as the EXACT straight line, so migrated
/// legacy toggles reproduce the old linear response bit-for-bit.
class BrushPressureCurve {
  BrushPressureCurve(List<BrushCurvePoint> points, {this.maximum = 1.0})
    : points = List.unmodifiable(points) {
    if (!maximum.isFinite || maximum < 1.0) {
      throw ArgumentError.value(
        maximum,
        'maximum',
        'BrushPressureCurve.maximum must be finite and at least 1.0.',
      );
    }
    if (points.length < 2) {
      throw ArgumentError.value(
        points,
        'points',
        'BrushPressureCurve needs at least 2 control points.',
      );
    }
    if (points.first.x != 0.0 || points.last.x != 1.0) {
      throw ArgumentError.value(
        points,
        'points',
        'BrushPressureCurve endpoints must sit at x=0 and x=1.',
      );
    }
    for (var i = 0; i < points.length; i += 1) {
      final point = points[i];
      if (!point.x.isFinite ||
          !point.y.isFinite ||
          point.x < 0.0 ||
          point.x > 1.0 ||
          point.y < 0.0 ||
          point.y > 1.0) {
        throw ArgumentError.value(
          points,
          'points',
          'BrushPressureCurve points must lie in the unit square.',
        );
      }
      if (i > 0 && point.x <= points[i - 1].x) {
        throw ArgumentError.value(
          points,
          'points',
          'BrushPressureCurve points must have strictly increasing x.',
        );
      }
    }
    _tangents = _monotoneTangents(this.points);
  }

  /// The straight 1:1 response — what the old boolean toggle meant.
  factory BrushPressureCurve.identity({double maximum = 1.0}) =>
      BrushPressureCurve(const [
        BrushCurvePoint(0.0, 0.0),
        BrushCurvePoint(1.0, 1.0),
      ], maximum: maximum);

  /// The legacy minimum-floor line (0, [minimum])-(1, 1): the old
  /// `min + (1 - min) * pressure` size response.
  factory BrushPressureCurve.linearFrom(double minimum, {double maximum = 1.0}) =>
      BrushPressureCurve([
        BrushCurvePoint(0.0, minimum.clamp(0.0, 1.0).toDouble()),
        const BrushCurvePoint(1.0, 1.0),
      ], maximum: maximum);

  /// Ascending-x control points; first at x=0, last at x=1.
  final List<BrushCurvePoint> points;

  /// How far past the base value a full input may push, as a multiplier —
  /// Clip Studio's 最大値, which it offers on 傾き alone (100–1000%, so
  /// 1.0–10.0 here). 1.0 is "never exceeds the base", which is what every
  /// curve meant before this existed.
  ///
  /// ⛔IT CANNOT BE A CONTROL POINT. [points] are confined to the unit square
  /// and [evaluate] clamps the shape to [0, 1] besides, so a curve simply has
  /// no way to say "300%". The shape and the ceiling are two facts.
  ///
  /// ⚠️Only SIZE can actually show a value above 1.0: `applyBrushInputDynamics`
  /// clamps opacity, flow and hardness to [0, 1] because there is no such
  /// thing as 300% opacity. That is not a rule about this field — it is a
  /// rule about those three quantities, and it is written where they are
  /// clamped.
  final double maximum;

  late final List<double> _tangents;

  /// The multiplier for [pressure] (input clamped to [0, 1]).
  double evaluate(double pressure) {
    final x = pressure.isFinite ? pressure.clamp(0.0, 1.0).toDouble() : 1.0;
    var i = points.length - 2;
    for (var k = 0; k < points.length - 1; k += 1) {
      if (x <= points[k + 1].x) {
        i = k;
        break;
      }
    }
    final p0 = points[i];
    final p1 = points[i + 1];
    final h = p1.x - p0.x;
    final t = (x - p0.x) / h;
    final t2 = t * t;
    final t3 = t2 * t;
    final value =
        (2 * t3 - 3 * t2 + 1) * p0.y +
        (t3 - 2 * t2 + t) * h * _tangents[i] +
        (-2 * t3 + 3 * t2) * p1.y +
        (t3 - t2) * h * _tangents[i + 1];
    return value.clamp(0.0, 1.0).toDouble() * maximum;
  }

  /// Whether this is the plain 1:1 line (the migrated "toggle ON" shape).
  ///
  /// ⚠️A raised [maximum] disqualifies it: the line may be 1:1 but the curve
  /// no longer means "pressure scales the value up to its base and no
  /// further", which is what every reader of this getter is asking.
  bool get isIdentity =>
      maximum == 1.0 &&
      points.length == 2 &&
      points.first.y == 0.0 &&
      points.last.y == 1.0;

  /// The x,y pairs, and — only when it is not the default — [maximum] as a
  /// single trailing value.
  ///
  /// ⚠️THE ODD TAIL IS THE ENCODING, and it is deliberate: [fromJson]'s pair
  /// loop already stops before a lone final element, so a curve saved by a
  /// build that knows about maximums still loads on one that does not (it
  /// reads the shape and ignores the ceiling) — and a curve at the default
  /// writes the exact same bytes it always did.
  List<double> toJson() => [
    for (final point in points) ...[point.x, point.y],
    if (maximum != 1.0) maximum,
  ];

  factory BrushPressureCurve.fromJson(List<dynamic> json) {
    return BrushPressureCurve(
      [
        for (var i = 0; i + 1 < json.length; i += 2)
          BrushCurvePoint(
            (json[i] as num).toDouble(),
            (json[i + 1] as num).toDouble(),
          ),
      ],
      maximum: json.length.isOdd ? (json.last as num).toDouble() : 1.0,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is! BrushPressureCurve ||
        other.points.length != points.length ||
        other.maximum != maximum) {
      return false;
    }
    for (var i = 0; i < points.length; i += 1) {
      if (other.points[i] != points[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(Object.hashAll(points), maximum);

  @override
  String toString() =>
      'BrushPressureCurve($points${maximum == 1.0 ? '' : ', max: $maximum'})';
}

/// Fritsch–Carlson monotone tangents: interior slopes average the
/// neighboring secants (zero across a sign change), then the (α, β)
/// circle limiter caps them so no segment overshoots its endpoints.
List<double> _monotoneTangents(List<BrushCurvePoint> points) {
  final n = points.length;
  final deltas = List<double>.generate(
    n - 1,
    (i) => (points[i + 1].y - points[i].y) / (points[i + 1].x - points[i].x),
  );
  final tangents = List<double>.filled(n, 0.0);
  tangents[0] = deltas[0];
  tangents[n - 1] = deltas[n - 2];
  for (var i = 1; i < n - 1; i += 1) {
    final previous = deltas[i - 1];
    final next = deltas[i];
    tangents[i] = previous * next <= 0.0 ? 0.0 : (previous + next) / 2.0;
  }
  for (var i = 0; i < n - 1; i += 1) {
    final delta = deltas[i];
    if (delta == 0.0) {
      tangents[i] = 0.0;
      tangents[i + 1] = 0.0;
      continue;
    }
    final alpha = tangents[i] / delta;
    final beta = tangents[i + 1] / delta;
    final magnitude = alpha * alpha + beta * beta;
    if (magnitude > 9.0) {
      final tau = 3.0 / math.sqrt(magnitude);
      tangents[i] = tau * alpha * delta;
      tangents[i + 1] = tau * beta * delta;
    }
  }
  return tangents;
}
