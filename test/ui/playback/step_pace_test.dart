import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/playback/step_pace.dart';

const _ms = Duration(milliseconds: 1);

void main() {
  late int now;
  late StepPace pace;

  /// [count] frames [gap] apart, after the ones before.
  var frame = Duration.zero;
  void frames(int count, Duration gap) {
    for (var i = 0; i < count; i += 1) {
      frame += gap;
      pace.painted(frame);
    }
  }

  /// A step that took [took], asked for at once.
  void step(Duration took) {
    pace
      ..askNow()
      ..asked();
    now += took.inMicroseconds;
    pace.landed();
  }

  void steps(int count, Duration took) {
    for (var i = 0; i < count; i += 1) {
      step(took);
    }
  }

  setUp(() {
    now = 0;
    frame = Duration.zero;
    pace = StepPace(nowMicros: () => now);
    frames(1, _ms);
  });

  test('a step is held for what the last ones leave of a frame, less the '
      'margin', () {
    frames(4, _ms * 7);
    steps(4, _ms * 3);
    expect(pace.ask(), _ms * 3);
  });

  test('says nothing on fewer than four frames, or fewer than four steps', () {
    frames(3, _ms * 7);
    steps(4, _ms * 3);
    expect(pace.ask(), Duration.zero, reason: 'three frames');

    frames(1, _ms * 7);
    expect(pace.ask(), isNot(Duration.zero), reason: '⛔premise: four');

    final fresh = StepPace(nowMicros: () => now);
    fresh.painted(_ms);
    for (var i = 2; i < 6; i += 1) {
      fresh.painted(_ms * (i * 7));
    }
    for (var i = 0; i < 3; i += 1) {
      fresh
        ..askNow()
        ..asked()
        ..landed();
    }
    expect(fresh.ask(), Duration.zero, reason: 'three steps');
  });

  test('the longest of the last four steps, not the last', () {
    frames(4, _ms * 16);
    steps(1, _ms * 9);
    steps(3, _ms * 2);
    expect(pace.ask(), _ms * 6);
  });

  test('a step past the last four counts no more', () {
    frames(4, _ms * 16);
    steps(1, _ms * 9);
    steps(4, _ms * 2);
    expect(pace.ask(), _ms * 13);
  });

  test('the shortest of the last four frames: a pause is no longer frame', () {
    frames(3, _ms * 7);
    frames(1, _ms * 300);
    steps(4, _ms * 3);
    expect(pace.ask(), _ms * 3);
  });

  test('a frame past the last four counts no more', () {
    frames(1, _ms * 7);
    frames(4, _ms * 16);
    steps(4, _ms * 3);
    expect(pace.ask(), _ms * 12);
  });

  test('a paint twice in a frame is no frame between', () {
    frames(4, _ms * 7);
    for (var i = 0; i < 4; i += 1) {
      pace.painted(frame);
    }
    steps(4, _ms * 3);
    expect(pace.ask(), _ms * 3);
  });

  test('none where the steps leave too little to wait for', () {
    frames(4, _ms * 7);
    steps(4, const Duration(microseconds: 5600));
    expect(pace.ask(), Duration.zero, reason: '400 µs is left');

    steps(4, const Duration(microseconds: 5500));
    expect(pace.ask(), const Duration(microseconds: 500));
  });

  test('none where the steps take the frame or more', () {
    frames(4, _ms * 7);
    steps(4, _ms * 11);
    expect(pace.ask(), Duration.zero);
  });

  test('a step held counts from when it was to go, so a timer\'s lateness is '
      'in what it took', () {
    frames(4, _ms * 16);
    steps(4, _ms * 3);
    expect(pace.ask(), _ms * 12, reason: '⛔premise: held');

    now += (_ms * 12).inMicroseconds; // Held for that.
    now += (_ms * 2).inMicroseconds; // A timer 2 late.
    pace.asked();
    now += (_ms * 3).inMicroseconds; // The step.
    pace.landed();
    expect(pace.ask(), _ms * 10);
  });

  test('a step that went before it was due counts from when it went', () {
    frames(4, _ms * 16);
    steps(4, _ms * 3);
    expect(pace.ask(), _ms * 12, reason: '⛔premise: held');

    pace.asked();
    now += (_ms * 5).inMicroseconds;
    pace.landed();
    expect(pace.ask(), _ms * 10);
  });

  test('a paint with a step out does not move when that step went', () {
    frames(4, _ms * 16);
    steps(4, _ms * 3);
    pace
      ..askNow()
      ..asked();
    now += (_ms * 5).inMicroseconds;
    pace.ask();
    now += (_ms * 1).inMicroseconds;
    pace.landed();
    expect(pace.ask(), _ms * 9);
  });
}
