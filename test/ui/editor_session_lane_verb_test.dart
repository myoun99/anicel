import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/transform_lane_editing.dart'
    show transformLaneKeyFrames;
import 'package:anicel/src/ui/timeline/transform_lane_policy.dart'
    show transformGroupHeaderLane;

/// R10 #19: the row you are STANDING on is the verb's subject.
///
/// The user's ask: make fx/property rows selectable, and adding a frame
/// while one is the subject should key THAT property — without the layer
/// ceasing to be the drawing target, which is the hazard that made it
/// impossible before ("현재 레이어가 선택상태인게 풀리고 … 그림 그리지
/// 못하는 상태가 되는거지").
void main() {
  EditorSessionManager sessionOnLane(String laneId) {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    final layer = session.requireActiveCut.layers.first;
    session.selectLayer(layer.id);
    session.selectFrameIndex(3);
    session.selectRow(LaneRowAddress(layer.id, laneId));
    return session;
  }

  Set<int> keysOf(EditorSessionManager session, String laneId) =>
      transformLaneKeyFrames(
        session.requireActiveCut.layers.first.transformTrack,
        laneId,
      );

  test('standing on a property row does NOT cost the drawing target — the '
      'whole reason this could not be done before', () {
    final session = sessionOnLane('position');
    addTearDown(session.dispose);

    expect(session.currentRow, isA<LaneRowAddress>());
    expect(
      session.activeLayerId,
      session.requireActiveCut.layers.first.id,
      reason: 'the layer you draw on is a different question',
    );
  });

  test('Add keys THAT property at the playhead — no span needed', () {
    final session = sessionOnLane('position');
    addTearDown(session.dispose);
    expect(keysOf(session, 'position'), isEmpty);

    expect(session.createInstancesForSelection(), isTrue);

    expect(keysOf(session, 'position'), {3});
    expect(
      keysOf(session, 'scale'),
      isEmpty,
      reason: 'only the property you are standing on',
    );
  });

  test('on a group HEADER, Add keys every member — the camera row\'s pose '
      'key, reached by the same code', () {
    final session = sessionOnLane(transformGroupHeaderLane.laneId);
    addTearDown(session.dispose);

    expect(session.createInstancesForSelection(), isTrue);

    expect(keysOf(session, 'position'), {3});
    expect(keysOf(session, 'scale'), {3});
    expect(keysOf(session, 'rotation'), {3});
  });

  test('Delete follows the same rule: the key under the playhead goes, not '
      'a cel', () {
    final session = sessionOnLane('position');
    addTearDown(session.dispose);
    session.createInstancesForSelection();
    expect(keysOf(session, 'position'), {3});

    expect(session.canDeleteCellAtCurrentFrame, isTrue);
    session.deleteCellAtCurrentFrame();

    expect(keysOf(session, 'position'), isEmpty);
  });

  test('with no key there, Delete does not claim the press — it falls '
      'through to whatever the cell path would do', () {
    final session = sessionOnLane('position');
    addTearDown(session.dispose);

    expect(
      session.canDeleteCellAtCurrentFrame,
      isFalse,
      reason: 'an empty property row has nothing to delete, and must not '
          'pretend otherwise',
    );
  });

  test('back on the LAYER row, Add is a cel again', () {
    final session = sessionOnLane('position');
    addTearDown(session.dispose);
    final layerId = session.requireActiveCut.layers.first.id;

    session.selectLayer(layerId);
    expect(session.currentRow, LayerRowAddress(layerId));
    expect(
      session.createInstancesForSelection(),
      isFalse,
      reason: 'no selection and no lane subject: the Add button dispatches '
          'on the layer KIND, as it always did',
    );
    expect(keysOf(session, 'position'), isEmpty);
  });
}
