import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/se_name_tag.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/se_name_tag_lane_editing.dart';
import 'package:anicel/src/ui/timeline/se_name_tag_lane_policy.dart';

/// C① (2026-08-17, #1116's open cell ①) — the name-tag lane family joins
/// the ONE lane-move machine: a ranged key move on a nametag lane shifts
/// its keys as one rigid group, exactly as the transform and effect
/// families do. No new machine — a third subject arm.
void main() {
  group('seNameTagTrackWithLaneSpanKeysShifted (the pure law)', () {
    SeNameTagTrack keyed(Map<int, double> sizes, {Map<int, bool>? bolds}) =>
        SeNameTagTrack(
          fontSize: PropertyTrack(
            keys: {
              for (final entry in sizes.entries)
                entry.key: PropertyKey(entry.value),
            },
          ),
          bold: bolds == null
              ? null
              : PropertyTrack(
                  keys: {
                    for (final entry in bolds.entries)
                      entry.key: PropertyKey(entry.value),
                  },
                ),
        );

    test('shifts every ranged key of every spanned lane as one group', () {
      final track = keyed({2: 20, 3: 24}, bolds: {2: true});

      final next = seNameTagTrackWithLaneSpanKeysShifted(
        track,
        laneIds: const [seNameTagSizeLaneId, seNameTagBoldLaneId],
        rangeStartIndex: 2,
        rangeEndIndexExclusive: 4,
        frameDelta: 5,
      )!;

      expect(next.fontSize.keys.keys.toList(), [7, 8]);
      expect(next.bold.keys.keys.toList(), [7]);
    });

    test('a lane with no ranged key rides along', () {
      final track = keyed({2: 20}, bolds: {9: true});

      final next = seNameTagTrackWithLaneSpanKeysShifted(
        track,
        laneIds: const [seNameTagSizeLaneId, seNameTagBoldLaneId],
        rangeStartIndex: 2,
        rangeEndIndexExclusive: 4,
        frameDelta: 3,
      )!;

      expect(next.fontSize.keys.keys.toList(), [5]);
      expect(next.bold.keys.keys.toList(), [9], reason: 'untouched');
    });

    test('a blocked landing vetoes the WHOLE move', () {
      // The size lane would land fine; the bold lane's landing collides
      // with its own unshifted key at 9 — all-or-nothing across lanes.
      final track = keyed({2: 20}, bolds: {3: true, 9: false});

      expect(
        seNameTagTrackWithLaneSpanKeysShifted(
          track,
          laneIds: const [seNameTagSizeLaneId, seNameTagBoldLaneId],
          rangeStartIndex: 2,
          rangeEndIndexExclusive: 4,
          frameDelta: 6,
        ),
        isNull,
      );
    });

    test('a landing below zero vetoes', () {
      final track = keyed({2: 20});

      expect(
        seNameTagTrackWithLaneSpanKeysShifted(
          track,
          laneIds: const [seNameTagSizeLaneId],
          rangeStartIndex: 0,
          rangeEndIndexExclusive: 4,
          frameDelta: -3,
        ),
        isNull,
      );
    });

    test('null when no spanned lane moves a key', () {
      final track = keyed({9: 20});

      expect(
        seNameTagTrackWithLaneSpanKeysShifted(
          track,
          laneIds: const [seNameTagSizeLaneId, seNameTagBoldLaneId],
          rangeStartIndex: 0,
          rangeEndIndexExclusive: 4,
          frameDelta: 2,
        ),
        isNull,
      );
    });
  });

  group('the lane-move machine, third arm (session)', () {
    test('a member-span drag moves exactly the ranged keys as ONE undo, '
        'and the selection rides to the landed span', () {
      final session = EditorSessionManager(
        initialProject: createDefaultProject(),
      );
      addTearDown(session.dispose);
      final se = session.activeTrack.seLayers.first;
      session.setSeNameTagForLayer(
        se.id,
        SeNameTag(
          track: SeNameTagTrack(
            fontSize: PropertyTrack(
              keys: {2: PropertyKey(20.0), 3: PropertyKey(24.0)},
            ),
          ),
        ),
      );

      session.updateLaneRangeSelectionDrag(
        layerId: se.id,
        laneId: seNameTagSizeLaneId,
        anchorIndex: 2,
        headIndex: 3,
        framesAreGlobal: true,
      );
      expect(session.beginLaneRangeMoveDrag(), isTrue,
          reason: 'the nametag family used to refuse in silence — the '
              'observed C① symptom');
      session.updateLaneRangeMoveDrag(frameDelta: 5);
      session.endLaneRangeMoveDrag();

      SeNameTagTrack keysOf() => session.activeTrack.seLayers.first
          .seNameTag!
          .track!;
      expect(keysOf().fontSize.keys.keys.toList(), [7, 8]);
      expect(session.laneRangeSelection.value!.startIndex, 7);

      session.undo();
      expect(keysOf().fontSize.keys.keys.toList(), [2, 3]);
    });

    test('a HEADER-anchored drag moves every member\'s ranged keys '
        '(한번에 잡아 이동)', () {
      final session = EditorSessionManager(
        initialProject: createDefaultProject(),
      );
      addTearDown(session.dispose);
      final se = session.activeTrack.seLayers.first;
      session.setSeNameTagForLayer(
        se.id,
        SeNameTag(
          track: SeNameTagTrack(
            fontSize: PropertyTrack(keys: {2: PropertyKey(20.0)}),
            bold: PropertyTrack(keys: {3: PropertyKey(true)}),
          ),
        ),
      );

      session.updateLaneRangeSelectionDrag(
        layerId: se.id,
        laneId: seNameTagGroupLaneId,
        anchorIndex: 2,
        headIndex: 3,
        framesAreGlobal: true,
      );
      expect(session.beginLaneRangeMoveDrag(), isTrue);
      session.updateLaneRangeMoveDrag(frameDelta: 4);
      session.endLaneRangeMoveDrag();

      final keys = session.activeTrack.seLayers.first.seNameTag!.track!;
      expect(keys.fontSize.keys.keys.toList(), [6]);
      expect(keys.bold.keys.keys.toList(), [7]);
    });

    test('an UNKEYED nametag span still refuses to begin', () {
      final session = EditorSessionManager(
        initialProject: createDefaultProject(),
      );
      addTearDown(session.dispose);
      final se = session.activeTrack.seLayers.first;

      session.updateLaneRangeSelectionDrag(
        layerId: se.id,
        laneId: seNameTagSizeLaneId,
        anchorIndex: 2,
        headIndex: 3,
        framesAreGlobal: true,
      );
      expect(session.beginLaneRangeMoveDrag(), isFalse);
    });

    test('a blocked step HOLDS the last valid preview (UI-R23 #10)', () {
      final session = EditorSessionManager(
        initialProject: createDefaultProject(),
      );
      addTearDown(session.dispose);
      final se = session.activeTrack.seLayers.first;
      session.setSeNameTagForLayer(
        se.id,
        SeNameTag(
          track: SeNameTagTrack(
            fontSize: PropertyTrack(
              keys: {
                2: PropertyKey(20.0),
                3: PropertyKey(24.0),
                9: PropertyKey(30.0),
              },
            ),
          ),
        ),
      );

      session.updateLaneRangeSelectionDrag(
        layerId: se.id,
        laneId: seNameTagSizeLaneId,
        anchorIndex: 2,
        headIndex: 3,
        framesAreGlobal: true,
      );
      expect(session.beginLaneRangeMoveDrag(), isTrue);
      session.updateLaneRangeMoveDrag(frameDelta: 2);
      // 2+7=9 collides with the unshifted key at 9 — the step holds.
      session.updateLaneRangeMoveDrag(frameDelta: 7);
      session.endLaneRangeMoveDrag();

      final keys = session.activeTrack.seLayers.first.seNameTag!.track!;
      expect(
        keys.fontSize.keys.keys.toList(),
        [4, 5, 9],
        reason: 'the LAST VALID step (+2) landed, not the blocked one',
      );
    });

    test('🚨track-SE axis: the commit lands on the GLOBAL axis exactly '
        'ONCE — never through the window-converting host verb', () {
      final session = EditorSessionManager(
        initialProject: createDefaultProject(),
      );
      addTearDown(session.dispose);
      // A second cut, active, so the active cut's global start is NOT 0 —
      // a commit that window-converts a second time would shift the keys
      // by that start again.
      session.createCut();
      final firstDuration = session
          .repository
          .requireProject()
          .tracks
          .first
          .cuts
          .first
          .duration;
      final se = session.activeTrack.seLayers.first;
      // The host verb converts cut-local input → global on the way IN:
      // input 2,3 becomes global first+2, first+3.
      session.setSeNameTagForLayer(
        se.id,
        SeNameTag(
          track: SeNameTagTrack(
            fontSize: PropertyTrack(
              keys: {2: PropertyKey(20.0), 3: PropertyKey(24.0)},
            ),
          ),
        ),
      );
      final globalKeys = session.activeTrack.seLayers.first.seNameTag!.track!
          .fontSize
          .keys
          .keys
          .toList();
      expect(globalKeys, [firstDuration + 2, firstDuration + 3]);

      session.updateLaneRangeSelectionDrag(
        layerId: se.id,
        laneId: seNameTagSizeLaneId,
        anchorIndex: firstDuration + 2,
        headIndex: firstDuration + 3,
        framesAreGlobal: true,
      );
      expect(session.beginLaneRangeMoveDrag(), isTrue);
      session.updateLaneRangeMoveDrag(frameDelta: 5);
      session.endLaneRangeMoveDrag();

      expect(
        session.activeTrack.seLayers.first.seNameTag!.track!.fontSize.keys.keys
            .toList(),
        [firstDuration + 7, firstDuration + 8],
        reason: 'shifted by the drag delta alone — a double window '
            'conversion would add the cut start again',
      );
    });
  });
}
