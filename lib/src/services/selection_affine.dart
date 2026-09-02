import 'dart:math' as math;

import '../models/canvas_point.dart';

/// The Ctrl+T free-transform affine (P9b), canvas space:
/// `p' = R(θ) · S(sx, sy) · (p − pivot) + pivot + t` — rotate/scale about
/// the fixed [pivot] (the base box center at session start), then
/// translate. Anchored handle scaling (Photoshop's opposite-corner
/// anchor) is expressed by compensating [tx]/[ty], so ONE composite
/// covers every handle interaction.
class SelectionAffine {
  const SelectionAffine({
    required this.pivot,
    this.sx = 1,
    this.sy = 1,
    this.rotationDegrees = 0,
    this.tx = 0,
    this.ty = 0,
  });

  final CanvasPoint pivot;
  final double sx;
  final double sy;
  final double rotationDegrees;
  final double tx;
  final double ty;

  bool get isIdentity =>
      sx == 1 && sy == 1 && rotationDegrees == 0 && tx == 0 && ty == 0;

  double get _radians => rotationDegrees * math.pi / 180;

  /// The rotation's cosine and sine, EXACT at the quarter turns.
  ///
  /// `math.cos(pi / 2)` is 6.1e-17, not zero, and that residue is enough to
  /// make a quarter turn miss the resampler's lattice: destination pixel
  /// centres land a hair off source pixel centres, the footprint reaches a
  /// neighbour it should not, and "rotating by 90° gives back the same
  /// pixels" becomes a rounding accident rather than a guarantee. Reading
  /// the table for exact multiples of 90 makes it structural.
  ///
  /// Both the geometry ([apply], which moves the selection outline) and the
  /// pixels (the resample fold) read these, so the ants and the picture can
  /// never disagree about where the rotation went.
  double get cosTheta {
    final quarter = _exactQuarterTurn;
    return quarter == null ? math.cos(_radians) : _quarterCos[quarter];
  }

  double get sinTheta {
    final quarter = _exactQuarterTurn;
    return quarter == null ? math.sin(_radians) : _quarterSin[quarter];
  }

  /// 0/1/2/3 for an exact 0/90/180/270, null for anything in between.
  int? get _exactQuarterTurn {
    if (rotationDegrees % 90 != 0 || !rotationDegrees.isFinite) {
      return null;
    }
    final quarter = (rotationDegrees ~/ 90) % 4;
    return quarter < 0 ? quarter + 4 : quarter;
  }

  static const List<double> _quarterCos = <double>[1, 0, -1, 0];
  static const List<double> _quarterSin = <double>[0, 1, 0, -1];

  CanvasPoint apply(CanvasPoint point) {
    final lx = (point.x - pivot.x) * sx;
    final ly = (point.y - pivot.y) * sy;
    final cos = cosTheta;
    final sin = sinTheta;
    return CanvasPoint(
      x: lx * cos - ly * sin + pivot.x + tx,
      y: lx * sin + ly * cos + pivot.y + ty,
    );
  }

  /// [apply] run backwards: the pre-image of a canvas point.
  ///
  /// The perspective and mesh modes hold their control points as
  /// displacements in the box's OWN frame, so that rotating or scaling the
  /// box carries the warp with it instead of leaving it behind. Turning a
  /// pointer position into one of those displacements is this function.
  ///
  /// The scales cannot be zero — every writer clamps them away from it —
  /// so there is no degenerate case to guard.
  CanvasPoint applyInverse(CanvasPoint point) {
    final ux = point.x - pivot.x - tx;
    final uy = point.y - pivot.y - ty;
    final cos = cosTheta;
    final sin = sinTheta;
    final lx = ux * cos + uy * sin;
    final ly = -ux * sin + uy * cos;
    return CanvasPoint(x: lx / sx + pivot.x, y: ly / sy + pivot.y);
  }

  SelectionAffine copyWith({
    double? sx,
    double? sy,
    double? rotationDegrees,
    double? tx,
    double? ty,
  }) {
    return SelectionAffine(
      pivot: pivot,
      sx: sx ?? this.sx,
      sy: sy ?? this.sy,
      rotationDegrees: rotationDegrees ?? this.rotationDegrees,
      tx: tx ?? this.tx,
      ty: ty ?? this.ty,
    );
  }
}
