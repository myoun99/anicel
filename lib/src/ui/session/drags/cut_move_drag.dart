import 'package:flutter/foundation.dart';

import '../../../models/cut_id.dart';
import '../../../models/cut_move_plan.dart';
import '../../../models/timeline_row_address.dart';
import '../../../models/track.dart';
import '../../../models/track_frame_range.dart';
import '../../../models/track_id.dart';
import '../../timeline/timeline_drag_preview.dart';
import 'editor_drag_session.dart';

/// The storyboard cut-block MOVE drag (R10-④).
///
/// Where the block ends up is [planCutMove]'s answer: a drag that stays in
/// its own free space re-times (its leading gap grows or shrinks, the
/// neighbours hold still), and a drag that reaches the seat BEYOND a
/// neighbour REORDERS the track instead. Sliding used to shove the followers
/// along on contact; that whole-track shove is what the push/pull buttons
/// are for, and a drag that could only shove could never say "put this cut
/// after that one".
///
/// A reorder carries the shared rule's SECOND answer too: the gaps stay
/// with their positions (R5 #13) and the run keeps re-timing in its new
/// rank (UI 08-14 #5). [planCutMove] re-keys the position gaps by the cut
/// that lands in each position, this drag previews and commits them with
/// the sequence, and the commit stays one undo step.
class CutMoveDrag implements EditorDragSession {
  CutMoveDrag._({
    required TrackId trackId,
    required List<CutMoveSlot> slots,
    required int runStart,
    required int? runEnd,
    required int runFromFrame,
    required int runToFrame,
    required ValueNotifier<TimelineDragPreview?> preview,
    required TrackFrameRangeSelection? selectionBefore,
    required void Function(TrackFrameRangeSelection?) publishSelection,
    required void Function({
      required TrackId trackId,
      required List<CutId> order,
      required Map<CutId, int> beforeGaps,
      required Map<CutId, int> afterGaps,
    })
    commitOrder,
    required void Function({
      required Map<CutId, int> beforeGaps,
      required Map<CutId, int> afterGaps,
    })
    commitGaps,
  }) : _trackId = trackId,
       _slots = slots,
       _runStart = runStart,
       _runEnd = runEnd,
       _runFromFrame = runFromFrame,
       _runToFrame = runToFrame,
       _preview = preview,
       _selectionBefore = selectionBefore,
       _publishSelection = publishSelection,
       _commitOrder = commitOrder,
       _commitGaps = commitGaps;

  /// Starts a whole-block move drag on [cutId]; null when no track carries
  /// it — no object, no drag.
  ///
  /// Dragging inside the cut SELECTION slides the whole run (UI-R18 #1):
  /// anchor at the run's first cut, compensate past its last. Only a
  /// CONTIGUOUS run travels as one — a selection with a hole in it has no
  /// single length to carry.
  static CutMoveDrag? begin({
    required CutId cutId,
    required List<Track> tracks,
    required List<CutId> selectedCutIds,
    required ValueNotifier<TimelineDragPreview?> preview,
    required TrackFrameRangeSelection? selection,
    required void Function(TrackFrameRangeSelection?) publishSelection,
    required void Function({
      required TrackId trackId,
      required List<CutId> order,
      required Map<CutId, int> beforeGaps,
      required Map<CutId, int> afterGaps,
    })
    commitOrder,
    required void Function({
      required Map<CutId, int> beforeGaps,
      required Map<CutId, int> afterGaps,
    })
    commitGaps,
  }) {
    for (final track in tracks) {
      final index = track.cuts.indexWhere((cut) => cut.id == cutId);
      if (index < 0) {
        continue;
      }
      var runStart = index;
      int? runEnd;
      if (selectedCutIds.contains(cutId)) {
        final order = [for (final cut in track.cuts) cut.id];
        final indexes = [for (final id in selectedCutIds) order.indexOf(id)]
          ..removeWhere((value) => value < 0);
        if (indexes.length > 1) {
          indexes.sort();
          if (indexes.last - indexes.first == indexes.length - 1) {
            runStart = indexes.first;
            runEnd = indexes.last;
          }
        }
      }
      final slots = <CutMoveSlot>[
        for (final cut in track.cuts)
          (
            id: cut.id,
            leadingGapFrames: cut.leadingGapFrames,
            duration: cut.duration,
          ),
      ];
      // The selection rides the run when it is the CUT ROW's selection on
      // this track and touches the run (the drag machine's law: every step
      // writes the previewed span through the selection notifier; the band
      // just listens). An SE/transition-row selection merely overlapping
      // the frames stays put — a cut move does not move that content.
      var runFrom = 0;
      for (var position = 0; position <= runStart; position += 1) {
        runFrom += slots[position].leadingGapFrames;
        if (position < runStart) {
          runFrom += slots[position].duration;
        }
      }
      var runTo = runFrom;
      for (var position = runStart; position <= (runEnd ?? runStart);
          position += 1) {
        runTo += slots[position].duration +
            (position > runStart ? slots[position].leadingGapFrames : 0);
      }
      final rides = selection != null &&
          selection.trackId == track.id &&
          selection.coversRow(TrackRowAddress(track.id)) &&
          selection.overlaps(runFrom, runTo);
      return CutMoveDrag._(
        trackId: track.id,
        slots: slots,
        runStart: runStart,
        runEnd: runEnd,
        runFromFrame: runFrom,
        runToFrame: runTo,
        preview: preview,
        selectionBefore: rides ? selection : null,
        publishSelection: publishSelection,
        commitOrder: commitOrder,
        commitGaps: commitGaps,
      );
    }
    return null;
  }

  final TrackId _trackId;
  final List<CutMoveSlot> _slots;
  final int _runStart;
  final int? _runEnd;

  /// The run's original global span — the reference every step's shift is
  /// measured from.
  final int _runFromFrame;
  final int _runToFrame;

  /// The selection riding the run (captured at begin, already claimed by
  /// the select path), or null when the drag grabbed an unselected cut.
  /// The drag machine's law: every step writes the previewed span through
  /// the selection notifier, and the band painters just listen.
  final TrackFrameRangeSelection? _selectionBefore;
  final void Function(TrackFrameRangeSelection?) _publishSelection;

  /// The plan the last update arrived at, or null while it shows "no
  /// change". The commit reads THIS, never [_preview].
  CutMovePlan? _after;

  final ValueNotifier<TimelineDragPreview?> _preview;

  /// The session's two committers, each one undo step with the refresh
  /// epilogue behind it: the track's new sequence WITH the position gaps
  /// its cuts took over, or the re-time's gaps alone.
  final void Function({
    required TrackId trackId,
    required List<CutId> order,
    required Map<CutId, int> beforeGaps,
    required Map<CutId, int> afterGaps,
  })
  _commitOrder;
  final void Function({
    required Map<CutId, int> beforeGaps,
    required Map<CutId, int> afterGaps,
  })
  _commitGaps;

  /// The run's span length after [plan] lands: durations plus the landed
  /// INTERIOR gaps. A reorder may re-key an interior position's gap (the
  /// gaps stay with positions), so the run's extent is not fixed — the
  /// band must follow the landed extent, or a shrunken run leaves the band
  /// overlapping a neighbour the user never selected (and the delete verbs
  /// then act on the wrong set).
  int _landedRunLengthFor(CutMovePlan plan) {
    var length = 0;
    for (var index = _runStart; index <= (_runEnd ?? _runStart); index += 1) {
      final slot = _slots[index];
      if (index > _runStart) {
        length += plan.gaps[slot.id] ?? slot.leadingGapFrames;
      }
      length += slot.duration;
    }
    return length;
  }

  /// Publishes the riding selection at the run's PREVIEWED landing: the
  /// start rides [CutMovePlan.runStartFrame] and the end rides the landed
  /// extent (no-op when no selection rides the run). Passing null restores
  /// the drag-start selection (cancel).
  void _publishLanded(CutMovePlan? plan) {
    final before = _selectionBefore;
    if (before == null) {
      return;
    }
    if (plan == null) {
      _publishSelection(before);
      return;
    }
    // Only a selection that IS the run (the snap makes them equal when the
    // grabbed cut is selected) reshapes to the landed extent; a wider or
    // offset overlap keeps the plain shift, which is all it can honestly
    // claim to know.
    final exact =
        before.startFrame == _runFromFrame &&
        before.endFrameExclusive == _runToFrame;
    final delta = plan.runStartFrame - _runFromFrame;
    final start = before.startFrame + delta;
    final end = exact
        ? start + _landedRunLengthFor(plan)
        : before.endFrameExclusive + delta;
    if (start == before.startFrame && end == before.endFrameExclusive) {
      _publishSelection(before);
      return;
    }
    _publishSelection(
      TrackFrameRangeSelection(
        trackId: before.trackId,
        anchorRow: before.anchorRow,
        rows: before.rows,
        startFrame: start,
        endFrameExclusive: end,
      ),
    );
  }

  /// Applies the move's cumulative frame delta as a live preview (the
  /// repository is NOT touched).
  @override
  void update(int cumulativeDelta) {
    final plan = planCutMove(
      slots: _slots,
      runStart: _runStart,
      runEnd: _runEnd ?? _runStart,
      frameDelta: cumulativeDelta,
    );
    // The band follows the run's previewed landing in the SAME step as the
    // blocks — the notifier-per-step law the frame axis already lives by.
    _publishLanded(plan);
    if (plan.isReorder) {
      _after = plan;
      _preview.value = CutTrimDragPreview(
        previewDurations: const {},
        previewGaps: plan.gaps,
        previewOrder: {_trackId: plan.order!},
      );
      return;
    }
    _after = plan.gaps.isEmpty ? null : plan;
    _preview.value = plan.gaps.isEmpty
        ? null
        : CutTrimDragPreview(
            previewDurations: const {},
            previewGaps: plan.gaps,
          );
  }

  /// Commits the move as a single undo step (no-op when nothing changed):
  /// a re-time lands as gaps, a reorder as the track's new sequence WITH
  /// the position gaps its cuts took over (which may be none, when the
  /// track is packed). Durations are untouched either way, so no fade
  /// re-anchor is needed.
  @override
  void commit() {
    final plan = _after;
    _preview.value = null;
    if (plan == null) {
      return;
    }
    // The sparse before/after of the gaps the plan changed — [plan.gaps]
    // only carries cuts whose gap differs from their current one, so this
    // is the changed set on both shapes.
    final beforeGaps = <CutId, int>{
      for (final slot in _slots)
        if (plan.gaps.containsKey(slot.id)) slot.id: slot.leadingGapFrames,
    };
    if (plan.isReorder) {
      _commitOrder(
        trackId: _trackId,
        order: plan.order!,
        beforeGaps: beforeGaps,
        afterGaps: plan.gaps,
      );
    } else if (plan.gaps.isNotEmpty) {
      _commitGaps(beforeGaps: beforeGaps, afterGaps: plan.gaps);
    }
    // The landed span goes out AFTER the repository commit, so a reader
    // that resolves cuts from the selection's frames against the CURRENT
    // layout ([storyboardSelectedCutIds]) sees the moved cuts, not their
    // old seats.
    _publishLanded(plan);
  }

  /// Drops an in-flight move preview without touching history, and puts
  /// the riding selection back where the drag found it.
  @override
  void cancel() {
    _preview.value = null;
    _publishLanded(null);
  }
}
