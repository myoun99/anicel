import 'dart:math' as math;

import 'package:flutter/foundation.dart' show mapEquals;

import '../../../models/cut.dart';
import '../../../models/cut_end_gap.dart';
import '../../../models/cut_id.dart';
import '../../../models/cut_lead_edge_plan.dart';
import '../../../models/layer.dart';
import '../../../models/storyboard_coverage.dart';
import '../../../models/storyboard_timeline_layout.dart';
import '../../../models/timeline_coverage.dart' show TimelineBlockEdge;
import '../../storyboard_layer_policy.dart';
import '../../timeline/timeline_drag_preview.dart';
import 'edge_drag_roles.dart';
import 'editor_drag_session.dart';

/// A cut TRIM's previewed answer: the durations, the gaps, and the conte-row
/// rewrite that rides them.
typedef CutTrimResult = ({
  Map<CutId, int> durations,
  Map<CutId, int> gaps,
  List<({Layer before, Layer after})> rowEdits,
});

/// The plain duration/gap drag on a cut's edge, as its own object.
///
/// 🚨Sealed over the two EDGES, because the edge is not a property of a
/// trim — it decides what the drag even is, and the two arms share no
/// mid-drag state (R10 R4). It used to be a `TimelineBlockEdge?` field
/// beside eleven others on the session, of which four belonged to the lead
/// arm and one to the trailing arm: the update read the lead's order and
/// index through `!` and its panel through `?? 0`, because nothing but the
/// shape of the code said they were set together. The edge is now the
/// runtime type, and each arm carries exactly its own capture.
sealed class CutTrimDrag implements EditorDragSession {
  CutTrimDrag._({
    required EdgeDragRoles roles,
    required CutId cutId,
    required Map<CutId, int> beforeDurations,
    required Map<CutId, int> beforeGaps,
  }) : _roles = roles,
       _cutId = cutId,
       _beforeDurations = beforeDurations,
       _beforeGaps = beforeGaps;

  /// Starts a duration/gap drag on [cutId]'s [edge]; null when the cut is
  /// not on any track's layout — no object, no drag.
  ///
  /// - the LEAD edge is one verb for every cut (R10 R4): the cut loses
  ///   frames off its front, its END holds so the cuts behind never move,
  ///   the cut GLUED in front translates wholesale, and the difference comes
  ///   to rest at the head of the film ([planCutLeadEdge]). On a cut WITH a
  ///   conte row the frames come off [panelIndex] — the panel the grip
  ///   belongs to — and every other panel keeps its commas
  ///   ([storyboardTimelineWithPanelLeadRetimed], user's rule 2026-08-02).
  ///   The row is what floors the drag, and it floors the GRABBED panel, not
  ///   the last one;
  /// - the TRAILING edge trims the duration, growth eating the following
  ///   gap first. (A cut WITH a storyboard row never reaches this arm on
  ///   that edge — feedback #9 sends it to the row's last comma instead.)
  static CutTrimDrag? begin({
    required EdgeDragRoles roles,
    required CutId cutId,
    required TimelineBlockEdge edge,
    int panelIndex = 0,
  }) {
    final layout = buildStoryboardTimelineLayout(
      roles.project.repository.requireProject(),
    );
    StoryboardTimelineLayoutEntry? entry;
    for (final candidate in layout) {
      if (candidate.cutId == cutId) {
        entry = candidate;
        break;
      }
    }
    if (entry == null) {
      return null;
    }
    return switch (edge) {
      TimelineBlockEdge.start => _beginLead(
        roles: roles,
        layout: layout,
        entry: entry,
        panelIndex: panelIndex,
      ),
      TimelineBlockEdge.end => _beginTrail(
        roles: roles,
        layout: layout,
        entry: entry,
      ),
    };
  }

  /// The start TRIM's leftward growth cascades through the PREDECESSORS'
  /// gaps, so the whole track's order and gaps join the drag snapshot.
  static CutLeadTrimDrag _beginLead({
    required EdgeDragRoles roles,
    required List<StoryboardTimelineLayoutEntry> layout,
    required StoryboardTimelineLayoutEntry entry,
    required int panelIndex,
  }) {
    final trackEntries = [
      for (final candidate in layout)
        if (candidate.trackId == entry.trackId) candidate,
    ];
    return CutLeadTrimDrag._(
      roles: roles,
      cutId: entry.cutId,
      beforeDurations: {entry.cutId: entry.cut.duration},
      beforeGaps: {
        for (final candidate in trackEntries)
          candidate.cutId: candidate.cut.leadingGapFrames,
      },
      order: [for (final candidate in trackEntries) candidate.cutId],
      index: entry.cutIndex,
      panelIndex: panelIndex,
    );
  }

  static CutTrailTrimDrag _beginTrail({
    required EdgeDragRoles roles,
    required List<StoryboardTimelineLayoutEntry> layout,
    required StoryboardTimelineLayoutEntry entry,
  }) {
    StoryboardTimelineLayoutEntry? next;
    for (final candidate in layout) {
      if (candidate.trackId == entry.trackId &&
          candidate.cutIndex == entry.cutIndex + 1) {
        next = candidate;
        break;
      }
    }
    return CutTrailTrimDrag._(
      roles: roles,
      cutId: entry.cutId,
      beforeDurations: {entry.cutId: entry.cut.duration},
      beforeGaps: {
        entry.cutId: entry.cut.leadingGapFrames,
        if (next != null) next.cutId: next.cut.leadingGapFrames,
      },
      nextCutId: next?.cutId,
    );
  }

  final EdgeDragRoles _roles;
  final CutId _cutId;
  final Map<CutId, int> _beforeDurations;
  final Map<CutId, int> _beforeGaps;

  /// What the release would commit; null while the drag has not left its
  /// frame. Fields, never the preview channel: a consumer clearing
  /// [SessionInternals.dragPreview] mid-drag must not void the commit.
  CutTrimResult? _after;

  /// The durations and gaps this edge resolves [cumulativeDelta] to. The
  /// whole difference between the two arms — see each override.
  ({Map<CutId, int> durations, Map<CutId, int> gaps}) _plan(
    int cumulativeDelta,
  );

  /// The conte-row rewrite this edge owes for [planned], mid-drag. Empty on
  /// the trailing edge: nothing on the row moves until the release, which
  /// re-tiles it to the cut's new length.
  List<({Layer before, Layer after})> _rowEditsForPlan(
    ({Map<CutId, int> durations, Map<CutId, int> gaps}) planned,
  ) => const [];

  /// Applies the drag's cumulative frame delta as a live preview on
  /// [SessionInternals.dragPreview] (the repository is NOT touched).
  @override
  void update(int cumulativeDelta) {
    final planned = _plan(cumulativeDelta);
    // The conte row is re-keyed by the SAME drag, and it is re-keyed HERE
    // rather than at the release: the strip and the timeline both re-derive
    // panels from (row, duration), so a preview that moved only the duration
    // showed the LAST panel shrinking for the whole gesture and then jumped
    // to the real answer on pointer-up.
    final rowEdits = _rowEditsForPlan(planned);
    final changed =
        planned.durations[_cutId] != _beforeDurations[_cutId] ||
        planned.gaps.entries.any(
          (entry) => _beforeGaps[entry.key] != entry.value,
        );
    final after = changed
        ? (
            durations: planned.durations,
            gaps: planned.gaps,
            rowEdits: rowEdits,
          )
        : null;
    _after = after;
    _roles.internals.dragPreview.value = after == null
        ? null
        : CutTrimDragPreview(
            previewDurations: after.durations,
            previewGaps: after.gaps,
            previewLayers: {
              for (final edit in after.rowEdits) edit.after.id: edit.after,
            },
          );
  }

  /// Commits the drag as a single undo step (no-op when nothing changed):
  /// the command's execute applies the final durations AND gaps.
  @override
  void commit() {
    final after = _after;
    _roles.internals.dragPreview.value = null;
    if (after == null) {
      return;
    }

    final scopedBeforeDurations = {
      for (final id in after.durations.keys) id: _beforeDurations[id]!,
    };
    final scopedBeforeGaps = {
      for (final id in after.gaps.keys) id: _beforeGaps[id]!,
    };

    // "The cut ENDS WHERE THE ROW ENDS" (see [ExposureEdgeDrag]). A drag
    // that changes the duration without going near the row would leave a
    // conte cut's stored row ending somewhere the cut no longer does — and
    // the next end/comma drag, which derives the duration FROM the row end,
    // would snap the cut back to the stale one and shove the cuts behind it.
    //
    // The two edges pay that debt at opposite ends of the row. A LEAD drag
    // already decided which panel gives way, back when it knew the pointer's
    // grip. A TRAILING one has no such record, and its last panel simply
    // follows the new end.
    final rowEdits = after.rowEdits.isNotEmpty
        ? after.rowEdits
        : _rowEditsForResizedCuts(
            beforeDurations: scopedBeforeDurations,
            afterDurations: after.durations,
          );
    if (rowEdits.isNotEmpty) {
      _roles.controllers.timelineController
          .commitLayerTimelineDragsWithCutDurations(
            edits: rowEdits,
            beforeDurations: scopedBeforeDurations,
            afterDurations: after.durations,
            beforeGaps: scopedBeforeGaps,
            afterGaps: after.gaps,
            description: 'Trim cut duration',
          );
      _roles.changes.refreshAfterCutCommand();
      _roles.changes.warmActiveCut();
      _roles.changes.notifyChanged();
      return;
    }

    _roles.project.cutCommandCoordinator.commitCutDurationDrag(
      beforeDurations: scopedBeforeDurations,
      afterDurations: after.durations,
      beforeGaps: scopedBeforeGaps,
      afterGaps: after.gaps,
    );
    _roles.changes.refreshAfterCutCommand();
    _roles.changes.notifyChanged();
  }

  /// Drops an in-flight trim preview without touching history (the
  /// repository was never written during the drag).
  @override
  void cancel() {
    _roles.internals.dragPreview.value = null;
  }

  /// The storyboard-row rewrites a duration change owes, one per resized cut
  /// that HAS a row: the row re-tiled to the cut's new length, so its last
  /// panel ends exactly where the cut now does.
  ///
  /// Empty when no resized cut has a row — the overwhelmingly common case,
  /// and the one that keeps the plain cut-duration command as the commit.
  List<({Layer before, Layer after})> _rowEditsForResizedCuts({
    required Map<CutId, int> beforeDurations,
    required Map<CutId, int> afterDurations,
  }) {
    final edits = <({Layer before, Layer after})>[];
    for (final entry in afterDurations.entries) {
      if (beforeDurations[entry.key] == entry.value) {
        continue;
      }
      final cut = _roles.project.cutById(entry.key);
      final row = cut == null ? null : storyboardLayerForCut(cut);
      if (row == null) {
        continue;
      }
      final filled = storyboardTimelineFilledToCover(
        timeline: row.timeline,
        cutDuration: entry.value,
      );
      if (filled == null || mapEquals(filled, row.timeline)) {
        continue;
      }
      edits.add((before: row, after: row.copyWith(timeline: filled)));
    }
    return edits;
  }
}

/// The LEAD (start) edge: the END stays put and the LENGTH changes, so
/// nothing behind moves; a GLUED predecessor rides the boundary in either
/// direction and a separated one lets its gap absorb the move; growth is
/// walled by frame 0 and shrink by the grabbed panel's floor.
///
/// Two behaviours used to live here — this one's ancestor opened the dragged
/// cut's own leading gap, and a cut WITH a conte row went somewhere else
/// entirely (a lead retime that pinned the start and pulled the followers
/// in). Neither was what the timeline does, and the fork is why the
/// storyboard read as a different instrument.
final class CutLeadTrimDrag extends CutTrimDrag {
  CutLeadTrimDrag._({
    required super.roles,
    required super.cutId,
    required super.beforeDurations,
    required super.beforeGaps,
    required List<CutId> order,
    required int index,
    required int panelIndex,
  }) : _order = order,
       _index = index,
       _panelIndex = panelIndex,
       super._();

  /// Track cut order + the dragged cut's slot, snapshotted because the
  /// leftward cascade pushes predecessor gaps (R12-⑦).
  final List<CutId> _order;
  final int _index;

  /// Which conte PANEL this drag grabbed, cut-local. Every panel hangs a
  /// front grip on the strip (user's rule 2026-08-02), and the panel you
  /// grabbed is the one that loses commas — so the verb cannot be resolved
  /// from the cut alone.
  final int _panelIndex;

  @override
  ({Map<CutId, int> durations, Map<CutId, int> gaps}) _plan(
    int cumulativeDelta,
  ) {
    // The floor is the STORYBOARD row's extent, not one frame: its cells are
    // panels OF this cut, so an edge cannot be dragged past the panel it
    // belongs to (delete the cells to shrink further). Cuts without a
    // storyboard row keep the plain one-frame floor.
    final trimmedCut = _roles.project.cutById(_cutId);
    final plan = planCutLeadEdge(
      slots: [
        for (final id in _order)
          (
            id: id,
            leadingGapFrames: _beforeGaps[id]!,
            // Nothing but the dragged cut changes duration mid-drag, and the
            // preview never touches the repository, so a live read IS the
            // before-value for every slot.
            duration: _roles.project.cutById(id)?.duration ?? 1,
          ),
      ],
      targetIndex: _index,
      frameDelta: cumulativeDelta,
      minDuration: trimmedCut == null ? 1 : _minimumDurationFor(trimmedCut),
    );
    return (durations: plan.durations, gaps: plan.gaps);
  }

  /// How far this drag may shrink the cut, as a minimum DURATION — the shape
  /// [planCutLeadEdge] wants.
  ///
  /// The floor belongs to the panel the grip is on: that panel keeps one
  /// frame, and since every other panel keeps its commas, the cut's floor is
  /// its current duration less that panel's room. A cut with no conte row
  /// (or a row a drag cannot address) keeps the plain one-frame floor.
  ///
  /// ⚠️ [minimumCutDurationFor] is the LAST panel's floor and is the right
  /// answer for the trailing edge only. Using it here let a drag ask the
  /// first cell for a negative length — the assert in
  /// [StoryboardCoverageCell] — whenever the grabbed panel was shorter than
  /// the last one.
  int _minimumDurationFor(Cut cut) {
    final row = storyboardLayerForCut(cut);
    if (row == null) {
      return 1;
    }
    final maxShrink = storyboardPanelLeadMaxShrink(
      timeline: row.timeline,
      cutDuration: cut.duration,
      panelIndex: _panelIndex,
    );
    return maxShrink == null ? 1 : math.max(1, cut.duration - maxShrink);
  }

  /// The conte-row rewrite a LEAD drag owes: the grabbed panel loses the
  /// applied frames off its front and every other panel keeps its commas.
  ///
  /// The shift is read off the plan's own result, never off the raw
  /// cumulative delta — the plan clamps, and the delta does not know it did.
  ///
  /// Empty when the cut has no row, when the drag was clamped to nothing, or
  /// when the row cannot be addressed — in each of those the plain cut
  /// duration change is the whole edit.
  @override
  List<({Layer before, Layer after})> _rowEditsForPlan(
    ({Map<CutId, int> durations, Map<CutId, int> gaps}) planned,
  ) {
    final applied =
        _beforeDurations[_cutId]! - (planned.durations[_cutId] ?? 0);
    if (applied == 0) {
      return const [];
    }
    final cut = _roles.project.cutById(_cutId);
    final row = cut == null ? null : storyboardLayerForCut(cut);
    if (cut == null || row == null) {
      return const [];
    }
    final retimed = storyboardTimelineWithPanelLeadRetimed(
      timeline: row.timeline,
      cutDuration: cut.duration,
      panelIndex: _panelIndex,
      delta: applied,
    );
    if (retimed == null || mapEquals(retimed, row.timeline)) {
      return const [];
    }
    return [(before: row, after: row.copyWith(timeline: retimed))];
  }
}

/// The TRAILING (end) edge: the duration changes; growth consumes the
/// FOLLOWING cut's leading gap first (that cut holds still until the gap is
/// spent, then ripples). Shrinking follows the timeline's block language
/// (R10-⑦): only an ATTACHED next cut rides the boundary — a detached one
/// holds its global position (its gap grows by the shrink).
final class CutTrailTrimDrag extends CutTrimDrag {
  CutTrailTrimDrag._({
    required super.roles,
    required super.cutId,
    required super.beforeDurations,
    required super.beforeGaps,
    required CutId? nextCutId,
  }) : _nextCutId = nextCutId,
       super._();

  /// The cut behind this one on the same track, or null at the track's end.
  final CutId? _nextCutId;

  @override
  ({Map<CutId, int> durations, Map<CutId, int> gaps}) _plan(
    int cumulativeDelta,
  ) {
    // The trailing edge sits on the LAST panel, so its floor is the row's
    // full extent ([minimumCutDurationFor]); cuts without a storyboard row
    // keep the plain one-frame floor.
    final trimmedCut = _roles.project.cutById(_cutId);
    final minDuration = trimmedCut == null
        ? 1
        : minimumCutDurationFor(trimmedCut);
    final beforeDuration = _beforeDurations[_cutId]!;
    final newDuration = math.max(minDuration, beforeDuration + cumulativeDelta);
    final gaps = <CutId, int>{};
    final nextId = _nextCutId;
    if (nextId != null) {
      gaps[nextId] = followingGapAfterEndMove(
        baseGap: _beforeGaps[nextId]!,
        growth: newDuration - beforeDuration,
      );
    }
    return (durations: {_cutId: newDuration}, gaps: gaps);
  }
}
