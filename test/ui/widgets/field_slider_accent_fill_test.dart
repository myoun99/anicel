import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/theme/text_on_ground.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_style.dart';
import 'package:anicel/src/ui/widgets/field_slider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The filled bar is the accent ITSELF (유저 2026-09-08).
///
/// ⚠️The writing on it no longer asks the ground law anything: 유저 2026-09-10
/// 「흰색 고정으로 하고」 settled that, and the white ink is pinned in
/// `field_slider_test.dart`. What remains here is the FILL, plus the law's own
/// anti-fork check — the timeline is its reader now.
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
          unit: '%',
          onChanged: (_) {},
        ),
      ),
    );
    // ⛔The 26%-alpha wash this replaced would fail on colour alone: the
    // assertion is the OPAQUE accent over the left half of the TRACK.
    //
    // ⚠️The track, not the box: this bar is LABELLED, so it carries the +/−
    // stepper and half the widget is no longer half the bar.
    final track = find.descendant(
      of: find.byType(FieldSlider),
      matching: find.byType(FieldSliderTrack),
    );
    expect(
      track,
      paints..rect(
        rect: Rect.fromLTWH(0, 0, tester.getSize(track).width / 2, 24),
        color: AppColors.accent,
      ),
    );
  });

  // R4 #6: the legend's master-opacity bar reads gray at rest and lights
  // while adjusting — a resting state, which F-474's own colour is not.
  testWidgets('a resting colour gives way to the accent while dragged', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        FieldSlider(
          value: 0.5,
          min: 0,
          max: 1,
          label: 'Size',
          unit: '%',
          restingAccent: AppColors.textDim,
          onChanged: (_) {},
        ),
      ),
    );
    final track = find.descendant(
      of: find.byType(FieldSlider),
      matching: find.byType(FieldSliderTrack),
    );
    expect(track, paints..rect(color: AppColors.textDim));

    final hand = await tester.startGesture(tester.getCenter(track));
    await hand.moveBy(const Offset(10, 0));
    await tester.pump();
    await hand.moveBy(const Offset(10, 0));
    await tester.pump();
    expect(track, paints..rect(color: AppColors.accent), reason: 'dragged');
    await hand.up();
    await tester.pumpAndSettle();
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
          unit: '%',
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

}
