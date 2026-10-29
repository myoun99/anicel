import 'package:anicel/src/models/app_input_settings.dart';
import 'package:anicel/src/ui/canvas/canvas_touch_contacts.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

/// 🗣️I-121-Q1 (유저 2026-10-22): 「손가락도 — 세는 곳을 하나로 묶고
/// 나서」 — a finger resting on the glass beside a press is a tablet's
/// modifier key held (I-69-Q5), and every reader asks it of ONE count: the
/// stroke's Shift, the transform's and the shape's modifier, the text box's
/// carry, the stamp's Shift. The brush view and the selection layer each
/// kept a count of their own, and the two answered the same question
/// differently.
void main() {
  setUp(CanvasTouchContacts.reset);
  tearDown(() {
    CanvasTouchContacts.reset();
    AppInput.settings.value = AppInputSettings.testCorpusBaseline;
  });

  void down(int pointer, {PointerDeviceKind kind = PointerDeviceKind.touch}) =>
      CanvasTouchContacts.noteAppWide(
        PointerDownEvent(pointer: pointer, kind: kind),
      );

  void up(int pointer, {PointerDeviceKind kind = PointerDeviceKind.touch}) =>
      CanvasTouchContacts.noteAppWide(
        PointerUpEvent(pointer: pointer, kind: kind),
      );

  void cancel(int pointer) => CanvasTouchContacts.noteAppWide(
    PointerCancelEvent(pointer: pointer, kind: PointerDeviceKind.touch),
  );

  test('a finger besides a press is one other than its own', () {
    down(1);

    expect(CanvasTouchContacts.aFingerDownBesides(1), isFalse);
    expect(CanvasTouchContacts.aFingerDownBesides(2), isTrue);
  });

  test('besides nothing, it is any finger at all', () {
    expect(CanvasTouchContacts.aFingerDownBesides(null), isFalse);
    down(1);
    expect(CanvasTouchContacts.aFingerDownBesides(null), isTrue);
  });

  test('a pen or a mouse is no finger', () {
    down(1, kind: PointerDeviceKind.stylus);
    down(2, kind: PointerDeviceKind.mouse);

    expect(CanvasTouchContacts.aFingerDownBesides(null), isFalse);
  });

  test('a finger holds a MOVE\'s Shift beside a pen\'s or a mouse\'s drag '
      '— a finger\'s own drag takes none (I-136, as the stamp\'s '
      'I-121-Q1)', () {
    bool holds({required bool byTouch}) =>
        CanvasTouchContacts.aFingerHoldsAMovesShift(byTouch: byTouch);
    expect(holds(byTouch: false), isFalse);
    down(1);

    expect(holds(byTouch: false), isTrue);
    expect(holds(byTouch: true), isFalse);
  });

  group('a finger leaving', () {
    late List<bool> heard;

    setUp(() {
      heard = [];
      void listener() =>
          heard.add(CanvasTouchContacts.aFingerDownBesides(null));
      CanvasTouchContacts.addAppWideLiftListener(listener);
      addTearDown(
        () => CanvasTouchContacts.removeAppWideLiftListener(listener),
      );
    });

    test('is heard once the count no longer counts it', () {
      down(1);
      down(2);
      up(1);
      up(2);

      expect(heard, [true, false]);
    });

    test('cancelled, it is heard as lifted', () {
      down(1);
      cancel(1);

      expect(heard, [false]);
    });

    test('⛔what was never counted leaves nothing to hear', () {
      up(5);
      down(1, kind: PointerDeviceKind.stylus);
      up(1, kind: PointerDeviceKind.stylus);

      expect(heard, isEmpty);
    });
  });

  group('a stroke\'s Shift', () {
    test('⛔off — as the switch comes — a finger holds none', () {
      down(9);

      expect(AppInput.settings.value.strokeFingerModifier, isFalse);
      expect(CanvasTouchContacts.aFingerHoldsAStrokesShift(3), isFalse);
    });

    test('on, it is a finger resting besides the stroke', () {
      AppInput.settings.value = AppInputSettings.testCorpusBaseline.copyWith(
        strokeFingerModifier: true,
      );
      down(3);

      expect(CanvasTouchContacts.aFingerHoldsAStrokesShift(3), isFalse);
      down(9);
      expect(CanvasTouchContacts.aFingerHoldsAStrokesShift(3), isTrue);
    });
  });
}
