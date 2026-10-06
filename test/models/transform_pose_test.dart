// A LAYER'S POSE HOLDS A SCALE AN AXIS; THE CAMERA'S HOLDS ONE ZOOM.
//
// 🗣️F-256-Q1 (유저 2026-10-06): 「가른다 — AE 처럼 Scale X · Y(마이너스 =
// 반전)」 — the option whose own terms say of the camera 「카메라는 줌 하나
// 그대로」. Until that answer the two were one class under two names
// (`typedef TransformPose = CameraPose`), so none of this could be said.
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/transform_pose.dart';

void main() {
  final centre = CanvasPoint(x: 12, y: 34);

  TransformPose pose({double x = 2, double y = 3, double turn = 10}) =>
      TransformPose(
        center: centre,
        scaleX: x,
        scaleY: y,
        rotationDegrees: turn,
      );

  test('a pose keeps its two scales apart, and a mirror is a number', () {
    final mirrored = TransformPose(center: centre, scaleX: -2, scaleY: 0.5);

    expect(mirrored.scaleX, -2);
    expect(mirrored.scaleY, 0.5);
    expect(mirrored.scale, CanvasPoint(x: -2, y: 0.5));
  });

  test('a pose that names no scale is the size the layer has', () {
    expect(TransformPose(center: centre).scale, CanvasPoint(x: 1, y: 1));
    expect(TransformPose(center: centre).rotationDegrees, 0);
  });

  test('a scale of nothing, or of no number, is refused on EITHER axis', () {
    for (final bad in [0.0, double.nan, double.infinity]) {
      expect(
        () => TransformPose(center: centre, scaleX: bad),
        throwsArgumentError,
        reason: 'scaleX $bad',
      );
      expect(
        () => TransformPose(center: centre, scaleY: bad),
        throwsArgumentError,
        reason: 'scaleY $bad',
      );
    }
    expect(
      () => TransformPose(center: centre, rotationDegrees: double.nan),
      throwsArgumentError,
    );
  });

  test('two poses are one when all four of their numbers are', () {
    expect(pose(), pose());
    expect(pose().hashCode, pose().hashCode);
    expect(pose(x: 4), isNot(pose()));
    expect(pose(y: 4), isNot(pose()), reason: 'the second scale counts');
    expect(pose(turn: 11), isNot(pose()));
    expect(pose().copyWith(center: CanvasPoint(x: 0, y: 0)), isNot(pose()));
  });

  test('copyWith moves the number it names and keeps the rest', () {
    expect(pose().copyWith(scaleX: 7), pose(x: 7));
    expect(pose().copyWith(scaleY: 7), pose(y: 7));
    expect(pose().copyWith(rotationDegrees: 7), pose(turn: 7));
    expect(pose().copyWith(), pose());
  });

  test('uniformScale is one number along both axes', () {
    expect(uniformScale(2.5), CanvasPoint(x: 2.5, y: 2.5));
  });

  group('where it meets the camera', () {
    final camera = CameraPose(center: centre, zoom: 1.5, rotationDegrees: -30);

    test('a camera\'s zoom is its scale along both axes', () {
      final ofCamera = TransformPose.ofCamera(camera);

      expect(ofCamera.center, centre);
      expect(ofCamera.scale, uniformScale(1.5));
      expect(ofCamera.rotationDegrees, -30);
      expect(
        ofCamera,
        TransformPose.uniform(center: centre, zoom: 1.5, rotationDegrees: -30),
      );
    });

    test('and it comes back out the pose that went in', () {
      expect(TransformPose.ofCamera(camera).toCameraPose(), camera);
    });

    test('🚨a pose with two scales has no ONE zoom to hand a reader that '
        'still works a placement out as a similarity', () {
      expect(TransformPose.uniform(center: centre, zoom: 2).zoom, 2);
      expect(
        () => TransformPose(center: centre, scaleX: 2).zoom,
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => TransformPose(center: centre, scaleX: 2).toCameraPose(),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
