import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/services/cel_source_effect_pass.dart';
import 'package:anicel/src/ui/timeline/effect_lane_editing.dart';
import 'package:anicel/src/ui/timeline/effect_lane_policy.dart';
import 'package:anicel/src/ui/timeline/property_lane_model.dart';
import 'package:anicel/src/ui/timeline/se_name_tag_lane_policy.dart'
    show seNameTagLaneValueKind, seNameTagNameInkLaneId;

/// F-477 (유저 2026-10-26): 「se행의 이름표fx의 이름 잉크같은것처럼 색
/// 컬러팝오버로 고르는거 그대로 사용하라고. 쓸데없이 빨강파랑초록 나누지말고」
/// — a cel number's colour — and I-132-Q10 (유저 2026-10-27): 「합친다 — 키
/// 색상 = 색 레인 하나(셀 번호 · 이름표 잉크와 같은 컬러 팝오버)」 — a colour
/// key's. Both are ONE colour parameter ([EffectParameterUnit.color]), as an
/// SE name tag's name ink is: its value cell the shared colour swatch, a pick
/// a key at the playhead — and every verb a lane takes the same for the two.
void main() {
  const id = EffectId('n');
  const red = 0xFFC80A1E;
  const black = 0xFF000000;

  for (final (kind, parameter) in [
    (EffectKind.celNumber, 'ink'),
    (EffectKind.colorKey, 'keyColor'),
  ]) {
    group('${kind.label}: $parameter', () {
      final lane = effectLaneId(id, parameter);

      LayerEffect effect({
        Map<int, PropertyKey<int>> keys = const {},
        bool changesPixels = false,
      }) => LayerEffect(
        id: id,
        kind: kind,
        colors: {parameter: PropertyTrack<int>(keys: keys)},
        // One the chain holds: a key of no amount changes no pixel, and the
        // resolver drops it (EffectKind.strength).
        parameters: {
          if (kind.strength case final strength? when changesPixels)
            strength: EffectParameter(value: 100),
        },
      );

      PropertyKey<int> key(int argb, {String? name}) =>
          PropertyKey(argb, name: name);

      int? keyedAt(List<LayerEffect> effects, int frame) =>
          effects.single.colors[parameter]!.keyAt(frame)?.value;

      test('🎯the colour is ONE lane, a colour as the name tag\'s ink is — '
          'no Red, Green or Blue', () {
        final effects = [effect()];
        final rows = effectPropertyLanes(
          effects,
          isExpanded: (_) => true,
          valueAt: (effectId, parameterId, time) =>
              effectParameterValueAtTime(effects, effectId, parameterId, time),
        );
        final row = rows.singleWhere((row) => row.laneId == lane);

        expect(row.valueKind, PropertyLaneValueKind.color);
        expect(row.valueKind, seNameTagLaneValueKind(seNameTagNameInkLaneId));
        expect(row.colorCanBeNone, isFalse);
        expect(row.curve, isNull, reason: 'a colour draws no graph line');
        expect(row.scrubValue, isNull, reason: 'nor scrubs as a number');
        expect(row.valueLabel!(0), '#000000', reason: 'unkeyed: black');
        for (final channel in [
          'red',
          'green',
          'blue',
          'keyRed',
          'keyGreen',
          'keyBlue',
        ]) {
          expect(
            rows.map((row) => row.laneId),
            isNot(contains(effectLaneId(id, channel))),
            reason: channel,
          );
        }
      });

      test('a colour picked keys it at the playhead, and the chain reads it '
          'there', () {
        final picked = effectsWithLaneValueEdited(
          [effect(changesPixels: true)],
          laneId: lane,
          frameIndex: 3,
          input: formatLaneColorValue(red),
          scaleLinked: false,
        )!;

        expect(picked.single.colors[parameter]!.keys.keys, {3});
        expect(keyedAt(picked, 3), red);
        expect(
          resolveLayerEffectsAt(
            effects: picked,
            frameIndex: 3,
          ).single.color(parameter),
          red,
        );
        expect(
          effectsWithLaneValueEdited(
            picked,
            laneId: lane,
            frameIndex: 3,
            input: 'not a colour',
            scaleLinked: false,
          ),
          isNull,
        );
      });

      test('between two keys it walks channel by channel, not as a number',
          () {
        final effects = [
          effect(
            keys: {0: key(black), 10: key(0xFFFFFFFF)},
            changesPixels: true,
          ),
        ];
        final halfway = resolveLayerEffectsAt(
          effects: effects,
          frameIndex: 5,
        ).single.color(parameter);
        // A number's walk from 0xFF000000 to 0xFFFFFFFF passes 0xFF7FFFFF.
        expect(halfway, 0xFF808080);
        expect(
          effectParameterValueAtTime(effects, id, parameter, 5).toInt(),
          halfway,
          reason: 'the lane reads the walk the chain does',
        );
      });

      test('the diamond freezes the colour it shows, and takes it away', () {
        final rested = effectsWithLaneKeyToggled(
          [effect()],
          laneId: lane,
          frameIndex: 4,
        )!;
        expect(keyedAt(rested, 4), black);

        final frozen = effectsWithLaneKeyToggled(
          [
            effect(keys: {0: key(red)}),
          ],
          laneId: lane,
          frameIndex: 4,
        )!;
        expect(keyedAt(frozen, 4), red);

        final gone = effectsWithLaneKeyToggled(
          frozen,
          laneId: lane,
          frameIndex: 4,
        )!;
        expect(keyedAt(gone, 4), isNull);
      });

      test('the group reset puts a keyed colour back to the rest — and keys '
          'no unkeyed one', () {
        final reset = effectsWithGroupReset(
          [
            effect(keys: {2: key(red)}),
          ],
          laneId: effectGroupLaneId(id),
          frameIndexes: [2],
        )!;
        expect(keyedAt(reset, 2), black);

        expect(
          effectsWithGroupReset(
            [effect()],
            laneId: effectGroupLaneId(id),
            frameIndexes: [2],
          ),
          isNull,
        );
      });

      test('the file keeps it, and a kind without it holds none', () {
        final keyed = effect(keys: {5: key(red)});
        expect(LayerEffect.fromJson(keyed.toJson()), keyed);
        expect(
          effect().toJson().containsKey('colors'),
          isFalse,
          reason: 'unkeyed it says nothing',
        );
        expect(
          effect(keys: {5: key(red)}).parameters,
          isNot(contains(parameter)),
          reason: 'its keys are a colour\'s, not a number\'s',
        );

        final blur = LayerEffect(
          id: id,
          kind: EffectKind.blur,
          colors: {
            parameter: PropertyTrack<int>(keys: {0: key(red)}),
          },
        );
        expect(blur.colors, isEmpty);
        expect(blur.lanes, isNot(contains(parameter)));
      });

      test('its keys move and are counted through the lens, as every '
          'lane\'s — and take no number', () {
        final lens = effectLaneLens(lane)!;
        final effects = [
          effect(keys: {3: key(red)}),
        ];

        expect(lens.keyFrames(effects), {3});
        expect(lens.numberShown(5), isNull, reason: 'a colour, not a number');
        expect(lens.numberHeld(effects, 5), isNull);
        final shifted = lens.update(
          effects,
          <U>(PropertyTrack<U> lane) =>
              PropertyTrack<U>(keys: {7: lane.keyAt(3)!}),
        )!;
        expect(keyedAt(shifted, 7), red);
        expect(effectLaneKeyFrames(shifted, effectGroupLaneId(id)), {7});
      });

      test('a named colour carries its value to the same name elsewhere', () {
        final before = [
          effect(keys: {0: key(black, name: 'A')}),
        ];
        final after = [
          effect(keys: {0: key(red, name: 'A')}),
        ];
        final changes = namedEffectKeyChanges(before, after);
        expect([for (final change in changes) change.lane], [parameter]);

        final sibling = effectsWithNamedValues([
          effect(keys: {9: key(black, name: 'A')}),
        ], changes);
        expect(keyedAt(sibling, 9), red);
      });
    });
  }

  test('a number lane still takes a number', () {
    final lens = effectLaneLens(effectLaneId(id, 'tolerance'))!;
    final effects = [LayerEffect(id: id, kind: EffectKind.colorKey)];
    expect(lens.numberShown(5), 5);
    expect(lens.numberHeld(effects, 500), 255, reason: 'clamped to its range');
  });

  test('the key colour is the colour the key compares', () {
    final key = CelColorKey.fromResolved(
      ResolvedLayerEffect(
        kind: EffectKind.colorKey,
        values: [
          for (final spec in EffectKind.colorKey.parameters)
            switch (spec.id) {
              'keyColor' => red.toDouble(),
              'amount' => 100,
              _ => spec.defaultValue,
            },
        ],
      ),
    )!;
    expect((key.red, key.green, key.blue), (0xC8, 0x0A, 0x1E));
  });
}
