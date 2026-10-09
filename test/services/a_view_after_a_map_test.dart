import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/services/camera_projection_matrix.dart';
import 'package:anicel/src/services/viewport_transform_matrix.dart';

/// [viewportAfter]: the view a canvas is seen through when a map lays it
/// where a view shows — the camera's projection inside the panel's view
/// (playback-plays-the-screen-material ②), a sheet picture's slot inside
/// the page's.
void main() {
  final camera = cameraProjectionMatrix(
    CameraPose(
      center: CanvasPoint(x: 300, y: 200),
      zoom: 0.7,
      rotationDegrees: 15,
    ),
    const CanvasSize(width: 1920, height: 1080),
  );

  test('the view it gives maps as the view and the map do, one after the '
      'other — a mirrored view too, which no similarity reads alone', () {
    for (final flipHorizontal in [false, true]) {
      for (final flipVertical in [false, true]) {
        for (final rotationDegrees in [0.0, 30.0, -120.0]) {
          final view = CanvasViewport(
            zoom: 0.8,
            panX: 12.5,
            panY: -7.25,
            rotationDegrees: rotationDegrees,
            flipHorizontal: flipHorizontal,
            flipVertical: flipVertical,
          );
          final wanted = viewportTransformMatrix(view)..multiply(camera);
          final given = viewportTransformMatrix(viewportAfter(view, camera));
          for (var entry = 0; entry < 16; entry += 1) {
            expect(
              given.storage[entry],
              closeTo(wanted.storage[entry], 1e-9),
              reason: 'flipped ${(flipHorizontal, flipVertical)}, turned '
                  '$rotationDegrees°: entry $entry',
            );
          }
        }
      }
    }
  });

  test('an unmirrored view is read as it always was — a sheet picture\'s '
      'live view does not move', () {
    final view = CanvasViewport(
      zoom: 1.5,
      panX: 3,
      panY: 4,
      rotationDegrees: 10,
    );
    expect(
      viewportAfter(view, camera),
      viewportOfSimilarity(viewportTransformMatrix(view)..multiply(camera)),
    );
  });
}
