import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/transform_track.dart' show doubleKeySpace;
import 'package:flutter_test/flutter_test.dart';

/// I-89 ③: a header graph draws a lane's curve through times BETWEEN its
/// frames, by the one reading of the track its value column prints at a
/// frame ([PropertyTrack.resolveAtTime] — the frame's own reading is it).
void main() {
  double at(PropertyTrack<double> track, double time) => track.resolveAtTime(
    time: time,
    orElse: () => -1,
    space: doubleKeySpace,
  );

  double onFrame(PropertyTrack<double> track, int frame) => track.resolveAt(
    frameIndex: frame,
    orElse: () => -1,
    space: doubleKeySpace,
  );

  // Eased out of 2, straight from 6 to 9, held on 9 until 12.
  final track = PropertyTrack<double>()
      .withKey(2, 10, outgoing: const EaseSide())
      .withKey(6, 30)
      .withKey(9, 0, outgoing: KeyExit.hold)
      .withKey(12, 50);

  test('on a frame it is that frame\'s value — the one the value column '
      'prints', () {
    for (var frame = 0; frame <= 14; frame += 1) {
      expect(
        at(track, frame.toDouble()),
        onFrame(track, frame),
        reason: 'frame $frame',
      );
    }
  });

  test('between two frames the segment they lie in answers', () {
    expect(at(track, 7.5), closeTo(15, 1e-9), reason: 'half of 6 → 9');
    expect(at(track, 8.5), closeTo(5, 1e-9), reason: 'the frame before a key');
    expect(
      at(track, 6.5),
      closeTo(25, 1e-9),
      reason: 'just past a key: the segment leaving it',
    );
  });

  test('a key is only on its own frame', () {
    expect(at(track, 6), 30);
    expect(at(track, 5.999), allOf(lessThan(30), greaterThan(29)));
  });

  test('a segment eases between frames as it eases on them', () {
    const straight = 10 + 20 * 0.5 / 4;
    expect(at(track, 2.5), allOf(greaterThan(10), lessThan(straight)));
  });

  test('a hold stays held until the next key\'s frame', () {
    expect(at(track, 9.5), 0);
    expect(at(track, 11.999), 0);
    expect(at(track, 12), 50);
  });

  test('before the first key and after the last, the nearest key — and the '
      'default where there is none', () {
    expect(at(track, 0.5), 10);
    expect(at(track, 13.25), 50);
    expect(at(PropertyTrack<double>(), 3.5), -1);
  });
}
