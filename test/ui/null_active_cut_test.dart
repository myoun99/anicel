import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/playback/canvas_playback_controller.dart';
import 'package:anicel/src/ui/storyboard_playhead_mapping.dart';

/// UI-R9 #3: standing in a GAP means NO cut is selected — the session's
/// activeCutId goes NULL, cut-scoped surfaces empty out and cut-scoped
/// commands stand down without crashing.
void main() {
  /// Two default-track cuts with a 4-frame gap before the second.
  (EditorSessionManager, CutId, CutId, int) gappedSession() {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    s.createCut();
    final track = s.repository.requireProject().tracks.first;
    final first = track.cuts[0].id;
    final second = track.cuts[1].id;
    s.repository.updateCutLeadingGap(cutId: second, leadingGapFrames: 4);
    return (s, first, second, track.cuts[0].duration);
  }

  test('a committed gap seek NULLS the active cut and empties the '
      'cut-scoped surfaces', () {
    final (s, first, _, aEnd) = gappedSession();
    addTearDown(s.dispose);
    s.selectCut(first);

    s.selectGlobalFrame(aEnd + 1);
    expect(s.activeCutId, isNull);
    expect(s.activeCutOrNull, isNull);
    expect(s.layers, isEmpty, reason: 'no rows at all — not even track SE');
    expect(s.activeLayer, isNull);
    expect(s.activeBrushEditorSelection, isNull);
    expect(s.editingPlayheadInGap, isTrue);
    expect(s.canvasSelectionLabels.cutLabel, '—');
    expect(() => s.requireActiveCut, throwsStateError);
  });

  test('hiding the ACTIVE cut\'s picture enters the no-cut state exactly '
      'like a gap landing (UI-R13 #2); re-showing RESTORES the parked '
      'position (UI-R14 #2, the symmetric inverse)', () {
    final (s, first, second, aEnd) = gappedSession();
    addTearDown(s.dispose);
    s.selectCut(first);
    s.selectFrameIndex(2);

    // Hiding ANOTHER cut's picture: selection untouched.
    s.toggleCutPictureVisibility(second);
    expect(s.activeCutId, first);
    s.toggleCutPictureVisibility(second); // restore

    // Hiding the ACTIVE cut's picture: the index shows nothing anymore —
    // the no-cut state, parked at the exact global.
    s.toggleCutPictureVisibility(first);
    expect(s.isCutPictureVisible(first), isFalse);
    expect(s.activeCutId, isNull, reason: 'the active cut ceases');
    expect(s.gapParkedGlobalFrame, 2, reason: 'parked where it stood');
    expect(s.editingPlayheadInGap, isTrue);

    // Re-showing while parked ON the cut lands there again — as if the
    // position were clicked (without this the eye-on read as a no-op:
    // the editing view stayed in the void).
    s.toggleCutPictureVisibility(first);
    expect(s.isCutPictureVisible(first), isTrue);
    expect(s.activeCutId, first, reason: 'the parked position restores');
    expect(s.currentFrameIndex, 2);
    expect(s.editingPlayheadInGap, isFalse);

    // Parked in a REAL axis gap: re-showing a nearby cut keeps the
    // parking (nothing to land on at that index).
    s.selectGlobalFrame(aEnd + 1);
    expect(s.activeCutId, isNull);
    s.toggleCutPictureVisibility(first);
    s.toggleCutPictureVisibility(first);
    expect(s.activeCutId, isNull, reason: 'the gap parking survives');
    expect(s.gapParkedGlobalFrame, aEnd + 1);
  });

  test('a gap scrub deselects the cut IMMEDIATELY (UI-R10 #13): the empty '
      'states show during the drag, the release is a no-op backstop', () {
    final (s, first, _, aEnd) = gappedSession();
    addTearDown(s.dispose);
    s.selectCut(first);

    scrubStoryboardGlobalFrame(s, aEnd + 2);
    expect(s.activeCutId, isNull, reason: 'mid-drag already no-cut');
    expect(s.gapParkedGlobalFrame, aEnd + 2);

    commitStoryboardScrub(s);
    expect(s.activeCutId, isNull);
    expect(s.gapParkedGlobalFrame, aEnd + 2, reason: 'parking survives');
    expect(storyboardPlayheadFrame(s), aEnd + 2);
  });

  test('selecting a cut FROM the gap lands on ITS first frame '
      '(UI-R10 #14) — no stale gap-global cursor', () {
    final (s, first, second, aEnd) = gappedSession();
    addTearDown(s.dispose);
    s.selectCut(first);
    s.selectFrameIndex(3);
    s.selectGlobalFrame(aEnd + 1); // Park in the gap.
    expect(s.activeCutId, isNull);

    s.selectCut(second);

    expect(s.activeCutId, second);
    expect(s.editingFrameCursor.value, 0, reason: 'index 1 (local 0)');
    expect(s.gapParkedGlobalFrame, isNull, reason: 'parking cleared');
    expect(
      storyboardPlayheadFrame(s),
      aEnd + 4,
      reason: 'the playhead sits on the cut start, not in the gap',
    );
  });

  test('cut-scoped commands stand down in the gap state instead of '
      'crashing; undo/redo stay safe', () {
    final (s, first, _, aEnd) = gappedSession();
    addTearDown(s.dispose);
    s.selectCut(first);
    final pose = s.cameraPoseAtFrame(0); // Captured BEFORE the gap.
    s.selectGlobalFrame(aEnd + 1);
    expect(s.activeCutId, isNull);

    // Every one of these used to require a cut — now a silent stand-down.
    s.renameActiveCut('X');
    s.updateActiveCutNote('note');
    s.duplicateActiveCut();
    s.deleteActiveCut();
    s.addLayer();
    s.addLayerOfKind(LayerKind.se);
    s.setCameraKeyframeAtCurrentFrame(pose);
    s.toggleActiveCutThumbnailFrame();
    s.selectNextFrame();
    s.selectPreviousFrame();
    expect(s.activeCutId, isNull, reason: 'stand-downs kept the gap state');
    expect(
      s.repository.requireProject().tracks.first.cuts.length,
      2,
      reason: 'no cut was created/deleted by the stand-downs',
    );

    // Undo/redo replay REAL commands and may legitimately restore a cut
    // selection (cut creation owns it) — the pin here is NO CRASH from
    // the null state.
    s.undo();
    s.redo();
    expect(s.repository.requireProject().tracks.first.cuts.length, 2);
  });

  test('seeking back onto a cut restores the selection from the null '
      'state', () {
    final (s, first, second, aEnd) = gappedSession();
    addTearDown(s.dispose);
    s.selectCut(first);
    s.selectGlobalFrame(aEnd + 1);
    expect(s.activeCutId, isNull);

    s.selectGlobalFrame(aEnd + 4);
    expect(s.activeCutId, second);
    expect(s.currentFrameIndex, 0);
    expect(s.layers, isNotEmpty);
    expect(s.editingPlayheadInGap, isFalse);
  });

  testWidgets('playback FOLLOW keeps the cut through gaps; STOP in a gap '
      'deselects and parks', (tester) async {
    final (s, first, _, aEnd) = gappedSession();
    addTearDown(s.dispose);
    s.selectCut(first);

    s.playback.play(scope: PlaybackScope.allCuts);
    s.playback.seekToGlobalFrame(aEnd + 2);
    expect(s.playback.position, isNull, reason: 'a gap frame');
    expect(s.activeCutId, first, reason: 'follow keeps the last cut');

    s.playback.stop();
    expect(s.activeCutId, isNull, reason: 'stop in the gap deselects');
    expect(s.gapParkedGlobalFrame, aEnd + 2);
    await tester.pumpAndSettle();
  });

  testWidgets('active-cut-scoped play is a no-op in the gap state', (
    tester,
  ) async {
    final (s, first, _, aEnd) = gappedSession();
    addTearDown(s.dispose);
    s.selectCut(first);
    s.selectGlobalFrame(aEnd + 1);
    expect(s.activeCutId, isNull);

    s.playback.play(scope: PlaybackScope.activeCut);
    expect(s.playback.isActive, isFalse, reason: 'empty playlist — no-op');
    await tester.pumpAndSettle();
  });

  testWidgets('the timeline shows the no-cut empty state and the timesheet '
      'the bare background', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    final cutId = s.repository.requireProject().tracks.first.cuts.first.id;
    s.repository.updateCutLeadingGap(cutId: cutId, leadingGapFrames: 3);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: Listenable.merge([s, s.frameSeekCommitted]),
            builder: (context, _) => const SizedBox.expand(),
          ),
        ),
      ),
    );

    // Session-level oracles stand in for the full app pump (the hosts'
    // empty branches are plain build-time gates on activeCutOrNull; the
    // keys timeline-empty-no-cut / timesheet-empty-no-cut are covered by
    // widget_test's app-level sweeps).
    s.selectGlobalFrame(1);
    expect(s.activeCutId, isNull);
    expect(s.layers, isEmpty);
    await tester.pumpAndSettle();
  });
}
