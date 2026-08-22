import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/input/app_input_settings.dart';

/// 🚨결정 10 (유저 확정 2026-08-22) — **A FINGER IS A MOUSE WHEN IT DRAWS.**
///
/// > 「1핑거 드로잉모드일때는 타임라인 터치시 **선택범위나 엣지조작
/// > 작동하게하고싶은데 안돼있음.** 1핑거 드로잉일땐 **터치를 마우스로
/// > 인식**하게하면 **다른 패널도 공통적으로** 마우스로 할수있는조작
/// > 할수있게되서 **통일성면에서도 좋을거같음**」
///
/// The mode is the user's own global statement about what one finger IS.
/// Inside the canvas it says "the drawing hand"; outside it says "the
/// pointer". The timeline's scroll ownership yields to it.
///
/// ⚠️The cost was named by the USER first: 「그러면 1핑거 드로잉에선
/// **타임라인 스크롤 불가**해지는거지 … **그걸 원해서 한 말이야.** 어차피
/// 2핑거로 스크롤되니까」.
void main() {
  setUp(() {
    AppInput.settings.value = const AppInputSettings();
  });
  tearDown(() {
    AppInput.settings.value = const AppInputSettings();
  });

  bool touchEdits() =>
      AppInput.timelineEditPanDevices.contains(PointerDeviceKind.touch);

  test('scroll ON + one finger NOT drawing: the finger scrolls, as before',
      () {
    AppInput.settings.value = const AppInputSettings(
      touchTimelineScroll: true,
      touchDragOneFinger: CanvasTouchDragAction.navigate,
    );
    expect(AppInput.touchDraws, isFalse, reason: 'presence first');
    expect(
      touchEdits(),
      isFalse,
      reason: 'the timeline scroll owns the finger — the pre-결정 10 answer, '
          'and it must survive for anyone who kept that mode',
    );
  });

  test('scroll ON + one finger DRAWS: the finger edits instead (결정 10)', () {
    AppInput.settings.value = const AppInputSettings(
      touchTimelineScroll: true,
      touchDragOneFinger: CanvasTouchDragAction.draw,
    );
    expect(AppInput.touchDraws, isTrue, reason: 'presence first');
    expect(
      touchEdits(),
      isTrue,
      reason: '1핑거 드로잉이면 터치는 마우스다 — 선택범위·엣지조작이 손가락 '
          '하나로 되어야 한다. 대가(타임라인 스크롤 상실)는 유저가 먼저 '
          '받아들였다',
    );
  });

  test('scroll OFF: the finger edits either way — the mode only ADDS reach',
      () {
    for (final action in [
      CanvasTouchDragAction.navigate,
      CanvasTouchDragAction.draw,
    ]) {
      AppInput.settings.value = AppInputSettings(
        touchTimelineScroll: false,
        touchDragOneFinger: action,
      );
      expect(
        touchEdits(),
        isTrue,
        reason: 'with scroll off the finger already edited; 결정 10 must not '
            'take that away for $action',
      );
    }
  });

  test('⛔the app never asks WHAT DEVICE it is on — the mode is the whole '
      'answer', () {
    // 유저 확정 2026-08-22: 「아이폰이면 강제 터치그리기같은거 없애. **기종
    // 묻지말고 그냥 핑거 모드따라가도록**」.
    //
    // There used to be a capability rule: iOS below a physical-size
    // threshold had no pen, so the one-finger slot was FORCED to draw
    // whatever the user had chosen. It measured hardware to guess an intent
    // the user states directly, and it made the setting silently inert on
    // one platform — a user who set one finger to navigate watched it not
    // happen with no way to find out why.
    for (final platform in TargetPlatform.values) {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      AppInput.settings.value = const AppInputSettings(
        touchDragOneFinger: CanvasTouchDragAction.navigate,
      );
      expect(
        AppInput.touchDraws,
        isFalse,
        reason: 'on $platform the STORED mode says navigate, so a finger '
            'navigates — no platform gets to override it',
      );
      AppInput.settings.value = const AppInputSettings(
        touchDragOneFinger: CanvasTouchDragAction.draw,
      );
      expect(AppInput.touchDraws, isTrue, reason: 'and draw means draw');
    }
    debugDefaultTargetPlatformOverride = null;
  });

  test('⛔the canvas is a different question and keeps its own answer', () {
    AppInput.settings.value = const AppInputSettings(
      touchTimelineScroll: true,
      touchDragOneFinger: CanvasTouchDragAction.draw,
    );
    expect(
      AppInput.toolPointerDevices,
      isNull,
      reason: 'null is "every device welcome" — the canvas tool gate reads '
          'touchDraws directly and 결정 10 must not disturb it',
    );

    AppInput.settings.value = const AppInputSettings(
      touchTimelineScroll: false,
      touchDragOneFinger: CanvasTouchDragAction.flip,
    );
    expect(
      AppInput.toolPointerDevices,
      isNot(contains(PointerDeviceKind.touch)),
      reason: 'a finger on FLIP is navigating, and a canvas tool acting on '
          'it stays a bug — 「드로잉모드가 아닌이상은 툴이 작동하면 안되지」',
    );
  });
}
