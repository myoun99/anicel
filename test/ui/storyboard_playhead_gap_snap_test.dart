import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/playback/canvas_playback_controller.dart';
import 'package:anicel/src/ui/storyboard_playhead_mapping.dart';
import 'package:anicel/src/ui/storyboard_timeline_layout.dart';

/// R14-① (was R10-⑤b) + UI-R9 #3/#4: the editing playhead LANDS in cut
/// gaps — and a gap landing means NO CUT IS SELECTED (activeCutId null,
/// the parking carries the exact global). The timeline's over-end runway
/// stays a clipped view of the CUT: the storyboard playhead clamps to the
/// cut's last frame, never the trailing gap. Playback seeks land in gaps
/// directly (follow keeps the last cut; STOP in a gap deselects).
void main() {
  /// Two default-track cuts with a gap before the second:
  /// cut-a [0, aEnd), gap [aEnd, aEnd+4), cut-b [aEnd+4, ...).
  (EditorSessionManager, CutId, CutId, int) gappedSession() {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    s.createCut();
    final track = s.repository.requireProject().tracks.first;
    final first = track.cuts[0].id;
    final second = track.cuts[1].id;
    s.repository.updateCutLeadingGap(cutId: second, leadingGapFrames: 4);
    return (s, first, second, track.cuts[0].duration);
  }

  test('storyboardEntryOwningFrame: cut frames map to their cut, gap frames '
      'to the PRECEDING cut, past-the-end to the last cut', () {
    final (s, first, second, aEnd) = gappedSession();
    final layout = buildStoryboardTimelineLayout(s.repository.requireProject());

    expect(storyboardEntryOwningFrame(layout, 0)?.cutId, first);
    expect(storyboardEntryOwningFrame(layout, aEnd - 1)?.cutId, first);
    // Every gap frame belongs to cut-a's runway — no nearest-edge split.
    expect(storyboardEntryOwningFrame(layout, aEnd)?.cutId, first);
    expect(storyboardEntryOwningFrame(layout, aEnd + 3)?.cutId, first);
    expect(storyboardEntryOwningFrame(layout, aEnd + 4)?.cutId, second);
    expect(
      storyboardEntryOwningFrame(layout, aEnd + 400)?.cutId,
      second,
      reason: 'past the last cut = its endless runway',
    );
  });

  test('an editing seek into the gap LANDS there with NO active cut '
      '(UI-R9 #3), and the playhead maps back to the same global frame', () {
    final (s, first, _, aEnd) = gappedSession();
    s.selectCut(first);

    seekStoryboardGlobalFrame(s, aEnd + 1);
    expect(s.activeCutId, isNull, reason: 'a gap is a no-cut position');
    expect(s.gapParkedGlobalFrame, aEnd + 1);
    expect(
      storyboardPlayheadFrame(s),
      aEnd + 1,
      reason: 'the ruler shows the gap landing, not a snapped edge',
    );

    // Late in the gap: still no cut, still the exact landing.
    seekStoryboardGlobalFrame(s, aEnd + 3);
    expect(s.activeCutId, isNull);
    expect(storyboardPlayheadFrame(s), aEnd + 3);
  });

  test('a LEADING gap before the first cut PARKS the playhead exactly '
      'there (R16-⑥: a gap is a no-cut position, not a snap)', () {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    final cutId = s.repository.requireProject().tracks.first.cuts.first.id;
    s.repository.updateCutLeadingGap(cutId: cutId, leadingGapFrames: 3);

    seekStoryboardGlobalFrame(s, 1);
    expect(s.editingGlobalFrame, 1, reason: 'the ruler stays where clicked');
    expect(storyboardPlayheadFrame(s), 1);
    expect(s.editingPlayheadInGap, isTrue, reason: 'no cut here — the void');

    // Seeking back onto the cut leaves the parking.
    seekStoryboardGlobalFrame(s, 3);
    expect(s.editingPlayheadInGap, isFalse);
    expect(s.currentFrameIndex, 0);
  });

  test('gap parkings read as IN-GAP (the canvas void); cut frames do not', () {
    final (s, first, _, aEnd) = gappedSession();
    s.selectCut(first);

    s.selectGlobalFrame(aEnd + 1);
    expect(s.editingPlayheadInGap, isTrue);
    s.selectGlobalFrame(2);
    expect(s.editingPlayheadInGap, isFalse);
  });

  test('an editing scrub inside the cut rides the cursor path (no session '
      'notify); crossing into the gap deselects IMMEDIATELY (UI-R10 #13)',
      () {
    final (s, first, _, aEnd) = gappedSession();
    s.selectCut(first);
    var notifies = 0;
    s.addListener(() => notifies += 1);

    scrubStoryboardGlobalFrame(s, aEnd - 2);
    expect(s.editingFrameCursor.value, aEnd - 2);
    expect(notifies, 0, reason: 'in-cut moves stay on the cursor path');

    scrubStoryboardGlobalFrame(s, aEnd + 1);
    expect(s.activeCutId, isNull, reason: 'mid-drag no-cut (UI-R10 #13)');
    expect(s.gapParkedGlobalFrame, aEnd + 1);
    expect(notifies, 1, reason: 'ONE notify on the gap entry');
  });

  test('gap scrubs PARK per move: the first gap entry deselects (one '
      'notify), further gap moves stay silent, the release keeps the '
      'parking, and scrubbing back onto the cut re-selects', () {
    final (s, first, _, aEnd) = gappedSession();
    s.selectCut(first);
    var notifies = 0;
    s.addListener(() => notifies += 1);

    scrubStoryboardGlobalFrame(s, aEnd + 1);
    expect(s.activeCutId, isNull);
    expect(s.gapParkedGlobalFrame, aEnd + 1);
    expect(storyboardPlayheadFrame(s), aEnd + 1);
    expect(s.editingPlayheadInGap, isTrue);
    expect(notifies, 1, reason: 'the gap entry deselect');

    scrubStoryboardGlobalFrame(s, aEnd + 3);
    expect(s.gapParkedGlobalFrame, aEnd + 3);
    expect(notifies, 1, reason: 'further gap moves ride the parking only');

    commitStoryboardScrub(s);
    expect(
      s.gapParkedGlobalFrame,
      aEnd + 3,
      reason: 'the release keeps the parking (the commit used to wipe it)',
    );
    expect(storyboardPlayheadFrame(s), aEnd + 3);

    scrubStoryboardGlobalFrame(s, 2);
    expect(s.gapParkedGlobalFrame, isNull, reason: 'back on the cut');
    expect(s.activeCutId, first, reason: 'the cut re-selects');
    commitStoryboardScrub(s);
  });

  test('the LEADING gap scrub deselects on entry and parks per move '
      '(UI-R10 #13 over the UI-R7 #9 cursor path)', () {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    final cutId = s.repository.requireProject().tracks.first.cuts.first.id;
    s.repository.updateCutLeadingGap(cutId: cutId, leadingGapFrames: 3);
    var notifies = 0;
    s.addListener(() => notifies += 1);

    scrubStoryboardGlobalFrame(s, 1);
    expect(s.activeCutId, isNull);
    expect(s.gapParkedGlobalFrame, 1);
    expect(storyboardPlayheadFrame(s), 1);
    scrubStoryboardGlobalFrame(s, 2);
    expect(s.gapParkedGlobalFrame, 2);
    expect(notifies, 1, reason: 'one deselect notify, then parking only');

    commitStoryboardScrub(s);
    expect(
      storyboardPlayheadFrame(s),
      2,
      reason: 'the release stays parked in the leading gap',
    );
    expect(s.editingPlayheadInGap, isTrue);
  });

  test('the mid-track over-end playhead clamps to the CUT end, never the '
      'trailing gap (UI-R9 #4) — and the tab-switch clamp agrees', () {
    final (s, first, _, aEnd) = gappedSession();
    s.selectCut(first);

    // The timeline's runway is a clipped view of the CUT: the storyboard
    // shows it at the cut's last frame, never inside the gap.
    s.selectFrameIndex(aEnd + 40);
    expect(storyboardPlayheadFrame(s), aEnd - 1);

    clampPlayheadForStoryboard(s);
    expect(s.currentFrameIndex, aEnd - 1);

    // A runway index inside the gap clamps the same way (a gap landing is
    // the PARKED no-cut state, never a raw cut-local runway index).
    s.selectFrameIndex(aEnd + 2);
    expect(storyboardPlayheadFrame(s), aEnd - 1);
    clampPlayheadForStoryboard(s);
    expect(s.currentFrameIndex, aEnd - 1);
  });

  test('R15-①: the session speaks the axis natively — selectGlobalFrame '
      'round-trips through editingGlobalFrame, and the storyboard playhead '
      'is the SAME number (one model, both panels)', () {
    final (s, first, second, aEnd) = gappedSession();
    s.selectCut(first);

    for (final global in [0, aEnd - 1, aEnd, aEnd + 3, aEnd + 4, aEnd + 9]) {
      s.selectGlobalFrame(global);
      expect(s.editingGlobalFrame, global, reason: 'round trip at $global');
      expect(
        storyboardPlayheadFrame(s),
        global,
        reason: 'the storyboard reads the same axis at $global',
      );
    }
    // Ownership: gap frames select NO cut (UI-R9 #3); cut-b starts at
    // aEnd+4.
    s.selectGlobalFrame(aEnd + 2);
    expect(s.activeCutId, isNull);
    s.selectGlobalFrame(aEnd + 4);
    expect(s.activeCutId, second);

    // Territory clamp: a stale over-end local never addresses cut-b.
    s.selectCut(first);
    expect(
      s.trackFrameAxis().clampedGlobalOf(first, aEnd + 400),
      aEnd + 3,
      reason: 'mid-track territory ends at the gap\'s last frame',
    );
  });

  testWidgets('a playback seek lands IN the gap: background frame, no snap', (
    tester,
  ) async {
    final (s, first, _, aEnd) = gappedSession();
    addTearDown(s.dispose);
    s.selectCut(first);

    s.playback.play(scope: PlaybackScope.allCuts);
    seekStoryboardGlobalFrame(s, aEnd + 1);

    expect(s.playback.globalFrameIndexListenable.value, aEnd + 1);
    expect(s.playback.position, isNull, reason: 'gap frames resolve to null');
    // The gap belongs to no cut — the editing selection stays put.
    expect(s.activeCutId, first);
    s.playback.stop();
    // Drain the prerender scheduler's zero-delay warming loop.
    await tester.pumpAndSettle();
  });

  testWidgets('the storyboard playhead keeps MOVING through gaps during '
      'all-cuts playback (R10-⑤)', (tester) async {
    final (s, first, _, aEnd) = gappedSession();
    addTearDown(s.dispose);
    s.selectCut(first);
    s.selectFrameIndex(0);

    s.playback.play(scope: PlaybackScope.allCuts);
    // Inside cut-a: the mapped position and the global agree.
    seekStoryboardGlobalFrame(s, 1);
    expect(storyboardPlayheadFrame(s), 1);

    // IN the gap: the ruler playhead reads the playback clock's global
    // frame instead of freezing on the stale editing playhead.
    seekStoryboardGlobalFrame(s, aEnd + 2);
    expect(s.playback.position, isNull);
    expect(storyboardPlayheadFrame(s), aEnd + 2);

    s.playback.stop();
    await tester.pumpAndSettle();
  });
}
