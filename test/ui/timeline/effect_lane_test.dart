import 'dart:ui' show Offset;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/timeline_frame_range.dart'
    show TimelineLaneSelection;
import 'package:anicel/src/ui/timeline/effect_lane_editing.dart';
import 'package:anicel/src/ui/timeline/effect_lane_policy.dart';
import 'package:anicel/src/ui/timeline/property_lane_model.dart';
import 'package:anicel/src/ui/timeline/transform_lane_policy.dart';

/// The effect lanes' side of the shared lane substrate (R6): the addresses,
/// the rows, and the pure key edits the host commits as one undo.
void main() {
  LayerEffect blur({double x = 0, double y = 0, String id = 'e1'}) =>
      LayerEffect(
        id: EffectId(id),
        kind: EffectKind.blur,
        parameters: {
          'blurX': EffectParameter(value: x),
          'blurY': EffectParameter(value: y),
        },
      );

  LayerEffect hue({String id = 'e2'}) =>
      LayerEffect.defaults(id: EffectId(id), kind: EffectKind.hueSaturation);

  group('lane addresses', () {
    test('round-trip, and never collide with the transform lane ids', () {
      const effectId = EffectId('e1');
      final laneId = effectLaneId(effectId, 'blurX');
      final address = parseEffectLaneId(laneId);
      expect(address!.effectId, effectId);
      expect(address.parameterId, 'blurX');

      final header = parseEffectLaneId(effectGroupLaneId(effectId));
      expect(header!.effectId, effectId);
      expect(header.parameterId, isNull);

      for (final transformLane in transformLaneDisplayOrder) {
        expect(parseEffectLaneId(transformLane), isNull, reason: transformLane);
      }
      expect(parseEffectLaneId(transformGroupHeaderLane.laneId), isNull);
      expect(parseEffectLaneId('se-audio'), isNull);
    });

    test('malformed addresses answer null instead of a wrong effect', () {
      expect(parseEffectLaneId('fx:'), isNull);
      expect(parseEffectLaneId('fx:only-an-id'), isNull);
      expect(parseEffectLaneId('fx:e1:'), isNull);
      expect(parseEffectLaneId('fx-group:'), isNull);
    });
  });

  group('lane rows', () {
    test('a collapsed effect shows its header alone, with the key union', () {
      final animated = LayerEffect(
        id: const EffectId('e1'),
        kind: EffectKind.blur,
        parameters: {
          'blurX': EffectParameter(
            track: PropertyTrack<double>(
              keys: {3: const PropertyKey<double>(4)},
            ),
          ),
          'blurY': EffectParameter(
            track: PropertyTrack<double>(
              keys: {7: const PropertyKey<double>(2)},
            ),
          ),
        },
      );
      final rows = effectPropertyLanes([animated], isExpanded: (_) => false);
      expect(rows, hasLength(1));
      expect(rows.single.isGroupHeader, isTrue);
      expect(rows.single.groupExpanded, isFalse);
      expect(rows.single.keyedFrames, {3, 7});
      expect(rows.single.showsKeyNavigator, isFalse);
    });

    test('an expanded effect adds one lane per parameter, in spec order', () {
      final rows = effectPropertyLanes([hue()], isExpanded: (_) => true);
      expect(rows.map((row) => row.label), [
        'Hue/Saturation',
        'Hue',
        'Saturation',
        'Lightness',
      ]);
      expect(rows.skip(1).every((row) => row.showsKeyNavigator), isTrue);
    });

    test('two effects of the SAME kind keep separate lanes', () {
      final rows = effectPropertyLanes([
        blur(id: 'a'),
        blur(id: 'b'),
      ], isExpanded: (_) => true);
      final ids = rows.map((row) => row.laneId).toSet();
      expect(ids, hasLength(rows.length), reason: 'no address collision');
    });

    test('a disabled effect says so in its header label', () {
      final rows = effectPropertyLanes([
        blur().copyWith(enabled: false),
      ], isExpanded: (_) => false);
      expect(rows.single.label, contains('off'));
    });

    test('the value column formats per unit and parses back', () {
      final rows = effectPropertyLanes(
        [blur(x: 8)],
        isExpanded: (_) => true,
        valueAt: (effectId, parameterId, frameIndex) =>
            parameterId == 'blurX' ? 8 : 0,
      );
      final lane = rows.firstWhere((row) => row.label == 'Blur Width');
      expect(lane.valueLabel!(0), '8 px');
      final spec = effectParametersOf(EffectKind.blur).first;
      expect(parseEffectLaneValue(spec, '8 px'), 8);
      expect(parseEffectLaneValue(spec, '12'), 12);
      expect(parseEffectLaneValue(spec, 'wide'), isNull);
      expect(
        parseEffectLaneValue(spec, '-5'),
        0,
        reason: 'clamped to the spec',
      );
    });

    test('scrubbing moves the value in the form the editor parses', () {
      final spec = effectParametersOf(EffectKind.hueSaturation).first;
      expect(scrubEffectLaneValue(spec, '10°', const Offset(20, 0)), '20°');
      expect(scrubEffectLaneValue(spec, '10°', const Offset(-100, 0)), '-40°');
      // Clamped at the spec edge, never past it.
      expect(scrubEffectLaneValue(spec, '170°', const Offset(200, 0)), '180°');
    });
  });

  group('the lane span (R26 #3)', () {
    test('a HEADER endpoint selects the whole effect', () {
      final effects = [hue()];
      expect(
        effectLaneSpan(effects, effectGroupLaneId(const EffectId('e2')), 'x'),
        effectLaneDisplayOrder(effects.single),
      );
    });

    test('two parameter lanes select the range between them', () {
      final effects = [hue()];
      final span = effectLaneSpan(
        effects,
        effectLaneId(const EffectId('e2'), 'hue'),
        effectLaneId(const EffectId('e2'), 'saturation'),
      );
      expect(span, [
        effectLaneId(const EffectId('e2'), 'hue'),
        effectLaneId(const EffectId('e2'), 'saturation'),
      ]);
    });

    test('endpoints in DIFFERENT effects collapse to the anchor alone', () {
      final effects = [blur(id: 'a'), blur(id: 'b')];
      expect(
        effectLaneSpan(
          effects,
          effectLaneId(const EffectId('a'), 'blurX'),
          effectLaneId(const EffectId('b'), 'blurX'),
        ),
        [effectLaneId(const EffectId('a'), 'blurX')],
      );
    });

    test('a transform lane pair answers null so the caller falls through', () {
      expect(effectLaneSpan([blur()], 'position', 'scale'), isNull);
    });

    test('the header washes when its own members are the selection', () {
      const layerId = LayerId('l');
      final header = effectGroupLaneId(const EffectId('e2'));
      final members = effectLaneDisplayOrder(hue());
      expect(effectGroupHeaderCovered(header, members), isTrue);
      expect(
        effectGroupHeaderCovered(header, [members.first]),
        isFalse,
        reason: 'one lane is not the group',
      );
      expect(
        effectGroupHeaderCovered(header, transformLaneDisplayOrder),
        isFalse,
      );
      // …and the shared predicate routes an effect header here.
      expect(
        laneSelectionCoversBandRow(
          TimelineLaneSelection(
            layerId: layerId,
            laneId: members.first,
            startIndex: 0,
            endIndexExclusive: 2,
            laneIds: members,
          ),
          layerId,
          header,
        ),
        isTrue,
      );
    });
  });

  group('key edits', () {
    test(
      'the diamond toggles a key at the RESOLVED value, then removes it',
      () {
        final effects = [blur(x: 6)];
        final keyed = effectsWithLaneKeyToggled(
          effects,
          laneId: effectLaneId(const EffectId('e1'), 'blurX'),
          frameIndex: 4,
        )!;
        expect(keyed.single.parameterOf('blurX').track.keyAt(4)!.value, 6);
        final unkeyed = effectsWithLaneKeyToggled(
          keyed,
          laneId: effectLaneId(const EffectId('e1'), 'blurX'),
          frameIndex: 4,
        )!;
        expect(unkeyed.single.parameterOf('blurX').track.isEmpty, isTrue);
      },
    );

    test('a value edit sets the STATIC value while unanimated', () {
      final edited = effectsWithLaneValueEdited(
        [blur()],
        laneId: effectLaneId(const EffectId('e1'), 'blurX'),
        frameIndex: 7,
        input: '9',
      )!;
      expect(edited.single.parameterOf('blurX').value, 9);
      expect(
        edited.single.parameterOf('blurX').isAnimated,
        isFalse,
        reason: '"add a blur and set it to 9" must not plant a keyframe',
      );
    });

    test('a value edit KEYS at the playhead once animated (AE rule)', () {
      final animated = effectsWithLaneKeyToggled(
        [blur(x: 6)],
        laneId: effectLaneId(const EffectId('e1'), 'blurX'),
        frameIndex: 0,
      )!;
      final edited = effectsWithLaneValueEdited(
        animated,
        laneId: effectLaneId(const EffectId('e1'), 'blurX'),
        frameIndex: 5,
        input: '9',
      )!;
      expect(edited.single.parameterOf('blurX').track.keyAt(5)!.value, 9);
    });

    test('move, remove and hold behave like the transform lanes', () {
      final laneId = effectLaneId(const EffectId('e1'), 'blurX');
      var effects = effectsWithLaneKeyToggled(
        [blur(x: 6)],
        laneId: laneId,
        frameIndex: 2,
      )!;
      effects = effectsWithLaneKeyMoved(
        effects,
        laneId: laneId,
        fromFrame: 2,
        toFrame: 9,
      )!;
      final track = effects.single.parameterOf('blurX').track;
      expect(track.keyAt(2), isNull);
      expect(track.keyAt(9)!.value, 6);

      effects = effectsWithLaneHoldToggled(
        effects,
        laneId: laneId,
        frameIndex: 9,
      )!;
      expect(
        effects.single.parameterOf('blurX').track.keyAt(9)!.interpolation,
        PropertyKeyInterpolation.hold,
      );

      effects = effectsWithLaneKeyRemoved(
        effects,
        laneId: laneId,
        frameIndex: 9,
      )!;
      expect(effects.single.parameterOf('blurX').track.isEmpty, isTrue);
    });

    test('every edit answers null on a lane it does not own', () {
      final effects = [blur(x: 6)];
      const foreign = 'position';
      expect(
        effectsWithLaneKeyToggled(effects, laneId: foreign, frameIndex: 0),
        isNull,
      );
      expect(
        effectsWithLaneValueEdited(
          effects,
          laneId: foreign,
          frameIndex: 0,
          input: '3',
        ),
        isNull,
      );
      expect(
        effectsWithLaneKeyToggled(
          effects,
          laneId: effectLaneId(const EffectId('gone'), 'blurX'),
          frameIndex: 0,
        ),
        isNull,
        reason: 'a stale address must not edit the wrong effect',
      );
      expect(
        effectsWithLaneKeyToggled(
          effects,
          laneId: effectLaneId(const EffectId('e1'), 'hue'),
          frameIndex: 0,
        ),
        isNull,
        reason: 'a parameter from another kind is not this effect\'s',
      );
    });

    test('an edit leaves the OTHER effects identical', () {
      final effects = [blur(x: 6, id: 'a'), hue(id: 'b')];
      final edited = effectsWithLaneValueEdited(
        effects,
        laneId: effectLaneId(const EffectId('a'), 'blurX'),
        frameIndex: 0,
        input: '3',
      )!;
      expect(edited[1], same(effects[1]));
    });
  });

  group('the range move', () {
    String laneOf(String parameter) =>
        effectLaneId(const EffectId('e1'), parameter);

    List<LayerEffect> withKeys(Map<String, Map<int, double>> lanes) {
      var effects = [blur()];
      for (final lane in lanes.entries) {
        for (final key in lane.value.entries) {
          effects = effectsWithLaneValueEdited(
            effectsWithLaneKeyToggled(
              effects,
              laneId: laneOf(lane.key),
              frameIndex: key.key,
            )!,
            laneId: laneOf(lane.key),
            frameIndex: key.key,
            input: '${key.value}',
          )!;
        }
      }
      return effects;
    }

    test('shifts every ranged key of every spanned lane by one delta', () {
      final effects = withKeys({
        'blurX': {2: 4, 3: 6},
        'blurY': {2: 1},
      });
      final moved = effectsWithLaneSpanKeysShifted(
        effects,
        laneIds: [laneOf('blurX'), laneOf('blurY')],
        rangeStartIndex: 2,
        rangeEndIndexExclusive: 4,
        frameDelta: 5,
      )!;
      expect(moved.single.parameterOf('blurX').track.keys.keys, [7, 8]);
      expect(moved.single.parameterOf('blurY').track.keys.keys, [7]);
    });

    test('a blocked landing vetoes the WHOLE move (all-or-nothing)', () {
      final effects = withKeys({
        'blurX': {2: 4, 6: 9},
        'blurY': {2: 1},
      });
      expect(
        effectsWithLaneSpanKeysShifted(
          effects,
          laneIds: [laneOf('blurX'), laneOf('blurY')],
          rangeStartIndex: 2,
          rangeEndIndexExclusive: 3,
          frameDelta: 4,
        ),
        isNull,
        reason: 'blurX would land on its own unshifted key at 6',
      );
      expect(
        effectsWithLaneSpanKeysShifted(
          effects,
          laneIds: [laneOf('blurX')],
          rangeStartIndex: 2,
          rangeEndIndexExclusive: 3,
          frameDelta: -5,
        ),
        isNull,
        reason: 'a landing below frame 0 is blocked too',
      );
    });

    test('a lane with no ranged key rides along without blocking', () {
      final effects = withKeys({
        'blurX': {2: 4},
      });
      final moved = effectsWithLaneSpanKeysShifted(
        effects,
        laneIds: [laneOf('blurX'), laneOf('blurY')],
        rangeStartIndex: 2,
        rangeEndIndexExclusive: 3,
        frameDelta: 1,
      )!;
      expect(moved.single.parameterOf('blurX').track.keys.keys, [3]);
    });

    test('the navigator reads a lane\'s keys, and a header its union', () {
      final effects = withKeys({
        'blurX': {2: 4},
        'blurY': {8: 1},
      });
      expect(effectLaneKeyFrames(effects, laneOf('blurX')), {2});
      expect(
        effectLaneKeyFrames(effects, effectGroupLaneId(const EffectId('e1'))),
        {2, 8},
      );
      expect(effectLaneKeyFrames(effects, 'position'), isEmpty);
    });
  });

  group('chain edits', () {
    test('add appends, remove drops, and both answer null on a miss', () {
      final one = effectsWithAdded(const [], blur(id: 'a'));
      expect(one, hasLength(1));
      final two = effectsWithAdded(one, hue(id: 'b'));
      expect(two.map((effect) => effect.id.value), ['a', 'b']);
      expect(
        effectsWithRemoved(two, const EffectId('a'))!.single.id.value,
        'b',
      );
      expect(effectsWithRemoved(two, const EffectId('zz')), isNull);
      expect(
        effectsWithEnabledToggled(two, const EffectId('b'))!.last.enabled,
        isFalse,
      );
      expect(effectsWithEnabledToggled(two, const EffectId('zz')), isNull);
    });
  });

  group('the group key', () {
    test('names the row AND the group, so two groups stay independent', () {
      const layerId = LayerId('l1');
      expect(
        laneGroupKey(layerId, transformGroupHeaderLane.laneId),
        isNot(laneGroupKey(layerId, effectGroupLaneId(const EffectId('e1')))),
      );
      expect(
        laneGroupKey(const LayerId('a'), 'transform-group'),
        isNot(laneGroupKey(const LayerId('b'), 'transform-group')),
      );
    });
  });
}
