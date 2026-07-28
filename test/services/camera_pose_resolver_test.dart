import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut_camera.dart';
import 'package:anicel/src/services/camera_pose_resolver.dart';

void main() {
  const canvasSize = CanvasSize(width: 2000, height: 1000);

  CameraPose resolve(CutCamera camera, int frameIndex) => resolveCameraPoseAt(
    camera: camera,
    canvasSize: canvasSize,
    frameIndex: frameIndex,
  );

  test('empty camera resolves to the default pose', () {
    final pose = resolve(CutCamera.empty(), 10);

    expect(pose, defaultCameraPoseFor(canvasSize));
    expect(pose.center, CanvasPoint(x: 1000, y: 500));
    expect(pose.zoom, 1);
    expect(pose.rotationDegrees, 0);
  });

  test('an exact keyframe wins over interpolation', () {
    final keyframe = CameraPose(center: CanvasPoint(x: 10, y: 20), zoom: 3);
    final camera = CutCamera(
      keyframes: {
        0: CameraPose(center: CanvasPoint(x: 0, y: 0)),
        5: keyframe,
        10: CameraPose(center: CanvasPoint(x: 100, y: 100)),
      },
    );

    expect(resolve(camera, 5), keyframe);
  });

  test('frames before the first keyframe hold the first pose', () {
    final first = CameraPose(center: CanvasPoint(x: 50, y: 50), zoom: 2);
    final camera = CutCamera(
      keyframes: {
        8: first,
        16: CameraPose(center: CanvasPoint(x: 100, y: 100)),
      },
    );

    expect(resolve(camera, 0), first);
    expect(resolve(camera, 7), first);
  });

  test('frames after the last keyframe hold the last pose', () {
    final last = CameraPose(center: CanvasPoint(x: 100, y: 100), zoom: 0.5);
    final camera = CutCamera(
      keyframes: {
        0: CameraPose(center: CanvasPoint(x: 0, y: 0)),
        8: last,
      },
    );

    expect(resolve(camera, 9), last);
    expect(resolve(camera, 100), last);
  });

  test('frames between keyframes interpolate linearly', () {
    final camera = CutCamera(
      keyframes: {
        10: CameraPose(
          center: CanvasPoint(x: 100, y: 200),
          zoom: 1,
          rotationDegrees: 0,
        ),
        20: CameraPose(
          center: CanvasPoint(x: 300, y: 600),
          zoom: 3,
          rotationDegrees: 90,
        ),
      },
    );

    final quarter = resolve(camera, 12);
    expect(quarter.center.x, closeTo(140, 1e-9));
    expect(quarter.center.y, closeTo(280, 1e-9));
    expect(quarter.zoom, closeTo(1.4, 1e-9));
    expect(quarter.rotationDegrees, closeTo(18, 1e-9));

    final half = resolve(camera, 15);
    expect(half.center.x, closeTo(200, 1e-9));
    expect(half.center.y, closeTo(400, 1e-9));
    expect(half.zoom, closeTo(2, 1e-9));
    expect(half.rotationDegrees, closeTo(45, 1e-9));
  });

  test('rotation interpolates without wrap-around so full turns work', () {
    final camera = CutCamera(
      keyframes: {
        0: CameraPose(center: CanvasPoint(x: 0, y: 0), rotationDegrees: 0),
        10: CameraPose(center: CanvasPoint(x: 0, y: 0), rotationDegrees: 360),
      },
    );

    expect(resolve(camera, 5).rotationDegrees, closeTo(180, 1e-9));
  });

  test('a single keyframe applies everywhere', () {
    final only = CameraPose(center: CanvasPoint(x: 42, y: 24), zoom: 1.25);
    final camera = CutCamera(keyframes: {6: only});

    expect(resolve(camera, 0), only);
    expect(resolve(camera, 6), only);
    expect(resolve(camera, 60), only);
  });
}
