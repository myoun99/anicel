import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/playback/first_look_start.dart';

/// 🚨A device's run starts on the first look of the clock that reads it —
/// not when it is armed (play-press-first-frame-stall).
void main() {
  test('an armed run starts on its first look — not at the arm, and once',
      () {
    final started = <String>[];
    final start = FirstLookStart()..arm((_) => started.add('run'));

    expect(started, isEmpty, reason: 'the press arms; it starts nothing');
    start.look(frameTime: null);
    expect(started, ['run']);
    start
      ..look(frameTime: null)
      ..look(frameTime: null);
    expect(started, ['run'], reason: 'every later look finds it started');
  });

  test('a run armed again before its first look is the run armed last', () {
    final started = <String>[];
    FirstLookStart()
      ..arm((_) => started.add('pressed'))
      ..arm((_) => started.add('sought'))
      ..look(frameTime: null);

    expect(started, ['sought']);
  });

  test('a run stopped before its first look never starts — the next arm '
      'does', () {
    final started = <String>[];
    final start = FirstLookStart()
      ..arm((_) => started.add('stopped'))
      ..disarm()
      ..look(frameTime: null);
    expect(started, isEmpty);

    start
      ..arm((_) => started.add('next'))
      ..look(frameTime: null);
    expect(started, ['next']);
  });

  // board a-start-is-heard-ahead-of-its-first-picture: the run's first
  // sample is heard as the look's frame is shown, so the start must know
  // when that is (`HeardOnTheDevice.leadFor`).
  test('🚨the run starts told when the look that starts it is shown', () {
    final told = <Duration?>[];
    final start = FirstLookStart()..arm(told.add);

    start.look(frameTime: const Duration(milliseconds: 40));
    start.look(frameTime: const Duration(milliseconds: 80));
    expect(told, [const Duration(milliseconds: 40)]);
  });
}
