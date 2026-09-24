import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/services/layer_pose_matrix.dart';

/// The ONE pose inverse (I-36): the eyedropper's pick, a region restated in
/// a posed layer's pixels, the guides the pen draws against and the fill's
/// raster all ask [canvasToArtwork] — so it has to be exactly the way back
/// from [artworkToCanvas], which has to be exactly [layerPoseMatrix].
void main() {
  const size = CanvasSize(width: 64, height: 48);
  final sample = (
    pose: TransformPose(
      center: CanvasPoint(x: 40, y: 30),
      zoom: 2,
      rotationDegrees: 30,
    ),
    anchorPoint: CanvasPoint(x: 12, y: 8),
  );
  final points = [
    CanvasPoint(x: 0, y: 0),
    CanvasPoint(x: 17, y: -5),
    CanvasPoint(x: 63.5, y: 47.25),
  ];

  test('artworkToCanvas is the pose matrix, in the plane', () {
    final matrix = layerPoseMatrix(
      sample.pose,
      size,
      anchorPoint: sample.anchorPoint,
    ).storage;
    final forward = artworkToCanvas(sample, size);
    for (final point in points) {
      final mapped = forward.apply(point);
      expect(
        mapped.x,
        closeTo(matrix[0] * point.x + matrix[4] * point.y + matrix[12], 1e-9),
      );
      expect(
        mapped.y,
        closeTo(matrix[1] * point.x + matrix[5] * point.y + matrix[13], 1e-9),
      );
    }
  });

  test('canvasToArtwork takes every point back where it came from', () {
    final forward = artworkToCanvas(sample, size);
    final back = canvasToArtwork(sample, size)!;
    for (final point in points) {
      final round = back.apply(forward.apply(point));
      expect(round.x, closeTo(point.x, 1e-9));
      expect(round.y, closeTo(point.y, 1e-9));
    }
  });
}
