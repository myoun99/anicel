import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/services/input/pen_path_tally.dart';

/// The `path` line: how many points a contact took, how soon after the
/// press its first move's came, and the longest wait between two — in its
/// opening ([PenPathTally.opening]) and in all of it (F-611).
void main() {
  Duration ms(int milliseconds) => Duration(milliseconds: milliseconds);

  test('a wait is the opening\'s while the point that ends it is', () {
    final tally = PenPathTally()..press(ms(0));
    for (final at in [8, 16, 150, 158, 400]) {
      tally.take(ms(at));
    }
    expect(tally.said(), 'path pts=6 1st=8ms open=134ms max=242ms');
  });

  test('a contact said is let go of: the next is counted alone', () {
    final tally = PenPathTally()
      ..press(ms(0))
      ..take(ms(100));
    expect(tally.said(), 'path pts=2 1st=100ms open=100ms max=100ms');
    expect(tally.said(), isNull);

    tally
      ..press(ms(500))
      ..take(ms(504));
    expect(tally.said(), 'path pts=2 1st=4ms open=4ms max=4ms');
  });

  test('a press alone says no move', () {
    final tally = PenPathTally()..press(ms(0));
    expect(tally.said(), 'path pts=1 1st=- open=0ms max=0ms');
  });

  test('a point with no press before it counts nothing', () {
    final tally = PenPathTally()
      ..take(ms(30))
      ..take(ms(38));
    expect(tally.said(), isNull);
  });
}
