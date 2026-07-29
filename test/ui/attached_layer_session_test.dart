import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/attached_layer_resolve.dart';
import 'package:anicel/src/models/attached_mode.dart';
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_folder.dart';
import 'package:anicel/src/models/timeline_coverage.dart'
    show TimelineBlockEdge;
import 'package:anicel/src/models/timeline_repeat.dart'
    show
        TimelineRunEdgeMode,
        TimelineRunEdgeSide,
        runBehaviorOwningGhostAt,
        timelineIndexIsGhost;
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/widgets/cursor_notice.dart';

/// W5 attach layers through the session: creation/placement, the attach
/// cel flow (Create Drawing = cel + link), edit guards and the cascade
/// delete.
void main() {
  (EditorSessionManager, Layer) sessionWithBase() {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    final base = s.activeLayer!;
    return (s, base);
  }

  List<Layer> cutLayers(EditorSessionManager s) => s.requireActiveCut.layers;

  test('addAttachedLayer places rows adjacent to the base — below before, '
      'above after — selected on creation and off the timesheet', () {
    final (s, base) = sessionWithBase();
    final baseIndexBefore = cutLayers(
      s,
    ).indexWhere((layer) => layer.id == base.id);

    expect(s.canAddAttachedLayerToActive, isTrue);
    s.addAttachedLayer(AttachedPlacement.above);
    final above = s.activeLayer!;
    expect(isAttachedLayer(above), isTrue);
    expect(above.attachedToLayerId, base.id);
    expect(above.attachedPlacement, AttachedPlacement.above);
    expect(above.kind, base.kind);
    expect(above.onTimesheet, isFalse);
    // Signed default names hang off the BASE name (R26 #29): B+1, B+2, …
    expect(above.name, '${base.name}+1');
    expect(
      cutLayers(s).indexWhere((layer) => layer.id == above.id),
      baseIndexBefore + 1,
    );

    // Adding from the attach row targets ITS base (same group); a below
    // row lands right before the base and counts its own side (-1).
    expect(s.canAddAttachedLayerToActive, isTrue);
    s.addAttachedLayer(AttachedPlacement.below);
    final below = s.activeLayer!;
    expect(below.attachedToLayerId, base.id);
    expect(below.name, '${base.name}-1');
    final layers = cutLayers(s);
    final baseIndex = layers.indexWhere((layer) => layer.id == base.id);
    expect(layers[baseIndex - 1].id, below.id);
    expect(layers[baseIndex + 1].id, above.id);
  });

  test('the attach display clone shows the mirrored blocks as ordinary '
      'BLOCKS (synced-block UI) while the brush target resolves through '
      'them', () {
    final (s, _) = sessionWithBase();
    s.createDrawingAtCurrentFrame();
    s.addAttachedLayer(AttachedPlacement.above);
    final attachId = s.activeLayer!.id;
    s.createDrawingAtCurrentFrame();

    final clone = s.layers.firstWhere((layer) => layer.id == attachId);
    expect(
      timelineIndexIsGhost(clone, 0),
      isFalse,
      reason: 'mirror cels are real drawable cels — the row reads as '
          'blocks; timing stands down row-wise, not through ghost',
    );
    // Anchor resolve-through (the R19b rule): the mirrored cell IS the
    // attach cel — drawing lands on it.
    final cutAttach = cutLayers(s).firstWhere((l) => l.id == attachId);
    expect(s.activeBrushEditorSelection!.frameId, cutAttach.frames.single.id);
  });

  test('a SYNCED attach row EAGERLY mirrors every base cel at creation '
      '(UI-R23 #7): one cel + link per base cel up front, no lazy Create '
      'Drawing, and one undo removes the whole row', () {
    final (s, base) = sessionWithBase();
    // Give the BASE two exposed cels (frames 0 and 2).
    s.createDrawingAtCurrentFrame();
    s.selectFrameIndex(2);
    s.createDrawingAtCurrentFrame();
    s.selectFrameIndex(0);

    s.addAttachedLayer(AttachedPlacement.above);
    final attachId = s.activeLayer!.id;

    // The mirror is FULL the moment the row is created: one own cel + base
    // link per base cel, and the synced row still owns no timeline of its
    // own (the display derives it).
    final attached = cutLayers(s).firstWhere((layer) => layer.id == attachId);
    expect(attached.frames, hasLength(2));
    expect(attached.baseFrameLinks, hasLength(2));
    expect(attached.timeline, isEmpty);

    // Every base cel is already mirrored — nothing left to lazily create.
    expect(s.canCreateDrawingAtCurrentFrame, isFalse);
    s.selectFrameIndex(2);
    expect(s.canCreateDrawingAtCurrentFrame, isFalse);
    s.selectFrameIndex(0);

    // The mirror cel at the playhead resolves as the brush target (its own
    // independent pixels, riding the base's exposure).
    expect(s.selectedFrame!.id, s.activeBrushEditorSelection!.frameId);
    expect(
      attached.baseFrameLinks.values,
      contains(s.selectedFrame!.id),
    );

    // ONE undo removes the whole attach row (cels + links together).
    s.undo();
    expect(cutLayers(s).any((l) => l.id == attachId), isFalse);
    expect(base.id, isNotNull); // base untouched throughout
  });

  test('ALWAYS-MIRROR (UI-R23 #7 v2): a base cel created AFTER the attach '
      'row exists auto-mirrors in the same write — and undo/redo of the '
      'base creation replays the identical mirror ids', () {
    final (s, base) = sessionWithBase();
    s.createDrawingAtCurrentFrame(); // base cel at 0
    s.addAttachedLayer(AttachedPlacement.above);
    final attachId = s.activeLayer!.id;
    expect(
      cutLayers(s).firstWhere((l) => l.id == attachId).frames,
      hasLength(1),
    );

    // The BASE gains a second cel while the attach row already exists:
    // the mirror follows in the very same edit — no manual step.
    s.selectLayer(base.id);
    s.selectFrameIndex(3);
    s.createDrawingAtCurrentFrame();
    var attached = cutLayers(s).firstWhere((l) => l.id == attachId);
    expect(attached.frames, hasLength(2));
    expect(attached.baseFrameLinks, hasLength(2));
    final links = Map.of(attached.baseFrameLinks);
    List<int> mirrorDisplayKeys() => s.layers
        .firstWhere((l) => l.id == attachId)
        .timeline
        .keys
        .toList();
    expect(mirrorDisplayKeys(), [0, 3]);

    // Undo the base creation: the mirror cel stays as an ORPHAN link
    // (audio-clip semantics — it comes back with the cel), but the
    // DERIVED display mirrors only what the base exposes now.
    s.undo();
    expect(mirrorDisplayKeys(), [0]);

    // Redo: the base cel returns and the SAME orphaned mirror cel + link
    // resume (no duplicate minting — the invariant is adds-only).
    s.redo();
    attached = cutLayers(s).firstWhere((l) => l.id == attachId);
    expect(attached.baseFrameLinks, links);
    expect(attached.frames, hasLength(2));
    expect(mirrorDisplayKeys(), [0, 3]);

    // A cel arriving on the base via a CROSS-ROW MOVE mirrors too.
    s.addLayer();
    final otherId = s.activeLayer!.id;
    s.selectLayer(otherId);
    s.selectFrameIndex(6);
    s.createDrawingAtCurrentFrame();
    s.updateFrameRangeSelectionDrag(
      layerId: otherId,
      anchorIndex: 6,
      headIndex: 6,
    );
    expect(s.beginFrameRangeMoveDrag(), isTrue);
    s.updateFrameRangeMoveDrag(frameDelta: 0, targetLayerId: base.id);
    s.endFrameRangeMoveDrag();
    attached = cutLayers(s).firstWhere((l) => l.id == attachId);
    expect(
      attached.frames,
      hasLength(3),
      reason: 'the moved-in base cel auto-mirrors like any other',
    );
  });

  test('the mirror reprints the base\'s run-edge NOTATION (UI-R24 #2): a '
      'hold edge\'s dashes resolve on the display clone, and the mirror '
      'prints the BASE\'s cel name (name follows the owner)', () {
    final (s, base) = sessionWithBase();
    s.createDrawingAtCurrentFrame();
    // Name the base cel '1' and author a HOLD run edge after it.
    expect(s.renameSelectedFrame('1'), isNull);
    s.setRunEdgeBehavior(
      layerId: base.id,
      blockStartIndex: 0,
      side: TimelineRunEdgeSide.end,
      mode: TimelineRunEdgeMode.hold,
    );
    s.selectLayer(base.id);
    s.addAttachedLayer(AttachedPlacement.above);
    final attachId = s.activeLayer!.id;

    // The display clone mirrors the hold ghost WITH its owner id and the
    // base's runBehaviors, so the cells painter resolves the dash mode.
    final clone = s.layers.firstWhere((l) => l.id == attachId);
    expect(clone.timeline[1]!.ghost, isTrue);
    expect(
      runBehaviorOwningGhostAt(clone, 1)?.mode,
      TimelineRunEdgeMode.hold,
      reason: 'the mirror resolves the base\'s hold mode (the ----- dash)',
    );

    // The mirror prints the BASE's name — never its own unnamed cel's ○.
    expect(s.frameNameForLayer(clone, 0), '1');
    expect(s.frameNameForLayer(clone, 1), '1');
  });

  test('the eager mirror preserves the base HOLD notation (UI-R23 #8): a '
      'held base cel mirrors as ONE block of the same length, never a '
      'restarted per-frame cel', () {
    final (s, base) = sessionWithBase();
    // Base cel at 0, stretched to a 3-frame hold via a comma drag.
    s.createDrawingAtCurrentFrame();
    s.beginExposureEdgeDrag(
      layerId: base.id,
      blockStartIndex: 0,
      edge: TimelineBlockEdge.end,
    );
    s.updateExposureEdgeDrag(2);
    s.endExposureEdgeDrag();
    expect(
      cutLayers(s).firstWhere((l) => l.id == base.id).timeline[0]!.length,
      3,
    );

    s.selectLayer(base.id);
    s.addAttachedLayer(AttachedPlacement.above);
    final attachId = s.activeLayer!.id;

    // ONE own cel for the whole held region — not three restarted cels.
    final attached = cutLayers(s).firstWhere((l) => l.id == attachId);
    expect(attached.frames, hasLength(1));
    expect(attached.baseFrameLinks, hasLength(1));

    // The derived mirror shows a single block whose length matches the
    // base's hold (the hold/run notation is preserved, not restarted).
    final display = s.layers.firstWhere((l) => l.id == attachId);
    expect(display.timeline.keys.toList(), [0]);
    expect(display.timeline[0]!.length, 3);
  });

  test('a FREE attach row (UI-R21 #3) authors its own timeline like a '
      'normal drawing layer — create/cut/mark/delete/comma all live, no '
      'cell links, no ghost mirror', () {
    final (s, base) = sessionWithBase();
    s.createDrawingAtCurrentFrame(); // base cel at 0 (not required, but real)
    s.addAttachedLayer(AttachedPlacement.above, mode: AttachedMode.free);
    final attachId = s.activeLayer!.id;
    expect(
      cutLayers(s).firstWhere((l) => l.id == attachId).attachedMode,
      AttachedMode.free,
    );

    // Normal authoring path: a cel with a plain timeline entry, NO link.
    expect(s.canCreateDrawingAtCurrentFrame, isTrue);
    s.createDrawingAtCurrentFrame();
    final attached = cutLayers(s).firstWhere((l) => l.id == attachId);
    expect(attached.frames, hasLength(1));
    expect(attached.baseFrameLinks, isEmpty);
    expect(attached.timeline[0]?.isDrawing, isTrue);

    // The display list hands back the REAL layer — no clone, no ghosts.
    final display = s.layers.firstWhere((l) => l.id == attachId);
    expect(identical(display, attached), isTrue);
    expect(timelineIndexIsGhost(display, 0), isFalse);

    // Timing edits behave like any drawing layer. A COMMA DRAG stretches
    // the block to length 3 (the old attach standdown refused the begin):
    expect(
      s.beginExposureEdgeDrag(
        layerId: attachId,
        blockStartIndex: 0,
        edge: TimelineBlockEdge.end,
      ),
      isTrue,
    );
    s.updateExposureEdgeDrag(2);
    s.endExposureEdgeDrag();
    expect(
      cutLayers(s).firstWhere((l) => l.id == attachId).timeline[0]!.length,
      3,
    );

    // Breakdown marks live INSIDE a block (normal rule) and the covering
    // cel deletes from anywhere on it — both gates open now.
    s.selectFrameIndex(1);
    expect(s.canToggleMarkAtCurrentFrame, isTrue);
    expect(s.canDeleteCellAtCurrentFrame, isTrue);
    s.selectFrameIndex(0);

    // Range selection + move are open too (the synced mirror stands down
    // until the ghost-snap rework).
    s.updateFrameRangeSelectionDrag(
      layerId: attachId,
      anchorIndex: 0,
      headIndex: 0,
    );
    expect(s.frameRangeSelection.value, isNotNull);
    expect(s.beginFrameRangeMoveDrag(), isTrue);
    s.cancelFrameRangeMoveDrag();

    // Still an ATTACH row structurally: no nesting base, cascades with
    // the base's delete, and adding from it targets ITS base.
    expect(canCarryAttachedLayers(attached), isFalse);
    expect(s.canAddAttachedLayerToActive, isTrue);
  });

  test('SYNCED attach mirrors join range selection (P3b-1): the mirror '
      'snaps to the base blocks, a base+mirror span moves with the mirror '
      'as a PASSENGER, and a mirror-only move refuses', () {
    final (s, base) = sessionWithBase();
    s.createDrawingAtCurrentFrame(); // base cel at 0, length 1
    s.addAttachedLayer(AttachedPlacement.above);
    final attachId = s.activeLayer!.id;
    s.createDrawingAtCurrentFrame(); // linked attach cel riding block 0

    // A drag ON the mirror row selects, snapped to the mirrored block.
    s.updateFrameRangeSelectionDrag(
      layerId: attachId,
      anchorIndex: 0,
      headIndex: 0,
    );
    var selection = s.frameRangeSelection.value;
    expect(selection, isNotNull);
    expect(selection!.layerId, attachId);
    expect(selection.startIndex, 0);
    expect(selection.endIndexExclusive, 1);

    // Mirror-only selection: nothing of its own to move — and the
    // refusal SAYS so at the cursor (the synced-block UI made the row
    // look grabbable).
    expect(s.beginFrameRangeMoveDrag(), isFalse);
    expect(cursorNotices.message, AppText.strings.noticeEditAttachOwner);
    cursorNotices.clear();

    // A span across base + mirror MOVES: the base slides, the mirror
    // follows by derivation (passenger — it never refuses the move).
    s.updateFrameRangeSelectionDrag(
      layerId: base.id,
      anchorIndex: 0,
      headIndex: 0,
      headLayerId: attachId,
    );
    selection = s.frameRangeSelection.value;
    expect(selection!.spanLayerIds, containsAll([base.id, attachId]));
    expect(s.beginFrameRangeMoveDrag(), isTrue);
    s.updateFrameRangeMoveDrag(frameDelta: 3);
    s.endFrameRangeMoveDrag();

    final movedBase = cutLayers(s).firstWhere((l) => l.id == base.id);
    expect(movedBase.timeline.containsKey(3), isTrue);
    expect(movedBase.timeline.containsKey(0), isFalse);
    // The mirror followed to the landing (a real block on the clone —
    // the synced-block UI).
    final mirror = s.layers.firstWhere((l) => l.id == attachId);
    expect(mirror.timeline.containsKey(3), isTrue);
    expect(mirror.timeline[3]!.ghost, isFalse);
  });

  test('deleting the base cascades over BOTH attach modes in one undo', () {
    final (s, base) = sessionWithBase();
    s.addAttachedLayer(AttachedPlacement.above, mode: AttachedMode.free);
    final freeId = s.activeLayer!.id;
    s.addAttachedLayer(AttachedPlacement.below);
    final syncedId = s.activeLayer!.id;

    s.selectLayer(base.id);
    s.addLayer(); // second standalone drawing layer = base deletable
    s.selectLayer(base.id);
    s.deleteActiveLayer();
    final after = cutLayers(s).map((l) => l.id).toList();
    expect(after.contains(freeId), isFalse);
    expect(after.contains(syncedId), isFalse);

    s.undo();
    final restored = cutLayers(s).map((l) => l.id).toList();
    expect(restored.contains(freeId), isTrue);
    expect(restored.contains(syncedId), isTrue);
    expect(
      cutLayers(s).firstWhere((l) => l.id == freeId).attachedMode,
      AttachedMode.free,
      reason: 'the mode survives the cascade undo',
    );
  });

  test('attach rows own no timing: exposure/mark/cell edits and comma '
      'drags stand down; kind toggles too', () {
    final (s, _) = sessionWithBase();
    s.addAttachedLayer(AttachedPlacement.above);
    s.createDrawingAtCurrentFrame();
    final attachId = s.activeLayer!.id;

    expect(s.canCutExposureAtCurrentFrame, isFalse);
    expect(s.canToggleMarkAtCurrentFrame, isFalse);
    expect(s.canDeleteCellAtCurrentFrame, isFalse);
    expect(s.canPasteLinkedFrameAtCurrentFrame, isFalse);
    expect(s.canToggleTargetLayerKind, isFalse);
    expect(
      s.beginExposureEdgeDrag(
        layerId: attachId,
        blockStartIndex: 0,
        edge: TimelineBlockEdge.end,
      ),
      isFalse,
    );
  });

  test('deleting the base cascades over its attach rows in ONE undo (R28 '
      '#14: no drawing floor stands in the way)', () {
    final (s, base) = sessionWithBase();
    s.addAttachedLayer(AttachedPlacement.above);
    s.addAttachedLayer(AttachedPlacement.below);
    final layersBefore = cutLayers(s).map((layer) => layer.id).toList();

    // R28 #14: the base is deletable even as the ONLY standalone drawing
    // layer — the action section may empty out.
    s.selectLayer(base.id);
    expect(s.canDeleteActiveLayer, isTrue);

    // Attach rows stay deletable too (accessories always were).
    final attachIds = attachedLayersOf(
      base.id,
      cutLayers(s),
    ).map((layer) => layer.id).toList();
    s.selectLayer(attachIds.first);
    expect(s.canDeleteActiveLayer, isTrue);

    // The cascade itself: deleting the base takes its attach rows with
    // it, restored whole by ONE undo.
    s.selectLayer(base.id);
    s.addLayer(); // regular layer above the group
    s.selectLayer(base.id);
    expect(s.canDeleteActiveLayer, isTrue);
    s.deleteActiveLayer();
    final afterDelete = cutLayers(s).map((layer) => layer.id).toList();
    expect(afterDelete.contains(base.id), isFalse);
    for (final id in attachIds) {
      expect(afterDelete.contains(id), isFalse);
    }

    s.undo(); // the cascade
    final restored = cutLayers(s).map((layer) => layer.id).toList();
    expect(restored.contains(base.id), isTrue);
    for (final id in attachIds) {
      expect(restored.contains(id), isTrue);
    }
    s.undo(); // the added regular layer
    expect(cutLayers(s).map((layer) => layer.id).toList(), layersBefore);
  });

  test('adding a regular layer while an attach row is active lands ABOVE '
      'the whole group, never inside it', () {
    final (s, base) = sessionWithBase();
    s.addAttachedLayer(AttachedPlacement.above);
    final attachId = s.activeLayer!.id;

    s.addLayer();
    final added = s.activeLayer!;
    expect(isAttachedLayer(added), isFalse);

    final layers = cutLayers(s);
    final baseIndex = layers.indexWhere((layer) => layer.id == base.id);
    expect(layers[baseIndex + 1].id, attachId);
    expect(layers[baseIndex + 2].id, added.id);
  });

  test('attach rows are ineligible bases (no nesting) and non-drawing '
      'kinds cannot carry them', () {
    final (s, _) = sessionWithBase();
    s.addAttachedLayer(AttachedPlacement.above);
    // Active = attach row: adding again targets the BASE (allowed).
    expect(s.canAddAttachedLayerToActive, isTrue);

    // A camera row cannot carry attach layers.
    final camera = cutLayers(
      s,
    ).firstWhere((layer) => layer.id.value.endsWith('-camera'));
    s.selectLayer(camera.id);
    expect(s.canAddAttachedLayerToActive, isFalse);
  });

  group('synced mirrors never commit their display clone', () {
    test('a bulk comma retime spanning base + mirror leaves the stored '
        'mirror timeline EMPTY (the clone must never write back)', () {
      final (s, base) = sessionWithBase();
      s.createDrawingAtCurrentFrame();
      s.addAttachedLayer(AttachedPlacement.above);
      final attachId = s.activeLayer!.id;

      s.updateFrameRangeSelectionDrag(
        layerId: base.id,
        anchorIndex: 0,
        headIndex: 0,
        headLayerId: attachId,
      );
      expect(
        s.beginExposureEdgeDrag(
          layerId: base.id,
          blockStartIndex: 0,
          edge: TimelineBlockEdge.end,
        ),
        isTrue,
      );
      s.updateExposureEdgeDrag(2);
      s.endExposureEdgeDrag();

      final storedBase = cutLayers(s).firstWhere((l) => l.id == base.id);
      expect(storedBase.timeline[0]!.length, 3, reason: 'the base retimed');
      final storedMirror = cutLayers(s).firstWhere((l) => l.id == attachId);
      expect(
        storedMirror.timeline,
        isEmpty,
        reason: 'the synced row\'s stored timeline stays empty — the '
            'display derives it from the base',
      );
      // And the DISPLAY still follows (derivation, not commitment).
      final clone = s.layers.firstWhere((l) => l.id == attachId);
      expect(clone.timeline[0]!.length, 3);
    });

    test('push/pull spanning base + mirror shifts the base only; the '
        'stored mirror timeline stays empty', () {
      final (s, base) = sessionWithBase();
      s.createDrawingAtCurrentFrame();
      s.addAttachedLayer(AttachedPlacement.above);
      final attachId = s.activeLayer!.id;

      s.updateFrameRangeSelectionDrag(
        layerId: base.id,
        anchorIndex: 0,
        headIndex: 0,
        headLayerId: attachId,
      );
      s.pushFrames(2);

      final storedBase = cutLayers(s).firstWhere((l) => l.id == base.id);
      expect(storedBase.timeline.containsKey(2), isTrue);
      final storedMirror = cutLayers(s).firstWhere((l) => l.id == attachId);
      expect(storedMirror.timeline, isEmpty);
      // The mirror followed by derivation.
      final clone = s.layers.firstWhere((l) => l.id == attachId);
      expect(clone.timeline.containsKey(2), isTrue);
    });

    test('a mirror-only selection keeps the delete/comma verbs OFF (their '
        'blocks are borrowed — pressing them would silently no-op)', () {
      final (s, _) = sessionWithBase();
      s.createDrawingAtCurrentFrame();
      s.addAttachedLayer(AttachedPlacement.above);
      final attachId = s.activeLayer!.id;

      s.updateFrameRangeSelectionDrag(
        layerId: attachId,
        anchorIndex: 0,
        headIndex: 0,
      );
      expect(s.canSetCommaForSelectionOrCurrent, isFalse);
    });

    test('독립시키기 from a BELOW attach row unlinks the whole group '
        '(the slice starts before the base)', () {
      final (s, base) = sessionWithBase();
      s.createDrawingAtCurrentFrame();
      s.addAttachedLayer(AttachedPlacement.below);
      final belowId = s.activeLayer!.id;

      s.selectLayer(base.id);
      s.linkDuplicateActiveLayer();
      s.selectLayer(belowId);
      expect(s.isLayerLinked(belowId), isTrue);

      s.unlinkActiveLayer();
      expect(s.isLayerLinked(base.id), isFalse);
      expect(
        s.isLayerLinked(belowId),
        isFalse,
        reason: 'the below side must not stay linked behind the user\'s '
            'back',
      );
    });
  });

  group('attach-organizer folders (공정 폴더)', () {
    test('wrapping an attach row makes an organizer INSIDE the group: the '
        'attach relation stays direct to the base, the group span swallows '
        'the folder row, and the structure validates', () {
      final (s, base) = sessionWithBase();
      s.addAttachedLayer(AttachedPlacement.above);
      final attachId = s.activeLayer!.id;

      expect(s.canGroupActiveAttachIntoFolder, isTrue);
      s.groupActiveAttachIntoFolder();

      final layers = cutLayers(s);
      final attach = layers.firstWhere((l) => l.id == attachId);
      final organizer = layers.folderById(attach.folderId)!;
      expect(attach.attachedToLayerId, base.id, reason: 'relation direct');
      expect(attachOrganizerBaseOf(organizer, layers), base.id);
      expect(
        layers.firstWhere((l) => l.id == base.id).folderId,
        isNull,
        reason: 'the base never joins the organizer',
      );
      // The group span swallows the organizer row — insertion for "add
      // above the group" stays past it.
      final baseIndex = layers.indexWhere((l) => l.id == base.id);
      expect(attachedGroupStartIndex(base.id, layers), baseIndex);
      expect(
        attachedGroupEndIndex(base.id, layers),
        layers.indexWhere((l) => l.id == organizer.id) + 1,
      );
      expect(folderStructureProblem(layers), isNull);

      // FLAT one-level rule: a row already inside an organizer refuses.
      s.selectLayer(attachId);
      expect(s.canGroupActiveAttachIntoFolder, isFalse);
      // The whole-group fold is not fooled either: a base cannot wrap.
      s.selectLayer(base.id);
      expect(s.canGroupActiveAttachIntoFolder, isFalse);
    });

    test('the SIBLING rule: adding an attach from a row inside an '
        'organizer (same placement) joins that organizer; a different '
        'placement lands at the group edge with the base\'s folder', () {
      final (s, base) = sessionWithBase();
      s.addAttachedLayer(AttachedPlacement.above);
      final firstId = s.activeLayer!.id;
      s.groupActiveAttachIntoFolder();
      s.selectLayer(firstId);

      s.addAttachedLayer(AttachedPlacement.above);
      final sibling = s.activeLayer!;
      final layers = cutLayers(s);
      final organizerId = layers
          .firstWhere((l) => l.id == firstId)
          .folderId;
      expect(sibling.folderId, organizerId, reason: 'same 공정, same folder');
      expect(folderStructureProblem(layers), isNull);

      // A BELOW attach from the same active row skips the organizer (its
      // side is different) and lands at the group edge, folder-free.
      s.selectLayer(firstId);
      s.addAttachedLayer(AttachedPlacement.below);
      final below = s.activeLayer!;
      expect(below.folderId, isNull);
      expect(folderStructureProblem(cutLayers(s)), isNull);
    });

    test('the whole-group fold keeps inner organizers: organizer rows '
        'join the outer folder, their members keep the organizer', () {
      final (s, base) = sessionWithBase();
      s.addAttachedLayer(AttachedPlacement.above);
      final attachId = s.activeLayer!.id;
      s.groupActiveAttachIntoFolder();
      s.selectLayer(base.id);

      s.groupActiveLayerIntoFolder();

      final layers = cutLayers(s);
      final attach = layers.firstWhere((l) => l.id == attachId);
      final organizer = layers.folderById(attach.folderId)!;
      final baseAfter = layers.firstWhere((l) => l.id == base.id);
      expect(baseAfter.folderId, isNotNull, reason: 'outer folder exists');
      expect(organizer.folderId, baseAfter.folderId,
          reason: 'the organizer joined the outer folder');
      expect(attach.folderId, organizer.id,
          reason: 'inner membership survived the fold');
      expect(folderStructureProblem(layers), isNull);
    });

    test('a BELOW attach row joins the whole-group fold (the group slice '
        'starts before the base)', () {
      final (s, base) = sessionWithBase();
      s.addAttachedLayer(AttachedPlacement.below);
      final belowId = s.activeLayer!.id;
      s.selectLayer(base.id);

      s.groupActiveLayerIntoFolder();

      final layers = cutLayers(s);
      final folderId = layers.firstWhere((l) => l.id == base.id).folderId;
      expect(folderId, isNotNull);
      expect(
        layers.firstWhere((l) => l.id == belowId).folderId,
        folderId,
        reason: 'the below side must not split out of the fold',
      );
      expect(folderStructureProblem(layers), isNull);
    });

    test('deleting the base cascades over organizer rows too; undo '
        'restores the whole shape', () {
      final (s, base) = sessionWithBase();
      s.addAttachedLayer(AttachedPlacement.above);
      final attachId = s.activeLayer!.id;
      s.groupActiveAttachIntoFolder();
      final organizerId = cutLayers(s)
          .firstWhere((l) => l.id == attachId)
          .folderId!;

      s.selectLayer(base.id);
      s.addLayer(); // keep a second drawing layer so the base can delete
      s.selectLayer(base.id);
      s.deleteActiveLayer();

      final after = cutLayers(s).map((l) => l.id).toSet();
      expect(after.contains(attachId), isFalse);
      expect(after.contains(organizerId), isFalse,
          reason: 'an organizer cannot outlive its group');

      s.undo();
      final restored = cutLayers(s);
      expect(restored.any((l) => l.id == organizerId), isTrue);
      expect(
        restored.firstWhere((l) => l.id == attachId).folderId,
        organizerId,
      );
      expect(folderStructureProblem(restored), isNull);
    });

    test('deleting the LAST member of an organizer removes the empty '
        'folder row with it, in one undo', () {
      final (s, base) = sessionWithBase();
      s.addAttachedLayer(AttachedPlacement.above);
      final attachId = s.activeLayer!.id;
      s.groupActiveAttachIntoFolder();
      final organizerId = cutLayers(s)
          .firstWhere((l) => l.id == attachId)
          .folderId!;

      s.selectLayer(attachId);
      s.deleteActiveLayer();

      final after = cutLayers(s).map((l) => l.id).toSet();
      expect(after.contains(attachId), isFalse);
      expect(after.contains(organizerId), isFalse,
          reason: 'no empty organizer strands behind');

      s.undo();
      final restored = cutLayers(s);
      expect(restored.any((l) => l.id == attachId), isTrue);
      expect(
        restored.firstWhere((l) => l.id == attachId).folderId,
        organizerId,
      );
      expect(folderStructureProblem(restored), isNull);
    });

    test('link-duplicating a group with an organizer remaps the copies '
        'onto the copied folder row', () {
      final (s, base) = sessionWithBase();
      s.createDrawingAtCurrentFrame();
      s.addAttachedLayer(AttachedPlacement.above);
      final attachId = s.activeLayer!.id;
      s.groupActiveAttachIntoFolder();
      final organizerId = cutLayers(s)
          .firstWhere((l) => l.id == attachId)
          .folderId!;

      s.selectLayer(base.id);
      s.linkDuplicateActiveLayer();

      final layers = cutLayers(s);
      final copiedOrganizers = [
        for (final l in layers.folderLayers)
          if (l.id != organizerId) l,
      ];
      expect(copiedOrganizers, hasLength(1));
      final copiedAttach = layers.firstWhere(
        (l) =>
            l.id != attachId &&
            isAttachedLayer(l) &&
            l.folderId == copiedOrganizers.single.id,
      );
      expect(copiedAttach.attachedToLayerId, isNot(base.id),
          reason: 'the copy re-attaches to the copied base');
      expect(folderStructureProblem(layers), isNull);
    });
  });
}
