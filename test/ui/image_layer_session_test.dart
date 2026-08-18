import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/delete_subject.dart';
import 'package:anicel/src/models/edit_instance_subject.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timeline_coverage.dart'
    show TimelineBlockEdge;
import 'package:anicel/src/models/timeline_repeat.dart'
    show TimelineRunEdgeMode, TimelineRunEdgeSide;
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/services/commands/convert_to_linked_cut_plan.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/timeline_drag_preview.dart';
import 'package:anicel/src/ui/timeline/toolbar_panel_context.dart';

/// The IMAGE layer contract (§6-z23): one cel by definition, born
/// covering its cut, no second cel to create, an ordinary attach base.
void main() {
  test('addLayerOfKind(image) is born COVERING the cut — ONE real 1-frame '
      'cell plus a fixed end hold whose ghosts tile to the cut boundary '
      '(D22) — and create-drawing has nothing left to make', () {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    final duration = s.requireActiveCut.duration;

    s.addLayerOfKind(LayerKind.image);
    final layer = s.activeLayer!;
    expect(layer.kind, LayerKind.image);
    expect(layer.frames, hasLength(1));
    expect(layer.timeline[0]!.length, 1, reason: '「블록은 1칸」');
    expect(layer.timeline[0]!.ghost, isFalse);
    var covered = 0;
    for (final exposure in layer.timeline.values) {
      expect(exposure.frameId, layer.frames.single.id);
      covered += exposure.length!;
    }
    expect(covered, duration, reason: 'real + hold ghosts tile the cut');
    expect(layer.runBehaviors, hasLength(1));
    expect(layer.runBehaviors.single.mode, TimelineRunEdgeMode.hold);
    expect(layer.runBehaviors.single.side, TimelineRunEdgeSide.end);
    expect(
      layer.frames.single.name,
      isNull,
      reason: 'no frame name by default — the layer name addresses the '
          'picture',
    );
    expect(s.canCreateDrawingAtCurrentFrame, isFalse);
  });

  test('the image row is EDGE-LESS: the session refuses a comma/edge drag '
      'on its own block (D22)', () {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    s.addLayerOfKind(LayerKind.image);
    final imageId = s.activeLayer!.id;

    expect(
      s.beginExposureEdgeDrag(
        layerId: imageId,
        blockStartIndex: 0,
        edge: TimelineBlockEdge.end,
      ),
      isFalse,
      reason: 'no grips in the chrome, no drag in the session — one answer',
    );
  });

  test('a BULK edge drag whose selection reaches the image row never '
      'retimes it — not even for one preview frame (D22 + ⛔먼저 옮기고 '
      '되돌리기 금지)', () {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    final celId = s.layers
        .firstWhere((layer) => layer.kind == LayerKind.animation)
        .id;
    s.selectLayer(celId);
    s.selectFrameIndex(0);
    s.createDrawingAtCurrentFrame();

    s.addLayerOfKind(LayerKind.image);
    final imageId = s.activeLayer!.id;

    Layer imageRow() => s.layers.firstWhere((layer) => layer.id == imageId);
    int realLength() => imageRow().timeline[0]!.length!;
    expect(realLength(), 1);

    /// The image row's block as the ROW ACTUALLY RENDERS it mid-drag: the
    /// live preview channel wins over the stored layer while a drag is in
    /// flight, so reading [s.layers] alone would miss the stretch the user
    /// watches happen.
    int? previewedRealLength() {
      final preview = s.dragPreview.value;
      final layer = switch (preview) {
        ExposureEdgeDragPreview(:final previewLayer) =>
          previewLayer.id == imageId ? previewLayer : null,
        BlockMoveDragPreview(:final previewLayers) => previewLayers[imageId],
        _ => null,
      };
      return layer?.timeline[0]?.length;
    }

    // A selection spanning the cel row DOWN THROUGH the image row, then a
    // comma drag on the cel row's own block edge.
    s.updateFrameRangeSelectionDrag(
      layerId: celId,
      anchorIndex: 0,
      headIndex: 4,
      headLayerId: imageId,
    );
    expect(
      s.beginExposureEdgeDrag(
        layerId: celId,
        blockStartIndex: 0,
        edge: TimelineBlockEdge.end,
      ),
      isTrue,
      reason: 'the DRAWING row still drags — only the image row stands down',
    );

    s.updateExposureEdgeDrag(3);
    expect(
      previewedRealLength() ?? 1,
      1,
      reason: 'the live PREVIEW must not stretch the picture: the write '
          'normalization would snap it back, and a frame of movement that '
          'gets reverted is exactly what the project bans',
    );
    expect(realLength(), 1);

    s.endExposureEdgeDrag();
    expect(realLength(), 1, reason: 'and the commit leaves it alone too');
    var covered = 0;
    for (final exposure in imageRow().timeline.values) {
      covered += exposure.length!;
    }
    expect(
      covered,
      s.requireActiveCut.duration,
      reason: 'the hold ghosts still tile the cut after the drag',
    );
  });

  test('the image cel is not deletable by the CELL verb — one picture is '
      'the row\'s definition, so the row is what you delete (D22)', () {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    s.addLayerOfKind(LayerKind.image);
    final imageId = s.activeLayer!.id;
    s.selectFrameIndex(0);

    expect(
      s.canDeleteCellAtCurrentFrame,
      isFalse,
      reason: 'the ghost hold keeps the cel referenced, so the delete would '
          'be rebuilt by the same write — a lit button that does nothing '
          'and burns an undo slot',
    );

    // Same answer through the SELECTION rung, which is a second door onto
    // the same verb.
    s.updateFrameRangeSelectionDrag(
      layerId: imageId,
      anchorIndex: 0,
      headIndex: 3,
    );
    expect(
      s.canDeleteCellForSelection,
      isFalse,
      reason: 'an image-only selection offers no cell delete either',
    );
  });

  test('a selection the verbs refuse is a NO-OP, never a redirect: an '
      'image-only band leaves the active drawing row alone (Delete AND '
      'comma)', () {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    final celId = s.layers
        .firstWhere((layer) => layer.kind == LayerKind.animation)
        .id;
    s.selectLayer(celId);
    s.selectFrameIndex(0);
    s.createDrawingAtCurrentFrame();

    s.addLayerOfKind(LayerKind.image);
    final imageId = s.activeLayer!.id;
    // A cell band never moves the active layer, so sweeping the BG row
    // while a drawing row stays active is the ORDINARY case.
    s.selectLayer(celId);
    s.selectFrameIndex(0);
    s.updateFrameRangeSelectionDrag(
      layerId: imageId,
      anchorIndex: 0,
      headIndex: 3,
    );

    Layer celRow() => s.layers.firstWhere((layer) => layer.id == celId);
    expect(celRow().frames, hasLength(1));

    expect(
      s.canDeleteCellAtCurrentFrame,
      isFalse,
      reason: 'the highlighted row IS the subject — with nothing deletable '
          'in it the button goes dark instead of retargeting',
    );
    s.deleteCellAtCurrentFrame();
    expect(
      celRow().frames,
      hasLength(1),
      reason: 'the unselected active row must not lose its drawing',
    );

    expect(s.canSetCommaForSelectionOrCurrent, isFalse);
    s.setCommaForSelectionOrCurrent(4);
    expect(
      celRow().timeline[0]!.length,
      1,
      reason: 'and the comma press must not retime it either',
    );
  });

  test('the STORYBOARD panel\'s delete ladder stops at the refused band '
      'too — a track-row cursor behind it means DELETE THE CUT', () {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    s.addLayerOfKind(LayerKind.image);
    final imageId = s.activeLayer!.id;
    final cutsBefore = s.activeTrack.cuts.length;

    // The storyboard cursor stands on the TRACK row (where the panel's
    // last delete rung means "the cut"), with a cell band on the image
    // row in front of it.
    s.selectRow(TrackRowAddress(s.activeTrack.id));
    s.updateFrameRangeSelectionDrag(
      layerId: imageId,
      anchorIndex: 0,
      headIndex: 3,
    );

    final panel = StoryboardToolbarPanelContext(s);
    expect(
      panel.deleteSubject,
      DeleteSubject.nothing,
      reason: 'the band owns the press; it must not reach the cut rung',
    );
    panel.deleteSelectionSubject();
    expect(
      s.activeTrack.cuts.length,
      cutsBefore,
      reason: 'pressing Delete over a picture band must never destroy the '
          'cut, its layers and its artwork',
    );
  });

  test('the comma gate reads its OWN ladder, not the delete gate\'s lane '
      'rung: a blockless band with live lane keys leaves the buttons dark '
      'instead of lit-and-dead', () {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    final celId = s.layers
        .firstWhere((layer) => layer.kind == LayerKind.animation)
        .id;
    s.selectLayer(celId);
    s.selectFrameIndex(0);
    s.createDrawingAtCurrentFrame();

    s.addLayerOfKind(LayerKind.image);
    final imageId = s.activeLayer!.id;

    // The mixed cell→lane drag (R26 #3): a band over the image row that
    // holds no editable block, whose tail also owns a LANE span.
    s.selectLayer(celId);
    s.selectFrameIndex(0);
    s.updateFrameRangeSelectionDrag(
      layerId: imageId,
      anchorIndex: 0,
      headIndex: 3,
      headLaneId: 'position',
    );
    s.createInstancesForSelection();

    expect(s.cellSelectionClaimsSubject, isTrue);
    expect(
      s.canSetCommaForSelectionOrCurrent,
      isFalse,
      reason: 'the delete gate answers true here for the LANE KEYS, which '
          'the comma verb has no branch for — inheriting that lit a button '
          'whose press the band\'s claim then swallowed',
    );
    // And the press really is a no-op on the unswept active row.
    final before = s.layers
        .firstWhere((layer) => layer.id == celId)
        .timeline[0]!
        .length;
    s.setCommaForSelectionOrCurrent(4);
    expect(
      s.layers.firstWhere((layer) => layer.id == celId).timeline[0]!.length,
      before,
    );
  });

  test('잘라내기 stands down on the image row too — COPY stays lit, since '
      'it never claims to remove the picture', () {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    s.addLayerOfKind(LayerKind.image);

    for (final frameIndex in [0, 5]) {
      s.selectFrameIndex(frameIndex);
      expect(
        s.canCutRunAtCurrentFrame,
        isFalse,
        reason: 'at index $frameIndex: the lift is rebuilt by the same '
            'write, so the press would only cost a phantom undo entry',
      );
      expect(
        s.canCopyFrameAtCurrentFrame,
        isTrue,
        reason: 'copy is honest on a picture row',
      );
    }
  });

  test('the WHOLE shared-pill family reads the band\'s claim, not just '
      'Delete: Edit Instance and the storyboard comma answer with it', () {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    final celId = s.layers
        .firstWhere((layer) => layer.kind == LayerKind.animation)
        .id;
    s.selectLayer(celId);
    s.selectFrameIndex(0);
    s.createDrawingAtCurrentFrame();
    s.renameSelectedFrame('KEEP');

    s.addLayerOfKind(LayerKind.image);
    final imageId = s.activeLayer!.id;
    s.selectLayer(celId);
    s.selectFrameIndex(0);
    s.updateFrameRangeSelectionDrag(
      layerId: imageId,
      anchorIndex: 0,
      headIndex: 3,
    );

    expect(
      s.deleteSubject,
      DeleteSubject.nothing,
      reason: 'the band claims the press and holds nothing deletable',
    );
    expect(
      s.editInstanceSubject,
      EditInstanceSubject.nothing,
      reason: 'Edit Instance is DOCUMENTED as the same ladder as Delete — '
          'two shared-pill verbs answering 「지금 무엇이 선택됐나」 '
          'differently is a rule the user would have to hold twice',
    );


    expect(
      s.canSetCommaForStoryboardCursor,
      isFalse,
      reason: 'the storyboard panel\'s comma gate reads it too — its own '
          'dispatch already refuses this band',
    );

    // The STORYBOARD panel runs its own ladders and must give the same
    // answers — with the cursor on the track row, where its last rungs
    // mean "the cut".
    s.selectRow(TrackRowAddress(s.activeTrack.id));
    final panel = StoryboardToolbarPanelContext(s);
    expect(panel.deleteSubject, DeleteSubject.nothing);
    expect(
      panel.canEditInstance,
      isFalse,
      reason: 'the panel\'s edit resolver is the same ladder as its '
          'delete — falling through would open the CUT rename for a band '
          'the user drew over a picture row',
    );
    expect(panel.editTarget, isNull);
  });

  test('X-here reads the band\'s claim too: with a blankable hold under '
      'the playhead, an image-only band still darkens it', () {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    final celId = s.layers
        .firstWhere((layer) => layer.kind == LayerKind.animation)
        .id;
    s.selectLayer(celId);
    s.selectFrameIndex(0);
    s.createDrawingAtCurrentFrame();
    // A real HOLD, so X-here has something to blank — without this the
    // gate is already false and the pin would pass for the wrong reason.
    s.setCommaForSelectionOrCurrent(4);
    s.selectFrameIndex(2);
    expect(
      s.canBlankExposureAtCurrentFrame,
      isTrue,
      reason: 'the control: this row IS blankable at this frame',
    );

    s.addLayerOfKind(LayerKind.image);
    final imageId = s.activeLayer!.id;
    s.selectLayer(celId);
    s.selectFrameIndex(2);
    s.updateFrameRangeSelectionDrag(
      layerId: imageId,
      anchorIndex: 0,
      headIndex: 3,
    );

    expect(
      s.canBlankExposureAtCurrentFrame,
      isFalse,
      reason: 'X edits an EXISTING hold, so a band holding nothing ends '
          'the ladder instead of shortening the unswept active row\'s hold',
    );
    s.blankExposureAtCurrentFrame();
    expect(
      s.layers.firstWhere((layer) => layer.id == celId).timeline[0]!.length,
      4,
      reason: 'and the press really leaves that hold alone',
    );
  });

  test('a band naming OTHER rows ends every verb that has no band rung — '
      'the case a predicate one word too weak let through', () {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    final rowA = s.layers
        .firstWhere((layer) => layer.kind == LayerKind.animation)
        .id;
    s.selectLayer(rowA);
    s.selectFrameIndex(0);
    s.createDrawingAtCurrentFrame();
    s.setCommaForSelectionOrCurrent(4);

    // A SECOND drawing row, with a block of its own — so the band holds
    // real blocks and the collector answers non-null. That is exactly
    // where "a band that holds nothing" stopped guarding.
    s.addLayerOfKind(LayerKind.animation);
    final rowB = s.activeLayer!.id;
    s.selectFrameIndex(0);
    s.createDrawingAtCurrentFrame();

    // Row A is active; the band names row B only.
    s.selectLayer(rowA);
    s.selectFrameIndex(2);
    s.updateFrameRangeSelectionDrag(
      layerId: rowB,
      anchorIndex: 0,
      headIndex: 1,
    );
    expect(
      s.canDeleteCellForSelection,
      isTrue,
      reason: 'the control: this band DOES hold editable blocks',
    );

    Map<int, int?> rowATimeline() => s.layers
        .firstWhere((layer) => layer.id == rowA)
        .timeline
        .map((key, value) => MapEntry(key, value.length));
    final before = rowATimeline();

    // A clip on the board so the paste gates have something to offer —
    // taken from ROW A, because the linked paste only re-exposes a cel on
    // the row it came from.
    s.selectLayer(rowA);
    s.selectFrameIndex(0);
    s.copyFrameAtCurrentFrame();
    s.selectFrameIndex(2);
    s.updateFrameRangeSelectionDrag(
      layerId: rowB,
      anchorIndex: 0,
      headIndex: 1,
    );

    for (final (name, gate) in [
      ('X-here', s.canBlankExposureAtCurrentFrame),
      ('mark', s.canToggleMarkAtCurrentFrame),
      ('잘라내기', s.canCutRunAtCurrentFrame),
      ('rename', s.canEditCellInstanceAtCurrentFrame),
      ('독립 붙여넣기', s.canPasteIndependentFrameAtCurrentFrame),
      ('링크 붙여넣기', s.canPasteLinkedFrameAtCurrentFrame),
    ]) {
      expect(
        gate,
        isFalse,
        reason: '$name has no rung that acts on a band, so it must not '
            'fall through to the playhead on the UNSWEPT active row',
      );
    }

    s.blankExposureAtCurrentFrame();
    s.toggleMarkAtCurrentFrame();
    s.cutRunAtCurrentFrame();
    s.pasteIndependentFrameAtCurrentFrame();
    s.pasteLinkedFrameAtCurrentFrame();
    expect(
      rowATimeline(),
      before,
      reason: 'and none of the presses touched the row the user did not '
          'sweep',
    );

    // THE OTHER HALF OF THE AXIS: a band that DOES cover the active row
    // is served, not refused — 범위 선택 후 잘라내기·붙여넣기 is the
    // documented way to use them, and blanket refusal broke it once.
    s.updateFrameRangeSelectionDrag(
      layerId: rowA,
      anchorIndex: 0,
      headIndex: 2,
    );
    expect(s.canCutRunAtCurrentFrame, isTrue);
    expect(s.canPasteIndependentFrameAtCurrentFrame, isTrue);
    expect(s.canPasteLinkedFrameAtCurrentFrame, isTrue);
  });

  test('the image row refuses every verb that would mint or re-expose a '
      'second cel — duplicate and LINK paste join the standdown (D22)', () {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    s.addLayerOfKind(LayerKind.image);

    for (final frameIndex in [0, 5]) {
      s.selectFrameIndex(frameIndex);
      expect(
        s.canDuplicateActiveBlock,
        isFalse,
        reason: 'at $frameIndex: the independent half MINTS a cel the '
            'normalization then strands — a second cel is the one thing '
            'this row\'s definition rules out',
      );
    }

    // Copy fills the clipboard from the picture row (kept lit on purpose),
    // and the LINK paste that would re-expose it stands down.
    s.selectFrameIndex(0);
    expect(s.canCopyFrameAtCurrentFrame, isTrue);
    s.copyFrameAtCurrentFrame();
    expect(
      s.canPasteLinkedFrameAtCurrentFrame,
      isFalse,
      reason: 'a second exposure of the one cel is rebuilt by the same '
          'write — the phantom undo entry the cut standdown exists to stop',
    );
  });

  test('an image layer carries attach rows like any drawing base', () {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    s.addLayerOfKind(LayerKind.image);
    expect(s.canAddAttachedLayerToActive, isTrue);
    s.addAttachedLayer(AttachedPlacement.above);
    expect(s.activeLayer!.attachedToLayerId, isNotNull);
  });

  test('겸용: two image rows with the same layer name LINK their single '
      'unnamed cels by position (the image-layer exception to the '
      'unnamed-never-conflicts rule)', () {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    s.addLayerOfKind(LayerKind.image);
    final imageName = s.activeLayer!.name;
    final origin = s.requireActiveCut;

    // A second cut with an image row of the SAME NAME and its own cel.
    s.duplicateActiveCut();
    final target = s.requireActiveCut;
    expect(target.id, isNot(origin.id));

    final originImage = origin.layers.firstWhere(
      (l) => l.kind == LayerKind.image && l.name == imageName,
    );
    final targetImage = target.layers.firstWhere(
      (l) => l.kind == LayerKind.image && l.name == imageName,
    );
    // The duplicate minted fresh cel ids, both unnamed.
    expect(targetImage.frames.single.id, isNot(originImage.frames.single.id));
    expect(originImage.frames.single.name, isNull);

    final resolution = resolveLayerMerge(
      origin: originImage,
      target: targetImage,
    );
    expect(
      resolution.retargetedFrameIds,
      {targetImage.frames.single.id: originImage.frames.single.id},
      reason: 'single unnamed image cels match by position',
    );
    expect(resolution.joiningFrameIds, isEmpty);

    // A DRAWING layer's unnamed cels keep the old rule: join, not link.
    final originDrawing = Layer(
      id: originImage.id,
      name: 'A',
      frames: [
        Frame(
          id: originImage.frames.single.id,
          duration: 1,
          strokes: const [],
        ),
      ],
      timeline: const {},
    );
    final targetDrawing = Layer(
      id: targetImage.id,
      name: 'A',
      frames: [
        Frame(
          id: targetImage.frames.single.id,
          duration: 1,
          strokes: const [],
        ),
      ],
      timeline: const {},
    );
    final drawingResolution = resolveLayerMerge(
      origin: originDrawing,
      target: targetDrawing,
    );
    expect(drawingResolution.retargetedFrameIds, isEmpty);
    expect(drawingResolution.joiningFrameIds, [
      targetImage.frames.single.id,
    ]);
  });
}
