import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/track_transform_lane_carrier.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/models/working_panel.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/lane_verbs.dart';
import 'package:anicel/src/ui/timeline/effect_lane_policy.dart';
import 'package:anicel/src/ui/timeline/timeline_drag_preview.dart';

import '../../helpers/placement_reading.dart';

/// F-195 at the session: A LANE EDIT IN FLIGHT IS SHOWN, NOT WRITTEN — and
/// what it shows is what its release writes.
///
/// The widget half — real pointers on the lanes and the handles — is
/// `an_edit_shows_while_it_is_dragged_test`. This half pins the verbs and
/// the readers each row family reaches: a cut row, the camera (whose lanes
/// live on the cut), a V track's chain, a track-owned SE row on a non-first
/// cut (two axes), and the key range move that now rides the same channel.
///
/// The collaborator the law lives in — named so `tool/mutation_run.dart`
/// runs this file for it.
LaneVerbs laneVerbsOf(EditorSessionManager session) => session.laneVerbs;

void main() {
  EditorSessionManager open() {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    return session;
  }

  /// The row being drawn on, as the canvas's composite holds it.
  CanvasActiveLayerRow activeRowIn(EditorSessionManager session) {
    CanvasActiveLayerRow? found;
    void walk(List<CompositeNode<CanvasStackRow>> nodes) {
      for (final node in nodes) {
        switch (node) {
          case CompositeLeaf(:final payload)
              when payload is CanvasActiveLayerRow:
            found = payload;
          case CompositeGroup(:final children):
            walk(children);
          case CompositeAdjustment(:final children):
            walk(children);
          case CompositeLeaf():
            break;
        }
      }
    }

    walk(session.editingCanvas.stack.nodes);
    return found!;
  }

  /// Where that row shows the canvas centre — its Position, while its
  /// anchor is the centre.
  CanvasPoint shownCentre(EditorSessionManager session) => activeRowIn(
    session,
  ).placement!.centreOf(session.requireActiveCut.canvasSize);

  Layer committed(EditorSessionManager session, Layer layer) =>
      session.requireActiveCut.layers.byId(layer.id)!;

  group('a cut row', () {
    test('a scrubbed value reaches the picture and the pen, writes nothing, '
        'and its release writes exactly what it showed', () {
      final session = open();
      final row = session.activeLayer!;
      final undoable = session.historyManager.canUndo;

      session.laneVerbs.previewLaneValueAt(
        row.id,
        'position',
        0,
        '40, 30',
        frameIsGlobal: false,
      );

      final preview = session.dragPreview.value;
      expect(preview, isA<LaneEditPreview>());
      expect(shownCentre(session), nearPoint(CanvasPoint(x: 40, y: 30)));
      expect(
        session.frameVerbs
            .layerCanvasPoseSample(row.id)!
            .centreOf(session.requireActiveCut.canvasSize),
        nearPoint(CanvasPoint(x: 40, y: 30)),
        reason: 'the pen draws in the space the picture shows',
      );
      expect(
        committed(session, row).transformTrack.position.isEmpty,
        isTrue,
        reason: 'DISPLAY only',
      );
      expect(session.historyManager.canUndo, undoable);

      session.laneVerbs.setLaneValueAt(
        row.id,
        'position',
        0,
        '40, 30',
        frameIsGlobal: false,
        description: 'Set Position',
      );

      expect(session.dragPreview.value, isNull, reason: 'dropped with it');
      expect(
        committed(session, row).transformTrack,
        (preview! as LaneEditPreview).row!.transformTrack,
        reason: 'ONE computation: the release writes the preview\'s track',
      );
    });

    test('an input that changes nothing shows the committed row again', () {
      final session = open();
      final row = session.activeLayer!;

      session.laneVerbs.previewLaneValueAt(
        row.id,
        'position',
        0,
        '40, 30',
        frameIsGlobal: false,
      );
      session.laneVerbs.previewLaneValueAt(
        row.id,
        'position',
        0,
        'not a value',
        frameIsGlobal: false,
      );

      expect(session.dragPreview.value, isNull);
    });

    test('a handle\'s preview is the edit its drop writes', () {
      final session = open();
      final row = session.activeLayer!;
      TransformTrack moveTo(TransformTrack track, int frame) =>
          track.withKeyframe(
            frame,
            TransformPose(center: CanvasPoint(x: 12, y: 34)),
          );

      session.laneVerbs.previewLayerTransformAtPlayhead(row.id, moveTo);
      final shown = (session.dragPreview.value! as LaneEditPreview).row!;
      expect(shownCentre(session), nearPoint(CanvasPoint(x: 12, y: 34)));

      session.laneVerbs.editLayerTransformAtPlayhead(
        row.id,
        moveTo,
        description: 'Move',
      );
      expect(session.dragPreview.value, isNull);
      expect(committed(session, row).transformTrack, shown.transformTrack);
    });

    test('🆕a key range slid along a lane moves the picture before the '
        'release — the move rides the same channel now', () {
      final session = open();
      final row = session.activeLayer!;
      session.laneVerbs.updateLayerTransformTrack(
        row.id,
        TransformTrack.empty().copyWith(
          position: PropertyTrack(
            keys: {
              0: PropertyKey(CanvasPoint(x: 0, y: 0)),
              4: PropertyKey(CanvasPoint(x: 100, y: 0)),
            },
          ),
        ),
      );
      session.selectFrameIndex(2);
      expect(
        shownCentre(session).x,
        closeTo(50, 1e-9),
        reason: 'the premise: halfway between the two keys',
      );

      session.updateLaneRangeSelectionDrag(
        layerId: row.id,
        laneId: 'position',
        anchorIndex: 4,
        headIndex: 4,
        spanLaneIds: const [],
        panel: WorkingPanel.timeline,
      );
      expect(session.laneMove.beginLaneRangeMoveDrag(), isTrue);
      session.laneMove.updateLaneRangeMoveDrag(frameDelta: -2);

      expect(session.dragPreview.value, isA<LaneEditPreview>());
      expect(
        shownCentre(session).x,
        closeTo(100, 1e-9),
        reason: 'the key slid onto the playhead — the picture shows it there',
      );
      expect(
        committed(session, row).transformTrack.position.keyAt(4),
        isNotNull,
        reason: 'nothing written yet',
      );

      session.laneMove.endLaneRangeMoveDrag();
      expect(session.dragPreview.value, isNull);
      expect(committed(session, row).transformTrack.position.keyAt(2), isNotNull);
    });

    // ↩️This pinned 「a BLOCK move is not followed by the canvas」 until
    // 유저 2026-09-28 answered 「따라가게」 (canvas-follows-block-moves); the
    // canvas's half now lives in `a_drag_in_flight_shows_on_the_canvas_test`.
    test('another drag\'s preview is not the lane verbs\' to drop', () {
      final session = open();
      final row = session.activeLayer!;

      session.dragPreview.value = BlockMoveDragPreview(
        previewLayers: {
          row.id: row.copyWith(
            transformTrack: TransformTrack.empty().withKeyframe(
              0,
              TransformPose(center: CanvasPoint(x: 9, y: 9)),
            ),
          ),
        },
      );

      session.laneVerbs.endLaneEditPreview();
      expect(
        session.dragPreview.value,
        isA<BlockMoveDragPreview>(),
        reason: 'another drag\'s preview is not the lane verbs\' to drop',
      );
      session.dragPreview.value = null;
    });
  });

  group('the camera', () {
    test('a scrubbed camera value moves the frame the canvas draws, writes '
        'nothing, and its release keys it', () {
      final session = open();
      final camera = session.requireActiveCut.layers.firstWhere(
        (layer) => layer.kind == LayerKind.camera,
      );

      session.laneVerbs.previewLaneValueAt(
        camera.id,
        'position',
        0,
        '100, 80',
        frameIsGlobal: false,
      );

      expect(
        session.camera.cameraPoseAtCurrentFrame.center,
        CanvasPoint(x: 100, y: 80),
      );
      expect(
        session.camera.displayedCameraPose!.center,
        CanvasPoint(x: 100, y: 80),
        reason: 'the frame the canvas draws',
      );
      expect(
        session.camera.activeCutCameraTrack!.position.keyAt(0),
        isNotNull,
        reason: 'the one camera answer every lane reader takes',
      );
      expect(session.requireActiveCut.camera.isEmpty, isTrue);

      session.laneVerbs.setLaneValueAt(
        camera.id,
        'position',
        0,
        '100, 80',
        frameIsGlobal: false,
        description: 'Set Position',
      );
      expect(session.dragPreview.value, isNull);
      expect(
        session.requireActiveCut.camera.track.position.keyAt(0)!.value,
        CanvasPoint(x: 100, y: 80),
      );
    });

    test('a camera key range slid along its lane reaches the camera readers '
        'through the channel — nothing parked beside it', () {
      final session = open();
      final camera = session.requireActiveCut.layers.firstWhere(
        (layer) => layer.kind == LayerKind.camera,
      );
      session.laneVerbs.setLaneValueAt(
        camera.id,
        'position',
        4,
        '100, 80',
        frameIsGlobal: false,
        description: 'Set Position',
      );
      session.updateLaneRangeSelectionDrag(
        layerId: camera.id,
        laneId: 'position',
        anchorIndex: 4,
        headIndex: 4,
        spanLaneIds: const [],
        panel: WorkingPanel.timeline,
      );
      expect(session.laneMove.beginLaneRangeMoveDrag(), isTrue);
      session.laneMove.updateLaneRangeMoveDrag(frameDelta: 2);

      expect(session.camera.activeCutCameraTrack!.position.keyAt(6), isNotNull);
      expect(session.camera.activeCutCameraTrack!.position.keyAt(4), isNull);
      expect(
        timelineDragPreviewLayerFor(session.dragPreview.value, camera.id),
        isNotNull,
        reason: 'the camera row\'s gate is tripped — a fresh marker per step',
      );

      session.laneMove.cancelLaneRangeMoveDrag();
      expect(session.camera.activeCutCameraTrack!.position.keyAt(4), isNotNull);
    });
  });

  test('a V track\'s chain previews on its TRACK — the strips and the '
      'labels read it there', () {
    final session = open();
    final track = session.activeTrack;
    const effectId = EffectId('v-fx');
    session.effectsAndFx.updateTrackEffects(track.id, [
      LayerEffect.defaults(id: effectId, kind: EffectKind.blur),
    ]);
    final laneId = effectLaneId(effectId, 'blurX');

    session.laneVerbs.previewLaneValueAt(
      trackTransformLaneCarrierId(track.id),
      laneId,
      0,
      '12',
      frameIsGlobal: true,
    );

    final shown = timelineDragPreviewTrackEffectsFor(
      session.dragPreview.value,
      track.id,
    );
    expect(shown, isNotNull);
    expect(
      effectParameterValueAt(shown!, effectId, 'blurX', 0),
      12,
    );
    expect(
      effectParameterValueAt(session.activeTrack.effects, effectId, 'blurX', 0),
      isNot(12),
      reason: 'the track itself is untouched',
    );
  });

  test('a track-owned SE row on the SECOND cut shows its edit on both axes, '
      'and the release lands on the track\'s row', () {
    final session = open();
    session.cutVerbs.createCut();
    final cutStart = session.activeCutGlobalStartFrame;
    expect(cutStart, greaterThan(0), reason: 'the premise: a second cut');
    final se = session.activeTrack.seLayers.first;
    // A line under the playhead, so the row puts a tag on the canvas.
    session.selectLayer(se.id);
    session.selectFrameIndex(2);
    session.seEntries.createSeEntryAtCurrentFrame(name: '쿵', seName: 'A');
    Offset? tagAt({TimelineDragPreview? preview}) => session.seEntries
        .seNameTagsForCutFrame(session.requireActiveCut, 2, preview: preview)
        .single
        .content
        .position;
    final tagBefore = tagAt();

    session.laneVerbs.previewLaneValueAt(
      se.id,
      'position',
      2,
      '40, 30',
      frameIsGlobal: false,
    );

    final preview = session.dragPreview.value;
    expect(
      tagAt(preview: preview),
      isNot(tagBefore),
      reason: 'the tag the canvas draws follows the edit in flight',
    );
    expect(tagAt(), tagBefore, reason: 'the committed film does not');
    expect(
      timelineDragPreviewLayerFor(preview, se.id)!
          .transformTrack
          .position
          .keyAt(2),
      isNotNull,
      reason: 'the cut\'s rows read the cut-local clone',
    );
    expect(
      timelineDragPreviewGlobalLayerFor(preview, se.id)!
          .transformTrack
          .position
          .keyAt(cutStart + 2),
      isNotNull,
      reason: 'the track axis reads the global form',
    );
    expect(
      session.activeTrack.seLayers.first.transformTrack.position.isEmpty,
      isTrue,
    );

    session.laneVerbs.setLaneValueAt(
      se.id,
      'position',
      2,
      '40, 30',
      frameIsGlobal: false,
      description: 'Set Position',
    );
    expect(
      session.activeTrack.seLayers.first.transformTrack.position.keyAt(
        cutStart + 2,
      ),
      isNotNull,
      reason: 'the release lands on the track\'s own row (F-102)',
    );
  });

  test('a handle\'s late drop after its session went does nothing — even '
      'with an edit still on the channel it went with', () {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    session.laneVerbs.previewLaneValueAt(
      session.activeLayer!.id,
      'position',
      0,
      '40, 30',
      frameIsGlobal: false,
    );
    expect(
      session.dragPreview.value,
      isA<LaneEditPreview>(),
      reason: 'the premise: the tab closes mid-drag',
    );
    session.dispose();

    expect(
      session.laneVerbs.endLaneEditPreview,
      returnsNormally,
      reason: 'dropping it would write to a channel that is already gone',
    );
  });

  test('an SE row\'s Opacity lane in flight thins its picture on the canvas '
      '— the track\'s rows join the stack through the same substitution', () {
    final session = open();
    final se = session.layers.firstWhere(
      (layer) => layer.kind == LayerKind.se,
    );
    session.selectLayer(se.id);
    session.selectFrameIndex(0);
    session.seEntries.createSeEntryAtCurrentFrame(name: '쿵');
    double? seOpacity() {
      for (final node in session.editingCanvas.stack.nodes) {
        if (node case CompositeLeaf(payload: final CanvasLayerImageRequest r)
            when r.frameKey.layerId == se.id) {
          return r.opacity;
        }
      }
      return null;
    }

    expect(seOpacity(), closeTo(1, 1e-9), reason: 'the premise');

    session.laneVerbs.previewLaneValueAt(
      se.id,
      'opacity',
      0,
      '40%',
      frameIsGlobal: false,
    );

    expect(seOpacity(), closeTo(0.4, 1e-9));
  });
}
