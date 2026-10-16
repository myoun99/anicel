import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/playback/behind_its_clock.dart';

/// 🚨A run behind its clock shows every picture as its mode says — and the
/// first look after its clock starts is never lateness (F-364-Q1 b), for
/// the canvas's run and the media viewer's alike
/// (F-364-every-picture-even-when-late-Q1 a).
void main() {
  test('🚨the first look after the clock starts is its start — every look '
      'after it shows every picture', () {
    final behind = BehindItsClock(() => true)..clockStarts();

    expect(behind.look(), isFalse, reason: 'its start, not lateness');
    expect(behind.look(), isTrue);
    expect(behind.look(), isTrue);

    behind.clockStarts();
    expect(
      behind.look(),
      isFalse,
      reason: 'started again — a press, a run going on, a clock put back',
    );
    expect(behind.look(), isTrue);
  });

  test('a run whose mode keeps time never shows every picture — and a mode '
      'picked under a run holds from its next look, which is not its '
      'start', () {
    var shows = false;
    final behind = BehindItsClock(() => shows)..clockStarts();
    behind.look();

    expect(behind.look(), isFalse, reason: 'skipping frames keeps time');
    shows = true;
    expect(behind.look(), isTrue);
  });
}
