import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_cut_helpers.dart';
import 'package:anicel/src/controllers/default_layer_helpers.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer_section_defaults.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// The storyboard's cut range runs through the SAME snap the timeline's
/// cell range uses — cuts are simply the blocks. These drive the frame axis
/// the rule actually speaks, so half-covering a cut has to pull it in whole
/// and a span that only crosses a gap has to select nothing.
void main() {
  const trackId = TrackId('track-a');

  Project projectWithGap() {
    Cut cutAt(String id, int leadingGap, int layerSequence) => createDefaultCut(
      cutId: CutId(id),
      name: id,
      layerId: defaultLayerIdForSequence(layerSequence),
    ).copyWith(leadingGapFrames: leadingGap);

    return Project(
      id: const ProjectId('cut-range-project'),
      name: 'Cut range',
      createdAt: DateTime.utc(2026, 7, 25),
      tracks: [
        Track(
          id: trackId,
          name: 'A',
          cuts: [
            cutAt('cut-1', 0, 1),
            // A five-frame gap sits between cut 1 and cut 2.
            cutAt('cut-2', 5, 2),
            cutAt('cut-3', 0, 3),
          ],
          seLayers: [
            createTrackSeLayer(trackId: trackId, slot: 1),
            createTrackSeLayer(trackId: trackId, slot: 2),
          ],
        ),
      ],
    );
  }

  EditorSessionManager sessionWithGap() {
    final session = EditorSessionManager(initialProject: projectWithGap());
    addTearDown(session.dispose);
    return session;
  }

  test('a drag from inside one cut to inside another takes both whole', () {
    final session = sessionWithGap();
    final axis = session.trackFrameAxis();
    final first = axis.entryFor(const CutId('cut-1'))!;
    final second = axis.entryFor(const CutId('cut-2'))!;

    session.updateStoryboardCutSelectionByFrame(
      anchorGlobalFrame: first.startFrame + 1,
      headGlobalFrame: second.startFrame + 1,
    );

    expect(session.storyboardSelectedCutIds, const [
      CutId('cut-1'),
      CutId('cut-2'),
    ]);
  });

  test('a span that only crosses a gap still SELECTS — the cut row is a '
      'frame-block row, and empty cells select on every one of them', () {
    final session = sessionWithGap();
    final axis = session.trackFrameAxis();
    final first = axis.entryFor(const CutId('cut-1'))!;
    final second = axis.entryFor(const CutId('cut-2'))!;

    session.updateStoryboardCutSelectionByFrame(
      anchorGlobalFrame: first.endFrame,
      headGlobalFrame: second.startFrame - 1,
    );

    final selection = session.trackFrameRangeSelection.value!;
    expect(selection.startFrame, first.endFrame);
    expect(selection.endFrameExclusive, second.startFrame);
    // It covers no CUTS, so the verbs that act on cuts find nothing — the
    // ordinary meaning of an empty selection.
    expect(session.storyboardSelectedCutIds, isEmpty);
  });

  test('a single frame inside a cut takes that whole cut', () {
    final session = sessionWithGap();
    final axis = session.trackFrameAxis();
    final third = axis.entryFor(const CutId('cut-3'))!;

    session.updateStoryboardCutSelectionByFrame(
      anchorGlobalFrame: third.startFrame + 2,
      headGlobalFrame: third.startFrame + 2,
    );

    expect(session.storyboardSelectedCutIds, const [CutId('cut-3')]);
  });

  test('a sweep across every cut paints the whole run', () {
    final session = sessionWithGap();
    final axis = session.trackFrameAxis();

    session.updateStoryboardCutSelectionByFrame(
      trackId: trackId,
      anchorGlobalFrame: axis.entryFor(const CutId('cut-1'))!.startFrame,
      headGlobalFrame: axis.entryFor(const CutId('cut-3'))!.startFrame,
    );

    expect(session.storyboardSelectedCutIds, const [
      CutId('cut-1'),
      CutId('cut-2'),
      CutId('cut-3'),
    ]);
  });

  test('a backwards drag orders the run the same way', () {
    final session = sessionWithGap();
    final axis = session.trackFrameAxis();

    session.updateStoryboardCutSelectionByFrame(
      trackId: trackId,
      anchorGlobalFrame: axis.entryFor(const CutId('cut-3'))!.startFrame,
      headGlobalFrame: axis.entryFor(const CutId('cut-2'))!.startFrame,
    );

    expect(session.storyboardSelectedCutIds, const [
      CutId('cut-2'),
      CutId('cut-3'),
    ]);
  });

  group('the cut row is a frame-axis row', () {
    test('the selection IS a frame range on the track axis — the cuts are '
        'what the range covers, not a list of their own', () {
      final session = sessionWithGap();
      final axis = session.trackFrameAxis();
      final second = axis.entryFor(const CutId('cut-2'))!;

      session.updateStoryboardCutSelectionByFrame(
        trackId: trackId,
        anchorGlobalFrame: second.startFrame + 1,
        headGlobalFrame: second.startFrame + 1,
      );

      final selection = session.trackFrameRangeSelection.value!;
      // The snap expanded one pressed frame to the whole cut block.
      expect(selection.startFrame, second.startFrame);
      expect(selection.endFrameExclusive, second.endFrame);
      expect(selection.anchorRow, const TrackRowAddress(trackId));
      expect(selection.trackId, trackId);
    });

    test('it OUTLIVES a cut switch: the track axis does not belong to any '
        'one cut, unlike the cut-local selection', () {
      final session = sessionWithGap();
      final axis = session.trackFrameAxis();
      final third = axis.entryFor(const CutId('cut-3'))!;
      session.updateStoryboardCutSelectionByFrame(
        trackId: trackId,
        anchorGlobalFrame: third.startFrame,
        headGlobalFrame: third.startFrame,
      );

      session.selectCut(const CutId('cut-1'));

      expect(session.storyboardSelectedCutIds, const [CutId('cut-3')]);
    });

    test(
      'starting a CUT-LOCAL selection clears it: two axes, one highlight',
      () {
        final session = sessionWithGap();
        final axis = session.trackFrameAxis();
        final first = axis.entryFor(const CutId('cut-1'))!;
        session.updateStoryboardCutSelectionByFrame(
          trackId: trackId,
          anchorGlobalFrame: first.startFrame,
          headGlobalFrame: first.startFrame,
        );

        session.updateFrameRangeSelectionDrag(
          layerId: session.activeLayerId!,
          anchorIndex: 0,
          headIndex: 0,
        );

        expect(session.trackFrameRangeSelection.value, isNull);
        expect(session.storyboardSelectedCutIds, isEmpty);
      },
    );

    test('and starting a TRACK-axis one clears the cut-local selection', () {
      final session = sessionWithGap();
      session.updateFrameRangeSelectionDrag(
        layerId: session.activeLayerId!,
        anchorIndex: 0,
        headIndex: 0,
      );
      expect(session.frameRangeSelection.value, isNotNull);
      final axis = session.trackFrameAxis();
      final first = axis.entryFor(const CutId('cut-1'))!;

      session.updateStoryboardCutSelectionByFrame(
        trackId: trackId,
        anchorGlobalFrame: first.startFrame,
        headGlobalFrame: first.startFrame,
      );

      expect(session.frameRangeSelection.value, isNull);
      expect(session.storyboardSelectedCutIds, const [CutId('cut-1')]);
    });
  });
}
