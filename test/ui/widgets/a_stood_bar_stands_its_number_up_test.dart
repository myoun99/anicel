import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/brush_value_group.dart';
import 'package:anicel/src/ui/text/vertical_writing.dart';
import 'package:anicel/src/ui/text/vertical_writing_text.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/theme/text_on_ground.dart';
import 'package:anicel/src/ui/widgets/field_slider.dart';

import '../../helpers/raster_parity.dart';

/// 🗣️I-125 (유저 2026-10-23): 「브러시 사이즈가 숫자가 옆으로 누워있어서
/// 읽기 힘든게 큰 단점」 — Q1 answered 「B 縦中横(두세 자리를 한 칸에)」,
/// 「시안대로 px는 필요없어보임. %는 괜찮은데」; then F-460: 「가로표기
/// 세로쓰기 … 숫자가 90도로 안기울었으면」, 「불투명도는 % 없앰」, and Q1
/// 「a 한 글자씩 한 칸」.
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

  test('「한 글자씩 한 칸」: 10.0 is 1 / 0 / . / 0 and 100 is 1 / 0 / 0, as '
      '2000.0 always was', () {
    List<String> cells(String number) => [
      for (final cell in verticalTextCells(
        number,
        tateChuYokoDigits: FieldSlider.uprightDigits,
        latinForm: VerticalLatinForm.upright,
      ))
        cell.text,
    ];
    expect(cells('10.0'), ['1', '0', '.', '0']);
    expect(cells('100'), ['1', '0', '0']);
    expect(cells('2000.0'), ['2', '0', '0', '0', '.', '0']);
  });

  testWidgets('the column keeps a bar\'s insets clear at its ends — it asks '
      'for them, and sets its first cell after one', (tester) async {
    const style = TextStyle(fontSize: 10);
    late Size bare;
    late Size inset;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 20,
            height: 100,
            child: Builder(
              builder: (context) {
                bare = const VerticalWritingText(
                  text: '1',
                  style: style,
                ).naturalSizeIn(context);
                inset = const VerticalWritingText(
                  text: '1',
                  style: style,
                  endInset: 8,
                ).naturalSizeIn(context);
                return const VerticalWritingText(
                  text: '1',
                  style: style,
                  endInset: 8,
                  mainAlignment: 0,
                );
              },
            ),
          ),
        ),
      ),
    );

    expect(inset.height, bare.height + 16);
    // The one cell's centre: an inset down, then half a cell of 10 × 1.15.
    expect(
      tester.renderObject(writing()),
      paints..translate(x: 10, y: 8 + 10 * verticalWritingLineHeight / 2),
    );
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
      tester.renderObject(writing()),
      paints
        ..clipRect(rect: Rect.fromLTRB(0, 0, box.width, box.height / 2))
        ..clipRect(
          rect: Rect.fromLTRB(0, box.height / 2, box.width, box.height),
        ),
    );
  });

  testWidgets('each stretch is set in its own ink — the column read off the '
      'screen: the track\'s colour above the fill\'s edge, the fill\'s on it, '
      'and the style\'s own nowhere', (tester) async {
    const above = Color(0xFFFF0000);
    const on = Color(0xFF0000FF);
    final bytes = await surfaceBytes(
      tester,
      const VerticalWritingText(
        text: '0000000000',
        style: TextStyle(fontSize: 10, color: Color(0xFF00FF00)),
        inks: [(end: 0.5, ink: above), (end: 1.0, ink: on)],
      ),
      left: 20,
      width: 20,
      height: 100,
      settle: () async {},
    );
    final ratio = tester.view.devicePixelRatio;
    final stride = (parityCaptureWidth * ratio).round();
    Set<String> inksBetween(double top, double bottom) => {
      for (var y = (top * ratio).ceil(); y < (bottom * ratio).floor(); y++)
        for (var x = (20 * ratio).ceil(); x < (40 * ratio).floor(); x++)
          if (bytes.getUint8((y * stride + x) * 4 + 3) == 255)
            switch ((
              bytes.getUint8((y * stride + x) * 4),
              bytes.getUint8((y * stride + x) * 4 + 1),
              bytes.getUint8((y * stride + x) * 4 + 2),
            )) {
              (255, 0, 0) => 'above',
              (0, 0, 255) => 'on',
              (0, 255, 0) => 'the style\'s',
              _ => 'blended',
            },
    }..remove('blended');
    // The box stands at y 20..120 in the capture; its middle is the edge.
    expect(inksBetween(20, 69), {'above'});
    expect(inksBetween(71, 120), {'on'});
  });

  testWidgets('the brush pill stands both its numbers up — the size without '
      'its px, the opacity without its % — and the strip still lays them '
      'down, units and all', (
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
    expect(words.last, matches(RegExp(r'^\d+$')), reason: 'no %');

    await pumpBars(BrushValuesLayout.strip);
    expect(writing(), findsNothing);
    expect(find.textContaining(' px'), findsOneWidget);
    expect(find.textContaining('%'), findsOneWidget);
  });
}
