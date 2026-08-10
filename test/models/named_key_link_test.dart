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

    test('valueForName reads what a name already holds', () {
      final subject = track({0: (1, null), 4: (6, 'A')});

      expect(subject.valueForName('A'), 6);
      expect(subject.valueForName('B'), isNull);
    });

    test('namedEffectKeyValue reads it through the chain, per parameter', () {
      final effects = [blur('e1', track({4: (6, 'A')}))];

      expect(
        namedEffectKeyValue(
          effects,
          effectId: EffectId('e1'),
          parameterId: radiusId,
          name: 'A',
        ),
        6,
      );
      expect(
        namedEffectKeyValue(
          effects,
          effectId: EffectId('e2'),
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

  // The transform lanes ride the SAME predicate as effect parameters
  // ([movedNamedValues]) — a transform simply has no effect id to carry its
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

      expect(changes.rotation, {'A': 45.0});
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
      final result = transformTrackWithNamedValues(
        lanes(rotation: track({0: (10, 'A'), 5: (20, null), 9: (30, 'A')})),
        const TransformNamedChanges(rotation: {'A': 45}),
      );

      expect(result.rotation.keyAt(0)!.value, 45);
      expect(result.rotation.keyAt(9)!.value, 45);
      expect(result.rotation.keyAt(5)!.value, 20, reason: 'unnamed is free');
    });

    test('the same name in another LANE is another link', () {
      final result = transformTrackWithNamedValues(
        lanes(rotation: track({0: (10, 'A')}), scale: track({0: (2, 'A')})),
        const TransformNamedChanges(rotation: {'A': 45}),
      );

      expect(result.rotation.keyAt(0)!.value, 45);
      expect(
        result.scale.keyAt(0)!.value,
        2,
        reason: 'Rotation A and Scale A are different names by construction',
      );
    });

    test('joining ADOPTS the name\'s value and keeps the interpolation', () {
      final joiner = lanes(
        rotation: PropertyTrack<double>(
          keys: {
            3: const PropertyKey(10, interpolation: PropertyKeyInterpolation.hold),
          },
        ),
      );

      final result = transformTrackAdoptingName(
        joiner,
        lanes(rotation: track({0: (45, 'A')})),
        TransformPropertyId.rotation,
        3,
        'A',
      );

      expect(result.rotation.keyAt(3)!.value, 45, reason: 'the name wins');
      expect(
        result.rotation.keyAt(3)!.interpolation,
        PropertyKeyInterpolation.hold,
        reason: 'adopting a value must not restyle the segment leaving it',
      );
    });

    test('naming reads and writes go through one lane switch', () {
      final subject = lanes(rotation: track({4: (10, null)}));

      expect(transformLaneHasKeyAt(subject, TransformPropertyId.rotation, 4),
          isTrue);
      expect(transformLaneHasKeyAt(subject, TransformPropertyId.scale, 4),
          isFalse);
      expect(
        transformLaneKeyName(subject, TransformPropertyId.rotation, 4),
        isNull,
      );

      final named = transformTrackWithKeyName(
        subject,
        TransformPropertyId.rotation,
        4,
        'A',
      );

      expect(transformLaneKeyName(named, TransformPropertyId.rotation, 4), 'A');
      expect(
        transformLaneUsesName(named, TransformPropertyId.rotation, 'A'),
        isTrue,
      );
      expect(
        transformLaneUsesName(named, TransformPropertyId.scale, 'A'),
        isFalse,
      );
    });
  });
}
