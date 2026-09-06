import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/services/camera_projection_matrix.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

/// The ONE camera projection behind the export renderer, the playback
/// painter and the overlay's frame corners (the audit's clone scan,
/// 2026-09-06): output center = pose center, zoom scales, the world turns
/// the opposite way to the camera.
void main() {
  const frame = CanvasSize(width: 1920, height: 1080);

  ({double x, double y}) project(
    CameraPose pose,
    double x,
    double y, {
    CanvasSize? outputSize,
  }) {
    final mapped = cameraProjectionMatrix(
      pose,
      frame,
      outputSize: outputSize,
    ).transform3(Vector3(x, y, 0));
    return (x: mapped.x, y: mapped.y);
  }

  test('the pose center lands on the output center', () {
    final pose = CameraPose(center: CanvasPoint(x: 1000, y: 600));
    final mapped = project(pose, 1000, 600);
    expect(mapped.x, closeTo(960, 1e-9));
    expect(mapped.y, closeTo(540, 1e-9));
  });

  test('zoom 2: one canvas pixel off the center is two output pixels', () {
    final pose = CameraPose(center: CanvasPoint(x: 1000, y: 600), zoom: 2);
    final mapped = project(pose, 1001, 600);
    expect(mapped.x, closeTo(962, 1e-9));
    expect(mapped.y, closeTo(540, 1e-9));
  });

  test('a camera rotated 90 clockwise shows the world turned the other '
      'way: a point to the RIGHT of the center appears ABOVE it', () {
    final pose = CameraPose(
      center: CanvasPoint(x: 1000, y: 600),
      rotationDegrees: 90,
    );
    final mapped = project(pose, 1100, 600);
    expect(mapped.x, closeTo(960, 1e-9));
    expect(mapped.y, closeTo(540 - 100, 1e-9));
  });

  test('an output smaller than the frame scales by the width ratio', () {
    final pose = CameraPose(center: CanvasPoint(x: 1000, y: 600));
    final mapped = project(
      pose,
      1100,
      600,
      outputSize: const CanvasSize(width: 960, height: 540),
    );
    expect(mapped.x, closeTo(480 + 50, 1e-9));
    expect(mapped.y, closeTo(270, 1e-9));
  });
}
