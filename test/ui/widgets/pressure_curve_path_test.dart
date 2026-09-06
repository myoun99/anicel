import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_pressure_curve.dart';
import 'package:anicel/src/ui/widgets/pressure_curve_popup.dart';

/// The ONE sampling kernel behind the button's mini graph and the editor's
/// big graph (the audit's clone scan, 2026-09-06): the curve is walked in
/// [steps] equal pressure steps, x runs left→right and value 1 sits at the
/// TOP of the box. Both painters used to spell the loop out.
void main() {
  const size = Size(100, 50);

  Offset positionAt(Path path, double fraction) {
    final metric = path.computeMetrics().single;
    return metric.getTangentForOffset(metric.length * fraction)!.position;
  }

  test('the identity curve runs from the bottom-left to the top-right', () {
    final path = pressureCurvePath(
      BrushPressureCurve.identity(),
      size,
      steps: 4,
    );
    expect(positionAt(path, 0), const Offset(0, 50));
    final end = positionAt(path, 1);
    expect(end.dx, closeTo(100, 1e-6));
    expect(end.dy, closeTo(0, 1e-6));
    expect(
      path.computeMetrics().single.length,
      closeTo(math.sqrt(100 * 100 + 50 * 50), 1e-6),
    );
  });

  test('a flat curve at 1.0 is a line along the top edge', () {
    final path = pressureCurvePath(
      BrushPressureCurve(const [BrushCurvePoint(0, 1), BrushCurvePoint(1, 1)]),
      size,
      steps: 12,
    );
    expect(path.getBounds(), const Rect.fromLTWH(0, 0, 100, 0));
  });

  test('the step count is the sampling density, so a kink needs enough '
      'steps to show', () {
    final tent = BrushPressureCurve(const [
      BrushCurvePoint(0, 0),
      BrushCurvePoint(0.5, 1),
      BrushCurvePoint(1, 0),
    ]);
    final two = pressureCurvePath(tent, size, steps: 2);
    expect(
      two.computeMetrics().single.length,
      closeTo(2 * math.sqrt(50 * 50 + 50 * 50), 1e-6),
    );
    expect(positionAt(two, 0.5).dy, closeTo(0, 1e-6), reason: 'apex on top');
    final one = pressureCurvePath(tent, size, steps: 1);
    expect(one.computeMetrics().single.length, closeTo(100, 1e-6));
  });
}
