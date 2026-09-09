import 'package:anicel/src/models/brush_input_source.dart';
import 'package:anicel/src/models/brush_pressure_curve.dart';
import 'package:anicel/src/ui/widgets/pressure_curve_popup.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The settings panel reserves [PressureCurveButton.slotWidth] on EVERY
/// slider row, so eighteen sliders without a curve button stay the same
/// length as the two with one. That reservation is a number written in one
/// place and a widget laid out somewhere else — this is the mechanism that
/// stops them drifting apart.
void main() {
  testWidgets('the button is exactly as wide as the slot it declares', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: PressureCurveButton(
              keyValue: 'slot-probe',
              title: 'Size',
              curves: const {},
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(
      tester.getSize(find.byKey(const ValueKey<String>('slot-probe'))).width,
      PressureCurveButton.slotWidth,
    );
  });

  testWidgets('a curve on the button does not change its width', (
    tester,
  ) async {
    // The active state swaps the border colour, and a colour must not move
    // the row: the eighteen empty slots are sized off this one number.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: PressureCurveButton(
              keyValue: 'slot-probe',
              title: 'Size',
              curves: {
                BrushInputSource.pressure: BrushPressureCurve.identity(),
              },
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(
      tester.getSize(find.byKey(const ValueKey<String>('slot-probe'))).width,
      PressureCurveButton.slotWidth,
    );
  });
}
