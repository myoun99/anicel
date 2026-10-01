import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/services/editing/default_layer_helpers.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// Standing on a track with NO cut, the selected track's axis is every
/// track's — the answer the whole-layout axis gave before the track
/// selection became its own state (#723, 2026-07-26), kept when the track
/// axes moved beside the layout they narrow (the session-state audit's
/// twenty-second family, 2026-09-29). Pinned then: nothing measured it,
/// and a mutant that dropped it survived every suite.
void main() {
  const a = TrackId('track-a');
  const b = TrackId('track-b');
  const onA = CutId('a-1');

  EditorSessionManager standingOnTheEmptyTrack() {
    final session = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('one-empty-track'),
        name: 'One empty track',
        createdAt: DateTime.utc(2026, 9, 29),
        tracks: [
          Track(
            id: a,
            name: 'A',
            cuts: [
              createDefaultCut(
                cutId: onA,
                name: 'a-1',
                layerId: defaultLayerIdForSequence(1),
              ),
            ],
          ),
          Track(id: b, name: 'B', cuts: const []),
        ],
      ),
    );
    addTearDown(session.dispose);
    session.selectTrackCutAtPlayhead(b);
    expect(session.activeCutId, isNull, reason: '⛔premise: parked on B');
    expect(session.selectedTrackId, b, reason: '⛔premise: B is selected');
    return session;
  }

  test('the axis of a track with no cut is every track\'s', () {
    final s = standingOnTheEmptyTrack();

    expect([for (final entry in s.trackFrameAxis().entries) entry.cutId], [
      onA,
    ]);
  });

  test('and it follows an edit of the tracks it reads', () {
    final s = standingOnTheEmptyTrack();
    final start = s.trackFrameAxis().entries.single.startFrame;

    s.repository.updateCutDuration(cutId: onA, duration: 48);

    expect(s.trackFrameAxis().entries.single.endFrame, start + 48);
  });
}
