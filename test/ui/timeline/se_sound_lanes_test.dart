import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/se_sound.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/property_lane_model.dart';
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
/// the Pan, keyed as the Volume is — 🗣️audio-fx-grows-like-the-pros-Q7
/// (유저 2026-11-17): 「音量처럼 키를 단다」. ↩️Q3's one value.
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
        soundAt: null,
      );
      expect(shut.map((lane) => lane.laneId), [seSoundGroupLaneId]);
      final header = shut.single;
      expect(header.isGroupHeader, isTrue);
      expect(
        header.groupEnabled,
        isTrue,
        reason: 'its fx switch, as every fx group\'s — ↩️none, 「the row '
            'speaker mutes it」, till audio-fx-grows-like-the-pros-Q6',
      );
      expect(header.showsKeyNavigator, isFalse);

      final open = seSoundPropertyLanes(
        const SeSound(),
        expanded: true,
        soundAt: null,
      );
      expect(open.map((lane) => lane.laneId), [
        seSoundGroupLaneId,
        ...seSoundLaneDisplayOrder,
      ]);
    });

    test('the Volume reads in per cents and the Pan its side, both where '
        'the rail reads the row, and both key — the header shows the union '
        'of their keys', () {
      final sound = SeSound(
        pan: PropertyTrack<double>(
          keys: {2: const PropertyKey(-1.0), 12: const PropertyKey(0.0)},
        ),
        volume: PropertyTrack<double>(
          keys: {0: const PropertyKey(0.0), 10: const PropertyKey(1.0)},
        ),
      );
      final lanes = {
        for (final lane in seSoundPropertyLanes(
          sound,
          expanded: true,
          // The rail two frames behind the row's own.
          soundAt: (time) => (sound: sound, time: time + 2),
        ))
          lane.laneId: lane,
      };
      final volume = lanes[seSoundVolumeLaneId]!;
      final pan = lanes[seSoundPanLaneId]!;

      expect(volume.valueLabel!(2), '40.00%');
      expect(volume.keyMarks.keys, [0, 10]);
      expect(volume.curve!.at(2).single, closeTo(40, 1e-9));
      expect(pan.valueLabel!(4), 'L60');
      expect(pan.keyMarks.keys, [2, 12]);
      expect(pan.curve!.at(4).single, closeTo(-60, 1e-9));
      expect(pan.showsKeyNavigator, isTrue, reason: '↩️none while one value');
      expect(lanes[seSoundGroupLaneId]!.keyMarks.keys.toSet(), {0, 2, 10, 12});
    });

    // 🗣️I-177 (유저 2026-11-17): 「s행 오디오fx에 총 볼륨 똑같은거있는데 이건
    // s행의 막대로서만 있도록. fx값으로선 존재안함」. ↩️I-145-Q1 「따로 한 값 —
    // 두 입구」 laid a Total lane between the Volume and the Pan.
    test('the group holds no Total — whatever the row\'s Total, its lanes '
        'are the Volume and the Pan', () {
      final lanes = seSoundPropertyLanes(
        const SeSound(totalVolume: 0.4),
        expanded: true,
        soundAt: null,
      );
      expect(lanes.map((lane) => lane.laneId), [
        seSoundGroupLaneId,
        seSoundVolumeLaneId,
        seSoundPanLaneId,
      ]);
    });

    test('where the rail has nothing to read the sound in, its lanes show no '
        'value and no line', () {
      final members = seSoundPropertyLanes(
        ramp(),
        expanded: true,
        soundAt: null,
      ).where((lane) => !lane.isGroupHeader);
      expect(members, hasLength(seSoundLaneDisplayOrder.length));
      for (final lane in members) {
        expect(lane.valueLabel, isNull, reason: lane.laneId);
        expect(lane.curve, isNull, reason: lane.laneId);
      }
    });

    test('the Volume holds its per cents as a share inside 0–200 %', () {
      expect(volumeLaneNumbers.shown(0.5), 50);
      expect(volumeLaneNumbers.held(80), 0.8);
      expect(volumeLaneNumbers.held(250), SeSound.maxVolume);
      expect(volumeLaneNumbers.held(-5), 0.0);
    });

    test('the Pan holds its per cents as a share inside the two sides, '
        'whole per cents, as it is typed', () {
      expect(panLaneNumbers.shown(-0.5), -50);
      expect(panLaneNumbers.held(37.4), 0.37);
      expect(panLaneNumbers.held(150), 1.0);
      expect(panLaneNumbers.held(-150), -1.0);
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
    test('the diamond keys what the row plays there, and takes a key away — '
        'the Pan as the Volume', () {
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
      final swept = SeSound(
        pan: PropertyTrack<double>(
          keys: {0: const PropertyKey(-1.0), 10: const PropertyKey(0.0)},
        ),
      );
      final panKeyed = seSoundWithLaneKeyToggled(
        swept,
        laneId: seSoundPanLaneId,
        frameIndex: 5,
      )!;
      expect(panKeyed.pan.keyAt(5)!.value, closeTo(-0.5, 1e-9));
      expect(
        seSoundWithLaneKeyToggled(
          panKeyed,
          laneId: seSoundPanLaneId,
          frameIndex: 5,
        ),
        swept,
      );
      expect(
        seSoundWithLaneKeyToggled(
          ramp(),
          laneId: seSoundGroupLaneId,
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

    test('a typed Volume or Pan KEYS at the frame; what is not a number '
        'changes nothing', () {
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
      expect(typed(seSoundPanLaneId, 'L30')!.pan.keyAt(3)!.value, -0.3);
      expect(typed(seSoundPanLaneId, 'left'), isNull);
      expect(typed(seSoundGroupLaneId, '50'), isNull);
    });

    test('Reset puts a keyed Volume at 100 % and a keyed Pan in the middle '
        'where they stand — keeping their keys', () {
      final sound = SeSound(
        pan: PropertyTrack<double>(
          keys: {0: const PropertyKey(-0.3), 6: const PropertyKey(0.4)},
        ),
        volume: PropertyTrack<double>(
          keys: {0: const PropertyKey(0.5), 6: const PropertyKey(0.2)},
        ),
      );

      final reset = seSoundWithGroupReset(sound, frameIndexes: [6])!;
      expect(reset.volume.keys.keys, [0, 6]);
      expect(reset.volume.keyAt(6)!.value, 1.0);
      expect(reset.volume.keyAt(0)!.value, 0.5);
      expect(reset.pan.keys.keys, [0, 6]);
      expect(reset.pan.keyAt(6)!.value, 0.0);
      expect(reset.pan.keyAt(0)!.value, -0.3);

      final spanned = seSoundWithGroupReset(
        sound,
        frameIndexes: [3, 6],
        keyedFramesOnly: true,
      )!;
      for (final lane in [spanned.volume, spanned.pan]) {
        expect(
          lane.keys.keys,
          [0, 6],
          reason: 'a range resets the keys it covers, and makes none',
        );
      }

      expect(
        seSoundWithGroupReset(const SeSound(), frameIndexes: [2]),
        isNull,
        reason: 'an unkeyed Volume and Pan already play at their rest',
      );
      // 🗣️I-177: the Total is the S row's bar, no value of this group.
      final kept = seSoundWithGroupReset(
        SeSound(
          pan: PropertyTrack<double>(keys: {2: const PropertyKey(0.4)}),
          totalVolume: 0.4,
        ),
        frameIndexes: [2],
      )!;
      expect(kept.panAt(2), 0.0);
      expect(kept.totalVolume, 0.4, reason: 'the Reset leaves the Total');
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

    test('🎯a typed Volume and a typed Pan each key at the frame — one undo '
        'each, and the row reads them back', () {
      type(seSoundVolumeLaneId, 4, '50');
      type(seSoundPanLaneId, 4, 'L30');

      expect(sound().volume.keys.keys, [4]);
      expect(sound().volumeAt(4), 0.5);
      expect(sound().pan.keys.keys, [4]);
      expect(sound().panAt(4), -0.3);
      for (final (laneId, shown) in [
        (seSoundVolumeLaneId, '50.00%'),
        (seSoundPanLaneId, 'L30'),
      ]) {
        expect(
          s.laneVerbs.laneValueAt(se.id, laneId, 4, frameIsGlobal: true),
          shown,
        );
        expect(
          s.laneVerbs.isLaneKeyedAt(se.id, laneId, 4, frameIsGlobal: true),
          isTrue,
          reason: laneId,
        );
      }

      s.undo();
      expect(sound().isPanKeyed, isFalse);
      expect(sound().volume.keys.keys, [4]);
      s.undo();
      expect(sound(), const SeSound());
    });

    test('the diamond keys the Volume and the Pan there, and the header\'s '
        'Reset puts them back — 100 %, the middle — one undo', () {
      type(seSoundVolumeLaneId, 0, '20');
      type(seSoundPanLaneId, 0, 'R40');
      for (final laneId in seSoundLaneDisplayOrder) {
        s.laneVerbs.toggleLaneKeyAt(
          se.id,
          laneId,
          8,
          frameIsGlobal: true,
          description: 'Key',
        );
      }
      expect(sound().volume.keys.keys, [0, 8]);
      expect(sound().volumeAt(8), closeTo(0.2, 1e-9), reason: 'as it plays');
      expect(sound().pan.keys.keys, [0, 8]);
      expect(sound().panAt(8), closeTo(0.4, 1e-9), reason: 'as it plays');

      s.selectFrameIndex(8);
      expect(s.laneVerbs.resetsLaneGroup(se.id, seSoundGroupLaneId), isTrue);
      expect(s.laneVerbs.resetLaneGroup(se.id, seSoundGroupLaneId), isTrue);
      expect(
        s.laneVerbs.resetsLaneGroup(se.id, seSoundGroupLaneId),
        isFalse,
        reason: 'back at their rest there, its Reset is out (F-583)',
      );
      expect(sound().volumeAt(8), 1.0);
      expect(sound().panAt(8), 0.0);
      expect(sound().volume.keys.keys, [0, 8], reason: 'keys are kept');
      expect(sound().pan.keys.keys, [0, 8], reason: 'keys are kept');
      s.undo();
      expect(sound().volumeAt(8), closeTo(0.2, 1e-9));
      expect(sound().panAt(8), closeTo(0.4, 1e-9));
    });

    test('a Volume or a Pan key copied goes down where the press stands, as '
        'every lane\'s does', () {
      final pill = TimelineToolbarPanelContext(s);
      for (final (laneId, typed) in [
        (seSoundVolumeLaneId, '40'),
        (seSoundPanLaneId, 'L40'),
      ]) {
        type(laneId, 3, typed);
        s.selectLayer(se.id);
        s.selectFrameIndex(3);
        s.standOnRow(LaneRowAddress(se.id, laneId));
        pill.copyFrame();
        expect(s.keyClipboard.holdsKeys, isTrue, reason: '⛔전제');

        s.selectFrameIndex(9);
        s.standOnRow(LaneRowAddress(se.id, laneId));
        pill.pasteIndependentFrame();
      }

      expect(sound().volume.keys.keys, [3, 9]);
      expect(sound().volume.keyAt(9)!.value, closeTo(0.4, 1e-9));
      expect(sound().pan.keys.keys, [3, 9]);
      expect(sound().pan.keyAt(9)!.value, closeTo(-0.4, 1e-9));
    });

    // 🗣️key-paste-across-lanes-keeps-the-raw-value-Q1 (유저 2026-10-22):
    // 「숫자끼리는 숫자 그대로」 — the number a lane shows, held as the lane it
    // goes on holds a number typed.
    test('a Volume key goes on the Pan as the per cent it shows, held inside '
        'the two sides — and a Pan key on the Volume as its own', () {
      final pill = TimelineToolbarPanelContext(s);
      type(seSoundVolumeLaneId, 3, '150');
      type(seSoundPanLaneId, 5, 'R40');
      s.selectLayer(se.id);
      void carried(String from, int at, String onto, int to) {
        s.selectFrameIndex(at);
        s.standOnRow(LaneRowAddress(se.id, from));
        pill.copyFrame();
        s.selectFrameIndex(to);
        s.standOnRow(LaneRowAddress(se.id, onto));
        pill.pasteIndependentFrame();
      }

      carried(seSoundVolumeLaneId, 3, seSoundPanLaneId, 9);
      carried(seSoundPanLaneId, 5, seSoundVolumeLaneId, 12);

      expect(sound().pan.keyAt(9)!.value, 1.0, reason: '150 is R100 at most');
      expect(sound().volume.keyAt(12)!.value, closeTo(0.4, 1e-9));
    });

    // 🗣️audio-fx-grows-like-the-pros-Q4 note 「뭐든 fx라면 있어야」 · -Q6
    // 「音量 키 · パン 을 건너뛴다」.
    test('🎯the header wears an fx switch as every fx group does: off, the '
        'keys and the pan stay, the row\'s master reads it and sets it', () {
      type(seSoundVolumeLaneId, 4, '50');
      type(seSoundPanLaneId, 4, 'L30');
      PropertyLaneRow header() => timelineLanesForLayer(
        layer: s.activeTrack.seLayers.firstWhere((row) => row.id == se.id),
        session: s,
        expandedGroupKeys: {},
      ).firstWhere((lane) => lane.laneId == seSoundGroupLaneId);
      expect(header().groupEnabled, isTrue);

      s.laneVerbs.toggleLaneGroupEnabled(
        se.id,
        seSoundGroupLaneId,
        description: 'Toggle',
      );
      expect(sound().enabled, isFalse);
      expect(header().groupEnabled, isFalse);
      expect(s.laneVerbs.isLaneGroupOn(se.id, seSoundGroupLaneId), isFalse);
      expect(sound().volume.keys.keys, [4], reason: 'kept');
      expect(sound().pan.keys.keys, [4], reason: 'kept');
      expect(s.effectsAndFx.layerFxState(se.id), isNot(LayerFxState.on));

      s.effectsAndFx.toggleLayerFx(se.id);
      s.effectsAndFx.toggleLayerFx(se.id);
      expect(sound().enabled, isTrue, reason: 'the master turns it on');
      s.effectsAndFx.toggleLayerFx(se.id);
      expect(sound().enabled, isFalse, reason: 'and off');
      expect(s.effectsAndFx.layerFxState(se.id), LayerFxState.off);
    });
  });
}
