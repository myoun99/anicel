import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_pressure_curve.dart';
import 'package:anicel/src/models/brush_settings.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';

void main() {
  group('BrushSettings', () {
    test('default values are stable', () {
      final brush = BrushSettings();

      expect(brush.color, 0xFF000000);
      expect(brush.size, 4.0);
      expect(brush.opacity, 1.0);
      expect(brush.flow, 1.0);
      expect(brush.hardness, 1.0);
      expect(brush.spacing, 0.1);
      expect(brush.tipShape, BrushTipShape.round);
      expect(brush.sizePressureCurve, isNull);
      expect(brush.opacityPressureCurve, isNull);
      expect(brush.flowPressureCurve, isNull);
      expect(brush.hardnessPressureCurve, isNull);
      expect(brush.roundness, 1.0);
      expect(brush.angleDegrees, 0.0);
    });

    test('copyWith updates each field independently', () {
      final brush = BrushSettings();

      expect(brush.copyWith(color: 0xFFFFFFFF).color, 0xFFFFFFFF);
      expect(brush.copyWith(size: 8).size, 8);
      expect(brush.copyWith(opacity: 0.5).opacity, 0.5);
      expect(brush.copyWith(flow: 0.25).flow, 0.25);
      expect(brush.copyWith(hardness: 0.75).hardness, 0.75);
      expect(brush.copyWith(spacing: 0.2).spacing, 0.2);
      expect(
        brush.copyWith(tipShape: BrushTipShape.square).tipShape,
        BrushTipShape.square,
      );
      expect(
        brush
            .copyWith(sizePressureCurve: BrushPressureCurve.identity())
            .sizePressureCurve,
        BrushPressureCurve.identity(),
      );
      expect(
        brush
            .copyWith(opacityPressureCurve: BrushPressureCurve.identity())
            .opacityPressureCurve,
        BrushPressureCurve.identity(),
      );
      expect(brush.copyWith(roundness: 0.5).roundness, 0.5);
      expect(brush.copyWith(angleDegrees: 45).angleDegrees, 45.0);
      expect(brush, BrushSettings());
    });

    test('equality includes new fields', () {
      final brush = BrushSettings();

      expect(brush.copyWith(flow: 0.5), isNot(brush));
      expect(brush.copyWith(hardness: 0.5), isNot(brush));
      expect(brush.copyWith(spacing: 0.2), isNot(brush));
      expect(brush.copyWith(tipShape: BrushTipShape.square), isNot(brush));
      expect(
        brush.copyWith(sizePressureCurve: BrushPressureCurve.identity()),
        isNot(brush),
      );
      expect(
        brush.copyWith(opacityPressureCurve: BrushPressureCurve.identity()),
        isNot(brush),
      );
      expect(brush.copyWith(roundness: 0.5), isNot(brush));
      expect(brush.copyWith(angleDegrees: 45), isNot(brush));
    });

    test('toJson includes new fields', () {
      final json = BrushSettings().toJson();

      expect(
        json.keys,
        containsAll(<String>[
          'color',
          'size',
          'opacity',
          'flow',
          'hardness',
          'spacing',
          'tipShape',
          'roundness',
          'angleDegrees',
        ]),
      );
    });

    test('fromJson round-trips new fields', () {
      final brush = BrushSettings(
        color: 0xFF123456,
        size: 12,
        opacity: 0.6,
        flow: 0.4,
        hardness: 0.8,
        spacing: 0.15,
        tipShape: BrushTipShape.square,
        sizePressureCurve: BrushPressureCurve.linearFrom(0.3),
        opacityPressureCurve: BrushPressureCurve.identity(),
        roundness: 0.35,
        angleDegrees: 120,
      );

      expect(BrushSettings.fromJson(brush.toJson()), brush);
    });

    test('fromJson supports legacy color/size/opacity JSON', () {
      final brush = BrushSettings.fromJson({
        'color': 0xFFFFFFFF,
        'size': 6,
        'opacity': 0.5,
      });

      expect(brush, BrushSettings(color: 0xFFFFFFFF, size: 6, opacity: 0.5));
      expect(brush.flow, 1.0);
      expect(brush.hardness, 1.0);
      expect(brush.spacing, 0.1);
      expect(brush.tipShape, BrushTipShape.round);
      expect(brush.sizePressureCurve, isNull);
      expect(brush.opacityPressureCurve, isNull);
      expect(brush.flowPressureCurve, isNull);
      expect(brush.hardnessPressureCurve, isNull);
      expect(brush.roundness, 1.0);
      expect(brush.angleDegrees, 0.0);
    });

    test('fromJson migrates legacy pressure toggles to curves (BB-3)', () {
      // pressureSize ON with a minimum floor becomes the straight line
      // (0, min)-(1, 1); pressureOpacity ON becomes the identity line.
      final brush = BrushSettings.fromJson({
        'color': 0xFF000000,
        'size': 10,
        'opacity': 1.0,
        'pressureSize': true,
        'pressureOpacity': true,
        'minimumSizeRatio': 0.3,
      });

      expect(brush.sizePressureCurve, BrushPressureCurve.linearFrom(0.3));
      expect(brush.opacityPressureCurve, BrushPressureCurve.identity());
      expect(brush.flowPressureCurve, isNull);
      expect(brush.hardnessPressureCurve, isNull);
      // Behavior parity with the old formula at any pressure.
      expect(
        brush.sizePressureCurve!.evaluate(0.5),
        closeTo(0.3 + 0.7 * 0.5, 1e-12),
      );
    });

    test('fromJson ignores legacy toggles when OFF', () {
      final brush = BrushSettings.fromJson({
        'color': 0xFF000000,
        'size': 10,
        'opacity': 1.0,
        'pressureSize': false,
        'pressureOpacity': false,
        'minimumSizeRatio': 0.3,
      });

      expect(brush.sizePressureCurve, isNull);
      expect(brush.opacityPressureCurve, isNull);
    });

    test('invalid size throws', () {
      expect(() => BrushSettings(size: 0), throwsArgumentError);
    });

    test('invalid roundness throws', () {
      expect(() => BrushSettings(roundness: 0), throwsArgumentError);
      expect(() => BrushSettings(roundness: 1.1), throwsArgumentError);
      expect(() => BrushSettings(roundness: double.nan), throwsArgumentError);
    });

    test('non-finite angle throws', () {
      expect(
        () => BrushSettings(angleDegrees: double.infinity),
        throwsArgumentError,
      );
    });

    test('invalid opacity throws', () {
      expect(() => BrushSettings(opacity: -0.1), throwsArgumentError);
      expect(() => BrushSettings(opacity: 1.1), throwsArgumentError);
    });

    test('invalid flow throws', () {
      expect(() => BrushSettings(flow: -0.1), throwsArgumentError);
      expect(() => BrushSettings(flow: 1.1), throwsArgumentError);
    });

    test('invalid hardness throws', () {
      expect(() => BrushSettings(hardness: -0.1), throwsArgumentError);
      expect(() => BrushSettings(hardness: 1.1), throwsArgumentError);
    });

    test('invalid spacing throws', () {
      expect(() => BrushSettings(spacing: 0), throwsArgumentError);
    });
  });
}
