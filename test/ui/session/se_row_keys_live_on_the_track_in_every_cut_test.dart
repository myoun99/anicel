import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/se_name_tag.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/lane_verbs.dart';
import 'package:anicel/src/ui/timeline/property_lane_model.dart'
    show laneGroupKey;
import 'package:anicel/src/ui/timeline/se_name_tag_lane_policy.dart'
    show seNameTagGroupLaneId, seNameTagSizeLaneId;
import 'package:anicel/src/ui/timeline/timeline_lane_provider.dart'
    show timelineLanesForLayer;
import 'package:anicel/src/ui/timeline/transform_lane_editing.dart'
    show transformTrackWithRotationDragged;
import 'package:anicel/src/ui/timeline/transform_lane_policy.dart'
    show transformGroupHeaderLane;

/// F-102 (유저 2026-09-12): 「컷1에서 se의 트랜스폼으로 포지션 조정했는데, 그게
/// 다른 컷2에서 값이 안바뀌어 있고 초기값인 상태로 보임. 아마 se든 아니든
/// 카메라든 fx든 같은 상황 있을텐데 조사해서 법 하나로 통일해서 해결」 — and
/// the law they gave it (09-15): 「글로벌트랙은 fx든뭐던 로컬에선 글로벌을
/// 투영해서 보여주도록? 물론 로컬에서도 조작은 가능하지만」.
///
/// An SE row is ONE row on its track's global axis; a cut shows a projection
/// of it. So the value a key made in cut 1 holds is what cut 2 shows, and
/// every way of keying the row from cut 2 — the lane navigator's ◆, a typed
/// value, a canvas handle, the storyboard's rail — writes that one row and
/// leaves cut 1's key where it was.
///
/// The collaborator both halves of the projection live in — named so
/// `tool/mutation_run.dart` runs this file for it.
LaneVerbs laneVerbsOf(EditorSessionManager session) => session.laneVerbs;

void main() {
  late EditorSessionManager session;
  late Layer se;
  late int cut2Start;

  setUp(() {
    session = EditorSessionManager(initialProject: createDefaultProject());
    se = session.activeTrack.seLayers.first;
    // The key cut 1 made: Rotation 30° at global frame 2.
    session.updateLayerTransformTrack(
      se.id,
      TransformTrack.empty().copyWith(
        rotation: PropertyTrack(keys: {2: const PropertyKey(30.0)}),
      ),
    );
    session.cutVerbs.createCut();
    cut2Start = session.activeCutGlobalStartFrame;
    expect(
      cut2Start,
      greaterThan(2),
      reason: 'fixture premise: the second cut, active, starts after the key',
    );
  });
  tearDown(() => session.dispose());

  PropertyTrack<double> rotationOnTheRow() =>
      session.activeTrack.seLayers.first.transformTrack.rotation;

  test('🚨in cut 2, S1\'s Rotation lane SHOWS the value cut 1 keyed — read off '
      'the track\'s row, while the key itself draws no mark on this rail', () {
    final lanes = timelineLanesForLayer(
      layer: session.layerById(se.id)!,
      session: session,
      expandedGroupKeys: {laneGroupKey(se.id, transformGroupHeaderLane.laneId)},
    );
    final rotation = lanes.singleWhere((lane) => lane.laneId == 'rotation');
    expect(rotation.valueLabel!(0), '30°');
    expect(
      rotation.keyedFrames,
      isEmpty,
      reason: 'the key is cut 1\'s: the cut-2 rail has no frame for it',
    );
  });

  test('🚨in cut 2, S1\'s name tag Size lane SHOWS the size cut 1 keyed', () {
    session.cutCommandCoordinator.setSeNameTag(
      layerId: se.id,
      seNameTag: SeNameTag(
        track: SeNameTagTrack(
          fontSize: PropertyTrack(keys: {2: const PropertyKey(20.0)}),
        ),
      ),
    );
    final lanes = timelineLanesForLayer(
      layer: session.layerById(se.id)!,
      session: session,
      expandedGroupKeys: {laneGroupKey(se.id, seNameTagGroupLaneId)},
    );
    final size = lanes.singleWhere(
      (lane) => lane.laneId == seNameTagSizeLaneId,
    );
    expect(size.valueLabel!(0), '20');
  });

  test('🚨the navigator ◆ in cut 2 keys the row at its GLOBAL frame, frozen at '
      'the value it holds there, and cut 1 keeps its key', () {
    laneVerbsOf(session).toggleLaneKeyAt(
      se.id,
      'rotation',
      3,
      frameIsGlobal: false,
      description: 'Rotation keyframe at frame 4',
    );
    final lane = rotationOnTheRow();
    expect(lane.keys.keys.toList(), [2, cut2Start + 3]);
    expect(
      lane.keyAt(cut2Start + 3)!.value,
      30,
      reason: 'frozen at what the row resolves there, not the default',
    );

    session.undo();
    expect(rotationOnTheRow().keys.keys.toList(), [2], reason: 'one undo');
  });

  test('a value typed in cut 2 lands at the GLOBAL frame, and cut 1 keeps its '
      'key', () {
    laneVerbsOf(session).setLaneValueAt(
      se.id,
      'rotation',
      3,
      '-45°',
      frameIsGlobal: false,
      description: 'Set Rotation at frame 4',
    );
    final lane = rotationOnTheRow();
    expect(lane.keys.keys.toList(), [2, cut2Start + 3]);
    expect(lane.keyAt(cut2Start + 3)!.value, -45);
    expect(lane.keyAt(2)!.value, 30);
  });

  test('the storyboard states its frames GLOBALLY — the key lands where it '
      'says, not shifted by the cut start again', () {
    laneVerbsOf(session).toggleLaneKeyAt(
      se.id,
      'rotation',
      cut2Start + 5,
      frameIsGlobal: true,
      description: 'Rotation keyframe',
    );
    expect(rotationOnTheRow().keys.keys.toList(), [2, cut2Start + 5]);
  });

  test('🚨a canvas handle dragged in cut 2 keys the row at the playhead on its '
      'GLOBAL axis, and cut 1 keeps its key', () {
    session.selectFrameIndex(4);
    laneVerbsOf(session).editLayerTransformAtPlayhead(
      se.id,
      (track, frameIndex) => transformTrackWithRotationDragged(
        track,
        frameIndex: frameIndex,
        rotationDegrees: 90,
      ),
      description: 'Rotate S1',
    );
    final lane = rotationOnTheRow();
    expect(lane.keys.keys.toList(), [2, cut2Start + 4]);
    expect(lane.keyAt(cut2Start + 4)!.value, 90);
  });

  test('🚨a name tag member keyed in cut 2 lands at its GLOBAL frame, frozen '
      'at the value it holds, and cut 1 keeps its key', () {
    session.cutCommandCoordinator.setSeNameTag(
      layerId: se.id,
      seNameTag: SeNameTag(
        track: SeNameTagTrack(
          fontSize: PropertyTrack(keys: {2: const PropertyKey(20.0)}),
        ),
      ),
    );
    laneVerbsOf(session).toggleLaneKeyAt(
      se.id,
      seNameTagSizeLaneId,
      3,
      frameIsGlobal: false,
      description: 'Size keyframe at frame 4',
    );
    final sizes =
        session.activeTrack.seLayers.first.seNameTag!.track!.fontSize;
    expect(sizes.keys.keys.toList(), [2, cut2Start + 3]);
    expect(sizes.keyAt(cut2Start + 3)!.value, 20);
  });
}
