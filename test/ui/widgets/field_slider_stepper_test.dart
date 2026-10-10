// THERE ARE TWO KINDS OF VALUE BAR, AND THE VARIANT DECIDES WHICH.
//
// 유저 2026-09-09: 「슬라이더는 2개로 두자. 스텝퍼 적용 미적용 규칙. **초소형
// 변형은 기본적으로 빼도록**」 — after measuring that putting the +/− pair on
// literally every bar shortened twelve tests' worth of tracks, the timeline's
// inline slots included.
//
// ⛔The rule lives in the widget, not at the call sites: a per-site flag is
// how two kinds stop being two kinds.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/theme/app_theme.dart' show AppColors;
import 'package:anicel/src/ui/widgets/field_slider.dart';
import 'package:anicel/src/ui/widgets/inline_numeric_field.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget slider) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(child: SizedBox(width: 200, child: slider)),
      ),
    ),
  );

  final up = find.byKey(const ValueKey<String>('field-slider-step-up'));
  final down = find.byKey(const ValueKey<String>('field-slider-step-down'));
  // 🗣️tool-settings-panel-tidy (유저 2026-10-10): 막대에도 연필을
  // 「달도록」 — the pencil is the pair's companion, by the same rule.
  final pencil = find.byKey(const ValueKey<String>('field-slider-type'));

  testWidgets('a LABELLED bar carries the pair', (tester) async {
    await pump(
      tester,
      FieldSlider(
        value: 0.5,
        min: 0,
        max: 1,
        label: 'Size',
        unit: '%',
        onChanged: (_) {},
      ),
    );
    expect(up, findsOneWidget);
    expect(down, findsOneWidget);
    expect(pencil, findsOneWidget);
  });

  testWidgets('the MICRO variant does not — that is the whole rule', (
    tester,
  ) async {
    await pump(
      tester,
      FieldSlider(
        value: 0.5,
        min: 0,
        max: 1,
        unit: '%',
        onChanged: (_) {},
      ),
    );
    expect(up, findsNothing);
    expect(down, findsNothing);
    expect(pencil, findsNothing);
  });

  testWidgets('nor does a STOOD-UP bar, whatever it is named — its row has '
      'no room across for the pair', (tester) async {
    // The rule's other half, in the bar's own words: 「A VERTICAL bar is out
    // for a plainer reason: it is the timeline's turned axis, whose row has
    // no horizontal room at all」. ⛔Nothing pinned it until 2026-10-08, when
    // the rule gained a second reader (the bar's narrowest) and a mutant
    // that dropped this half lived.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 28,
              height: 200,
              child: FieldSlider(
                value: 0.5,
                min: 0,
                max: 1,
                label: 'Size',
                unit: '%',
                axis: Axis.vertical,
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('Size'), findsOneWidget, reason: '⛔LIVENESS');
    expect(up, findsNothing);
    expect(down, findsNothing);
    expect(pencil, findsNothing);
  });

  testWidgets('a DISABLED bar keeps the slot — the row must not resize when '
      'the control comes alive', (tester) async {
    Future<double> widthWith(bool enabled) async {
      await pump(
        tester,
        FieldSlider(
          value: 0.5,
          min: 0,
          max: 1,
          label: 'Size',
          unit: '%',
          onChanged: enabled ? (_) {} : null,
        ),
      );
      return tester.getSize(find.byType(FieldSlider)).width;
    }

    expect(up, findsNothing, reason: 'nothing pumped yet');
    expect(await widthWith(false), await widthWith(true));
    expect(up, findsOneWidget);
  });

  testWidgets('🚨ONE NOTCH IS ONE WHEEL NOTCH (유저 확정)', (tester) async {
    // The buttons call the slider's own step, so there is no second
    // definition of "a step" to drift from the wheel's.
    var value = 0.5;
    await pump(
      tester,
      StatefulBuilder(
        builder: (context, setState) => FieldSlider(
          value: value,
          min: 0,
          max: 1,
          divisions: 100,
          label: 'Size',
          unit: '%',
          displayScale: 100,
          onChanged: (next) => setState(() => value = next),
        ),
      ),
    );
    await tester.tap(up);
    await tester.pump();
    expect(value, closeTo(0.51, 1e-9), reason: 'one division up');
    await tester.tap(down);
    await tester.pump();
    await tester.tap(down);
    await tester.pump();
    expect(value, closeTo(0.49, 1e-9), reason: 'and back down, twice');
  });

  /// A bar a host keeps, telling each change and each end.
  Future<({List<double> changes, List<double> ends})> pumpKept(
    WidgetTester tester,
  ) async {
    final changes = <double>[];
    final ends = <double>[];
    var value = 0.5;
    await pump(
      tester,
      StatefulBuilder(
        builder: (context, setState) => FieldSlider(
          value: value,
          min: 0,
          max: 1,
          divisions: 100,
          label: 'Size',
          unit: '%',
          displayScale: 100,
          onChanged: (next) => setState(() {
            value = next;
            changes.add(next);
          }),
          onChangeEnd: ends.add,
        ),
      ),
    );
    return (changes: changes, ends: ends);
  }

  final field = find.byKey(const ValueKey<String>('field-slider-type-input'));

  testWidgets('its PENCIL types a number: the number alone, selected, the '
      'bar all field — no name, no unit', (tester) async {
    await pumpKept(tester);
    expect(field, findsNothing);
    await tester.tap(pencil);
    await tester.pump();
    expect(field, findsOneWidget);
    final typed = tester.widget<TextField>(
      find.descendant(
        of: find.byType(InlineNumericField),
        matching: find.byType(TextField),
      ),
    );
    expect(typed.controller!.text, '50');
    expect(
      typed.controller!.selection,
      const TextSelection(baseOffset: 0, extentOffset: 2),
    );
    // 🗣️유저 2026-10-11: 「X같은 글자 없애고 전면텍스트박스로 … %나 도같은
    // 단위도 텍스트편집창에서 없도록」.
    expect(find.text('%'), findsNothing);
    expect(find.text('Size'), findsNothing);
    // 「다른박스 마찬가지 통일」: typed, the bar is a number box typed — its
    // field runs the whole frame, and the frame wears the accent.
    final framed = find.ancestor(
      of: find.byType(EditableText),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is DecoratedBox &&
            widget.decoration is ShapeDecoration &&
            (widget.decoration as ShapeDecoration).shape is OutlinedBorder,
      ),
    );
    expect(framed, findsOneWidget);
    final frame = tester.getRect(framed);
    final editable = tester.getRect(find.byType(EditableText));
    expect(editable.left, closeTo(frame.left + FieldSlider.inset, 0.01));
    expect(editable.right, closeTo(frame.right - FieldSlider.inset, 0.01));
    final decoration =
        tester.widget<DecoratedBox>(framed).decoration as ShapeDecoration;
    expect((decoration.shape as OutlinedBorder).side.color, AppColors.accent);
  });

  testWidgets('a typed number is held to the range and handed over as ONE '
      'complete edit, as a step is', (tester) async {
    final seen = await pumpKept(tester);
    await tester.tap(pencil);
    await tester.pump();
    await tester.enterText(field, '150');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(seen.changes, [1.0], reason: 'held to the top of the range');
    expect(seen.ends, [1.0]);
    expect(field, findsNothing, reason: 'the bar stands again');

    await tester.tap(pencil);
    await tester.pump();
    await tester.enterText(field, '25');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(seen.changes.last, closeTo(0.25, 1e-9));
    expect(seen.ends.length, 2);
  });

  testWidgets('an EXPONENTIAL bar typed below its range holds to its bottom '
      '— a negative is not its top', (tester) async {
    // A log scale has no place for a number under zero: unheld, it read as
    // the far end of the bar.
    final changes = <double>[];
    await pump(
      tester,
      FieldSlider(
        value: 1,
        min: 0.25,
        max: 4,
        scale: FieldSliderScale.exponential,
        label: 'Gamma',
        onChanged: changes.add,
      ),
    );
    await tester.tap(pencil);
    await tester.pump();
    await tester.enterText(field, '-2');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(changes, [0.25]);
  });

  testWidgets('Escape abandons the typing and changes nothing', (
    tester,
  ) async {
    final seen = await pumpKept(tester);
    await tester.tap(pencil);
    await tester.pump();
    await tester.enterText(field, '80');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(field, findsNothing);
    expect(seen.changes, isEmpty);
    expect(seen.ends, isEmpty);
  });
}
