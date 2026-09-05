import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_frame_range.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/ui/session/drags/lane_range_move_drag.dart';
import 'package:anicel/src/ui/timeline/timeline_drag_preview.dart';
import 'package:anicel/src/ui/timeline/transform_lane_editing.dart';

/// The lane-key range MOVE drag — nothing named it (the audit's
/// untested-file pass, 2026-09-05).
///
/// 🚨Three families share one drag: the transform lanes, an effect chain's
/// lanes, and (on SE rows) the name tag's. Which one is decided ONCE at
/// begin, the same way update decides it — asking per lane would let the
/// drag answer "there are keys" about a lane the step is not going to
/// shift.
///
/// 🚨A BLOCKED landing HOLDS: the last valid preview and outline stay
/// where they were, rather than snapping back mid-drag.
void main() {
  TransformTrack trackWithKeysAt(List<int> frames) => TransformTrack(
    keyframes: {
      for (final frame in frames)
        frame: CameraPose(center: CanvasPoint(x: frame.toDouble(), y: 0)),
    },
  );

  TimelineLaneSelection selection({
    int start = 2,
    int endExclusive = 5,
    List<String> laneIds = const ['position'],
  }) => TimelineLaneSelection(
    layerId: const LayerId('l'),
    laneId: laneIds.first,
    startIndex: start,
    endIndexExclusive: endExclusive,
    laneIds: laneIds,
  );

  ({
    LaneRangeMoveDrag? drag,
    ValueNotifier<TimelineDragPreview?> preview,
    ValueNotifier<TimelineLaneSelection?> outline,
    List<TransformTrack> transformCommits,
    List<List<LayerEffect>> effectCommits,
    int cameraClears,
  })
  open({
    TransformTrack? track,
    List<String> laneIds = const ['position'],
    int start = 2,
    int endExclusive = 5,
  }) {
    final subjectTrack = track ?? trackWithKeysAt([0, 3, 4, 9]);
    final preview = ValueNotifier<TimelineDragPreview?>(null);
    final outline = ValueNotifier<TimelineLaneSelection?>(null);
    addTearDown(preview.dispose);
    addTearDown(outline.dispose);
    final transformCommits = <TransformTrack>[];
    final effectCommits = <List<LayerEffect>>[];
    var cameraClears = 0;
    final before = selection(
      start: start,
      endExclusive: endExclusive,
      laneIds: laneIds,
    );
    outline.value = before;
    return (
      drag: LaneRangeMoveDrag.begin(
        selection: before,
        subject: LaneMoveSubject(
          transformTrack: subjectTrack,
          effects: const [],
          commitTransform: transformCommits.add,
          commitEffects: effectCommits.add,
          previewTransform: (next) =>
              const BlockMoveDragPreview(previewLayers: {}),
          previewEffects: (next) =>
              const BlockMoveDragPreview(previewLayers: {}),
        ),
        laneVerbTargets: (spanLaneIds, {effects = const []}) => spanLaneIds,
        preview: preview,
        selectionChannel: outline,
        clearCameraPreview: () => cameraClears += 1,
      ),
      preview: preview,
      outline: outline,
      transformCommits: transformCommits,
      effectCommits: effectCommits,
      cameraClears: cameraClears,
    );
  }

  test('⛔a selection covering NO key on any spanned lane gives no object — '
      'nothing to move, no drag', () {
    expect(
      open(track: trackWithKeysAt([0, 9]), start: 2, endExclusive: 5).drag,
      isNull,
    );
  });

  test('a selection that does cover a key begins', () {
    expect(open().drag, isNotNull);
  });

  test('a shift moves the keys inside the range and leaves the rest', () {
    final session = open();

    session.drag!.update(frameDelta: 2);
    session.drag!.commit();

    expect(
      transformLaneKeyFrames(session.transformCommits.single, 'position'),
      {0, 5, 6, 9},
      reason: 'the keys at 3 and 4 moved; 0 and 9 were outside the range',
    );
  });

  test('🚨the OUTLINE rides the shift, so the selection lands on what it '
      'moved', () {
    final session = open();

    session.drag!.update(frameDelta: 2);

    expect(session.outline.value?.startIndex, 4);
    expect(session.outline.value?.endIndexExclusive, 7);
  });

  test('⛔the outline never rides BELOW zero, even when the KEYS can still '
      'move — the span would name frames that do not exist', () {
    // Keys at 3 and 4 slide to 0 and 1, which is legal; the outline's own
    // start would be -1, which is not.
    final session = open(track: trackWithKeysAt([3, 4, 9]));

    session.drag!.update(frameDelta: -3);

    expect(session.outline.value?.startIndex, 2, reason: 'it did not ride');
  });

  test('🚨a BLOCKED landing HOLDS the last valid preview and outline — it '
      'does not snap back mid-drag', () {
    final session = open();

    session.drag!.update(frameDelta: 2);
    final held = session.outline.value;

    // Landing on top of the key at 9 is refused all-or-nothing.
    session.drag!.update(frameDelta: 6);

    expect(session.outline.value, held);
  });

  test('a delta of ZERO puts the outline back and previews nothing', () {
    final session = open();

    session.drag!.update(frameDelta: 2);
    session.drag!.update(frameDelta: 0);

    expect(session.preview.value, isNull);
    expect(session.outline.value?.startIndex, 2);
  });

  test('🚨a drag that never produced a valid shift writes NOTHING and puts '
      'the outline back where it started', () {
    final session = open();

    session.drag!.update(frameDelta: 0);
    session.drag!.commit();

    expect(session.transformCommits, isEmpty);
    expect(session.outline.value?.startIndex, 2);
  });

  test('commit lands ONE step and leaves the outline on the landed span', () {
    final session = open();

    session.drag!.update(frameDelta: 2);
    session.drag!.commit();

    expect(session.transformCommits, hasLength(1));
    expect(session.outline.value?.startIndex, 4);
    expect(session.preview.value, isNull);
  });

  test('cancel writes nothing and puts the outline back', () {
    final session = open();

    session.drag!.update(frameDelta: 2);
    session.drag!.cancel();

    expect(session.transformCommits, isEmpty);
    expect(session.outline.value?.startIndex, 2);
    expect(session.preview.value, isNull);
  });
}
