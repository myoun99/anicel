import 'dart:math' as math;

import '../models/canvas_point.dart';
import '../models/drawing_guide.dart';

/// A 2-D affine map, `[a c tx; b d ty]` — the shape a symmetry copy takes.
///
/// Position is the ONLY thing a guide transforms. Stamp angle, tip
/// direction and velocity all fall out of the transformed points
/// downstream, which is the reason guides act on INPUT rather than on the
/// rasterised result: a mirrored stroke is a stroke that was drawn
/// mirrored, not a picture that was flipped afterwards.
class GuideTransform {
  const GuideTransform(this.a, this.b, this.c, this.d, this.tx, this.ty);

  const GuideTransform.identity() : this(1, 0, 0, 1, 0, 0);

  final double a;
  final double b;
  final double c;
  final double d;
  final double tx;
  final double ty;

  bool get isIdentity =>
      a == 1 && b == 0 && c == 0 && d == 1 && tx == 0 && ty == 0;

  /// Whether this copy is a REFLECTION rather than a rotation — the sign of
  /// the determinant. Asymmetric brush tips read this to know they are
  /// drawing left-handed.
  bool get flipsHandedness => a * d - b * c < 0;

  CanvasPoint apply(CanvasPoint point) => CanvasPoint(
    x: a * point.x + c * point.y + tx,
    y: b * point.x + d * point.y + ty,
  );

  /// A [GuideAxis] angle after this map.
  ///
  /// An axis points along `(cos φ, sin φ)` — the plain canvas convention,
  /// unlike a dab's tip angle, which is measured the other way round. Two
  /// methods rather than one flag: the two conventions are a standing trap
  /// and naming them apart is what keeps them straight.
  double mapAxisAngleDegrees(double angleDegrees) {
    final radians = angleDegrees * math.pi / 180;
    final dirX = math.cos(radians);
    final dirY = math.sin(radians);
    final mappedX = a * dirX + c * dirY;
    final mappedY = b * dirX + d * dirY;
    if (mappedX == 0 && mappedY == 0) return angleDegrees;
    return math.atan2(mappedY, mappedX) * 180 / math.pi;
  }

  /// A direction (not a position) under this map, renormalised. Null when
  /// the map collapses it.
  ({double dx, double dy})? mapDirection(double dx, double dy) {
    final mappedX = a * dx + c * dy;
    final mappedY = b * dx + d * dy;
    final scale = math.max(mappedX.abs(), mappedY.abs());
    if (scale == 0 || !scale.isFinite) return null;
    final sx = mappedX / scale;
    final sy = mappedY / scale;
    final length = math.sqrt(sx * sx + sy * sy);
    if (length == 0 || !length.isFinite) return null;
    return (dx: sx / length, dy: sy / length);
  }

  /// A brush dab's tip angle after this map — the tip turns with its copy.
  ///
  /// `BrushDab.angleDegrees` is the VISUAL counter-clockwise rotation of the
  /// tip's major axis, and canvas coordinates run y-down, so the axis points
  /// along `(cos α, −sin α)`. Mapping that direction and reading the angle
  /// back covers rotations and reflections with one rule — the alternative
  /// is a sign case per transform kind, which is where this sort of thing
  /// usually goes wrong.
  double mapTipAngleDegrees(double angleDegrees) {
    final radians = angleDegrees * math.pi / 180;
    final axisX = math.cos(radians);
    final axisY = -math.sin(radians);
    final mappedX = a * axisX + c * axisY;
    final mappedY = b * axisX + d * axisY;
    if (mappedX == 0 && mappedY == 0) return angleDegrees;
    return -math.atan2(mappedY, mappedX) * 180 / math.pi;
  }

  /// `this ∘ other` — apply [other] first.
  GuideTransform compose(GuideTransform other) => GuideTransform(
    a * other.a + c * other.b,
    b * other.a + d * other.b,
    a * other.c + c * other.d,
    b * other.c + d * other.d,
    a * other.tx + c * other.ty + tx,
    b * other.tx + d * other.ty + ty,
  );

  /// A rotation of [degrees] (clockwise-positive, matching the transform
  /// lanes) about [origin].
  factory GuideTransform.rotation(CanvasPoint origin, double degrees) {
    final radians = degrees * math.pi / 180;
    final cos = math.cos(radians);
    final sin = math.sin(radians);
    return GuideTransform(
      cos,
      sin,
      -sin,
      cos,
      origin.x - cos * origin.x + sin * origin.y,
      origin.y - sin * origin.x - cos * origin.y,
    );
  }

  /// A reflection across the line through [origin] at [degrees].
  factory GuideTransform.reflection(CanvasPoint origin, double degrees) {
    final radians = degrees * math.pi / 180;
    final cos2 = math.cos(2 * radians);
    final sin2 = math.sin(2 * radians);
    return GuideTransform(
      cos2,
      sin2,
      sin2,
      -cos2,
      origin.x - cos2 * origin.x - sin2 * origin.y,
      origin.y - sin2 * origin.x + cos2 * origin.y,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GuideTransform &&
          other.a == a &&
          other.b == b &&
          other.c == c &&
          other.d == d &&
          other.tx == tx &&
          other.ty == ty;

  @override
  int get hashCode => Object.hash(a, b, c, d, tx, ty);

  @override
  String toString() => 'GuideTransform([$a $c $tx; $b $d $ty])';
}

/// Every copy a symmetry guide makes of one stroke, the ORIGINAL first.
///
/// The list is exactly `shape.lineCount` long — that is what the count
/// counts, so the ceiling on it is a direct ceiling on stroke cost.
///
/// * mirrored — the dihedral group generated by the axis and a rotation of
///   `720/lineCount`: `m` rotations and `m` reflections for `m = count/2`.
///   Count 2 is the plain left/right mirror, count 4 the quadrant.
/// * not mirrored — the cyclic group: `count` rotations of `360/count`.
///   Nothing changes handedness, which is why "mirror" would be the wrong
///   name for this feature.
List<GuideTransform> symmetryTransforms(SymmetryShape shape) {
  final origin = shape.axis.origin;
  final axisAngle = shape.axis.angleDegrees;
  if (!shape.lineSymmetry) {
    final step = 360 / shape.lineCount;
    return [
      for (var k = 0; k < shape.lineCount; k += 1)
        if (k == 0)
          const GuideTransform.identity()
        else
          GuideTransform.rotation(origin, step * k),
    ];
  }
  final sectors = shape.lineCount ~/ 2;
  final step = 360 / sectors;
  return [
    for (var k = 0; k < sectors; k += 1) ...[
      if (k == 0)
        const GuideTransform.identity()
      else
        GuideTransform.rotation(origin, step * k),
      // r^k ∘ s: reflect across the axis, then turn into this sector.
      if (k == 0)
        GuideTransform.reflection(origin, axisAngle)
      else
        GuideTransform.rotation(
          origin,
          step * k,
        ).compose(GuideTransform.reflection(origin, axisAngle)),
    ],
  ];
}

/// One candidate the perspective snap can lock a stroke onto.
class SnapCandidate {
  const SnapCandidate({
    required this.origin,
    required this.dx,
    required this.dy,
  });

  /// Where the stroke started — the ray passes through it.
  final CanvasPoint origin;

  /// Unit direction towards the vanishing point.
  final double dx;
  final double dy;

  /// [point] pushed onto this ray.
  CanvasPoint project(CanvasPoint point) {
    final along = (point.x - origin.x) * dx + (point.y - origin.y) * dy;
    return CanvasPoint(x: origin.x + dx * along, y: origin.y + dy * along);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SnapCandidate &&
          other.origin == origin &&
          other.dx == dx &&
          other.dy == dy;

  @override
  int get hashCode => Object.hash(origin, dx, dy);

  @override
  String toString() => 'SnapCandidate($origin → $dx, $dy)';
}

/// The rays a stroke starting at [start] could lock onto, in the order the
/// guides are listed — the order that settles ties.
///
/// Every vanishing point of every snapping guide is a candidate. Two or
/// three of them per guide is the normal case and it has to be: a
/// two-point perspective where only one vanishing point were live could
/// not draw a box.
List<SnapCandidate> snapCandidatesAt(
  Iterable<PerspectiveShape> snapping,
  CanvasPoint start,
) {
  final candidates = <SnapCandidate>[];
  for (final shape in snapping) {
    for (final vanishingPoint in shape.vanishingPoints) {
      final direction = vanishingPoint.resolve().directionFrom(start);
      // A vanishing point sitting exactly under the stroke's first sample
      // names no direction; skip it rather than inventing one.
      if (direction == null) continue;
      candidates.add(
        SnapCandidate(
          origin: start,
          dx: direction.dx,
          dy: direction.dy,
        ),
      );
    }
  }
  return candidates;
}

/// Which candidate a stroke travelling along ([dx], [dy]) locks onto.
///
/// Chosen by smallest ANGLE between the travel and the candidate line, and
/// a line has no sense of forward: `|dot|` compares them, so a stroke drawn
/// away from the vanishing point locks onto the same ray as one drawn
/// towards it.
///
/// Two deliberate absences:
///
/// * **No threshold.** A cutoff would make the same gesture snap sometimes
///   and not others, which is worse to draw with than always snapping. The
///   way out is the guide's own snap switch, not a tolerance.
/// * **No nearest-in-distance term.** Only direction decides, so the choice
///   does not change as the stroke grows.
///
/// Ties go to the earlier candidate — strictly-greater keeps the first — so
/// the same gesture always picks the same ray no matter how the doubles
/// happened to round.
SnapCandidate? chooseSnapCandidate(
  List<SnapCandidate> candidates, {
  required double dx,
  required double dy,
}) {
  SnapCandidate? best;
  var bestAlignment = double.negativeInfinity;
  for (final candidate in candidates) {
    final alignment = (dx * candidate.dx + dy * candidate.dy).abs();
    if (alignment > bestAlignment) {
      bestAlignment = alignment;
      best = candidate;
    }
  }
  return best;
}

/// [point] slid onto the line of [axis] — how a vanishing point is held on
/// the eye level while it is dragged.
CanvasPoint projectOntoAxis(GuideAxis axis, CanvasPoint point) {
  final radians = axis.angleDegrees * math.pi / 180;
  final dx = math.cos(radians);
  final dy = math.sin(radians);
  final along =
      (point.x - axis.origin.x) * dx + (point.y - axis.origin.y) * dy;
  return CanvasPoint(
    x: axis.origin.x + dx * along,
    y: axis.origin.y + dy * along,
  );
}

/// [guides] carried through [transform] — every axis, vanishing point and
/// defining line.
///
/// Guides are stored in CANVAS space, but a layer carrying a transform is
/// drawn through it and its strokes record in the layer's own ARTWORK
/// coordinates ("draw-through"). Feeding the canvas-space guide to that
/// stroke path unchanged would put the axis somewhere the pen is not. The
/// transform to pass is the layer pose's inverse.
///
/// Poses are similarities, so a mapped axis is still a straight line and a
/// mapped direction is still a direction — nothing here has to cope with
/// shear.
CutGuides mapGuides(CutGuides guides, GuideTransform transform) {
  if (transform.isIdentity || guides.isEmpty) return guides;
  return CutGuides(
    guides: [
      for (final guide in guides.guides)
        guide.copyWith(shape: _mapShape(guide.shape, transform)),
    ],
    activeSymmetryId: guides.activeSymmetryId,
  );
}

GuideShape _mapShape(GuideShape shape, GuideTransform transform) {
  return switch (shape) {
    SymmetryShape() => shape.copyWith(
      axis: _mapAxis(shape.axis, transform),
    ),
    PerspectiveShape() => shape.copyWith(
      vanishingPoints: [
        for (final point in shape.vanishingPoints)
          _mapVanishingPoint(point, transform),
      ],
      eyeLevel: _mapAxis(shape.eyeLevel, transform),
    ),
  };
}

GuideAxis _mapAxis(GuideAxis axis, GuideTransform transform) => GuideAxis(
  origin: transform.apply(axis.origin),
  angleDegrees: transform.mapAxisAngleDegrees(axis.angleDegrees),
);

VanishingPoint _mapVanishingPoint(
  VanishingPoint point,
  GuideTransform transform,
) {
  switch (point) {
    case VanishingPointAt():
      return VanishingPointAt(transform.apply(point.point));
    case VanishingPointTowards():
      final mapped = transform.mapDirection(point.dx, point.dy);
      // A collapsed direction has no meaningful image; keeping the original
      // is closer to the truth than inventing one.
      return mapped == null
          ? point
          : VanishingPointTowards(dx: mapped.dx, dy: mapped.dy);
    case VanishingPointFromLines():
      return VanishingPointFromLines(
        _mapLine(point.first, transform),
        _mapLine(point.second, transform),
      );
  }
}

GuideLine _mapLine(GuideLine line, GuideTransform transform) =>
    GuideLine(a: transform.apply(line.a), b: transform.apply(line.b));

/// Where a vanishing point being dragged to [target] actually lands.
///
/// The eye-level constraint is a rule about DRAGGING, not a normalisation
/// of what is stored. Two reasons it must stay that way: sweeping every
/// vanishing point onto the horizon would have to replace a two-line
/// definition with the bare point it currently names — throwing away the
/// lines the user drew — and switching the toggle on would silently move
/// artwork-defining geometry that was never touched. Turning the constraint
/// on binds the NEXT drag; it does not rewrite history.
CanvasPoint constrainedVanishingPointTarget(
  PerspectiveShape shape,
  CanvasPoint target,
) {
  if (!shape.constrainToEyeLevel) return target;
  return projectOntoAxis(shape.eyeLevel, target);
}
