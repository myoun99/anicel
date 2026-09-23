import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/widgets/boolean_dot.dart';

/// The app's one boolean (guide-sym ⑥⑧) — what it looks like in each state,
/// and what it must never carry.
void main() {
  Future<Icon> pumpDot(
    WidgetTester tester, {
    required bool value,
    bool inPickOneGroup = false,
    bool enabled = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Center(
            child: BooleanDot(
              value: value,
              inPickOneGroup: inPickOneGroup,
              enabled: enabled,
            ),
          ),
        ),
      ),
    );
    return tester.widget<Icon>(find.byType(Icon));
  }

  testWidgets('🚨a RING either way, and the dot is what changes — 유저: '
      '「적용시 안에 동그라미 추가. 구체적으론 환경설정-입력-태블릭서비스의 '
      '버튼처럼」', (tester) async {
    expect(
      (await pumpDot(tester, value: true)).icon,
      Icons.radio_button_checked,
    );
    expect(
      (await pumpDot(tester, value: false)).icon,
      Icons.radio_button_unchecked,
    );
  });

  testWidgets('it tells a screen reader its state — toggled, on or off, as '
      'the switch it replaced did', (tester) async {
    final semantics = tester.ensureSemantics();
    for (final value in [false, true]) {
      await pumpDot(tester, value: value);
      expect(
        tester.getSemantics(find.byType(BooleanDot)),
        isSemantics(hasToggledState: true, isToggled: value),
        reason: 'value: $value',
      );
    }
    semantics.dispose();
  });

  group('🚨the colour is 유저\'s rule: 「하나만 선택하는 그룹의 버튼이면 '
      '비활성화될때 색도 비활성화색으로 어둡게. 아니면 비활성화되도 색 '
      '변하지않고 흰색 그대로」', () {
    testWidgets('ON is the accent, in a group or alone', (tester) async {
      for (final inPickOneGroup in [false, true]) {
        expect(
          (await pumpDot(
            tester,
            value: true,
            inPickOneGroup: inPickOneGroup,
          )).color,
          AppColors.accent,
          reason: 'inPickOneGroup: $inPickOneGroup',
        );
      }
    });

    testWidgets('OFF in a pick-one group steps back, in the off alpha the '
        'eye wears', (tester) async {
      expect(
        (await pumpDot(tester, value: false, inPickOneGroup: true)).color,
        AppColors.text.withValues(alpha: AppColors.offAlpha),
      );
    });

    testWidgets('OFF on its own stays WHITE — and says so, rather than '
        'taking the ink around it', (tester) async {
      // ⚠️NAMED, not inherited: a `ListTile` inks a trailing glyph in the dim
      // `onSurfaceVariant`, so a null here would have dimmed every
      // standalone flag in the Preferences window.
      expect(
        (await pumpDot(tester, value: false)).color,
        AppColors.text,
      );
    });

    testWidgets('a dead one is the app\'s disabled glyph, on or off — the '
        'GLYPH still tells them apart', (tester) async {
      for (final value in [false, true]) {
        final dot = await pumpDot(tester, value: value, enabled: false);
        expect(dot.color, AppColors.glyphDisabled, reason: 'value: $value');
      }
    });
  });

  group('BooleanDotButton', () {
    Future<List<bool>> pumpButton(
      WidgetTester tester, {
      required bool value,
      bool live = true,
    }) async {
      final changes = <bool>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: Center(
              child: BooleanDotButton(
                keyValue: 'probe',
                tooltip: 'Probe',
                value: value,
                onChanged: live ? changes.add : null,
              ),
            ),
          ),
        ),
      );
      return changes;
    }

    testWidgets('a press hands over the value it does NOT hold', (
      tester,
    ) async {
      for (final value in [false, true]) {
        final changes = await pumpButton(tester, value: value);
        await tester.tap(find.byKey(const ValueKey<String>('probe')));
        await tester.pumpAndSettle();
        expect(changes, [!value], reason: 'from $value');
      }
    });

    testWidgets('a null onChanged is a dead button, and its dot says so', (
      tester,
    ) async {
      final changes = await pumpButton(tester, value: true, live: false);
      await tester.tap(
        find.byKey(const ValueKey<String>('probe')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      expect(changes, isEmpty);
      expect(
        tester.widget<Icon>(find.byType(Icon)).color,
        AppColors.glyphDisabled,
      );
    });

    testWidgets('🚨NO `Opacity` in it, on or off, live or dead (board '
        '`a-panel-with-a-switch-can-never-bake`) — one is a repaint '
        'boundary at any alpha above zero', (tester) async {
      for (final value in [false, true]) {
        for (final live in [false, true]) {
          await pumpButton(tester, value: value, live: live);
          expect(
            find.descendant(
              of: find.byType(BooleanDotButton),
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is Opacity ||
                    widget is AnimatedOpacity ||
                    widget is FadeTransition,
              ),
            ),
            findsNothing,
            reason: 'value: $value, live: $live',
          );
        }
      }
    });
  });
}
