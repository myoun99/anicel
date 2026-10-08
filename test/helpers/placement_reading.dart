import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/services/layer_pose_matrix.dart';

/// [pose] — about the canvas centre, or [anchorPoint] — as the placement a
/// row under no folder lies at: what a test hands a carrier that takes one.
LayerPlacement placedBy(
  TransformPose pose,
  CanvasSize canvasSize, {
  CanvasPoint? anchorPoint,
}) => placementOf((pose: pose, anchorPoint: anchorPoint), canvasSize);

/// [sample] as that placement — and none for none: a harness that takes a
/// row's pose and anchor from its cases hands the panel this.
LayerPlacement? placementOfSample(
  LayerPoseSample? sample,
  CanvasSize canvasSize,
) => sample == null ? null : placementOf(sample, canvasSize);

/// A placement read back the way a test says what it expects of one: where a
/// point of the artwork lands, and — of a placement that only moves, turns
/// and scales both axes alike — by how much.
///
/// ⚠️TEST-SIDE ON PURPOSE. Nothing in the app may ask a placement for 「its
/// zoom」 or 「its turn」: a folder stretched along one axis over a turned
/// row has neither (`LayerPlacement`). A test that built the poses knows its
/// placement is that plain kind, and says so by reading it this way.
extension PlacementReading on LayerPlacement {
  /// Where the centre of a canvas of [size] lands — a pose's `center` while
  /// the anchor is the default.
  CanvasPoint centreOf(CanvasSize size) =>
      apply(CanvasPoint(x: size.width / 2, y: size.height / 2));

  /// The one scale of a placement that scales both axes alike.
  double get evenScale => math.sqrt(a * a + b * b);

  /// The clockwise turn of such a placement, in degrees.
  double get turnDegrees => math.atan2(b, a) * 180 / math.pi;
}

/// A point within [within] of [expected] on both axes — a fold of matrices
/// lands a hair off the number a test writes down.
Matcher nearPoint(CanvasPoint expected, {double within = 1e-9}) =>
    predicate<CanvasPoint>(
      (point) =>
          (point.x - expected.x).abs() <= within &&
          (point.y - expected.y).abs() <= within,
      'a point within $within of $expected',
    );
