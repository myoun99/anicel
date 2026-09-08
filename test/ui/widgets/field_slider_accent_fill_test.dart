import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/theme/text_on_ground.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_style.dart';
import 'package:anicel/src/ui/widgets/field_slider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The filled bar is the accent ITSELF (유저 2026-09-08), and the writing on
/// it takes its ink from the one ground law rather than from a second sum.
void main() {
  Widget host(Widget child) => MaterialApp(
    home: Scaffold(
      body: Center(child: SizedBox(width: 100, child: child)),
    ),
  );

  testWidgets('the fill is the accent at full strength', (tester) async {
    await tester.pumpWidget(
      host(
        FieldSlider(
          value: 0.5,
          min: 0,
          max: 1,
          label: 'Size',
          valueText: '50%',
          onChanged: (_) {},
        ),
      ),
    );

    // ⛔The 26%-alpha wash this replaced would fail on colour alone: the
    // assertion is the OPAQUE accent over the left half of a 100px track.
    expect(
      find.byType(FieldSlider),
      paints..rect(
        rect: const Rect.fromLTWH(0, 0, 50, 24),
        color: AppColors.accent,
      ),
    );
  });

  testWidgets('nothing marks the fill edge — the fill is the mark', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        FieldSlider(
          value: 0.5,
          min: 0,
          max: 1,
          label: 'Size',
          valueText: '50%',
          onChanged: (_) {},
        ),
      ),
    );

    // The 2px accent edge sat at x=49 and was the same colour as the fill,
    // so only its NARROWNESS distinguishes it. Painting it again would put
    // a second accent rect in the stream.
    expect(
      find.byType(FieldSlider),
      isNot(
        paints..rect(
          rect: const Rect.fromLTWH(49, 0, 2, 24),
          color: AppColors.accent,
        ),
      ),
    );
  });

  test('the ground law did not fork when it moved out of the timeline', () {
    // `timeline_cell_style.dart` keeps the timeline's thirty-one call sites
    // working by delegating. If someone re-implements either side, these
    // disagree.
    for (final ground in <Color>[
      AppColors.accent,
      AppColors.surface,
      AppColors.backdrop,
      const Color(0xFFFFFFFF),
      const Color(0xFF000000),
    ]) {
      expect(timelineTextOnColor(ground), textOnColor(ground));
    }
    expect(
      timelineTextGroundLuminanceCrossover,
      textGroundLuminanceCrossover,
    );
  });

  test('the accent takes dark writing and the track takes light', () {
    // The reason the slider needed the law at all: its two grounds land on
    // opposite sides of the crossover.
    expect(textOnColor(AppColors.accent), textOnLightGroundColor);
    expect(textOnColor(AppColors.surface), textOnDarkGroundColor);
  });
}
