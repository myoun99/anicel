import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/track_se_display.dart';

/// F-113: the session hands both grids, per track-SE row that spills into
/// the active cut, how far into that sound the cut starts — the one window
/// fact the `~` marks, the start grip and now the waveforms all read.
///
/// The collaborator that answers it — named so `tool/mutation_run.dart` runs
/// this file for it.
TrackSeDisplay trackSeOf(EditorSessionManager session) => session.trackSe;

void main() {
  test('🚨a sound entered in cut 1 that runs into cut 2 is that far along '
      'when cut 2 starts', () {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    final se = session.activeTrack.seLayers.first;
    session.selectLayer(se.id);
    session.selectFrameIndex(2);
    // A block from cut 1's frame 2 running as long as cut 1 itself — past
    // its end, into the next cut.
    session.seEntries.createSeEntryAtCurrentFrame(
      name: '',
      lengthFrames: session.requireActiveCut.duration,
    );
    expect(
      trackSeOf(session).trackSeSpillInLeadFrames,
      isEmpty,
      reason: 'in cut 1 the block starts inside the cut',
    );

    session.cutVerbs.createCut();
    final cut2Start = session.activeCutGlobalStartFrame;
    expect(
      trackSeOf(session).trackSeSpillInLeadFrames,
      {se.id: cut2Start - 2},
    );
  });
}
