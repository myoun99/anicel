import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/ui/timeline/effect_lane_editing.dart';
import 'package:anicel/src/ui/timeline/effect_lane_policy.dart';
import 'package:anicel/src/ui/timeline/property_lane_model.dart';
import 'package:anicel/src/ui/timeline/se_name_tag_lane_policy.dart'
    show seNameTagLaneValueKind, seNameTagNameInkLaneId;

/// F-477 (유저 2026-10-26): 「se행의 이름표fx의 이름 잉크같은것처럼 색
/// 컬러팝오버로 고르는거 그대로 사용하라고. 쓸데없이 빨강파랑초록 나누지말고」
/// — a cel number's colour is ONE colour lane, as an SE name tag's name ink
/// is: its value cell the shared colour swatch, a pick a key at the playhead.
void main() {
  const id = EffectId('n');
  final ink = effectLaneId(id, effectInkLane);
  const red = 0xFFC80A1E;

  LayerEffect number({Map<int, PropertyKey<int>> keys = const {}}) =>
      LayerEffect(
        id: id,
        kind: EffectKind.celNumber,
        ink: PropertyTrack<int>(keys: keys),
      );

  test('🎯the colour is ONE lane, a colour as the name tag\'s ink is — no '
      'Red, Green or Blue', () {
    final rows = effectPropertyLanes(
      [number()],
      isExpanded: (_) => true,
      valueAt: (_, _, _) => 0,
    );
    final lane = rows.singleWhere((row) => row.laneId == ink);

    expect(lane.valueKind, PropertyLaneValueKind.color);
    expect(lane.valueKind, seNameTagLaneValueKind(seNameTagNameInkLaneId));
    expect(lane.colorCanBeNone, isFalse);
    expect(lane.curve, isNull, reason: 'a colour draws no graph line');
    expect(lane.valueLabel!(0), '#000000', reason: 'unkeyed: the text tool\'s');
    for (final channel in ['red', 'green', 'blue']) {
      expect(
        rows.map((row) => row.laneId),
        isNot(contains(effectLaneId(id, channel))),
        reason: channel,
      );
    }
    expect(EffectKind.celNumber.parameters, isEmpty);
  });

  test('a colour picked keys it at the playhead — and the letters are '
      'drawn in it', () {
    final picked = effectsWithLaneValueEdited(
      [number()],
      laneId: ink,
      frameIndex: 3,
      input: formatLaneColorValue(red),
      scaleLinked: false,
    )!;

    expect(picked.single.ink.keys.keys, {3});
    expect(picked.single.ink.keyAt(3)!.value, red);
    expect(
      resolveLayerEffectsAt(effects: picked, frameIndex: 3).single.ink,
      red,
    );
    expect(
      effectsWithLaneValueEdited(
        picked,
        laneId: ink,
        frameIndex: 3,
        input: 'not a colour',
        scaleLinked: false,
      ),
      isNull,
    );
  });

  test('the diamond freezes the colour it shows, and takes it away', () {
    final rested = effectsWithLaneKeyToggled(
      [number()],
      laneId: ink,
      frameIndex: 4,
    )!;
    expect(rested.single.ink.keyAt(4)!.value, effectInkAtRest);

    final frozen = effectsWithLaneKeyToggled(
      [
        number(keys: {0: const PropertyKey(red)}),
      ],
      laneId: ink,
      frameIndex: 4,
    )!;
    expect(frozen.single.ink.keyAt(4)!.value, red);

    final gone = effectsWithLaneKeyToggled(frozen, laneId: ink, frameIndex: 4)!;
    expect(gone.single.ink.keyAt(4), isNull);
  });

  test('the group reset puts a keyed colour back to the rest — and keys no '
      'unkeyed one', () {
    final reset = effectsWithGroupReset(
      [
        number(keys: {2: const PropertyKey(red)}),
      ],
      laneId: effectGroupLaneId(id),
      frameIndexes: [2],
    )!;
    expect(reset.single.ink.keyAt(2)!.value, effectInkAtRest);

    expect(
      effectsWithGroupReset(
        [number()],
        laneId: effectGroupLaneId(id),
        frameIndexes: [2],
      ),
      isNull,
    );
  });

  test('the file keeps it, and a kind that draws no picture holds none', () {
    final keyed = number(keys: {5: const PropertyKey(red)});
    expect(LayerEffect.fromJson(keyed.toJson()), keyed);
    expect(LayerEffect.fromJson(number().toJson()).ink.isEmpty, isTrue);

    final blur = LayerEffect(
      id: id,
      kind: EffectKind.blur,
      ink: PropertyTrack<int>(keys: {0: const PropertyKey(red)}),
    );
    expect(blur.ink.isEmpty, isTrue);
    expect(blur.lanes, isNot(contains(effectInkLane)));
  });

  test('its keys move and are counted through the lens, as every lane\'s', () {
    final lens = effectLaneLens(ink)!;
    final effects = [
      number(keys: {3: const PropertyKey(red)}),
    ];

    expect(lens.keyFrames(effects), {3});
    expect(lens.numberShown(5), isNull, reason: 'a colour, not a number');
    final shifted = lens.update(
      effects,
      <U>(PropertyTrack<U> lane) =>
          PropertyTrack<U>(keys: {7: lane.keyAt(3)!}),
    )!;
    expect(shifted.single.ink.keyAt(7)!.value, red);
    expect(effectLaneKeyFrames(shifted, effectGroupLaneId(id)), {7});
  });

  test('a named colour carries its value to the same name elsewhere', () {
    final before = [
      number(keys: {0: const PropertyKey(0xFF000000, name: 'A')}),
    ];
    final after = [
      number(keys: {0: const PropertyKey(red, name: 'A')}),
    ];
    final changes = namedEffectKeyChanges(before, after);
    expect([for (final change in changes) change.lane], [effectInkLane]);

    final sibling = effectsWithNamedValues([
      number(keys: {9: const PropertyKey(0xFF000000, name: 'A')}),
    ], changes);
    expect(sibling.single.ink.keyAt(9)!.value, red);
  });
}
