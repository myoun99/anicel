import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/property_track.dart';

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
    test('withNamedValue moves every key of that name', () {
      final result = track({
        0: (1, 'A'),
        5: (2, null),
        10: (3, 'A'),
      }).withNamedValue('A', 9);

      expect(result.keyAt(0)!.value, 9);
      expect(result.keyAt(10)!.value, 9);
      expect(result.keyAt(5)!.value, 2, reason: 'unnamed keys are untouched');
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
        (value) => (value as num).toDouble(),
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

    test('a RENAME counts as a change even at the same value', () {
      final before = [blur('e1', track({0: (1, null)}))];
      final after = [blur('e1', track({0: (1, 'A')}))];

      final changes = namedEffectKeyChanges(before, after);

      expect(changes, hasLength(1));
      expect(
        changes.single.value,
        1,
        reason: 'joining a name adopts THIS key\'s number elsewhere',
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
        ),
      ]);

      final radius = result.single.parameters[radiusId]!.track;
      expect(radius.keyAt(0)!.value, 9);
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
        ),
      ]);

      expect(result[0].parameters[radiusId]!.track.keyAt(0)!.value, 9);
      expect(result[1].parameters[radiusId]!.track.keyAt(0)!.value, 2);
    });
  });
}
