import 'dart:math' as math;

import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/row_block_shift.dart';
import '../../models/timeline_row_address.dart';
import 'active_cut_controllers.dart';
import 'cut_shift.dart';
import 'session_roles.dart';

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
    required SessionInternals internals,
    required ActiveCutControllers controllers,
    required CutShift cutShift,
  }) : _project = project,
       _selection = selection,
       _changes = changes,
       _internals = internals,
       _controllers = controllers,
       _cutShift = cutShift;

  final ProjectAccess _project;
  final SelectionAccess _selection;
  final ChangeSink _changes;
  final SessionInternals _internals;
  final ActiveCutControllers _controllers;
  final CutShift _cutShift;

  /// The frame-axis scope: which layer rows shift, from where, and which
  /// AXIS that anchor is stated in.
  ///
  /// A track-axis selection (the storyboard's S rows) arrives already in
  /// commit keys; a cut-local one has to be translated for those same rows.
  /// Carrying the axis is what keeps the shove from translating twice.
  ({List<LayerId> layerIds, int anchorIndex, bool anchorIsGlobal})?
  frameShiftScope({TimelineRowAddress? currentRow}) {
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
        );
      }
    }
    final selection = _selection.frameRangeSelection.value;
    if (selection != null) {
      // Rows whose timing is not their own stand down —
      // [ChangeSink.standsDownFromRetime].
      final rows = [
        for (final id in selection.spanLayerIds)
          if (!_changes.standsDownFromRetime(id) &&
              _project.rangeLayerById(id) != null)
            id,
      ];
      return rows.isEmpty
          ? null
          : (
              layerIds: rows,
              anchorIndex: selection.startIndex,
              anchorIsGlobal: false,
            );
    }
    // NO selection: the current row at the current cell — the timeline's
    // rule, applied to whichever rail asked. The storyboard's current row
    // is an S row on the global axis, so its anchor is the global playhead.
    if (currentRow is LayerRowAddress &&
        _project.trackSeGlobalLayerById(currentRow.layerId) != null) {
      return (
        layerIds: [currentRow.layerId],
        anchorIndex: _selection.editingGlobalFrame,
        anchorIsGlobal: true,
      );
    }
    final layerId = _selection.activeLayerId;
    final index = _controllers.timelineController.currentFrameIndex;
    if (layerId == null ||
        index < 0 ||
        _changes.standsDownFromRetime(layerId) ||
        _project.rangeLayerById(layerId) == null) {
      return null;
    }
    return (layerIds: [layerId], anchorIndex: index, anchorIsGlobal: false);
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
      ? _internals.commitBlockStart(layerId, anchorIndex)
      : anchorIndex;

  bool canPushFrames({TimelineRowAddress? currentRow}) =>
      frameShiftScope(currentRow: currentRow) != null;

  /// How far a frame PULL can travel: the LEAST slack across the scope's
  /// rows, so the whole scope stops where the first one touches.
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
          blocks: timelineShiftableBlocks(layer.timeline),
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
          before.timeline,
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
    _changes.refreshAfterCutCommand();
    _changes.notifyChanged();
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
