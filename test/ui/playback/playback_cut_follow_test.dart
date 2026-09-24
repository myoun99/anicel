import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/playback/canvas_playback_controller.dart';

/// ③ Premiere-style playback follow: while playing across cut boundaries
/// the ACTIVE cut tracks the playing cut (pure selection state — the undo
/// stack never sees it) and stays on that cut when playback stops.
void main() {
  (EditorSessionManager, CutId, CutId) twoCutSession() {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    s.cutVerbs.createCut();
    final track = s.repository.requireProject().tracks.first;
    // createCut selects the new cut; playback starts from the first one.
    s.selectCut(track.cuts[0].id);
    return (s, track.cuts[0].id, track.cuts[1].id);
  }

  testWidgets('crossing a cut boundary switches the active cut QUIETLY and '
      'never touches undo — the stop notify catches the UI up', (tester) async {
    final (s, first, second) = twoCutSession();
    addTearDown(s.dispose);
    final firstDuration = s.cutById(first)!.duration;
    var notifies = 0;
    s.addListener(() => notifies += 1);

    s.playbackRig.playback.play(scope: PlaybackScope.allCuts);
    expect(s.activeCutId, first);
    notifies = 0;

    // Forward across the boundary → the second cut becomes active and the
    // playhead lands on the playing local frame. NO session notify: a
    // boundary tick must not rebuild the visible panels mid-playback
    // (R12-B — that stutter was the cut-transition lag).
    s.playbackRig.playback.seekToGlobalFrame(firstDuration + 2);
    expect(s.activeCutId, second);
    expect(s.currentFrameIndex, 2);
    expect(notifies, 0, reason: 'the mid-playback follow is quiet');

    // Backward across the boundary follows too (loop wrap, ruler seeks).
    s.playbackRig.playback.seekToGlobalFrame(0);
    expect(s.activeCutId, first);
    expect(notifies, 0);

    // Stopping stays on the cut playback reached (Premiere behavior) and
    // fires the ONE notify that catches every activeCut consumer up.
    s.playbackRig.playback.seekToGlobalFrame(firstDuration + 3);
    s.playbackRig.playback.stop();
    expect(s.activeCutId, second);
    expect(s.currentFrameIndex, 3);
    expect(notifies, greaterThan(0), reason: 'stop catches the UI up');

    // The whole ride left history untouched: the next undo is still the
    // fixture's createCut, nothing selection-shaped sits on top of it. It
    // left the playhead on frame 0 of the new cut, and the ride did not —
    // so the first press walks back there (I-41) and the second takes it.
    s.undo();
    expect(s.activeCutId, second);
    expect(s.currentFrameIndex, 0, reason: 'a walk, not a step');
    s.undo();
    expect(s.repository.requireProject().tracks.first.cuts, hasLength(1));
    expect(s.canUndo, isFalse);

    // Drain the prerender scheduler's zero-delay warming loop.
    await tester.pumpAndSettle();
  });

  testWidgets('single-cut playback never follows anywhere', (tester) async {
    final (s, first, _) = twoCutSession();
    addTearDown(s.dispose);

    s.playbackRig.playback.play(scope: PlaybackScope.activeCut);
    s.playbackRig.playback.seekToGlobalFrame(2);
    expect(s.activeCutId, first);

    s.playbackRig.playback.stop();
    expect(s.activeCutId, first);
    expect(s.currentFrameIndex, 2);

    await tester.pumpAndSettle();
  });
}
