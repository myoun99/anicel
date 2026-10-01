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

  test('⛔another hand says nothing: a mouse in the air or pressing keeps a '
      'pen down, and a pen keeps a mouse', () {
    down(1, PointerDeviceKind.stylus);
    hover(2, PointerDeviceKind.mouse);
    down(3, PointerDeviceKind.mouse);
    expect(cancelled, isEmpty);

    hover(4, PointerDeviceKind.stylus);
    expect(cancelled, [1], reason: 'the pen\'s own hover lifts the pen alone');
    expect(census.anyDown, isTrue, reason: 'the mouse is still pressed');
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
