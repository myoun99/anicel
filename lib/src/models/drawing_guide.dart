import 'dart:math' as math;

import '../core/collection_equality.dart';
import 'canvas_point.dart';
import 'string_id.dart';

/// Stable identity of one guide instance on a cut. The active-symmetry
/// pointer and the undo commands both name guides by this, so reordering
/// the list never re-points an edit at the wrong guide.
final class GuideId extends StringId {
  const GuideId(super.value);

  factory GuideId.fromJson(Map<String, dynamic> json) =>
      GuideId(json['value'] as String);
}

/// The guide families. The library panel groups by this, and the two act
/// DIFFERENTLY on input: symmetry REPLICATES a stroke, perspective
/// CONSTRAINS one. Everything else about them is shared.
enum GuideKind {
  symmetry('symmetry'),
  perspective('perspective');

  const GuideKind(this.jsonValue);

  final String jsonValue;

  static GuideKind fromJson(Object? json) {
    for (final kind in GuideKind.values) {
      if (json == kind.jsonValue) {
        return kind;
      }
    }
    throw ArgumentError.value(
      json,
      'kind',
      'Guide kind must be one of '
          '${GuideKind.values.map((kind) => '"${kind.jsonValue}"').join(', ')}.',
    );
  }
}

/// A point in the projective plane: `(x, y, w)`.
///
/// `w != 0` is the ordinary canvas point `(x/w, y/w)`; **`w == 0` is a point
/// at INFINITY** — a pure direction. Vanishing points need both cases (a
/// one-point perspective's horizontal family converges nowhere), and
/// [CanvasPoint] cannot express the second: it rejects non-finite
/// coordinates by construction. Carrying `w` instead of a nullable point
/// keeps every consumer on ONE formula — see [directionFrom].
class HomogeneousPoint {
  const HomogeneousPoint(this.x, this.y, this.w);

  /// The finite point `(x, y)`.
  const HomogeneousPoint.at(this.x, this.y) : w = 1;

  /// The point at infinity in direction `(dx, dy)` — parallel lines.
  const HomogeneousPoint.towards(this.x, this.y) : w = 0;

  final double x;
  final double y;
  final double w;

  bool get isInfinite => w == 0;

  /// The finite position, or null at infinity.
  CanvasPoint? get position {
    if (w == 0) return null;
    final px = x / w;
    final py = y / w;
    if (!px.isFinite || !py.isFinite) return null;
    return CanvasPoint(x: px, y: py);
  }

  /// The unit direction from [from] towards this point — the ONE formula
  /// both cases share.
  ///
  /// `(x - from.x·w, y - from.y·w)` is `(x, y) - from` when `w == 1` and the
  /// bare direction `(x, y)` when `w == 0`, so a vanishing point that ran off
  /// to infinity needs no branch here. Null when the two coincide (there is
  /// no ray through a point and itself).
  ({double dx, double dy})? directionFrom(CanvasPoint from) {
    final dx = x - from.x * w;
    final dy = y - from.y * w;
    // Scale by the larger term before squaring: a vanishing point a few
    // million canvas units away would otherwise overflow on its way to a
    // unit vector.
    final scale = math.max(dx.abs(), dy.abs());
    if (scale == 0 || !scale.isFinite) return null;
    final sx = dx / scale;
    final sy = dy / scale;
    final length = math.sqrt(sx * sx + sy * sy);
    if (length == 0 || !length.isFinite) return null;
    return (dx: sx / length, dy: sy / length);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HomogeneousPoint && other.x == x && other.y == y && other.w == w;

  @override
  int get hashCode => Object.hash(x, y, w);

  @override
  String toString() => 'HomogeneousPoint($x, $y, $w)';
}

/// An oriented line through [origin] at [angleDegrees] (clockwise-positive,
/// matching the transform lanes' rotation sign). The symmetry axis and the
/// perspective eye level are the same shape, so they get the same handles
/// and the same math.
class GuideAxis {
  GuideAxis({required this.origin, required this.angleDegrees});

  final CanvasPoint origin;
  final double angleDegrees;

  GuideAxis copyWith({CanvasPoint? origin, double? angleDegrees}) => GuideAxis(
    origin: origin ?? this.origin,
    angleDegrees: angleDegrees ?? this.angleDegrees,
  );

  Map<String, dynamic> toJson() => {
    'origin': origin.toJson(),
    'angle': angleDegrees,
  };

  factory GuideAxis.fromJson(Map<String, dynamic> json) => GuideAxis(
    origin: CanvasPoint.fromJson(json['origin'] as Map<String, dynamic>),
    angleDegrees: (json['angle'] as num).toDouble(),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GuideAxis &&
          other.origin == origin &&
          other.angleDegrees == angleDegrees;

  @override
  int get hashCode => Object.hash(origin, angleDegrees);

  @override
  String toString() => 'GuideAxis($origin, $angleDegrees°)';
}

/// A finite segment the user dragged, read as the INFINITE line through its
/// two ends. Two of these define a vanishing point by intersection.
class GuideLine {
  GuideLine({required this.a, required this.b});

  final CanvasPoint a;
  final CanvasPoint b;

  /// The line in homogeneous coordinates: `ã × b̃`, the triple `(A, B, C)`
  /// of `Ax + By + C = 0`.
  ({double a, double b, double c}) get coefficients {
    final start = a;
    final end = b;
    return (
      a: start.y - end.y,
      b: end.x - start.x,
      c: start.x * end.y - end.x * start.y,
    );
  }

  GuideLine copyWith({CanvasPoint? a, CanvasPoint? b}) =>
      GuideLine(a: a ?? this.a, b: b ?? this.b);

  Map<String, dynamic> toJson() => {'a': a.toJson(), 'b': b.toJson()};

  factory GuideLine.fromJson(Map<String, dynamic> json) => GuideLine(
    a: CanvasPoint.fromJson(json['a'] as Map<String, dynamic>),
    b: CanvasPoint.fromJson(json['b'] as Map<String, dynamic>),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is GuideLine && other.a == a && other.b == b;

  @override
  int get hashCode => Object.hash(a, b);

  @override
  String toString() => 'GuideLine($a → $b)';
}

/// Where a family of parallel lines converges.
///
/// Three variants, and a guide's point is in exactly ONE of them at a time —
/// this is a sum, not two fields to keep in sync. [resolve] is the single
/// derivation every consumer calls; nothing else reads the variants.
///
/// * [VanishingPointAt] — the user dropped a point.
/// * [VanishingPointTowards] — a pure direction, the point at infinity. This
///   is what "the vertical perspective is always vertical" means, and it has
///   to be first-class: expressing it as "two exactly parallel lines" would
///   put a hard requirement on floating-point equality.
/// * [VanishingPointFromLines] — the intersection of two lines the user drew
///   (Clip Studio's affordance). Parallel lines simply resolve to `w == 0`,
///   so the infinite case falls out with no tolerance to tune.
sealed class VanishingPoint {
  const VanishingPoint();

  HomogeneousPoint resolve();

  Map<String, dynamic> toJson();

  static VanishingPoint fromJson(Map<String, dynamic> json) {
    final type = json['type'];
    return switch (type) {
      'at' => VanishingPointAt(
        CanvasPoint.fromJson(json['point'] as Map<String, dynamic>),
      ),
      'towards' => VanishingPointTowards(
        dx: (json['dx'] as num).toDouble(),
        dy: (json['dy'] as num).toDouble(),
      ),
      'lines' => VanishingPointFromLines(
        GuideLine.fromJson(json['first'] as Map<String, dynamic>),
        GuideLine.fromJson(json['second'] as Map<String, dynamic>),
      ),
      _ => throw ArgumentError.value(
        type,
        'type',
        'Vanishing point type must be "at", "towards" or "lines".',
      ),
    };
  }
}

/// A vanishing point the user placed directly.
final class VanishingPointAt extends VanishingPoint {
  const VanishingPointAt(this.point);

  final CanvasPoint point;

  @override
  HomogeneousPoint resolve() => HomogeneousPoint.at(point.x, point.y);

  @override
  Map<String, dynamic> toJson() => {'type': 'at', 'point': point.toJson()};

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VanishingPointAt && other.point == point;

  @override
  int get hashCode => point.hashCode;

  @override
  String toString() => 'VanishingPointAt($point)';
}

/// A vanishing point at infinity: the family stays parallel, running along
/// `(dx, dy)`. A vertical family is `(0, 1)` exactly.
final class VanishingPointTowards extends VanishingPoint {
  VanishingPointTowards({required this.dx, required this.dy}) {
    if (!dx.isFinite || !dy.isFinite) {
      throw ArgumentError('A vanishing direction must be finite.');
    }
    if (dx == 0 && dy == 0) {
      throw ArgumentError('A vanishing direction must not be zero-length.');
    }
  }

  final double dx;
  final double dy;

  @override
  HomogeneousPoint resolve() => HomogeneousPoint.towards(dx, dy);

  @override
  Map<String, dynamic> toJson() => {'type': 'towards', 'dx': dx, 'dy': dy};

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VanishingPointTowards && other.dx == dx && other.dy == dy;

  @override
  int get hashCode => Object.hash(dx, dy);

  @override
  String toString() => 'VanishingPointTowards($dx, $dy)';
}

/// A vanishing point defined as where two drawn lines meet. Keeping the
/// lines (rather than baking the crossing into a point) is what lets the
/// user grab a line later and slide the convergence.
final class VanishingPointFromLines extends VanishingPoint {
  const VanishingPointFromLines(this.first, this.second);

  final GuideLine first;
  final GuideLine second;

  @override
  HomogeneousPoint resolve() {
    final l1 = first.coefficients;
    final l2 = second.coefficients;
    // The cross product of two homogeneous lines is their meeting point;
    // parallel lines yield w == 0, which is exactly the right answer.
    return HomogeneousPoint(
      l1.b * l2.c - l1.c * l2.b,
      l1.c * l2.a - l1.a * l2.c,
      l1.a * l2.b - l1.b * l2.a,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': 'lines',
    'first': first.toJson(),
    'second': second.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VanishingPointFromLines &&
          other.first == first &&
          other.second == second;

  @override
  int get hashCode => Object.hash(first, second);

  @override
  String toString() => 'VanishingPointFromLines($first, $second)';
}

/// The largest symmetry count. A stroke costs one commit per copy, so the
/// ceiling is a performance contract as much as a UI range — kaleidoscope
/// work never wants more, and the preview has to stay live at the top of
/// the range on a debug build.
const int maxSymmetryLineCount = 16;

/// The shape of one guide. Two families, one list, one overlay.
sealed class GuideShape {
  const GuideShape();

  GuideKind get kind;

  Map<String, dynamic> toJson();

  static GuideShape fromJson(Map<String, dynamic> json) {
    return switch (GuideKind.fromJson(json['kind'])) {
      GuideKind.symmetry => SymmetryShape.fromJson(json),
      GuideKind.perspective => PerspectiveShape.fromJson(json),
    };
  }
}

/// Symmetry: the stroke is COPIED [lineCount] times around [axis].
///
/// [lineCount] counts the copies the canvas ends up with, the original
/// included — Clip Studio's "선 수", so 2 with [lineSymmetry] on is the plain
/// left/right mirror everybody reaches for first.
///
/// * [lineSymmetry] on — the copies alternate handedness (a true kaleidoscope:
///   the dihedral group generated by [axis] and a rotation). Reflections come
///   in pairs, so the count is kept EVEN.
/// * [lineSymmetry] off — the copies are pure rotations by `360/lineCount`.
///   Nothing is mirrored here, which is exactly why this feature is not
///   called "mirror".
final class SymmetryShape extends GuideShape {
  SymmetryShape({
    required this.axis,
    this.lineCount = 2,
    this.lineSymmetry = true,
  }) {
    if (lineCount < 2 || lineCount > maxSymmetryLineCount) {
      throw ArgumentError.value(
        lineCount,
        'lineCount',
        'Symmetry line count must be 2…$maxSymmetryLineCount.',
      );
    }
    if (lineSymmetry && lineCount.isOdd) {
      throw ArgumentError.value(
        lineCount,
        'lineCount',
        'Line symmetry mirrors in pairs, so the count must be even.',
      );
    }
  }

  final GuideAxis axis;
  final int lineCount;
  final bool lineSymmetry;

  @override
  GuideKind get kind => GuideKind.symmetry;

  SymmetryShape copyWith({
    GuideAxis? axis,
    int? lineCount,
    bool? lineSymmetry,
  }) {
    final mirrors = lineSymmetry ?? this.lineSymmetry;
    var count = lineCount ?? this.lineCount;
    // Turning line symmetry ON from an odd count has to land somewhere; the
    // nearest even count below keeps the change from ever exceeding the max.
    if (mirrors && count.isOdd) {
      count = count > 2 ? count - 1 : 2;
    }
    return SymmetryShape(
      axis: axis ?? this.axis,
      lineCount: count,
      lineSymmetry: mirrors,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'kind': kind.jsonValue,
    'axis': axis.toJson(),
    'lineCount': lineCount,
    'lineSymmetry': lineSymmetry,
  };

  factory SymmetryShape.fromJson(Map<String, dynamic> json) => SymmetryShape(
    axis: GuideAxis.fromJson(json['axis'] as Map<String, dynamic>),
    lineCount: json['lineCount'] as int? ?? 2,
    lineSymmetry: json['lineSymmetry'] as bool? ?? true,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SymmetryShape &&
          other.axis == axis &&
          other.lineCount == lineCount &&
          other.lineSymmetry == lineSymmetry;

  @override
  int get hashCode => Object.hash(axis, lineCount, lineSymmetry);

  @override
  String toString() =>
      'SymmetryShape($axis, ×$lineCount, mirrored: $lineSymmetry)';
}

/// Perspective: strokes are CONSTRAINED to a ray towards one of the
/// [vanishingPoints].
///
/// [snapEnabled] is per guide on purpose — several perspective guides may
/// snap at once (two buildings in one background each want their own pair of
/// vanishing points), and the way to keep the candidate rays from getting
/// too crowded to predict is to switch off the guides you are not drawing.
///
/// [constrainToEyeLevel] holds the vanishing points ON [eyeLevel], which is
/// what a shared horizon means physically. It is a default, not a law —
/// deliberately-broken horizons are a real drawing.
final class PerspectiveShape extends GuideShape {
  PerspectiveShape({
    required List<VanishingPoint> vanishingPoints,
    required this.eyeLevel,
    this.snapEnabled = true,
    this.eyeLevelVisible = true,
    this.constrainToEyeLevel = true,
  }) : vanishingPoints = List.unmodifiable(vanishingPoints) {
    if (vanishingPoints.isEmpty || vanishingPoints.length > 3) {
      throw ArgumentError.value(
        vanishingPoints.length,
        'vanishingPoints',
        'A perspective guide carries one to three vanishing points.',
      );
    }
  }

  final List<VanishingPoint> vanishingPoints;
  final GuideAxis eyeLevel;
  final bool snapEnabled;
  final bool eyeLevelVisible;
  final bool constrainToEyeLevel;

  @override
  GuideKind get kind => GuideKind.perspective;

  PerspectiveShape copyWith({
    List<VanishingPoint>? vanishingPoints,
    GuideAxis? eyeLevel,
    bool? snapEnabled,
    bool? eyeLevelVisible,
    bool? constrainToEyeLevel,
  }) => PerspectiveShape(
    vanishingPoints: vanishingPoints ?? this.vanishingPoints,
    eyeLevel: eyeLevel ?? this.eyeLevel,
    snapEnabled: snapEnabled ?? this.snapEnabled,
    eyeLevelVisible: eyeLevelVisible ?? this.eyeLevelVisible,
    constrainToEyeLevel: constrainToEyeLevel ?? this.constrainToEyeLevel,
  );

  @override
  Map<String, dynamic> toJson() => {
    'kind': kind.jsonValue,
    'vanishingPoints': [
      for (final point in vanishingPoints) point.toJson(),
    ],
    'eyeLevel': eyeLevel.toJson(),
    'snapEnabled': snapEnabled,
    'eyeLevelVisible': eyeLevelVisible,
    'constrainToEyeLevel': constrainToEyeLevel,
  };

  factory PerspectiveShape.fromJson(Map<String, dynamic> json) =>
      PerspectiveShape(
        vanishingPoints: [
          for (final point in json['vanishingPoints'] as List<dynamic>)
            VanishingPoint.fromJson(point as Map<String, dynamic>),
        ],
        eyeLevel: GuideAxis.fromJson(json['eyeLevel'] as Map<String, dynamic>),
        snapEnabled: json['snapEnabled'] as bool? ?? true,
        eyeLevelVisible: json['eyeLevelVisible'] as bool? ?? true,
        constrainToEyeLevel: json['constrainToEyeLevel'] as bool? ?? true,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PerspectiveShape &&
          listEquals(other.vanishingPoints, vanishingPoints) &&
          other.eyeLevel == eyeLevel &&
          other.snapEnabled == snapEnabled &&
          other.eyeLevelVisible == eyeLevelVisible &&
          other.constrainToEyeLevel == constrainToEyeLevel;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(vanishingPoints),
    eyeLevel,
    snapEnabled,
    eyeLevelVisible,
    constrainToEyeLevel,
  );

  @override
  String toString() =>
      'PerspectiveShape(${vanishingPoints.length} VP, snap: $snapEnabled)';
}

/// One guide a cut owns.
///
/// Guides belong to the CUT, not to a layer or the viewport: an axis pinned
/// to the viewport would slide off the drawing the moment you zoom, and one
/// pinned to a layer would have to be redrawn on every new cel. Cut-owned
/// means it survives frame changes and follows the background it was set up
/// for — and it is why 겸용 cuts, which show ONE physical cel in two places,
/// must carry the same guides.
///
/// [visible] and the shape's own act-on-input switch are separate on
/// purpose: a guide can be drawn without steering the brush.
class DrawingGuide {
  DrawingGuide({
    required this.id,
    required this.name,
    required this.shape,
    this.visible = true,
  });

  final GuideId id;
  final String name;
  final GuideShape shape;
  final bool visible;

  GuideKind get kind => shape.kind;

  DrawingGuide copyWith({String? name, GuideShape? shape, bool? visible}) =>
      DrawingGuide(
        id: id,
        name: name ?? this.name,
        shape: shape ?? this.shape,
        visible: visible ?? this.visible,
      );

  Map<String, dynamic> toJson() => {
    'id': id.toJson(),
    'name': name,
    'shape': shape.toJson(),
    'visible': visible,
  };

  factory DrawingGuide.fromJson(Map<String, dynamic> json) => DrawingGuide(
    id: GuideId.fromJson(json['id'] as Map<String, dynamic>),
    name: json['name'] as String,
    shape: GuideShape.fromJson(json['shape'] as Map<String, dynamic>),
    visible: json['visible'] as bool? ?? true,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DrawingGuide &&
          other.id == id &&
          other.name == name &&
          other.shape == shape &&
          other.visible == visible;

  @override
  int get hashCode => Object.hash(id, name, shape, visible);

  @override
  String toString() => 'DrawingGuide($id, $name, $shape)';
}

/// A cut's guides plus WHICH symmetry guide is doing the replicating.
///
/// Several symmetry guides can be kept around, but only one may act. That is
/// not a UI simplification: two mirror axes generate rotations by twice the
/// angle between them, and unless that angle divides π the group never
/// closes — the copies would multiply without end. Perspective has no such
/// trouble (it picks among candidate rays rather than multiplying output), so
/// its guides switch on and off independently, inside each shape.
class CutGuides {
  CutGuides({List<DrawingGuide> guides = const [], this.activeSymmetryId})
    : guides = List.unmodifiable(guides) {
    if (activeSymmetryId != null) {
      final active = guides.where((guide) => guide.id == activeSymmetryId);
      if (active.isEmpty) {
        throw ArgumentError.value(
          activeSymmetryId,
          'activeSymmetryId',
          'The active symmetry guide must be in the list.',
        );
      }
      if (active.first.kind != GuideKind.symmetry) {
        throw ArgumentError.value(
          activeSymmetryId,
          'activeSymmetryId',
          'The active symmetry guide must be a symmetry guide.',
        );
      }
    }
  }

  static final CutGuides empty = CutGuides();

  final List<DrawingGuide> guides;
  final GuideId? activeSymmetryId;

  bool get isEmpty => guides.isEmpty;
  bool get isNotEmpty => guides.isNotEmpty;

  Iterable<DrawingGuide> get symmetryGuides =>
      guides.where((guide) => guide.kind == GuideKind.symmetry);

  Iterable<DrawingGuide> get perspectiveGuides =>
      guides.where((guide) => guide.kind == GuideKind.perspective);

  DrawingGuide? guideFor(GuideId id) {
    for (final guide in guides) {
      if (guide.id == id) return guide;
    }
    return null;
  }

  /// The symmetry that replicates strokes right now, or null when none is
  /// chosen. Visibility does not gate it — a guide can steer the brush while
  /// its drawing is hidden, the same way perspective snapping does.
  SymmetryShape? get actingSymmetry {
    final id = activeSymmetryId;
    if (id == null) return null;
    final guide = guideFor(id);
    final shape = guide?.shape;
    return shape is SymmetryShape ? shape : null;
  }

  /// The perspective guides whose snapping is switched on, in list order —
  /// the order that breaks ties between equally-close candidate rays, so
  /// the same gesture always picks the same one.
  Iterable<PerspectiveShape> get snappingPerspectives sync* {
    for (final guide in guides) {
      final shape = guide.shape;
      if (shape is PerspectiveShape && shape.snapEnabled) {
        yield shape;
      }
    }
  }

  CutGuides copyWith({
    List<DrawingGuide>? guides,
    GuideId? activeSymmetryId,
    bool clearActiveSymmetry = false,
  }) {
    final nextGuides = guides ?? this.guides;
    final nextActive = clearActiveSymmetry
        ? null
        : (activeSymmetryId ?? this.activeSymmetryId);
    // A list edit that drops the acting guide clears the pointer instead of
    // dangling — the constructor's invariant would otherwise throw on an
    // ordinary delete.
    final stillThere =
        nextActive != null &&
        nextGuides.any(
          (guide) =>
              guide.id == nextActive && guide.kind == GuideKind.symmetry,
        );
    return CutGuides(
      guides: nextGuides,
      activeSymmetryId: stillThere ? nextActive : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'guides': [for (final guide in guides) guide.toJson()],
    if (activeSymmetryId != null) 'activeSymmetry': activeSymmetryId!.toJson(),
  };

  factory CutGuides.fromJson(Map<String, dynamic> json) {
    final guides = [
      for (final guide in json['guides'] as List<dynamic>? ?? const [])
        DrawingGuide.fromJson(guide as Map<String, dynamic>),
    ];
    final activeJson = json['activeSymmetry'];
    final active = activeJson == null
        ? null
        : GuideId.fromJson(activeJson as Map<String, dynamic>);
    // Tolerate a stale pointer rather than refusing to open the file: a
    // guide deleted by an older build is a dangling id, not a corrupt cut.
    final valid =
        active != null &&
        guides.any(
          (guide) => guide.id == active && guide.kind == GuideKind.symmetry,
        );
    return CutGuides(guides: guides, activeSymmetryId: valid ? active : null);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CutGuides &&
          listEquals(other.guides, guides) &&
          other.activeSymmetryId == activeSymmetryId;

  @override
  int get hashCode => Object.hash(Object.hashAll(guides), activeSymmetryId);

  @override
  String toString() =>
      'CutGuides(${guides.length} guides, active: $activeSymmetryId)';
}
