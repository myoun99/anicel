import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/timeline_frame_range.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/key_clipboard.dart';
import 'package:anicel/src/ui/timeline/effect_lane_policy.dart'
    show effectGroupLaneId, effectLaneId;
import 'package:anicel/src/ui/timeline/toolbar_panel_context.dart';
import 'package:anicel/src/ui/timeline/transform_lane_policy.dart'
    show transformGroupHeaderLane, transformLaneDisplayOrder;

/// 🗣️F-388 (유저 2026-10-17): 「해당 fx에 서있으면 지금 캔버스 조작이 그 행
/// 기준으로 작동할텐데 복붙은 그 fx의 주인인 레이어행을 기준으로 작동함.
/// 제대로 서있는곳에서 작동하도록. 그래서 키도 복붙기능 제대로 만들고
/// 기존것들이랑 법 통일하고」 · I-101 (2026-10-15): 「키의 행(헤더나
/// 멤버든)에 서있거나, 선택하거나. 프레임이랑 동일하게」.
///
/// A lane row is the subject of the shared pill's clipboard as it is of its
/// Delete (F-87): the frame board does not reach through it to the cel of
/// the layer the lane belongs to, and a copy there takes the lane's keys.
///
/// The collaborator the copy lives in — named so `tool/mutation_run.dart`
/// runs this file for it.
KeyClipboard keyClipboardOf(EditorSessionManager session) =>
    session.keyClipboard;

void main() {
  late EditorSessionManager s;
  late Layer before;
  late ToolbarPanelContext pill;

  setUp(() {
    s = EditorSessionManager(initialProject: createDefaultProject());
    final layer = s.requireActiveCut.layers.first;
    s.selectLayer(layer.id);
    s.selectFrameIndex(3);
    s.createDrawingAtCurrentFrame();
    before = s.requireActiveCut.layers.first;
    pill = TimelineToolbarPanelContext(s);
  });
  tearDown(() => s.dispose());

  Layer now() =>
      s.requireActiveCut.layers.firstWhere((layer) => layer.id == before.id);

  void standOn(String laneId) =>
      s.standOnRow(LaneRowAddress(before.id, laneId));

  void standOnTheLayer() => s.standOnRow(LayerRowAddress(before.id));

  group('🚨on a lane over the owner\'s drawing, the clipboard leaves the '
      'drawing alone', () {
    late EffectId blur;

    setUp(() {
      s.effectsAndFx.addEffectToActiveLayer(EffectKind.blur);
      blur = now().effects.single.id;
      before = now();
    });

    test('a copy there takes no cel, and a frame in hand pastes none', () {
      pill.copyFrame();
      expect(s.clipboard.bankedRowLayerIds, [before.id], reason: '⛔전제');

      for (final laneId in [
        transformGroupHeaderLane.laneId,
        'position',
        effectGroupLaneId(blur),
        effectLaneId(blur, 'blurX'),
      ]) {
        standOn(laneId);
        expect(
          (
            pill.canCopyFrame,
            pill.canCutRun,
            pill.canPasteIndependentFrame,
            pill.canPasteLinkedFrame,
          ),
          (false, false, false, false),
          reason: '$laneId holds no key here, and the cel is not its',
        );
        pill.pasteIndependentFrame();
        pill.pasteLinkedFrame();
        pill.cutRun();
        expect(now().timeline, before.timeline, reason: laneId);
        expect(now().frames, before.frames, reason: laneId);
      }
    });
  });

  test('standing on a keyed lane, a copy takes its keys at the playhead — '
      'and lets the frame in hand go', () {
    pill.copyFrame();
    standOn(transformGroupHeaderLane.laneId);
    expect(
      s.cellInstances.createInstancesForSelection(),
      isTrue,
      reason: '⛔전제: the header keys every member at the playhead',
    );

    standOn('rotation');
    expect(pill.canCopyFrame, isTrue);
    pill.copyFrame();
    expect(s.keyClipboard.bankedKeyFrames, {
      'rotation': {0},
    });
    expect(
      s.clipboard.bankedRowLayerIds,
      isEmpty,
      reason: 'one copy in hand',
    );
    expect(now().timeline, before.timeline);

    standOn(transformGroupHeaderLane.laneId);
    pill.copyFrame();
    expect(s.keyClipboard.bankedKeyFrames, {
      for (final laneId in transformLaneDisplayOrder) laneId: {0},
    }, reason: 'a header stands for its members');
  });

  test('a lane range copies every key inside it, by its frame from the '
      'range\'s first', () {
    var rotation = now().transformTrack.rotation;
    for (final (frame, value) in [(3, 10.0), (7, 20.0), (12, 30.0)]) {
      rotation = rotation.withKey(frame, value);
    }
    s.laneVerbs.updateLayerTransformTrack(
      before.id,
      now().transformTrack.copyWith(rotation: rotation),
    );
    standOn('rotation');
    s.laneRangeSelection.value = TimelineLaneSelection(
      layerId: before.id,
      laneId: 'rotation',
      startIndex: 2,
      endIndexExclusive: 10,
    );

    pill.copyFrame();

    expect(s.keyClipboard.bankedKeyFrames, {
      'rotation': {1, 5},
    });
  });

  test('a frame copy lets the keys in hand go', () {
    standOn('rotation');
    expect(s.cellInstances.createInstancesForSelection(), isTrue);
    pill.copyFrame();
    expect(s.keyClipboard.holdsKeys, isTrue, reason: '⛔전제');

    standOnTheLayer();
    pill.copyFrame();

    expect(s.keyClipboard.holdsKeys, isFalse);
    expect(s.clipboard.bankedRowLayerIds, [before.id]);
  });
}
