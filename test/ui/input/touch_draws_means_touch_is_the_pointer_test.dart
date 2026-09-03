import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_input_settings.dart';

/// 🚨★★★터치 묘화 ON ⇒ A FINGER IS THE POINTER, PRESS AND ALL.
///
/// 유저 2026-08-29: 「**터치 묘화 on이면 터치가 마우스랑 완전 똑같이 작용
/// 하길 원하는데** 지금 그상태로 터치하면 탭다운으로 인덱스 바껴야하는데
/// 손떼야 바껴」.
///
/// ⛔THE CARVE-OUT WAS NEVER ABOUT TOUCH AS SUCH. It came from UI-R23 #2
/// (「the first scroll touch kept moving the playhead」) — a finger that is
/// NAVIGATING. With 터치 묘화 on the finger is not navigating, so the very
/// sentence that justified the carve-out is what lifts it.
void main() {
  tearDown(() {
    AppInput.settings.value = AppInputSettings.testCorpusBaseline;
  });

  void setTouchDraws({required bool draws}) {
    AppInput.settings.value = AppInput.settings.value.copyWith(
      touchDragOneFinger: draws
          ? CanvasTouchDragAction.draw
          : CanvasTouchDragAction.flip,
    );
  }

  test('a mouse always seeks on the press', () {
    for (final draws in [true, false]) {
      setTouchDraws(draws: draws);
      expect(
        AppInput.timelineCellPressSeeks(PointerDeviceKind.mouse),
        isTrue,
        reason: 'the mouse never depended on this setting',
      );
    }
  });

  test('a finger seeks on the press ONLY while 터치 묘화 is on', () {
    setTouchDraws(draws: true);
    expect(
      AppInput.timelineCellPressSeeks(PointerDeviceKind.touch),
      isTrue,
      reason: '터치 묘화 on — the finger IS the pointer',
    );

    // ⛔THE CONTROL, and it is UI-R23 #2 itself. A blanket flip would pass
    // the assertion above and bring back 「the first scroll touch kept
    // moving the playhead」.
    setTouchDraws(draws: false);
    expect(
      AppInput.timelineCellPressSeeks(PointerDeviceKind.touch),
      isFalse,
      reason:
          'in flip mode the finger is navigating, and a press that seeks '
          'is the bug the user reported in UI-R23 #2',
    );
  });

  test('it is the SAME question the tool door asks', () {
    // 🚨Not a parallel rule. The door's own doc says every input layer
    // written after it took fingers in flip mode because it did not ask —
    // this gate was one of them, and the fix is to ASK, not to copy the
    // condition into a second place that can drift.
    for (final draws in [true, false]) {
      setTouchDraws(draws: draws);
      for (final kind in PointerDeviceKind.values) {
        expect(
          AppInput.timelineCellPressSeeks(kind),
          AppInput.toolAcceptsPointer(kind),
          reason: '$kind with touchDraws=$draws',
        );
      }
    }
  });
}
