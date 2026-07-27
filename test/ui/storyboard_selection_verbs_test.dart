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
import 'package:quick_animaker_v2/src/models/timeline_row_address.dart';
import 'package:quick_animaker_v2/src/models/track.dart';
import 'package:quick_animaker_v2/src/models/track_id.dart';
import 'package:quick_animaker_v2/src/ui/editor_session_manager.dart';

/// What the storyboard's selection can DO. Every verb here is the
/// timeline's, aimed at the other axis: the rows differ, the grammar does
/// not.
const _trackId = TrackId('verbs-track');
const _seLayerId = LayerId('verbs-se-1');
const _seLayer2Id = LayerId('verbs-se-2');

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
        // An empty sibling row, so a MOVE has somewhere of its own kind
        // to land.
        Layer(
          id: _seLayer2Id,
          name: 'S2',
          kind: LayerKind.se,
          frames: const [],
          timeline: const {},
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

  /// The track's GLOBAL SE layers as the repository holds them now.
  Layer seLayerOf(EditorSessionManager session) =>
      session.repository.requireProject().tracks.single.seLayers.first;

  Layer seLayer2Of(EditorSessionManager session) =>
      session.repository.requireProject().tracks.single.seLayers.last;

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
      expect(session.canPushFrames(), isTrue);

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
      expect(session.framePullSlack(), 4);
      session.pullFrames(9);

      expect(seLayerOf(session).timeline.keys, [2, 5]);
    });

    test('with no storyboard selection the timeline scope is untouched', () {
      final session = sessionFor();

      // The active layer is cut 1's cel, which carries nothing — the frame
      // scope still resolves to it, not to any S row.
      expect(session.canPushFrames(), isTrue);
      session.pushFrames(2);

      expect(seLayerOf(session).timeline.keys, [2, 9]);
    });
  });

  group('Range MOVE on an S row', () {
    test('slides the selected sounds along the GLOBAL axis, one undo', () {
      final session = sessionFor();
      session.updateTrackSeRangeSelectionByFrame(
        layerId: _seLayerId,
        anchorGlobalFrame: 3,
        headGlobalFrame: 3,
      );

      expect(session.beginTrackRangeMoveDrag(_seLayerId), isTrue);
      session.updateFrameRangeMoveDrag(frameDelta: 2);
      session.endFrameRangeMoveDrag();

      // ONLY the selected sound moved — a shove would have carried the
      // other one too.
      expect(seLayerOf(session).timeline.keys, [4, 9]);

      session.undo();
      expect(seLayerOf(session).timeline.keys, [2, 9]);
    });

    test('the selection FOLLOWS the landing, and stays on the track axis', () {
      final session = sessionFor();
      session.updateTrackSeRangeSelectionByFrame(
        layerId: _seLayerId,
        anchorGlobalFrame: 3,
        headGlobalFrame: 3,
      );

      session.beginTrackRangeMoveDrag(_seLayerId);
      session.updateFrameRangeMoveDrag(frameDelta: 2);
      session.endFrameRangeMoveDrag();

      final landed = session.trackFrameRangeSelection.value!;
      expect(landed.startFrame, 4);
      expect(landed.endFrameExclusive, 7);
      expect(landed.anchorRow, const LayerRowAddress(_seLayerId));
      // The cut-local selection was never touched by a track-axis drag.
      expect(session.frameRangeSelection.value, isNull);
    });

    test('a slide stops at CONTACT rather than pushing its neighbour — the '
        'timeline rule, on the track axis', () {
      final session = sessionFor();
      session.updateTrackSeRangeSelectionByFrame(
        layerId: _seLayerId,
        anchorGlobalFrame: 3,
        headGlobalFrame: 3,
      );

      session.beginTrackRangeMoveDrag(_seLayerId);
      // +3 keeps [2,5) on its own side of the neighbour's midpoint, so it
      // re-times inside its free space and the sound at 9 holds still.
      session.updateFrameRangeMoveDrag(frameDelta: 3);
      session.endFrameRangeMoveDrag();

      expect(seLayerOf(session).timeline.keys, [5, 9]);
      expect(seLayerOf(session).timeline[5]!.frameId, const FrameId('se-one'));
    });

    test('reaching past the neighbour\'s midpoint REORDERS the sounds', () {
      final session = sessionFor();
      session.updateTrackSeRangeSelectionByFrame(
        layerId: _seLayerId,
        anchorGlobalFrame: 3,
        headGlobalFrame: 3,
      );

      session.beginTrackRangeMoveDrag(_seLayerId);
      // +7 drives [2,5) level with [9,12)'s midpoint: the two swap places,
      // each carrying the lead-in it owns, so the row's total span holds.
      session.updateFrameRangeMoveDrag(frameDelta: 7);
      session.endFrameRangeMoveDrag();

      expect(seLayerOf(session).timeline.keys, [4, 9]);
      expect(seLayerOf(session).timeline[4]!.frameId, const FrameId('se-two'));
      expect(seLayerOf(session).timeline[9]!.frameId, const FrameId('se-one'));
    });

    test('lands on a SIBLING S row: the timeline row-change grammar, on '
        'the track axis', () {
      final session = sessionFor();
      session.updateTrackSeRangeSelectionByFrame(
        layerId: _seLayerId,
        anchorGlobalFrame: 3,
        headGlobalFrame: 3,
      );

      session.beginTrackRangeMoveDrag(_seLayerId);
      session.updateFrameRangeMoveDrag(
        frameDelta: 0,
        targetLayerId: _seLayer2Id,
      );
      session.endFrameRangeMoveDrag();

      // The sound left S1 for S2 at the SAME global frames — proof the
      // row change read the span in the track axis (a cut-local reading
      // would have offset it by the cut's start).
      expect(seLayerOf(session).timeline.keys, [9]);
      expect(seLayer2Of(session).timeline.keys, [2]);
    });

    test('the selection follows onto the row it landed on', () {
      final session = sessionFor();
      session.updateTrackSeRangeSelectionByFrame(
        layerId: _seLayerId,
        anchorGlobalFrame: 3,
        headGlobalFrame: 3,
      );

      session.beginTrackRangeMoveDrag(_seLayerId);
      session.updateFrameRangeMoveDrag(
        frameDelta: 0,
        targetLayerId: _seLayer2Id,
      );
      session.endFrameRangeMoveDrag();

      expect(
        session.trackFrameRangeSelection.value!.anchorRow,
        const LayerRowAddress(_seLayer2Id),
      );
    });

    test('a row change carries the frame delta with it', () {
      final session = sessionFor();
      session.updateTrackSeRangeSelectionByFrame(
        layerId: _seLayerId,
        anchorGlobalFrame: 3,
        headGlobalFrame: 3,
      );

      session.beginTrackRangeMoveDrag(_seLayerId);
      session.updateFrameRangeMoveDrag(
        frameDelta: 4,
        targetLayerId: _seLayer2Id,
      );
      session.endFrameRangeMoveDrag();

      expect(seLayer2Of(session).timeline.keys, [6]);
    });

    test('cancelling puts the selection back where it started', () {
      final session = sessionFor();
      session.updateTrackSeRangeSelectionByFrame(
        layerId: _seLayerId,
        anchorGlobalFrame: 3,
        headGlobalFrame: 3,
      );

      session.beginTrackRangeMoveDrag(_seLayerId);
      session.updateFrameRangeMoveDrag(frameDelta: 2);
      session.cancelFrameRangeMoveDrag();

      expect(seLayerOf(session).timeline.keys, [2, 9]);
      expect(session.trackFrameRangeSelection.value!.startFrame, 2);
    });

    test('a track-axis drag leaves the cut-local machine unarmed: the next '
        'timeline move publishes to its own selection', () {
      final session = sessionFor();
      session.updateTrackSeRangeSelectionByFrame(
        layerId: _seLayerId,
        anchorGlobalFrame: 3,
        headGlobalFrame: 3,
      );
      session.beginTrackRangeMoveDrag(_seLayerId);
      session.endFrameRangeMoveDrag();

      // The SAME row, selected the other way: the timeline's cut-local
      // view of it (cut 1 starts at 0, so the sound at 2 is local 2). The
      // axis has to be re-stated by THIS begin, not inherited.
      session.updateFrameRangeSelectionDrag(
        layerId: _seLayerId,
        anchorIndex: 2,
        headIndex: 2,
      );
      expect(session.beginFrameRangeMoveDrag(), isTrue);
      session.updateFrameRangeMoveDrag(frameDelta: 1);
      session.cancelFrameRangeMoveDrag();

      // The restore landed in the CUT-LOCAL object, not the track one.
      expect(session.frameRangeSelection.value, isNotNull);
      expect(session.trackFrameRangeSelection.value, isNull);
    });
  });

  group('ONE push/pull aimed at what is selected', () {
    test('a CUT selection shoves cuts', () {
      final session = sessionFor();
      session.updateStoryboardCutSelectionByFrame(
        trackId: _trackId,
        anchorGlobalFrame: 9,
        headGlobalFrame: 9,
      );

      expect(session.canPushBlocks(), isTrue);
      session.pushBlocks(3);

      // Cut 2's leading gap carries its whole run (design D); the sounds
      // are on another axis and stay put.
      expect(
        session.repository
            .requireProject()
            .tracks
            .single
            .cuts
            .last
            .leadingGapFrames,
        3,
      );
      expect(seLayerOf(session).timeline.keys, [2, 9]);
    });

    test('an S-ROW selection shoves sounds instead', () {
      final session = sessionFor();
      session.updateTrackSeRangeSelectionByFrame(
        layerId: _seLayerId,
        anchorGlobalFrame: 3,
        headGlobalFrame: 3,
      );

      session.pushBlocks(2);

      expect(seLayerOf(session).timeline.keys, [4, 11]);
      expect(
        session.repository
            .requireProject()
            .tracks
            .single
            .cuts
            .last
            .leadingGapFrames,
        0,
      );
    });

    test('with NOTHING selected the asking rail decides: a cut row shoves '
        'cuts, an S row shoves sounds', () {
      final cutRowSession = sessionFor();
      cutRowSession.pushBlocks(
        2,
        currentRow: cutRowSession.selectedRow, // the V row by default
      );
      expect(
        cutRowSession.repository
            .requireProject()
            .tracks
            .single
            .cuts
            .first
            .leadingGapFrames,
        2,
      );

      final seRowSession = sessionFor();
      seRowSession.selectRow(const LayerRowAddress(_seLayerId));
      seRowSession.pushBlocks(2, currentRow: seRowSession.selectedRow);
      expect(seLayerOf(seRowSession).timeline.keys, [4, 11]);
    });
  });
}
