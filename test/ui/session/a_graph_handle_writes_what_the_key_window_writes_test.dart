import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/timeline_frame_range.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/lane_verbs.dart';
import 'package:anicel/src/ui/timeline/effect_lane_policy.dart'
    show effectGroupLaneId, effectLaneId;
import 'package:anicel/src/ui/timeline/timeline_drag_preview.dart';
import 'package:anicel/src/ui/timeline/transform_lane_policy.dart'
    show transformGroupHeaderLane;

/// I-89 ③ at the session: A HEADER GRAPH'S HANDLE WRITES WHAT THE KEY
/// WINDOW WRITES — the ease of the key it stands for and, when the lane
/// range holds that key, the same side of every key the range covers
/// (I-89-Q-b), by the window's own write: a range is a range whoever asks
/// (유저 2026-08-10: 「선택범위로 통하는 조작이 모두 다른것들이랑 동일한
/// 로직」).
///
/// The widget half — the handle drawn, pressed and pulled — is the graph's.
///
/// The collaborator the law lives in — named so `tool/mutation_run.dart`
/// runs this file for it.
LaneVerbs laneVerbsOf(EditorSessionManager session) => session.laneVerbs;

void main() {
  late EditorSessionManager session;
  late LaneVerbs laneVerbs;

  setUp(() {
    session = EditorSessionManager(initialProject: createDefaultProject());
    laneVerbs = laneVerbsOf(session);
  });

  tearDown(() => session.dispose());

  /// What a pulled leaving handle hands over: half the segment, at twice
  /// its average speed — an ease's numbers, never a kind.
  const pulled = KeySidesEdit(
    outgoing: KeySideEdit(influence: 0.5, speed: 2),
  );
  const pulledEase = EaseSide(influence: 0.5, speed: 2);

  Layer layerOf(LayerId id) => session.requireActiveCut.layers.byId(id)!;

  /// [id]'s Rotation keyed on 0, 4 and 8 and its Opacity on 0 and 8, each
  /// leaving at Easy Ease but Rotation's key on 4, which leaves straight.
  void keyTheRow(LayerId id) => laneVerbs.updateLayerTransformTrack(
    id,
    layerOf(id).transformTrack.copyWith(
      rotation: PropertyTrack<double>()
          .withKey(0, 0, outgoing: const EaseSide())
          .withKey(4, 20)
          .withKey(8, 40, outgoing: const EaseSide()),
      opacity: PropertyTrack<double>()
          .withKey(0, 1, outgoing: const EaseSide())
          .withKey(8, 0.5, outgoing: const EaseSide()),
    ),
  );

  KeyExit leaving(LayerId id, String lane, int frame) {
    final track = layerOf(id).transformTrack;
    final keys = lane == 'rotation' ? track.rotation : track.opacity;
    return keys.keyAt(frame)!.outgoing;
  }

  void select(
    LayerId id, {
    required List<String> lanes,
    required int start,
    required int end,
  }) => session.laneRangeSelection.value = TimelineLaneSelection(
    layerId: id,
    laneId: lanes.first,
    startIndex: start,
    endIndexExclusive: end,
    laneIds: lanes,
  );

  void pull(LayerId id, String lane, int frame, KeySidesEdit sides) =>
      laneVerbs.setLaneKeySidesAt(
        LaneRowAddress(id, lane),
        frame,
        sides,
        frameIsGlobal: false,
      );

  test('with nothing selected, a handle eases the key it stands for alone, '
      'in one undo step', () {
    final row = session.activeLayer!.id;
    keyTheRow(row);
    expect(laneVerbs.laneVerbRange, isNull, reason: '⛔전제: no range');

    pull(row, 'rotation', 0, pulled);

    expect(leaving(row, 'rotation', 0), pulledEase);
    expect(
      leaving(row, 'rotation', 8),
      const EaseSide(),
      reason: 'another key of the lane',
    );
    expect(
      leaving(row, 'opacity', 0),
      const EaseSide(),
      reason: 'another lane\'s key on the frame',
    );
    session.undo();
    expect(leaving(row, 'rotation', 0), const EaseSide());
  });

  test('a lane range that holds the key eases every key it covers — as the '
      'key window writes them, a straight side staying straight', () {
    final row = session.activeLayer!.id;
    keyTheRow(row);
    select(row, lanes: ['rotation', 'opacity'], start: 0, end: 9);

    pull(row, 'rotation', 0, pulled);

    for (final (lane, frame) in [
      ('rotation', 0),
      ('rotation', 8),
      ('opacity', 0),
      ('opacity', 8),
    ]) {
      expect(leaving(row, lane, frame), pulledEase, reason: '$lane $frame');
    }
    expect(
      leaving(row, 'rotation', 4),
      KeySide.linear,
      reason: 'a handle sets an ease\'s numbers and makes none',
    );
    final pulledTrack = layerOf(row).transformTrack;

    session.undo();
    expect(
      leaving(row, 'opacity', 8),
      const EaseSide(),
      reason: 'one step took them all',
    );
    laneVerbs.setLaneKeyTypeForSelection(const KeyTypePick(sides: pulled));
    expect(
      layerOf(row).transformTrack,
      pulledTrack,
      reason: 'the key window writes what the handle wrote',
    );
  });

  test('a range that does not hold the key leaves the handle its key '
      'alone — not its frames, not its lane, not its row', () {
    final row = session.activeLayer!.id;
    keyTheRow(row);
    session.layerStack.addLayer();
    final other = session.activeLayer!.id;
    expect(other, isNot(row), reason: '⛔전제: a second row');
    keyTheRow(other);

    for (final (lanes, start, at) in [
      (['rotation'], 4, row),
      (['opacity'], 0, row),
      (['rotation'], 0, other),
    ]) {
      select(at, lanes: lanes, start: start, end: 9);
      pull(row, 'rotation', 0, pulled);

      final range = '$lanes from $start on ${at == row ? 'the' : 'another'} '
          'row';
      expect(leaving(row, 'rotation', 0), pulledEase, reason: range);
      expect(leaving(row, 'rotation', 8), const EaseSide(), reason: range);
      expect(leaving(row, 'opacity', 0), const EaseSide(), reason: range);
      expect(leaving(other, 'rotation', 0), const EaseSide(), reason: range);
      session.undo();
    }
  });

  test('standing on the Transform header at the key\'s frame stands on a '
      'one-frame range: the handle eases each member\'s key there', () {
    final row = session.activeLayer!.id;
    keyTheRow(row);
    session.standOnRow(
      LaneRowAddress(row, transformGroupHeaderLane.laneId),
      frameIndex: 0,
    );
    expect(
      laneVerbs.laneVerbRange,
      TimelineLaneSelection(
        layerId: row,
        laneId: transformGroupHeaderLane.laneId,
        startIndex: 0,
        endIndexExclusive: 1,
      ),
      reason: '⛔전제: the range the key window would type',
    );

    pull(row, 'rotation', 0, pulled);

    expect(leaving(row, 'rotation', 0), pulledEase);
    expect(leaving(row, 'opacity', 0), pulledEase);
    expect(leaving(row, 'rotation', 8), const EaseSide());
  });

  test('an effect\'s header range holds its parameters\' keys', () {
    final row = session.activeLayer!.id;
    session.effectsAndFx.addEffectToActiveLayer(EffectKind.blur);
    final blur = layerOf(row).effects.single;
    PropertyTrack<double> eased(double to) => PropertyTrack<double>()
        .withKey(0, 0, outgoing: const EaseSide())
        .withKey(8, to);
    session.effectsAndFx.updateLayerEffects(row, [
      blur
          .withParameter('blurX', EffectParameter(track: eased(16)))
          .withParameter('blurY', EffectParameter(track: eased(4))),
    ]);
    KeyExit blurLeaving(String parameter) => layerOf(
      row,
    ).effects.single.parameterOf(parameter).track.keyAt(0)!.outgoing;

    pull(row, effectLaneId(blur.id, 'blurX'), 0, pulled);
    expect(blurLeaving('blurX'), pulledEase);
    expect(blurLeaving('blurY'), const EaseSide(), reason: 'nothing selected');
    session.undo();

    select(row, lanes: [effectGroupLaneId(blur.id)], start: 0, end: 9);
    pull(row, effectLaneId(blur.id, 'blurX'), 0, pulled);
    expect(blurLeaving('blurX'), pulledEase);
    expect(blurLeaving('blurY'), pulledEase, reason: 'the header holds it');
  });

  test('a handle in flight is shown, not written; let go of, it is dropped; '
      'dropped on, it writes what it showed', () {
    final row = session.activeLayer!.id;
    keyTheRow(row);
    final undoable = session.historyManager.canUndo;
    void inFlight() => laneVerbs.previewLaneKeySidesAt(
      LaneRowAddress(row, 'rotation'),
      0,
      pulled,
      frameIsGlobal: false,
    );

    inFlight();
    final preview = session.dragPreview.value;
    expect(preview, isA<LaneEditPreview>());
    final shown = (preview! as LaneEditPreview).row!.transformTrack;
    expect(shown.rotation.keyAt(0)!.outgoing, pulledEase);
    expect(leaving(row, 'rotation', 0), const EaseSide(), reason: 'shown');
    expect(session.historyManager.canUndo, undoable, reason: 'not written');

    laneVerbs.endLaneEditPreview();
    expect(session.dragPreview.value, isNull);
    expect(leaving(row, 'rotation', 0), const EaseSide());

    inFlight();
    pull(row, 'rotation', 0, pulled);
    expect(session.dragPreview.value, isNull, reason: 'dropped with it');
    expect(
      layerOf(row).transformTrack,
      shown,
      reason: 'ONE computation: the drop writes the preview\'s track',
    );
  });

  // 🗣️F-389 (유저 2026-10-17): 「키에 관한 리니어 등 타입 편집, 세기편집이
  // 라이브로 화면이나 그래프에도 보이도록」.
  test('the key window\'s pick is shown before it is written, by the write '
      'its OK makes — as a handle in flight is', () {
    final row = session.activeLayer!.id;
    keyTheRow(row);
    select(row, lanes: ['rotation', 'opacity'], start: 0, end: 9);
    final undoable = session.historyManager.canUndo;
    const pick = KeyTypePick(sides: pulled);

    laneVerbs.previewLaneKeyTypeForSelection(pick);
    final preview = session.dragPreview.value;
    expect(preview, isA<LaneEditPreview>());
    final shown = (preview! as LaneEditPreview).row!.transformTrack;
    expect(shown.opacity.keyAt(8)!.outgoing, pulledEase);
    expect(leaving(row, 'opacity', 8), const EaseSide(), reason: 'shown');
    expect(session.historyManager.canUndo, undoable, reason: 'not written');

    laneVerbs.previewLaneKeyTypeForSelection(const KeyTypePick());
    expect(
      session.dragPreview.value,
      isNull,
      reason: 'nothing picked shows the row as it stands',
    );

    laneVerbs.previewLaneKeyTypeForSelection(pick);
    laneVerbs.setLaneKeyTypeForSelection(pick);
    expect(session.dragPreview.value, isNull, reason: 'dropped with it');
    expect(
      layerOf(row).transformTrack,
      shown,
      reason: 'ONE computation: the OK writes what the pick showed',
    );
  });

  test('a track-owned SE row on the SECOND cut: the handle names its key by '
      'its rail\'s frame, the cut\'s or the track\'s, and the key is the '
      'track\'s', () {
    session.cutVerbs.createCut();
    final cutStart = session.activeCutGlobalStartFrame;
    expect(cutStart, greaterThan(0), reason: '⛔전제: a second cut');
    final se = session.activeTrack.seLayers.first.id;
    for (final (frame, value) in [(2, '10'), (6, '20')]) {
      laneVerbs.setLaneValueAt(
        se,
        'rotation',
        frame,
        value,
        frameIsGlobal: false,
        description: 'Set Rotation',
        scaleLinked: false,
      );
    }
    select(se, lanes: ['rotation'], start: cutStart + 2, end: cutStart + 3);
    laneVerbs.setLaneKeyTypeForSelection(
      const KeyTypePick(
        sides: KeySidesEdit(outgoing: KeySideEdit(side: EaseSide())),
      ),
    );
    session.laneRangeSelection.value = null;
    KeyExit seLeaving() => session.activeTrack.seLayers.first.transformTrack
        .rotation
        .keyAt(cutStart + 2)!
        .outgoing;
    expect(seLeaving(), const EaseSide(), reason: '⛔전제: an eased key');

    pull(se, 'rotation', 2, pulled);
    expect(seLeaving(), pulledEase, reason: 'the cut\'s rail');

    laneVerbs.setLaneKeySidesAt(
      LaneRowAddress(se, 'rotation'),
      cutStart + 2,
      const KeySidesEdit(outgoing: KeySideEdit(influence: 0.25)),
      frameIsGlobal: true,
    );
    expect(
      seLeaving(),
      const EaseSide(influence: 0.25, speed: 2),
      reason: 'the storyboard\'s rail',
    );
  });
}
