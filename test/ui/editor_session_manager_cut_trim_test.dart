import 'package:flutter_test/flutter_test.dart';
import 'package:quick_animaker_v2/src/controllers/default_project_helpers.dart';
import 'package:quick_animaker_v2/src/models/cut_id.dart';
import 'package:quick_animaker_v2/src/models/property_track.dart';
import 'package:quick_animaker_v2/src/models/timeline_coverage.dart'
    show TimelineBlockEdge;
import 'package:quick_animaker_v2/src/models/transform_track.dart';
import 'package:quick_animaker_v2/src/ui/editor_session_manager.dart';
import 'package:quick_animaker_v2/src/ui/storyboard_cut_fade_policy.dart';
import 'package:quick_animaker_v2/src/ui/storyboard_timeline_layout.dart';
import 'package:quick_animaker_v2/src/ui/timeline/timeline_drag_preview.dart';

void main() {
  /// Two cuts on the default track; returns (session, first id, second id).
  (EditorSessionManager, CutId, CutId) twoCutSession() {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    s.createCut();
    final track = s.repository.requireProject().tracks.first;
    return (s, track.cuts[0].id, track.cuts[1].id);
  }

  /// The previewed duration for [cutId], falling back to the repository
  /// (what a preview consumer renders during the drag).
  int previewedDuration(EditorSessionManager s, CutId cutId) {
    final preview = s.dragPreview.value;
    if (preview is CutTrimDragPreview &&
        preview.previewDurations.containsKey(cutId)) {
      return preview.previewDurations[cutId]!;
    }
    return s.cutById(cutId)!.duration;
  }

  /// The previewed leading gap for [cutId], falling back to the repository.
  int previewedGap(EditorSessionManager s, CutId cutId) {
    final preview = s.dragPreview.value;
    if (preview is CutTrimDragPreview &&
        preview.previewGaps.containsKey(cutId)) {
      return preview.previewGaps[cutId]!;
    }
    return s.cutById(cutId)!.leadingGapFrames;
  }

  /// [cutId]'s committed global start frame on the track layout.
  int layoutStart(EditorSessionManager s, CutId cutId) {
    return buildStoryboardTimelineLayout(
      s.repository.requireProject(),
    ).firstWhere((entry) => entry.cutId == cutId).startFrame;
  }

  /// The previewed cut order for the only track, or null when the live
  /// preview is a re-time rather than a reorder.
  List<CutId>? previewOrderOf(EditorSessionManager s) {
    final preview = s.dragPreview.value;
    if (preview is! CutTrimDragPreview) {
      return null;
    }
    return preview.previewOrder[s.repository.requireProject().tracks.first.id];
  }

  /// A cut-select drag stated the way the panel's gesture states it —
  /// track-global frames inside the anchor and head cuts.
  void selectCutRun(EditorSessionManager s, CutId anchor, CutId head) {
    s.updateStoryboardCutSelectionByFrame(
      anchorGlobalFrame: layoutStart(s, anchor),
      headGlobalFrame: layoutStart(s, head),
    );
  }

  test('end-edge drag previews on the channel and commits one undo', () {
    final (s, first, _) = twoCutSession();
    final before = s.cutById(first)!.duration;
    var notifies = 0;
    s.addListener(() => notifies += 1);

    expect(
      s.beginCutEdgeDrag(cutId: first, edge: TimelineBlockEdge.end),
      isTrue,
    );
    s.updateCutEdgeDrag(3);
    // The preview rides the channel; the REPOSITORY stays untouched and no
    // session notify fires per step (the drag-lag fix's core invariant).
    expect(previewedDuration(s, first), before + 3);
    expect(s.cutById(first)!.duration, before);
    expect(notifies, 0);

    // Cumulative deltas recompute from the snapshot; a huge negative clamps
    // at one frame.
    s.updateCutEdgeDrag(-before - 30);
    expect(previewedDuration(s, first), 1);

    s.updateCutEdgeDrag(6);
    expect(previewedDuration(s, first), before + 6);

    s.endCutEdgeDrag();
    expect(s.cutById(first)!.duration, before + 6);
    expect(s.dragPreview.value, isNull);
    expect(notifies, 1);

    // ONE undo step for the whole drag.
    s.undo();
    expect(s.cutById(first)!.duration, before);
    s.redo();
    expect(s.cutById(first)!.duration, before + 6);
  });

  test('start-edge drag TRIMS from the front (R12-B): the end stays put, '
      'rightward shrinks the length and opens the gap', () {
    final (s, first, second) = twoCutSession();
    final firstDuration = s.cutById(first)!.duration;
    final secondDuration = s.cutById(second)!.duration;
    final secondEnd = firstDuration + secondDuration;

    expect(
      s.beginCutEdgeDrag(cutId: second, edge: TimelineBlockEdge.start),
      isTrue,
    );

    // Rightward: the start moves later — the gap opens, the LENGTH
    // shrinks, and the end (with everything after it) never moves.
    s.updateCutEdgeDrag(5);
    expect(previewedGap(s, second), 5);
    expect(previewedDuration(s, second), secondDuration - 5);
    expect(previewedDuration(s, first), firstDuration);

    // Rightward movement clamps at length 1.
    s.updateCutEdgeDrag(secondDuration + 40);
    expect(previewedDuration(s, second), 1);

    // Leftward past the wall (no gap, no predecessor slack) clamps back
    // to the original start — nothing changes.
    s.updateCutEdgeDrag(-9);
    expect(s.dragPreview.value, isNull);

    s.updateCutEdgeDrag(4);
    s.endCutEdgeDrag();
    expect(s.cutById(second)!.leadingGapFrames, 4);
    expect(s.cutById(second)!.duration, secondDuration - 4);
    expect(layoutStart(s, second), firstDuration + 4);
    // The cut's END is pinned.
    expect(layoutStart(s, second) + s.cutById(second)!.duration, secondEnd);

    // ONE undo step restores the gap AND the length.
    s.undo();
    expect(s.cutById(second)!.leadingGapFrames, 0);
    expect(s.cutById(second)!.duration, secondDuration);
    s.redo();
    expect(s.cutById(second)!.duration, secondDuration - 4);
  });

  test('start-edge leftward GROWTH pushes predecessors through their gaps '
      '(block-body push language) and adds the movement to the length', () {
    final (s, first, second) = twoCutSession();

    // Give the FIRST cut a 4-frame lead-in gap. Its START edge trims from
    // the front, which is what opens a lead-in — a move drag cannot, with
    // the second cut packed against it.
    s.beginCutEdgeDrag(cutId: first, edge: TimelineBlockEdge.start);
    s.updateCutEdgeDrag(4);
    s.endCutEdgeDrag();
    expect(layoutStart(s, first), 4);

    final firstDuration = s.cutById(first)!.duration;
    final secondDuration = s.cutById(second)!.duration;
    final secondEnd = layoutStart(s, second) + secondDuration;

    // Grow the SECOND cut's start left by 6: its own gap is 0, so the
    // cascade pushes the first cut left through ITS gap (4 frames of
    // slack) and clamps there — the length grows by the achieved 4.
    s.beginCutEdgeDrag(cutId: second, edge: TimelineBlockEdge.start);
    s.updateCutEdgeDrag(-6);
    expect(previewedGap(s, first), 0);
    expect(previewedDuration(s, second), secondDuration + 4);
    s.endCutEdgeDrag();

    expect(s.cutById(first)!.leadingGapFrames, 0);
    expect(layoutStart(s, first), 0);
    expect(s.cutById(second)!.duration, secondDuration + 4);
    expect(layoutStart(s, second), firstDuration);
    // The END is pinned; the predecessor's length never changes.
    expect(layoutStart(s, second) + s.cutById(second)!.duration, secondEnd);
    expect(s.cutById(first)!.duration, firstDuration);
  });

  test('the FIRST cut start-trims too — its gap is black lead-in and the '
      'rest of the track never moves (end pinned)', () {
    final (s, first, second) = twoCutSession();
    final firstDuration = s.cutById(first)!.duration;
    final secondStart = layoutStart(s, second);

    expect(
      s.beginCutEdgeDrag(cutId: first, edge: TimelineBlockEdge.start),
      isTrue,
    );
    s.updateCutEdgeDrag(3);
    s.endCutEdgeDrag();

    expect(s.cutById(first)!.leadingGapFrames, 3);
    expect(s.cutById(first)!.duration, firstDuration - 3);
    expect(layoutStart(s, first), 3);
    // The follower NEVER moves on a start trim.
    expect(layoutStart(s, second), secondStart);
  });

  test('end-edge growth eats the following gap first — the next cut holds '
      'still until the gap is spent, then gets pushed', () {
    final (s, first, second) = twoCutSession();
    final firstDuration = s.cutById(first)!.duration;

    // Open a 4-frame gap before the second cut.
    s.beginCutEdgeDrag(cutId: second, edge: TimelineBlockEdge.start);
    s.updateCutEdgeDrag(4);
    s.endCutEdgeDrag();
    expect(layoutStart(s, second), firstDuration + 4);

    // Grow the first cut by 3: the gap absorbs it, the second cut's start
    // does not move.
    s.beginCutEdgeDrag(cutId: first, edge: TimelineBlockEdge.end);
    s.updateCutEdgeDrag(3);
    expect(previewedDuration(s, first), firstDuration + 3);
    expect(previewedGap(s, second), 1);
    s.endCutEdgeDrag();
    expect(s.cutById(second)!.leadingGapFrames, 1);
    expect(layoutStart(s, second), firstDuration + 4);

    // Grow past the remaining gap: gap 0, the excess pushes the second cut.
    s.beginCutEdgeDrag(cutId: first, edge: TimelineBlockEdge.end);
    s.updateCutEdgeDrag(3);
    s.endCutEdgeDrag();
    expect(s.cutById(second)!.leadingGapFrames, 0);
    expect(layoutStart(s, second), firstDuration + 6);
  });

  test('end-edge shrink with a DETACHED next cut leaves it in place — the '
      'gap absorbs the shrink (R10-⑦: the timeline block language)', () {
    final (s, first, second) = twoCutSession();
    final firstDuration = s.cutById(first)!.duration;

    s.beginCutEdgeDrag(cutId: second, edge: TimelineBlockEdge.start);
    s.updateCutEdgeDrag(4);
    s.endCutEdgeDrag();
    final secondStart = layoutStart(s, second);

    s.beginCutEdgeDrag(cutId: first, edge: TimelineBlockEdge.end);
    s.updateCutEdgeDrag(-2);
    expect(previewedGap(s, second), 6);
    s.endCutEdgeDrag();

    expect(s.cutById(first)!.duration, firstDuration - 2);
    expect(s.cutById(second)!.leadingGapFrames, 6);
    expect(
      layoutStart(s, second),
      secondStart,
      reason: 'a detached cut never rides a neighbor\'s trim',
    );
  });

  test('end-edge shrink with an ATTACHED next cut ripples it along (gap '
      'stays 0 — attachment is preserved)', () {
    final (s, first, second) = twoCutSession();
    final firstDuration = s.cutById(first)!.duration;

    s.beginCutEdgeDrag(cutId: first, edge: TimelineBlockEdge.end);
    s.updateCutEdgeDrag(-3);
    expect(previewedGap(s, second), 0);
    s.endCutEdgeDrag();

    expect(s.cutById(first)!.duration, firstDuration - 3);
    expect(s.cutById(second)!.leadingGapFrames, 0);
    expect(layoutStart(s, second), firstDuration - 3);
  });

  test('a trim re-anchors the CANONICAL fade to the new duration — the '
      'fade-out keeps riding the cut end, in the SAME undo step (W4 fade '
      'durability)', () {
    final (s, first, _) = twoCutSession();
    final duration = s.cutById(first)!.duration;
    s.setCutFade(first, fadeInFrames: 0, fadeOutFrames: 6);

    s.beginCutEdgeDrag(cutId: first, edge: TimelineBlockEdge.end);
    s.updateCutEdgeDrag(-4);
    s.endCutEdgeDrag();

    final trimmed = s.cutById(first)!;
    expect(trimmed.duration, duration - 4);
    expect(cutFadeLengths(trimmed), (fadeInFrames: 0, fadeOutFrames: 6));
    final trimmedLast = trimmed.duration - 1;
    expect(trimmed.transformTrack.opacity.keyAt(trimmedLast)!.value, 0.0);
    expect(trimmed.transformTrack.opacity.keyAt(trimmedLast - 6)!.value, 1.0);

    // ONE undo restores the duration AND the original fade keys exactly.
    s.undo();
    final restored = s.cutById(first)!;
    expect(restored.duration, duration);
    expect(cutFadeLengths(restored), (fadeInFrames: 0, fadeOutFrames: 6));
    expect(restored.transformTrack.opacity.keyAt(duration - 1)!.value, 0.0);
    expect(restored.transformTrack.opacity.keyAt(duration - 1 - 6)!.value, 1.0);

    // Growth re-anchors the same way: the fade-out rides the new end.
    s.beginCutEdgeDrag(cutId: first, edge: TimelineBlockEdge.end);
    s.updateCutEdgeDrag(5);
    s.endCutEdgeDrag();
    final grown = s.cutById(first)!;
    expect(grown.duration, duration + 5);
    expect(grown.transformTrack.opacity.keyAt(grown.duration - 1)!.value, 0.0);
    expect(cutFadeLengths(grown), (fadeInFrames: 0, fadeOutFrames: 6));
  });

  test('a hand-keyed (non-canonical) opacity lane survives a trim '
      'untouched — the invariant only owns the canonical fade shape', () {
    final (s, first, _) = twoCutSession();
    final custom = TransformTrack.empty().copyWith(
      opacity: PropertyTrack<double>.empty().withKey(3, 0.4).withKey(7, 0.9),
    );
    s.updateCutTransformTrack(first, custom);

    s.beginCutEdgeDrag(cutId: first, edge: TimelineBlockEdge.end);
    s.updateCutEdgeDrag(-4);
    s.endCutEdgeDrag();

    expect(s.cutById(first)!.transformTrack.opacity, custom.opacity);
  });

  test('a start-edge TRIM re-anchors the canonical fade to the new length '
      '(the fade-out keeps riding the end — same durability as end trims)', () {
    final (s, _, second) = twoCutSession();
    s.setCutFade(second, fadeInFrames: 2, fadeOutFrames: 3);

    s.beginCutEdgeDrag(cutId: second, edge: TimelineBlockEdge.start);
    s.updateCutEdgeDrag(5);
    s.endCutEdgeDrag();

    expect(s.cutById(second)!.leadingGapFrames, 5);
    final lengths = cutFadeLengths(s.cutById(second)!);
    expect(lengths.fadeInFrames, 2);
    expect(lengths.fadeOutFrames, 3);
  });

  test('cancel drops the preview without touching history or the repo', () {
    final (s, first, _) = twoCutSession();
    final before = s.cutById(first)!.duration;
    final undoDepthProbe = s.canUndo; // createCut is already undoable.

    s.beginCutEdgeDrag(cutId: first, edge: TimelineBlockEdge.end);
    s.updateCutEdgeDrag(5);
    expect(previewedDuration(s, first), before + 5);
    expect(s.cutById(first)!.duration, before);

    s.cancelCutEdgeDrag();
    expect(s.dragPreview.value, isNull);
    expect(s.cutById(first)!.duration, before);
    expect(s.canUndo, undoDepthProbe);

    // Undo now reverts the CUT CREATION, not a phantom trim.
    s.undo();
    expect(s.repository.requireProject().tracks.first.cuts, hasLength(1));
  });

  test('ending an unchanged drag leaves no undo entry', () {
    final (s, first, _) = twoCutSession();

    s.beginCutEdgeDrag(cutId: first, edge: TimelineBlockEdge.end);
    s.updateCutEdgeDrag(0);
    s.endCutEdgeDrag();

    // The only undoable step is still the cut creation.
    s.undo();
    expect(s.repository.requireProject().tracks.first.cuts, hasLength(1));
    expect(s.canUndo, isFalse);
  });

  group('whole-block move drags (R10-④)', () {
    test('a rightward move eats the follower\'s gap and stops at contact — '
        'it never shoves the follower along', () {
      final (s, first, second) = twoCutSession();
      final firstStart = layoutStart(s, first);
      final secondStart = layoutStart(s, second);

      // Open a 3-frame gap before the second cut, then move the FIRST cut
      // right by 5: only 3 frames of free space exist, so it lands there
      // and the second cut does not move at all.
      s.beginCutEdgeDrag(cutId: second, edge: TimelineBlockEdge.start);
      s.updateCutEdgeDrag(3);
      s.endCutEdgeDrag();

      expect(s.beginCutMoveDrag(first), isTrue);
      s.updateCutMoveDrag(5);
      expect(previewedGap(s, first), 3);
      expect(previewedGap(s, second), 0);
      s.endCutMoveDrag();

      expect(layoutStart(s, first), firstStart + 3);
      expect(layoutStart(s, second), secondStart + 3);

      // ONE undo restores both gaps.
      s.undo();
      expect(layoutStart(s, first), firstStart);
      expect(layoutStart(s, second), secondStart + 3);
    });

    test('a leftward move consumes its own gap and stops at the '
        'predecessor; the predecessor holds still', () {
      final (s, first, second) = twoCutSession();

      // first: gap 4, second: gap 2.
      s.beginCutEdgeDrag(cutId: first, edge: TimelineBlockEdge.start);
      s.updateCutEdgeDrag(4);
      s.endCutEdgeDrag();
      s.beginCutEdgeDrag(cutId: second, edge: TimelineBlockEdge.start);
      s.updateCutEdgeDrag(2);
      s.endCutEdgeDrag();
      final secondStart = layoutStart(s, second);
      final firstStart = layoutStart(s, first);

      // Move the SECOND cut left by 5: its own 2 frames of gap are all it
      // has, so it stops touching the first cut, which never moves.
      expect(s.beginCutMoveDrag(second), isTrue);
      s.updateCutMoveDrag(-5);
      expect(previewedGap(s, second), 0);
      expect(previewedGap(s, first), 4);
      s.endCutMoveDrag();

      expect(layoutStart(s, second), secondStart - 2);
      expect(layoutStart(s, first), firstStart);
    });

    test('a leftward move clamps at the chain\'s total slack (frame 0)', () {
      final (s, first, second) = twoCutSession();
      // No gaps anywhere: the first cut cannot move left at all.
      expect(s.beginCutMoveDrag(first), isTrue);
      s.updateCutMoveDrag(-10);
      expect(s.dragPreview.value, isNull, reason: 'nothing can change');
      s.endCutMoveDrag();
      expect(layoutStart(s, first), 0);
      expect(layoutStart(s, second), s.cutById(first)!.duration);
    });

    test('moving a MIDDLE cut left keeps its follower in place (the gap '
        'behind it grows)', () {
      final (s, first, second) = twoCutSession();
      s.beginCutEdgeDrag(cutId: second, edge: TimelineBlockEdge.start);
      s.updateCutEdgeDrag(4);
      s.endCutEdgeDrag();
      final firstDuration = s.cutById(first)!.duration;

      // Move the SECOND (last) cut left by 3 into its own gap.
      s.beginCutMoveDrag(second);
      s.updateCutMoveDrag(-3);
      s.endCutMoveDrag();
      expect(layoutStart(s, second), firstDuration + 1);
    });

    test('cancel leaves no trace', () {
      final (s, first, second) = twoCutSession();
      // Room to actually move into.
      s.beginCutEdgeDrag(cutId: second, edge: TimelineBlockEdge.start);
      s.updateCutEdgeDrag(10);
      s.endCutEdgeDrag();
      final undoDepthProbe = s.canUndo;

      s.beginCutMoveDrag(first);
      s.updateCutMoveDrag(7);
      expect(previewedGap(s, first), 7);
      s.cancelCutMoveDrag();

      expect(s.dragPreview.value, isNull);
      expect(s.cutById(first)!.leadingGapFrames, 0);
      expect(s.canUndo, undoDepthProbe);
    });
  });

  group('cut range selection (UI-R18 #1, O2c)', () {
    /// Three cuts on the default track.
    (EditorSessionManager, CutId, CutId, CutId) threeCutSession() {
      final s = EditorSessionManager(initialProject: createDefaultProject());
      s.createCut();
      s.createCut();
      final track = s.repository.requireProject().tracks.first;
      return (s, track.cuts[0].id, track.cuts[1].id, track.cuts[2].id);
    }

    test('a selection drag paints a contiguous run in track order, '
        'whichever way it sweeps', () {
      final (s, first, second, third) = threeCutSession();

      selectCutRun(s, first, second);
      expect(s.storyboardCutSelection.value, [first, second]);

      // Backwards sweep normalizes; a head dragged off the left edge
      // clamps at frame 0.
      s.updateStoryboardCutSelectionByFrame(
        anchorGlobalFrame: layoutStart(s, third),
        headGlobalFrame: -5,
      );
      expect(s.storyboardCutSelection.value, [first, second, third]);

      s.clearStoryboardCutSelection();
      expect(s.storyboardCutSelection.value, isNull);
    });

    test('a packed run has nowhere to slide: it stops at contact rather '
        'than shoving the follower along', () {
      final (s, first, second, third) = threeCutSession();
      final thirdStart = layoutStart(s, third);

      // No gaps anywhere: the run already touches the third cut, so a
      // small nudge right changes nothing at all (a bigger one would
      // reorder — see below).
      selectCutRun(s, first, second);
      expect(s.beginCutMoveDrag(first), isTrue);
      s.updateCutMoveDrag(5);
      expect(s.dragPreview.value, isNull);
      s.endCutMoveDrag();

      expect(layoutStart(s, first), 0);
      expect(layoutStart(s, second), s.cutById(first)!.duration);
      expect(layoutStart(s, third), thirdStart);
    });

    test('a drag past the neighbour\'s midpoint REORDERS the track, and '
        'the whole selected run crosses in one undo step', () {
      final (s, first, second, third) = threeCutSession();
      final undoDepthBefore = s.canUndo;

      // [first, second] dragged right past the third cut: 24-frame cuts,
      // so the pair's midpoint reaches the third's after 36 frames.
      selectCutRun(s, first, second);
      expect(s.beginCutMoveDrag(first), isTrue);
      s.updateCutMoveDrag(36);
      // The preview already shows the new order.
      expect(previewOrderOf(s), [third, first, second]);
      s.endCutMoveDrag();

      expect(
        [
          for (final cut in s.repository.requireProject().tracks.first.cuts)
            cut.id,
        ],
        [third, first, second],
      );
      expect(undoDepthBefore || s.canUndo, isTrue);

      s.undo();
      expect(
        [
          for (final cut in s.repository.requireProject().tracks.first.cuts)
            cut.id,
        ],
        [first, second, third],
      );
    });

    test('a single cut swaps with its neighbour and the gaps ride along', () {
      final (s, first, second, third) = threeCutSession();

      expect(s.beginCutMoveDrag(first), isTrue);
      s.updateCutMoveDrag(24);
      s.endCutMoveDrag();

      expect(
        [
          for (final cut in s.repository.requireProject().tracks.first.cuts)
            cut.id,
        ],
        [second, first, third],
      );
    });

    test('with follower slack the run slides INTO the gap: members keep '
        'formation, the follower holds still', () {
      final (s, first, second, third) = threeCutSession();

      // Open a 6-frame gap before the THIRD cut.
      s.beginCutEdgeDrag(cutId: third, edge: TimelineBlockEdge.start);
      s.updateCutEdgeDrag(6);
      s.endCutEdgeDrag();
      final thirdStart = layoutStart(s, third);

      selectCutRun(s, first, second);
      expect(s.beginCutMoveDrag(second), isTrue);
      s.updateCutMoveDrag(4);
      s.endCutMoveDrag();

      // The run moved 4 together; the third cut's gap absorbed it all.
      expect(layoutStart(s, first), 4);
      expect(layoutStart(s, second), 4 + s.cutById(first)!.duration);
      expect(layoutStart(s, third), thirdStart);
      expect(s.cutById(third)!.leadingGapFrames, 2);
    });

    test('deleteSelectedCuts removes the run as ONE undo step; deleting '
        'every cut is refused', () {
      final (s, first, second, third) = threeCutSession();

      // Selecting ALL cuts: delete stands down (the project never
      // empties).
      selectCutRun(s, first, third);
      expect(s.canDeleteSelectedCuts, isFalse);
      s.deleteSelectedCuts();
      expect(s.repository.requireProject().tracks.first.cuts.length, 3);

      // A two-cut run deletes in one step and clears the selection.
      selectCutRun(s, first, second);
      expect(s.canDeleteSelectedCuts, isTrue);
      s.deleteSelectedCuts();
      final cutsAfter = s.repository.requireProject().tracks.first.cuts;
      expect([for (final cut in cutsAfter) cut.id], [third]);
      expect(s.storyboardCutSelection.value, isNull);

      // ONE undo restores both.
      s.undo();
      final cutsRestored = s.repository.requireProject().tracks.first.cuts;
      expect([for (final cut in cutsRestored) cut.id], [first, second, third]);
    });

    test('deleteActiveCut routes to the selection while one is live', () {
      final (s, first, second, third) = threeCutSession();
      s.selectCut(third);

      selectCutRun(s, first, second);
      s.deleteActiveCut();

      // The SELECTED run went, not the active cut.
      final cutsAfter = s.repository.requireProject().tracks.first.cuts;
      expect([for (final cut in cutsAfter) cut.id], [third]);
      expect(s.activeCutId, third);
    });
  });
}
