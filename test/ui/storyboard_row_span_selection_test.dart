import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_cut_helpers.dart';
import 'package:anicel/src/controllers/default_layer_helpers.dart';
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
/// The rail's row ORDER is what a row delta walks, and it is the VISUAL
/// order — the S rows top-down (highest slot first), then the cut row at
/// the BOTTOM. It used to lead with the cut row, which inverted every
/// cross-row drag on screen: dragging downward from an S row toward the V
/// row walked the list away from it (the real-device "row-span select does
/// nothing" report). Nothing else is on the list, which is why the clamp
/// at either end is the whole of the kind guard: the strip is a cut-owned
/// row on the other axis and simply cannot be reached from here.
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
    expect(session.storyboardSelectedCutIds, isNotEmpty);
  });

  test('reaching UP from the V row picks up the S row above it — slot 0 '
      'sits just over the cut row — and the span snaps against BOTH', () {
    final session = sessionWithSound();
    final trackId = session.selectedTrackId;
    final seId = session.activeTrack.seLayers.first.id;

    session.updateStoryboardCutSelectionByFrame(
      anchorGlobalFrame: 2,
      headGlobalFrame: 6,
      headRowDelta: -1,
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

  test('reaching DOWN from an S row picks up the V row below — the same '
      'rail, the direction the screen actually stacks them', () {
    final session = sessionWithSound();
    final trackId = session.selectedTrackId;
    final seId = session.activeTrack.seLayers.first.id;

    session.updateTrackSeRangeSelectionByFrame(
      layerId: seId,
      anchorGlobalFrame: 3,
      headGlobalFrame: 5,
      headRowDelta: 1,
    );

    final selection = session.trackFrameRangeSelection.value!;
    expect(selection.anchorRow, LayerRowAddress(seId));
    expect(selection.spanRows, [
      LayerRowAddress(seId),
      TrackRowAddress(trackId),
    ]);
  });

  test('a row delta past the rail\'s TOP stops at its first row instead of '
      'reaching off it', () {
    final session = sessionWithSound();
    final track = session.activeTrack;

    session.updateStoryboardCutSelectionByFrame(
      anchorGlobalFrame: 2,
      headGlobalFrame: 6,
      headRowDelta: -99,
    );

    final selection = session.trackFrameRangeSelection.value!;
    expect(
      selection.spanRows.length,
      track.seLayers.length + 1,
      reason: 'every SE row plus the cut row, and nothing beyond',
    );
    expect(selection.spanRows.first, LayerRowAddress(track.seLayers.last.id));
    expect(selection.spanRows.last, TrackRowAddress(track.id));
  });

  test('a row delta below the V row stays on it — the cut row is the '
      'rail\'s bottom, with nothing under it to reach', () {
    final session = sessionWithSound();

    session.updateStoryboardCutSelectionByFrame(
      anchorGlobalFrame: 2,
      headGlobalFrame: 6,
      headRowDelta: 99,
    );

    final selection = session.trackFrameRangeSelection.value!;
    expect(selection.spanRows, [TrackRowAddress(session.selectedTrackId)]);
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

    session.updateTrackSeRangeSelectionByFrame(
      layerId: otherSe.id,
      anchorGlobalFrame: 2,
      headGlobalFrame: 5,
    );

    var selection = session.trackFrameRangeSelection.value!;
    expect(selection.trackId, otherTrackId);
    expect(selection.startFrame, 0, reason: 'snapped to the sound');
    expect(selection.endFrameExclusive, 10, reason: 'snapped to the sound');

    session.updateTrackSeRangeSelectionByFrame(
      layerId: otherSe.id,
      anchorGlobalFrame: 2,
      headGlobalFrame: 5,
      headRowDelta: 1,
    );

    selection = session.trackFrameRangeSelection.value!;
    expect(selection.trackId, otherTrackId);
    expect(selection.spanRows, [
      LayerRowAddress(otherSe.id),
      TrackRowAddress(otherTrackId),
    ]);
  });
}
