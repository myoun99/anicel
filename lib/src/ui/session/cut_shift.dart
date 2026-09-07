import 'dart:math' as math;

import '../../models/row_block_shift.dart';
import '../../models/storyboard_timeline_layout.dart';
import '../../models/track_id.dart';
import 'session_roles.dart';
import 'storyboard_rows.dart';

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
    required ChangeSink changes,
    required StoryboardRows storyboardRows,
  }) : _project = project,
       _changes = changes,
       _storyboardRows = storyboardRows;

  final ProjectAccess _project;
  final ChangeSink _changes;
  final StoryboardRows _storyboardRows;

  /// The cut-axis scope: which track, and the ordinal the shove starts at.
  ({TrackId trackId, int anchorCutIndex})? _cutShiftScope() {
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
        return (trackId: track.id, anchorCutIndex: indexes.first);
      }
      final activeIndex = track.cuts.indexWhere(
        (c) => c.id == _project.activeCutId,
      );
      if (activeIndex >= 0) {
        return (trackId: track.id, anchorCutIndex: activeIndex);
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
    _changes.refreshAfterCutCommand();
    _changes.notifyChanged();
  }
}
