import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_pixel_coverage.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/rgba_color.dart';
import 'package:anicel/src/services/brush_pixel_blend.dart';

void main() {
  BrushDab dab({int color = 0xFFFF0000, double opacity = 1, double flow = 1}) {
    return BrushDab(
      center: CanvasPoint(x: 0, y: 0),
      color: color,
      size: 1,
      opacity: opacity,
      flow: flow,
      hardness: 1,
      tipShape: BrushTipShape.round,
      pressure: 1,
      sequence: 0,
    );
  }

  BrushPixelCoverage pixelCoverage({
    int x = 0,
    int y = 0,
    double coverage = 1,
  }) {
    return BrushPixelCoverage(x: x, y: y, coverage: coverage);
  }

  group('effectiveBrushPixelOpacity', () {
    test('multiplies dab opacity by coverage', () {
      expect(
        effectiveBrushPixelOpacity(
          dab: dab(opacity: 0.5),
          coverage: pixelCoverage(coverage: 0.25),
        ),
        0.125,
      );
    });

    test('returns 0 when dab opacity is 0', () {
      expect(
        effectiveBrushPixelOpacity(
          dab: dab(opacity: 0),
          coverage: pixelCoverage(coverage: 1),
        ),
        0,
      );
    });

    test('returns 0 when coverage is 0', () {
      expect(
        effectiveBrushPixelOpacity(
          dab: dab(opacity: 1),
          coverage: pixelCoverage(coverage: 0),
        ),
        0,
      );
    });

    test('returns 1 when dab opacity and coverage are both 1', () {
      expect(
        effectiveBrushPixelOpacity(
          dab: dab(opacity: 1),
          coverage: pixelCoverage(coverage: 1),
        ),
        1,
      );
    });
  });

  group('blendBrushDabPixelCoverage', () {
    test('uses dab.color as source color', () {
      expect(
        blendBrushDabPixelCoverage(
          dab: dab(color: 0xFF00FF00),
          coverage: pixelCoverage(),
          destination: RgbaColor(r: 0, g: 0, b: 0, a: 0),
        ),
        RgbaColor(r: 0, g: 255, b: 0, a: 255),
      );
    });

    test('respects dab color alpha', () {
      expect(
        blendBrushDabPixelCoverage(
          dab: dab(color: 0x80FF0000),
          coverage: pixelCoverage(),
          destination: RgbaColor(r: 0, g: 0, b: 0, a: 0),
        ),
        RgbaColor(r: 255, g: 0, b: 0, a: 128),
      );
    });

    test('respects dab opacity', () {
      expect(
        blendBrushDabPixelCoverage(
          dab: dab(opacity: 0.5),
          coverage: pixelCoverage(),
          destination: RgbaColor(r: 0, g: 0, b: 0, a: 0),
        ),
        RgbaColor(r: 255, g: 0, b: 0, a: 128),
      );
    });

    test('respects dab flow', () {
      expect(
        blendBrushDabPixelCoverage(
          dab: dab(flow: 0.5),
          coverage: pixelCoverage(),
          destination: RgbaColor(r: 0, g: 0, b: 0, a: 0),
        ),
        RgbaColor(r: 255, g: 0, b: 0, a: 128),
      );
    });

    test('respects pixel coverage', () {
      expect(
        blendBrushDabPixelCoverage(
          dab: dab(),
          coverage: pixelCoverage(coverage: 0.5),
          destination: RgbaColor(r: 0, g: 0, b: 0, a: 0),
        ),
        RgbaColor(r: 255, g: 0, b: 0, a: 128),
      );
    });

    test('returns destination when coverage is 0', () {
      final destination = RgbaColor(r: 1, g: 2, b: 3, a: 4);
      expect(
        blendBrushDabPixelCoverage(
          dab: dab(),
          coverage: pixelCoverage(coverage: 0),
          destination: destination,
        ),
        destination,
      );
    });

    test('returns destination when dab opacity is 0', () {
      final destination = RgbaColor(r: 1, g: 2, b: 3, a: 4);
      expect(
        blendBrushDabPixelCoverage(
          dab: dab(opacity: 0),
          coverage: pixelCoverage(),
          destination: destination,
        ),
        destination,
      );
    });

    test('returns destination when dab flow is 0', () {
      final destination = RgbaColor(r: 1, g: 2, b: 3, a: 4);
      expect(
        blendBrushDabPixelCoverage(
          dab: dab(flow: 0),
          coverage: pixelCoverage(),
          destination: destination,
        ),
        destination,
      );
    });

    test('blends over transparent destination', () {
      expect(
        blendBrushDabPixelCoverage(
          dab: dab(),
          coverage: pixelCoverage(),
          destination: RgbaColor(r: 0, g: 0, b: 0, a: 0),
        ),
        RgbaColor(r: 255, g: 0, b: 0, a: 255),
      );
    });

    test('blends over opaque destination', () {
      expect(
        blendBrushDabPixelCoverage(
          dab: dab(),
          coverage: pixelCoverage(coverage: 0.5),
          destination: RgbaColor(r: 0, g: 0, b: 255, a: 255),
        ),
        RgbaColor(r: 128, g: 0, b: 128, a: 255),
      );
    });

    test('does not mutate BrushDab', () {
      final value = dab(opacity: 0.5, flow: 0.5);
      final before = value.copyWith();
      blendBrushDabPixelCoverage(
        dab: value,
        coverage: pixelCoverage(coverage: 0.5),
        destination: RgbaColor(r: 0, g: 0, b: 0, a: 0),
      );
      expect(value, before);
    });

    test('does not mutate BrushPixelCoverage', () {
      final value = pixelCoverage(x: 1, y: 2, coverage: 0.5);
      final before = value.copyWith();
      blendBrushDabPixelCoverage(
        dab: dab(),
        coverage: value,
        destination: RgbaColor(r: 0, g: 0, b: 0, a: 0),
      );
      expect(value, before);
    });

    test('does not mutate destination RgbaColor', () {
      final destination = RgbaColor(r: 1, g: 2, b: 3, a: 4);
      final before = destination.copyWith();
      blendBrushDabPixelCoverage(
        dab: dab(),
        coverage: pixelCoverage(coverage: 0.5),
        destination: destination,
      );
      expect(destination, before);
    });
  });
}
