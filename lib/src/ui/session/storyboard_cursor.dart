import '../../models/cut.dart';
import '../../models/cut_id.dart';
import '../../models/exposure_memo.dart';
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/layer_kind.dart';
import '../../models/storyboard_coverage.dart';
import '../../models/timeline_coverage.dart';
import '../../models/timeline_row_address.dart';
import '../storyboard_layer_policy.dart';
import '../text/app_strings.dart';
import '../../services/command.dart';
import 'session_roles.dart';
import 'range_selections.dart';
import 'cell_verbs.dart';
import 'cut_verbs.dart';
import 'transitions.dart';

/// The STORYBOARD CURSOR — what the cell under the storyboard cursor is,
/// and the verbs that act there: the comma, deleting the block, creating an
/// SE entry or a panel, the cell action — as its own object.
///
/// 🚨A collaborator carved out of `EditorSessionManager` (the audit's SRP cut,
/// 2026-09-02). Measured before cutting: nothing of its own and seventeen
/// session members touched. It names the roles it needs in its constructor.
class StoryboardCursor {
  StoryboardCursor({required ProjectAccess project, required SelectionAccess selection, required ChangeSink changes, required FrameIds frameIds, required TimelineAccess timeline, required SessionInternals internals, required RangeSelections rangeSelections, required CellVerbs cells, required CutVerbs cutVerbs, required Transitions transitions}) : _project = project, _selection = selection, _changes = changes, _frameIds = frameIds, _timeline = timeline, _internals = internals, _rangeSelections = rangeSelections, _cells = cells, _cutVerbs = cutVerbs, _transitions = transitions;

  final CellVerbs _cells;
  final CutVerbs _cutVerbs;
  final Transitions _transitions;

  final ProjectAccess _project;
  final SelectionAccess _selection;
  final ChangeSink _changes;
  final FrameIds _frameIds;
  final TimelineAccess _timeline;
  final SessionInternals _internals;
  final RangeSelections _rangeSelections;

  /// Why the storyboard toggle is refused, or null when it is allowed.
  ///
  /// A cut holds at most ONE storyboard row: the conte has one strip per
  /// cut and the coverage rule has one row to tile it. The toggle says so
  /// rather than silently doing nothing, and rather than making the second
  /// row that used to red-screen the V row.
  String? get targetLayerStoryboardRefusal {
    final targetLayer = _internals.targetLayerForKindToggle;
    if (targetLayer == null || targetLayer.kind == LayerKind.storyboard) {
      return null;
    }
    final cut = _project.activeCutOrNull;
    if (cut == null ||
        cutAcceptsAnotherStoryboardLayer(cut, exceptLayerId: targetLayer.id)) {
      return null;
    }
    return AppText.strings.sbOneStoryboardRowPerCut;
  }

  /// Writes a conte cell's ACTION text, undoably.
  ///
  /// A cell is a panel of the cut's storyboard row, so the text lands on the
  /// exposure that OPENS it — block-owned like the inbetween dots, which is
  /// what lets it ride every move and copy with no re-indexing. Typing into
  /// a cut with no storyboard row does nothing yet: there is no block to
  /// hang it on until the row exists.
  void setStoryboardCellAction({
    required CutId cutId,
    required int cellIndex,
    required String action,
  }) {
    final cut = _project.cutById(cutId);
    if (cut == null) {
      return;
    }
    final layer = storyboardLayerForCut(cut);
    if (layer == null) {
      return;
    }
    final cells = storyboardCoverageCells(
      timeline: layer.timeline,
      cutDuration: cut.duration,
    );
    if (cellIndex < 0 || cellIndex >= cells.length) {
      return;
    }
    final blockStart = cells[cellIndex].startIndex;
    final entry = layer.timeline[blockStart];
    if (entry == null || !entry.isDrawing || entry.ghost) {
      return;
    }
    _project.cutCommandCoordinator.updateExposureMemo(
      cutId: cutId,
      layerId: layer.id,
      blockStartIndex: blockStart,
      memo: (entry.memo ?? const ExposureMemo.empty()).copyWith(
        actionMemo: action,
      ),
    );
    _changes.notifyChanged();
  }

  /// The BLOCK under the storyboard cursor, whatever its kind: the standing
  /// V row's cut, the standing S row's SE block, or the transition row's
  /// span. Null where the cursor covers nothing (a gap is an honest
  /// nothing, not a fallback to the other panel's subject).
  StoryboardCursorBlock? storyboardCursorBlockOrNull() {
    switch (_selection.selectedRow) {
      case LayerRowAddress(:final layerId)
          when _project.isTrackTransitionLayerId(layerId):
        final span = _transitions.transitionSpanAt(_selection.editingGlobalFrame);
        if (span == null) {
          return null;
        }
        return StoryboardCursorTransitionSpan(span.key, span.value.length);
      case LayerRowAddress(:final layerId):
        final global = _project.trackSeGlobalLayerById(layerId);
        final frame = _selection.editingGlobalFrame;
        if (global == null || frame < 0) {
          return null;
        }
        final block = coveringDrawingBlockAt(global.timeline, frame);
        if (block == null || block.entry.ghost) {
          return null;
        }
        return StoryboardCursorSeBlock(layerId, block.startIndex);
      case LaneRowAddress():
        // A lane row holds keys, not blocks — the lane-verb family owns it.
        return null;
      case TrackRowAddress():
        // Not parked in a gap ⇒ the cut-local playhead sits inside the
        // ACTIVE cut, so the cut under the cursor is that cut by
        // construction (the storyboard's cell press promotes it).
        if (_internals.editingPlayheadInGap) {
          return null;
        }
        final cut = _project.activeCutOrNull;
        if (cut == null) {
          return null;
        }
        // D28: with a storyboard layer on the cut, the frame verbs target
        // the PANEL under the cut-local cursor. A ghost or uncovered cell
        // (junk the coverage rule merely tolerates) falls back to the cut
        // block rather than lighting a verb the machinery will refuse
        // (T25); a cut with NO storyboard layer keeps the old cut-block
        // law outright.
        final row = storyboardLayerForCut(cut);
        if (row != null) {
          final panel = coveringDrawingBlockAt(
            row.timeline,
            _timeline.timelineController.currentFrameIndex,
          );
          if (panel != null && !panel.entry.ghost && panel.startIndex >= 0) {
            return StoryboardCursorStoryboardPanel(
              cut,
              row,
              panel.startIndex,
              panel.entry.length!,
            );
          }
        }
        return StoryboardCursorCutBlock(cut);
    }
  }

  /// Whether the storyboard's comma press (1/2/3/4/N) has a target: a live
  /// selection's blocks — either axis — else the block under the cursor.
  bool get canSetCommaForStoryboardCursor {
    if (_rangeSelections.selectionBlockStartsByLayer() != null) {
      return true;
    }
    // Its own dispatch already stops at a live band ([setCommaForStoryboardCursor]
    // returns inside the selection branch), so the gate stops there too —
    // otherwise the band falls through to the CURSOR rung and lights the
    // buttons off a cut block the press will never reach.
    if (_cells.cellSelectionClaimsSubject) {
      return false;
    }
    return switch (storyboardCursorBlockOrNull()) {
      null => false,
      // ⛔An SE block used to answer `activeCutOrNull != null` here, on the
      // grounds that "a parked playhead has no cut to lens through" — the
      // lens is 0 for a track row and the lookup no longer wants a cut
      // (H11). A global row is reachable wherever it is standing.
      StoryboardCursorSeBlock() ||
      StoryboardCursorCutBlock() ||
      StoryboardCursorTransitionSpan() ||
      StoryboardCursorStoryboardPanel() => true,
    };
  }

  /// Whether the storyboard's delete has a block under the cursor (its
  /// selection rungs are asked separately — see the toolbar context).
  bool get canDeleteBlockAtStoryboardCursor =>
      switch (storyboardCursorBlockOrNull()) {
        null => false,
        // H11: a track row answers wherever it stands — see the create gate.
        StoryboardCursorSeBlock() ||
        StoryboardCursorCutBlock() ||
        StoryboardCursorTransitionSpan() ||
        // D28 ⚠️: delete keeps the CUT answer for now — whether the shared
        // delete should remove the PANEL instead is a recorded user
        // question (the frame pill retargeted; the verb matrix beyond it
        // is the user's to rule).
        StoryboardCursorStoryboardPanel() => true,
      };

  /// Deletes THE BLOCK UNDER THE CURSOR, whatever its kind — the cut, the
  /// SE block, or the transition span, each through its own existing
  /// removal verb. One undo step each, like the cell delete it mirrors.
  void deleteBlockAtStoryboardCursor() {
    switch (storyboardCursorBlockOrNull()) {
      case null:
        return;
      case StoryboardCursorCutBlock() || StoryboardCursorStoryboardPanel():
        _cutVerbs.deleteActiveCut();
      case StoryboardCursorSeBlock(:final layerId, :final blockStartIndex):
        // ⛔This used to return when `activeCutOrNull == null` — the fourth
        // copy of the sentence H11 retired (「a parked playhead has no cut
        // to lens through」, 유저 2026-08-22: 「각 행들은 독립적인 글로벌행이라
        // 뭐든 가능해야함」). The gate above already lights the verb in a
        // gap; the lookup below finds the track row without a cut; the verb
        // was the one still refusing. Found by the adversarial check on the
        // 2026-09-02 cut — the verb had no test of its own.
        _timeline.timelineController.deleteBlocksForLayers({
          layerId: [blockStartIndex],
        });
        _changes.notifyChanged();
      case StoryboardCursorTransitionSpan():
        _transitions.removeTransitionSpanAt(_selection.editingGlobalFrame);
    }
  }

  /// Whether the frame `＋` can author a fresh SE entry on the standing S
  /// row: standing there, on an EMPTY cursor frame. That is the whole gate.
  ///
  /// ⛔It used to ask for an ACTIVE CUT as well, so the button went dead in
  /// a gap — 「S행이 컷이 없는 갭에서 프레임추가가 안됨. 버튼활성안됨」
  /// (유저 H11, 2026-08-22). The cut was never this row's business; it was
  /// standing in for `_requireLayer`, which demanded a cut before it would
  /// reach the track's own layers. That lookup answers for a track row now.
  bool get canCreateSeEntryAtStoryboardCursor {
    // Standing on one of the row's LANES answers with the row (C3-lane-move,
    // and [LaneRowAddress]'s own law: standing on a property must never cost
    // you the layer).
    final rowLayerId = _selection.selectedRow.owningLayerId;
    if (rowLayerId == null || _project.isTrackTransitionLayerId(rowLayerId)) {
      return false;
    }
    final global = _project.trackSeGlobalLayerById(rowLayerId);
    final frame = _selection.editingGlobalFrame;
    return global != null &&
        frame >= 0 &&
        coveringDrawingBlockAt(global.timeline, frame) == null;
  }

  /// One blank one-frame dialogue entry at the cursor — the cut-scoped SE
  /// creation ([SeEntries.createSeEntryAtCurrentFrame]) said of the standing row, via
  /// the SAME fills funnel the track-range create commits through.
  void createSeEntryAtStoryboardCursor() {
    if (!canCreateSeEntryAtStoryboardCursor) {
      return;
    }
    final row = _selection.selectedRow as LayerRowAddress;
    final layerId = row.layerId;
    // ⚠️The fills funnel re-applies the track-SE display lens on the way in
    // (the active cut's global start) — pre-subtract the SAME expression,
    // exactly as [_createTrackSeEntriesForRange] does, or the entry lands
    // double-shifted.
    final commands = _timeline.timelineController
        .drawingFramesCommandsForLayers({
          layerId: [
            (
              startIndex:
                  _selection.editingGlobalFrame -
                  _project.activeCutGlobalStartFrame,
              length: 1,
              frameId: _frameIds.mintFrameId(layerId),
              name: '',
            ),
          ],
        });
    if (commands.isEmpty) {
      return;
    }
    _project.historyManager.execute(
      commands.length == 1
          ? commands.single
          : CompositeCommand(
              description: 'Create SE entry',
              commands: commands,
            ),
    );
    _changes.notifyChanged();
  }

  /// D28: whether the frame ＋ can DIVIDE the storyboard panel under the
  /// cursor. An existing division START refuses — there is nothing to
  /// divide there (the timeline's own creation law); gate and dispatch
  /// read the ONE cursor resolver (T25).
  bool get canCreateStoryboardPanelAtCursor {
    if (storyboardCursorBlockOrNull() case StoryboardCursorStoryboardPanel(
      :final panelStartIndex,
    )) {
      return _timeline.timelineController.currentFrameIndex != panelStartIndex;
    }
    return false;
  }

  /// D28: divides the panel under the cursor — the covering division
  /// splits, the new drawing taking the rest of the hold, exactly as the
  /// timeline's ＋ divides a held block.
  void createStoryboardPanelAtCursor() {
    if (storyboardCursorBlockOrNull() case StoryboardCursorStoryboardPanel(
      :final row,
      :final panelStartIndex,
    )) {
      if (_timeline.timelineController.currentFrameIndex == panelStartIndex) {
        return;
      }
      _timeline.timelineController.createDrawingFrameForLayer(
        layerId: row.id,
        frameId: _frameIds.mintFrameId(row.id),
      );
      _changes.notifyChanged();
    }
  }
}

/// B8 — the block under the STORYBOARD cursor (standing row × track-global
/// playhead), resolved once per verb so the gates and the dispatches read
/// one answer. Kinds, not rules: every kind takes the same verbs (comma =
/// length, delete = removal), each through its own existing machinery.
sealed class StoryboardCursorBlock {
  const StoryboardCursorBlock();
}

class StoryboardCursorCutBlock extends StoryboardCursorBlock {
  const StoryboardCursorCutBlock(this.cut);

  final Cut cut;
}

class StoryboardCursorSeBlock extends StoryboardCursorBlock {
  const StoryboardCursorSeBlock(this.layerId, this.blockStartIndex);

  final LayerId layerId;

  /// GLOBAL — the S rows' timelines live on the track's axis.
  final int blockStartIndex;
}

class StoryboardCursorTransitionSpan extends StoryboardCursorBlock {
  const StoryboardCursorTransitionSpan(this.spanStartIndex, this.spanLength);

  final int spanStartIndex;
  final int spanLength;
}

/// D28: the cut's STORYBOARD PANEL under the cursor — with a storyboard
/// layer on the cut, the frame verbs target the panel, not the cut
/// (「스토리보드레이어 존재 시 대상이 스토리보드레이어로」, the later law
/// superseding 「컷블록 위 4 = 컷길이 4」 exactly where a panel exists).
class StoryboardCursorStoryboardPanel extends StoryboardCursorBlock {
  const StoryboardCursorStoryboardPanel(
    this.cut,
    this.row,
    this.panelStartIndex,
    this.panelLength,
  );

  final Cut cut;
  final Layer row;

  /// CUT-LOCAL — the storyboard row lives inside its cut.
  final int panelStartIndex;
  final int panelLength;
}
