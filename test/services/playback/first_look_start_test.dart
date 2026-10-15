import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/playback/first_look_start.dart';

/// 🚨A device's run starts on the first look of the clock that reads it —
/// not when it is armed (play-press-first-frame-stall).
void main() {
  test('an armed run starts on its first look — not at the arm, and once',
      () {
    final started = <String>[];
    final start = FirstLookStart()..arm(() => started.add('run'));

    expect(started, isEmpty, reason: 'the press arms; it starts nothing');
    start.look();
    expect(started, ['run']);
    start
      ..look()
      ..look();
    expect(started, ['run'], reason: 'every later look finds it started');
  });

  test('a run armed again before its first look is the run armed last', () {
    final started = <String>[];
    FirstLookStart()
      ..arm(() => started.add('pressed'))
      ..arm(() => started.add('sought'))
      ..look();

    expect(started, ['sought']);
  });

  test('a run stopped before its first look never starts — the next arm '
      'does', () {
    final started = <String>[];
    final start = FirstLookStart()
      ..arm(() => started.add('stopped'))
      ..disarm()
      ..look();
    expect(started, isEmpty);

    start
      ..arm(() => started.add('next'))
      ..look();
    expect(started, ['next']);
  });
}
