import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/playback/frame_demand.dart' show FrameGhosts;
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/playback_cache_budget.dart';

import '../../helpers/draw_on_current_frame.dart';

/// I-22: the green bar asks once per span of one picture, remembering
/// each picture's full signature — so what it remembers must be dropped
/// exactly when the answer can change without the cut changing.
void main() {
  const canvasSize = CanvasSize(width: 8, height: 8);

  /// One cel held across the whole 24 frames, nothing after them.
  EditorSessionManager session() => EditorSessionManager(
    initialProject: Project(
      id: const ProjectId('project'),
      name: 'P',
      createdAt: DateTime.utc(2026),
      tracks: [
        Track(
          id: const TrackId('track'),
          name: 'T',
          cuts: [
            Cut(
              id: const CutId('cut'),
              name: '1',
              duration: 24,
              canvasSize: canvasSize,
              layers: [
                Layer(
                  id: const LayerId('layer'),
                  name: 'A',
                  frames: [
                    Frame(
                      id: const FrameId('frame-a'),
                      duration: 1,
                      strokes: const [],
                    ),
                  ],
                  timeline: {
                    0: const TimelineExposure.drawing(
                      FrameId('frame-a'),
                      length: 24,
                    ),
                  },
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  );

  /// Two rows, each one cel held across the whole 24 frames.
  EditorSessionManager twoRows() => EditorSessionManager(
    initialProject: Project(
      id: const ProjectId('project'),
      name: 'P',
      createdAt: DateTime.utc(2026),
      tracks: [
        Track(
          id: const TrackId('track'),
          name: 'T',
          cuts: [
            Cut(
              id: const CutId('cut'),
              name: '1',
              duration: 24,
              canvasSize: canvasSize,
              layers: [
                for (final row in ['over', 'under'])
                  Layer(
                    id: LayerId(row),
                    name: row,
                    frames: [
                      Frame(id: FrameId(row), duration: 1, strokes: const []),
                    ],
                    timeline: {
                      0: TimelineExposure.drawing(FrameId(row), length: 24),
                    },
                  ),
              ],
            ),
          ],
        ),
      ],
    ),
  );

  /// The budget under test, held BY ITS OWN TYPE so the mutation campaign
  /// finds this file as its witness.
  PlaybackCacheBudget budgetOf(EditorSessionManager s) =>
      s.playbackRig.playbackCache;

  testWidgets('🚨a stroke turns the hold grey on the SAME cut instance — '
      'the row\'s image is of the cel before it', (tester) async {
    await tester.runAsync(() async {
      final s = session();
      addTearDown(s.dispose);
      final held = s.activeCutOrNull!;
      final key = s.brushFrameKeyForCut(
        held,
        const LayerId('layer'),
        const FrameId('frame-a'),
      );
      void stroke(double x, double size) => inkCel(
        s,
        key,
        canvasSize: canvasSize,
        at: CanvasPoint(x: x, y: x),
        size: size,
      );
      stroke(4, 4);
      final budget = budgetOf(s);

      await s.playbackRig.framePictures.make((
        cut: held,
        frameIndex: 0,
        paintPaper: true,
        ghosts: FrameGhosts.none,
      ), shouldAbort: () => false);
      expect(budget.playbackReadyRuns(0, 30), [
        (startIndex: 0, endIndexExclusive: 30, unreadable: false),
      ], reason: 'one image answers the whole hold; past it is nothing');

      stroke(2, 2);
      expect(identical(s.activeCutOrNull, held), isTrue);
      expect(
        budget.playbackReadyRuns(0, 30),
        [(startIndex: 24, endIndexExclusive: 30, unreadable: false)],
        reason: 'the image the row holds is of the cel before the stroke — '
            'the cel\'s revision moves the picture, not a new cut',
      );
    });
  });

  testWidgets('the timeline ruler reads the active cut', (tester) async {
    await tester.runAsync(() async {
      final s = session();
      addTearDown(s.dispose);
      final held = s.activeCutOrNull!;
      final budget = budgetOf(s);
      inkCel(
        s,
        s.brushFrameKeyForCut(
          held,
          const LayerId('layer'),
          const FrameId('frame-a'),
        ),
        canvasSize: canvasSize,
        at: CanvasPoint(x: 4, y: 4),
        size: 4,
      );
      expect(budget.playbackReadyRuns(3, 30), [
        (startIndex: 24, endIndexExclusive: 30, unreadable: false),
      ], reason: '⛔premise: the drawn hold waits for its picture');
      await s.playbackRig.framePictures.make((
        cut: held,
        frameIndex: 0,
        paintPaper: true,
        ghosts: FrameGhosts.none,
      ), shouldAbort: () => false);

      expect(budget.playbackReadyRuns(3, 30), [
        (startIndex: 3, endIndexExclusive: 30, unreadable: false),
      ]);
    });
  });

  // 유저 2026-10-16 (frame-picture-indicator-Q1 b): red is for a cel that
  // will never come — 「영영실패만 생각하면 될거같아」.
  testWidgets('🚨a frame showing a cel that cannot be read is red only once '
      'its other rows are there — until then it waits for them like any '
      'frame', (tester) async {
    await tester.runAsync(() async {
      final s = twoRows();
      addTearDown(s.dispose);
      final cut = s.activeCutOrNull!;
      BrushFrameKey celOf(String row) =>
          s.brushFrameKeyForCut(cut, LayerId(row), FrameId(row));
      for (final row in ['over', 'under']) {
        inkCel(
          s,
          celOf(row),
          canvasSize: canvasSize,
          at: CanvasPoint(x: 4, y: 4),
          size: 4,
        );
      }
      // How the cache keeps a cel whose reading threw.
      s.renderCaches.layerFrameImageCache.unreadable.note(celOf('over'));
      final budget = budgetOf(s);
      expect(
        budget.playbackReadyRuns(0, 24),
        isEmpty,
        reason: 'the other row\'s picture is still to come',
      );

      await s.playbackRig.framePictures.make((
        cut: cut,
        frameIndex: 0,
        paintPaper: true,
        ghosts: FrameGhosts.none,
      ), shouldAbort: () => false);

      expect(budget.playbackReadyRuns(0, 24), [
        (startIndex: 0, endIndexExclusive: 24, unreadable: true),
      ]);
    });
  });

  // The bar reads where a frame stands off one walk of its stack (card
  // frame-panels-build-in-one-frame, 2026-10-28).
  testWidgets('a frame given up on is red where a cel it shows cannot be '
      'read, and not on the bar at all where every cel reads', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final s = twoRows();
      addTearDown(s.dispose);
      final cut = s.activeCutOrNull!;
      BrushFrameKey celOf(String row) =>
          s.brushFrameKeyForCut(cut, LayerId(row), FrameId(row));
      for (final row in ['over', 'under']) {
        inkCel(
          s,
          celOf(row),
          canvasSize: canvasSize,
          at: CanvasPoint(x: 4, y: 4),
          size: 4,
        );
      }
      final budget = budgetOf(s);
      final frame = (
        cut: cut,
        frameIndex: 0,
        paintPaper: true,
        ghosts: FrameGhosts.none,
      );

      s.playbackRig.framePictures.noteFailure(frame);
      expect(
        budget.playbackReadyRuns(0, 24),
        isEmpty,
        reason: 'every cel reads: a run goes on past it, but it is not ready',
      );

      // A cel that will not read is no part of the frame's picture, so the
      // frame is another one — given up on in its turn.
      s.renderCaches.layerFrameImageCache.unreadable.note(celOf('over'));
      s.playbackRig.framePictures.noteFailure(frame);
      expect(budget.playbackReadyRuns(0, 24), [
        (startIndex: 0, endIndexExclusive: 24, unreadable: true),
      ], reason: 'it plays without the cel that will not read');
    });
  });
}
