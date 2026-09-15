import '../../controllers/timeline_controller.dart';
import '../../models/attached_layer_resolve.dart';
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/layer_kind.dart';
import '../../models/timeline_coverage.dart';
import '../timeline/timeline_cell_exposure_state.dart';
import 'active_cut_controllers.dart';
import 'cell_verbs.dart';
import 'drags/exposure_edge_drag.dart'
    show CutSyncCapture, commitWithCutSync, cutSyncResizeFor, cutSyncSnapshotFor, ridesCutLength;
import 'range_selections.dart';
import 'session_roles.dart';
import 'camera.dart';

/// The EXPOSURE VERBS — blanking an exposure, lengthening and shortening
/// the selected one, setting a whole run's comma, and a layer's exposure
/// state — as their own object.
///
/// 🚨A collaborator carved out of `EditorSessionManager` (the audit's SRP cut,
/// 2026-09-02). Dry-run before cutting: the rest reads none of it. The
/// comma set joined it in G4-2 (2026-09-08): it is the same subject —
/// how long a block is exposed — and its gate and its press have to read
/// one answer, so they live beside the lengthen/shorten pair.
class ExposureVerbs {
  ExposureVerbs({
    required SelectionAccess selection,
    required ProjectAccess project,
    required ChangeSink changes,
    required ActiveCutControllers controllers,
    required Camera camera,
    required RangeSelections rangeSelections,
    required CellVerbs cells,
  }) : _selection = selection,
       _project = project,
       _changes = changes,
       _controllers = controllers,
       _camera = camera,
       _rangeSelections = rangeSelections,
       _cells = cells;

  final Camera _camera;

  final SelectionAccess _selection;
  final ProjectAccess _project;
  final ChangeSink _changes;
  final ActiveCutControllers _controllers;
  final RangeSelections _rangeSelections;
  final CellVerbs _cells;

  /// The timesheet "X here" action: blanks the covering block's hold so the
  /// current cell (and the rest of the old hold) becomes empty.
  ///
  /// ⛔Renamed off "cut" in T3 — see [blankExposureAtCurrentFrame].
  /// 🚨결정 14 ①ⓑ (유저 확정 2026-08-22) — **X BLANKS EXACTLY THE SWEPT
  /// CELLS.**
  ///
  /// The rows the band names, each with the swept span. The playhead X
  /// truncates a block at the pressed frame; over a band that would blank
  /// PAST the sweep, so the swept cells go empty and the block's tail stays
  /// where it stands (see [TimelineController.blankableSpanInBand]).
  Map<LayerId, ({int start, int endExclusive})> _blankableSpanForSelection() =>
      _selection.bandRowsForSelection(
        _blankable,
        (ids, selection) => _controllers.timelineController.blankableSpanInBand(
          layerIds: ids,
          startIndex: selection.startIndex,
          endExclusive: selection.endIndexExclusive,
        ),
      );

  /// Whether an X can blank [layer]'s exposure at all.
  ///
  /// ⛔ONE PREDICATE FOR THE BAND AND THE PLAYHEAD — and the X-here is one
  /// of the reshaping verbs the retime law answers for
  /// ([ChangeSink.standsDownFromRetime]), so the rows that stand down are
  /// asked there, not listed again here: SYNCED attach rows (the base owns
  /// the timing), SINGLE-CEL image rows (the covering normalization would
  /// revert the X) and a MOVIE kept as a reference (a gap would restart the
  /// movie). Free attach rows cut exposures like any drawing layer
  /// (UI-R21 #3).
  ///
  /// 🚨F-107 (유저 2026-09-12): 「콘티레이어에선 불가능한 버튼 비활성화.
  /// 우선 프레임의 x버튼. 그 외도 있나 확인」. An X makes an EMPTY cell, and a
  /// COVERING row ([LayerKind.coversWithoutGaps]) has none in its world: the
  /// storyboard row's write normalization runs every panel on to the next
  /// division in the same write, so the X lit there and its press only left
  /// an undo step that undid nothing. That row times its panels by the comma
  /// (F-91), so it is no retime stand-down — what it refuses is the hole,
  /// and the kind answers that.
  bool _blankable(Layer layer) =>
      layer.kind.holdsDrawings &&
      !layer.kind.coversWithoutGaps &&
      !_changes.standsDownFromRetime(layer.id);

  bool get canBlankExposureForSelection =>
      _blankableSpanForSelection().isNotEmpty;

  bool get canBlankExposureAtCurrentFrame => _selection.bandOrActiveRow(
    canBlankExposureForSelection,
    _blankable,
    (layer) => _controllers.timelineController.canCutExposureAt(
      layer: layer,
      frameIndex: _controllers.timelineController.currentFrameIndex,
    ),
  );

  /// The timesheet "X here" — ⛔NOT the clipboard's cut.
  ///
  /// 🚨T3 rename: this was `cutExposureAtCurrentFrame` while 「잘라내기」 was
  /// a word nothing in the app used. Now that [FrameClipboard.cutRunAtCurrentFrame] exists,
  /// two different verbs would answer to "cut". The UI never said 「cut」
  /// here — the button is `×` (`blank-exposure-button`, tooltip `tlBlankX`)
  /// — so the code name follows the button and the new verb takes the word
  /// the user gave it.
  void blankExposureAtCurrentFrame() {
    final banded = _blankableSpanForSelection();
    if (banded.isNotEmpty) {
      _controllers.timelineController.blankSpansForLayers(banded);
      _changes.notifyChanged();
      return;
    }
    final layer = _selection.activeLayer;
    if (layer == null || !canBlankExposureAtCurrentFrame) {
      return;
    }

    _controllers.timelineController.cutExposureForLayer(layerId: layer.id);
    _changes.notifyChanged();
  }

  /// The toolbar +/- buttons are one-frame comma adjustments of the
  /// selected block's end edge (the same op the drag grips use).
  void increaseSelectedExposure() => _shiftSelectedExposureEnd(1);

  void decreaseSelectedExposure() => _shiftSelectedExposureEnd(-1);

  void _shiftSelectedExposureEnd(int delta) {
    final layer = _selection.activeLayer;
    if (layer == null) {
      return;
    }
    final block = _controllers.timelineController.blockForLayerAt(layer: layer);
    if (block == null) {
      return;
    }

    _controllers.timelineController.shiftExposureEdge(
      layerId: layer.id,
      blockStartIndex: block.startIndex,
      edge: TimelineBlockEdge.end,
      delta: delta,
    );
    _changes.notifyChanged();
  }

  TimelineCellExposureState exposureStateForLayer(Layer layer, int frameIndex) {
    if (layer.kind.groupsLayers) {
      // R10: a folder row is a CELLS row whose coverage is the subtree
      // union, carried by its band clone's own timeline. HELD, never
      // drawingStart — a held cell prints no glyph, so the band stays
      // nameless (L5) without touching the shared marker table, and the
      // block chrome still wraps the whole merged run because the segment
      // rule bounds on coverage rather than on starts.
      return coveringDrawingBlockAt(layer.timeline, frameIndex) != null
          ? TimelineCellExposureState.held
          : TimelineCellExposureState.uncovered;
    }
    if (layer.kind == LayerKind.camera) {
      // The camera row's cells mirror [activeCutCameraTrack] — the ONE
      // preview-aware answer (lane move, block ride, or committed), the
      // same track the member lanes and the union markers read (B4), so
      // the row follows any drag while the repository stays untouched.
      return _camera.activeCutCameraTrack?.keyframeAt(frameIndex) != null
          ? TimelineCellExposureState.drawingStart
          : TimelineCellExposureState.uncovered;
    }

    if (_controllers.timelineController.isDrawingStartForLayer(
      layer: layer,
      frameIndex: frameIndex,
    )) {
      return TimelineCellExposureState.drawingStart;
    }

    final held = _controllers.timelineController.isHeldExposureForLayer(
      layer: layer,
      frameIndex: frameIndex,
    );
    // Block-owned dots live on held cells only (offsets 1..length-1), so
    // markUncovered is never produced anymore — the enum value survives
    // solely for exhaustive switches over legacy-visual states.
    if (held &&
        _controllers.timelineController.hasMarkAt(
          layer: layer,
          frameIndex: frameIndex,
        )) {
      return TimelineCellExposureState.markHeld;
    }
    return held
        ? TimelineCellExposureState.held
        : TimelineCellExposureState.uncovered;
  }

  bool get canDecreaseSelectedExposure {
    final layer = _selection.activeLayer;
    if (layer == null) {
      return false;
    }
    final block = _controllers.timelineController.blockForLayerAt(layer: layer);
    return block != null && block.length > 1;
  }

  bool get canIncreaseSelectedExposure {
    final layer = _selection.activeLayer;
    if (layer == null) {
      return false;
    }
    return _controllers.timelineController.blockForLayerAt(layer: layer) !=
        null;
  }

  // --- Comma set (UI-R17 #7: the 1/2/3/4/N buttons) -------------------------

  /// Whether a comma set has a target: the selection's blocks, else the
  /// active layer's block covering the playhead.
  ///
  /// The second rung borrows the delete gate, which answers true for LANE
  /// KEYS as well — a subject this verb has no branch for. Under a
  /// claiming band that inheritance is what lit the buttons over a press
  /// [setCommaForSelectionOrCurrent] then refuses, so the band's claim is
  /// read here too and the two stay one answer.
  bool get canSetCommaForSelectionOrCurrent =>
      _rangeSelections.selectionBlockStartsByLayer() != null ||
      (!_cells.cellSelectionClaimsSubject &&
          _cells.canDeleteCellAtCurrentFrame);

  /// Sets the exposure length of every selected block — or the covering
  /// block at the playhead without a selection — to [comma], packing each
  /// layer's run with the retime ripple (1--2--3-- set to 1 reads 123;
  /// TVP). One composite undo across spanned layers; the selection
  /// follows the retimed span so repeated comma presses keep operating on
  /// the same cels.
  void setCommaForSelectionOrCurrent(int comma) {
    if (comma < 1) {
      return;
    }
    final selection = _selection.frameRangeSelection.value;
    // Single-cel rows are already absent — the shared collector states
    // that standdown once, so this verb and its `can…` gate agree.
    final selectionTargets = _rangeSelections.selectionBlockStartsByLayer();
    if (selection != null &&
        selectionTargets != null &&
        selectionTargets.isNotEmpty) {
      _retimeKeepingTheCutOnItsRow({
        for (final entry in selectionTargets.entries)
          entry.key: {for (final start in entry.value) start: comma},
      });
      _rangeSelections.reselectRetimedSelection(selection, selectionTargets);
      _changes.warmActiveCut();
      _changes.notifyChanged();
      return;
    }
    if (_cells.cellSelectionClaimsSubject) {
      // Same law as the delete verb: a band that resolves to nothing
      // retimable is a no-op, never a press that lands on some other row.
      return;
    }
    final layer = _selection.activeLayer;
    // Synced attach rows own no timing (free rows retime normally);
    // single-cel rows are pinned by the covering normalization.
    if (layer == null ||
        isSyncedAttachedLayer(layer) ||
        layer.kind.holdsSingleCel) {
      return;
    }
    final block = coveringDrawingBlockAt(
      layer.timeline,
      _controllers.timelineController.currentFrameIndex,
    );
    if (block == null || block.entry.ghost) {
      return;
    }
    _retimeKeepingTheCutOnItsRow({
      layer.id: {block.startIndex: comma},
    });
    _changes.warmActiveCut();
    _changes.notifyChanged();
  }

  /// The comma buttons' retime, keeping the cut on its storyboard row.
  ///
  /// 🚨F-91 (유저 2026-09-12): 「스토리보드레이어의 마지막 프레임 블록에 대한
  /// 코마 편집이 안먹힘. 컷길이 바뀌는걸 원하는게 맞으니까 법 나누지말고
  /// 작동하도록」 · F-100: 「노출 편집 버튼, 1,2,3,4,n 을 통해 콘티레이어
  /// 편집하면 컷길이랑 어긋남. 근본/구조적으로 어긋나지 않도록」. The buttons
  /// retimed the row alone; the storyboard's write normalization then re-tiled
  /// a shortened last panel back out to the cut's end, or left a row pushed
  /// past it standing apart from the cut. Only the comma DRAG moved the cut
  /// with its row, so the buttons now commit by the drag's own law.
  void _retimeKeepingTheCutOnItsRow(
    Map<LayerId, Map<int, int>> newLengthsByLayer,
  ) {
    final controller = _controllers.timelineController;
    final cut = _project.activeCutOrNull;
    final edits = <({Layer before, Layer after})>[];
    CutSyncCapture? sync;
    Layer? syncedRow;
    for (final MapEntry(key: layerId, value: lengths)
        in newLengthsByLayer.entries) {
      final before = _project.layerById(layerId);
      final after = before == null
          ? null
          : controller.retimedLayerForBlocks(
              layer: before,
              newLengthByStart: lengths,
            );
      if (before == null || after == null) {
        continue;
      }
      edits.add((before: before, after: after));
      if (sync == null && cut != null && ridesCutLength(before.kind)) {
        sync = cutSyncSnapshotFor(project: _project, cut: cut, row: before);
        syncedRow = after;
      }
    }
    final resize = sync == null || syncedRow == null
        ? null
        : cutSyncResizeFor(project: _project, sync: sync, afterRow: syncedRow);
    if (sync == null || resize == null) {
      controller.retimeBlocksForLayers(newLengthsByLayer);
      return;
    }
    commitWithCutSync(
      controller: controller,
      edits: edits,
      sync: sync,
      resize: resize,
      description: 'Set comma exposure',
    );
    _changes.refreshAfterCutCommand();
  }
}
