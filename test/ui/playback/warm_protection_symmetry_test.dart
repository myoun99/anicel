import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/cut_warm_extent.dart';
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
import 'package:anicel/src/ui/playback/playback_prerender_scheduler.dart'
    show PrerenderProgress;
import 'package:anicel/src/ui/session/playback_cache_budget.dart';
import 'package:anicel/src/ui/storyboard_playhead_mapping.dart';

/// B1 — THE WARM, THE BUDGET AND THE BAR REASON OVER ONE ORDER.
///
/// The asymmetry was not hypothetical: the warm baked out to the authored
/// runway (⑯) while the non-playing protection stopped AT the end line,
/// so every runway composite was evictable the moment it landed — by the
/// budget enforcer that runs after every warmed frame. ↩️B1 closed it by
/// deriving the kept range from the warm's own frame count; since
/// 2026-10-08 there is no range to derive — the budget lets go by the very
/// order the warm makes pictures in (`FrameDemand`), and the warm makes
/// none it has no room for.
///
/// ⛔THE FIXTURE IS THE TEST. A runway that RE-EXPOSES a body cel shares
/// its signature, and content addressing then keeps the runway image
/// through the body frame's index key. The runway cel here appears NOWHERE
/// inside the duration.
void main() {
  const canvasSize = CanvasSize(width: 8, height: 8);

  // duration 4; body cel at 0..1, a HOLE at 2..3, and a runway cel at
  // 5..6 that exists nowhere in the body. Warm world = 7 frames.
  Cut cut() => Cut(
    id: const CutId('cut'),
    name: '1',
    duration: 4,
    canvasSize: canvasSize,
    layers: [
      Layer(
        id: const LayerId('layer'),
        name: 'A',
        frames: [
          Frame(id: const FrameId('frame-a'), duration: 1, strokes: const []),
          Frame(id: const FrameId('frame-b'), duration: 1, strokes: const []),
        ],
        timeline: {
          0: const TimelineExposure.drawing(FrameId('frame-a'), length: 2),
          5: const TimelineExposure.drawing(FrameId('frame-b'), length: 2),
        },
      ),
    ],
  );

  EditorSessionManager session() => EditorSessionManager(
    initialProject: Project(
      id: const ProjectId('project'),
      name: 'P',
      createdAt: DateTime.utc(2026),
      tracks: [
        Track(id: const TrackId('track'), name: 'T', cuts: [cut()]),
      ],
    ),
  );

  /// The budget under test, held BY ITS OWN TYPE (2026-09-08).
  ///
  /// 🚨`tool/mutation_run.dart` picks a file's witnesses by which tests
  /// IMPORT it. A collaborator only ever spelled
  /// `s.playbackRig.playbackCache` is one the campaign reports UNNAMED and
  /// never runs a mutant against — B1's one-law derivation lives in that
  /// file and this is its witness.
  PlaybackCacheBudget budgetOf(EditorSessionManager s) =>
      s.playbackRig.playbackCache;

  const picture = 8 * 8 * 4;

  bool held(EditorSessionManager s, int frameIndex) =>
      s.renderCaches.cutFrameCompositeCache.validCompositeOrNull(
        cut: s.activeCutOrNull!,
        frameIndex: frameIndex,
      ) !=
      null;

  testWidgets('🚨the warm makes no picture the budget then lets go: under an '
      'allowance of two it rests on the two nearest the playhead, and the '
      'enforcer that follows takes neither', (tester) async {
    await tester.runAsync(() async {
      final s = session();
      addTearDown(s.dispose);
      final budget = budgetOf(s);
      budget.debugSetPlaybackCacheBudgetBytes(2 * picture);
      final scheduler = s.playbackRig.prerenderScheduler;

      // The playhead on frame 0. The cut's three pictures, nearest first:
      // the body cel (0..1), the nothing between (2..4), the runway cel.
      s.warmActiveCut();
      await scheduler.idle;
      expect(
        [for (final frame in [0, 2, 5]) held(s, frame)],
        [true, true, false],
        reason: 'two fit; the runway cel is the farthest, and is not made',
      );
      expect(
        scheduler.progress.value,
        const PrerenderProgress(cached: 5, total: 5),
        reason: 'what is held is the window: frames 0..4 are there',
      );

      budget.enforcePlaybackCacheBudget();
      expect(
        s.renderCaches.cutFrameCompositeCache.estimatedBytes,
        2 * picture,
        reason: 'the treadmill B1 ended: nothing made is let go',
      );

      // The playhead out on the runway: the window follows it.
      s.selectFrameIndex(5);
      await scheduler.idle;
      expect(
        [for (final frame in [0, 2, 5]) held(s, frame)],
        [false, true, true],
        reason: 'the body cel is the farthest from here, and gave its room',
      );
      expect(
        s.renderCaches.cutFrameCompositeCache.estimatedBytes,
        2 * picture,
      );
    });
  });

  testWidgets('🚨the enforcer lets go by what is WANTED, not by what was '
      'used longest ago', (tester) async {
    await tester.runAsync(() async {
      final s = session();
      addTearDown(s.dispose);
      final budget = budgetOf(s);
      budget.debugSetPlaybackCacheBudgetBytes(2 * picture);
      final scheduler = s.playbackRig.prerenderScheduler;
      final composites = s.renderCaches.cutFrameCompositeCache;
      s.warmActiveCut();
      await scheduler.idle;

      // A third picture — the runway cel, made by another hand — and the
      // nothing between is now the one used longest ago.
      await composites.prepareComposite(
        cut: s.activeCutOrNull!,
        frameIndex: 5,
      );
      expect(held(s, 0), isTrue, reason: 'asked: the body cel is used now');
      expect(held(s, 5), isTrue);

      budget.enforcePlaybackCacheBudget();

      expect(
        [for (final frame in [0, 2, 5]) held(s, frame)],
        [true, true, false],
        reason: 'the runway cel is wanted last from frame 0 — recency '
            'would have taken the nothing between',
      );
    });
  });

  testWidgets('the warm and the budget read ONE order', (tester) async {
    final s = session();
    addTearDown(s.dispose);
    final activeCut = s.activeCutOrNull!;

    s.playbackRig.prerenderScheduler.requestWarmCut(
      cutId: activeCut.id,
    );

    expect(
      s.playbackRig.prerenderScheduler.progress.value.total,
      cutWarmFrameCount(activeCut),
    );
    expect(
      identical(
        s.playbackRig.demand,
        s.playbackRig.prerenderScheduler.demand,
      ),
      isTrue,
      reason: 'one object, two readers — the disagreement WAS the bug',
    );
    expect(s.playbackRig.demand!.length, cutWarmFrameCount(activeCut));

    // Stand the run down INSIDE the test: its zero-length yield timer
    // otherwise trips the binding's timer invariant, which runs before
    // the teardown dispose (the scheduler's own documented hazard).
    s.playbackRig.prerenderScheduler.cancel();
    await tester.pump();
  });

  testWidgets('the bar answers two kinds of frame: baked-when-bakeable, '
      'ready-by-definition when there is nothing to bake', (tester) async {
    await tester.runAsync(() async {
      final s = session();
      addTearDown(s.dispose);
      final activeCut = s.activeCutOrNull!;
      final budget = budgetOf(s);
      bool ready(int frame) => budget
          .playbackReadyRunsForCut(activeCut, 0, 12)
          .any(
            (run) => frame >= run.startIndex && frame < run.endIndexExclusive,
          );

      expect(
        ready(2),
        isTrue,
        reason: 'the hole between blocks composes to nothing — ready by '
            'definition, no bake required',
      );
      expect(
        ready(8),
        isTrue,
        reason: 'past every drawing is the same nothing',
      );
      expect(
        ready(5),
        isFalse,
        reason: 'the runway cel is REAL content — green must wait for its '
            'bake, or the bar claims readiness playback cannot deliver',
      );
      expect(
        budget.playbackReadyRunsForCut(activeCut, 0, 12),
        [
          (startIndex: 2, endIndexExclusive: 5),
          (startIndex: 7, endIndexExclusive: 12),
        ],
        reason: 'the body cel waits for its bake too; everything that '
            'composes to nothing is one stretch each',
      );

      await s.renderCaches.cutFrameCompositeCache.prepareComposite(
        cut: activeCut,
        frameIndex: 5,
      );
      expect(ready(5), isTrue);
      expect(
        budget.playbackReadyRunsForCut(activeCut, 0, 12),
        [(startIndex: 2, endIndexExclusive: 12)],
        reason: 'one bake answers the whole held span — frame 6 shows the '
            'same picture, so it is the same composite',
      );
    });
  });

  testWidgets('a track gap is ready by definition — playback there draws '
      'the background and nothing else', (tester) async {
    final s = session();
    addTearDown(s.dispose);

    expect(
      storyboardReadyRuns(s, 999, 1000, layout: const []),
      [(startIndex: 999, endIndexExclusive: 1000)],
      reason: 'no cut owns the frame, so there is nothing to prepare — '
          'the same two-kind law the in-cut answer follows',
    );
  });
}
