import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/se_name_tag.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/ui/timeline/effect_lane_editing.dart';
import 'package:anicel/src/ui/timeline/effect_lane_policy.dart';
import 'package:anicel/src/ui/timeline/lane_span_keys_shift.dart';
import 'package:anicel/src/ui/timeline/se_name_tag_lane_policy.dart';
import 'package:anicel/src/ui/timeline/transform_lane_editing.dart';

/// The `switch (laneId)` every verb used to carry is a TABLE now: one lens
/// per lane id, and the verbs dispatch over it. These pin the tables —
/// every id reaches its own field and no other — and run the one shared
/// keys-shift verb through all three families.
void main() {
  /// A lane edit that needs no value of the lane's type: it EMPTIES the
  /// lane, so a write through one lens is visible on exactly one field.
  PropertyTrack<U>? clear<U>(PropertyTrack<U> lane) => PropertyTrack<U>.empty();

  PropertyTrack<T> keyed<T>(T value, {int at = 7}) =>
      PropertyTrack<T>(keys: {at: PropertyKey<T>(value)});

  group('the transform table', () {
    final fields = <String, PropertyTrack<Object?> Function(TransformTrack)>{
      'anchor-point': (t) => t.anchorPoint,
      'position': (t) => t.position,
      'scale': (t) => t.scale,
      'rotation': (t) => t.rotation,
      'opacity': (t) => t.opacity,
    };
    TransformTrack allKeyed() => TransformTrack.properties(
      anchorPoint: keyed(CanvasPoint(x: 1, y: 1)),
      position: keyed(CanvasPoint(x: 2, y: 2)),
      scale: keyed(1.5),
      rotation: keyed(30.0),
      opacity: keyed(0.5),
    );

    test('every lane id reads and writes its own field and no other', () {
      for (final entry in fields.entries) {
        final lens = transformLaneLens(entry.key)!;
        expect(lens.keyFrames(allKeyed()), {7});
        expect(transformLaneKeyFrames(allKeyed(), entry.key), {7});
        final cleared = lens.update(allKeyed(), clear)!;
        for (final other in fields.entries) {
          expect(
            other.value(cleared).keys.keys,
            other.key == entry.key ? isEmpty : [7],
            reason: '${entry.key} must write ${entry.key} only',
          );
        }
      }
    });

    test('an id off the table is null, and its key frames are empty', () {
      expect(transformLaneLens('name-tag:size'), isNull);
      expect(transformLaneLens('nope'), isNull);
      expect(transformLaneKeyFrames(allKeyed(), 'nope'), isEmpty);
    });

    test('a null edit writes nothing', () {
      expect(
        transformLaneLens(
          'scale',
        )!.update(allKeyed(), <U>(PropertyTrack<U> lane) => null),
        isNull,
      );
    });
  });

  group('the name-tag table', () {
    final fields = <String, PropertyTrack<Object?> Function(SeNameTagTrack)>{
      seNameTagSizeLaneId: (t) => t.fontSize,
      seNameTagTrackingLaneId: (t) => t.letterSpacing,
      seNameTagBoldLaneId: (t) => t.bold,
      seNameTagNameInkLaneId: (t) => t.nameInk,
      seNameTagBoxColorLaneId: (t) => t.boxColor,
      seNameTagLineInkLaneId: (t) => t.lineInk,
      seNameTagShowLineLaneId: (t) => t.showLine,
    };
    SeNameTagTrack allKeyed() => SeNameTagTrack(
      fontSize: keyed(12.0),
      letterSpacing: keyed(1.0),
      bold: keyed(true),
      nameInk: keyed(0xFF000000),
      boxColor: keyed(0xFFFF0000),
      lineInk: keyed(0xFF0000FF),
      showLine: keyed(false),
    );

    test('every member lane id reads and writes its own field and no '
        'other', () {
      expect(fields.keys, seNameTagLaneDisplayOrder);
      for (final entry in fields.entries) {
        final lens = seNameTagLaneLens(entry.key)!;
        expect(lens.keyFrames(allKeyed()), {7});
        expect(seNameTagLaneKeyFrames(allKeyed(), entry.key), {7});
        final cleared = lens.update(allKeyed(), clear)!;
        for (final other in fields.entries) {
          expect(
            other.value(cleared).keys.keys,
            other.key == entry.key ? isEmpty : [7],
            reason: '${entry.key} must write ${entry.key} only',
          );
        }
      }
    });

    test('the header and a foreign id are off the table', () {
      expect(seNameTagLaneLens(seNameTagGroupLaneId), isNull);
      expect(seNameTagLaneLens('scale'), isNull);
      expect(seNameTagLaneKeyFrames(allKeyed(), seNameTagGroupLaneId), isEmpty);
    });
  });

  group('the effect table', () {
    LayerEffect blur() => LayerEffect(
      id: const EffectId('e1'),
      kind: EffectKind.blur,
      parameters: {
        'blurX': EffectParameter(track: keyed(4.0, at: 5)),
        'blurY': EffectParameter(track: keyed(1.0, at: 9)),
      },
    );
    final x = effectLaneId(const EffectId('e1'), 'blurX');
    final y = effectLaneId(const EffectId('e1'), 'blurY');
    final header = effectGroupLaneId(const EffectId('e1'));

    test('a parameter lane reads and writes its own parameter and no '
        'other', () {
      expect(effectLaneLens(x)!.keyFrames([blur()]), {5});
      expect(effectLaneLens(y)!.keyFrames([blur()]), {9});
      final cleared = effectLaneLens(x)!.update([blur()], clear)!;
      expect(cleared.single.parameterOf('blurX').track.keys.keys, isEmpty);
      expect(cleared.single.parameterOf('blurY').track.keys.keys, [9]);
    });

    test('the header sums its members\' keys but holds no track to edit', () {
      expect(effectLaneLens(header)!.keyFrames([blur()]), {5, 9});
      expect(effectLaneLens(header)!.update([blur()], clear), isNull);
    });

    test('an effect that is not in the chain, or a foreign id, is null', () {
      expect(
        effectLaneLens(
          effectLaneId(const EffectId('zz'), 'blurX'),
        )!.update([blur()], clear),
        isNull,
      );
      expect(effectLaneLens('position'), isNull);
    });
  });

  group('the one keys-shift verb runs through every table', () {
    test('transform', () {
      final track = TransformTrack.empty().copyWith(
        rotation: PropertyTrack<double>().withKey(2, 30).withKey(9, 60),
      );
      final shifted = trackWithLaneKeysShifted(
        track,
        lensOf: transformLaneLens,
        laneId: 'rotation',
        rangeStartIndex: 0,
        rangeEndIndexExclusive: 5,
        frameDelta: 4,
      )!;
      expect(shifted.rotation.keys.keys.toSet(), {6, 9});
      expect(shifted.rotation.keyAt(6)!.value, 30);
    });

    test('name tag', () {
      final keys = SeNameTagTrack.empty().copyWith(
        bold: PropertyTrack<bool>().withKey(1, true),
      );
      final shifted = trackWithLaneKeysShifted(
        keys,
        lensOf: seNameTagLaneLens,
        laneId: seNameTagBoldLaneId,
        rangeStartIndex: 0,
        rangeEndIndexExclusive: 5,
        frameDelta: 2,
      )!;
      expect(shifted.bold.keys.keys.toSet(), {3});
    });

    test('effects', () {
      final x = effectLaneId(const EffectId('e1'), 'blurX');
      final effects = [
        LayerEffect(
          id: const EffectId('e1'),
          kind: EffectKind.blur,
          parameters: {'blurX': EffectParameter(track: keyed(4.0, at: 2))},
        ),
      ];
      final shifted = trackWithLaneKeysShifted(
        effects,
        lensOf: effectLaneLens,
        laneId: x,
        rangeStartIndex: 0,
        rangeEndIndexExclusive: 5,
        frameDelta: 3,
      )!;
      expect(shifted.single.parameterOf('blurX').track.keys.keys, [5]);
    });

    test('a zero delta and an unknown lane are null on every table', () {
      for (final call in [
        () => trackWithLaneKeysShifted(
          TransformTrack.empty(),
          lensOf: transformLaneLens,
          laneId: 'scale',
          rangeStartIndex: 0,
          rangeEndIndexExclusive: 5,
          frameDelta: 0,
        ),
        () => trackWithLaneKeysShifted(
          TransformTrack.empty(),
          lensOf: transformLaneLens,
          laneId: 'nope',
          rangeStartIndex: 0,
          rangeEndIndexExclusive: 5,
          frameDelta: 1,
        ),
        () => trackWithLaneKeysShifted(
          SeNameTagTrack.empty(),
          lensOf: seNameTagLaneLens,
          laneId: 'nope',
          rangeStartIndex: 0,
          rangeEndIndexExclusive: 5,
          frameDelta: 1,
        ),
      ]) {
        expect(call(), isNull);
      }
    });
  });
}
