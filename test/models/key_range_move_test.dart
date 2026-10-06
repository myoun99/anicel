import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/camera_instruction.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/key_range_move.dart';
import 'package:anicel/src/models/key_range_shift.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/transform_track.dart';

/// P3b-2 (#2 second half): instruction spans shift with a range selection
/// — rigid, all-or-nothing.
///
/// ↩️The camera's keys were shifted here too, as a map of whole poses
/// (`shiftCameraKeysInRange`). They ride as the track they are now, by the
/// lanes' own range move (F-309) — pinned where that law lives
/// (`property_track_edits_test`) and where the camera row rides it
/// (`editor_session_manager_range_move_test`).
void main() {
  group('transform tracks (P3c #13)', () {
    TransformTrack track() => TransformTrack.properties(
      anchorPoint: PropertyTrack.empty(),
      position: PropertyTrack<CanvasPoint>().withKey(
        2,
        CanvasPoint(x: 1, y: 1),
      ),
      scale: PropertyTrack<CanvasPoint>().withKey(4, uniformScale(1.5)),
      rotation: PropertyTrack.empty(),
      opacity: PropertyTrack<double>().withKey(2, 0.5).withKey(9, 1.0),
    );

    test('the union covers every lane\'s keyed frames', () {
      expect(transformKeyFrameUnion(track()), {2, 4, 9});
    });
  });

  group('shiftInstructionEventsAt', () {
    const pan = InstructionEvent(instructionId: 'pan', length: 3);
    const zoom = InstructionEvent(instructionId: 'zoom', length: 2);

    test('shifts the events STARTING at the named keys; overlap with an '
        'unmoved event voids', () {
      final events = {1: pan, 8: zoom};
      final shifted = shiftInstructionEventsAt(
        events: events,
        starts: {1},
        frameDelta: 3,
      );
      expect(shifted!.keys.toSet(), {4, 8});
      expect(shifted[4], same(pan));

      expect(
        shiftInstructionEventsAt(events: events, starts: {1}, frameDelta: 6),
        isNull,
        reason: 'pan at [7,10) would overlap zoom at [8,10)',
      );
    });

    test('negative landings void', () {
      expect(
        shiftInstructionEventsAt(
          events: const {1: pan},
          starts: {1},
          frameDelta: -2,
        ),
        isNull,
      );
    });
  });

  test('a range holds the keys STARTING in it', () {
    expect(keysStartingIn(const [1, 3, 4, 8], 1, 4), {1, 3});
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
      scale: PropertyTrack<CanvasPoint>(
        keys: {
          for (final entry in scale.entries)
            entry.key: PropertyKey<CanvasPoint>(
              uniformScale(1),
              name: entry.value,
            ),
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
