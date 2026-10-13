import 'dart:collection';

import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut_camera.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/services/camera_pose_resolver.dart';
import 'package:anicel/src/services/import/camera_track.dart';
import 'package:flutter_test/flutter_test.dart';

/// [cutCameraOfFramePoses] — the one way an import's baked camera, a pose on
/// every frame, becomes the keys a cut keeps (I-89 ⑦): each lane keyed where
/// the file keys it and where its move starts and stops, every way between
/// two keys held, straight or one AE ease, and more keys only where one way
/// does not play what the file shows. The TVPaint and CLIP STUDIO imports
/// both make their cut's camera here.
void main() {
  const canvas = CanvasSize(width: 1920, height: 1080);
  const keyedNowhere = (position: <int>[], zoom: <int>[], rotation: <int>[]);

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

  CutCamera keyed(
    SplayTreeMap<int, CameraPose> poses, {
    CameraKeyFrames keyedOn = keyedNowhere,
  }) => cutCameraOfFramePoses(poses, keyedOn: keyedOn);

  /// Every frame of [poses], played back from [camera]'s keys the way the
  /// app plays a camera ([resolveCameraPoseAt]), is the pose baked there.
  void expectPlaysBack(
    SplayTreeMap<int, CameraPose> poses,
    CutCamera camera,
  ) {
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
    expect(keyed(SplayTreeMap()).isEmpty, isTrue);
  });

  test('a camera that never moves is ONE key, where it starts — not a key '
      'on the last frame no one set (288, hands-on)', () {
    final camera = keyed(baked(48, (_) => pose(100, 80)));

    expect(camera.keyframes.keys, [0]);
  });

  test('a straight move is its two ends', () {
    final poses = baked(
      48,
      (f) => pose(100 + f * 10.0, 80 + f * 2.5, zoom: 1 + f / 100, turn: f / 4),
    );
    final camera = keyed(poses);

    expect(camera.keyframes.keys, [0, 47]);
    expectPlaysBack(poses, camera);
  });

  test('a hold at either end needs no key of its own: a move that starts '
      'late and stops early is keyed where it starts and stops (s6\'s pan, '
      'keyed on frames 0 and 108 of 186, arrived with a third on its '
      'last)', () {
    final poses = baked(
      30,
      (f) => pose(100 + (f.clamp(10, 20) - 10) * 10.0, 80),
    );
    final camera = keyed(poses);

    expect(camera.track.position.keys.keys, [10, 20]);
    expect(
      [camera.track.scale.keys.keys, camera.track.rotation.keys.keys],
      [
        [0],
        [0],
      ],
      reason: 'a lane that never moves is one key, where it starts',
    );
    expectPlaysBack(poses, camera);
  });

  test('🎯an eased move is its two ends and the ease between — not the many '
      'straight keys it came in as (I-89 ⑦: 「천천히 출발하는 팬이 키 둘 + '
      '이징이 아니라 리니어 키 여럿으로 들어온다」)', () {
    // A smoothstep is AE's Easy Ease exactly: a third of the way in, at no
    // speed, on both sides.
    final poses = baked(48, (f) {
      final t = f / 47;
      final eased = t * t * (3 - 2 * t);
      return pose(100 + 900 * eased, 80, zoom: 1 + eased, turn: 30 * eased);
    });
    final camera = keyed(poses);

    for (final lane in [
      camera.track.position,
      camera.track.scale,
      camera.track.rotation,
    ]) {
      expect(lane.keys.keys, [0, 47]);
      final leaving = lane.keys[0]!.outgoing as EaseSide;
      final arriving = lane.keys[47]!.incoming as EaseSide;
      expect(leaving.influence, closeTo(1 / 3, 1e-3));
      expect(leaving.speed, closeTo(0, 1e-3));
      expect(arriving.influence, closeTo(1 / 3, 1e-3));
      expect(arriving.speed, closeTo(0, 1e-3));
    }
    expectPlaysBack(poses, camera);
  });

  test('a move that turns a corner keeps it: the keys either side of it run '
      'straight, as the frames they stand for did', () {
    final poses = baked(
      41,
      (f) => f <= 20
          ? pose(100 + 40.0 * f, 80)
          : pose(900, 80 + 40.0 * (f - 20)),
    );
    final camera = keyed(poses);

    expect(camera.keyframes.keys, [0, 20, 40]);
    expect(camera.track.position.keys[0]!.outgoing, KeySide.linear);
    expectPlaysBack(poses, camera);
  });

  test('a key stands on every frame the file keys — even where one straight '
      'way through it would do (유저 10-09: 「구조적으론 원본 그대로를 '
      '원해」)', () {
    final poses = baked(49, (f) => pose(100 + f * 5.0, 80));
    final camera = keyed(
      poses,
      keyedOn: (position: [0, 24, 48], zoom: [0], rotation: [0]),
    );

    expect(camera.track.position.keys.keys, [0, 24, 48]);
    expectPlaysBack(poses, camera);
  });

  test('each lane is keyed on its own frames, as the file keys them apart '
      '— a zoom keyed once is one key however the position moves', () {
    final poses = baked(
      48,
      (f) => pose(100 + f * 10.0, 80, zoom: 2, turn: f.clamp(0, 23) * 2.0),
    );
    final camera = keyed(
      poses,
      keyedOn: (position: [0, 47], zoom: [0], rotation: [0, 23]),
    );

    expect(camera.track.position.keys.keys, [0, 47]);
    expect(camera.track.scale.keys.keys, [0]);
    expect(camera.track.rotation.keys.keys, [0, 23]);
    expectPlaysBack(poses, camera);
  });

  test('a value that holds to the next key and steps there is HELD from the '
      'key — CLIP STUDIO\'s Constant — not a ramp over the frames before '
      'the step', () {
    final poses = baked(20, (f) => pose(f < 10 ? 100 : 400, 80));
    final camera = keyed(
      poses,
      keyedOn: (position: [0, 10], zoom: [0], rotation: [0]),
    );

    expect(camera.track.position.keys.keys, [0, 10]);
    expect(camera.track.position.keys[0]!.outgoing, KeyExit.hold);
    expectPlaysBack(poses, camera);
  });

  test('where one ease does not play the file\'s way, keys stand where it '
      'stops — each of them still on the file\'s, and every frame within a '
      'quarter pixel', () {
    // A TVPaint profile drawn as a polyline through four points (the
    // reference cut's own shape), a 1036px pan over 25 frames.
    const corners = [
      (0.0, 0.0),
      (0.134, 0.430),
      (0.283, 0.785),
      (0.498, 0.941),
      (0.773, 0.970),
      (1.0, 1.0),
    ];
    double along(double t) {
      var at = 0;
      while (at + 2 < corners.length && corners[at + 1].$1 <= t) {
        at += 1;
      }
      final (t0, s0) = corners[at];
      final (t1, s1) = corners[at + 1];
      return s0 + (s1 - s0) * (t - t0) / (t1 - t0);
    }

    final poses = baked(26, (f) => pose(877, 694 + 1036 * along(f / 25)));
    final camera = keyed(
      poses,
      keyedOn: (position: [0, 25], zoom: [0], rotation: [0]),
    );
    final keys = camera.track.position.keys;

    expect(keys.keys, containsAll([0, 25]));
    expect(keys.length, greaterThan(2), reason: 'one ease misses by 19px');
    expect(
      keys.values.any((key) => key.outgoing is EaseSide),
      isTrue,
      reason: 'the ways between are eased',
    );
    expectPlaysBack(poses, camera);
  });

  test('a long straight move is its two ends, however long', () {
    final poses = baked(2000, (f) => pose(f * 1.0, 0));
    final camera = keyed(poses);

    expect(camera.keyframes.keys, [0, 1999]);
    expectPlaysBack(poses, camera);
  });
}
