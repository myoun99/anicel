import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/input/app_input_settings.dart';
import 'package:anicel/src/ui/panels/tool_size_preset_panel.dart';

/// **I-2 — the tool's sizes, as buttons.**
///
/// 유저 2026-08-24: 「클튜처럼 툴 사이즈 패널 만들고싶음. **프리셋으로서 툴
/// 사이즈.** 브러시면 브러시 사이즈들이 여러개 존재해서 그거 누르면 브러시
/// 사이즈 바뀌는 패널」 · 유저 결정 2026-08-25: 「**새 패널로 만든다 — 이번은
/// 예외**」.
///
/// ⚠️The sizes ARE the snap list. Two lists of the same thing would drift
/// the day someone edited one, and the app has no other list of sizes — so
/// the panel shows what the size drag already snaps to, and adds no editor
/// of its own.
void main() {
  Future<List<double>> pumpPanel(
    WidgetTester tester, {
    double size = 8,
  }) async {
    final picked = <double>[];
    addTearDown(() {
      AppInput.settings.value = AppInputSettings.testCorpusBaseline;
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 260,
            height: 320,
            child: ToolSizePresetPanel(
              size: size,
              onSizeSelected: picked.add,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return picked;
  }

  Finder chip(double value) => find.byKey(
    ValueKey<String>('tool-size-preset-${ToolSizePresetPanel.label(value)}'),
  );

  testWidgets('every snap is a button, and pressing one asks for that size', (
    tester,
  ) async {
    AppInput.settings.value = AppInputSettings.testCorpusBaseline.copyWith(
      brushSizeSnaps: const [2, 8, 32],
    );
    final picked = await pumpPanel(tester);

    for (final size in [2.0, 8.0, 32.0]) {
      expect(chip(size), findsOneWidget, reason: '$size');
    }
    expect(
      chip(64),
      findsNothing,
      reason: 'the list is the user\'s, not a table of this panel\'s own',
    );

    await tester.tap(chip(32));
    await tester.pumpAndSettle();
    expect(picked, [32]);
  });

  testWidgets('the size the tool is on reads as selected — by colour', (
    tester,
  ) async {
    AppInput.settings.value = AppInputSettings.testCorpusBaseline.copyWith(
      brushSizeSnaps: const [2, 8, 32],
    );
    await pumpPanel(tester, size: 8);

    Color colourOf(double value) =>
        tester.widget<Material>(
          find.descendant(of: chip(value), matching: find.byType(Material)),
        ).color!;

    expect(
      colourOf(8),
      isNot(colourOf(2)),
      reason: 'selection reads by COLOUR only — no checkmark, the app rule',
    );
    expect(colourOf(2), colourOf(32));
  });

  testWidgets('and it follows the list being edited elsewhere', (
    tester,
  ) async {
    AppInput.settings.value = AppInputSettings.testCorpusBaseline.copyWith(
      brushSizeSnaps: const [2, 8],
    );
    await pumpPanel(tester);
    expect(chip(300), findsNothing);

    AppInput.settings.value = AppInput.settings.value.copyWith(
      brushSizeSnaps: const [2, 8, 300],
    );
    await tester.pumpAndSettle();

    expect(
      chip(300),
      findsOneWidget,
      reason: 'one list, so editing it in Input settings is editing this',
    );
  });
}
