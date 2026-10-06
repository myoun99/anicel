import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/core/tree_nodes.dart' show preorderNodes;
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/camera_instruction.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timeline_coverage.dart'
    show TimelineBlockEdge, coveringDrawingBlockAt;
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/transitions.dart';
import 'package:anicel/src/ui/timeline/timeline_drag_preview.dart';

import '../../helpers/placement_reading.dart';

/// canvas-follows-block-moves — 유저 2026-09-28: 「따라가게 — 끄는 동안
/// 캔버스도 바뀐다」.
///
/// Every drag on the preview channel reaches the editing canvas through the
/// ONE substitution the timeline rows paint with — a block, a comma, an SE
/// line, a transition span, a block carrying keys, a file pushing its
/// neighbours, a cut's length — and the row being drawn
/// on composites the cel the drag shows there as an IMAGE while the brush
/// still holds another. Read at the session, before the release; the widget
/// half with real pointers is `a_block_drag_shows_on_the_canvas_test`.
///
/// The collaborator the fade's law lives in — named so
/// `tool/mutation_run.dart` runs this file for it. (The stack map's own
/// pins are in `editing_stack_map_test`.)
Transitions transitionsOf(EditorSessionManager session) => session.transitions;

void main() {
  EditorSessionManager open() {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    return session;
  }

  /// Every leaf of the canvas's composite, depth-first.
  List<CanvasStackRow> rowsOf(EditorSessionManager session) => [
    for (final node in preorderNodes(session.editingCanvas.stack.nodes))
      if (node case CompositeLeaf(:final payload)) payload,
  ];

  CanvasActiveLayerRow? liveRowOf(EditorSessionManager session) =>
      rowsOf(session).whereType<CanvasActiveLayerRow>().firstOrNull;

  /// The cels the canvas asks as IMAGES on [layerId].
  List<FrameId> imagesOn(EditorSessionManager session, LayerId layerId) => [
    for (final row in rowsOf(session).whereType<CanvasLayerImageRequest>())
      if (row.frameKey.layerId == layerId) row.frameKey.frameId,
  ];

  FrameId celAt(EditorSessionManager session, LayerId layerId, int frame) =>
      coveringDrawingBlockAt(
        session.requireActiveCut.layers.byId(layerId)!.timeline,
        frame,
      )!.frameId;

  /// A cut whose active row A holds cels at 0 and 3 (length 1 each), with a
  /// second drawing row B above it holding a cel at 3; standing on A.
  (EditorSessionManager, LayerId a, LayerId b) twoRows() {
    final session = open();
    session.createDrawingAtCurrentFrame();
    final a = session.activeLayer!.id;
    session.selectFrameIndex(3);
    session.createDrawingAtCurrentFrame();
    session.layerStack.addLayer();
    final b = session.activeLayer!.id;
    session.createDrawingAtCurrentFrame();
    session.selectLayer(a);
    return (session, a, b);
  }

  void moveRange(
    EditorSessionManager session,
    LayerId layerId,
    int at,
    int by,
  ) {
    session.updateFrameRangeSelectionDrag(
      layerId: layerId,
      anchorIndex: at,
      headIndex: at,
    );
    expect(
      session.rangeMove.beginFrameRangeMoveDrag(),
      isTrue,
      reason: 'the premise: a whole block to move',
    );
    session.rangeMove.updateFrameRangeMoveDrag(frameDelta: by);
    expect(session.dragPreview.value, isA<BlockMoveDragPreview>());
  }

  test('a block on ANOTHER row dragged under the playhead is on the canvas '
      'before the release — and the row being drawn on stays live', () {
    final (session, a, b) = twoRows();
    session.selectFrameIndex(0);
    final bCel = celAt(session, b, 3);
    expect(imagesOn(session, b), isEmpty, reason: 'the premise: B is empty at 0');

    moveRange(session, b, 3, -3);

    expect(
      imagesOn(session, b),
      [bCel],
      reason: 'the canvas shows the block where the drag holds it',
    );
    expect(
      liveRowOf(session),
      isNotNull,
      reason: 'A still shows the cel its brush holds — live',
    );
    expect(
      celAt(session, b, 3),
      bCel,
      reason: 'DISPLAY only — nothing written before the release',
    );

    session.rangeMove.endFrameRangeMoveDrag();
    expect(session.dragPreview.value, isNull);
    expect(imagesOn(session, b), [bCel], reason: 'the release keeps it there');
    expect(liveRowOf(session), isNotNull);
    expect(a, isNot(b));
  });

  test('the row being drawn on: a drag that brings ANOTHER cel under the '
      'playhead draws that cel as an image — and keeps the row\'s opacity', () {
    final (session, a, _) = twoRows();
    session.opacityVerbs.commitLayerOpacity(a, 0.5);
    session.selectFrameIndex(1);
    final opacity = session.editingCanvas.stack.activeLayerOpacity;
    expect(opacity, closeTo(0.5, 1e-9), reason: 'the premise');
    expect(
      liveRowOf(session)?.frameKey,
      isNull,
      reason: 'the premise: nothing exposed at 1 — the empty live row',
    );
    final later = celAt(session, a, 3);

    moveRange(session, a, 3, -2);

    expect(
      liveRowOf(session),
      isNull,
      reason: 'the live surface holds the cel the brush holds — not this one',
    );
    expect(imagesOn(session, a), [later], reason: 'the cel the drag shows');
    expect(
      session.editingCanvas.stack.activeLayerOpacity,
      opacity,
      reason: 'the ROW\'s opacity — the panel wraps the live surface in it, '
          'and a default would unwrap and remount it',
    );

    session.rangeMove.endFrameRangeMoveDrag();
    expect(
      liveRowOf(session)?.frameKey?.frameId,
      later,
      reason: 'the release hands the cel to the brush',
    );
    expect(imagesOn(session, a), isEmpty);
  });

  test('the row being drawn on: a drag that takes its cel AWAY from the '
      'playhead draws nothing there — not the cel the brush still holds', () {
    final (session, a, _) = twoRows();
    session.opacityVerbs.commitLayerOpacity(a, 0.5);
    session.selectFrameIndex(0);
    final held = celAt(session, a, 0);
    expect(liveRowOf(session)?.frameKey?.frameId, held, reason: 'the premise');

    moveRange(session, a, 0, 1);

    expect(liveRowOf(session), isNull);
    expect(imagesOn(session, a), isEmpty);
    expect(
      session.editingCanvas.stack.activeLayerOpacity,
      closeTo(0.5, 1e-9),
      reason: 'still the row\'s opacity',
    );

    session.rangeMove.cancelFrameRangeMoveDrag();
    expect(
      liveRowOf(session)?.frameKey?.frameId,
      held,
      reason: 'a cancel gives the brush its cel back where it was',
    );
  });

  test('a comma stretched over the playhead shows its cel there before the '
      'release', () {
    final (session, a, _) = twoRows();
    session.selectFrameIndex(1);
    final first = celAt(session, a, 0);

    expect(
      session.edgeDrag.beginExposureEdgeDrag(
        layerId: a,
        blockStartIndex: 0,
        edge: TimelineBlockEdge.end,
      ),
      isTrue,
    );
    session.edgeDrag.updateExposureEdgeDrag(1);

    expect(session.dragPreview.value, isA<ExposureEdgeDragPreview>());
    expect(imagesOn(session, a), [first]);
    expect(liveRowOf(session), isNull);

    session.edgeDrag.endExposureEdgeDrag();
    expect(liveRowOf(session)?.frameKey?.frameId, first);
  });

  test('the onion ghosts follow a block past the playhead — what the drag '
      'shows is what its release leaves', () {
    final (session, a, _) = twoRows();
    session.onionSkin.toggleLayerOnionSkin(a);
    session.selectFrameIndex(2);
    List<(FrameId, int?, double)> ghosts() => [
      for (final request in session.onionSkin.onionSkinCanvasRequests())
        (request.frameKey.frameId, request.tint, request.opacity),
    ];
    final before = ghosts();
    expect(before, isNotEmpty, reason: 'the premise: ghosts around frame 2');

    moveRange(session, a, 3, -2);
    final during = ghosts();
    expect(during, isNot(before), reason: 'the later cel is BEHIND now');

    session.rangeMove.endFrameRangeMoveDrag();
    expect(ghosts(), during);
  });

  test('a drag that carries the row\'s keys but leaves its cel under the '
      'playhead keeps it LIVE — posed as the drag shows it, and the pen with '
      'it', () {
    final session = open();
    final row = session.activeLayer!;
    final canvas = session.requireActiveCut.canvasSize;
    final before = liveRowOf(session)!.placement;

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

    expect(before?.centreOf(canvas), isNot(CanvasPoint(x: 9, y: 9)));
    expect(
      liveRowOf(session)!.placement!.centreOf(canvas),
      nearPoint(CanvasPoint(x: 9, y: 9)),
    );
    expect(
      session.frameVerbs.layerCanvasPoseSample(row.id)!.centreOf(canvas),
      nearPoint(CanvasPoint(x: 9, y: 9)),
      reason: 'a stroke mid-drag lands where the picture shows',
    );
    session.dragPreview.value = null;
  });

  test('an SE line moved under the playhead puts its tag and its picture on '
      'the canvas before the release', () {
    final session = open();
    final se = session.activeTrack.seLayers.first;
    session.selectLayer(se.id);
    session.selectFrameIndex(2);
    session.seEntries.createSeEntryAtCurrentFrame(name: '쿵', seName: 'A');
    session.selectFrameIndex(0);
    List<Object> tagsAt0() => session.seEntries.seNameTagsForCutFrame(
      session.requireActiveCut,
      0,
      preview: session.dragPreview.value,
    );
    expect(tagsAt0(), isEmpty, reason: 'the premise: the line starts at 2');
    expect(imagesOn(session, se.id), isEmpty);

    moveRange(session, se.id, 2, -2);

    expect(tagsAt0(), hasLength(1), reason: 'the tag follows the line');
    expect(imagesOn(session, se.id), hasLength(1));
    expect(
      session.seEntries.seNameTagsForCutFrame(session.requireActiveCut, 0),
      isEmpty,
      reason: 'the committed film does not',
    );
    session.rangeMove.cancelFrameRangeMoveDrag();
  });

  test('a fade stretched over the playhead lays its screen before the '
      'release', () {
    final session = open();
    transitionsOf(session).updateTransitionInstructions({
      0: const InstructionEvent(instructionId: 'fo', length: 5),
    });
    session.selectFrameIndex(6);
    expect(
      session.opacityVerbs.activeCutEditingVeils(),
      isEmpty,
      reason: 'the premise: the span ends at 5',
    );

    expect(
      session.edgeDrag.beginTransitionEdgeDrag(
        spanStartIndex: 0,
        edge: TimelineBlockEdge.end,
      ),
      isTrue,
    );
    session.edgeDrag.updateTransitionEdgeDrag(3);

    expect(session.opacityVerbs.activeCutEditingVeils(), isNotEmpty);
    expect(
      session.activeTrack.transitionLayer.instructions[0]!.length,
      5,
      reason: 'DISPLAY only',
    );
    session.edgeDrag.cancelTransitionEdgeDrag();
    expect(session.opacityVerbs.activeCutEditingVeils(), isEmpty);
  });

  test('the ruler\'s margin and the name across it read the one row a drag '
      'shows — an O.L stretched over the cut\'s end signs the label before '
      'the release', () {
    final session = open();
    session.cutVerbs.createCut();
    final cuts = session.repository.requireProject().tracks.first.cuts;
    session.selectCut(cuts.first.id);
    final end = cuts.first.duration;
    transitionsOf(session).updateTransitionInstructions({
      end - 4: const InstructionEvent(instructionId: 'ol', length: 3),
    });
    final span = session.activeCutSpan;
    final film = span.activeCutPlaybackFrameCount;
    expect(
      span.activeCutNoriShiroLabel,
      isEmpty,
      reason: 'the premise: the O.L ends inside the cut',
    );

    expect(
      session.edgeDrag.beginTransitionEdgeDrag(
        spanStartIndex: end - 4,
        edge: TimelineBlockEdge.end,
      ),
      isTrue,
    );
    session.edgeDrag.updateTransitionEdgeDrag(3);

    expect(
      span.activeCutDrawnFrameCount,
      greaterThan(film),
      reason: 'the margin follows the hand',
    );
    expect(
      span.activeCutNoriShiroLabel,
      contains('O.L'),
      reason: 'and the name across it reads the same row',
    );
    session.edgeDrag.cancelTransitionEdgeDrag();
    expect(span.activeCutNoriShiroLabel, isEmpty);
  });

  test('a file held over the timeline, pushing a neighbour under the '
      'playhead, shows that neighbour there — the same substitution', () {
    final (session, _, b) = twoRows();
    session.selectFrameIndex(0);
    final row = session.requireActiveCut.layers.byId(b)!;
    final pushed = celAt(session, b, 3);

    session.dragPreview.value = MediaPlacementPreview(
      previewLayers: {
        b: row.copyWith(
          timeline: {0: TimelineExposure.drawing(pushed, length: 1)},
        ),
      },
    );

    expect(imagesOn(session, b), [pushed]);
    session.dragPreview.value = null;
    expect(imagesOn(session, b), isEmpty);
  });

  test('a cut\'s length dragged in the storyboard, re-keying a row, shows '
      'the row as re-keyed — the same substitution', () {
    final (session, _, b) = twoRows();
    session.selectFrameIndex(0);
    final row = session.requireActiveCut.layers.byId(b)!;
    final rekeyed = celAt(session, b, 3);

    session.dragPreview.value = CutTrimDragPreview(
      previewDurations: const {},
      previewLayers: {
        b: row.copyWith(
          timeline: {0: TimelineExposure.drawing(rekeyed, length: 1)},
        ),
      },
    );

    expect(imagesOn(session, b), [rekeyed]);
    session.dragPreview.value = null;
    expect(imagesOn(session, b), isEmpty);
  });

  test('a SYNCED attach row follows its base\'s block under the playhead — '
      'as an image, the brush holding nothing there', () {
    final session = open();
    session.selectFrameIndex(3);
    session.createDrawingAtCurrentFrame();
    final base = session.activeLayer!.id;
    session.folders.addAttachedLayer(AttachedPlacement.above);
    final attach = session.activeLayer!.id;
    expect(attach, isNot(base), reason: 'the premise: on the attach row');
    final mirror = session.selectedFrame!.id;
    session.selectFrameIndex(0);
    expect(imagesOn(session, attach), isEmpty, reason: 'the premise');

    moveRange(session, base, 3, -3);

    expect(imagesOn(session, attach), [mirror]);
    expect(liveRowOf(session), isNull);
    session.rangeMove.cancelFrameRangeMoveDrag();
  });

  test('a camera row stays out of the picture — its marker clone changes '
      'nothing the canvas composites', () {
    final session = open();
    final camera = session.requireActiveCut.layers.firstWhere(
      (layer) => layer.kind == LayerKind.camera,
    );
    List<(Type, Object?)> drawn() => [
      for (final row in rowsOf(session))
        switch (row) {
          CanvasActiveLayerRow(:final frameKey) => (row.runtimeType, frameKey),
          CanvasLayerImageRequest(:final frameKey) => (
            row.runtimeType,
            frameKey,
          ),
        },
    ];
    final before = drawn();

    session.dragPreview.value = BlockMoveDragPreview(
      previewLayers: const {},
      cameraMarkerLayer: camera.copyWith(),
    );

    expect(drawn(), before);
    session.dragPreview.value = null;
  });
}
