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
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/widgets/field_slider.dart';

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
}
