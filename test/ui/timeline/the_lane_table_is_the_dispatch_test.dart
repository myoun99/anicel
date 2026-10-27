import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/se_name_tag.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/ui/timeline/effect_lane_editing.dart';
import 'package:anicel/src/ui/timeline/effect_lane_policy.dart';
import 'package:anicel/src/ui/timeline/lane_span_keys_shift.dart';
import 'package:anicel/src/ui/timeline/property_lane_lens.dart';
import 'package:anicel/src/ui/timeline/se_name_tag_lane_policy.dart';
import 'package:anicel/src/ui/timeline/transform_lane_editing.dart';

/// The `switch (laneId)` every verb used to carry is a TABLE now: one lens
/// per lane id, and the verbs dispatch over it. These pin the tables —
/// every id reaches its own field and no other — and run the one shared
/// keys-move verb through all three families.
void main() {
  /// A lane edit that needs no value of the lane's type: it drops the key
  /// at [frame]. Every field below is keyed on a DIFFERENT frame, so a lens
  /// that read one field and wrote another would carry a foreign key
  /// across — and the table check would see it.
  PropertyLaneEdit without(int frame) =>
      <U>(PropertyTrack<U> lane) => lane.withoutKey(frame);

  /// A lane edit that needs no value of the lane's type: it EMPTIES the
  /// lane, so a write through one lens is visible on exactly one field.
  PropertyTrack<U>? clear<U>(PropertyTrack<U> lane) => PropertyTrack<U>.empty();

  PropertyTrack<T> keyed<T>(T value, {required int at}) =>
      PropertyTrack<T>(keys: {at: PropertyKey<T>(value)});

  group('the transform table', () {
    // (field reader, the frame that field alone is keyed on)
    final fields =
        <String, (PropertyTrack<Object?> Function(TransformTrack), int)>{
          'anchor-point': ((t) => t.anchorPoint, 1),
          'position': ((t) => t.position, 2),
          'scale': ((t) => t.scale, 3),
          'rotation': ((t) => t.rotation, 4),
          'opacity': ((t) => t.opacity, 5),
        };
    TransformTrack allKeyed() => TransformTrack.properties(
      anchorPoint: keyed(CanvasPoint(x: 1, y: 1), at: 1),
      position: keyed(CanvasPoint(x: 2, y: 2), at: 2),
      scale: keyed(uniformScale(1.5), at: 3),
      rotation: keyed(30.0, at: 4),
      opacity: keyed(0.5, at: 5),
    );

    test('every lane id reads and writes its own field and no other', () {
      for (final entry in fields.entries) {
        final (_, frame) = entry.value;
        final lens = transformLaneLens(entry.key)!;
        expect(lens.keyFrames(allKeyed()), {frame});
        expect(transformLaneKeyFrames(allKeyed(), entry.key), {frame});
        final cleared = lens.update(allKeyed(), without(frame))!;
        for (final other in fields.entries) {
          final (read, otherFrame) = other.value;
          expect(
            read(cleared).keys.keys,
            other.key == entry.key ? isEmpty : [otherFrame],
            reason: '${entry.key} must read and write ${entry.key} only',
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
    final fields =
        <String, (PropertyTrack<Object?> Function(SeNameTagTrack), int)>{
          seNameTagSizeLaneId: ((t) => t.fontSize, 1),
          seNameTagTrackingLaneId: ((t) => t.letterSpacing, 2),
          seNameTagBoldLaneId: ((t) => t.bold, 3),
          seNameTagItalicLaneId: ((t) => t.italic, 4),
          seNameTagUnderlineLaneId: ((t) => t.underline, 5),
          seNameTagStrikethroughLaneId: ((t) => t.strikethrough, 6),
          seNameTagNameInkLaneId: ((t) => t.nameInk, 7),
          seNameTagBoxColorLaneId: ((t) => t.boxColor, 8),
          seNameTagLineInkLaneId: ((t) => t.lineInk, 9),
          seNameTagShowLineLaneId: ((t) => t.showLine, 10),
        };
    SeNameTagTrack allKeyed() => SeNameTagTrack(
      fontSize: keyed(12.0, at: 1),
      letterSpacing: keyed(1.0, at: 2),
      bold: keyed(true, at: 3),
      italic: keyed(true, at: 4),
      underline: keyed(true, at: 5),
      strikethrough: keyed(true, at: 6),
      nameInk: keyed(0xFF000000, at: 7),
      boxColor: keyed(0xFFFF0000, at: 8),
      lineInk: keyed(0xFF0000FF, at: 9),
      showLine: keyed(false, at: 10),
    );

    test('every member lane id reads and writes its own field and no '
        'other', () {
      expect(fields.keys, seNameTagLaneDisplayOrder);
      for (final entry in fields.entries) {
        final (_, frame) = entry.value;
        final lens = seNameTagLaneLens(entry.key)!;
        expect(lens.keyFrames(allKeyed()), {frame});
        expect(seNameTagLaneKeyFrames(allKeyed(), entry.key), {frame});
        final cleared = lens.update(allKeyed(), without(frame))!;
        for (final other in fields.entries) {
          final (read, otherFrame) = other.value;
          expect(
            read(cleared).keys.keys,
            other.key == entry.key ? isEmpty : [otherFrame],
            reason: '${entry.key} must read and write ${entry.key} only',
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
        'blurriness': EffectParameter(track: keyed(4.0, at: 5)),
        'blurDimensions': EffectParameter(track: keyed(1.0, at: 9)),
      },
    );
    final x = effectLaneId(const EffectId('e1'), 'blurriness');
    final y = effectLaneId(const EffectId('e1'), 'blurDimensions');
    final header = effectGroupLaneId(const EffectId('e1'));

    test('a parameter lane reads and writes its own parameter and no '
        'other', () {
      expect(effectLaneLens(x)!.keyFrames([blur()]), {5});
      expect(effectLaneLens(y)!.keyFrames([blur()]), {9});
      final cleared = effectLaneLens(x)!.update([blur()], clear)!;
      expect(cleared.single.parameterOf('blurriness').track.keys.keys, isEmpty);
      expect(cleared.single.parameterOf('blurDimensions').track.keys.keys, [9]);
    });

    test('the header sums its members\' keys but holds no track to edit', () {
      expect(effectLaneLens(header)!.keyFrames([blur()]), {5, 9});
      expect(effectLaneLens(header)!.update([blur()], clear), isNull);
    });

    test('an effect that is not in the chain, or a foreign id, is null', () {
      expect(
        effectLaneLens(
          effectLaneId(const EffectId('zz'), 'blurriness'),
        )!.update([blur()], clear),
        isNull,
      );
      expect(effectLaneLens('position'), isNull);
    });
  });

  group('the one keys-move verb runs through every table', () {
    test('transform', () {
      final track = TransformTrack.empty().copyWith(
        rotation: PropertyTrack<double>().withKey(2, 30).withKey(9, 60),
      );
      final shifted = transformLaneLens('rotation')!.keysMoved(track, (
        rangeStartIndex: 0,
        rangeEndIndexExclusive: 5,
        to: (frame) => frame + 4,
      ))!;
      expect(shifted.rotation.keys.keys.toSet(), {6, 9});
      expect(shifted.rotation.keyAt(6)!.value, 30);
    });

    test('name tag', () {
      final keys = SeNameTagTrack.empty().copyWith(
        bold: PropertyTrack<bool>().withKey(1, true),
      );
      final shifted = seNameTagLaneLens(seNameTagBoldLaneId)!.keysMoved(keys, (
        rangeStartIndex: 0,
        rangeEndIndexExclusive: 5,
        to: (frame) => frame + 2,
      ))!;
      expect(shifted.bold.keys.keys.toSet(), {3});
    });

    test('effects', () {
      final x = effectLaneId(const EffectId('e1'), 'blurriness');
      final effects = [
        LayerEffect(
          id: const EffectId('e1'),
          kind: EffectKind.blur,
          parameters: {'blurriness': EffectParameter(track: keyed(4.0, at: 2))},
        ),
      ];
      final shifted = effectLaneLens(x)!.keysMoved(effects, (
        rangeStartIndex: 0,
        rangeEndIndexExclusive: 5,
        to: (frame) => frame + 3,
      ))!;
      expect(shifted.single.parameterOf('blurriness').track.keys.keys, [5]);
    });

    test('an unknown lane is null on every table', () {
      for (final call in [
        () => transformLaneLens('nope')?.keysMoved(TransformTrack.empty(), (
          rangeStartIndex: 0,
          rangeEndIndexExclusive: 5,
          to: (frame) => frame + 1,
        )),
        () => seNameTagLaneLens('nope')?.keysMoved(SeNameTagTrack.empty(), (
          rangeStartIndex: 0,
          rangeEndIndexExclusive: 5,
          to: (frame) => frame + 1,
        )),
      ]) {
        expect(call(), isNull);
      }
    });
  });
}
