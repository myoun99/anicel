import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/track_se_display.dart';
import 'package:anicel/src/ui/timeline/effect_lane_editing.dart';
import 'package:anicel/src/ui/timeline/effect_lane_policy.dart';
import 'package:anicel/src/ui/timeline/property_lane_model.dart'
    show laneGroupKey;
import 'package:anicel/src/ui/timeline/timeline_drag_preview.dart';
import 'package:anicel/src/ui/timeline/timeline_lane_provider.dart'
    show timelineLanesForLayer;
import 'package:anicel/src/ui/timeline/transform_lane_policy.dart'
    show transformGroupHeaderLane;

/// A DRAG PREVIEWS A TRACK-SE ROW ON THE CUT'S AXIS.
///
/// An SE row is ONE row on its track's global frames and each cut shows a
/// projection of it, so a drag has two forms to publish: the cut-local
/// display clone, which the timeline's rows render, and the global form,
/// which the storyboard's track-global strips read. The lane move's
/// name-tag arm was taught that in d524af02; its transform and effect arms
/// were left there as a named follow-up and went on publishing the GLOBAL
/// row into the cut's channel — so on any non-first cut every diamond of
/// the row being dragged sat the cut's start to the right until release,
/// and the lane's value column, which resolves through the global form,
/// did not follow the hand at all.
///
/// The collaborator the law lives in — named so `tool/mutation_run.dart`
/// runs this file for it.
TrackSeDisplay trackSeDisplayOf(EditorSessionManager session) =>
    session.trackSe;

void main() {
  test('🚨transform: a lane range move in cut 2 previews the row on the '
      "CUT's axis, and its global form beside it", () {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    session.cutVerbs.createCut();
    final cutStart = session.activeCutGlobalStartFrame;
    expect(
      cutStart,
      greaterThan(0),
      reason: 'fixture premise: a second cut, active, starting after the first',
    );
    final se = session.activeTrack.seLayers.first;
    session.updateLayerTransformTrack(
      se.id,
      TransformTrack.empty().copyWith(
        rotation: PropertyTrack(
          keys: {
            cutStart + 2: const PropertyKey(30.0),
            cutStart + 3: const PropertyKey(60.0),
          },
        ),
      ),
    );
    expect(
      session.activeTrack.seLayers.first.transformTrack.rotation.keys.keys
          .toList(),
      [cutStart + 2, cutStart + 3],
      reason: "fixture premise: the keys sit on the row's GLOBAL axis",
    );

    session.updateLaneRangeSelectionDrag(
      layerId: se.id,
      laneId: 'rotation',
      anchorIndex: cutStart + 2,
      headIndex: cutStart + 3,
      spanLaneIds: const [],
      framesAreGlobal: true,
    );
    expect(session.laneMove.beginLaneRangeMoveDrag(), isTrue);
    session.laneMove.updateLaneRangeMoveDrag(frameDelta: 5);

    final preview = session.dragPreview.value;
    final shown = timelineDragPreviewLayerFor(preview, se.id);
    expect(shown, isNotNull, reason: "the timeline's row gate resolves this");
    expect(
      shown!.transformTrack.rotation.keys.keys.toList(),
      [7, 8],
      reason: 'cut-local: the active cut starts at $cutStart',
    );
    expect(
      timelineDragPreviewGlobalLayerFor(
        preview,
        se.id,
      )?.transformTrack.rotation.keys.keys.toList(),
      [cutStart + 7, cutStart + 8],
      reason: "the storyboard's track-global strips read this one",
    );

    // What the rail actually draws, built from the previewed row exactly as
    // the row gate hands it over.
    final lanes = timelineLanesForLayer(
      layer: shown,
      session: session,
      expandedGroupKeys: {
        laneGroupKey(se.id, transformGroupHeaderLane.laneId),
      },
    );
    final rotation = lanes.singleWhere((lane) => lane.laneId == 'rotation');
    expect(rotation.keyedFrames, {7, 8});
    expect(
      rotation.valueLabel!(7),
      '30°',
      reason: 'the value column reads the drag in its GLOBAL form',
    );

    session.laneMove.endLaneRangeMoveDrag();
    expect(
      session.activeTrack.seLayers.first.transformTrack.rotation.keys.keys
          .toList(),
      [cutStart + 7, cutStart + 8],
      reason: 'the commit shifted by the drag delta alone',
    );
  });

  test('🚨effects: an effect lane move in cut 2 previews on the same two '
      'axes — the arm that published no global form at all', () {
    final base = createDefaultProject();
    final track = base.tracks.first;
    final se = track.seLayers.first;
    const effectId = EffectId('fx-se-blur');
    final laneId = effectLaneId(effectId, 'blurX');
    final firstDuration = track.cuts.first.duration;
    var effects = [LayerEffect.defaults(id: effectId, kind: EffectKind.blur)];
    for (final frame in [firstDuration + 2, firstDuration + 3]) {
      effects = effectsWithLaneKeyToggled(
        effects,
        laneId: laneId,
        frameIndex: frame,
      )!;
    }
    final session = EditorSessionManager(
      initialProject: base.copyWith(
        tracks: [
          track.copyWith(
            seLayers: [
              se.copyWith(effects: effects),
              ...track.seLayers.skip(1),
            ],
          ),
          ...base.tracks.skip(1),
        ],
      ),
    );
    addTearDown(session.dispose);
    session.cutVerbs.createCut();
    expect(
      session.activeCutGlobalStartFrame,
      firstDuration,
      reason: 'fixture premise: the second cut, active, starts after cut 1',
    );

    session.updateLaneRangeSelectionDrag(
      layerId: se.id,
      laneId: laneId,
      anchorIndex: firstDuration + 2,
      headIndex: firstDuration + 3,
      spanLaneIds: const [],
      framesAreGlobal: true,
    );
    expect(session.laneMove.beginLaneRangeMoveDrag(), isTrue);
    session.laneMove.updateLaneRangeMoveDrag(frameDelta: 5);

    final preview = session.dragPreview.value;
    expect(
      timelineDragPreviewLayerFor(
        preview,
        se.id,
      )!.effects.single.parameterOf('blurX').track.keys.keys.toList(),
      [7, 8],
      reason: 'cut-local: the active cut starts at $firstDuration',
    );
    expect(
      timelineDragPreviewGlobalLayerFor(
        preview,
        se.id,
      )!.effects.single.parameterOf('blurX').track.keys.keys.toList(),
      [firstDuration + 7, firstDuration + 8],
    );

    // ⚠️The step, not the landing: an effect chain on a track-owned row has
    // no write path of its own yet (the cut coordinator resolves effects
    // through the open cut's layers), which is a question of its own and
    // not this preview's.
    session.laneMove.cancelLaneRangeMoveDrag();
  });

  test('a row keyed on the CUT previews as itself, with no global form', () {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    final layer = session.activeLayer!;
    session.updateLayerTransformTrack(
      layer.id,
      TransformTrack.empty().copyWith(
        rotation: PropertyTrack(keys: {2: const PropertyKey(30.0)}),
      ),
    );

    session.updateLaneRangeSelectionDrag(
      layerId: layer.id,
      laneId: 'rotation',
      anchorIndex: 2,
      headIndex: 2,
      spanLaneIds: const [],
    );
    expect(session.laneMove.beginLaneRangeMoveDrag(), isTrue);
    session.laneMove.updateLaneRangeMoveDrag(frameDelta: 3);

    final preview = session.dragPreview.value! as BlockMoveDragPreview;
    expect(
      preview.previewLayers[layer.id]!.transformTrack.rotation.keys.keys
          .toList(),
      [5],
    );
    expect(
      preview.previewGlobalLayers,
      isEmpty,
      reason: 'a cut row has one axis — a second form would be a second answer',
    );
    session.laneMove.cancelLaneRangeMoveDrag();
  });
}
