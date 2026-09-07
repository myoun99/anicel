import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/se_name_tag.dart';
import 'package:anicel/src/models/text_cel_style.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/ui/text/trimmed_decimal.dart';
import 'package:anicel/src/ui/timeline/effect_lane_policy.dart';
import 'package:anicel/src/ui/timeline/se_name_tag_lane_policy.dart';
import 'package:anicel/src/ui/timeline/transform_lane_policy.dart';

/// Characterisation of the numeric readout law the value columns share:
/// round to N decimals, then print an integer when the rounded value is
/// whole and drop the trailing zeros otherwise.
///
/// Pinned through the three public lane formatters BEFORE the law moved
/// into one place, so the move is provably byte-for-byte.
void main() {
  const numberSpec = EffectParameterSpec(
    id: 'p',
    label: 'P',
    minimum: -10000,
    maximum: 10000,
    defaultValue: 0,
    unit: EffectParameterUnit.number,
  );

  const oneDecimal = <(double, String)>[
    (0.0, '0'),
    (12.0, '12'),
    (12.5, '12.5'),
    (12.44, '12.4'),
    (-3.5, '-3.5'),
    (99.96, '100'),
    (0.04, '0'),
    (-0.04, '0'),
    (1234.0, '1234'),
  ];

  group('one decimal, whole numbers print as integers', () {
    test('an effect lane in the plain number unit', () {
      for (final (value, text) in oneDecimal) {
        expect(
          formatEffectLaneValue(numberSpec, value),
          text,
          reason: 'value $value',
        );
      }
    });

    test('a transform lane carries its unit around the same number', () {
      expect(
        formatTransformLaneValue(
          'rotation',
          TransformPose(center: CanvasPoint(x: 0, y: 0), rotationDegrees: -3.5),
        ),
        '-3.5°',
      );
      expect(
        formatTransformLaneValue(
          'position',
          TransformPose(center: CanvasPoint(x: 12.0, y: 99.96)),
        ),
        '12, 100',
      );
    });

    test('a name-tag lane reads the same law', () {
      const tag = SeNameTag(
        style: TextCelStyle(fontSize: 12.44, letterSpacing: 0.04),
      );
      expect(formatSeNameTagLaneValue(seNameTagSizeLaneId, tag), '12.4');
      expect(formatSeNameTagLaneValue(seNameTagTrackingLaneId, tag), '0');
    });

    test('the shared law answers each of them the same way', () {
      for (final (value, text) in oneDecimal) {
        expect(formatTrimmedDecimal(value), text, reason: 'value $value');
      }
    });
  });

  group('two decimals — the Move tool readouts', () {
    test('trailing zeros go, they do not pad out to the digit count', () {
      expect(formatTrimmedDecimal(12.5, fractionDigits: 2), '12.5');
      expect(formatTrimmedDecimal(12.0, fractionDigits: 2), '12');
      expect(formatTrimmedDecimal(-2.5, fractionDigits: 2), '-2.5');
    });

    test('the second decimal survives, unlike at one digit', () {
      expect(formatTrimmedDecimal(12.34, fractionDigits: 2), '12.34');
      expect(formatTrimmedDecimal(12.34), '12.3');
      expect(formatTrimmedDecimal(0.126, fractionDigits: 2), '0.13');
    });
  });
}
