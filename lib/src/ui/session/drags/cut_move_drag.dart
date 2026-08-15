import 'package:flutter/foundation.dart';

import '../../../models/cut_id.dart';
import '../../../models/cut_move_plan.dart';
import '../../../models/track.dart';
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
/// ⚠️The shared rule now also re-times a run AFTER it has reordered (UI
/// 08-14 #5), but THIS axis cannot show it: [planCutMove] answers a reorder
/// with the sequence alone and this drag commits that sequence, so a swapped
/// cut still seats itself. Carrying it here means giving
/// `CutMovePlan.reorder` its gaps and re-keying them by the cut that ends up
/// in each position — a separate change, not done.
class CutMoveDrag implements EditorDragSession {
  CutMoveDrag._({
    required TrackId trackId,
    required List<CutMoveSlot> slots,
    required int runStart,
    required int? runEnd,
    required ValueNotifier<TimelineDragPreview?> preview,
    required void Function({required TrackId trackId, required List<CutId> order})
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
       _preview = preview,
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
    required void Function({required TrackId trackId, required List<CutId> order})
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
      return CutMoveDrag._(
        trackId: track.id,
        slots: [
          for (final cut in track.cuts)
            (
              id: cut.id,
              leadingGapFrames: cut.leadingGapFrames,
              duration: cut.duration,
            ),
        ],
        runStart: runStart,
        runEnd: runEnd,
        preview: preview,
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

  /// The plan the last update arrived at, or null while it shows "no
  /// change". The commit reads THIS, never [_preview].
  CutMovePlan? _after;

  final ValueNotifier<TimelineDragPreview?> _preview;

  /// The session's two committers, each one undo step with the refresh
  /// epilogue behind it: the track's new sequence, or the re-time's gaps.
  final void Function({required TrackId trackId, required List<CutId> order})
  _commitOrder;
  final void Function({
    required Map<CutId, int> beforeGaps,
    required Map<CutId, int> afterGaps,
  })
  _commitGaps;

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
    if (plan.isReorder) {
      _after = plan;
      _preview.value = CutTrimDragPreview(
        previewDurations: const {},
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
  /// a re-time lands as gaps, a reorder as the track's new sequence.
  /// Durations are untouched either way, so no fade re-anchor is needed.
  @override
  void commit() {
    final plan = _after;
    _preview.value = null;
    if (plan == null) {
      return;
    }
    if (plan.isReorder) {
      _commitOrder(trackId: _trackId, order: plan.order!);
      return;
    }
    final beforeGaps = {
      for (final slot in _slots) slot.id: slot.leadingGapFrames,
    };
    final afterGaps = {
      for (final id in beforeGaps.keys) id: plan.gaps[id] ?? beforeGaps[id]!,
    };
    final changed = afterGaps.entries.any(
      (entry) => beforeGaps[entry.key] != entry.value,
    );
    if (!changed) {
      return;
    }
    _commitGaps(beforeGaps: beforeGaps, afterGaps: afterGaps);
  }

  /// Drops an in-flight move preview without touching history.
  @override
  void cancel() {
    _preview.value = null;
  }
}
