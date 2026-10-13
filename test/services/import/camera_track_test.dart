import 'dart:collection';
import 'dart:math' as math;

import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut_camera.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/transform_track.dart';
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
  /// app plays a camera ([resolveCameraPoseAt]), is within a pixel of the
  /// pose baked there.
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
      expect(shown.center.x, closeTo(baked.center.x, 1), reason: '$frame');
      expect(shown.center.y, closeTo(baked.center.y, 1), reason: '$frame');
      expect(shown.zoom, closeTo(baked.zoom, 4e-4), reason: '$frame');
      expect(
        shown.rotationDegrees,
        closeTo(baked.rotationDegrees, 0.04),
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

  test('a straight move is its two ends, run straight — no ease comes '
      'nearer it', () {
    final poses = baked(
      48,
      (f) => pose(100 + f * 10.0, 80 + f * 2.5, zoom: 1 + f / 100, turn: f / 4),
    );
    final camera = keyed(poses);

    expect(camera.keyframes.keys, [0, 47]);
    for (final lane in [
      camera.track.position,
      camera.track.scale,
      camera.track.rotation,
    ]) {
      expect(
        (lane.keys[0]!.outgoing, lane.keys[47]!.incoming),
        (KeySide.linear, KeySide.linear),
      );
    }
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

  test('🗣️an ease of a few pixels comes in eased too, where one straight way '
      'would play it within the pixel: the pixel says where another key '
      'stands, not how the way between two bends (the user\'s zoom-and-turn '
      'sample: CLIP STUDIO\'s own slow-out slow-in of 3px came in straight, '
      '0.29px off)', () {
    final poses = baked(30, (f) {
      final t = f / 29;
      final eased = t * t * (3 - 2 * t);
      return pose(
        100 + 3 * eased,
        80 - 2 * eased,
        zoom: 1 + 3e-4 * eased,
        turn: 0.1 * eased,
      );
    });
    final camera = keyed(poses);

    for (final lane in [
      camera.track.position,
      camera.track.scale,
      camera.track.rotation,
    ]) {
      expect(lane.keys.keys, [0, 29]);
      final leaving = lane.keys[0]!.outgoing as EaseSide;
      final arriving = lane.keys[29]!.incoming as EaseSide;
      expect(leaving.influence, closeTo(1 / 3, 1e-3));
      expect(leaving.speed, closeTo(0, 1e-3));
      expect(arriving.influence, closeTo(1 / 3, 1e-3));
      expect(arriving.speed, closeTo(0, 1e-3));
    }
    expectPlaysBack(poses, camera);
  });

  /// A move of 100px over 30 frames, [by] px of it bent the way an ease
  /// bends one — straight a tenth of [by] away at the most.
  SplayTreeMap<int, CameraPose> bentBy(double by) => baked(30, (f) {
    final t = f / 29;
    return pose(100 + 100 * t + by * (t * t * (3 - 2 * t) - t), 80);
  });

  test('an ease straight plays within a hundredth of the pixel is straight — '
      'nearer than the import knows a file (TVPaint\'s own bake against the '
      'decode\'s: 0.003 to 0.006px); one it misses by more comes in '
      'eased', () {
    final finer = keyed(bentBy(0.05)).track.position;
    final coarser = keyed(bentBy(0.5)).track.position;

    expect(finer.keys.keys, [0, 29]);
    expect(finer.keys[0]!.outgoing, KeySide.linear, reason: '0.005px');
    expect(coarser.keys.keys, [0, 29]);
    expect(coarser.keys[0]!.outgoing, isA<EaseSide>(), reason: '0.05px');
  });

  test('a way out and back by under a pixel is one straight way — no ease '
      'bends a way that ends where it starts', () {
    final poses = baked(
      25,
      (f) => pose(100 + 0.5 * math.sin(math.pi * f / 24), 80),
    );
    final position = keyed(poses).track.position;

    expect(position.keys.keys, [0, 24]);
    expect(position.keys[0]!.outgoing, KeySide.linear);
    expectPlaysBack(poses, keyed(poses));
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
      'pixel', () {
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

  /// A straight move over 25 frames, wobbled three times back and forth —
  /// what no one way follows — by [by] px, by [zoomBy] of zoom and [turnBy]
  /// degrees: a way's tolerance must take the wobble whole for the way to
  /// stand alone.
  SplayTreeMap<int, CameraPose> wobbled({
    required double by,
    required double zoomBy,
    required double turnBy,
  }) => baked(25, (f) {
    final wobble = math.sin(6 * math.pi * f / 24);
    return pose(
      100 + 10.0 * f + by * wobble,
      80,
      zoom: 1 + f / 50 + zoomBy * wobble,
      turn: 2.0 * f + turnBy * wobble,
    );
  });

  test('🗣️a way that plays the file\'s within a pixel is one way — and a '
      'zoom or a turn within what moves one (유저 10-13: 「1px 까지 '
      '허용」)', () {
    // Under a pixel's worth, over the quarter's the import kept before.
    final poses = wobbled(by: 0.6, zoomBy: 3e-4, turnBy: 0.03);
    final camera = keyed(poses);

    expect(camera.track.position.keys.keys, [0, 24]);
    expect(camera.track.scale.keys.keys, [0, 24]);
    expect(camera.track.rotation.keys.keys, [0, 24]);
    expectPlaysBack(poses, camera);
  });

  test('and one that misses by more than a pixel is keyed again, on every '
      'lane', () {
    final poses = wobbled(by: 1.5, zoomBy: 6e-4, turnBy: 0.06);
    final camera = keyed(poses);

    expect(camera.track.position.keys.length, greaterThan(2));
    expect(camera.track.scale.keys.length, greaterThan(2));
    expect(camera.track.rotation.keys.length, greaterThan(2));
    expectPlaysBack(poses, camera);
  });

  test('a camera folder\'s anchor is keyed to the same pixel', () {
    Iterable<int> keyedFor(double by) => transformTrackOfFramePoses(
      {
        for (final MapEntry(key: frame, value: pose)
            in wobbled(by: by, zoomBy: 0, turnBy: 0).entries)
          frame: (
            pose: TransformPose(center: CanvasPoint(x: 360, y: 270)),
            anchorPoint: pose.center,
          ),
      },
      keyedOn: (
        anchorPoint: const [],
        position: const [],
        scale: const [],
        rotation: const [],
      ),
    ).anchorPoint.keys.keys;

    expect(keyedFor(0.6), [0, 24]);
    expect(keyedFor(1.5).length, greaterThan(2));
  });
}
