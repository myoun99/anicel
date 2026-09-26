import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/playback_quality.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/playback_cache_budget.dart';

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

  /// The budget under test, held BY ITS OWN TYPE so the mutation campaign
  /// finds this file as its witness.
  PlaybackCacheBudget budgetOf(EditorSessionManager s) =>
      s.playbackRig.playbackCache;

  testWidgets('a stroke turns the hold grey on the SAME cut instance — the '
      'pixel revision moves the signature, not a new cut', (tester) async {
    await tester.runAsync(() async {
      final s = session();
      addTearDown(s.dispose);
      final held = s.activeCutOrNull!;
      final budget = budgetOf(s);
      await s.renderCaches.cutFrameCompositeCache.prepareComposite(
        cut: held,
        frameIndex: 0,
        quality: s.playbackRig.playbackQuality,
      );

      expect(budget.playbackReadyRunsForCut(held, 0, 30), [
        (startIndex: 0, endIndexExclusive: 30),
      ], reason: 'one bake answers the whole hold; past it is nothing');

      s.renderCaches.brushFrameStore.markCelEdited(
        s.brushFrameKeyForCut(
          held,
          const LayerId('layer'),
          const FrameId('frame-a'),
        ),
      );

      expect(identical(s.activeCutOrNull, held), isTrue);
      expect(
        budget.playbackReadyRunsForCut(held, 0, 30),
        [(startIndex: 24, endIndexExclusive: 30)],
        reason: 'the held image is the picture BEFORE the stroke — a '
            'signature remembered past the pixel revision would still find '
            'it and call the hold ready',
      );
    });
  });

  testWidgets('the bar answers for the quality playback plays at', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final s = session();
      addTearDown(s.dispose);
      final held = s.activeCutOrNull!;
      final budget = budgetOf(s);
      s.playbackRig.playbackQuality = PlaybackQuality.full;
      await s.renderCaches.cutFrameCompositeCache.prepareComposite(
        cut: held,
        frameIndex: 0,
        quality: PlaybackQuality.full,
      );

      expect(budget.playbackReadyRunsForCut(held, 0, 30), [
        (startIndex: 0, endIndexExclusive: 30),
      ]);
      s.playbackRig.playbackQuality = PlaybackQuality.half;
      expect(
        budget.playbackReadyRunsForCut(held, 0, 30),
        [(startIndex: 24, endIndexExclusive: 30)],
        reason: 'nothing was baked at half — the full bake is another '
            'picture',
      );
      s.playbackRig.playbackQuality = PlaybackQuality.full;
      expect(budget.playbackReadyRunsForCut(held, 0, 30), [
        (startIndex: 0, endIndexExclusive: 30),
      ]);
    });
  });

  testWidgets('the timeline ruler reads the active cut', (tester) async {
    await tester.runAsync(() async {
      final s = session();
      addTearDown(s.dispose);
      final held = s.activeCutOrNull!;
      final budget = budgetOf(s);
      await s.renderCaches.cutFrameCompositeCache.prepareComposite(
        cut: held,
        frameIndex: 0,
        quality: s.playbackRig.playbackQuality,
      );

      expect(budget.playbackReadyRuns(3, 30), [
        (startIndex: 3, endIndexExclusive: 30),
      ]);
    });
  });
}
