import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/brush_value_group.dart';
import 'package:anicel/src/ui/text/vertical_writing.dart';
import 'package:anicel/src/ui/text/vertical_writing_text.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/theme/text_on_ground.dart';
import 'package:anicel/src/ui/widgets/field_slider.dart';

/// 🗣️I-125 (유저 2026-10-23): 「브러시 사이즈가 숫자가 옆으로 누워있어서
/// 읽기 힘든게 큰 단점」 — Q1 answered 「B 縦中横(두세 자리를 한 칸에)」,
/// 「시안대로 px는 필요없어보임. %는 괜찮은데」.
void main() {
  Future<void> pumpStood(
    WidgetTester tester, {
    required double value,
    bool upright = true,
  }) => tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 20,
            height: 160,
            child: FieldSlider(
              label: 'Size',
              nameInside: false,
              value: value,
              min: 0,
              max: 100,
              axis: Axis.vertical,
              height: 20,
              upright: upright,
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    ),
  );

  Finder writing() => find.byType(VerticalWritingText);

  testWidgets('a stood bar that stands its number up writes it down the bar '
      'in a column — not the row turned — at the end a lying bar writes it', (
    tester,
  ) async {
    await pumpStood(tester, value: 10);

    final column = tester.widget<VerticalWritingText>(writing());
    expect(column.text, '10.0');
    expect(column.latinForm, VerticalLatinForm.upright);
    expect(column.tateChuYokoDigits, FieldSlider.uprightDigits);
    expect(column.mainAlignment, 1, reason: 'the far end: the bottom');
    expect(find.text('10.0'), findsNothing, reason: 'no lying row');
    expect(
      find.ancestor(of: writing(), matching: find.byType(RotatedBox)),
      findsNothing,
    );

    await pumpStood(tester, value: 10, upright: false);
    expect(writing(), findsNothing);
    expect(find.text('10.0'), findsOneWidget, reason: 'the x-sheet\'s way');
  });

  test('「두세 자리를 한 칸에」: 10.0 is 10 / . / 0, and 100% is 100 / %', () {
    List<String> cells(String number) => [
      for (final cell in verticalTextCells(
        number,
        tateChuYokoDigits: FieldSlider.uprightDigits,
        latinForm: VerticalLatinForm.upright,
      ))
        cell.text,
    ];
    expect(cells('10.0'), ['10', '.', '0']);
    expect(cells('100%'), ['100', '%']);
  });

  testWidgets('the column\'s ink follows the ground under it: the track\'s '
      'above the fill, the fill\'s on it — each stretch set clipped to its '
      'own', (tester) async {
    await pumpStood(tester, value: 50);

    final column = tester.widget<VerticalWritingText>(writing());
    expect(column.inks, [
      (end: 0.5, ink: textOnColor(AppColors.surface)),
      (end: 1.0, ink: textOnColor(AppColors.accent)),
    ]);
    final box = tester.getSize(writing());
    expect(
      tester.renderObject(
        find.descendant(of: writing(), matching: find.byType(CustomPaint)),
      ),
      paints
        ..clipRect(rect: Rect.fromLTRB(0, 0, box.width, box.height / 2))
        ..clipRect(
          rect: Rect.fromLTRB(0, box.height / 2, box.width, box.height),
        ),
    );
  });

  testWidgets('the brush pill stands both its numbers up — the size without '
      'its px, the opacity with its % — and the strip still lays them down', (
    tester,
  ) async {
    final brushTool = ValueNotifier(BrushToolState.defaults);
    addTearDown(brushTool.dispose);
    Future<void> pumpBars(BrushValuesLayout layout) => tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Center(
            child: BrushValueBars(
              brushTool: brushTool,
              widths: (size: 200, opacity: 200),
              layout: layout,
            ),
          ),
        ),
      ),
    );

    await pumpBars(BrushValuesLayout.pill);
    final words = [
      for (final column in tester.widgetList<VerticalWritingText>(writing()))
        column.text,
    ];
    expect(words, hasLength(2));
    expect(words.first, matches(RegExp(r'^\d+\.\d$')), reason: 'no px');
    expect(words.last, matches(RegExp(r'^\d+%$')));

    await pumpBars(BrushValuesLayout.strip);
    expect(writing(), findsNothing);
    expect(find.textContaining(' px'), findsOneWidget);
  });
}
