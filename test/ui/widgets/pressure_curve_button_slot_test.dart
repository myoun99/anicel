import 'package:anicel/src/models/brush_input_source.dart';
import 'package:anicel/src/models/brush_pressure_curve.dart';
import 'package:anicel/src/models/brush_tip_rotation_mode.dart';
import 'package:anicel/src/ui/widgets/pressure_curve_popup.dart';
import 'package:anicel/src/ui/widgets/setting_source_button.dart';
import 'package:anicel/src/ui/widgets/tip_direction_popup.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The settings panel reserves [SettingSourceButton.slotWidth] on EVERY
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
              target: BrushPressureTarget.size,
              curves: const {},
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(
      tester.getSize(find.byKey(const ValueKey<String>('slot-probe'))).width,
      SettingSourceButton.slotWidth,
    );
  });

  testWidgets('the angle\'s direction button stands in the same slot, lit or '
      'not (F-176-Q6)', (tester) async {
    for (final base in [
      BrushTipRotationMode.fixed,
      BrushTipRotationMode.direction,
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: TipDirectionButton(
                direction: (base: base, random: 0),
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      expect(
        tester
            .getSize(
              find.byKey(const ValueKey<String>(TipDirectionButton.keyValue)),
            )
            .width,
        SettingSourceButton.slotWidth,
        reason: base.name,
      );
    }
  });

  testWidgets('the button is square, as wide as the brush pill\'s bars are '
      'thick (유저 2026-10-18: 「압력버튼 특히 그냥 정사각형이어도 '
      '문제없겟는데」)', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: PressureCurveButton(
              keyValue: 'slot-probe',
              target: BrushPressureTarget.size,
              curves: const {},
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(
      tester.getSize(find.byKey(const ValueKey<String>('slot-probe'))),
      const Size(20, 20),
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
              target: BrushPressureTarget.size,
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
      SettingSourceButton.slotWidth,
    );
  });
}
