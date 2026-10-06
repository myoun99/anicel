import 'dart:math' as math;

import '../../models/row_block_shift.dart';
import '../../models/storyboard_timeline_layout.dart';
import '../../models/track_id.dart';
import 'session_roles.dart';
import 'storyboard_rows.dart';

/// The TRACK-axis selection a shove was aimed by — an S row's sounds or the
/// cut row's cuts — carried the way its blocks went, [delta] frames.
///
/// 🚨F-264 (유저 2026-10-02): 「타임라인 버튼 밀기/당기기 작동시 선택범위로
/// 여러행선택한거라던가 블록 선택범위 풀리는데 안풀리도록」. A shove's scope
/// is 「the selection's rows, anchored at its start」, so the selection is
/// what the NEXT press is aimed by. Dropped — as the timeline's was, by a
/// tidy-up the shove did not owe (`BlockShift`) — that press shoved from the
/// playhead instead. Left on the frames it covered — as the storyboard's
/// two were — a second pull found the blocks it had just moved standing
/// BEFORE its anchor and passed them by, and a cut pushed out from under
/// its band was no longer the cut selected. Carried, it names the same
/// blocks for as many presses as it takes.
///
/// The cut's own selection is carried by the frame shove, beside its scope.
void carryTrackSelectionWithTheShove(SelectionAccess selection, int delta) {
  if (selection.trackFrameRangeSelection.value case final onTrack?) {
    selection.trackFrameRangeSelection.value = onTrack.shiftedBy(delta);
  }
}

/// THE CUT-AXIS SHOVE: push and pull on the storyboard's cut row.
///
/// Design D — a cut is a block on the cut row exactly as an exposure is a
/// block on a layer row, so "shove from here" means the same thing on
/// both and only the COMMIT differs. That is why the slack arithmetic is
/// `rowPullSlack`, shared with the frame axis, and only [_shiftCuts]
/// speaks to the cut command coordinator.
///
/// 🚨A collaborator carved out of `EditorSessionManager` (G3 of the
/// god-object decomposition, round 8). The session keeps the ONE
/// push/pull verb that aims at either axis; this object answers for the
/// cut half of it.
class CutShift {
  CutShift({
    required ProjectAccess project,
    required SelectionAccess selection,
    required ChangeSink changes,
    required StoryboardRows storyboardRows,
  }) : _project = project,
       _selection = selection,
       _changes = changes,
       _storyboardRows = storyboardRows;

  final ProjectAccess _project;
  final SelectionAccess _selection;
  final ChangeSink _changes;
  final StoryboardRows _storyboardRows;

  /// The cut-axis scope: which track, the ordinal the shove starts at, and
  /// whether a SELECTION aimed it there — the cuts it covers — rather than
  /// the cut stood on.
  ({TrackId trackId, int anchorCutIndex, bool aimedBySelection})?
  _cutShiftScope() {
    final project = _project.repository.requireProject();
    final selection = _storyboardRows.storyboardSelectedCutIds;
    for (final track in project.tracks) {
      if (selection.isNotEmpty) {
        final indexes = [
          for (final id in selection) track.cuts.indexWhere((c) => c.id == id),
        ]..removeWhere((value) => value < 0);
        if (indexes.isEmpty) {
          continue;
        }
        indexes.sort();
        return (
          trackId: track.id,
          anchorCutIndex: indexes.first,
          aimedBySelection: true,
        );
      }
      final activeIndex = track.cuts.indexWhere(
        (c) => c.id == _project.activeCutId,
      );
      if (activeIndex >= 0) {
        return (
          trackId: track.id,
          anchorCutIndex: activeIndex,
          aimedBySelection: false,
        );
      }
    }
    return null;
  }

  List<ShiftableBlock> _cutShiftBlocks(TrackId trackId) => [
    for (final entry in buildStoryboardTimelineLayout(
      _project.repository.requireProject(),
    ))
      if (entry.trackId == trackId)
        (startIndex: entry.startFrame, endIndexExclusive: entry.endFrame),
  ];

  bool get canPushCuts => _cutShiftScope() != null;

  /// How far a cut PULL can travel — the same slack rule, read off the
  /// track's cuts instead of a layer's exposures.
  int get cutPullSlack {
    final scope = _cutShiftScope();
    if (scope == null) {
      return 0;
    }
    final blocks = _cutShiftBlocks(scope.trackId);
    if (scope.anchorCutIndex >= blocks.length) {
      return 0;
    }
    final slack = rowPullSlack(
      blocks: blocks,
      anchorIndex: blocks[scope.anchorCutIndex].startIndex,
    );
    // ⛔MUTANT SURVIVES HERE, and the classification is NEVER APPLIED
    // (2026-09-07): the anchor is read OUT of `blocks`, so `rowPullSlack`
    // always finds a moved block and never returns its unbounded
    // sentinel. Kept as the clamp on that shared arithmetic's contract —
    // a caller that anchors off-list would otherwise pull 2^31 frames.
    return slack == 0x7fffffff ? 0 : slack;
  }

  bool get canPullCuts => cutPullSlack > 0;

  /// Slides the anchor cut and everything after it [count] frames later.
  /// Cut LENGTHS never change (design D) — only where the run starts.
  void pushCuts(int count) => _shiftCuts(count);

  void pullCuts(int count) => _shiftCuts(-math.min(count, cutPullSlack));

  void _shiftCuts(int delta) {
    final scope = _cutShiftScope();
    if (scope == null || delta == 0) {
      return;
    }
    final track = _project.repository.requireProject().tracks.firstWhere(
      (track) => track.id == scope.trackId,
    );
    if (scope.anchorCutIndex >= track.cuts.length) {
      return;
    }
    // Positions are cumulative, so the anchor's own leading gap carries the
    // whole run: every cut after it follows for free with its spacing
    // intact, which is exactly what "rigid" means here.
    final anchor = track.cuts[scope.anchorCutIndex];
    final after = anchor.leadingGapFrames + delta;
    if (after < 0) {
      return;
    }
    _project.cutCommandCoordinator.commitCutDurationDrag(
      beforeDurations: const {},
      afterDurations: const {},
      beforeGaps: {anchor.id: anchor.leadingGapFrames},
      afterGaps: {anchor.id: after},
    );
    // The cuts ARE this selection's blocks, and it goes where they went
    // (F-264) — before the tidy-up, which is a cut command's and leaves a
    // track selection be.
    if (scope.aimedBySelection) {
      carryTrackSelectionWithTheShove(_selection, delta);
    }
    _changes.refreshAfterCutCommand();
    _changes.notifyChanged();
  }
}
