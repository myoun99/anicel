import 'dart:math' as math;

import '../../models/cut.dart';
import '../../models/row_block_shift.dart';
import '../../models/storyboard_timeline_layout.dart';
import '../../models/track_id.dart';
import 'range_selections.dart';
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
    required SelectionAccess selection,
    required TimelineAccess timeline,
    required ChangeSink changes,
    required StoryboardRows storyboardRows,
    required RangeSelections rangeSelections,
  }) : _project = project,
       _selection = selection,
       _timeline = timeline,
       _changes = changes,
       _storyboardRows = storyboardRows,
       _rangeSelections = rangeSelections;

  final ProjectAccess _project;
  final SelectionAccess _selection;
  final TimelineAccess _timeline;
  final ChangeSink _changes;
  final StoryboardRows _storyboardRows;
  final RangeSelections _rangeSelections;

  /// The cut-axis scope: which track's cut row, and the FRAME the shove
  /// starts at — the selection's start where it is swept over that row,
  /// else the frame the playhead stands on, on the track stood on.
  ///
  /// 🗣️F-626 (유저 2026-11-21): 「콘티패널 컷 빈 공간에서도 밀기/당기기
  /// 사용가능하게. 빈공간이든 뭐든 묻지말고 법 통일.」 — the frame axis' scope
  /// (`BlockShift.frameShiftScope`) asked of the cut row: the cuts that
  /// start at or after the frame travel ([shoveCarries]), whatever lies
  /// under it. ↩️The anchor was a CUT — the first one the selection held,
  /// else the one stood in — and empty space has neither: standing there
  /// both verbs were dead, and a selection over it aimed the cut stood in.
  ///
  /// ⚠️What that changes where a cut IS under the frame: standing INSIDE a
  /// cut, that cut stays and the ones after it travel — the anchor is a
  /// boundary, as it is inside a block on a layer row — where the cut stood
  /// in used to travel. At its first frame, or selected, it travels as
  /// before. Decided by the 타임라인/콘티 session (11-22) on the user's
  /// 「법 통일」, written on card F-626 for the user to overturn. ⛔Not
  /// taken: 「the start of the cut under the frame, else the frame」 — it
  /// asks whether the frame is in empty space, the question the user said
  /// not to ask, and leaves the two axes with two laws inside a block.
  ({TrackId trackId, int anchorFrame}) _scope() {
    final selection = _storyboardRows.cutRowSelection;
    return selection != null
        ? (trackId: selection.trackId, anchorFrame: selection.startFrame)
        : (
            trackId: _selection.selectedTrackId,
            anchorFrame: _selection.editingGlobalFrame,
          );
  }

  /// [trackId]'s cuts as they lie on its axis, in order.
  List<StoryboardTimelineLayoutEntry> _cutsOn(TrackId trackId) => [
    for (final entry in buildStoryboardTimelineLayout(
      _project.repository.requireProject(),
    ))
      if (entry.trackId == trackId) entry,
  ];

  /// The cut whose leading gap carries the shove: the first one the scope's
  /// frame carries — null where no cut starts at or after it.
  Cut? _firstCarried() {
    final scope = _scope();
    for (final entry in _cutsOn(scope.trackId)) {
      if (shoveCarries(entry.startFrame, anchorIndex: scope.anchorFrame)) {
        return entry.cut;
      }
    }
    return null;
  }

  /// How far a cut PULL can travel — the same slack rule, read off the
  /// track's cuts instead of a layer's exposures.
  int get cutPullSlack {
    final scope = _scope();
    final slack = rowPullSlack(
      blocks: [
        for (final entry in _cutsOn(scope.trackId))
          (startIndex: entry.startFrame, endIndexExclusive: entry.endFrame),
      ],
      anchorIndex: scope.anchorFrame,
    );
    // No cut starts at or after the frame — it stands past the last one —
    // so there is nothing to close: the shared arithmetic's 「no limit of
    // its own」 is no pull at all here. ↩️The anchor was read OUT of the
    // blocks, so that answer never came and a mutant on this line survived
    // (2026-09-07); a frame past the last cut brings it (F-626), and
    // `push_pull_test` asks there.
    return slack == 0x7fffffff ? 0 : slack;
  }

  bool get canPullCuts => cutPullSlack > 0;

  /// Slides the first cut at or after the scope's frame, and everything
  /// after it, [count] frames later. Cut LENGTHS never change (design D) —
  /// only where the run starts.
  void pushCuts(int count) => _shiftCuts(count);

  void pullCuts(int count) => _shiftCuts(-math.min(count, cutPullSlack));

  void _shiftCuts(int delta) {
    // Positions are cumulative, so the first carried cut's own leading gap
    // carries the whole run: every cut after it follows for free with its
    // spacing intact, which is exactly what "rigid" means here.
    final carrier = delta == 0 ? null : _firstCarried();
    if (carrier == null) {
      return;
    }
    final after = carrier.leadingGapFrames + delta;
    if (after < 0) {
      return;
    }
    final parked = _timeline.editingSession.gapGlobalFrame;
    _project.cutCommandCoordinator.commitCutDurationDrag(
      beforeDurations: const {},
      afterDurations: const {},
      beforeGaps: {carrier.id: carrier.leadingGapFrames},
      afterGaps: {carrier.id: after},
    );
    // The selection that aimed it stays where it is, and the cuts under it
    // now are the ones it selects — the frame shove's law (F-264,
    // `BlockShift`). The tidy-up is a cut command's and leaves a track
    // selection be.
    _changes.refreshAfterCutCommand();
    _rangeSelections.growOverTheBlocksItHolds();
    // So does a frame stood on in empty space, and the cut a pull brought
    // under it is the cut stood in (F-264's 「자기 위치에 갱신」, for the
    // playhead): left parked over a frame a cut covers, the session says
    // that cut's picture is hidden (`parkGlobalFrame`) and the next pull
    // finds the cut straddling its anchor. A playhead that stands IN a cut
    // is that cut's and goes where it goes, as with every cut command.
    if (parked != null && !_timeline.trackFrameAxis().isGap(parked)) {
      _selection.selectGlobalFrame(parked);
    }
    _changes.notifyChanged();
  }
}
