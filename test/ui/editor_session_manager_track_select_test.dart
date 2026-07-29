import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_cut_helpers.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// V-track selection (UI-R18 #6): tapping a V row makes THAT track's cut
/// under the shared global playhead the active cut — the fx/eye subject
/// rule promoted to a selection.
void main() {
  EditorSessionManager twoTrackSession() {
    final project = Project(
      id: const ProjectId('p-two-tracks'),
      name: 'Two Tracks',
      createdAt: DateTime.utc(2026, 7, 18),
      tracks: [
        createDefaultTrack(),
        Track(
          id: const TrackId('track-b'),
          name: 'Track 2',
          cuts: [
            createDefaultCut(
              cutId: const CutId('cut-b1'),
              name: '1',
              layerId: const LayerId('layer-b1'),
            ),
          ],
        ),
      ],
    );
    return EditorSessionManager(initialProject: project);
  }

  test('selecting the other track promotes ITS cut under the playhead and '
      'keeps the global position', () {
    final s = twoTrackSession();
    addTearDown(s.dispose);
    expect(s.activeCutId, const CutId('default-cut-1'));
    s.selectFrameIndex(3);

    s.selectTrackCutAtPlayhead(const TrackId('track-b'));

    expect(s.activeCutId, const CutId('cut-b1'));
    // Both cuts start at global 0: the same global frame is the same
    // local frame.
    expect(s.currentFrameIndex, 3);
  });

  test('selecting the track the active cut already lives on keeps it', () {
    final s = twoTrackSession();
    addTearDown(s.dispose);
    s.selectFrameIndex(2);

    s.selectTrackCutAtPlayhead(const TrackId('default-track'));

    expect(s.activeCutId, const CutId('default-cut-1'));
    expect(s.currentFrameIndex, 2);
  });

  test('a GAP on the tapped track PARKS there — selecting a row makes its '
      'current index the active state, and with no cut to take that state '
      'is the parked stack (user 2026-07-29, superseding the UI-R18 #6 '
      'no-op)', () {
    final s = twoTrackSession();
    addTearDown(s.dispose);
    // Slide track B's only cut right by 4: global 0..3 become its
    // leading gap.
    expect(s.beginCutMoveDrag(const CutId('cut-b1')), isTrue);
    s.updateCutMoveDrag(4);
    s.endCutMoveDrag();
    s.selectFrameIndex(0);

    s.selectTrackCutAtPlayhead(const TrackId('track-b'));

    expect(s.activeCutId, isNull, reason: 'the gap releases the cut');
    expect(s.gapParkedGlobalFrame, 0, reason: 'parked where it stood');
    expect(s.selectedTrackId, const TrackId('track-b'));

    // Past the gap the selection works and re-maps the local frame.
    s.selectGlobalFrame(6);
    s.selectTrackCutAtPlayhead(const TrackId('track-b'));
    expect(s.activeCutId, const CutId('cut-b1'));
    expect(s.currentFrameIndex, 2, reason: 'global 6 - start 4');
  });
}
