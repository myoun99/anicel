import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/timeline/effect_lane_editing.dart';
import 'package:anicel/src/ui/timeline/effect_lane_policy.dart';
import 'package:anicel/src/ui/timeline/property_lane_model.dart';

/// 🗣️I-132-Q16 a (유저 2026-10-28): 「「레이어」는 같은 컷의 행을 고르는
/// 메뉴(없음 + 행 이름들, 키 없음)」 — a camera lens blur's Blur Map Layer
/// names one row of its cut, or none: no number and no keys, one row at
/// every frame. A row that is not the cut's reads as none, as a dangling
/// attach does.
void main() {
  const map = 'blurMapLayer';
  final lens = LayerEffect.defaults(
    id: const EffectId('lens'),
    kind: EffectKind.cameraLensBlur,
  );
  final laneId = effectLaneId(lens.id, map);

  Layer row(String id, String name) =>
      Layer(id: LayerId(id), name: name, frames: const []);

  group('the effect', () {
    test('its blur map\'s lanes stand after the fringe, in the help\'s '
        'order: the layer, its channel, the focal distance, the inversion', () {
      final ids = [
        for (final spec in EffectKind.cameraLensBlur.parameters) spec.id,
      ];
      final fringe = ids.indexOf('irisDiffractionFringe');
      expect(ids.sublist(fringe + 1, fringe + 5), [
        map,
        'blurMapChannel',
        'blurFocalDistance',
        'invertBlurMap',
      ]);
      const kind = EffectKind.cameraLensBlur;
      expect(kind.parameterSpec(map)!.unit, EffectParameterUnit.layer);
      final channel = kind.parameterSpec('blurMapChannel')!;
      expect(
        [for (final word in channel.choices) word.id],
        ['luminance', 'red', 'green', 'blue', 'alpha'],
      );
      final focal = kind.parameterSpec('blurFocalDistance')!;
      expect((focal.minimum, focal.maximum, focal.defaultValue), (0, 255, 0));
      expect(
        kind.parameterSpec('invertBlurMap')!.unit,
        EffectParameterUnit.flag,
      );
    });

    test('names none to begin, says nothing of it in its file, and keeps a '
        'row it names through its file', () {
      expect(lens.layers, {map: null});
      expect(lens.parameters.containsKey(map), isFalse, reason: 'no number');
      expect(lens.toJson().containsKey('layers'), isFalse);
      expect(LayerEffect.fromJson(lens.toJson()), lens);

      final named = lens.withLayer(map, const LayerId('map'));
      expect(named.layers, {map: const LayerId('map')});
      expect(named, isNot(lens));
      expect(named.withLayer(map, null), lens);
      expect(LayerEffect.fromJson(named.toJson()), named);
    });

    test('a kind that declares no row holds none, whatever it is handed', () {
      final blur = LayerEffect(
        id: const EffectId('blur'),
        kind: EffectKind.blur,
        layers: {map: const LayerId('map')},
      );
      expect(blur.layers, isEmpty);
    });

    test('keeps no keys, and samples as the row it names at every frame', () {
      final named = lens
          .withParameter('blurRadius', EffectParameter(value: 20))
          .withLayer(map, const LayerId('map'));
      expect(named.laneTrack(map)!.isEmpty, isTrue);
      for (final frame in [0, 7]) {
        final sample = resolveLayerEffectsAt(
          effects: [named],
          frameIndex: frame,
        ).single;
        expect(sample.layers, {map: const LayerId('map')});
        expect(sample.parameter(map), 0, reason: 'no number');
        expect(
          sample,
          isNot(
            ResolvedLayerEffect(
              kind: sample.kind,
              values: sample.values,
              layers: {map: const LayerId('other')},
            ),
          ),
          reason: 'another row is another sample',
        );
      }
    });
  });

  group('its lane', () {
    PropertyLaneRow laneOf(List<LayerEffect> effects, List<Layer> rows) =>
        effectPropertyLanes(
          effects,
          cutRows: rows,
          isExpanded: (_) => true,
        ).firstWhere((lane) => lane.laneId == laneId);

    final none = AppText.strings.commonNone;
    final rows = [row('a', 'Same'), row('b', 'Same')];

    test('is a menu of none and the cut\'s rows by name, which writes the '
        'row\'s id — two rows of one name are two words', () {
      final lane = laneOf([lens.withLayer(map, const LayerId('b'))], rows);
      expect(lane.valueKind, PropertyLaneValueKind.choice);
      expect(lane.choices, [none, 'Same', 'Same']);
      expect(lane.choiceValues, ['', 'a', 'b']);
      expect(lane.choiceHeld, 'b');
      expect(lane.valueLabel!(0), 'Same');
    });

    test('has no keys to show or walk to, and nothing to scrub or draw', () {
      final lane = laneOf([lens], rows);
      expect(lane.keyMarks, isEmpty);
      expect(lane.showsKeyNavigator, isFalse);
      expect(lane.scrubValue, isNull);
      expect(lane.curve, isNull);
      expect(lane.choiceHeld, '');
      expect(lane.valueLabel!(0), none);
    });

    test('reads a row that is not the cut\'s — deleted — as none, and a '
        'track\'s chain, which is no cut\'s, names none', () {
      final gone = laneOf([lens.withLayer(map, const LayerId('gone'))], rows);
      expect(gone.choiceHeld, '');
      expect(gone.valueLabel!(0), none);
      expect(
        laneOf([lens.withLayer(map, const LayerId('a'))], const []).choices,
        [none],
      );
    });
  });

  group('an edit of it', () {
    List<LayerEffect>? picked(List<LayerEffect> effects, String input) =>
        effectsWithLaneValueEdited(
          effects,
          laneId: laneId,
          frameIndex: 5,
          input: input,
          scaleLinked: false,
        );

    test('names the row picked, and none unnames it — keying nothing', () {
      final named = picked([lens], 'b')!;
      expect(named.single.layers, {map: const LayerId('b')});
      expect(named.single.parameters, lens.parameters, reason: 'no key');
      expect(picked(named, '')!.single.layers, {map: null});
      expect(picked(named, 'b'), isNull, reason: 'the same row changes none');
    });

    test('keys nothing where a key is written: no edit of keys reaches it', () {
      final named = picked([lens], 'b')!;
      expect(
        effectsWithLaneKeysWritten(named, laneId: laneId, frames: {3}),
        isNull,
      );
      // An edit that writes the lane back as it is says it wrote something
      // on any lane it reaches — a number's.
      final keysOf = effectLaneLens(laneId)!;
      expect(keysOf.update(named, <U>(keys) => keys), isNull);
      expect(
        effectLaneLens(effectLaneId(named.single.id, 'blurRadius'))!.update(
          named,
          <U>(keys) => keys,
        ),
        isNotNull,
        reason: 'fixture: a number\'s lane is reached',
      );
    });

    test('a group reset takes it back to none, as it takes an unkeyed '
        'number back to its first value', () {
      final named = picked([lens], 'b')!;
      for (final keyedFramesOnly in [false, true]) {
        final reset = effectsWithGroupReset(
          named,
          laneId: effectGroupLaneId(lens.id),
          frameIndexes: const [0],
          keyedFramesOnly: keyedFramesOnly,
        )!;
        expect(reset.single.layers, {map: null});
      }
    });
  });
}
