import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/text/readout_text.dart';
import 'package:anicel/src/ui/widgets/drag_value_label.dart';
import 'package:anicel/src/ui/widgets/field_slider.dart';

import '../../helpers/number_pad_keyboard.dart';

/// 🗣️유저 2026-10-10 (tool-settings-panel-tidy): 「%나 각도같은 단위값은
/// 텍스트 편집시 안보이도록. 즉 100.00%를 눌러서 편집하려할때 %도 같이
/// 편집되버리는 텍스트면 너무 불편하니까. 편집시 100.00 만 뜨는느낌. 다른 모든
/// 텍스트 직접편집의 기준」 — and 「해당 상자, x상자같은거 드래그하면 바뀌는거는
/// 살아있는거지? 그건 좋아서」.
void main() {
  Widget host(Widget child) => MaterialApp(
    home: Scaffold(
      body: Center(child: SizedBox(width: 160, child: child)),
    ),
  );

  String typed(WidgetTester tester, String key) =>
      tester.widget<TextField>(find.byKey(ValueKey<String>(key))).controller!
          .text;

  /// The number the open number pad shows at its top (I-134).
  String? padShows(WidgetTester tester) =>
      tester.widget<Text>(theNumberPadsNumber).data;

  group('the readout law: what is typed is the number', () {
    test('a unit, a page count, a pair', () {
      expect(readoutParts('100.00%'), [(number: '100.00', unit: '%')]);
      expect(readoutParts('-12.50°'), [(number: '-12.50', unit: '°')]);
      expect(readoutParts('3 / 7'), [(number: '3', unit: ' / 7')]);
      expect(readoutParts('1218.00, 540.00'), [
        (number: '1218.00', unit: ''),
        (number: '540.00', unit: ''),
      ]);
      expect(readoutParts('off'), [(number: 'off', unit: '')]);
    });

    testWidgets('the bare readout opens on its number — ↩️`3 / 7` opened as '
        '`37`', (tester) async {
      for (final (readout, number) in const [
        ('100.00%', '100.00'),
        ('-15.00°', '-15.00'),
        ('3 / 7', '3'),
        ('0012', '0012'),
      ]) {
        await tester.pumpWidget(
          host(
            DragValueLabel(
              keyValue: 'v',
              text: readout,
              onDragDelta: (_) {},
              onEditSubmit: (_) {},
            ),
          ),
        );
        await tester.tap(find.byKey(const ValueKey<String>('v-edit')));
        await tester.pump();
        expect(padShows(tester), number, reason: readout);
        await openThePadsKeyboard(tester);
        expect(typed(tester, 'v-input'), number, reason: readout);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });
  });

  group('THE NUMBER BOX', () {
    Future<List<String>> pumpBox(
      WidgetTester tester, {
      String text = '100.00%',
      List<double>? dragged,
      bool enabled = true,
    }) async {
      final submitted = <String>[];
      await tester.pumpWidget(
        host(
          DragValueLabel.box(
            keyValue: 'box',
            name: 'X',
            text: text,
            enabled: enabled,
            onDragDelta: (units) => dragged?.add(units),
            onEditSubmit: submitted.add,
          ),
        ),
      );
      return submitted;
    }

    testWidgets('wears the settings bar\'s frame — one face for both', (
      tester,
    ) async {
      await pumpBox(tester);
      final frames = tester
          .widgetList<DecoratedBox>(
            find.ancestor(
              of: find.text('100.00%'),
              matching: find.byType(DecoratedBox),
            ),
          )
          .map((box) => box.decoration);
      expect(
        frames,
        contains(
          FieldSlider.frameOf(FieldSlider.defaultHeight, enabled: true),
        ),
      );
      expect(
        tester.getSize(find.byKey(const ValueKey<String>('box'))).height,
        FieldSlider.defaultHeight,
        reason: 'a bar\'s height, so it stands in a row of bars',
      );
      expect(find.text('X'), findsOneWidget, reason: 'its name, inside');
    });

    testWidgets('typed in — its pencil opens the number pad — it holds the '
        'number and nothing else: no unit, no name', (tester) async {
      final submitted = await pumpBox(tester);
      await tester.tap(find.byKey(const ValueKey<String>('box-edit')));
      await tester.pump();

      // 🗣️유저 2026-10-11: 「뒤에 붙은 %나 도같은 단위도 텍스트편집창에서
      // 없도록. 진짜 박스 전면 텍스트로 하고싶은거야」 — 「편집시 100.00 만
      // 뜨는느낌」, as 10-10 put it. ↩️It stood beside the field, as chrome;
      // the field is the pad's top now (I-134), and the box stands as shown.
      expect(padShows(tester), '100.00');
      await openThePadsKeyboard(tester);
      expect(typed(tester, 'box-input'), '100.00');

      await tester.enterText(
        find.byKey(const ValueKey<String>('box-input')),
        '150',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(submitted, ['150']);
    });

    testWidgets('a drag still changes it — the box is the readout it was', (
      tester,
    ) async {
      final dragged = <double>[];
      await pumpBox(tester, dragged: dragged);
      await tester.drag(
        find.byKey(const ValueKey<String>('box')),
        const Offset(40, 0),
      );
      await tester.pump();
      expect(
        dragged.fold<double>(0, (sum, units) => sum + units),
        greaterThan(0),
      );
      expect(
        find.byKey(const ValueKey<String>('box-input')),
        findsNothing,
        reason: 'a drag is not a press to type',
      );
    });

    testWidgets('disabled, it neither drags nor types', (tester) async {
      final dragged = <double>[];
      await pumpBox(tester, dragged: dragged, enabled: false);
      await tester.drag(
        find.byKey(const ValueKey<String>('box')),
        const Offset(40, 0),
      );
      await tester.tap(find.byKey(const ValueKey<String>('box-edit')));
      await tester.pump();
      expect(dragged, isEmpty);
      expect(find.byKey(const ValueKey<String>('box-input')), findsNothing);
    });
  });
}
