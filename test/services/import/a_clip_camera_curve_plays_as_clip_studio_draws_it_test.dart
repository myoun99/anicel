import 'package:anicel/src/services/import/clip_track_clip.dart';
import 'package:flutter_test/flutter_test.dart';

/// 보드 `clip-camera-folder-is-a-folder-transform` (유저 10-13: 「보간은 클립은
/// 그래프를 만지면 시간+공간을 같이움직임」): a 2D camera's value plays its
/// keys the way CLIP STUDIO drew the user's camera sample, frame for frame —
/// its own way slow out and slow in, a graph's way the cubic its slopes
/// make, a held key held.
void main() {
  ClipCurve curve(List<(double, double)> keys, List<ClipWay> ways) => ClipCurve(
    [for (final (frame, value) in keys) (frame: frame, value: value)],
    ways,
  );

  const flat = ClipCubic(leaving: 0, arriving: 0);

  test('🎯CLIP STUDIO\'s own way is no straight ramp: it leaves slowly and '
      'comes in slowly — 3u² − 2u³ of the way, After Effects\' Easy Ease', () {
    final pan = curve([(0, 100), (40, 300)], [flat]);

    expect(pan.at(10), closeTo(100 + 200 * 0.15625, 1e-9));
    expect(pan.at(20), closeTo(200, 1e-9));
    expect(pan.at(30), closeTo(100 + 200 * 0.84375, 1e-9));
  });

  test('a cubic whose slopes are the way\'s own average runs straight — the '
      'slopes span the whole way, in value per frame', () {
    final pan = curve(
      [(0, 100), (40, 300)],
      [const ClipCubic(leaving: 5, arriving: 5)],
    );

    for (final frame in [5.0, 13.0, 27.5]) {
      expect(pan.at(frame), closeTo(100 + 5 * frame, 1e-9));
    }
  });

  test('🎯a graph pulled steep at the start overshoots and comes back — the '
      'user\'s sample: 56 over 29 frames, leaving at 9.04 a frame, peaks a '
      'tenth past the end, as CLIP STUDIO\'s output did', () {
    final pan = curve(
      [(0, 0), (29, 56)],
      [const ClipCubic(leaving: 9.0436, arriving: 0)],
    );

    final peak = [
      for (var frame = 0; frame <= 29; frame += 1) pan.at(frame.toDouble())!,
    ].reduce((a, b) => a > b ? a : b);
    expect(peak / 56, closeTo(1.10, 0.005));
    expect(pan.at(29), 56);
  });

  test('a held key holds to the next; a way this reader does not know runs '
      'straight, and is said', () {
    final turn = curve(
      [(0, 0), (10, 30), (20, 50)],
      [ClipWay.held, ClipWay.straight],
    );

    expect([turn.at(9.9), turn.at(10), turn.at(15)], [0, 30, 40]);
    expect(turn.unread, isTrue);
    expect(curve([(0, 0), (10, 30)], [ClipWay.held]).unread, isFalse);
  });

  test('before its first key a curve is its first value, after its last its '
      'last, and its keys stand where its ticks land, unrounded', () {
    final pan = curve([(2.5, 10), (7.5, 20)], [ClipWay.straight]);

    expect([pan.at(0), pan.at(5), pan.at(9)], [10, 15, 20]);
    expect(pan.keyedFrames, [3, 8]);
    expect(ClipCurve.none.at(4), isNull);
    expect(ClipCurve.held(0, 7).at(4), 7);
  });
}
