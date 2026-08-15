import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/cut_warm_extent.dart';
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

/// B1 — WARMING, PROTECTION AND THE BAR REASON OVER ONE NUMBER.
///
/// The asymmetry was not hypothetical: the warm baked out to the authored
/// runway (⑯) while the non-playing protection stopped AT the end line,
/// so every runway composite was evictable the moment it landed — by the
/// budget enforcer that runs after every warmed frame.
///
/// ⛔THE FIXTURE IS THE TEST. A runway that RE-EXPOSES a body cel shares
/// its signature, and content addressing then protects the runway image
/// through the body frame's index key — delete the fix and the test stays
/// green. The runway cel here appears NOWHERE inside the duration.
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

  testWidgets('protection derives from the warm law — a runway composite '
      'survives the enforcer that follows every warmed frame',
      (tester) async {
    await tester.runAsync(() async {
      final s = session();
      addTearDown(s.dispose);
      final activeCut = s.activeCutOrNull!;
      final quality = s.playbackQuality;

      final range = s.debugPlaybackProtectedRanges().single;
      expect(range.endFrame, cutWarmFrameCount(activeCut) - 1);
      expect(range.endFrame, 6, reason: 'the runway reaches frame 6');

      await s.cutFrameCompositeCache.prepareComposite(
        cut: activeCut,
        frameIndex: 5,
        quality: quality,
      );
      // The same frame at the OTHER tier: same pixels' worth of work, no
      // protection — the anchor that says survival below is the range
      // doing its job, not the budget being roomy.
      final other = quality == PlaybackQuality.full
          ? PlaybackQuality.half
          : PlaybackQuality.full;
      await s.cutFrameCompositeCache.prepareComposite(
        cut: activeCut,
        frameIndex: 5,
        quality: other,
      );

      s.cutFrameCompositeCache.enforceBudget(
        maxBytes: 0,
        protect: s.debugPlaybackProtectedRanges(),
      );

      expect(
        s.cutFrameCompositeCache.validCompositeOrNull(
          cut: activeCut,
          frameIndex: 5,
          quality: quality,
        ),
        isNotNull,
        reason: 'the warm just baked this — evicting it is the treadmill '
            'the one-law derivation exists to end',
      );
      expect(
        s.cutFrameCompositeCache.validCompositeOrNull(
          cut: activeCut,
          frameIndex: 5,
          quality: other,
        ),
        isNull,
        reason: 'the unprotected tier goes, so the survival above is the '
            'range speaking',
      );
    });
  });

  testWidgets('the warm queue and the protected range agree to the frame',
      (tester) async {
    final s = session();
    addTearDown(s.dispose);
    final activeCut = s.activeCutOrNull!;

    s.prerenderScheduler.requestWarmCut(
      cutId: activeCut.id,
      quality: s.playbackQuality,
    );

    expect(
      s.prerenderScheduler.progress.value.total,
      cutWarmFrameCount(activeCut),
    );
    expect(
      s.debugPlaybackProtectedRanges().single.endFrame + 1,
      s.prerenderScheduler.progress.value.total,
      reason: 'one function, two readers — the disagreement WAS the bug',
    );

    // Stand the run down INSIDE the test: its zero-length yield timer
    // otherwise trips the binding's timer invariant, which runs before
    // the teardown dispose (the scheduler's own documented hazard).
    s.prerenderScheduler.cancel();
    await tester.pump();
  });

  testWidgets('the bar answers two kinds of frame: baked-when-bakeable, '
      'ready-by-definition when there is nothing to bake', (tester) async {
    await tester.runAsync(() async {
      final s = session();
      addTearDown(s.dispose);
      final activeCut = s.activeCutOrNull!;

      expect(
        s.isPlaybackFrameReadyForCut(activeCut, 2),
        isTrue,
        reason: 'the hole between blocks composes to nothing — ready by '
            'definition, no bake required',
      );
      expect(
        s.isPlaybackFrameReadyForCut(activeCut, 8),
        isTrue,
        reason: 'past every drawing is the same nothing',
      );
      expect(
        s.isPlaybackFrameReadyForCut(activeCut, 5),
        isFalse,
        reason: 'the runway cel is REAL content — green must wait for its '
            'bake, or the bar claims readiness playback cannot deliver',
      );

      await s.cutFrameCompositeCache.prepareComposite(
        cut: activeCut,
        frameIndex: 5,
        quality: s.playbackQuality,
      );
      expect(s.isPlaybackFrameReadyForCut(activeCut, 5), isTrue);
    });
  });
}
