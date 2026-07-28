import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_pressure_curve.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/ui/canvas/brush_edit_canvas_input_settings.dart';

void main() {
  group('BrushEditCanvasInputSettings', () {
    test('default values', () {
      final settings = BrushEditCanvasInputSettings();

      expect(settings.color, 0xFF000000);
      expect(settings.size, 1.0);
      expect(settings.opacity, 1.0);
      expect(settings.flow, 1.0);
      expect(settings.hardness, 1.0);
      expect(settings.tipShape, BrushTipShape.round);
      expect(settings.sizePressureCurve, isNull);
      expect(settings.opacityPressureCurve, isNull);
      expect(settings.flowPressureCurve, isNull);
      expect(settings.hardnessPressureCurve, isNull);
      expect(settings.hasPressureDynamics, isFalse);
    });

    test('stores custom values', () {
      final settings = BrushEditCanvasInputSettings(
        color: 0xFFFF00FF,
        size: 3.0,
        opacity: 0.5,
        flow: 0.25,
        hardness: 0.75,
        tipShape: BrushTipShape.square,
      );

      expect(settings.color, 0xFFFF00FF);
      expect(settings.size, 3.0);
      expect(settings.opacity, 0.5);
      expect(settings.flow, 0.25);
      expect(settings.hardness, 0.75);
      expect(settings.tipShape, BrushTipShape.square);
    });

    test('rejects size <= 0', () {
      expect(() => BrushEditCanvasInputSettings(size: 0), throwsAssertionError);
      expect(
        () => BrushEditCanvasInputSettings(size: -1),
        throwsAssertionError,
      );
    });

    test('rejects opacity < 0', () {
      expect(
        () => BrushEditCanvasInputSettings(opacity: -0.1),
        throwsAssertionError,
      );
    });

    test('rejects opacity > 1', () {
      expect(
        () => BrushEditCanvasInputSettings(opacity: 1.1),
        throwsAssertionError,
      );
    });

    test('rejects flow < 0', () {
      expect(
        () => BrushEditCanvasInputSettings(flow: -0.1),
        throwsAssertionError,
      );
    });

    test('rejects flow > 1', () {
      expect(
        () => BrushEditCanvasInputSettings(flow: 1.1),
        throwsAssertionError,
      );
    });

    test('rejects hardness < 0', () {
      expect(
        () => BrushEditCanvasInputSettings(hardness: -0.1),
        throwsAssertionError,
      );
    });

    test('rejects hardness > 1', () {
      expect(
        () => BrushEditCanvasInputSettings(hardness: 1.1),
        throwsAssertionError,
      );
    });

    test('stores and copies roundness and angle', () {
      final settings = BrushEditCanvasInputSettings(
        roundness: 0.4,
        angleDegrees: 30,
      );
      expect(settings.roundness, 0.4);
      expect(settings.angleDegrees, 30.0);

      final updated = settings.copyWith(angleDegrees: 90);
      expect(updated.roundness, 0.4);
      expect(updated.angleDegrees, 90.0);

      final defaults = BrushEditCanvasInputSettings();
      expect(defaults.roundness, 1.0);
      expect(defaults.angleDegrees, 0.0);
      expect(settings == defaults, isFalse);
    });

    test('rejects roundness outside (0, 1]', () {
      expect(
        () => BrushEditCanvasInputSettings(roundness: 0),
        throwsAssertionError,
      );
      expect(
        () => BrushEditCanvasInputSettings(roundness: 1.1),
        throwsAssertionError,
      );
    });

    test('stores and copies pressure curves (BB-3)', () {
      final settings = BrushEditCanvasInputSettings(
        sizePressureCurve: BrushPressureCurve.identity(),
        opacityPressureCurve: BrushPressureCurve.linearFrom(0.2),
      );
      expect(settings.sizePressureCurve, BrushPressureCurve.identity());
      expect(settings.opacityPressureCurve, BrushPressureCurve.linearFrom(0.2));
      expect(settings.hasPressureDynamics, isTrue);

      final updated = settings.copyWith(
        flowPressureCurve: BrushPressureCurve.identity(),
      );
      expect(updated.sizePressureCurve, BrushPressureCurve.identity());
      expect(updated.flowPressureCurve, BrushPressureCurve.identity());

      final a = BrushEditCanvasInputSettings(
        sizePressureCurve: BrushPressureCurve.identity(),
      );
      final b = BrushEditCanvasInputSettings(
        sizePressureCurve: BrushPressureCurve.identity(),
      );
      final c = BrushEditCanvasInputSettings();
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == c, isFalse);
      expect(a.toString(), contains('sizePressureCurve: BrushPressureCurve'));
    });

    test('copyWith preserves omitted values', () {
      final settings = BrushEditCanvasInputSettings(color: 0xFF112233, size: 2);

      expect(settings.copyWith(), settings);
    });

    test('copyWith updates each field', () {
      final updated = BrushEditCanvasInputSettings().copyWith(
        color: 0xFF445566,
        size: 4,
        opacity: 0.4,
        flow: 0.3,
        hardness: 0.2,
        tipShape: BrushTipShape.square,
      );

      expect(
        updated,
        BrushEditCanvasInputSettings(
          color: 0xFF445566,
          size: 4,
          opacity: 0.4,
          flow: 0.3,
          hardness: 0.2,
          tipShape: BrushTipShape.square,
        ),
      );
    });

    test('equality / hashCode / toString', () {
      final a = BrushEditCanvasInputSettings(size: 2, opacity: 0.5);
      final b = BrushEditCanvasInputSettings(size: 2, opacity: 0.5);
      final c = BrushEditCanvasInputSettings(size: 3, opacity: 0.5);

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == c, isFalse);
      expect(a.toString(), contains('BrushEditCanvasInputSettings'));
      expect(a.toString(), contains('size: 2.0'));
    });
  });
}
