import 'dart:collection';

import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/services/camera_pose_resolver.dart';
import 'package:anicel/src/services/import/camera_track.dart';
import 'package:flutter_test/flutter_test.dart';

/// [cutCameraOfFramePoses] — the one way an import's baked camera, a pose on
/// every frame, becomes the keys a cut keeps. The TVPaint and CLIP STUDIO
/// imports both make their cut's camera here.
void main() {
  const canvas = CanvasSize(width: 1920, height: 1080);

  CameraPose pose(double x, double y, {double zoom = 1, double turn = 0}) =>
      CameraPose(
        center: CanvasPoint(x: x, y: y),
        zoom: zoom,
        rotationDegrees: turn,
      );

  SplayTreeMap<int, CameraPose> baked(
    int frames,
    CameraPose Function(int frame) at,
  ) => SplayTreeMap.of({for (var f = 0; f < frames; f += 1) f: at(f)});

  /// Every frame of [poses], played back from the keys the way the app
  /// plays a camera ([resolveCameraPoseAt]), is the pose baked there.
  void expectPlaysBack(SplayTreeMap<int, CameraPose> poses) {
    final camera = cutCameraOfFramePoses(poses);
    poses.forEach((frame, baked) {
      final shown = resolveCameraPoseAt(
        camera: camera,
        canvasSize: canvas,
        frameIndex: frame,
      );
      expect(shown.center.x, closeTo(baked.center.x, 0.25), reason: '$frame');
      expect(shown.center.y, closeTo(baked.center.y, 0.25), reason: '$frame');
      expect(shown.zoom, closeTo(baked.zoom, 1e-4), reason: '$frame');
      expect(
        shown.rotationDegrees,
        closeTo(baked.rotationDegrees, 0.01),
        reason: '$frame',
      );
    });
  }

  test('nothing baked is no camera', () {
    expect(cutCameraOfFramePoses(SplayTreeMap()).isEmpty, isTrue);
  });

  test('a camera that never moves is ONE key, where it starts — not a key '
      'on the last frame no one set (288, hands-on)', () {
    final camera = cutCameraOfFramePoses(baked(48, (_) => pose(100, 80)));

    expect(camera.keyframes.keys, [0]);
  });

  test('a straight move is its two ends', () {
    final poses = baked(
      48,
      (f) => pose(100 + f * 10.0, 80 + f * 2.5, zoom: 1 + f / 100, turn: f / 4),
    );

    expect(cutCameraOfFramePoses(poses).keyframes.keys, [0, 47]);
    expectPlaysBack(poses);
  });

  test('an eased move keeps the keys its curve needs, and plays back as '
      'baked', () {
    final poses = baked(48, (f) {
      final t = f / 47;
      final eased = t * t * (3 - 2 * t);
      return pose(100 + 900 * eased, 80, zoom: 1 + eased, turn: 30 * eased);
    });

    expect(
      cutCameraOfFramePoses(poses).keyframes.length,
      inExclusiveRange(2, 48),
    );
    expectPlaysBack(poses);
  });

  test('a long move keeps a key at least every 512 frames', () {
    final keys = cutCameraOfFramePoses(
      baked(2000, (f) => pose(f * 1.0, 0)),
    ).keyframes.keys.toList();

    expect((keys.first, keys.last), (0, 1999));
    for (var i = 1; i < keys.length; i += 1) {
      expect(keys[i] - keys[i - 1], lessThanOrEqualTo(512));
    }
  });
}
