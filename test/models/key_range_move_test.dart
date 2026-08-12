import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/camera_instruction.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/key_range_move.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/transform_track.dart';

/// P3b-2 (#2 second half): camera keys and instruction spans shift with a
/// range selection — rigid, all-or-nothing.
void main() {
  final pose = CameraPose(center: CanvasPoint(x: 0, y: 0));

  group('shiftCameraKeysInRange', () {
    final keys = {2: pose, 4: pose, 9: pose};

    test('shifts exactly the keys in range; the rest stay', () {
      final shifted = shiftCameraKeysInRange(
        keyframes: keys,
        rangeStartIndex: 2,
        rangeEndIndexExclusive: 5,
        frameDelta: 3,
      );
      expect(shifted!.keys.toSet(), {5, 7, 9});
    });

    test('a landing on an UNSHIFTED key voids the plan', () {
      expect(
        shiftCameraKeysInRange(
          keyframes: keys,
          rangeStartIndex: 2,
          rangeEndIndexExclusive: 3,
          frameDelta: 2,
        ),
        isNull,
        reason: '2+2 lands on the unmoved 4',
      );
    });

    test('negative landings, empty ranges and zero deltas void', () {
      expect(
        shiftCameraKeysInRange(
          keyframes: keys,
          rangeStartIndex: 2,
          rangeEndIndexExclusive: 5,
          frameDelta: -3,
        ),
        isNull,
        reason: '2-3 dips below 0',
      );
      expect(
        shiftCameraKeysInRange(
          keyframes: keys,
          rangeStartIndex: 6,
          rangeEndIndexExclusive: 8,
          frameDelta: 2,
        ),
        isNull,
        reason: 'no keys in range',
      );
      expect(
        shiftCameraKeysInRange(
          keyframes: keys,
          rangeStartIndex: 2,
          rangeEndIndexExclusive: 5,
          frameDelta: 0,
        ),
        isNull,
      );
    });

    test('keys within the moved set may swap places freely', () {
      final shifted = shiftCameraKeysInRange(
        keyframes: {2: pose, 3: pose},
        rangeStartIndex: 2,
        rangeEndIndexExclusive: 4,
        frameDelta: 1,
      );
      expect(shifted!.keys.toSet(), {3, 4}, reason: '3 vacates before 2 lands');
    });
  });

  group('transform tracks (P3c #13)', () {
    TransformTrack track() => TransformTrack.properties(
      anchorPoint: PropertyTrack.empty(),
      position: PropertyTrack<CanvasPoint>().withKey(
        2,
        CanvasPoint(x: 1, y: 1),
      ),
      scale: PropertyTrack<double>().withKey(4, 1.5),
      rotation: PropertyTrack.empty(),
      opacity: PropertyTrack<double>().withKey(2, 0.5).withKey(9, 1.0),
    );

    test('the union covers every lane\'s keyed frames', () {
      expect(transformKeyFrameUnion(track()), {2, 4, 9});
      expect(transformTrackHasKeysInRange(track(), 2, 5), isTrue);
      expect(transformTrackHasKeysInRange(track(), 5, 9), isFalse);
    });

    test('a range shift moves every lane\'s keys together; untouched '
        'lanes pass through; a same-lane collision voids', () {
      final shifted = shiftTransformKeysInRange(
        track: track(),
        rangeStartIndex: 2,
        rangeEndIndexExclusive: 5,
        frameDelta: 3,
      );
      expect(shifted!.position.keys.keys.toList(), [5]);
      expect(shifted.scale.keys.keys.toList(), [7]);
      expect(shifted.opacity.keys.keys.toSet(), {5, 9});
      expect(shifted.rotation.isEmpty, isTrue);

      // Opacity key at 2 shifted +7 would land on the unmoved 9 → void.
      expect(
        shiftTransformKeysInRange(
          track: track(),
          rangeStartIndex: 2,
          rangeEndIndexExclusive: 5,
          frameDelta: 7,
        ),
        isNull,
      );
      expect(
        shiftTransformKeysInRange(
          track: track(),
          rangeStartIndex: 2,
          rangeEndIndexExclusive: 5,
          frameDelta: -3,
        ),
        isNull,
        reason: '2-3 dips below 0',
      );
    });
  });

  group('shiftInstructionEventsInRange', () {
    const pan = InstructionEvent(instructionId: 'pan', length: 3);
    const zoom = InstructionEvent(instructionId: 'zoom', length: 2);

    test('shifts events STARTING in range; overlap with an unmoved event '
        'voids', () {
      final events = {1: pan, 8: zoom};
      final shifted = shiftInstructionEventsInRange(
        events: events,
        rangeStartIndex: 0,
        rangeEndIndexExclusive: 4,
        frameDelta: 3,
      );
      expect(shifted!.keys.toSet(), {4, 8});
      expect(shifted[4], same(pan));

      expect(
        shiftInstructionEventsInRange(
          events: events,
          rangeStartIndex: 0,
          rangeEndIndexExclusive: 4,
          frameDelta: 6,
        ),
        isNull,
        reason: 'pan at [7,10) would overlap zoom at [8,10)',
      );
    });

    test('negative landings void', () {
      expect(
        shiftInstructionEventsInRange(
          events: const {1: pan},
          rangeStartIndex: 0,
          rangeEndIndexExclusive: 4,
          frameDelta: -2,
        ),
        isNull,
      );
    });
  });

  // ㉚ (user, 2026-08-12): 「유니언 그룹 이름 규칙 — 해당 인덱스 멤버들
  // 이름이 같으면 그 이름 그대로, 다르면 `...`」.
  group('transformKeyNameUnion', () {
    TransformTrack trackWith({
      Map<int, String?> position = const {},
      Map<int, String?> scale = const {},
    }) => TransformTrack.properties(
      anchorPoint: PropertyTrack.empty(),
      position: PropertyTrack<CanvasPoint>(
        keys: {
          for (final entry in position.entries)
            entry.key: PropertyKey<CanvasPoint>(
              CanvasPoint(x: 0, y: 0),
              name: entry.value,
            ),
        },
      ),
      scale: PropertyTrack<double>(
        keys: {
          for (final entry in scale.entries)
            entry.key: PropertyKey<double>(1, name: entry.value),
        },
      ),
      rotation: PropertyTrack.empty(),
      opacity: PropertyTrack.empty(),
    );

    test('members that agree print that name', () {
      expect(
        transformKeyNameUnion(
          trackWith(position: {3: 'Wall'}, scale: {3: 'Wall'}),
        ),
        {3: 'Wall'},
      );
    });

    test('members that disagree print the mixed mark', () {
      expect(
        transformKeyNameUnion(
          trackWith(position: {3: 'Wall'}, scale: {3: 'Floor'}),
        ),
        {3: unionMixedKeyName},
      );
    });

    test('a lone named member does NOT speak for the group', () {
      // It would otherwise claim a name only one lane carries.
      expect(
        transformKeyNameUnion(
          trackWith(position: {3: 'Wall'}, scale: {3: null}),
        ),
        {3: unionMixedKeyName},
      );
    });

    test('a lane with no key here has no vote', () {
      // Scale is keyed at 5, not at 3 — so frame 3 is Wall alone and agrees
      // with itself.
      expect(
        transformKeyNameUnion(
          trackWith(position: {3: 'Wall'}, scale: {5: 'Floor'}),
        ),
        {3: 'Wall', 5: 'Floor'},
      );
    });

    test('frames where nothing is named print nothing at all', () {
      // NOT `...`: the mark means "several different names", and over a set
      // with none it would be noise where the row used to print nothing.
      expect(
        transformKeyNameUnion(trackWith(position: {3: null}, scale: {3: null})),
        isEmpty,
      );
      expect(transformKeyNameUnion(TransformTrack.empty()), isEmpty);
    });
  });
}
