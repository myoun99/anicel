import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/theme/text_on_ground.dart';
import 'package:anicel/src/ui/widgets/field_slider.dart';
import 'package:anicel/src/ui/widgets/ground_ink_writing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 🗣️F-480 (유저 2026-10-27): the memory allowance's slider and the device
/// bar under it are one bar — 「두번째 슬라이더랑 내용적으로 같아지니 내용
/// 서로 합쳐서 통합」, on a fixed scale (「고정값으로」). [FieldSlider.ceiling]
/// is that bar: levels filled under the value, the value an outline.
void main() {
  const scale = 100.0;
  const floor = 10.0;
  const width = 200.0;

  Widget host({
    double value = 50,
    List<FieldSliderLevel> levels = const [],
    ValueChanged<double>? onChanged,
    ValueChanged<double>? onChangeEnd,
  }) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: width,
          child: FieldSlider.ceiling(
            value: value,
            max: scale,
            floor: floor,
            levels: levels,
            color: AppColors.textDim,
            unit: 'MB',
            onChanged: onChanged ?? (_) {},
            onChangeEnd: onChangeEnd,
          ),
        ),
      ),
    ),
  );

  final track = find.descendant(
    of: find.byType(FieldSlider),
    matching: find.byType(FieldSliderTrack),
  );

  testWidgets('the levels fill from the left, a later one over an earlier, '
      'and the value is an outline over them', (tester) async {
    await tester.pumpWidget(
      host(
        levels: [
          (value: 30, color: AppColors.hairline),
          (value: 10, color: AppColors.accent),
        ],
      ),
    );

    expect(tester.getSize(track).width, width, reason: 'premise: no hands');
    expect(
      track,
      paints
        ..rect(
          rect: const Rect.fromLTWH(0, 0, width * 0.3, 24),
          color: AppColors.hairline,
        )
        ..rect(
          rect: const Rect.fromLTWH(0, 0, width * 0.1, 24),
          color: AppColors.accent,
        )
        ..rect(
          rect: const Rect.fromLTWH(0, 0, width * 0.5, 24).deflate(0.75),
          color: AppColors.textDim,
          style: PaintingStyle.stroke,
        ),
    );
  });

  testWidgets('a press at the middle is half the scale — a fixed scale, not '
      'a curve', (tester) async {
    double? kept;
    await tester.pumpWidget(host(onChangeEnd: (value) => kept = value));

    await tester.tapAt(tester.getCenter(track));
    await tester.pump();

    expect(kept, closeTo(scale / 2, 1e-9));
  });

  testWidgets('a drag past the floor stops at it — the bar never shows a '
      'value the setting would not take', (tester) async {
    final seen = <double>[];
    double? kept;
    await tester.pumpWidget(
      host(onChanged: seen.add, onChangeEnd: (value) => kept = value),
    );

    final hand = await tester.startGesture(tester.getCenter(track));
    await tester.pump();
    await hand.moveTo(tester.getTopLeft(track) + const Offset(1, 12));
    await tester.pump();

    expect(seen.last, floor);
    expect(
      find.descendant(of: track, matching: find.text('10.0MB')),
      findsOneWidget,
      reason: 'the bar shows where the hand is held, not where it went',
    );
    await hand.up();
    await tester.pump();
    expect(kept, floor);
  });

  testWidgets('the writing takes the ink of the level on top under it — the '
      'outline is an edge, not a ground', (tester) async {
    await tester.pumpWidget(
      host(
        levels: [
          (value: 30, color: AppColors.hairline),
          (value: 10, color: AppColors.accent),
        ],
      ),
    );

    final writing = tester.widget<GroundInkWriting>(
      find.descendant(of: track, matching: find.byType(GroundInkWriting)),
    );
    expect(writing.runs, [
      (end: 0.1, ink: textOnColor(AppColors.accent)),
      (end: 0.3, ink: textOnColor(AppColors.hairline)),
      (end: 1.0, ink: textOnColor(AppColors.surface)),
    ]);
  });
}
