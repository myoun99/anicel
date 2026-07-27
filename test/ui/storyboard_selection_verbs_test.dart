import 'package:flutter_test/flutter_test.dart';
import 'package:quick_animaker_v2/src/models/canvas_size.dart';
import 'package:quick_animaker_v2/src/models/cut.dart';
import 'package:quick_animaker_v2/src/models/cut_id.dart';
import 'package:quick_animaker_v2/src/models/frame.dart';
import 'package:quick_animaker_v2/src/models/frame_id.dart';
import 'package:quick_animaker_v2/src/models/layer.dart';
import 'package:quick_animaker_v2/src/models/layer_id.dart';
import 'package:quick_animaker_v2/src/models/layer_kind.dart';
import 'package:quick_animaker_v2/src/models/project.dart';
import 'package:quick_animaker_v2/src/models/project_id.dart';
import 'package:quick_animaker_v2/src/models/timeline_exposure.dart';
import 'package:quick_animaker_v2/src/models/track.dart';
import 'package:quick_animaker_v2/src/models/track_id.dart';
import 'package:quick_animaker_v2/src/ui/editor_session_manager.dart';

/// What the storyboard's selection can DO. Every verb here is the
/// timeline's, aimed at the other axis: the rows differ, the grammar does
/// not.
const _trackId = TrackId('verbs-track');
const _seLayerId = LayerId('verbs-se-1');

Cut _cut(String id, int duration) => Cut(
  id: CutId(id),
  name: id,
  duration: duration,
  canvasSize: const CanvasSize(width: 640, height: 360),
  layers: [
    Layer(
      id: LayerId('$id-cel'),
      name: 'A',
      frames: const [],
      timeline: const {},
    ),
  ],
);

/// Cut 1 covers [0,8), cut 2 covers [8,14). The S row carries a sound in
/// each: [2,5) and [9,12).
Project _project() => Project(
  id: const ProjectId('verbs-project'),
  name: 'Verbs',
  createdAt: DateTime.utc(2026, 7, 27),
  tracks: [
    Track(
      id: _trackId,
      name: 'Video',
      cuts: [_cut('cut-1', 8), _cut('cut-2', 6)],
      seLayers: [
        Layer(
          id: _seLayerId,
          name: 'S1',
          kind: LayerKind.se,
          frames: [
            Frame(
              id: const FrameId('se-one'),
              duration: 3,
              name: 'One!',
              strokes: const [],
            ),
            Frame(
              id: const FrameId('se-two'),
              duration: 3,
              name: 'Two!',
              strokes: const [],
            ),
          ],
          timeline: const {
            2: TimelineExposure.drawing(FrameId('se-one'), length: 3),
            9: TimelineExposure.drawing(FrameId('se-two'), length: 3),
          },
        ),
      ],
    ),
  ],
);

void main() {
  EditorSessionManager sessionFor() {
    final session = EditorSessionManager(initialProject: _project());
    addTearDown(session.dispose);
    return session;
  }

  /// The track's GLOBAL SE layer as the repository holds it now.
  Layer seLayerOf(EditorSessionManager session) =>
      session.repository.requireProject().tracks.single.seLayers.single;

  group('Delete on the storyboard selection', () {
    test('removes the covered blocks of the S row — the timeline block '
        'delete, aimed at the track axis', () {
      final session = sessionFor();
      session.updateTrackSeRangeSelectionByFrame(
        layerId: _seLayerId,
        anchorGlobalFrame: 3,
        headGlobalFrame: 3,
      );

      session.deleteCellAtCurrentFrame();

      // The [2,5) sound is gone; the one in the OTHER cut is untouched —
      // proof the delete ran on the global layer, not on a cut-local clone
      // that could not even name it.
      expect(seLayerOf(session).timeline.keys, [9]);
      expect(session.trackFrameRangeSelection.value, isNull);
    });

    test('reaches a sound in another cut, and takes both when the range '
        'covers both', () {
      final session = sessionFor();
      session.updateTrackSeRangeSelectionByFrame(
        layerId: _seLayerId,
        anchorGlobalFrame: 3,
        headGlobalFrame: 10,
      );

      session.deleteCellAtCurrentFrame();

      expect(seLayerOf(session).timeline, isEmpty);
    });

    test('is undoable as ONE step, like every block delete', () {
      final session = sessionFor();
      session.updateTrackSeRangeSelectionByFrame(
        layerId: _seLayerId,
        anchorGlobalFrame: 3,
        headGlobalFrame: 10,
      );
      session.deleteCellAtCurrentFrame();

      session.undo();

      expect(seLayerOf(session).timeline.keys, [2, 9]);
    });

    test('the CUT row keeps its verb: a cut selection deletes cuts', () {
      final session = sessionFor();
      session.updateStoryboardCutSelectionByFrame(
        trackId: _trackId,
        anchorGlobalFrame: 9,
        headGlobalFrame: 9,
      );

      session.deleteActiveCut();

      expect(
        session.repository.requireProject().tracks.single.cuts.map(
          (cut) => cut.id,
        ),
        [const CutId('cut-1')],
      );
    });
  });

  group('Push / pull on the storyboard selection', () {
    test('shoves the S row on the GLOBAL axis, from the range start', () {
      final session = sessionFor();
      session.updateTrackSeRangeSelectionByFrame(
        layerId: _seLayerId,
        anchorGlobalFrame: 3,
        headGlobalFrame: 3,
      );
      expect(session.canPushFrames, isTrue);

      session.pushFrames(2);

      // Both sounds travel: the shove opens 2 frames at the anchor and
      // everything after keeps its own spacing.
      expect(seLayerOf(session).timeline.keys, [4, 11]);
    });

    test('a global anchor is NOT translated a second time — the bug a '
        'cut-local anchor would have hidden', () {
      final session = sessionFor();
      // Land the playhead in cut 2 so the cut-local translation, if it ran,
      // would move the anchor by the cut's start frame (8) and shove the
      // wrong sound.
      session.selectGlobalFrame(9);
      session.updateTrackSeRangeSelectionByFrame(
        layerId: _seLayerId,
        anchorGlobalFrame: 3,
        headGlobalFrame: 3,
      );

      session.pushFrames(1);

      expect(seLayerOf(session).timeline.keys, [3, 10]);
    });

    test('pull slack is measured on the global layer: it stops where the '
        'first sound would be overrun', () {
      final session = sessionFor();
      session.updateTrackSeRangeSelectionByFrame(
        layerId: _seLayerId,
        anchorGlobalFrame: 6,
        headGlobalFrame: 6,
      );

      // The [9,12) sound sits 4 frames after the anchor's block end (5),
      // so the pull closes that gap and stops.
      expect(session.framePullSlack, 4);
      session.pullFrames(9);

      expect(seLayerOf(session).timeline.keys, [2, 5]);
    });

    test('with no storyboard selection the timeline scope is untouched', () {
      final session = sessionFor();

      // The active layer is cut 1's cel, which carries nothing — the frame
      // scope still resolves to it, not to any S row.
      expect(session.canPushFrames, isTrue);
      session.pushFrames(2);

      expect(seLayerOf(session).timeline.keys, [2, 9]);
    });
  });
}
