import 'dart:math' as math;

import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/row_block_shift.dart';
import '../../models/timeline_repeat.dart' show ghostFreeTimeline;
import '../../models/timeline_row_address.dart';
import '../../models/track_conte_row.dart' show isTrackConteRow;
import '../storyboard_layer_policy.dart' show conteLayerInHand;
import 'active_cut_controllers.dart';
import 'cut_shift.dart';
import 'session_roles.dart';
import 'track_se_display.dart';

/// What a frame shove acts on: which layer rows shift, from where, which
/// AXIS that anchor is stated in, and whether a SELECTION aimed it there —
/// rather than the row and cell stood on.
typedef FrameShiftScope = ({
  List<LayerId> layerIds,
  int anchorIndex,
  bool anchorIsGlobal,
  bool aimedBySelection,
});

/// THE SHOVE — push and pull, aimed at whatever is selected.
///
/// 🚨A collaborator carved out of `EditorSessionManager` (G4-2 of the
/// god-object decomposition, round 8, 2026-09-08). It holds the FRAME-axis
/// half whole — the scope, the axis translation, the slack and the commit —
/// and the aim that chooses between the two axes; [CutShift] is the cut
/// half, injected as the sibling it is.
///
/// --- PUSH / PULL (design D) ----------------------------------------------
///
/// The rigid shove a drag used to do, as a verb you aim. PUSH opens n
/// frames at the anchor and everything after it travels with its own
/// spacing intact; PULL closes them and stops where the first affected
/// row runs out of room. The arithmetic is [rowPullSlack] /
/// [timelineShiftedFrom] for both axes; only the commit differs — re-keyed
/// exposures on a layer row, a leading gap on a track's cuts.
///
/// SCOPE: the live selection's rows, anchored at its start; with no
/// selection, the current row at the current index.
class BlockShift {
  BlockShift({
    required ProjectAccess project,
    required SelectionAccess selection,
    required ChangeSink changes,
    required RetimeLaw retime,
    required TrackSeDisplay trackSe,
    required ActiveCutControllers controllers,
    required CutShift cutShift,
  }) : _project = project,
       _selection = selection,
       _changes = changes,
       _retime = retime,
       _trackSe = trackSe,
       _controllers = controllers,
       _cutShift = cutShift;

  final ProjectAccess _project;
  final SelectionAccess _selection;
  final ChangeSink _changes;
  final RetimeLaw _retime;
  final TrackSeDisplay _trackSe;
  final ActiveCutControllers _controllers;
  final CutShift _cutShift;

  /// The frame-axis scope ([FrameShiftScope]).
  ///
  /// A track-axis selection (the storyboard's S rows) arrives already in
  /// commit keys; a cut-local one has to be translated for those same rows.
  /// Carrying the axis is what keeps the shove from translating twice — and
  /// with the aim, says which selection goes along with the blocks
  /// ([_carryTheSelection]).
  FrameShiftScope? frameShiftScope({TimelineRowAddress? currentRow}) {
    final trackSelection = _selection.trackFrameRangeSelection.value;
    if (trackSelection != null) {
      final rows = <LayerId>[
        ...{
          for (final row in trackSelection.spanRows)
            if (row.owningLayerId case final id?
                when _project.trackSeGlobalLayerById(id) != null)
              id,
        },
      ];
      if (rows.isNotEmpty) {
        return (
          layerIds: rows,
          anchorIndex: trackSelection.startFrame,
          anchorIsGlobal: true,
          aimedBySelection: true,
        );
      }
    }
    final selection = _selection.frameRangeSelection.value;
    if (selection != null) {
      // Rows whose timing is not their own stand down —
      // [RetimeLaw.standsDownFromRetime].
      final rows = [
        for (final id in selection.spanLayerIds)
          if (!_retime.standsDownFromRetime(id) &&
              _project.rangeLayerById(id) != null)
            id,
      ];
      return rows.isEmpty
          ? null
          : (
              layerIds: rows,
              anchorIndex: selection.startIndex,
              anchorIsGlobal: false,
              aimedBySelection: true,
            );
    }
    return _standingShiftScope(currentRow);
  }

  /// The scope with NO selection: the current row at the current cell — the
  /// timeline's rule, applied to whichever rail asked. The storyboard's
  /// current row is an S row on the global axis, so its anchor is the global
  /// playhead.
  FrameShiftScope? _standingShiftScope(TimelineRowAddress? currentRow) {
    if (currentRow is LayerRowAddress &&
        _project.trackSeGlobalLayerById(currentRow.layerId) != null) {
      return (
        layerIds: [currentRow.layerId],
        anchorIndex: _selection.editingGlobalFrame,
        anchorIsGlobal: true,
        aimedBySelection: false,
      );
    }
    // The storyboard's conte row shoves its own panels — the conte layer it
    // has in hand, which is the active row below — or nothing: over a cut
    // with no conte layer the active row is some other row of the cut, and
    // that one is not this rail's to shove (I-73).
    if (isTrackConteRow(currentRow) &&
        conteLayerInHand(
              cut: _project.activeCutOrNull,
              activeLayerId: _selection.activeLayerId,
            ) ==
            null) {
      return null;
    }
    final layerId = _selection.activeLayerId;
    final index = _controllers.timelineController.currentFrameIndex;
    if (layerId == null ||
        index < 0 ||
        _retime.standsDownFromRetime(layerId) ||
        _project.rangeLayerById(layerId) == null) {
      return null;
    }
    return (
      layerIds: [layerId],
      anchorIndex: index,
      anchorIsGlobal: false,
      aimedBySelection: false,
    );
  }

  /// The layer a shift MEASURES against, in the axis the anchor will be
  /// translated to: track-SE rows ALWAYS answer with the global layer —
  /// [shiftAnchorFor] puts every anchor on that axis for them — and
  /// everything else with the cut-local range layer, matching a cut-local
  /// anchor. Measuring the SE display clone against the translated global
  /// anchor mixed the axes: the pull verb read zero slack in any cut past
  /// the first, and a mixed selection's pull sailed past the SE wall into
  /// an overlap crash.
  Layer? shiftLayerFor(LayerId layerId) => _project.isTrackSeLayerId(layerId)
      ? _project.trackSeGlobalLayerById(layerId)
      : _project.rangeLayerById(layerId);

  /// The scope's anchor as [layerId]'s own timeline keys it.
  int shiftAnchorFor(
    LayerId layerId,
    int anchorIndex, {
    required bool anchorIsGlobal,
  }) =>
      // Track-SE rows live on the GLOBAL axis, so a cut-local anchor has to
      // be translated before it can address their blocks. A global one is
      // already there.
      !anchorIsGlobal && _project.isTrackSeLayerId(layerId)
      ? _trackSe.commitBlockStart(layerId, anchorIndex)
      : anchorIndex;

  bool canPushFrames({TimelineRowAddress? currentRow}) =>
      frameShiftScope(currentRow: currentRow) != null;

  /// How far a frame PULL can travel: the LEAST slack across the scope's
  /// rows, so the whole scope stops where the first one touches.
  ///
  /// 🗣️F-237 (유저 2026-09-29): 「뒤 성질 홀드인 블록의 뒤 갭부분에서 앞으로
  /// 당기기가 안됨. 몇번이나 말하지만 홀드든 리피트든 성질로 만들어진
  /// 공간이라도 빈공간으로 작동은 해야함」 — F-137's law (a ghost neither
  /// moves nor obstructs a plan) that the retime and the edges already kept.
  /// ↩️The slack and the shift read the row WITH its ghosts, so the hold's
  /// cells were a block the pull could not close; both read the ghost-free
  /// row now, and the layer edit derives the ghosts again.
  int framePullSlack({TimelineRowAddress? currentRow}) {
    final scope = frameShiftScope(currentRow: currentRow);
    if (scope == null) {
      return 0;
    }
    var slack = 0x7fffffff;
    for (final layerId in scope.layerIds) {
      final layer = shiftLayerFor(layerId);
      if (layer == null) {
        continue;
      }
      slack = math.min(
        slack,
        rowPullSlack(
          blocks: timelineShiftableBlocks(ghostFreeTimeline(layer)),
          anchorIndex: shiftAnchorFor(
            layerId,
            scope.anchorIndex,
            anchorIsGlobal: scope.anchorIsGlobal,
          ),
        ),
      );
    }
    return slack == 0x7fffffff ? 0 : slack;
  }

  bool canPullFrames({TimelineRowAddress? currentRow}) =>
      framePullSlack(currentRow: currentRow) > 0;

  /// Opens [count] frames at the anchor across the scope's rows; the
  /// blocks after it keep their own spacing (empty space is carried, not
  /// eaten). ONE undo step for every row it touches.
  ///
  /// ⛔NOT a forwarder to delete (round 8, G4): push and pull are one verb
  /// in two directions, and [pullFrames] clamps its own argument against
  /// [framePullSlack] — a HOST measurement, next to the scope and the
  /// slack that [pushBlocks]/[pullBlocks] dispatch into. Deleting the push
  /// half alone would leave the pair split across two objects, and
  /// deleting both would put `-math.min(count, framePullSlack(…))` at
  /// every call site.
  ///
  /// ★G4-2 (2026-09-08) honoured that by moving the WHOLE set into this
  /// object instead: the scope, the slack, the commit and both halves of
  /// the aim are one class now, so "next to" still holds and no call site
  /// carries the clamp.
  void pushFrames(int count, {TimelineRowAddress? currentRow}) =>
      _shiftFrames(count, currentRow: currentRow);

  /// Closes up to [count] frames, clamped to [framePullSlack].
  void pullFrames(int count, {TimelineRowAddress? currentRow}) => _shiftFrames(
    -math.min(count, framePullSlack(currentRow: currentRow)),
    currentRow: currentRow,
  );

  /// The frame-axis COMMIT: every row in the scope re-keyed from the
  /// anchor, in one undo step.
  void _shiftFrames(int delta, {TimelineRowAddress? currentRow}) {
    final scope = frameShiftScope(currentRow: currentRow);
    if (scope == null || delta == 0) {
      return;
    }
    final edits = <({Layer before, Layer after})>[];
    for (final layerId in scope.layerIds) {
      // The COMMIT layer, never the display clone: a track-SE row's clone
      // is a projection and writing it back would drop the edit (the
      // clones are never written back).
      final before = _project.commitLayerById(layerId);
      if (before == null) {
        continue;
      }
      final anchor = shiftAnchorFor(
        layerId,
        scope.anchorIndex,
        anchorIsGlobal: scope.anchorIsGlobal,
      );
      final after = before.copyWith(
        timeline: timelineShiftedFrom(
          ghostFreeTimeline(before),
          anchorIndex: anchor,
          delta: delta,
        ),
      );
      if (after.timeline != before.timeline) {
        edits.add((before: before, after: after));
      }
    }
    if (edits.isEmpty) {
      return;
    }
    _controllers.timelineController.commitLayerTimelineDrags(edits);
    if (scope.aimedBySelection) {
      _carryTheSelection(delta, onTrack: scope.anchorIsGlobal);
    }
    // A layer-timeline write, and what one owes — the comma edge's own
    // ending (`ExposureEdgeDrag.commit`). ↩️It ran the CUT commands' tidy-up
    // (`refreshAfterCutCommand`), which drops the frame selection: F-264
    // (유저 2026-10-02) 「타임라인 버튼 밀기/당기기 작동시 선택범위로
    // 여러행선택한거라던가 블록 선택범위 풀리는데 안풀리도록」. Nobody had
    // asked for the drop — the shove was born beside the cut axis' half,
    // which does owe that tidy-up, and took its ending along.
    _changes.warmActiveCut();
    _changes.notifyChanged();
  }

  /// The selection that aimed a shove, carried the way its blocks went:
  /// the track's for an S row's sounds
  /// ([carryTrackSelectionWithTheShove], which says why), the cut's own for
  /// its rows.
  void _carryTheSelection(int delta, {required bool onTrack}) {
    if (onTrack) {
      carryTrackSelectionWithTheShove(_selection, delta);
    } else if (_selection.frameRangeSelection.value case final inCut?) {
      _selection.frameRangeSelection.value = inCut.shiftedBy(delta);
    }
  }

  // --- ONE push / pull -----------------------------------------------------
  //
  // Push and pull are ONE verb aimed at whatever is selected, not two
  // verbs the user picks between: a cut is a block on the cut row exactly
  // as an exposure is a block on a layer row, so "shove from here" means
  // the same thing on both and only the commit differs.
  //
  // [currentRow] is the asking rail's current row, used only when nothing
  // is selected — the timeline's "current row at the current cell" rule,
  // applied to whichever rail asked.

  /// Whether a shove aims at the CUT axis: the selection is on a cut row,
  /// or — with nothing selected — the asking rail is.
  bool _shiftAimsAtCuts(TimelineRowAddress? currentRow) {
    final trackSelection = _selection.trackFrameRangeSelection.value;
    if (trackSelection != null) {
      return trackSelection.spanRows.whereType<TrackRowAddress>().isNotEmpty;
    }
    if (_selection.frameRangeSelection.value != null) {
      return false;
    }
    return currentRow is TrackRowAddress;
  }

  bool canPushBlocks({TimelineRowAddress? currentRow}) =>
      _shiftAimsAtCuts(currentRow)
      ? _cutShift.canPushCuts
      : canPushFrames(currentRow: currentRow);

  int blockPullSlack({TimelineRowAddress? currentRow}) =>
      _shiftAimsAtCuts(currentRow)
      ? _cutShift.cutPullSlack
      : framePullSlack(currentRow: currentRow);

  bool canPullBlocks({TimelineRowAddress? currentRow}) =>
      blockPullSlack(currentRow: currentRow) > 0;

  void pushBlocks(int count, {TimelineRowAddress? currentRow}) =>
      _shiftAimsAtCuts(currentRow)
      ? _cutShift.pushCuts(count)
      : pushFrames(count, currentRow: currentRow);

  void pullBlocks(int count, {TimelineRowAddress? currentRow}) =>
      _shiftAimsAtCuts(currentRow)
      ? _cutShift.pullCuts(count)
      : pullFrames(count, currentRow: currentRow);
}
