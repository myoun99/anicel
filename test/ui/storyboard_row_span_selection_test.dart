import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/services/editing/default_layer_helpers.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_section_defaults.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// The storyboard rail's range selection reaches ACROSS rows, the way the
/// timeline's does (feedback #14): the V row and the track's S rows are
/// rows of ONE track-axis selection, so a drag that starts on one and ends
/// on another covers both.
///
/// The rows a drag covers are the ones the PANEL hands over, sliced off
/// the rows it draws in the order it draws them — the S rows top-down
/// (highest slot first), then the cut row at the BOTTOM — so these pins
/// hand them as a sweep would. ↩️The session walked a list of its own by
/// a head address, and before that by a row delta: leading with the cut
/// row, it inverted every cross-row drag on screen (the real-device
/// "row-span select does nothing" report), and it could name no lane.
void main() {
  EditorSessionManager sessionWithSound() {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    // A sound on the first SE row, covering the first 10 frames.
    final seRow = session.activeTrack.seLayers.first;
    session.repository.replaceLayer(
      layer: seRow.copyWith(
        frames: [
          Frame(id: const FrameId('se-cel'), duration: 1, strokes: const []),
        ],
        timeline: const {
          0: TimelineExposure.drawing(FrameId('se-cel'), length: 10),
        },
      ),
    );
    return session;
  }

  test('a V-row drag with no row reach selects that row alone', () {
    final session = sessionWithSound();

    session.updateStoryboardCutSelectionByFrame(
      anchorGlobalFrame: 2,
      headGlobalFrame: 6,
    );

    final selection = session.trackFrameRangeSelection.value!;
    expect(selection.anchorRow, TrackRowAddress(session.selectedTrackId));
    expect(selection.spanRows, [TrackRowAddress(session.selectedTrackId)]);
    expect(session.storyboardRows.storyboardSelectedCutIds, isNotEmpty);
  });

  test('reaching UP from the V row picks up the S row above it — slot 0 '
      'sits just over the cut row — and the span snaps against BOTH', () {
    final session = sessionWithSound();
    final trackId = session.selectedTrackId;
    final seId = session.activeTrack.seLayers.first.id;

    session.updateStoryboardCutSelectionByFrame(
      anchorGlobalFrame: 2,
      headGlobalFrame: 6,
      spanRows: [LayerRowAddress(seId), TrackRowAddress(trackId)],
    );

    final selection = session.trackFrameRangeSelection.value!;
    expect(selection.spanRows, [
      LayerRowAddress(seId),
      TrackRowAddress(trackId),
    ]);
    expect(selection.coversRow(TrackRowAddress(trackId)), isTrue);
    expect(selection.coversRow(LayerRowAddress(seId)), isTrue);
    // The cut row expands the range to a whole cut, so the union reaches at
    // least as far as the cut does.
    expect(selection.startFrame, 0);
    expect(selection.endFrameExclusive, session.requireActiveCut.duration);
  });

  test('⑧ the TRANSITION row selects through the same verb — it is a '
      'track-owned rail row, and "is it an SE row" was standing in for that', () {
    final session = sessionWithSound();
    final transitionId = session.activeTrack.transitionLayer.id;

    session.updateTrackRowRangeSelectionByFrame(
      layerId: transitionId,
      anchorGlobalFrame: 2,
      headGlobalFrame: 6,
    );

    final selection = session.trackFrameRangeSelection.value;
    expect(
      selection,
      isNotNull,
      reason:
          'before this the owner lookup asked _trackSeAnywhere, missed, and '
          'returned early — the one row of the rail a drag could not touch',
    );
    expect(selection!.anchorRow, LayerRowAddress(transitionId));
    expect(selection.startFrame, lessThanOrEqualTo(2));
    expect(selection.endFrameExclusive, greaterThan(6));
  });

  test('⑧ and it still reaches ACROSS rows from there, like any other row', () {
    final session = sessionWithSound();
    final trackId = session.selectedTrackId;
    final transitionId = session.activeTrack.transitionLayer.id;

    session.updateTrackRowRangeSelectionByFrame(
      layerId: transitionId,
      anchorGlobalFrame: 3,
      headGlobalFrame: 5,
      spanRows: [
        LayerRowAddress(transitionId),
        for (final se in session.activeTrack.seLayers.reversed)
          LayerRowAddress(se.id),
        TrackRowAddress(trackId),
      ],
    );

    final selection = session.trackFrameRangeSelection.value!;
    expect(selection.anchorRow, LayerRowAddress(transitionId));
    expect(selection.spanRows, contains(TrackRowAddress(trackId)));
  });

  test('a single-row selection leaves `rows` empty, so the common case needs '
      'no special-casing downstream', () {
    final session = sessionWithSound();

    session.updateStoryboardCutSelectionByFrame(
      anchorGlobalFrame: 2,
      headGlobalFrame: 6,
    );

    expect(session.trackFrameRangeSelection.value!.rows, isEmpty);
  });

  test('an anchor on an UNSELECTED track\'s S row states the selection on '
      'that row\'s OWN track — the drag anchors wherever the pointer went '
      'down, not where the track selection happens to be', () {
    const otherTrackId = TrackId('track-b');
    final otherSe = createTrackSeLayer(trackId: otherTrackId, slot: 1);
    final project = Project(
      id: const ProjectId('p-span-two-tracks'),
      name: 'Two tracks',
      createdAt: DateTime.utc(2026, 7, 29),
      tracks: [
        createDefaultTrack(),
        Track(
          id: otherTrackId,
          name: 'V2',
          cuts: [
            createDefaultCut(
              cutId: const CutId('cut-b1'),
              name: '1',
              layerId: defaultLayerIdForSequence(9),
            ),
          ],
          seLayers: [otherSe],
        ),
      ],
    );
    final session = EditorSessionManager(initialProject: project);
    addTearDown(session.dispose);
    expect(session.selectedTrackId, isNot(otherTrackId));
    // A sound on the OTHER track's S row: the snap must read it off the
    // row's own track — the active-track lookup left it snapless.
    session.repository.replaceLayer(
      layer: otherSe.copyWith(
        frames: [
          Frame(id: const FrameId('b-se-cel'), duration: 1, strokes: const []),
        ],
        timeline: const {
          0: TimelineExposure.drawing(FrameId('b-se-cel'), length: 10),
        },
      ),
    );

    session.updateTrackRowRangeSelectionByFrame(
      layerId: otherSe.id,
      anchorGlobalFrame: 2,
      headGlobalFrame: 5,
    );

    var selection = session.trackFrameRangeSelection.value!;
    expect(selection.trackId, otherTrackId);
    expect(selection.startFrame, 0, reason: 'snapped to the sound');
    expect(selection.endFrameExclusive, 10, reason: 'snapped to the sound');

    session.updateTrackRowRangeSelectionByFrame(
      layerId: otherSe.id,
      anchorGlobalFrame: 2,
      headGlobalFrame: 5,
      spanRows: [
        LayerRowAddress(otherSe.id),
        const TrackRowAddress(otherTrackId),
      ],
    );

    selection = session.trackFrameRangeSelection.value!;
    expect(selection.trackId, otherTrackId);
    expect(selection.spanRows, [
      LayerRowAddress(otherSe.id),
      const TrackRowAddress(otherTrackId),
    ]);
  });
}
