/// BB-3 (R26 #11): per-setting input response curves.
///
/// A curve maps one normalized input (0..1) to a multiplier applied to one
/// brush setting's base value — Clip Studio's 影響元設定 model: a SHAPE (the
/// graph), a 最小値 and, on 傾き, a 最大値. `null` curve = the setting
/// ignores that input (no allocation on the plain hot path).
///
/// ↩️The floor used to live in the shape — "the legacy `min + (1 - min) *
/// pressure` formula IS the two-point line (0, min)-(1, 1)". That held until
/// the popup was rebuilt after Clip Studio's (F-176-Q2 「첨부한 클튜 팝업창
/// 최대한 참고해서 구현」, 2026-10-18), whose 最小値 is a slider beside the
/// graph: a floor folded into the points cannot be read back out of them, so
/// the slider would have had nothing to show. [minimum] is that slider.
library;

import 'dart:math' as math;

/// Which brush setting a curve drives.
///
/// [roundness] and [spacing] joined size, opacity, flow and hardness with
/// F-176-Q2 (「그래프 버튼이 붙는 설정도 넓힌다」) — Clip Studio's 厚さ and
/// 間隔 carry the same 影響元 as its size does.
enum BrushPressureTarget {
  size,
  opacity,
  flow,
  hardness,
  roundness,
  spacing,

  /// テクスチャ濃度 — Clip Studio gives it the same 影響元 as size. Under a
  /// multiplied paper it is how much of the paper shows, so a row that
  /// falls with pressure leaves a light touch grained and fills the valleys
  /// as the press grows — a pencil's grain filling as it darkens (F-456).
  /// Under the paper's height (`BrushTextureMode.height`) it is how deep the
  /// dab reaches into the paper instead.
  textureDensity,

  /// 絵の具量 and 絵の具濃度 — a mixing brush's load and the strength of
  /// what it lays, with the same 影響元 Clip Studio gives size (gouache card
  /// Q9 = a, 유저 2026-10-30 「필압 줄을 넣는다」): its 불투명 수채 · 투명
  /// 수채 · 구아슈 press their load from 0, so a light touch smears and a
  /// hard one lays the brush's own colour. Read per dab by the mixer
  /// (`BrushGroundColorMixer`), not carried on the dab.
  paintAmount,
  paintDensity;

  /// Whether a curve on this setting may go PAST its base — 傾き's 最大値.
  /// Clip Studio offers it where the base is not already the most there is
  /// (F-176-Q2): a size and a spacing grow, an opacity cannot pass 100%.
  bool get canPassItsBase => this == size || this == spacing;
}

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

/// An editable input→multiplier response: a shape drawn by control points,
/// laid between [minimum] and [maximum].
///
/// 🚨**THE POINTS PULL THE SHAPE; THEY DO NOT LIE ON IT** — Clip Studio's
/// graph (유저 F-456, 2026-10-23: 「클튜는 s자만드려면 두 포인트 찍어야하는
/// 방식」). The shape is the clamped quadratic B-spline over [points]: it
/// starts at the first and ends at the last, and between them it runs
/// through the middle of every inner edge of the line joining them, bent
/// towards each point it passes. One point bends it one way; an S takes
/// two. It stays in its points' hull, so in the unit square, and rises
/// wherever they rise; two points are the straight line between them.
///
/// ↩️It was a monotone cubic Hermite (Fritsch–Carlson) THROUGH the points,
/// which bent one point into an S. 📏Against Clip Studio's own drawing of
/// four of the user's graphs this is 0.010–0.017 off on average, 1–2 px of
/// its graph; the Hermite was 0.045–0.10.
class BrushPressureCurve {
  BrushPressureCurve(
    List<BrushCurvePoint> points, {
    this.minimum = 0.0,
    this.maximum = 1.0,
  }) : points = List.unmodifiable(points) {
    if (!maximum.isFinite || maximum < 1.0) {
      throw ArgumentError.value(
        maximum,
        'maximum',
        'BrushPressureCurve.maximum must be finite and at least 1.0.',
      );
    }
    if (!minimum.isFinite || minimum < 0.0 || minimum > 1.0) {
      throw ArgumentError.value(
        minimum,
        'minimum',
        'BrushPressureCurve.minimum must lie in [0, 1].',
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
  }

  /// The straight 1:1 response — what the old boolean toggle meant.
  factory BrushPressureCurve.identity({double maximum = 1.0}) =>
      BrushPressureCurve.linearFrom(0.0, maximum: maximum);

  /// The straight shape laid from [minimum] up — the old
  /// `min + (1 - min) * pressure` size response when [maximum] is 1.
  factory BrushPressureCurve.linearFrom(
    double minimum, {
    double maximum = 1.0,
  }) => BrushPressureCurve(
    const [BrushCurvePoint(0.0, 0.0), BrushCurvePoint(1.0, 1.0)],
    minimum: minimum.clamp(0.0, 1.0).toDouble(),
    maximum: maximum,
  );

  /// [BrushPressureCurve.identity] as a constant, for a default that has to
  /// be one — the pen's own response in `AppInputSettings` (F-480).
  static const BrushPressureCurve linear = BrushPressureCurve._linear();

  const BrushPressureCurve._linear()
    : points = const [BrushCurvePoint(0.0, 0.0), BrushCurvePoint(1.0, 1.0)],
      minimum = 0.0,
      maximum = 1.0;

  /// Ascending-x control points; first at x=0, last at x=1.
  final List<BrushCurvePoint> points;

  /// What no input at all gives, as a multiplier — Clip Studio's 最小値
  /// (0–100%, so 0.0–1.0 here). The response runs from here to [maximum] as
  /// the shape runs from 0 to 1, which is how Clip Studio's own panel reads
  /// a 傾き row of 最小値 100 · 最大値 500: upright draws at the base, laid
  /// flat at five times it.
  ///
  /// ⚠️0.0 — the default — is the old formula exactly (`shape * maximum`),
  /// so a curve that never had a floor of its own evaluates as it always did.
  final double minimum;

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

  /// The multiplier for [input] (clamped to [0, 1]): the shape laid between
  /// [minimum] and [maximum].
  double evaluate(double input) {
    final x = input.isFinite ? input.clamp(0.0, 1.0).toDouble() : 1.0;
    final shape = _shapeAt(x).clamp(0.0, 1.0).toDouble();
    if (minimum == 0.0) {
      return shape * maximum;
    }
    return minimum + (maximum - minimum) * shape;
  }

  /// The shape's height over [x], off the span that holds it: span `j` is
  /// the quadratic Bezier from the middle of edge `j - 1` (the first point,
  /// for the first) over point `j` to the middle of edge `j` (the last
  /// point, for the last).
  double _shapeAt(double x) {
    final last = points.length - 1;
    if (last == 1) {
      final from = points[0];
      final to = points[1];
      return from.y + (to.y - from.y) * (x - from.x) / (to.x - from.x);
    }
    var start = points[0];
    for (var j = 1; ; j += 1) {
      final pull = points[j];
      final next = points[j + 1];
      if (j + 1 == last) {
        return x >= next.x ? next.y : _bezierYAt(x, start, pull, next);
      }
      final end = BrushCurvePoint(
        (pull.x + next.x) / 2,
        (pull.y + next.y) / 2,
      );
      if (x <= end.x) {
        return _bezierYAt(x, start, pull, end);
      }
      start = end;
    }
  }

  /// Whether this is the plain 1:1 line (the migrated "toggle ON" shape).
  ///
  /// ⚠️A raised [maximum] or a [minimum] disqualifies it: the line may be
  /// 1:1 but the curve no longer means "the input scales the value from
  /// nothing up to its base", which is what every reader of this getter is
  /// asking.
  bool get isIdentity =>
      minimum == 0.0 &&
      maximum == 1.0 &&
      points.length == 2 &&
      points.first.y == 0.0 &&
      points.last.y == 1.0;

  /// The x,y pairs and — only when it is not the default — [maximum] as a
  /// single trailing value; a curve with a [minimum] is an object instead.
  ///
  /// ⚠️THE ODD TAIL IS THE ENCODING, and it is deliberate: [fromJson]'s pair
  /// loop already stops before a lone final element, so a curve at the
  /// default writes the exact same bytes it always did.
  ///
  /// 🚨THE OBJECT FORM IS FOR THE FLOOR ALONE (F-176-Q2, 2026-10-18). A list
  /// has one spare slot and the ceiling already holds it, so a floor cannot
  /// ride as a second tail without reading as a point. Every curve saved
  /// before floors existed is the list form and stays exactly that — the
  /// brush library is not renumbered (유저 2026-09-24: their own brushes are
  /// in it), so those files are read as they are, not migrated.
  Object toJson() {
    final pairs = [for (final point in points) ...[point.x, point.y]];
    if (minimum == 0.0) {
      return [...pairs, if (maximum != 1.0) maximum];
    }
    return {
      'points': pairs,
      'minimum': minimum,
      if (maximum != 1.0) 'maximum': maximum,
    };
  }

  /// Reads either form [toJson] writes.
  factory BrushPressureCurve.fromJson(Object? json) {
    if (json is Map) {
      return BrushPressureCurve(
        _pointsOf(json['points'] as List<dynamic>),
        minimum: (json['minimum'] as num?)?.toDouble() ?? 0.0,
        maximum: (json['maximum'] as num?)?.toDouble() ?? 1.0,
      );
    }
    final list = json! as List<dynamic>;
    return BrushPressureCurve(
      _pointsOf(list),
      maximum: list.length.isOdd ? (list.last as num).toDouble() : 1.0,
    );
  }

  static List<BrushCurvePoint> _pointsOf(List<dynamic> pairs) => [
    for (var i = 0; i + 1 < pairs.length; i += 2)
      BrushCurvePoint(
        (pairs[i] as num).toDouble(),
        (pairs[i + 1] as num).toDouble(),
      ),
  ];

  /// This curve with its floor and ceiling replaced — what the popup's
  /// 最小値 and 最大値 sliders write.
  BrushPressureCurve withRange({double? minimum, double? maximum}) =>
      BrushPressureCurve(
        points,
        minimum: minimum ?? this.minimum,
        maximum: maximum ?? this.maximum,
      );

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is! BrushPressureCurve ||
        other.points.length != points.length ||
        other.minimum != minimum ||
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
  int get hashCode => Object.hash(Object.hashAll(points), minimum, maximum);

  @override
  String toString() =>
      'BrushPressureCurve($points'
      '${minimum == 0.0 ? '' : ', min: $minimum'}'
      '${maximum == 1.0 ? '' : ', max: $maximum'})';
}

/// The height of the quadratic Bezier from [start] over [pull] to [end]
/// where it stands over [x]. Its x rises with its parameter t — the three
/// x's do — so one t answers: the root of `a t² + b t = x - start.x`, in
/// the form that stays exact where `a` vanishes.
double _bezierYAt(
  double x,
  BrushCurvePoint start,
  BrushCurvePoint pull,
  BrushCurvePoint end,
) {
  final a = start.x - 2 * pull.x + end.x;
  final b = 2 * (pull.x - start.x);
  final d = x - start.x;
  final root = math.sqrt(math.max(0.0, b * b + 4 * a * d));
  final t = (2 * d / (b + root)).clamp(0.0, 1.0);
  final u = 1 - t;
  return u * u * start.y + 2 * u * t * pull.y + t * t * end.y;
}
