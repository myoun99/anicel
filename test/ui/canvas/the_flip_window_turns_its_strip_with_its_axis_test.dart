import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/canvas/flip_hud_controller.dart';
import 'package:anicel/src/ui/canvas/flip_hud_model.dart';
import 'package:anicel/src/ui/canvas/flip_hud_overlay.dart';

/// The flip window's strip is one strip turned with its axis: on the frame
/// axis it runs across, on the row axis down. Its rules stand across it at
/// each slot's edge, and its fade eats its two ends — never its sides.
void main() {
  // Rows with nothing on them and no drawings to hold, so the strip holds
  // only its rules and the washes of where you stand: no X, no body.
  final snapshot = FlipHudSnapshot(
    rows: [
      for (final name in ['A', 'B', 'C'])
        FlipHudRow(
          name: name,
          kind: LayerKind.animation,
          runs: [],
          holdsDrawings: false,
        ),
    ],
    rowIndex: 1,
    frameIndex: 5,
    frameCount: 12,
  );

  FlipHudPainter painterFor(FlipHudAxis axis) => FlipHudPainter(
    snapshot: snapshot,
    axis: axis,
    frameStep: true,
    colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
    baseTextStyle: const TextStyle(fontSize: 11),
  );

  test('the frame axis rules its slots across the strip, the row axis '
      'along it', () {
    for (final (axis, upright) in [
      (FlipHudAxis.frame, true),
      (FlipHudAxis.row, false),
    ]) {
      final canvas = TestRecordingCanvas();
      painterFor(axis).paint(canvas, FlipHudMetrics.sizeFor(axis));
      final rules = [
        for (final call in canvas.invocations)
          if (call.invocation.memberName == #drawLine)
            (
              call.invocation.positionalArguments[0] as Offset,
              call.invocation.positionalArguments[1] as Offset,
            ),
      ];
      expect(rules, isNotEmpty, reason: '$axis: premise: the strip is ruled');
      for (final (from, to) in rules) {
        expect(
          upright ? from.dx == to.dx : from.dy == to.dy,
          isTrue,
          reason: '$axis: a rule from $from to $to',
        );
      }
    }
  });

  testWidgets('the fade runs along the strip — across it, the middle stands '
      'whole from side to side', (tester) async {
    for (final axis in FlipHudAxis.values) {
      final size = FlipHudMetrics.sizeFor(axis);
      final recorder = ui.PictureRecorder();
      painterFor(axis).paint(Canvas(recorder), size);
      final picture = recorder.endRecording();
      final image = picture.toImageSync(
        size.width.ceil(),
        size.height.ceil(),
      );
      picture.dispose();
      final bytes = await tester.runAsync(
        () => image.toByteData(format: ui.ImageByteFormat.rawStraightRgba),
      );
      final width = image.width;
      image.dispose();
      int alphaAt(double x, double y) =>
          bytes!.getUint8((y.floor() * width + x.floor()) * 4 + 3);

      // The strip is what stands right of the rail; where you stand is its
      // middle, between two of its rules.
      final strip = Rect.fromLTRB(
        FlipHudMetrics.railWidth,
        0,
        size.width,
        size.height,
      );
      final (side, middle) = axis == FlipHudAxis.frame
          ? (
              Offset(strip.center.dx, strip.top + 0.5),
              strip.center,
            )
          : (
              Offset(strip.left + 0.5, strip.center.dy),
              strip.center,
            );
      expect(
        alphaAt(middle.dx, middle.dy),
        greaterThan(0),
        reason: '$axis: premise: the wash of where you stand is there',
      );
      expect(
        alphaAt(side.dx, side.dy),
        closeTo(alphaAt(middle.dx, middle.dy), 2),
        reason: '$axis: the strip\'s side is not one of its ends',
      );
    }
  });
}
