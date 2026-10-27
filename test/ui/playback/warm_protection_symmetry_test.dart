import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
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
import 'package:anicel/src/ui/playback/playback_prerender_scheduler.dart';
import 'package:anicel/src/ui/session/playback_cache_budget.dart';
import 'package:anicel/src/ui/storyboard_playhead_mapping.dart';

import '../../helpers/draw_on_current_frame.dart';
import '../../helpers/poll_until.dart';

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

  /// The pictures are the frames' own (one-picture-per-frame ②-2): every
  /// screen — through the camera or not — shows a frame as its one picture,
  /// so the two cels are inked, each in both corners, which makes each
  /// frame's picture the whole 8×8 canvas on its paper. A frame with
  /// nothing in it draws its page alone: there by definition, nothing made.
  /// ↩️This file pinned the composite view's route, which the camera view
  /// played on, then the film's composites, then the canvas's row images
  /// (2026-10-10) — the hole between asked for none of those.
  EditorSessionManager session() {
    final s = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('project'),
        name: 'P',
        createdAt: DateTime.utc(2026),
        tracks: [
          Track(id: const TrackId('track'), name: 'T', cuts: [cut()]),
        ],
      ),
    );
    for (final cel in [const FrameId('frame-a'), const FrameId('frame-b')]) {
      for (final corner in [CanvasPoint(x: 1, y: 1), CanvasPoint(x: 6, y: 6)]) {
        inkCelIn(
          s.renderCaches.brushFrameStore,
          s.brushFrameKeyForCut(
            s.requireActiveCut,
            const LayerId('layer'),
            cel,
          ),
          canvasSize: canvasSize,
          at: corner,
          size: 2,
          tipShape: BrushTipShape.square,
          tileSize: 4,
        );
      }
    }
    return s;
  }

  /// The budget under test, held BY ITS OWN TYPE (2026-09-08).
  ///
  /// 🚨`tool/mutation_run.dart` picks a file's witnesses by which tests
  /// IMPORT it. A collaborator only ever spelled
  /// `s.playbackRig.playbackCache` is one the campaign reports UNNAMED and
  /// never runs a mutant against — B1's one-law derivation lives in that
  /// file and this is its witness.
  PlaybackCacheBudget budgetOf(EditorSessionManager s) =>
      s.playbackRig.playbackCache;

  /// Whether frame [frameIndex]'s picture is there, as the screen counts it.
  bool held(EditorSessionManager s, int frameIndex) => s
      .playbackRig
      .framePictures
      .has((
        cut: s.activeCutOrNull!,
        frameIndex: frameIndex,
        paintPaper: true,
        ghosts: false,
      ));

  int heldBytes(EditorSessionManager s) =>
      s.renderCaches.framePictureStore.estimatedBytes;

  /// What one frame's picture weighs — the body cel's, made in a session of
  /// its own, laid as the store lays it.
  Future<int> onePicture() async {
    final s = session();
    addTearDown(s.dispose);
    final frame = (
      cut: s.activeCutOrNull!,
      frameIndex: 0,
      paintPaper: true,
      ghosts: false,
    );
    await s.playbackRig.framePictures.make(frame, shouldAbort: () => false);
    return s.renderCaches.framePictureStore.bytesOf(
      s.playbackRig.framePictures.keyOf(frame),
    )!;
  }

  testWidgets('🚨the warm makes no picture the budget then lets go: under an '
      'allowance of one it rests on the one nearest the playhead, and the '
      'enforcer that follows takes nothing', (tester) async {
    await tester.runAsync(() async {
      final picture = await onePicture();
      final s = session();
      addTearDown(s.dispose);
      final budget = budgetOf(s);
      budget.debugSetPlaybackCacheBudgetBytes(picture);
      final scheduler = s.playbackRig.prerenderScheduler;

      // The playhead on frame 0. The cut's two pictures, nearest first: the
      // body cel (0..1) and the runway cel (5..6) — the nothing between asks
      // for none.
      s.warmActiveCut();
      await patiently(scheduler.idle);
      expect(
        [for (final frame in [0, 2, 5]) held(s, frame)],
        [true, true, false],
        reason: 'one fits; the runway cel is the farthest, and is not made',
      );
      expect(
        scheduler.progress.value,
        const PrerenderProgress(cached: 5, total: 5),
        reason: 'what is held is the window: frames 0..4 are there',
      );

      budget.enforcePlaybackCacheBudget();
      expect(
        heldBytes(s),
        picture,
        reason: 'the treadmill B1 ended: nothing made is let go',
      );

      // The playhead out on the runway: the window follows it.
      s.selectFrameIndex(5);
      await patiently(scheduler.idle);
      expect(
        [for (final frame in [0, 2, 5]) held(s, frame)],
        [false, true, true],
        reason: 'the body cel is the farthest from here, and gave its room',
      );
      expect(heldBytes(s), picture);
    });
  });

  testWidgets('🚨the enforcer lets go by what is WANTED, not by what was '
      'used longest ago', (tester) async {
    await tester.runAsync(() async {
      final picture = await onePicture();
      final s = session();
      addTearDown(s.dispose);
      final budget = budgetOf(s);
      budget.debugSetPlaybackCacheBudgetBytes(picture);
      final scheduler = s.playbackRig.prerenderScheduler;
      s.warmActiveCut();
      await patiently(scheduler.idle);

      // A second picture — the runway cel, made by another hand — and the
      // body cel is now the one used longest ago.
      await s.playbackRig.framePictures.make(
        (
          cut: s.activeCutOrNull!,
          frameIndex: 5,
          paintPaper: true,
          ghosts: false,
        ),
        shouldAbort: () => false,
      );
      expect([held(s, 0), held(s, 5)], [true, true], reason: '⛔premise');

      budget.enforcePlaybackCacheBudget();

      expect(
        [for (final frame in [0, 2, 5]) held(s, frame)],
        [true, true, false],
        reason: 'the runway cel is wanted last from frame 0 — recency '
            'would have taken the body cel',
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
          .playbackReadyRunsForCut(activeCut, 0, 12, paintPaper: true)
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
        budget.playbackReadyRunsForCut(activeCut, 0, 12, paintPaper: true),
        [
          (startIndex: 2, endIndexExclusive: 5, unreadable: false),
          (startIndex: 7, endIndexExclusive: 12, unreadable: false),
        ],
        reason: 'the body cel waits for its bake too; everything that '
            'composes to nothing is one stretch each',
      );
      expect(
        budget.playbackReadyRunsForCut(activeCut, 0, 12, paintPaper: false),
        budget.playbackReadyRunsForCut(activeCut, 0, 12, paintPaper: true),
        reason: 'on its paper or on none — a track over the stage — a frame '
            'of nothing draws its page alone, and nothing of it is made',
      );

      await s.playbackRig.framePictures.make(
        (cut: activeCut, frameIndex: 5, paintPaper: true, ghosts: false),
        shouldAbort: () => false,
      );
      expect(ready(5), isTrue);
      expect(
        budget.playbackReadyRunsForCut(activeCut, 0, 12, paintPaper: true),
        [(startIndex: 2, endIndexExclusive: 12, unreadable: false)],
        reason: 'one image answers the whole held span — frame 6 shows the '
            'same cel, so it is the same picture',
      );
    });
  });

  testWidgets('a track gap is ready by definition — playback there draws '
      'the background and nothing else', (tester) async {
    final s = session();
    addTearDown(s.dispose);

    expect(
      storyboardReadyRuns(s, 999, 1000, layout: const []),
      [(startIndex: 999, endIndexExclusive: 1000, unreadable: false)],
      reason: 'no cut owns the frame, so there is nothing to prepare — '
          'the same two-kind law the in-cut answer follows',
    );
  });
}
