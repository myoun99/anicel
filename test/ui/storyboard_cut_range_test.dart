import 'package:flutter_test/flutter_test.dart';
import 'package:quick_animaker_v2/src/controllers/default_cut_helpers.dart';
import 'package:quick_animaker_v2/src/controllers/default_layer_helpers.dart';
import 'package:quick_animaker_v2/src/models/cut.dart';
import 'package:quick_animaker_v2/src/models/cut_id.dart';
import 'package:quick_animaker_v2/src/models/layer_section_defaults.dart';
import 'package:quick_animaker_v2/src/models/project.dart';
import 'package:quick_animaker_v2/src/models/project_id.dart';
import 'package:quick_animaker_v2/src/models/track.dart';
import 'package:quick_animaker_v2/src/models/track_id.dart';
import 'package:quick_animaker_v2/src/ui/editor_session_manager.dart';

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

    expect(session.storyboardCutSelection.value, const [
      CutId('cut-1'),
      CutId('cut-2'),
    ]);
  });

  test('a span that only crosses a gap selects nothing', () {
    final session = sessionWithGap();
    final axis = session.trackFrameAxis();
    final first = axis.entryFor(const CutId('cut-1'))!;
    final second = axis.entryFor(const CutId('cut-2'))!;

    session.updateStoryboardCutSelectionByFrame(
      anchorGlobalFrame: first.endFrame,
      headGlobalFrame: second.startFrame - 1,
    );

    expect(session.storyboardCutSelection.value, isNull);
  });

  test('a single frame inside a cut takes that whole cut', () {
    final session = sessionWithGap();
    final axis = session.trackFrameAxis();
    final third = axis.entryFor(const CutId('cut-3'))!;

    session.updateStoryboardCutSelectionByFrame(
      anchorGlobalFrame: third.startFrame + 2,
      headGlobalFrame: third.startFrame + 2,
    );

    expect(session.storyboardCutSelection.value, const [CutId('cut-3')]);
  });

  test('the ordinal entry point still paints the contiguous run', () {
    final session = sessionWithGap();

    session.updateStoryboardCutSelectionDrag(
      trackId: trackId,
      anchorCutIndex: 0,
      headCutIndex: 2,
    );

    expect(session.storyboardCutSelection.value, const [
      CutId('cut-1'),
      CutId('cut-2'),
      CutId('cut-3'),
    ]);
  });

  test('the ordinal entry point orders a backwards drag the same way', () {
    final session = sessionWithGap();

    session.updateStoryboardCutSelectionDrag(
      trackId: trackId,
      anchorCutIndex: 2,
      headCutIndex: 1,
    );

    expect(session.storyboardCutSelection.value, const [
      CutId('cut-2'),
      CutId('cut-3'),
    ]);
  });
}
