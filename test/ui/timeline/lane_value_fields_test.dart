import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/ui/timeline/effect_lane_policy.dart';
import 'package:anicel/src/ui/text/readout_text.dart';
import 'package:anicel/src/ui/timeline/scale_lane_form.dart';
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
      expect(readoutParts('85%'), [(number: '85', unit: '%')]);
      expect(readoutParts('30°'), [(number: '30', unit: '°')]);
      expect(readoutParts('12 px'), [(number: '12', unit: ' px')]);
    });

    test('a pair is two values, and the separator is chrome', () {
      expect(readoutParts('120, 45'), [
        (number: '120', unit: ''),
        (number: '45', unit: ''),
      ]);
    });

    test('negatives and decimals are numbers, not units', () {
      expect(readoutParts('-3.5%'), [(number: '-3.5', unit: '%')]);
      expect(readoutParts('-12, -0.5'), [
        (number: '-12', unit: ''),
        (number: '-0.5', unit: ''),
      ]);
    });

    test('⛔a value that is not a number stays ONE field', () {
      // A colour, a font name, a flag: nothing to split and no unit to
      // strip, so the editor is the single free-text box it always was.
      expect(readoutParts('#FFAA00'), [
        (number: '#FFAA00', unit: ''),
      ]);
      expect(readoutParts('on'), [(number: 'on', unit: '')]);
      expect(readoutParts('none'), [(number: 'none', unit: '')]);
    });

    test('⛔and a TEXT value that happens to hold a comma is still one', () {
      expect(readoutParts('Hello, world'), [
        (number: 'Hello, world', unit: ''),
      ]);
      expect(readoutParts('120, world'), [
        (number: '120, world', unit: ''),
      ]);
    });
  });

  group('an angle is its turns and its degrees (I-132-Q17)', () {
    test('as After Effects writes one, every digit on the degrees', () {
      expect(
        [
          for (final degrees in const [0.0, 90, 450, -90, -450, -360, 720])
            turnsReadoutText(degrees.toDouble()),
        ],
        [
          '0x+0.00°',
          '0x+90.00°',
          '1x+90.00°',
          '0x-90.00°',
          '-1x-90.00°',
          '-1x+0.00°',
          '2x+0.00°',
        ],
      );
      expect(
        turnsReadoutText(359.999),
        '1x+0.00°',
        reason: 'on the readout grid first, so a whole turn is one',
      );
    });

    test('two boxes, rejoined as they were, with no comma', () {
      final parts = readoutParts('1x+90.00°');
      expect(parts, [
        (number: '1', unit: 'x'),
        (number: '+90.00', unit: '°'),
      ]);
      expect(readsTurns(parts), isTrue);
      expect(joinReadoutParts(parts), '1x+90.00°');
      expect(
        columnValueOf(
          joinReadoutParts([parts.first, (number: '-30', unit: '°')]),
        ),
        330,
        reason: 'a box typed: the turns kept, the degrees its own',
      );
    });

    test('⛔what is no angle is not read as one', () {
      expect(readsTurns(readoutParts('120, 45')), isFalse);
      expect(readoutParts('12 px'), [(number: '12', unit: ' px')]);
      expect(readoutParts('2x'), [(number: '2', unit: 'x')]);
      expect(readsTurns(readoutParts('2x')), isFalse);
      expect(
        readoutParts('1920x1080'),
        [(number: '1920', unit: 'x1080')],
        reason: 'a size: what follows its x is no angle',
      );
      expect(columnValueOf('12 px'), 12, reason: 'the x of px leads no turns');
    });
  });

  group('the split is reversible, for every label this app prints', () {
    /// 🚨The round trip is what lets the commit path stay untouched: what
    /// leaves the editor is the same text form every lane parser has always
    /// read. A split that could not be rejoined would be a second answer to
    /// "what does this value look like".
    void roundTrips(String label) {
      expect(
        joinReadoutParts(readoutParts(label)),
        label,
        reason: 'split then joined must be the label it started as',
      );
    }

    test('transform lanes', () {
      final pose = TransformPose(
        center: CanvasPoint(x: 120, y: 45.5),
        scaleX: 0.85,
        scaleY: -1.2,
        rotationDegrees: -30,
      );
      for (final laneId in ['position', 'rotation']) {
        roundTrips(formatTransformLaneValue(laneId, pose));
      }
      // Scale in both its forms: a camera's one zoom, a layer's two.
      roundTrips(const OneZoom().label(uniformScale(0.85)));
      roundTrips(const TwoScales().label(pose.scale));
    });

    test("a layer's Scale is edited as TWO numbers, the percent worn once", () {
      expect(
        readoutParts(
          const TwoScales().label(CanvasPoint(x: 0.85, y: -1.2)),
        ),
        [(number: '85.00', unit: ''), (number: '-120.00', unit: '%')],
      );
    });

    test('effect lanes, every unit', () {
      for (final unit in EffectParameterUnit.values) {
        // I-132-Q12 b: a point is no number — its row prints it as a
        // Position's does.
        if (unit == EffectParameterUnit.point) {
          roundTrips(
            transformPositionLane(
              TransformTrack.empty(),
              laneId: 'p',
              label: 'P',
              poseAt: (_) =>
                  TransformPose(center: CanvasPoint(x: 120, y: 45.5)),
            ).valueLabel!(0),
          );
          continue;
        }
        // I-132-Q16 a: nor is a row — its lane prints the row it names by
        // its name, or none.
        if (unit == EffectParameterUnit.layer) {
          final lens = LayerEffect.defaults(
            id: const EffectId('lens'),
            kind: EffectKind.cameraLensBlur,
          );
          final rows = [
            Layer(id: const LayerId('a'), name: 'Layer 2', frames: const []),
          ];
          for (final named in [null, const LayerId('a')]) {
            final lane = effectPropertyLanes(
              [lens.withLayer('blurMapLayer', named)],
              cutRows: rows,
              isExpanded: (_) => true,
            ).firstWhere(
              (lane) => lane.laneId == effectLaneId(lens.id, 'blurMapLayer'),
            );
            roundTrips(lane.valueLabel!(0));
          }
          continue;
        }
        final (spec, value) = switch (unit) {
          EffectParameterUnit.choice => (
            const EffectParameterSpec.choice(
              id: 'p',
              label: 'P',
              choices: [
                EffectChoice(id: 'one', label: 'One'),
                EffectChoice(id: 'two', label: 'Two Words'),
              ],
            ),
            1.0,
          ),
          EffectParameterUnit.color => (
            const EffectParameterSpec.color(
              id: 'p',
              label: 'P',
              defaultValue: 0xFF000000,
            ),
            0xFFC80A1E.toDouble(),
          ),
          EffectParameterUnit.flag => (
            const EffectParameterSpec.flag(id: 'p', label: 'P'),
            1.0,
          ),
          _ => (
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
        };
        roundTrips(formatEffectLaneValue(spec, value));
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
      final rejoined = joinReadoutParts([
        (number: '200', unit: '%'),
      ]);
      expect(rejoined, '200%');
      expect(
        const OneZoom().typed(
          rejoined,
          current: uniformScale(1),
          linked: false,
        ),
        uniformScale(2),
        reason: 'the lane reads it exactly as it reads its own readout',
      );
    });

    test("a layer's two scales typed as two bare numbers parse as the "
        'pair', () {
      final rejoined = joinReadoutParts([
        (number: '200', unit: ''),
        (number: '-50', unit: '%'),
      ]);
      expect(rejoined, '200, -50%');
      expect(
        const TwoScales().typed(
          rejoined,
          current: uniformScale(1),
          linked: false,
        ),
        CanvasPoint(x: 2, y: -0.5),
      );
    });

    test('a position typed as two bare numbers parses as a pair', () {
      final rejoined = joinReadoutParts([
        (number: '10', unit: ''),
        (number: '-4', unit: ''),
      ]);
      expect(rejoined, '10, -4');
      expect(
        scrubTransformLaneValue('position', rejoined, Offset.zero),
        '10.00, -4.00',
        reason: '🚨the comma the user no longer types is put back here',
      );
    });
  });
}
