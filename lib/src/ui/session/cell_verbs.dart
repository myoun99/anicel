import '../../models/attached_layer_resolve.dart';
import '../../models/layer_id.dart';
import '../../models/layer_kind.dart';
import 'active_cut_controllers.dart';
import 'session_roles.dart';
import 'lane_verbs.dart';
import 'range_selections.dart';
import 'frame_clipboard.dart';
import 'transition_range_hold.dart';
import 'transitions.dart';

/// The CELL VERBS — deleting the cell under the cursor or the selection,
/// 링크 독립 on the frame axis, and the facts those presses ask — as their
/// own object.
///
/// 🚨A collaborator carved out of `EditorSessionManager` (the audit's SRP cut,
/// 2026-09-02). Dry-run before cutting: the rest reads none of it.
/// ↩️The pixel verbs lived here too until I-55 doubled them (2026-10-01);
/// they are `PixelVerbs` now — the two halves shared no member.
class CellVerbs {
  CellVerbs({
    required ProjectAccess project,
    required SelectionAccess selection,
    required ChangeSink changes,
    required ActiveCutControllers controllers,
    required LaneVerbs laneVerbs,
    required RangeSelections rangeSelections,
    required FrameClipboard clipboard,
    required Transitions transitions,
  }) : _project = project,
       _selection = selection,
       _changes = changes,
       _controllers = controllers,
       _laneVerbs = laneVerbs,
       _rangeSelections = rangeSelections,
       _clipboard = clipboard,
       _transitions = transitions;

  final FrameClipboard _clipboard;
  final Transitions _transitions;

  final ProjectAccess _project;
  final SelectionAccess _selection;
  final ChangeSink _changes;
  final ActiveCutControllers _controllers;
  final LaneVerbs _laneVerbs;
  final RangeSelections _rangeSelections;

  bool get hasActiveNonNegativeCell {
    return _selection.activeLayer != null &&
        _controllers.timelineController.currentFrameIndex >= 0;
  }

  /// The SELECTION-borne rungs of the cell delete, alone (B8): lane keys
  /// under the lane-verb context, or a live selection's real blocks —
  /// either axis. [deleteCellAtCurrentFrame] dispatches both before it ever
  /// asks the active layer, so a caller gated on THIS can hand the press to
  /// that verb without the active-layer rung becoming reachable.
  bool get canDeleteCellForSelection =>
      // R10 #19: the same rule Add follows — when the subject is a PROPERTY
      // row, Delete removes its keys, not a cel. It also closes a gap the
      // other way round: a live LANE span used to fall through to the cell
      // path and delete the active layer's cel instead of the keys under it.
      // F-87: keys, or a live range naming an fx header (which removes the
      // effect).
      _laneVerbs.laneVerbRangeHasSomethingToDelete ||
      // A live selection is deletable wherever the playhead stands (UI-R17
      // #2) — its blocks, and the transition spans it holds
      // (transition-row-range-in-the-cut).
      _rangeSelections.selectionBlockStartsByLayer() != null ||
      _selectionTransitionStarts != null;

  /// The transition spans THE live selection holds, either axis.
  Map<LayerId, Set<int>>? get _selectionTransitionStarts =>
      _transitions.transitionStartsHeldBy(
        inCut: _selection.frameRangeSelection.value,
        onTrack: _selection.trackFrameRangeSelection.value,
      );

  /// Whether a live CELL band owns the next cell-verb press.
  ///
  /// A band is a subject claim, not a hint: the row the user swept is the
  /// row the verb acts on, and a band holding nothing this verb may touch
  /// makes the press a NO-OP — never a redirect onto whatever row happens
  /// to be active (a cell drag never moves the active layer, so those are
  /// routinely different rows).
  ///
  /// This is what keeps the collector's `null` from meaning two things.
  /// It answers "no band at all"; the collector answers "nothing in the
  /// band is editable". Reading only the collector let a refused band
  /// fall through and delete an unselected row's drawing.
  bool get cellSelectionClaimsSubject =>
      _selection.frameRangeSelection.value != null;

  bool get canDeleteCellAtCurrentFrame {
    if (canDeleteCellForSelection) {
      return true;
    }
    // 🚨F-87 (유저 2026-09-12: 「트랜스폼 헤더에 서있으면 … 키가 없을때
    // 삭제하면 레이어의 프레임이 삭제됨. 이런거 없도록」): a LANE row claims
    // the press the way a cell band does — with nothing on it this press may
    // take, the answer is nothing, never the cel of the layer the lane
    // belongs to (R10 #19 made the row its own subject; this rung had not
    // heard).
    if (_laneVerbs.laneVerbRange != null) {
      return false;
    }
    if (cellSelectionClaimsSubject) {
      return false;
    }
    final layer = _selection.activeLayer;
    // The transition row deletes the span its mark SHOWS, on the global row
    // (transition-row-open-in-the-cut) — its cells are a projection, which
    // no cut-local cel verb may read as its own. An O.L's mark is not the
    // cut's to delete (유저 2026-09-26).
    if (layer?.kind == LayerKind.transition) {
      return _transitions.transitionSpanStartEditableInCutAt(
            _controllers.timelineController.currentFrameIndex,
          ) !=
          null;
    }
    // SYNCED attach rows: cel removal is out of v1 scope (delete the row
    // or undo the creation) — cells are display material there. Free
    // attach rows delete cells like normal (UI-R21 #3).
    //
    // SINGLE-CEL (image) rows: the one picture IS the row (its cel is
    // born with it and there is no empty state in its world), so the row
    // is what you delete. Without this the button lit and did nothing —
    // the covering normalization rebuilt the cel from the same write, so
    // the press only cost a phantom undo entry (D22).
    if (layer == null ||
        isSyncedAttachedLayer(layer) ||
        layer.kind.holdsSingleCel) {
      return false;
    }

    return _controllers.timelineController.canDeleteCellAt(
      layer: layer,
      frameIndex: _controllers.timelineController.currentFrameIndex,
    );
  }

  void deleteCellAtCurrentFrame() {
    // R10 #19: a property row is its own subject — see
    // [canDeleteCellAtCurrentFrame].
    final lane = _laneVerbs.laneVerbRange;
    // F-87: the lane row takes the whole press — an fx header's range removes
    // the effect, other lanes lose their keys, and nothing falls through to
    // the cel below when there is nothing to take.
    if (lane != null) {
      _laneVerbs.deleteForLaneSelection(lane);
      return;
    }
    // A live selection routes the delete to EVERY selected block on
    // EVERY spanned layer (UI-R17 #2/#8) and to the transition spans it
    // holds, in one composite undo; the leftover selection covers empty
    // cells so it clears with the delete.
    final selectionTargets = _rangeSelections.selectionBlockStartsByLayer();
    final transitionTargets = _selectionTransitionStarts;
    if (selectionTargets != null || transitionTargets != null) {
      _project.historyManager.runAsOneStep('Delete selected cells', () {
        if (selectionTargets != null) {
          _controllers.timelineController.deleteBlocksForLayers(
            selectionTargets,
          );
        }
        if (transitionTargets != null) {
          _transitions.removeTransitionSpans(transitionTargets);
        }
      });
      // Whichever axis answered: the leftover span covers empty cells now.
      _selection.clearFrameRangeSelection();
      _selection.clearStoryboardCutSelection();
      _changes.notifyChanged();
      return;
    }
    if (cellSelectionClaimsSubject) {
      // The band holds nothing this verb may delete — that is a no-op,
      // not a licence to edit whatever row is active.
      return;
    }
    final layer = _selection.activeLayer;
    if (layer == null || !canDeleteCellAtCurrentFrame) {
      return;
    }
    if (layer.kind == LayerKind.transition) {
      final start = _transitions.transitionSpanStartEditableInCutAt(
        _controllers.timelineController.currentFrameIndex,
      );
      if (start != null) {
        _transitions.removeTransitionSpanAt(start);
      }
      return;
    }

    _controllers.timelineController.deleteCellForLayer(layerId: layer.id);
    _changes.notifyChanged();
  }

  // --- 링크 독립 (I-45): the frame-axis rung --------------------------------

  /// The runs a frame-axis 링크 독립 press means, one per row.
  ///
  /// ★DELETE'S TARGETS from the same press, read through the same claims
  /// (유저 2026-09-23: 「다른 편집버튼등의 로직 그대로 … 선택안하면
  /// 현재프레임, 선택하면 해당 선택한 소재가 기준」): a LANE row claims the
  /// press and has no cels (F-87); a band means every block it touches on
  /// every row it spans ([RangeSelections.selectionBlockStartsByLayer]); a
  /// band that touches none claims the press with nothing in it; with no
  /// band, the block under the playhead on the active row.
  ///
  /// ⚠️A row's blocks become ONE run, first start to last end — the band is
  /// contiguous, so everything between them is the band's too.
  List<UnlinkRun> _unlinkRuns() {
    if (_laneVerbs.laneVerbRange != null) {
      return const [];
    }
    final byLayer = _rangeSelections.selectionBlockStartsByLayer();
    if (byLayer == null) {
      if (cellSelectionClaimsSubject) {
        return const [];
      }
      final layer = _selection.activeLayer;
      if (layer == null || !rowHoldsLinks(layer)) {
        return const [];
      }
      final run = _controllers.timelineController.runAtPlayheadForLayer(
        layer.id,
      );
      return [(layer: layer, index: run.index, count: run.count)];
    }
    final runs = <UnlinkRun>[];
    for (final MapEntry(key: layerId, value: starts) in byLayer.entries) {
      final layer = _project.rangeLayerById(layerId);
      if (layer == null || !rowHoldsLinks(layer) || starts.isEmpty) {
        continue;
      }
      final first = starts.reduce((a, b) => a < b ? a : b);
      final last = starts.reduce((a, b) => a > b ? a : b);
      final end = last + (layer.timeline[last]?.length ?? 1);
      runs.add((layer: layer, index: first, count: end - first));
    }
    return runs;
  }

  /// Whether the frame axis holds a cel this press would give a copy of its
  /// own — the rung's gate, from the same runs its press takes.
  bool get canUnlinkCells =>
      _clipboard.sharedCelsIn(_unlinkRuns()).isNotEmpty;

  /// 링크 독립 on the frame axis ([FrameClipboard.unlinkRuns]).
  void unlinkCells() => _clipboard.unlinkRuns(_unlinkRuns());
}
