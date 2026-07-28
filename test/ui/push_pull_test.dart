import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/storyboard_timeline_layout.dart';

/// Design D: the rigid shove a drag used to do, as a verb you aim. One rule
/// for two axes — the arithmetic is shared, only the commit differs.
void main() {
  EditorSessionManager session() {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    return s;
  }

  int layoutStart(EditorSessionManager s, CutId cutId) =>
      buildStoryboardTimelineLayout(
        s.repository.requireProject(),
      ).firstWhere((entry) => entry.cutId == cutId).startFrame;

  group('cut axis', () {
    test('push slides the active cut and everything after it, lengths '
        'untouched', () {
      final s = session();
      s.createCut();
      final track = s.repository.requireProject().tracks.first;
      final first = track.cuts[0].id;
      final second = track.cuts[1].id;
      final secondStart = layoutStart(s, second);
      final firstDuration = s.cutById(first)!.duration;

      s.selectCut(first);
      expect(s.canPushCuts, isTrue);
      s.pushCuts(6);

      expect(layoutStart(s, first), 6);
      expect(layoutStart(s, second), secondStart + 6);
      expect(s.cutById(first)!.duration, firstDuration);

      // ONE undo step.
      s.undo();
      expect(layoutStart(s, first), 0);
      expect(layoutStart(s, second), secondStart);
    });

    test('pull closes the lead-in and stops at frame 0', () {
      final s = session();
      s.createCut();
      final first = s.repository.requireProject().tracks.first.cuts[0].id;

      s.selectCut(first);
      s.pushCuts(6);
      expect(s.cutPullSlack, 6);

      // Asking for more than there is closes what there is.
      s.pullCuts(10);
      expect(layoutStart(s, first), 0);
      expect(s.canPullCuts, isFalse);
    });

    test('a packed track cannot pull — nothing to close', () {
      final s = session();
      s.createCut();
      s.selectCut(s.repository.requireProject().tracks.first.cuts[0].id);

      expect(s.canPushCuts, isTrue);
      expect(s.canPullCuts, isFalse);
    });

    test('the SELECTION decides the anchor: the run\'s first cut', () {
      final s = session();
      s.createCut();
      s.createCut();
      final track = s.repository.requireProject().tracks.first;
      final first = track.cuts[0].id;
      final second = track.cuts[1].id;
      final third = track.cuts[2].id;
      final secondStart = layoutStart(s, second);

      // Select [second, third]: the shove starts at the second cut, so the
      // first one never moves.
      s.updateStoryboardCutSelectionByFrame(
        anchorGlobalFrame: secondStart,
        headGlobalFrame: layoutStart(s, third),
      );
      s.pushCuts(4);

      expect(layoutStart(s, first), 0);
      expect(layoutStart(s, second), secondStart + 4);
      expect(layoutStart(s, third), layoutStart(s, second) + 24);
    });

    test('push restores what a drag can no longer do: a lead-in gap in '
        'front of a packed track', () {
      final s = session();
      s.createCut();
      final first = s.repository.requireProject().tracks.first.cuts[0].id;

      // The drag stops at contact now, so it cannot open this.
      expect(s.beginCutMoveDrag(first), isTrue);
      s.updateCutMoveDrag(5);
      expect(s.dragPreview.value, isNull);
      s.cancelCutMoveDrag();

      s.selectCut(first);
      s.pushCuts(5);
      expect(layoutStart(s, first), 5);
    });
  });

  group('frame axis', () {
    /// One drawing at frame 0 and another at frame 4 — a block, a gap, a
    /// block.
    EditorSessionManager twoBlockSession() {
      final s = session();
      s.selectFrameIndex(0);
      s.createDrawingAtCurrentFrame();
      s.selectFrameIndex(4);
      s.createDrawingAtCurrentFrame();
      expect(blocksOf(s), [(0, 1), (4, 5)]);
      return s;
    }

    test('push opens frames at the playhead and the blocks after keep '
        'their spacing', () {
      final s = twoBlockSession();

      s.selectFrameIndex(4);
      expect(s.canPushFrames(), isTrue);
      s.pushFrames(3);

      expect(blocksOf(s), [(0, 1), (7, 8)]);

      // ONE undo step.
      s.undo();
      expect(blocksOf(s), [(0, 1), (4, 5)]);
    });

    test('pull closes the gap and stops where the blocks touch', () {
      final s = twoBlockSession();

      s.selectFrameIndex(4);
      expect(s.framePullSlack(), 3);

      // Asking for more than there is closes what there is.
      s.pullFrames(9);
      expect(blocksOf(s), [(0, 1), (1, 2)]);
      expect(s.canPullFrames(), isFalse);
    });

    test('a block STRADDLING the anchor stays put — the anchor is a '
        'boundary, not a split', () {
      final s = twoBlockSession();

      // Grow the first block over frames 0..3, then anchor inside it.
      s.selectFrameIndex(0);
      s.setCommaForSelectionOrCurrent(4);
      expect(blocksOf(s), [(0, 4), (4, 5)]);

      s.clearFrameRangeSelection();
      s.selectFrameIndex(2);
      s.pushFrames(2);

      // The straddled block held; only the one starting after the anchor
      // travelled.
      expect(blocksOf(s), [(0, 4), (6, 7)]);
    });

    test('the SELECTION decides the rows AND the anchor', () {
      final s = twoBlockSession();
      final layerId = s.activeLayerId!;

      // Select the SECOND block: the shove starts at its start.
      s.updateFrameRangeSelectionDrag(
        layerId: layerId,
        anchorIndex: 4,
        headIndex: 4,
      );
      s.pushFrames(2);

      expect(blocksOf(s), [(0, 1), (6, 7)]);
    });
  });
}

/// The active layer's drawing block spans, for readable expectations.
List<(int, int)> blocksOf(EditorSessionManager s) {
  final layer = s.activeLayer!;
  return [
    for (final entry in layer.timeline.entries)
      (entry.key, entry.key + entry.value.length!),
  ];
}
