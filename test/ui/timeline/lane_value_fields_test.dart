import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/ui/timeline/effect_lane_policy.dart';
import 'package:anicel/src/ui/timeline/property_lane_model.dart';
import 'package:anicel/src/ui/timeline/transform_lane_policy.dart';

/// **F-22 ②③ — a unit is not a value, and a pair is not a sentence.**
///
/// 유저 2026-08-24: 「**단위 같은 고정요소를 편집창에서 제거**」,
/// 「**포지션 등 2요소는 각각 편집**(온점 없이)」.
///
/// The lane's value editor was one text box over the whole readout, so
/// changing Scale meant typing the percent sign back and nudging Position's
/// y meant retyping `120, 45` — comma, space and all — around the one number
/// that changed.
void main() {
  group('what is edited and what is chrome', () {
    test('a unit is chrome', () {
      expect(propertyLaneValueParts('85%'), [(number: '85', unit: '%')]);
      expect(propertyLaneValueParts('30°'), [(number: '30', unit: '°')]);
      expect(propertyLaneValueParts('12 px'), [(number: '12', unit: ' px')]);
    });

    test('a pair is two values, and the separator is chrome', () {
      expect(propertyLaneValueParts('120, 45'), [
        (number: '120', unit: ''),
        (number: '45', unit: ''),
      ]);
    });

    test('negatives and decimals are numbers, not units', () {
      expect(propertyLaneValueParts('-3.5%'), [(number: '-3.5', unit: '%')]);
      expect(propertyLaneValueParts('-12, -0.5'), [
        (number: '-12', unit: ''),
        (number: '-0.5', unit: ''),
      ]);
    });

    test('⛔a value that is not a number stays ONE field', () {
      // A colour, a font name, a flag: nothing to split and no unit to
      // strip, so the editor is the single free-text box it always was.
      expect(propertyLaneValueParts('#FFAA00'), [
        (number: '#FFAA00', unit: ''),
      ]);
      expect(propertyLaneValueParts('on'), [(number: 'on', unit: '')]);
      expect(propertyLaneValueParts('none'), [(number: 'none', unit: '')]);
    });

    test('⛔and a TEXT value that happens to hold a comma is still one', () {
      expect(propertyLaneValueParts('Hello, world'), [
        (number: 'Hello, world', unit: ''),
      ]);
      expect(propertyLaneValueParts('120, world'), [
        (number: '120, world', unit: ''),
      ]);
    });
  });

  group('the split is reversible, for every label this app prints', () {
    /// 🚨The round trip is what lets the commit path stay untouched: what
    /// leaves the editor is the same text form every lane parser has always
    /// read. A split that could not be rejoined would be a second answer to
    /// "what does this value look like".
    void roundTrips(String label) {
      expect(
        joinPropertyLaneValueParts(propertyLaneValueParts(label)),
        label,
        reason: 'split then joined must be the label it started as',
      );
    }

    test('transform lanes', () {
      final pose = TransformPose(
        center: CanvasPoint(x: 120, y: 45.5),
        zoom: 0.85,
        rotationDegrees: -30,
      );
      for (final laneId in ['position', 'scale', 'rotation']) {
        roundTrips(formatTransformLaneValue(laneId, pose));
      }
    });

    test('effect lanes, every unit', () {
      for (final unit in EffectParameterUnit.values) {
        roundTrips(
          formatEffectLaneValue(
            EffectParameterSpec(
              id: 'p',
              label: 'P',
              minimum: -100,
              maximum: 100,
              defaultValue: 0,
              unit: unit,
            ),
            12.5,
          ),
        );
      }
    });

    test('and the values that are not numbers at all', () {
      for (final label in ['#FFAA00', 'on', 'off', 'none', 'Gothic A1']) {
        roundTrips(label);
      }
    });
  });

  group('what the editor hands back', () {
    /// The parsers are the other half of the contract: the rejoined text has
    /// to be something the lane can actually read. These are the very
    /// functions the commit calls.
    test('a scale typed WITHOUT its percent sign still parses', () {
      final rejoined = joinPropertyLaneValueParts([
        (number: '200', unit: '%'),
      ]);
      expect(rejoined, '200%');
      expect(
        scrubTransformLaneValue('scale', rejoined, Offset.zero),
        '200%',
        reason: 'the lane reads it exactly as it reads its own readout',
      );
    });

    test('a position typed as two bare numbers parses as a pair', () {
      final rejoined = joinPropertyLaneValueParts([
        (number: '10', unit: ''),
        (number: '-4', unit: ''),
      ]);
      expect(rejoined, '10, -4');
      expect(
        scrubTransformLaneValue('position', rejoined, Offset.zero),
        '10, -4',
        reason: '🚨the comma the user no longer types is put back here',
      );
    });
  });
}
