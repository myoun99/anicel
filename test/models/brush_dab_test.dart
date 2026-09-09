import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import '../helpers/json_round_trip.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_input_sample.dart';
import 'package:anicel/src/models/brush_pressure_curve.dart';
import 'package:anicel/src/models/brush_settings.dart';
import 'package:anicel/src/models/brush_tip_mask.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';

void main() {
  group('BrushDab', () {
    BrushDab dab({
      CanvasPoint? center,
      int color = 0xFF000000,
      double size = 4,
      double opacity = 1,
      double flow = 1,
      double hardness = 1,
      BrushTipShape tipShape = BrushTipShape.round,
      double pressure = 1,
      int sequence = 0,
      double roundness = 1,
      double angleDegrees = 0,
    }) {
      return BrushDab(
        center: center ?? CanvasPoint(x: 1, y: 2),
        color: color,
        size: size,
        opacity: opacity,
        flow: flow,
        hardness: hardness,
        tipShape: tipShape,
        pressure: pressure,
        sequence: sequence,
        roundness: roundness,
        angleDegrees: angleDegrees,
      );
    }



    test('rejects negative color', () {
      expect(() => dab(color: -1), throwsArgumentError);
    });

    test('rejects color greater than 0xFFFFFFFF', () {
      expect(() => dab(color: 0x100000000), throwsArgumentError);
    });

    test('rejects negative size', () {
      expect(() => dab(size: -0.1), throwsArgumentError);
    });

    test('allows zero size', () {
      expect(dab(size: 0).size, 0);
    });

    test('rejects opacity below 0', () {
      expect(() => dab(opacity: -0.1), throwsArgumentError);
    });

    test('rejects opacity above 1', () {
      expect(() => dab(opacity: 1.1), throwsArgumentError);
    });

    test('rejects flow below 0', () {
      expect(() => dab(flow: -0.1), throwsArgumentError);
    });

    test('rejects flow above 1', () {
      expect(() => dab(flow: 1.1), throwsArgumentError);
    });

    test('rejects hardness below 0', () {
      expect(() => dab(hardness: -0.1), throwsArgumentError);
    });

    test('rejects hardness above 1', () {
      expect(() => dab(hardness: 1.1), throwsArgumentError);
    });

    test('rejects pressure below 0', () {
      expect(() => dab(pressure: -0.1), throwsArgumentError);
    });

    test('rejects pressure above 1', () {
      expect(() => dab(pressure: 1.1), throwsArgumentError);
    });

    test('rejects negative sequence', () {
      expect(() => dab(sequence: -1), throwsArgumentError);
    });

    test('rejects non-finite size', () {
      expect(() => dab(size: double.nan), throwsArgumentError);
      expect(() => dab(size: double.infinity), throwsArgumentError);
    });

    test('rejects non-finite opacity', () {
      expect(() => dab(opacity: double.nan), throwsArgumentError);
      expect(() => dab(opacity: double.infinity), throwsArgumentError);
    });

    test('copyWith updates center', () {
      expect(
        dab().copyWith(center: CanvasPoint(x: 3, y: 4)).center,
        CanvasPoint(x: 3, y: 4),
      );
    });

    test('copyWith updates color', () {
      expect(dab().copyWith(color: 0x80FF3366).color, 0x80FF3366);
    });

    test('copyWith updates size', () {
      expect(dab().copyWith(size: 5).size, 5);
    });

    test('copyWith updates opacity', () {
      expect(dab().copyWith(opacity: 0.5).opacity, 0.5);
    });

    test('copyWith updates flow', () {
      expect(dab().copyWith(flow: 0.5).flow, 0.5);
    });

    test('copyWith updates hardness', () {
      expect(dab().copyWith(hardness: 0.5).hardness, 0.5);
    });

    test('copyWith updates tipShape', () {
      expect(
        dab().copyWith(tipShape: BrushTipShape.square).tipShape,
        BrushTipShape.square,
      );
    });

    test('copyWith updates pressure', () {
      expect(dab().copyWith(pressure: 0.5).pressure, 0.5);
    });

    test('copyWith updates sequence', () {
      expect(dab().copyWith(sequence: 5).sequence, 5);
    });

    test('equality includes all fields', () {
      final base = dab(
        size: 5,
        opacity: 0.6,
        flow: 0.7,
        hardness: 0.8,
        pressure: 0.9,
        sequence: 1,
      );
      expect(
        base,
        dab(
          size: 5,
          opacity: 0.6,
          flow: 0.7,
          hardness: 0.8,
          pressure: 0.9,
          sequence: 1,
        ),
      );
      expect(base.copyWith(center: CanvasPoint(x: 9, y: 2)), isNot(base));
      expect(base.copyWith(color: 0x80FF3366), isNot(base));
      expect(base.copyWith(size: 9), isNot(base));
      expect(base.copyWith(opacity: 0.9), isNot(base));
      expect(base.copyWith(flow: 0.9), isNot(base));
      expect(base.copyWith(hardness: 0.9), isNot(base));
      expect(base.copyWith(tipShape: BrushTipShape.square), isNot(base));
      expect(base.copyWith(pressure: 0.1), isNot(base));
      expect(base.copyWith(sequence: 2), isNot(base));
    });

    test('hashCode is value-based', () {
      expect(dab().hashCode, dab().hashCode);
    });

    test('toJson/fromJson round-trips', () {
      final value = dab(
        color: 0x80FF3366,
        tipShape: BrushTipShape.square,
        pressure: 0.4,
        sequence: 2,
        roundness: 0.4,
        angleDegrees: 137.5,
      );
      expectJsonRoundTrip(value, BrushDab.fromJson);
    });

    test('fromJson without color uses default black', () {
      final json = dab(color: 0x80FF3366).toJson()..remove('color');
      expect(BrushDab.fromJson(json).color, 0xFF000000);
    });

    test('erase flag round-trips and defaults to false', () {
      final eraseDab = dab().copyWith(erase: true);
      expect(BrushDab.fromJson(eraseDab.toJson()).erase, isTrue);

      // Paint dabs omit the key; legacy dabs without it stay paint dabs.
      final paintJson = dab().toJson();
      expect(paintJson.containsKey('erase'), isFalse);
      expect(BrushDab.fromJson(paintJson).erase, isFalse);
      expect(dab(), isNot(dab().copyWith(erase: true)));
    });

    test('fromJson defaults legacy dabs to the classic full-round tip', () {
      final json = dab().toJson()
        ..remove('roundness')
        ..remove('angleDegrees');
      final decoded = BrushDab.fromJson(json);
      expect(decoded.roundness, 1.0);
      expect(decoded.angleDegrees, 0.0);
    });

    test('rejects roundness outside (0, 1]', () {
      expect(() => dab(roundness: 0), throwsArgumentError);
      expect(() => dab(roundness: -0.2), throwsArgumentError);
      expect(() => dab(roundness: 1.1), throwsArgumentError);
      expect(() => dab(roundness: double.nan), throwsArgumentError);
    });

    test('rejects non-finite angle', () {
      expect(() => dab(angleDegrees: double.nan), throwsArgumentError);
      expect(() => dab(angleDegrees: double.infinity), throwsArgumentError);
    });

    test('copyWith updates roundness and angle', () {
      final updated = dab().copyWith(roundness: 0.5, angleDegrees: 45);
      expect(updated.roundness, 0.5);
      expect(updated.angleDegrees, 45.0);
      expect(dab().copyWith(size: 6).roundness, 1.0);
    });

    test('fromInputSample uses sample position as CanvasPoint', () {
      final value = BrushDab.fromInputSample(
        sample: BrushInputSample(x: 3, y: 4),
        settings: BrushSettings(),
        sequence: 0,
      );
      expect(value.center, CanvasPoint(x: 3, y: 4));
    });

    test('fromInputSample copies BrushSettings color', () {
      final value = BrushDab.fromInputSample(
        sample: BrushInputSample(x: 0, y: 0),
        settings: BrushSettings(color: 0x80FF3366),
        sequence: 0,
      );
      expect(value.color, 0x80FF3366);
    });

    test('fromInputSample carries the BASE values, curves unapplied', () {
      // 🚨The factory used to multiply the four curves in itself — a third
      // copy of the law that `applyBrushPressureDynamics` owns. It now hands
      // over the settings' base values and the sample's readings, and
      // `brushInputSamplesToBrushDabs` runs the law (see
      // `brush_dab_placement_test`, which asserts the product).
      final value = BrushDab.fromInputSample(
        sample: BrushInputSample(x: 0, y: 0, pressure: 0.25),
        settings: BrushSettings(
          size: 20,
          flow: 0.8,
          hardness: 0.5,
          sizePressureCurve: BrushPressureCurve.identity(),
          opacityPressureCurve: BrushPressureCurve.identity(),
          flowPressureCurve: BrushPressureCurve.identity(),
          hardnessPressureCurve: BrushPressureCurve.identity(),
        ),
        sequence: 0,
      );

      expect(value.size, 20);
      expect(value.flow, 0.8);
      expect(value.hardness, 0.5);
      // F-12 lives in the BASE: a dab's opacity starts at 1.0 because the
      // tool's opacity is the accumulated stroke's ceiling and rides
      // `BrushDabSequence.opacity` — on the dab it would cap nothing.
      expect(value.opacity, 1.0);
      // The reading still arrives, so the law downstream has something to
      // evaluate against.
      expect(value.pressure, 0.25);
    });

    test('🚨a BRUSH dab is always ROUND — there is no square brush', () {
      // 유저 2026-09-09: 「포토샵이나 클튜처럼 가자. 원이나 이미지」. A brush
      // tip is the analytic round one or a tip IMAGE, which is the pair Clip
      // Studio and Photoshop both offer — neither has a parametric square.
      // `BrushDab.tipShape` survives for the FILL, selection-lift and
      // cut-stamp verbs, which build a square dab to mean "cover exactly this
      // rect"; nothing a brush can set reaches it.
      expect(
        BrushDab.fromInputSample(
          sample: BrushInputSample(x: 0, y: 0),
          settings: BrushSettings(),
          sequence: 0,
        ).tipShape,
        BrushTipShape.round,
      );
    });

    test('a round dab writes no tipShape key at all', () {
      // Byte-identity with strokes recorded before the field left the brush:
      // every dab a brush lays is round, so the key never appears again.
      final json = BrushDab.fromInputSample(
        sample: BrushInputSample(x: 0, y: 0),
        settings: BrushSettings(),
        sequence: 0,
      ).toJson();

      expect(json.containsKey('tipShape'), isFalse);
      // ...and the verbs that DO set it still round-trip.
      final square = BrushDab.fromJson(
        BrushDab.fromInputSample(
          sample: BrushInputSample(x: 0, y: 0),
          settings: BrushSettings(),
          sequence: 0,
        ).copyWith(tipShape: BrushTipShape.square).toJson(),
      );
      expect(square.tipShape, BrushTipShape.square);
    });

    test('fromInputSample preserves flow and hardness', () {
      final value = BrushDab.fromInputSample(
        sample: BrushInputSample(x: 0, y: 0),
        settings: BrushSettings(
          flow: 0.3,
          hardness: 0.4,
        ),
        sequence: 0,
      );
      expect(value.flow, 0.3);
      expect(value.hardness, 0.4);
      expect(value.tipShape, BrushTipShape.square);
    });

    test('fromInputSample carries roundness and angle', () {
      final value = BrushDab.fromInputSample(
        sample: BrushInputSample(x: 0, y: 0),
        settings: BrushSettings(roundness: 0.6, angleDegrees: 30),
        sequence: 0,
      );
      expect(value.roundness, 0.6);
      expect(value.angleDegrees, 30.0);
    });

    test('tipMask round-trips through json and equality', () {
      final mask = BrushTipMask(
        id: 'tip',
        size: 2,
        alpha: Uint8List.fromList([0, 128, 255, 64]),
      );
      final value = dab().copyWith(tipMask: mask);
      expect(value.tipMask, mask);
      expect(BrushDab.fromJson(value.toJson()), value);
      // Legacy json without a mask stays maskless.
      expect(BrushDab.fromJson(dab().toJson()).tipMask, isNull);
    });

    test('fromInputSample carries the settings tip mask', () {
      final mask = BrushTipMask(
        id: 'tip',
        size: 2,
        alpha: Uint8List.fromList([0, 128, 255, 64]),
      );
      final value = BrushDab.fromInputSample(
        sample: BrushInputSample(x: 0, y: 0),
        settings: BrushSettings(tipMask: mask),
        sequence: 0,
      );
      expect(value.tipMask, mask);
    });
  });
}
