import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/camera_instruction.dart';
import 'package:anicel/src/models/camera_moves.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/cut_camera.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/transform_track.dart';

/// 🗣️I-73 ⑤ (유저 2026-10-08): 「이 선 중앙에 카메라 움직임에 따라 지시명도
/// 적을거거든? 상하좌우로만 움직이면 팬, 확대가 있으면 상화좌우 있더라도
/// T.U, 축소면 같은규칙으로 T.B」 — the camera's move over each stretch
/// between two keys, judged by what plays. 🗣️I-89 (유저 2026-10-10):
/// 「그리고 회전은 모아트기준대로 하자」 — the turn alone is 回転, and a
/// move the turn changes along with is written after it. ↩️「3. 회전도
/// PAN으로 인식하도록」(10-08).
void main() {
  CameraPose at(double x, {double zoom = 1, double turn = 0}) => CameraPose(
    center: CanvasPoint(x: x, y: 0),
    zoom: zoom,
    rotationDegrees: turn,
  );

  TransformTrack keyed(Map<int, CameraPose> poses) =>
      CutCamera(keyframes: poses).track;

  test('the zoom growing is T.U and shrinking T.B, whatever moves with it — '
      'the turn changing with it says so', () {
    expect(
      cameraMoves(
        keyed({0: at(0), 10: at(0, zoom: 2), 20: at(50, zoom: 1.5, turn: 9)}),
      ),
      [
        (from: 0, to: 10, term: 'tu', turning: false),
        (from: 10, to: 20, term: 'tb', turning: true),
      ],
    );
  });

  test('🎯the position alone is PAN, the turn alone 回転, and the two '
      'together a PAN that turns', () {
    expect(
      cameraMoves(
        keyed({
          0: at(0),
          10: at(30),
          20: at(30, turn: 15),
          30: at(60, turn: 40),
        }),
      ),
      [
        (from: 0, to: 10, term: 'pan', turning: false),
        (from: 10, to: 20, term: cameraTurnTerm, turning: false),
        (from: 20, to: 30, term: 'pan', turning: true),
      ],
    );
  });

  test('a move is written in the glossary\'s words, after 回転 where it '
      'turns — 「回転 T.B」', () {
    final glossary = CameraInstructionSet.standard;
    String word(String term, {bool turning = false}) => cameraMoveWord((
      from: 0,
      to: 1,
      term: term,
      turning: turning,
    ), glossary.defById);

    expect(word('tb'), 'T.B');
    expect(word(cameraTurnTerm), '回転');
    expect(word('tb', turning: true), '回転 T.B');
    expect(word('pan', turning: true), '回転 PAN');
  });

  test('a stretch that does not move has no term — only its line', () {
    expect(cameraMoves(keyed({0: at(5), 10: at(5), 20: at(9)})), [
      (from: 10, to: 20, term: 'pan', turning: false),
    ]);
    expect(cameraMoves(keyed({4: at(5)})), isEmpty, reason: 'one key');
  });

  test('🚨judged by what plays: after a HOLD key the camera jumps to the next '
      'one, it does not move', () {
    final track = keyed({0: at(0), 10: at(40), 20: at(80)});
    final held = track.copyWith(
      position: PropertyTrack(
        keys: {
          for (final MapEntry(key: frame, value: key)
              in track.position.keys.entries)
            frame: frame == 0
                ? key.copyWith(outgoing: KeyExit.hold)
                : key,
        },
      ),
    );

    expect(cameraMoves(held), [
      (from: 10, to: 20, term: 'pan', turning: false),
    ]);
  });

  test('…and so does a stretch of one frame: the next key is a cut, not a '
      'move', () {
    expect(cameraMoves(keyed({0: at(0), 1: at(40), 9: at(80)})), [
      (from: 1, to: 9, term: 'pan', turning: false),
    ]);
  });

  test('a lane keyed alone moves the stretches it changes over', () {
    final zoomOnly = keyed({0: at(0), 10: at(0)}).copyWith(
      scale: PropertyTrack(
        keys: {
          4: PropertyKey(uniformScale(1)),
          8: PropertyKey(uniformScale(3)),
        },
      ),
    );

    expect(cameraMoves(zoomOnly), [
      (from: 4, to: 8, term: 'tu', turning: false),
    ]);
  });
}
