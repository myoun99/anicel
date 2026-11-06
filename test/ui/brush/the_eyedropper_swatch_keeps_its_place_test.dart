import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/brush/eyedropper_swatch_painter.dart';

/// ⛔NO UI THAT POPS INTO EXISTENCE. The shown picture has no paper under it
/// (I-163-Q6), so a blank spot picks nothing — and the swatch keeps its
/// place there, its ring empty, rather than vanishing over every blank
/// stretch and coming back over ink.
void main() {
  void Function(Canvas) swatch({Offset? at, int? color}) {
    final painter = EyedropperSwatchPainter(
      position: ValueNotifier(at),
      sample: (_) => color,
    );
    return (canvas) => painter.paint(canvas, EyedropperSwatchPainter.extent);
  }

  test('over ink it shows the ink in its ring', () {
    expect(
      swatch(at: Offset.zero, color: 0xFF123456),
      paints
        ..circle(hasMaskFilter: true)
        ..circle(color: const Color(0xFF123456), style: PaintingStyle.fill)
        ..circle(color: Colors.white, style: PaintingStyle.stroke),
    );
  });

  test('over nothing to pick it keeps its ring, empty', () {
    expect(
      swatch(at: Offset.zero),
      paints
        ..circle(hasMaskFilter: true, style: PaintingStyle.stroke)
        ..circle(color: Colors.white, style: PaintingStyle.stroke),
    );
    expect(swatch(at: Offset.zero), paintsExactlyCountTimes(#drawCircle, 2));
  });

  test('with no aim it paints nothing', () {
    expect(swatch(), paintsNothing);
  });
}
