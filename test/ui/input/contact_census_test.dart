import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/input/contact_census.dart';

/// 🗣️F-232 — every way the census learns a press is over; see
/// [ContactCensus].
void main() {
  late List<int> cancelled;
  late ContactCensus census;

  setUp(() {
    cancelled = [];
    // The binding hands a cancel back through the global route — which is
    // how the census hears the press it let go of.
    census = ContactCensus(
      cancel: (pointer) {
        cancelled.add(pointer);
        census.note(PointerCancelEvent(pointer: pointer));
      },
    );
  });

  void down(int pointer, PointerDeviceKind kind) =>
      census.note(PointerDownEvent(pointer: pointer, kind: kind));

  void hover(int pointer, PointerDeviceKind kind) =>
      census.note(PointerHoverEvent(pointer: pointer, kind: kind));

  void up(int pointer, PointerDeviceKind kind) =>
      census.note(PointerUpEvent(pointer: pointer, kind: kind));

  test('🚨the census says WHAT is down — each contact\'s kind, pointer and '
      'age on the events\' own clock, so a screenshot names the press that '
      'lost its lift', () {
    expect(census.held, 'none');

    census.note(
      const PointerDownEvent(
        pointer: 1,
        kind: PointerDeviceKind.mouse,
        timeStamp: Duration(seconds: 10),
      ),
    );
    census.note(
      const PointerDownEvent(
        pointer: 5,
        kind: PointerDeviceKind.touch,
        timeStamp: Duration(seconds: 12),
      ),
    );
    census.note(
      const PointerMoveEvent(
        pointer: 5,
        kind: PointerDeviceKind.touch,
        timeStamp: Duration(milliseconds: 14500),
      ),
    );
    expect(census.held, 'mouse#1 +4.5s · touch#5 +2.5s');

    census.note(
      const PointerUpEvent(
        pointer: 5,
        kind: PointerDeviceKind.touch,
        timeStamp: Duration(seconds: 15),
      ),
    );
    expect(
      census.held,
      'mouse#1 +5.0s',
      reason: 'the press nothing lifts is the one that only gets older',
    );
  });

  test('a press is down until its lift or its cancel, and a hand that lifts '
      'cancels nothing', () {
    down(1, PointerDeviceKind.stylus);
    expect(census.anyDown, isTrue);
    up(1, PointerDeviceKind.stylus);
    hover(1, PointerDeviceKind.stylus);
    expect(census.anyDown, isFalse);

    down(2, PointerDeviceKind.touch);
    census.note(const PointerCancelEvent(pointer: 2));
    expect(census.anyDown, isFalse);
    expect(cancelled, isEmpty);
  });

  test('🚨a pen HOVERING back — under a new pointer — cancels the press '
      'whose lift was lost', () {
    down(1, PointerDeviceKind.stylus);

    hover(7, PointerDeviceKind.stylus);

    expect(cancelled, [1]);
    expect(census.anyDown, isFalse);
  });

  test('a hover under the press\'s OWN pointer says the same', () {
    down(1, PointerDeviceKind.stylus);

    hover(1, PointerDeviceKind.stylus);

    expect(cancelled, [1]);
  });

  test('a pen PRESSING again cancels the press it left and keeps the new '
      'one', () {
    down(1, PointerDeviceKind.stylus);

    down(2, PointerDeviceKind.stylus);

    expect(cancelled, [1]);
    expect(census.anyDown, isTrue, reason: 'the new press is down');
    up(2, PointerDeviceKind.stylus);
    expect(census.anyDown, isFalse);
  });

  test('the eraser end is the same pen', () {
    down(1, PointerDeviceKind.stylus);

    hover(3, PointerDeviceKind.invertedStylus);

    expect(cancelled, [1]);
  });

  test('a mouse in the air lets go of a mouse press', () {
    down(1, PointerDeviceKind.mouse);

    hover(1, PointerDeviceKind.mouse);

    expect(cancelled, [1]);
  });

  test('⛔a mouse says nothing of a pen: in the air or pressing, it keeps a '
      'pen down', () {
    down(1, PointerDeviceKind.stylus);
    hover(2, PointerDeviceKind.mouse);
    down(3, PointerDeviceKind.mouse);
    expect(cancelled, isEmpty);
  });

  test('⛔and a pen says nothing of a mouse: in the air — either end — or '
      'pressing, it lets go of its own press only (↩️F-232 let it go of the '
      'mouse\'s too; that press was the pen\'s echo, F-400)', () {
    down(1, PointerDeviceKind.mouse);
    down(2, PointerDeviceKind.stylus);
    hover(3, PointerDeviceKind.stylus);
    hover(4, PointerDeviceKind.invertedStylus);

    expect(cancelled, [2]);
    expect(census.held, 'mouse#1 +0.0s');
  });

  test('⛔fingers are many: a finger landing keeps another down, and no hand '
      'in the air lifts a finger', () {
    down(1, PointerDeviceKind.touch);
    down(2, PointerDeviceKind.touch);
    hover(3, PointerDeviceKind.stylus);
    hover(4, PointerDeviceKind.mouse);

    expect(cancelled, isEmpty);
    up(1, PointerDeviceKind.touch);
    expect(census.anyDown, isTrue, reason: 'the second finger is down');
  });

  test('the window losing the OS\'s focus cancels every press', () {
    down(1, PointerDeviceKind.touch);
    down(2, PointerDeviceKind.stylus);

    census.letGoOfEverything();

    expect(cancelled, unorderedEquals([1, 2]));
    expect(census.anyDown, isFalse);
  });
}
