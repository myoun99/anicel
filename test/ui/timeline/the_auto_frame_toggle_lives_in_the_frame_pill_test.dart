import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/input/app_input_settings.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/timeline/timeline_action_toolbar.dart';
import 'package:anicel/src/ui/widgets/app_icon_button.dart';

/// 🚨F-61 (유저): 「프레임 자동생성 버튼 툴 설정에 있는데, **왜 이딴식으로
/// 결정한거지? 내가 분명 타임라인 헤더쪽에 두라하지않았나?** 프레임 알약 안,
/// **중간나누기 버튼 오른쪽**에 두도록. 기존 잔재는 삭제」.
///
/// 「중간나누기 버튼」 is `blank-exposure-button` — 「중간 없음 / ×」, 中割なし.
///
/// ⚠️These drive the REAL toolbar rather than a stand-in, because two of the
/// three claims are about the toolbar's own machinery: the group is memoized
/// and baked into a `StaticRaster`, so a toggle that reads the settings
/// without listening would show yesterday's state and a stand-in would never
/// notice.
void main() {
  setUp(() => AppInput.settings.value = const AppInputSettings());
  tearDown(() => AppInput.settings.value = const AppInputSettings());

  Future<void> pumpEditor(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();
  }

  Finder inToolbar(String keyValue) => find.descendant(
    of: find.byType(TimelineActionToolbar),
    matching: find.byWidgetPredicate(
      (w) => w is AppIconButton && w.keyValue == keyValue,
    ),
  );

  testWidgets('it sits inside the frame pill, right of the × button', (
    tester,
  ) async {
    await pumpEditor(tester);

    // ★The premise: BOTH buttons are in the frame pill's own group, so
    // "right of" is a position within one row rather than across the bar.
    final pill = find.byKey(
      const ValueKey<String>('timeline-toolbar-frame-group'),
    );
    expect(pill, findsOneWidget);
    for (final key in ['blank-exposure-button', 'auto-frame-toggle-button']) {
      expect(
        find.descendant(of: pill, matching: inToolbar(key)),
        findsOneWidget,
        reason: '$key is in the frame pill',
      );
    }

    final blankX = tester.getTopLeft(inToolbar('blank-exposure-button')).dx;
    final toggleX = tester.getTopLeft(inToolbar('auto-frame-toggle-button')).dx;
    final markX = tester.getTopLeft(inToolbar('toggle-mark-button')).dx;

    expect(toggleX, greaterThan(blankX), reason: '「중간나누기 버튼 오른쪽」');
    expect(
      markX,
      greaterThan(toggleX),
      reason: 'immediately right of × — the mark button moved over for it',
    );
  });

  testWidgets('pressing it flips the setting, and again flips it back', (
    tester,
  ) async {
    await pumpEditor(tester);
    expect(
      AppInput.settings.value.autoCreateFrameOnDraw,
      isFalse,
      reason: 'the premise: OFF is the default this feature ships with',
    );

    await tester.tap(inToolbar('auto-frame-toggle-button'));
    await tester.pumpAndSettle();
    expect(AppInput.settings.value.autoCreateFrameOnDraw, isTrue);

    await tester.tap(inToolbar('auto-frame-toggle-button'));
    await tester.pumpAndSettle();
    expect(AppInput.settings.value.autoCreateFrameOnDraw, isFalse);
  });

  // 🚨The one this file exists for. The group is baked into a `StaticRaster`
  // and memoized on a `rebuildKey` that knows nothing about `AppInput`, so a
  // toggle that merely READ the value would be right exactly once.
  testWidgets('the glyph follows the setting, in colour and nothing else', (
    tester,
  ) async {
    await pumpEditor(tester);

    Icon glyph() => tester
        .widget<AppIconButton>(inToolbar('auto-frame-toggle-button'))
        .icon as Icon;

    final off = glyph();
    expect(
      off.color,
      isNot(AppColors.accent),
      reason: 'off is the resting colour',
    );

    await tester.tap(inToolbar('auto-frame-toggle-button'));
    await tester.pumpAndSettle();

    final on = glyph();
    expect(on.color, AppColors.accent, reason: 'on says so in colour');
    expect(
      on.icon,
      off.icon,
      reason:
          '⛔and ONLY in colour — 「선택 표시는 색상만」, so the glyph itself '
          'must be the same one either way',
    );
  });

  // 「기존 잔재는 삭제」 — the switch it replaced is gone, not hidden.
  testWidgets('the brush panel no longer offers it', (tester) async {
    await pumpEditor(tester);
    expect(
      find.byKey(const ValueKey<String>('brush-auto-create-frame-switch')),
      findsNothing,
    );
  });
}
