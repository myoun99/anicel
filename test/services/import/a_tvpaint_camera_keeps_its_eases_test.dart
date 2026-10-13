import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut_camera.dart';
import 'package:anicel/src/models/import/tvp_import_model.dart';
import 'package:anicel/src/models/import/tvpp_camera_bake.dart';
import 'package:anicel/src/models/import/tvpp_parse.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/services/camera_pose_resolver.dart';
import 'package:anicel/src/services/import/tvp_import_planner.dart';
import 'package:flutter_test/flutter_test.dart';

/// I-89 ⑦ (유저 10-10: 「TVPaint 의 채널별 속도 곡선 · 경로 베지어 … 새
/// 모델로 옮긴다 — 매 프레임 굽기 대신」): a .tvpp camera comes in keyed where
/// TVPaint keys it, each channel on its own keys, and its ease as an AE ease
/// — the move still played as TVPaint plays it, frame for frame.
void main() {
  const canvas = CanvasSize(width: 1920, height: 1080);

  TvppCameraPoint point(int instant, double x, {int flags = 15}) =>
      TvppCameraPoint(
        x: x,
        y: 300,
        rotationDegrees: 0,
        zoomFactor: 1,
        sizeX: 1920,
        sizeY: 1080,
        instant: instant,
        flags: flags,
        bezierBeforeX: 0,
        bezierBeforeY: 0,
        bezierAfterX: 0,
        bezierAfterY: 0,
      );

  TvppCameraProfilePoint profilePoint(
    double x,
    double y, {
    double beforeX = 0,
    double beforeY = 0,
    double afterX = 0,
    double afterY = 0,
  }) => TvppCameraProfilePoint(
    x: x,
    y: y,
    bezierBeforeX: beforeX,
    bezierBeforeY: beforeY,
    bezierAfterX: afterX,
    bezierAfterY: afterY,
  );

  // TVPaint's own default: the arriving handle on the diagonal and none
  // leaving — a straight ramp (the calibration files' every untouched key).
  final straight = TvppCameraProfile(
    points: [
      profilePoint(0, 0),
      profilePoint(1, 1, beforeX: -0.25, beforeY: -0.25),
    ],
  );
  // A slow start: the leaving handle drawn out flat along the time axis.
  final slowStart = TvppCameraProfile(
    points: [
      profilePoint(0, 0, afterX: 0.5),
      profilePoint(1, 1, beforeX: -0.25, beforeY: -0.25),
    ],
  );

  /// A pan from x 100 to 1100 over TVPaint frames 0 → 24, its position
  /// arriving by [profile], baked and planned for [frameCount] frames as a
  /// .tvpp is.
  ({CutCamera camera, List<TvpCameraPose> baked}) pan(
    TvppCameraProfile profile, {
    required int frameCount,
  }) {
    // The second key authors the position alone (flags 1), as the
    // calibration files' later keys do.
    final points = [point(0, 100), point(24, 1100, flags: 1)];
    final channels = TvppCameraChannels(
      position: [straight, profile],
      rotation: [straight, straight],
      zoom: [straight, straight],
      size: [straight, straight],
    );
    final baked = bakeTvppCamera(points, channels, frameCount: frameCount);
    final camera = planTvpCamera(
      camera: TvpCamera(
        width: 1920,
        height: 1080,
        keyedOn: tvppCameraKeyFrames(points),
        positions: baked,
      ),
      frameCount: frameCount,
    );
    return (camera: camera, baked: baked);
  }

  /// Every frame plays back where TVPaint's own bake put the camera.
  void expectPlaysAsBaked(CutCamera camera, List<TvpCameraPose> baked) {
    for (final pose in baked) {
      final shown = resolveCameraPoseAt(
        camera: camera,
        canvasSize: canvas,
        frameIndex: pose.frame - 1,
      );
      expect(shown.center.x, closeTo(pose.x, 0.25), reason: '${pose.frame}');
      expect(shown.center.y, closeTo(pose.y, 0.25), reason: '${pose.frame}');
    }
  }

  test('🎯a slow-starting pan is TVPaint\'s two keys and an ease — not the '
      'many straight keys it came in as', () {
    final (:camera, :baked) = pan(slowStart, frameCount: 25);
    final position = camera.track.position;

    expect(position.keys.keys, [0, 24]);
    final leaving = position.keys[0]!.outgoing as EaseSide;
    expect(leaving.speed, lessThan(0.05), reason: 'it starts at rest');
    expectPlaysAsBaked(camera, baked);
  });

  test('TVPaint\'s straight ramp is a straight way', () {
    final (:camera, :baked) = pan(straight, frameCount: 25);
    final position = camera.track.position;

    expect(position.keys.keys, [0, 24]);
    expect(position.keys[0]!.outgoing, KeySide.linear);
    expect(position.keys[24]!.incoming, KeySide.linear);
    expectPlaysAsBaked(camera, baked);
  });

  test('each channel on its own keys: the zoom and the turn TVPaint keys '
      'only on the first key are one key each, however the position '
      'moves', () {
    final (:camera, baked: _) = pan(slowStart, frameCount: 25);

    expect(camera.track.scale.keys.keys, [0]);
    expect(camera.track.rotation.keys.keys, [0]);
  });

  test('TVPaint passes its last key a frame late: a cut that runs on past '
      'it is keyed where the move really stops too, and holds there', () {
    final (:camera, :baked) = pan(slowStart, frameCount: 40);
    final position = camera.track.position;

    expect(position.keys.keys, [0, 24, 25]);
    expect(position.keys[25]!.value.x, 1100, reason: 'the key\'s own value');
    expect(
      position.keys[24]!.value.x,
      lessThan(1100),
      reason: 'what TVPaint shows on the key\'s own frame',
    );
    expectPlaysAsBaked(camera, baked);
  });
}
