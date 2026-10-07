import '../../models/conte/conte_ink_keys.dart'
    show conteInkRowLayerId;
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
import 'active_cut_controllers.dart';
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
  StoryboardCursor({required ProjectAccess project, required SelectionAccess selection, required TimelineAccess timeline, required ChangeSink changes, required FrameIds frameIds, required ActiveCutControllers controllers, required RangeSelections rangeSelections, required CellVerbs cells, required CutVerbs cutVerbs, required Transitions transitions}) : _project = project, _selection = selection, _timeline = timeline, _changes = changes, _frameIds = frameIds, _controllers = controllers, _rangeSelections = rangeSelections, _cells = cells, _cutVerbs = cutVerbs, _transitions = transitions;

  final CellVerbs _cells;
  final CutVerbs _cutVerbs;
  final Transitions _transitions;

  final ProjectAccess _project;
  final SelectionAccess _selection;
  final TimelineAccess _timeline;
  final ChangeSink _changes;
  final FrameIds _frameIds;
  final ActiveCutControllers _controllers;
  final RangeSelections _rangeSelections;

  /// Why the storyboard toggle is refused, or null when it is allowed.
  ///
  /// A cut holds at most ONE storyboard row: the conte has one strip per
  /// cut and the coverage rule has one row to tile it. The toggle says so
  /// rather than silently doing nothing, and rather than making the second
  /// row that used to red-screen the V row.
  String? get targetLayerStoryboardRefusal {
    final targetLayer = _selection.activeLayer;
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
    // The cell counts the conte's frames; the row's keys count the cut's
    // (F-227: an arriving O.L's のりしろ comes first).
    final blockStart =
        storyboardConteStart(layer.timeline) + cells[cellIndex].startIndex;
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

  /// 🚨THE HANDWRITING ID A BLOCK'S FIRST STROKE ON THE CONTE WOULD TAKE,
  /// named before it exists — the block of [cutId]'s storyboard row that
  /// opens at [startFrame].
  ///
  /// A block is written on under its own id (`ExposureMemo.inkId`); one
  /// never written on has none, so the pen writes under this name, and the
  /// stroke's landing puts it on the block ([writeConteBlockInk]) — the
  /// canvas's `frameIdForNextCel`, said of a block.
  ///
  /// ⚠️Minted by the drawings' own mint — an id no other in this run has.
  /// An id free in the PROJECT is not free: an undone first stroke and a
  /// deleted block both give theirs up while the session still holds the
  /// surface, and a redo or an undo hands it back.
  String conteInkIdFor(CutId cutId, int startFrame) =>
      _unwrittenInk.putIfAbsent(
        (cutId, startFrame),
        () => _frameIds.mintFrameId(conteInkRowLayerId).value,
      );

  final Map<(CutId, int), String> _unwrittenInk = {};

  /// Puts [inkId] on the block of [cutId] it was named for
  /// ([conteInkIdFor]) — undoably, and while a stroke's landings fold, in
  /// the stroke's own step. So a landing only says which handwriting it
  /// was drawn into. Nothing when no block was named so, or the block that
  /// opens there has its own already.
  void writeConteBlockInk(CutId cutId, String inkId) {
    final named = [
      for (final MapEntry(key: (owner, start), :value) in _unwrittenInk.entries)
        if (owner == cutId && value == inkId) start,
    ];
    final cut = _project.cutById(cutId);
    final layer = cut == null ? null : storyboardLayerForCut(cut);
    if (named.isEmpty || layer == null) {
      return;
    }
    // Named in the conte's frames (the conte tab's cell); the row counts
    // the cut's (F-227).
    final start = named.single;
    final key = storyboardConteStart(layer.timeline) + start;
    final entry = layer.timeline[key];
    final memo = entry?.memo ?? const ExposureMemo.empty();
    if (entry == null ||
        !entry.isDrawing ||
        entry.ghost ||
        memo.inkId.isNotEmpty) {
      return;
    }
    _unwrittenInk.remove((cutId, start));
    _project.cutCommandCoordinator.updateExposureMemo(
      cutId: cutId,
      layerId: layer.id,
      blockStartIndex: key,
      memo: memo.copyWith(inkId: inkId),
    );
    _changes.notifyChanged();
  }

  /// The BLOCK under the storyboard cursor, whatever its kind: the standing
  /// V row's cut, the standing S row's SE block, or the transition row's
  /// span. Null where the cursor covers nothing (a gap is an honest
  /// nothing, not a fallback to the other panel's subject).
  StoryboardCursorBlock? storyboardCursorBlockOrNull() {
    switch (_selection.storyboardStandingRow) {
      case LayerRowAddress(:final layerId)
          when _project.isTrackTransitionLayerId(layerId):
        final span = _transitions.transitionSpanAt(_selection.editingGlobalFrame);
        if (span == null) {
          return null;
        }
        return StoryboardCursorTransitionSpan(span.key, span.value.length);
      case LayerRowAddress(:final layerId):
        return _rowBlockUnderCursor(layerId);
      case LaneRowAddress():
        // A lane row holds keys, not blocks — the lane-verb family owns it.
        return null;
      case TrackRowAddress():
        // Not parked in a gap ⇒ the cut-local playhead sits inside the
        // ACTIVE cut, so the cut under the cursor is that cut by
        // construction (the storyboard's cell press promotes it).
        if (_timeline.editingSession.playheadInGap) {
          return null;
        }
        final cut = _project.activeCutOrNull;
        if (cut == null) {
          return null;
        }
        // D28: with a storyboard layer on the cut, the frame verbs target
        // the PANEL under the cut-local cursor; a cut with NO storyboard
        // layer keeps the old cut-block law outright.
        return _panelUnderCursor(cut) ?? StoryboardCursorCutBlock(cut);
    }
  }

  /// The BLOCK under the TIMELINE's cursor — the row that panel stands on
  /// ([Standing.timelineStandingRow]) × the playhead: the block of a cut's
  /// own row, a track-owned S row's, or the transition row's span. Null where
  /// the cursor covers nothing.
  ///
  /// 🗣️F-283 (유저 2026-10-04): 「타임라인패널의 se블록에 대해 코마조절
  /// 1,2,3,4 버튼이 작동안함. 콘티패널에선 작동하는데. 또 법 멋대로
  /// 사본만든건지 발견된거같은데 통일. 다른 글로벌트랙도 확인하는거 잊지말고.
  /// 블록이면 1,2,3,4 등 코마조절버튼 작동하는게 규칙임」.
  ///
  /// ↩️The timeline's comma press read the block off the ACTIVE row's
  /// cut-local display and handed its start on as it was. An S row's blocks
  /// are keyed on the TRACK's axis, so past the first cut that start named
  /// nothing and the press — its button lit — did nothing; the transition
  /// row's spans are no timeline entries at all, so it never found one
  /// (🧪measured 2026-10-06). Both panels resolve a KIND now, and one
  /// dispatch takes it ([EdgeDragVerbs.setCommaForTimelineCursor]).
  ///
  /// What differs from the storyboard's cursor is the standing place, not
  /// the law: this panel shows no V row, and its transition row is the
  /// cut's view — a span the cut draws but does not edit (an O.L's mark,
  /// 유저 2026-09-26) is not under its cursor.
  StoryboardCursorBlock? timelineCursorBlockOrNull() {
    switch (_selection.timelineStandingRow) {
      case LayerRowAddress(:final layerId)
          when _project.isTrackTransitionLayerId(layerId):
        final start = _transitions.transitionSpanStartEditableInCutAt(
          _controllers.timelineController.currentFrameIndex,
        );
        final span = start == null
            ? null
            : _selection.activeTrack.transitionLayer.instructions[start];
        return span == null
            ? null
            : StoryboardCursorTransitionSpan(start!, span.length);
      case LayerRowAddress(:final layerId):
        return _rowBlockUnderCursor(layerId);
      case LaneRowAddress():
        // A lane row claims the press the way the storyboard's does (F-87:
        // never the cel of the layer the lane belongs to).
        return null;
      case TrackRowAddress():
        // 「타임라인에서는 타임라인의 것을」 — cuts are the storyboard's.
        return null;
    }
  }

  /// The block the cursor stands on in [layerId]'s row, in the row's COMMIT
  /// keys — a track-owned S row's on the TRACK's axis, a cut's own row's in
  /// its cut. One kind for both: a row's block takes the same verbs
  /// whichever axis its row keys.
  StoryboardCursorRowBlock? _rowBlockUnderCursor(LayerId layerId) {
    final global = _project.trackSeGlobalLayerById(layerId);
    final frame = global == null
        ? _controllers.timelineController.currentFrameIndex
        : _selection.editingGlobalFrame;
    final row = global ?? _rangeSelections.cutRowWithTimingOfItsOwn(layerId);
    if (row == null || frame < 0) {
      return null;
    }
    final block = coveringDrawingBlockAt(row.timeline, frame);
    if (block == null || block.entry.ghost) {
      return null;
    }
    return StoryboardCursorRowBlock(layerId, block.startIndex);
  }

  /// D28: the conte PANEL the cut-local cursor stands on in [cut]'s
  /// storyboard row. Null without a row — and for a ghost or uncovered
  /// cell (junk the coverage rule merely tolerates), which falls back to
  /// the cut block rather than lighting a verb the machinery will refuse
  /// (T25).
  ///
  /// The storyboard's cursor stands in the CONTE's time; the row's keys
  /// count the cut's frames, which begin earlier in a cut an O.L arrives
  /// into (F-227).
  StoryboardCursorStoryboardPanel? _panelUnderCursor(Cut cut) {
    final row = storyboardLayerForCut(cut);
    if (row == null) {
      return null;
    }
    final panel = coveringDrawingBlockAt(
      row.timeline,
      storyboardConteStart(row.timeline) +
          _controllers.timelineController.currentFrameIndex,
    );
    if (panel == null || panel.entry.ghost || panel.startIndex < 0) {
      return null;
    }
    return StoryboardCursorStoryboardPanel(
      cut,
      row,
      panel.startIndex,
      panel.entry.length!,
    );
  }

  /// Whether the storyboard's comma press (1/2/3/4/N) has a target: a live
  /// selection's blocks — either axis — else the block under the cursor.
  bool get canSetCommaForStoryboardCursor =>
      _canSetCommaOf(storyboardCursorBlockOrNull);

  /// The same gate for the TIMELINE's press ([timelineCursorBlockOrNull]).
  ///
  /// ↩️Its cursor rung borrowed the DELETE gate, which answers for subjects
  /// this press has no branch for: an image row's block, which the press
  /// then refused, and a lane's key, where the press re-timed the cel of the
  /// layer the lane belongs to. One resolver for the pair now (T25).
  bool get canSetCommaForTimelineCursor =>
      _canSetCommaOf(timelineCursorBlockOrNull);

  bool _canSetCommaOf(StoryboardCursorBlock? Function() cursorBlock) {
    if (_rangeSelections.selectionBlockStartsByLayer() != null) {
      return true;
    }
    // Its own dispatch already stops at a live cell band (the selection's
    // half of the press claims it — [ExposureVerbs.setCommaForSelection]),
    // so the gate stops there too — otherwise the band falls through to the
    // CURSOR rung and lights the buttons off a block the press will never
    // reach.
    if (_cells.cellSelectionClaimsSubject) {
      return false;
    }
    return switch (cursorBlock()) {
      null => false,
      // ⛔An SE block used to answer `activeCutOrNull != null` here, on the
      // grounds that "a parked playhead has no cut to lens through" — the
      // lens is 0 for a track row and the lookup no longer wants a cut
      // (H11). A global row is reachable wherever it is standing.
      StoryboardCursorRowBlock() ||
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
        StoryboardCursorRowBlock() ||
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
      case StoryboardCursorRowBlock(:final layerId, :final blockStartIndex):
        // ⛔This used to return when `activeCutOrNull == null` — the fourth
        // copy of the sentence H11 retired (「a parked playhead has no cut
        // to lens through」, 유저 2026-08-22: 「각 행들은 독립적인 글로벌행이라
        // 뭐든 가능해야함」). The gate above already lights the verb in a
        // gap; the lookup below finds the track row without a cut; the verb
        // was the one still refusing. Found by the adversarial check on the
        // 2026-09-02 cut — the verb had no test of its own.
        _controllers.timelineController.deleteBlocksForLayers({
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
    final rowLayerId = _selection.storyboardStandingRow.owningLayerId;
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
    // The gate's own question — a lane answers with its row — so a lane
    // stood on is not a cast away from a crash.
    final layerId = _selection.storyboardStandingRow.owningLayerId!;
    // ⚠️The fills funnel re-applies the track-SE display lens on the way in
    // (the active cut's global start) — pre-subtract the SAME expression,
    // exactly as [_createTrackSeEntriesForRange] does, or the entry lands
    // double-shifted.
    final commands = _controllers.timelineController
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
    _project.historyManager.executeAsOneStep('Create SE entry', commands);
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
      return _controllers.timelineController.currentFrameIndex != panelStartIndex;
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
      if (_controllers.timelineController.currentFrameIndex == panelStartIndex) {
        return;
      }
      _controllers.timelineController.createDrawingFrameForLayer(
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

/// A ROW's block — an S row's, or (from the timeline) a cut's own row's.
///
/// ↩️`StoryboardCursorSeBlock` until F-283: the storyboard's cursor was the
/// only one resolved to a kind, and the S rows the only layer rows it
/// stands on. A cel row's block takes the same verbs.
class StoryboardCursorRowBlock extends StoryboardCursorBlock {
  const StoryboardCursorRowBlock(this.layerId, this.blockStartIndex);

  final LayerId layerId;

  /// In the row's COMMIT keys — GLOBAL for an S row, whose timeline lives
  /// on the track's axis; cut-local for a cut's own row.
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
