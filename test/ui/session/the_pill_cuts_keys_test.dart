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

/// THE SHARED PILL'S 잘라내기 OF KEYS (the-pill-cut-skips-text-and-keys,
/// in I-123's family): 복사 and 잘라내기 are ONE pair (「복사=원본 남기고 클립
/// 저장 · 잘라내기=원본 지우고 클립 저장」), so where the copy takes a lane's
/// keys (F-388) the cut takes the same keys — and lifts exactly those.
///
/// ⚠️It is not the lane's Delete: a range over an fx header deletes the
/// effect (F-87), and a cut lifts only what it banked (결정 14 ②ⓐ).
///
/// The collaborator the cut lives in — named so `tool/mutation_run.dart`
/// runs this file for it.
KeyClipboard keyClipboardOf(EditorSessionManager session) =>
    session.keyClipboard;

void main() {
  late EditorSessionManager s;
  late Layer before;
  late ToolbarPanelContext pill;

  setUp(() {
    s = EditorSessionManager(initialProject: createDefaultProject());
    before = s.requireActiveCut.layers.first;
    s.selectLayer(before.id);
    pill = TimelineToolbarPanelContext(s);
  });
  tearDown(() => s.dispose());

  Layer now() =>
      s.requireActiveCut.layers.firstWhere((layer) => layer.id == before.id);

  void rotationKeys(Map<int, double> values) {
    final track = now().transformTrack;
    var lane = track.rotation;
    for (final MapEntry(key: frame, :value) in values.entries) {
      lane = lane.withKey(frame, value);
    }
    s.laneVerbs.updateLayerTransformTrack(
      before.id,
      track.copyWith(rotation: lane),
    );
  }

  Map<int, double> rotation() => {
    for (final MapEntry(key: frame, value: key)
        in now().transformTrack.rotation.keys.entries)
      frame: key.value,
  };

  void standOn(String laneId, {required int at}) {
    s.selectFrameIndex(at);
    s.standOnRow(LaneRowAddress(before.id, laneId));
  }

  void select(String laneId, int start, int endExclusive) {
    standOn(laneId, at: start);
    s.laneRangeSelection.value = TimelineLaneSelection(
      layerId: before.id,
      laneId: laneId,
      startIndex: start,
      endIndexExclusive: endExclusive,
    );
  }

  test('standing, the cut takes the key at the playhead off its lane as ONE '
      'step, and the paste puts it back as a copy\'s would', () {
    rotationKeys({3: 10, 7: 20, 12: 30});
    standOn('rotation', at: 7);
    final steps = s.historyManager.undoCount;

    expect(pill.canCutRun, isTrue);
    expect(pill.cutPress, isNotNull, reason: 'Ctrl+X presses it too');
    pill.cutRun();

    expect(rotation(), {3: 10, 12: 30});
    expect(s.historyManager.undoCount, steps + 1, reason: 'ONE step');
    expect(s.keyClipboard.holdsKeys, isTrue);

    standOn('rotation', at: 3);
    pill.pasteIndependentFrame();
    expect(rotation(), {3: 20, 4: 10, 13: 30});
  });

  test('over a range, every key inside it goes, and undo brings them '
      'back', () {
    rotationKeys({3: 10, 7: 20, 12: 30});
    select('rotation', 2, 8);

    pill.cutRun();

    expect(rotation(), {12: 30});
    expect(s.keyClipboard.bankedKeyFrames, {
      'rotation': {1, 5},
    });
    s.undo();
    expect(rotation(), {3: 10, 7: 20, 12: 30});
  });

  test('over an fx header the cut lifts its keys and leaves the effect — '
      'it lifts what it banks, where Delete takes the effect (F-87)', () {
    s.effectsAndFx.addEffectToActiveLayer(EffectKind.blur);
    final blur = now().effects.single.id;
    s.laneVerbs.setLaneValueAt(
      before.id,
      effectLaneId(blur, 'blurX'),
      4,
      '1',
      frameIsGlobal: false,
      description: 'Type',
      scaleLinked: false,
    );
    double? blurX(int frame) => now()
        .effects
        .single
        .parameters['blurX']!
        .track
        .keys[frame]
        ?.value;
    expect(blurX(4), 1, reason: '⛔전제');
    select(effectGroupLaneId(blur), 3, 6);

    pill.cutRun();

    expect(now().effects.single.id, blur, reason: 'the effect stays');
    expect(blurX(4), isNull, reason: 'its key went');
    expect(s.keyClipboard.holdsKeys, isTrue);
  });

  test('a lane with no key in reach leaves the cut dark, as it leaves the '
      'copy — and never cuts the cel the lane belongs to', () {
    s.createDrawingAtCurrentFrame();
    final cels = now().timeline.length;
    standOn('rotation', at: 0);
    final steps = s.historyManager.undoCount;

    expect(pill.canCopyFrame, isFalse, reason: '⛔전제');
    expect(pill.canCutRun, isFalse);
    pill.cutRun();

    expect(now().timeline, hasLength(cels));
    expect(s.historyManager.undoCount, steps);
  });
}
