import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/services/canvas_flood_fill.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/tool_settings_panel.dart';
import 'package:anicel/src/ui/brush/tool_settings_section.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/widgets/boolean_dot.dart';
import 'package:anicel/src/ui/widgets/field_slider.dart';
import 'package:anicel/src/ui/widgets/settings_rows.dart';

/// 🗣️tool-settings-panel-tidy (유저 F-328 2026-10-10): 「도구마다 디자인이나
/// 조작 다 다르다던가 세련되지않은 정돈되지않은느낌」 — answered 「다
/// 추천대로」: one name style, one row height, the groups named in the
/// program's language.
void main() {
  Future<void> pumpTool(WidgetTester tester, CanvasTool tool) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 900,
            child: ToolSettingsPanel(
              state: BrushToolState(tool: tool),
              onChanged: (_) {},
              fillOptions: const FloodFillOptions(),
              onFillOptionsChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  double sizeOf(WidgetTester tester, String words) =>
      tester.renderObject<RenderParagraph>(find.text(words)).text.style!
          .fontSize!;

  testWidgets('a switch row is named as a bar and a choice are — the '
      'panel\'s one name style, a bar\'s row tall', (tester) async {
    await pumpTool(tester, CanvasTool.fill);
    final names = Theme.of(
      tester.element(find.byType(ToolSettingsPanel)),
    ).textTheme.labelSmall!;

    final strings = AppText.strings;
    for (final name in [
      strings.brAntiAlias,
      strings.brTolerance,
      strings.toolReadSource,
    ]) {
      expect(sizeOf(tester, name), names.fontSize, reason: name);
    }
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey<String>('fill-anti-alias-switch')),
          )
          .height,
      ToolSettingsSection.rowHeight,
    );
  });

  // 🗣️2차 (유저 2026-10-10): 「텍스트도구나 도형의 선/채움이런거 설정끼리
  // 사각형 박스 크기가 다 달라서 정돈된느낌 하나도안들어. X값Y값 크기
  // 통일한것처럼 이런부분 다 통일해서 정돈된 행/열 느낌 나도록」.
  testWidgets('🚨ONE GRID: a tool\'s controls start at one x and end at '
      'one x — the chip, the bar\'s track, the strip, the swatch and the '
      'ring alike — and every row stands one bar and one gap tall', (
    tester,
  ) async {
    await pumpTool(tester, CanvasTool.text);
    Rect rectOf(String key) =>
        tester.getRect(find.byKey(ValueKey<String>(key)));
    final chip = rectOf('text-tool-font');
    final bar = rectOf('text-tool-size');
    final strip = rectOf('text-tool-writing');
    final swatch = rectOf('text-tool-color');
    final ring = tester.getRect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('text-tool-bold')),
        matching: find.byType(BooleanDot),
      ),
    );

    for (final (name, control) in [('bar', bar), ('strip', strip)]) {
      expect(control.left, moreOrLessEquals(chip.left), reason: name);
    }
    // A bar's ± stand in the end column, past where every control ends.
    final end = bar.right - FieldSlider.stepperReach;
    for (final (name, control) in [
      ('chip', chip),
      ('strip', strip),
      ('swatch', swatch),
      ('ring', ring),
    ]) {
      expect(control.right, moreOrLessEquals(end), reason: name);
    }
    expect(strip.height, FieldSlider.defaultHeight);
    // A swatch's row is a bar's row tall, though the swatch is not.
    expect(
      rectOf('text-tool-outline').center.dy - swatch.center.dy,
      moreOrLessEquals(ToolSettingsSection.rowHeight),
    );
  });

  testWidgets('⛔a switch row anywhere else keeps the dense name it had', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: SettingsSwitchRow(
            label: 'Elsewhere',
            value: true,
            onChanged: (_) {},
          ),
        ),
      ),
    );
    expect(sizeOf(tester, 'Elsewhere'), 13);
  });

  testWidgets('the brush\'s groups are named in the program\'s language', (
    tester,
  ) async {
    AppText.settings.value = const AppLanguageSettings(
      programLanguage: AppLanguage.ko,
      notationLanguage: AppLanguage.ko,
    );
    addTearDown(() => AppText.settings.value = const AppLanguageSettings());
    await pumpTool(tester, CanvasTool.brush);

    final strings = AppText.strings;
    expect(find.text(strings.brGroupInk), findsOneWidget);
    expect(strings.brGroupInk, isNot('Ink'), reason: 'the premise: ko');
    for (final english in const ['Ink', 'Brush tip', 'Randomness']) {
      expect(find.text(english), findsNothing, reason: english);
    }
  });
}
