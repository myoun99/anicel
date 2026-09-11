import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/transform_track.dart';

/// Named keys: "same name, same value", the frame-name rule said of
/// keyframes. The naming space is ONE parameter of ONE effect, and linked
/// rows share effect ids — which is how a value crosses 겸용 cuts now that
/// their chains mirror only their shape.
void main() {
  final radiusId = effectParametersOf(EffectKind.blur).first.id;

  PropertyTrack<double> track(Map<int, (double, String?)> spec) =>
      PropertyTrack<double>(
        keys: {
          for (final entry in spec.entries)
            entry.key: PropertyKey(entry.value.$1, name: entry.value.$2),
        },
      );

  LayerEffect blur(String id, PropertyTrack<double> radius) => LayerEffect(
    id: EffectId(id),
    kind: EffectKind.blur,
    parameters: {radiusId: EffectParameter(track: radius)},
  );

  group('PropertyTrack', () {
    test('withNamedKey moves every key of that name — number AND type', () {
      final result = track({
        0: (1, 'A'),
        5: (2, null),
        10: (3, 'A'),
      }).withNamedKey('A', (
        value: 9,
        interpolation: PropertyKeyInterpolation.hold,
      ));

      expect(result.keyAt(0)!.value, 9);
      expect(result.keyAt(0)!.interpolation, PropertyKeyInterpolation.hold);
      expect(result.keyAt(10)!.value, 9);
      expect(result.keyAt(10)!.interpolation, PropertyKeyInterpolation.hold);
      expect(result.keyAt(5)!.value, 2, reason: 'unnamed keys are untouched');
      expect(
        result.keyAt(5)!.interpolation,
        PropertyKeyInterpolation.linear,
        reason: 'and so is their type',
      );
    });

    test('a value edit keeps the key TYPE, the way it keeps the name — the '
        'canvas write that turned a hold linear (유저 2026-09-12)', () {
      final held = track({
        4: (1, 'A'),
      }).withKeysInterpolated(frames: {4}, interpolation: PropertyKeyInterpolation.hold)!;

      final moved = held.withKey(4, 9);

      expect(moved.keyAt(4)!.value, 9);
      expect(moved.keyAt(4)!.interpolation, PropertyKeyInterpolation.hold);
      expect(moved.keyAt(4)!.name, 'A');
    });

    test('a TYPE-only change is a change the link carries', () {
      final before = track({4: (1, 'A')});
      final after = before.withKeysInterpolated(
        frames: {4},
        interpolation: PropertyKeyInterpolation.hold,
      )!;

      expect(movedNamedKeys(before, after), {
        'A': (value: 1, interpolation: PropertyKeyInterpolation.hold),
      });
    });

    test('a key that ARRIVES named carries NOTHING — not even its type', () {
      final before = track({4: (1, null)});
      final after = track({
        4: (1, 'A'),
      }).withKeysInterpolated(frames: {4}, interpolation: PropertyKeyInterpolation.hold)!;

      expect(
        movedNamedKeys(before, after),
        isEmpty,
        reason: 'joining ADOPTS what the name holds; it never imposes',
      );
    });

    test('a name SURVIVES a value edit — it is identity, not content', () {
      final result = track({4: (1, 'A')}).withKey(4, 7);

      expect(result.keyAt(4)!.value, 7);
      expect(result.keyAt(4)!.name, 'A');
    });

    test('withKeyName sets and clears; a missing key is a no-op', () {
      final named = track({2: (1, null)}).withKeyName(2, 'B');
      expect(named.keyAt(2)!.name, 'B');
      expect(named.withKeyName(2, null).keyAt(2)!.name, isNull);

      final absent = track({2: (1, null)});
      expect(absent.withKeyName(9, 'B'), absent);
    });

    test('names round-trip through JSON', () {
      final restored = PropertyTrack.fromJson<double>(
        track({0: (1, 'A'), 3: (2, null)}).toJson((value) => value),
        (value) => (value! as num).toDouble(),
      );

      expect(restored.keyAt(0)!.name, 'A');
      expect(restored.keyAt(3)!.name, isNull);
    });
  });

  group('effect chains', () {
    test('a moved named key is reported as a change', () {
      final before = [blur('e1', track({0: (1, 'A')}))];
      final after = [blur('e1', track({0: (5, 'A')}))];

      final changes = namedEffectKeyChanges(before, after);

      expect(changes, hasLength(1));
      expect(changes.single.name, 'A');
      expect(changes.single.value, 5);
      expect(changes.single.parameterId, radiusId);
    });

    test('a RENAME carries NOTHING — joining pulls, it never pushes', () {
      final before = [blur('e1', track({0: (1, null)}))];
      final after = [blur('e1', track({0: (1, 'A')}))];

      expect(
        namedEffectKeyChanges(before, after),
        isEmpty,
        reason:
            'joining a name adopts the value that name already holds, so '
            'the rename verb pulls it before it commits — the frame-link '
            'rule (user 2026-08-10). Only a value that MOVED propagates.',
      );
    });

    test('a key that ARRIVES already named carries nothing either', () {
      final before = [blur('e1', track({}))];
      final after = [blur('e1', track({0: (7, 'A')}))];

      expect(namedEffectKeyChanges(before, after), isEmpty);
    });

    test('keyForName reads the KEY a name already holds', () {
      final subject = track({0: (1, null), 4: (6, 'A')});

      expect(subject.keyForName('A')!.value, 6);
      expect(subject.keyForName('B'), isNull);
    });

    test('namedEffectKey reads it through the chain, per parameter', () {
      final effects = [blur('e1', track({4: (6, 'A')}))];

      expect(
        namedEffectKey(
          effects,
          effectId: const EffectId('e1'),
          parameterId: radiusId,
          name: 'A',
        )!.value,
        6,
      );
      expect(
        namedEffectKey(
          effects,
          effectId: const EffectId('e2'),
          parameterId: radiusId,
          name: 'A',
        ),
        isNull,
        reason: 'another effect is another naming space',
      );
    });

    test('an unnamed edit reports nothing', () {
      final before = [blur('e1', track({0: (1, null)}))];
      final after = [blur('e1', track({0: (5, null)}))];

      expect(namedEffectKeyChanges(before, after), isEmpty);
    });

    test('applying a change moves the sibling\'s key of that name', () {
      final sibling = [
        blur('e1', track({0: (1, 'A'), 4: (2, 'B'), 8: (3, null)})),
      ];

      final result = effectsWithNamedValues(sibling, [
        NamedEffectKeyChange(
          effectId: const EffectId('e1'),
          parameterId: radiusId,
          name: 'A',
          value: 9,
          interpolation: PropertyKeyInterpolation.hold,
        ),
      ]);

      final radius = result.single.parameters[radiusId]!.track;
      expect(radius.keyAt(0)!.value, 9);
      expect(
        radius.keyAt(0)!.interpolation,
        PropertyKeyInterpolation.hold,
        reason: 'the type travels with the number (유저 2026-09-12)',
      );
      expect(radius.keyAt(4)!.value, 2, reason: 'a different name is a '
          'different link');
      expect(radius.keyAt(8)!.value, 3);
    });

    test('a change for an effect the sibling lacks is ignored', () {
      final sibling = [blur('e1', track({0: (1, 'A')}))];

      final result = effectsWithNamedValues(sibling, [
        NamedEffectKeyChange(
          effectId: const EffectId('other'),
          parameterId: radiusId,
          name: 'A',
          value: 9,
          interpolation: PropertyKeyInterpolation.linear,
        ),
      ]);

      expect(result, sibling);
    });

    test('the naming space is per PARAMETER: the same name in another '
        'effect is another link', () {
      final chain = [
        blur('e1', track({0: (1, 'A')})),
        blur('e2', track({0: (2, 'A')})),
      ];

      final result = effectsWithNamedValues(chain, [
        NamedEffectKeyChange(
          effectId: const EffectId('e1'),
          parameterId: radiusId,
          name: 'A',
          value: 9,
          interpolation: PropertyKeyInterpolation.linear,
        ),
      ]);

      expect(result[0].parameters[radiusId]!.track.keyAt(0)!.value, 9);
      expect(result[1].parameters[radiusId]!.track.keyAt(0)!.value, 2);
    });
  });

  // The transform lanes ride the SAME predicate as effect parameters
  // ([movedNamedKeys]) — a transform simply has no effect id to carry its
  // naming space across cuts, so the link group stands in for one.
  group('transform lanes', () {
    TransformTrack lanes({
      PropertyTrack<double>? rotation,
      PropertyTrack<double>? scale,
    }) => TransformTrack.properties(
      anchorPoint: PropertyTrack.empty(),
      position: PropertyTrack.empty(),
      scale: scale ?? PropertyTrack.empty(),
      rotation: rotation ?? PropertyTrack.empty(),
      opacity: PropertyTrack.empty(),
    );

    test('a moved named key is reported per LANE', () {
      final changes = transformNamedKeyChanges(
        lanes(rotation: track({0: (10, 'A')})),
        lanes(rotation: track({0: (45, 'A')})),
      );

      expect(changes.rotation, {
        'A': (value: 45.0, interpolation: PropertyKeyInterpolation.linear),
      });
      expect(changes.position, isEmpty);
    });

    test('a RENAME carries nothing here either', () {
      final changes = transformNamedKeyChanges(
        lanes(rotation: track({0: (10, null)})),
        lanes(rotation: track({0: (10, 'A')})),
      );

      expect(changes.isEmpty, isTrue);
    });

    test('applying a change moves every key of that name in the lane', () {
      final result = transformTrackWithNamedKeys(
        lanes(rotation: track({0: (10, 'A'), 5: (20, null), 9: (30, 'A')})),
        const TransformNamedChanges(
          rotation: {
            'A': (value: 45, interpolation: PropertyKeyInterpolation.hold),
          },
        ),
      );

      expect(result.rotation.keyAt(0)!.value, 45);
      expect(
        result.rotation.keyAt(0)!.interpolation,
        PropertyKeyInterpolation.hold,
        reason: 'the type is part of the link (유저 2026-09-12)',
      );
      expect(result.rotation.keyAt(9)!.value, 45);
      expect(result.rotation.keyAt(5)!.value, 20, reason: 'unnamed is free');
      expect(
        result.rotation.keyAt(5)!.interpolation,
        PropertyKeyInterpolation.linear,
      );
    });

    test('the same name in another LANE is another link', () {
      final result = transformTrackWithNamedKeys(
        lanes(rotation: track({0: (10, 'A')}), scale: track({0: (2, 'A')})),
        const TransformNamedChanges(
          rotation: {
            'A': (value: 45, interpolation: PropertyKeyInterpolation.linear),
          },
        ),
      );

      expect(result.rotation.keyAt(0)!.value, 45);
      expect(
        result.scale.keyAt(0)!.value,
        2,
        reason: 'Rotation A and Scale A are different names by construction',
      );
    });
  });

  // Naming a RANGE: the covered keys collapse onto one value, because a
  // shared name MEANS a shared value (user 2026-08-10).
  group('range naming', () {
    test('the covered keys collapse onto ONE value', () {
      final result = track({
        0: (1, null),
        5: (2, null),
        9: (3, null),
      }).withRangeNamed(frames: {0, 5, 9}, name: 'A');

      expect(result!.keyAt(0)!.value, 1, reason: 'the earliest speaks');
      expect(result.keyAt(5)!.value, 1);
      expect(result.keyAt(9)!.value, 1);
      expect(result.keyNames, {'A'});
    });

    test('the key you are STANDING on outranks the earliest', () {
      final result = track({
        0: (1, null),
        5: (2, null),
      }).withRangeNamed(frames: {0, 5}, name: 'A', preferredFrame: 5);

      expect(result!.keyAt(0)!.value, 2);
      expect(result.keyAt(5)!.value, 2);
    });

    test('an ADOPTED key outranks both — joining takes what is there, type '
        'included', () {
      final result = track({0: (1, null), 5: (2, null)}).withRangeNamed(
        frames: {0, 5},
        name: 'A',
        adopted: const PropertyKey(
          9,
          interpolation: PropertyKeyInterpolation.hold,
        ),
        preferredFrame: 5,
      );

      expect(result!.keyAt(0)!.value, 9);
      expect(result.keyAt(5)!.value, 9);
      expect(
        result.keyAt(5)!.interpolation,
        PropertyKeyInterpolation.hold,
        reason: "the name's TYPE comes with its number (유저 2026-09-12: "
            '「싹다링크해야하는데」)',
      );
    });

    test('un-naming touches no values', () {
      final result = track({
        0: (1, 'A'),
        5: (2, 'A'),
      }).withRangeNamed(frames: {0, 5}, name: null);

      expect(result!.keyAt(0)!.value, 1, reason: 'no shared number left');
      expect(result.keyAt(5)!.value, 2);
      expect(result.keyNames, isEmpty);
    });

    test('frames with no key are skipped; a keyless range is null', () {
      expect(
        track({3: (1, null)}).withRangeNamed(frames: {0, 1}, name: 'A'),
        isNull,
      );

      final result = track({
        3: (1, null),
      }).withRangeNamed(frames: {0, 3}, name: 'A');
      expect(result!.keyNames, {'A'});
      expect(result.keys, hasLength(1));
    });

    test('the collapse lands ONE type as well as one value', () {
      final subject = PropertyTrack<double>(
        keys: {
          0: const PropertyKey(1),
          5: const PropertyKey(
            2,
            interpolation: PropertyKeyInterpolation.hold,
          ),
        },
      );

      final result = subject.withRangeNamed(frames: {0, 5}, name: 'A');

      expect(result!.keyAt(5)!.value, 1, reason: 'the earliest key speaks');
      expect(
        result.keyAt(5)!.interpolation,
        PropertyKeyInterpolation.linear,
        reason:
            "⛔REVERSES 'interpolation survives the collapse' (mine, no user "
            'behind it). 유저 2026-09-12: 「겸용컷끼리 홀드/리니어타입 '
            '링크안되는건가? 싹다링크해야하는데」 — the keys a name gathers '
            'hold one value AND one type',
      );
      expect(result.keyAt(0)!.interpolation, PropertyKeyInterpolation.linear);
    });

    test('keyForName can EXCLUDE the keys that are joining', () {
      final subject = track({0: (1, 'A'), 5: (2, null)});

      expect(subject.keyForName('A')!.value, 1);
      expect(
        subject.keyForName('A', excludeFrames: {0}),
        isNull,
        reason: 'a key doing the joining must not answer for the name',
      );
    });
  });
}
