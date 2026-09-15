import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/delete_subject.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/cell_verbs.dart';
import 'package:anicel/src/ui/timeline/effect_lane_policy.dart'
    show effectGroupLaneId, effectLaneId;
import 'package:anicel/src/ui/timeline/transform_lane_editing.dart'
    show transformLaneKeyFrames;
import 'package:anicel/src/ui/timeline/transform_lane_policy.dart'
    show transformGroupHeaderLane;

/// F-87 (유저 2026-09-12): 「공용 삭제버튼을 서있는곳 위치에 따라 나누도록.
/// 트랜스폼 헤더에 서있으면 지금처럼 해당 키 삭제 그대로 두는데, 키가
/// 없을때 삭제하면 레이어의 프레임이 삭제됨. 이런거 없도록. 법 최대한 하나로
/// 통일 / 그리고 fx 헤더 선택범위로 선택한채로 삭제누르면 해당 fx 삭제. 그리고
/// fx버튼에 있는 해당 fx 삭제버튼은 필요없으니 삭제하고 관련로직 싹 제거」
///
/// A LANE row is the subject of the one Delete exactly as a cell band is
/// (`cellSelectionClaimsSubject`): what it holds is what the press may take,
/// and with nothing there the answer is nothing — never the cel of the layer
/// the lane belongs to.
///
/// The collaborator the delete lives in — named so `tool/mutation_run.dart`
/// runs this file for it.
CellVerbs cellVerbsOf(EditorSessionManager session) => session.cells;

void main() {
  late EditorSessionManager session;
  late Layer before;

  setUp(() {
    session = EditorSessionManager(initialProject: createDefaultProject());
    final layer = session.requireActiveCut.layers.first;
    session.selectLayer(layer.id);
    session.selectFrameIndex(3);
    session.createDrawingAtCurrentFrame();
    before = session.requireActiveCut.layers.first;
    expect(
      before.timeline,
      isNotEmpty,
      reason: 'fixture premise: a drawing stands under the playhead',
    );
  });
  tearDown(() => session.dispose());

  Layer now() => session.requireActiveCut.layers.firstWhere(
    (layer) => layer.id == before.id,
  );

  void standOn(String laneId) =>
      session.selectRow(LaneRowAddress(before.id, laneId));

  void expectTheDrawingStays(String why) {
    expect(now().timeline, before.timeline, reason: why);
    expect(
      now().frames.map((frame) => frame.id),
      before.frames.map((frame) => frame.id),
      reason: why,
    );
  }

  test('🚨on the Transform header with no key at the playhead, Delete has '
      'nothing to take — and the drawing under it stays', () {
    standOn(transformGroupHeaderLane.laneId);

    expect(
      session.deleteSubjectFor(cutsAreThisPanels: false),
      DeleteSubject.nothing,
    );
    session.deleteSelectionSubject(cutsAreThisPanels: false);

    expectTheDrawingStays('「키가 없을때 삭제하면 레이어의 프레임이 삭제됨. 이런거 없도록」');
  });

  test('🚨on a property lane with no key there, the same', () {
    standOn('position');

    expect(
      session.deleteSubjectFor(cutsAreThisPanels: false),
      DeleteSubject.nothing,
    );
    session.deleteSelectionSubject(cutsAreThisPanels: false);

    expectTheDrawingStays('「법 최대한 하나로 통일」 — every lane row, not the header alone');
  });

  test('on the Transform header ON a key, Delete takes the keys and the '
      'drawing stays — today\'s good half, kept', () {
    standOn(transformGroupHeaderLane.laneId);
    expect(
      session.cellInstances.createInstancesForSelection(),
      isTrue,
      reason: 'premise: the header keys every member at the playhead',
    );
    expect(transformLaneKeyFrames(now().transformTrack, 'position'), {3});

    session.deleteSelectionSubject(cutsAreThisPanels: false);

    expect(transformLaneKeyFrames(now().transformTrack, 'position'), isEmpty);
    expectTheDrawingStays('the drawing is not the header\'s to take');
  });

  group('an fx on the row', () {
    late EffectId blur;

    setUp(() {
      session.effectsAndFx.addEffectToActiveLayer(EffectKind.blur);
      blur = now().effects.single.id;
    });

    test('🚨standing on its header or a parameter with no key, Delete has '
        'nothing to take — standing is not a range, so the effect stays', () {
      for (final laneId in [effectGroupLaneId(blur), effectLaneId(blur, 'blurX')]) {
        standOn(laneId);

        expect(
          session.deleteSubjectFor(cutsAreThisPanels: false),
          DeleteSubject.nothing,
          reason: laneId,
        );
        session.deleteSelectionSubject(cutsAreThisPanels: false);

        expectTheDrawingStays(laneId);
        expect(now().effects.map((effect) => effect.id), [blur], reason: laneId);
      }
    });

    test('🚨a RANGE over its header removes the effect, and one undo brings '
        'it back with its keys', () {
      standOn(effectLaneId(blur, 'blurX'));
      session.cellInstances.createInstancesForSelection();
      final keys = now().effects.single.parameterOf('blurX').track.keys;
      expect(keys, isNotEmpty, reason: 'premise: a key for the undo to bring back');

      session.updateLaneRangeSelectionDrag(
        layerId: before.id,
        laneId: effectGroupLaneId(blur),
        anchorIndex: 0,
        headIndex: 5,
        spanLaneIds: const [],
      );
      session.deleteSelectionSubject(cutsAreThisPanels: false);

      expect(
        now().effects,
        isEmpty,
        reason: '「fx 헤더 선택범위로 선택한채로 삭제누르면 해당 fx 삭제」',
      );
      expectTheDrawingStays('the drawing is not the fx\'s to take');

      session.undo();

      expect(now().effects.single.parameterOf('blurX').track.keys, keys);
    });

    test('a range over a PARAMETER lane takes its keys and leaves the effect',
        () {
      standOn(effectLaneId(blur, 'blurX'));
      session.cellInstances.createInstancesForSelection();

      session.updateLaneRangeSelectionDrag(
        layerId: before.id,
        laneId: effectLaneId(blur, 'blurX'),
        anchorIndex: 0,
        headIndex: 5,
        spanLaneIds: const [],
      );
      session.deleteSelectionSubject(cutsAreThisPanels: false);

      expect(now().effects.map((effect) => effect.id), [blur]);
      expect(now().effects.single.parameterOf('blurX').track.keys, isEmpty);
    });
  });
}
