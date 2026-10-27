import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/widgets/field_slider.dart';
import 'package:anicel/src/ui/widgets/rail_glyph_button.dart';

import '../../helpers/number_pad_keyboard.dart';

/// 🗣️I-135 (유저 2026-10-27): the brush pill's bars — 「슬라이더 막대엔 텍스트
/// 없애고, 연필버튼도 여기선 대체되니 없애고 … 이 위젯은 버튼이라
/// 클릭가능. 클릭하면 연필버튼이랑 똑같은 동작으로 텍스트 직접 편집」, the
/// number 「그냥 해당하는 막대 슬라이더 위에」. The link between a bar and its
/// readout ([FieldSliderReadout]) as any host holds it; the pill's own pins
/// are in `the_brush_pill_writes_its_numbers_above_its_bars_test`.
void main() {
  FieldSlider barWith(FieldSliderReadout readout) => FieldSlider(
    key: const ValueKey<String>('bar'),
    label: 'Size',
    nameInside: false,
    value: 10,
    min: 1,
    max: 100,
    axis: Axis.vertical,
    height: 20,
    readout: readout,
    onChanged: (_) {},
  );

  /// A readout that presses [readoutHolds] over a bar that holds
  /// [barHolds] — no bar where it is null.
  Future<void> pumpReadoutAndBar(
    WidgetTester tester, {
    required FieldSliderReadout? barHolds,
    required FieldSliderReadout readoutHolds,
  }) => tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FieldSliderValueReadout(
                keyValue: 'readout',
                bar: barWith(readoutHolds),
                width: 40,
              ),
              SizedBox(
                width: 20,
                height: 160,
                child: barHolds == null ? null : barWith(barHolds),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  // A press types as the pencil does: it opens the bar's number pad (I-134).
  final typing = theNumberPadsNumber;
  final readout = find.byKey(const ValueKey<String>('readout'));

  Future<BuildContext> pumpContext(WidgetTester tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Builder(
          builder: (built) {
            context = built;
            return const SizedBox();
          },
        ),
      ),
    );
    return context;
  }

  testWidgets('a bar handed another readout answers that one\'s press', (
    tester,
  ) async {
    final first = FieldSliderReadout();
    final second = FieldSliderReadout();
    await pumpReadoutAndBar(tester, barHolds: first, readoutHolds: first);
    await tester.tap(readout);
    await tester.pumpAndSettle();
    expect(typing, findsOneWidget, reason: '⛔premise: its first one types');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(typing, findsNothing, reason: '⛔premise: the pad closed');

    await pumpReadoutAndBar(tester, barHolds: second, readoutHolds: second);
    await tester.tap(readout);
    await tester.pumpAndSettle();
    expect(typing, findsOneWidget);
  });

  testWidgets('a readout takes the keyboard\'s press as its pencil did: '
      'Enter on it types into its bar', (tester) async {
    final link = FieldSliderReadout();
    await pumpReadoutAndBar(tester, barHolds: link, readoutHolds: link);
    final plate = find.descendant(
      of: readout,
      matching: find.byType(RailPlateButton),
    );
    Focus.of(tester.element(plate)).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(typing, findsOneWidget);
  });

  testWidgets('a readout its bar has left is dead: its press — even the '
      'keyboard\'s, which reaches a readout no bar holds — types into '
      'nothing, and nothing breaks', (tester) async {
    final link = FieldSliderReadout();
    await pumpReadoutAndBar(tester, barHolds: link, readoutHolds: link);
    await pumpReadoutAndBar(tester, barHolds: null, readoutHolds: link);
    expect(find.byKey(const ValueKey<String>('bar')), findsNothing);

    Focus.of(tester.element(find.byType(RailPlateButton))).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(typing, findsNothing);
  });

  testWidgets('a readout is as wide as the widest word its bar can say, '
      'whatever the bar says now — 「그냥 고정크기로하자」', (tester) async {
    final context = await pumpContext(tester);
    double widthAt(double value) => FieldSliderValueReadout.widthIn(context, [
      FieldSlider(
        label: 'Size',
        nameInside: false,
        value: value,
        min: 1,
        max: 100,
        axis: Axis.vertical,
        height: 20,
        readout: FieldSliderReadout(),
        onChanged: (_) {},
      ),
    ]);

    final widest = widthAt(100);
    expect(widthAt(10), widest, reason: '「10.0」 says less than 「100.0」');
    expect(widthAt(1), widest);
  });

  testWidgets('a readout bar asks no room of its track — its number is in '
      'its readout — and the run its number would stand in is the column '
      'an upright bar measures', (tester) async {
    final context = await pumpContext(tester);
    final read = barWith(FieldSliderReadout());
    expect(read.narrowestIn(context), FieldSlider.readoutHandsReach);

    final upright = FieldSlider(
      label: 'Size',
      nameInside: false,
      value: 10,
      min: 1,
      max: 100,
      axis: Axis.vertical,
      height: 20,
      upright: true,
      onChanged: (_) {},
    );
    expect(
      read.standingRunIn(context),
      upright.narrowestIn(context) - FieldSlider.handsReach,
    );
  });
}
