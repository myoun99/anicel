import 'package:flutter_test/flutter_test.dart';
import 'package:quick_animaker_v2/src/controllers/default_project_helpers.dart';
import 'package:quick_animaker_v2/src/models/frame.dart';
import 'package:quick_animaker_v2/src/models/frame_id.dart';
import 'package:quick_animaker_v2/src/models/timeline_exposure.dart';
import 'package:quick_animaker_v2/src/models/timeline_row_address.dart';
import 'package:quick_animaker_v2/src/ui/editor_session_manager.dart';

/// The storyboard rail's range selection reaches ACROSS rows, the way the
/// timeline's does (feedback #14): the V row and the track's S rows are
/// rows of ONE track-axis selection, so a drag that starts on one and ends
/// on another covers both.
///
/// The rail's row ORDER is what a row delta walks — cut row first, then the
/// track's SE rows. Nothing else is on it, which is why the clamp at either
/// end is the whole of the kind guard: the strip is a cut-owned row on the
/// other axis and simply cannot be reached from here.
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

  test('reaching DOWN from the V row picks up the S row below it, and the '
      'span snaps against BOTH', () {
    final session = sessionWithSound();
    final trackId = session.selectedTrackId;
    final seId = session.activeTrack.seLayers.first.id;

    session.updateStoryboardCutSelectionByFrame(
      anchorGlobalFrame: 2,
      headGlobalFrame: 6,
      headRowDelta: 1,
    );

    final selection = session.trackFrameRangeSelection.value!;
    expect(selection.spanRows, [
      TrackRowAddress(trackId),
      LayerRowAddress(seId),
    ]);
    expect(selection.coversRow(TrackRowAddress(trackId)), isTrue);
    expect(selection.coversRow(LayerRowAddress(seId)), isTrue);
    // The cut row expands the range to a whole cut, so the union reaches at
    // least as far as the cut does.
    expect(selection.startFrame, 0);
    expect(selection.endFrameExclusive, session.requireActiveCut.duration);
  });

  test('reaching UP from an S row picks up the V row — the same rail, the '
      'other direction', () {
    final session = sessionWithSound();
    final trackId = session.selectedTrackId;
    final seId = session.activeTrack.seLayers.first.id;

    session.updateTrackSeRangeSelectionByFrame(
      layerId: seId,
      anchorGlobalFrame: 3,
      headGlobalFrame: 5,
      headRowDelta: -1,
    );

    final selection = session.trackFrameRangeSelection.value!;
    expect(selection.anchorRow, LayerRowAddress(seId));
    expect(selection.spanRows, [
      TrackRowAddress(trackId),
      LayerRowAddress(seId),
    ]);
  });

  test('a row delta past the rail\'s end stops at the last row instead of '
      'reaching off it', () {
    final session = sessionWithSound();

    session.updateStoryboardCutSelectionByFrame(
      anchorGlobalFrame: 2,
      headGlobalFrame: 6,
      headRowDelta: 99,
    );

    final selection = session.trackFrameRangeSelection.value!;
    final seRows = session.activeTrack.seLayers.length;
    expect(
      selection.spanRows.length,
      seRows + 1,
      reason: 'the cut row plus every SE row, and nothing beyond',
    );
    expect(selection.spanRows.first, TrackRowAddress(session.selectedTrackId));
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
}
