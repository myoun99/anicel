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
