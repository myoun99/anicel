import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/se_sound.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/se_name_tag_lane_policy.dart'
    show seNameTagGroupLaneId;
import 'package:anicel/src/ui/timeline/se_sound_lane_editing.dart';
import 'package:anicel/src/ui/timeline/se_sound_lane_policy.dart';
import 'package:anicel/src/ui/timeline/timeline_lane_provider.dart';
import 'package:anicel/src/ui/timeline/toolbar_panel_context.dart';

/// 🗣️I-140 (유저 2026-10-28): 「se행의 오디오 … 오디오fx만들어서 거기서
/// 편집하도록. 프리미어프로나 그런 영상편집툴이 하는대로」 — Q1 「행에 늘 있는
/// 「오디오」 그룹」, Q2 「%」, Q3 「이번엔 한 값」.
///
/// Every SE row has a fixed 「오디오」 group, its name tag's sibling: the
/// Volume, keyed in per cents on the row's own frames like every lane, and
/// the Pan, one value.
void main() {
  SeSound ramp() => SeSound(
    volume: PropertyTrack<double>(
      keys: {0: const PropertyKey(0.0), 10: const PropertyKey(1.0)},
    ),
  );

  group('the lanes', () {
    test('a twirled-shut group is its header alone; open, the Volume and '
        'the Pan follow it', () {
      final shut = seSoundPropertyLanes(
        const SeSound(),
        expanded: false,
        volumeAt: null,
      );
      expect(shut.map((lane) => lane.laneId), [seSoundGroupLaneId]);
      final header = shut.single;
      expect(header.isGroupHeader, isTrue);
      expect(
        header.groupEnabled,
        isNull,
        reason: 'a FIXED group has no bypass — the row speaker mutes it',
      );
      expect(header.showsKeyNavigator, isFalse);

      final open = seSoundPropertyLanes(
        const SeSound(),
        expanded: true,
        volumeAt: null,
      );
      expect(open.map((lane) => lane.laneId), [
        seSoundGroupLaneId,
        ...seSoundLaneDisplayOrder,
      ]);
    });

    test('the Volume reads in per cents and keys; the Pan reads its side '
        'and keys nothing', () {
      final sound = SeSound(
        pan: -0.3,
        volume: PropertyTrack<double>(keys: {4: const PropertyKey(0.5)}),
      );
      final lanes = {
        for (final lane in seSoundPropertyLanes(
          sound,
          expanded: true,
          volumeAt: sound.volumeAt,
        ))
          lane.laneId: lane,
      };
      final volume = lanes[seSoundVolumeLaneId]!;
      final pan = lanes[seSoundPanLaneId]!;

      expect(volume.valueLabel!(4), '50.00%');
      expect(volume.keyMarks.keys, [4]);
      expect(volume.curve, isNotNull, reason: 'the graph draws the Volume');
      expect(lanes[seSoundGroupLaneId]!.keyMarks.keys, [4], reason: 'union');
      expect(pan.valueLabel!(4), 'L30');
      expect(pan.keyMarks, isEmpty);
      expect(pan.showsKeyNavigator, isFalse, reason: 'one value (Q3)');
    });

    // 🗣️I-145-Q1 (유저 2026-10-30): 「따로 한 값 — 두 입구」.
    test('the Total reads its one value in per cents, between the Volume and '
        'the Pan, and keys nothing', () {
      final lanes = seSoundPropertyLanes(
        SeSound(
          totalVolume: 0.4,
          volume: PropertyTrack<double>(keys: {4: const PropertyKey(0.5)}),
        ),
        expanded: true,
        volumeAt: null,
      );
      expect(lanes.map((lane) => lane.laneId), [
        seSoundGroupLaneId,
        seSoundVolumeLaneId,
        seSoundTotalVolumeLaneId,
        seSoundPanLaneId,
      ]);
      final total = lanes.firstWhere(
        (lane) => lane.laneId == seSoundTotalVolumeLaneId,
      );
      expect(total.valueLabel!(4), '40.00%');
      expect(total.valueLabel!(9), '40.00%', reason: 'one value, any frame');
      expect(total.keyMarks, isEmpty);
      expect(total.showsKeyNavigator, isFalse);
      expect(total.curve, isNull, reason: 'nothing over time to draw');
      expect(total.scrubValue!('100.00%', const Offset(100000, 0)), '200.00%');
    });

    test('where the rail has nothing to read the volume in, it shows no '
        'value and no line', () {
      final volume = seSoundPropertyLanes(
        ramp(),
        expanded: true,
        volumeAt: null,
      ).firstWhere((lane) => lane.laneId == seSoundVolumeLaneId);
      expect(volume.valueLabel, isNull);
      expect(volume.curve, isNull);
    });

    test('the Volume holds its per cents as a share inside 0–200 %', () {
      expect(volumeLaneNumbers.shown(0.5), 50);
      expect(volumeLaneNumbers.held(80), 0.8);
      expect(volumeLaneNumbers.held(250), SeSound.maxVolume);
      expect(volumeLaneNumbers.held(-5), 0.0);
    });

    test('a pan prints as a side and a distance, and reads back the same way '
        'or as a signed per cent — whole per cents, inside the two '
        'sides', () {
      expect(panLaneText(0), 'C');
      expect(panLaneText(-0.5), 'L50');
      expect(panLaneText(0.37), 'R37');

      expect(panOfLaneText('L50'), -0.5);
      expect(panOfLaneText(' r20 '), 0.2);
      expect(panOfLaneText('c'), 0.0);
      expect(panOfLaneText('-30'), -0.3);
      expect(panOfLaneText('37.4'), 0.37, reason: 'whole per cents');
      expect(panOfLaneText('L150'), -1.0);
      expect(panOfLaneText('left'), isNull);
      expect(panOfLaneText(''), isNull);
    });

    test('a scrub stays inside each lane\'s range', () {
      expect(scrubSeSoundVolume('100.00%', const Offset(100000, 0)), '200.00%');
      expect(scrubSeSoundVolume('100.00%', const Offset(-100000, 0)), '0.00%');
      expect(scrubSeSoundVolume('loud', const Offset(10, 0)), isNull);
      expect(scrubSeSoundPan('C', const Offset(-100000, 0)), 'L100');
      expect(scrubSeSoundPan('R20', Offset.zero), 'R20');
      expect(scrubSeSoundPan('left', const Offset(10, 0)), isNull);
    });
  });

  group('the edits', () {
    test('the diamond keys what the row plays there, and takes a key away; '
        'the Pan has none to toggle', () {
      final keyed = seSoundWithLaneKeyToggled(
        ramp(),
        laneId: seSoundVolumeLaneId,
        frameIndex: 5,
      )!;
      expect(keyed.volume.keyAt(5)!.value, closeTo(0.5, 1e-9));
      expect(
        seSoundWithLaneKeyToggled(
          keyed,
          laneId: seSoundVolumeLaneId,
          frameIndex: 5,
        ),
        ramp(),
      );
      expect(
        seSoundWithLaneKeyToggled(
          const SeSound(),
          laneId: seSoundVolumeLaneId,
          frameIndex: 3,
        )!.volume.keyAt(3)!.value,
        1.0,
        reason: 'an unkeyed row plays as recorded',
      );
      expect(
        seSoundWithLaneKeyToggled(
          ramp(),
          laneId: seSoundPanLaneId,
          frameIndex: 5,
        ),
        isNull,
      );
      expect(
        seSoundWithLaneKeyToggled(
          ramp(),
          laneId: seSoundVolumeLaneId,
          frameIndex: -1,
        ),
        isNull,
      );
    });

    test('a typed Volume KEYS at the frame; a typed Pan is the row\'s one '
        'value; what is not a number changes nothing', () {
      SeSound? typed(String laneId, String input) =>
          seSoundWithLaneValueEdited(
            const SeSound(),
            laneId: laneId,
            frameIndex: 3,
            input: input,
          );

      expect(typed(seSoundVolumeLaneId, '80%')!.volume.keyAt(3)!.value, 0.8);
      expect(typed(seSoundVolumeLaneId, '250')!.volume.keyAt(3)!.value, 2.0);
      expect(typed(seSoundVolumeLaneId, 'loud'), isNull);
      expect(typed(seSoundPanLaneId, 'L30'), const SeSound(pan: -0.3));
      expect(typed(seSoundPanLaneId, 'left'), isNull);
      expect(typed(seSoundGroupLaneId, '50'), isNull);
      expect(
        typed(seSoundTotalVolumeLaneId, '80%'),
        const SeSound(totalVolume: 0.8),
        reason: 'the Total is the row\'s one value, as the Pan is',
      );
      expect(typed(seSoundTotalVolumeLaneId, '250')!.totalVolume, 2.0);
      expect(typed(seSoundTotalVolumeLaneId, 'loud'), isNull);
    });

    test('Reset puts a keyed Volume at 100 % where it stands — keeping its '
        'keys — and the Pan in the middle', () {
      final sound = SeSound(
        pan: -0.3,
        volume: PropertyTrack<double>(
          keys: {0: const PropertyKey(0.5), 6: const PropertyKey(0.2)},
        ),
      );

      final reset = seSoundWithGroupReset(sound, frameIndexes: [6])!;
      expect(reset.volume.keys.keys, [0, 6]);
      expect(reset.volume.keyAt(6)!.value, 1.0);
      expect(reset.volume.keyAt(0)!.value, 0.5);
      expect(reset.pan, 0.0);

      final spanned = seSoundWithGroupReset(
        sound,
        frameIndexes: [3, 6],
        keyedFramesOnly: true,
      )!;
      expect(
        spanned.volume.keys.keys,
        [0, 6],
        reason: 'a range resets the keys it covers, and makes none',
      );

      expect(
        seSoundWithGroupReset(
          const SeSound(pan: 0.4),
          frameIndexes: [2],
        ),
        const SeSound(),
        reason: 'an unkeyed Volume already plays at 100 %',
      );
      expect(
        seSoundWithGroupReset(
          const SeSound(totalVolume: 0.4),
          frameIndexes: [2],
        ),
        const SeSound(),
        reason: 'the Total goes back to 100 %',
      );
      expect(
        seSoundWithGroupReset(const SeSound(), frameIndexes: [2]),
        isNull,
      );
    });
  });

  group('the row\'s lane verbs', () {
    late EditorSessionManager s;
    late Layer se;

    setUp(() {
      s = EditorSessionManager(initialProject: createDefaultProject());
      se = s.activeTrack.seLayers.first;
    });
    tearDown(() => s.dispose());

    SeSound sound() =>
        s.activeTrack.seLayers.firstWhere((row) => row.id == se.id).seSound;

    void type(String laneId, int frame, String input) =>
        s.laneVerbs.setLaneValueAt(
          se.id,
          laneId,
          frame,
          input,
          frameIsGlobal: true,
          description: 'Edit',
          scaleLinked: false,
        );

    test('every SE row has the group, leading its twirl-down; a drawing row '
        'has none', () {
      final ids = timelineLanesForLayer(
        layer: s.layers.firstWhere((layer) => layer.id == se.id),
        session: s,
        expandedGroupKeys: {},
      ).map((lane) => lane.laneId).toList();
      expect(ids.first, seSoundGroupLaneId);
      expect(
        ids.indexOf(seSoundGroupLaneId),
        lessThan(ids.indexOf(seNameTagGroupLaneId)),
      );

      final cel = s.requireActiveCut.layers.firstWhere(
        (layer) => layer.kind == LayerKind.animation,
      );
      expect(
        timelineLanesForLayer(
          layer: cel,
          session: s,
          expandedGroupKeys: {},
        ).where((lane) => laneIsSeSound(lane.laneId)),
        isEmpty,
      );
    });

    test('🎯a typed Volume keys at the frame, a typed Pan sets the row — '
        'one undo each, and the row reads them back', () {
      type(seSoundVolumeLaneId, 4, '50');
      type(seSoundPanLaneId, 4, 'L30');

      expect(sound().volume.keys.keys, [4]);
      expect(sound().volumeAt(4), 0.5);
      expect(sound().pan, -0.3);
      expect(
        s.laneVerbs.laneValueAt(
          se.id,
          seSoundVolumeLaneId,
          4,
          frameIsGlobal: true,
        ),
        '50.00%',
      );
      expect(
        s.laneVerbs.isLaneKeyedAt(
          se.id,
          seSoundVolumeLaneId,
          4,
          frameIsGlobal: true,
        ),
        isTrue,
      );

      s.undo();
      expect(sound().pan, 0.0);
      expect(sound().volume.keys.keys, [4]);
      s.undo();
      expect(sound(), const SeSound());
    });

    test('the diamond keys the Volume there, and the header\'s Reset puts '
        'it back at 100 % — one undo', () {
      type(seSoundVolumeLaneId, 0, '20');
      s.laneVerbs.toggleLaneKeyAt(
        se.id,
        seSoundVolumeLaneId,
        8,
        frameIsGlobal: true,
        description: 'Key',
      );
      expect(sound().volume.keys.keys, [0, 8]);
      expect(sound().volumeAt(8), closeTo(0.2, 1e-9), reason: 'as it plays');

      s.selectFrameIndex(8);
      expect(s.laneVerbs.resetLaneGroup(se.id, seSoundGroupLaneId), isTrue);
      expect(sound().volumeAt(8), 1.0);
      expect(sound().volume.keys.keys, [0, 8], reason: 'keys are kept');
      s.undo();
      expect(sound().volumeAt(8), closeTo(0.2, 1e-9));
    });

    test('a Volume key copied goes down where the press stands, as every '
        'lane\'s does', () {
      final pill = TimelineToolbarPanelContext(s);
      type(seSoundVolumeLaneId, 3, '40');
      s.selectLayer(se.id);
      s.selectFrameIndex(3);
      s.standOnRow(LaneRowAddress(se.id, seSoundVolumeLaneId));
      pill.copyFrame();
      expect(s.keyClipboard.holdsKeys, isTrue, reason: '⛔전제');

      s.selectFrameIndex(9);
      s.standOnRow(LaneRowAddress(se.id, seSoundVolumeLaneId));
      pill.pasteIndependentFrame();

      expect(sound().volume.keys.keys, [3, 9]);
      expect(sound().volume.keyAt(9)!.value, closeTo(0.4, 1e-9));
    });
  });
}
