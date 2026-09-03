import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_input_settings.dart';

/// 🚨★★★THE TOUCH RULES ARE UNCHANGED BY THE DEVICE UNIFICATION.
///
/// 유저 2026-08-29: 「기존 타임라인이나 그런것들 터치가 스크롤로 작동하게
/// 하는 경우 스크롤로 작동하는건 유효한거지? 1핑거 드로잉일땐 물론 1핑거가
/// 마우스로 작동해야하지만 … 1핑거가 드로잉이 아닐땐 제대로 터치로 작동해서
/// 스크롤같은거 기존 규칙 유지된다던가」.
///
/// It is, and this is why: adding the mouse to `dragDevices` and giving
/// controls their own presses changed WHO OWNS A PRESS, not what a finger
/// means. The finger's meaning lives in [AppInput.timelineEditPanDevices]
/// and its two switches, and neither was touched.
///
/// ⛔This is the guard against "unifying" by flattening. If the edit-pan set
/// ever stops answering these three ways, a finger has silently lost either
/// its scroll or its edit.
void main() {
  tearDown(() {
    AppInput.settings.value = AppInputSettings.testCorpusBaseline;
  });

  void setInput({required bool draws}) {
    AppInput.settings.value = AppInput.settings.value.copyWith(
      touchDragOneFinger: draws
          ? CanvasTouchDragAction.draw
          : CanvasTouchDragAction.flip,
    );
  }

  test('드로잉 OFF — the finger SCROLLS, so no edit pan takes it', () {
    setInput(draws: false);
    expect(
      AppInput.timelineEditPanDevices.contains(PointerDeviceKind.touch),
      isFalse,
      reason:
          'the default: 「1핑거가 드로잉이 아닐땐 제대로 터치로 작동해서 '
          '스크롤」 — the edit pans stand aside and the scroll owns it',
    );
  });

  test('1핑거 드로잉 — the finger is the POINTER, so it edits like a mouse', () {
    setInput(draws: true);
    expect(
      AppInput.timelineEditPanDevices.contains(PointerDeviceKind.touch),
      isTrue,
      reason:
          '유저 확정 10: 「1핑거 드로잉일땐 터치를 마우스로 인식」 — and the '
          'cost was named by the user first: 「그러면 1핑거 드로잉에선 '
          '타임라인 스크롤 불가해지는거지 … 어차피 2핑거로 스크롤되니까」',
    );
  });

  test('🚨the POINTER devices are in BOTH states', () {
    // The unification's own claim: mouse and pen are one answer, and it
    // does not depend on the touch mode.
    for (final draws in const [true, false]) {
      setInput(draws: draws);
      for (final kind in const [
        PointerDeviceKind.mouse,
        PointerDeviceKind.stylus,
        PointerDeviceKind.invertedStylus,
      ]) {
        expect(
          AppInput.timelineEditPanDevices.contains(kind),
          isTrue,
          reason: '$kind with draws=$draws',
        );
      }
    }
  });
}
