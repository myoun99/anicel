import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_cut_helpers.dart';
import 'package:anicel/src/controllers/default_layer_helpers.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer_section_defaults.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// Track selection is FIRST-CLASS session state, not a derivation of the
/// active cut. One track can never tell the two models apart — both answer
/// "the only track" — so these drive TWO tracks, where the old derivation
/// (hunt the active cut's owner, else fall back to `tracks.first`) gives a
/// visibly different answer the moment the playhead parks in a gap.
void main() {
  Track trackWith({
    required String trackId,
    required String cutId,
    required int layerSequence,
    int leadingGapFrames = 0,
  }) {
    final id = TrackId(trackId);
    final cut = createDefaultCut(
      cutId: CutId(cutId),
      name: cutId,
      layerId: defaultLayerIdForSequence(layerSequence),
    );
    return Track(
      id: id,
      name: trackId,
      cuts: [cut.copyWith(leadingGapFrames: leadingGapFrames)],
      seLayers: [
        createTrackSeLayer(trackId: id, slot: 1),
        createTrackSeLayer(trackId: id, slot: 2),
      ],
    );
  }

  Project twoTrackProject() => Project(
    id: const ProjectId('two-track-project'),
    name: 'Two tracks',
    createdAt: DateTime.utc(2026, 7, 25),
    tracks: [
      trackWith(trackId: 'track-a', cutId: 'cut-a', layerSequence: 1),
      // A leading gap gives track B a real gap address at frame 0 — the
      // place the old derivation had nothing to answer with.
      trackWith(
        trackId: 'track-b',
        cutId: 'cut-b',
        layerSequence: 2,
        leadingGapFrames: 4,
      ),
    ],
  );

  EditorSessionManager sessionForTwoTracks() {
    final session = EditorSessionManager(initialProject: twoTrackProject());
    addTearDown(session.dispose);
    return session;
  }

  test('a fresh session selects the track holding the default active cut', () {
    final session = sessionForTwoTracks();

    expect(session.activeCutId, const CutId('cut-a'));
    expect(session.selectedTrackId, const TrackId('track-a'));
  });

  test('selecting a cut selects its track', () {
    final session = sessionForTwoTracks();

    session.selectCut(const CutId('cut-b'));

    expect(session.selectedTrackId, const TrackId('track-b'));
  });

  test('the selected track survives the playhead parking in a gap', () {
    final session = sessionForTwoTracks();
    session.selectCut(const CutId('cut-b'));

    // Frame 0 is inside track B's leading gap: the park drops the active
    // cut entirely (UI-R9 #3).
    session.selectGlobalFrame(0);

    expect(session.activeCutId, isNull);
    // The old derivation answered `tracks.first` here — track A — because
    // there was no active cut left to hunt through.
    expect(session.selectedTrackId, const TrackId('track-b'));
  });

  test('tapping a track with a gap under the playhead PARKS there — the '
      'row pick lands its current index even with no cut to take (user '
      '2026-07-29, superseding UI-R18 #6\'s no-op)', () {
    final session = sessionForTwoTracks();

    // The playhead sits at global frame 0, which is track B's LEADING GAP.
    session.selectTrackCutAtPlayhead(const TrackId('track-b'));

    expect(session.activeCutId, isNull, reason: 'the gap releases the cut');
    expect(session.gapParkedGlobalFrame, 0);
    expect(session.selectedTrackId, const TrackId('track-b'));
  });

  test('tapping a track takes the cut under the playhead when there is one', () {
    final session = sessionForTwoTracks();
    // Park at global frame 5, which track B covers (its cut runs from 4).
    session.selectCut(const CutId('cut-b'));
    session.selectFrameIndex(1);
    session.selectTrackCutAtPlayhead(const TrackId('track-a'));

    expect(session.activeCutId, const CutId('cut-a'));
    expect(session.selectedTrackId, const TrackId('track-a'));
  });

  test('the track-global frame axis follows the selected track', () {
    final session = sessionForTwoTracks();
    session.selectCut(const CutId('cut-b'));

    final axis = session.trackFrameAxis();

    expect(axis.entryFor(const CutId('cut-b')), isNotNull);
    expect(axis.entryFor(const CutId('cut-a')), isNull);
    // Track B's cut starts after its leading gap, on its OWN axis.
    expect(axis.entryFor(const CutId('cut-b'))!.startFrame, 4);
  });
}
