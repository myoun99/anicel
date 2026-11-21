import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart';

import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/native/app_gpu_engine.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

import '../../helpers/a_canvas_standing_on_a_frame.dart';
import '../../helpers/poll_until.dart';

/// F-610 (2026-11-21): the engine folds its pictures' tiles once a hand
/// rests and weighs each as it lies, so the frames' pictures read lighter
/// with the playhead standing — room on the playback's line that no other
/// channel of the warmer's tells of. A rest that weighed them says so
/// ([GpuEngine.picturesWeighedAgain]), and each open project's warmer
/// looks again (`EditorSessionManager.playbackLineMoved`).
///
/// What a rest weighs, and when it says it did, is the crate's to pin
/// (rust/src/kernels/composite/screen_tests.rs · abi/tests.rs) — here,
/// that the word reaches the warmer, and only the word that it weighed.
void main() {
  opensTheEnginesScreens();
  const rest = Duration(milliseconds: 30);
  const all = (-1 << 31, -1 << 31, (1 << 31) - 1, (1 << 31) - 1);
  const identity = [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0];

  /// A project of one cut, one row and one cel nothing is drawn on.
  EditorSessionManager aProject() => EditorSessionManager(
    initialProject: Project(
      id: const ProjectId('weighed'),
      name: 'Weighed',
      cameraSize: const CanvasSize(width: 32, height: 32),
      createdAt: DateTime.utc(2026, 11, 21),
      tracks: [
        Track(
          id: const TrackId('track'),
          name: 'Video',
          cuts: [
            Cut(
              id: const CutId('c'),
              name: '1',
              duration: 2,
              canvasSize: const CanvasSize(width: 64, height: 64),
              layers: [
                Layer(
                  id: const LayerId('a'),
                  name: 'A',
                  kind: LayerKind.animation,
                  frames: [
                    Frame(
                      id: const FrameId('f'),
                      duration: 1,
                      strokes: const [],
                    ),
                  ],
                  timeline: const {
                    0: TimelineExposure.drawing(FrameId('f'), length: 2),
                  },
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  );

  testWidgets('🚨a rest that weighed the pictures again wakes the warmer '
      'that rests, and one that weighed nothing leaves it resting', (
    tester,
  ) async {
    await tester.runAsync(() async {
      GpuEngine.restsAfter = rest;
      addTearDown(() => GpuEngine.restsAfter = null);
      final pool = GpuPool(appGpuEngine, 1 << 30);
      addTearDown(pool.free);
      final bytes = calloc<Uint8>(gpuTileBytes);
      addTearDown(() => calloc.free(bytes));
      bytes.asTypedList(gpuTileBytes).fillRange(0, gpuTileBytes, 255);
      final plan = GpuPlan(appGpuEngine);
      addTearDown(plan.free);
      final added = plan.row(
        set: plan.set(
          0,
          0,
          1,
          1,
          pool.store(pool.cel(), [bytes], (tile) => tile),
        ),
        inverse: identity,
        sampling: GpuSampling.blend,
        columns: gpuTileSide,
        rows: gpuTileSide,
        mode: GpuBlend.normal,
      );
      expect(added, isTrue);

      /// A compose handed to the engine, and the rest after it taken
      /// and told: whatever it tells has reached this isolate.
      Future<void> aRestAfterACompose() async {
        appGpuComposite.run(pool, plan, [(0, 0)], all).free();
        expect(appGpuEngine.debugRestOnItsWay, isTrue, reason: '⛔premise');
        await pollUntil(() => !appGpuEngine.debugRestOnItsWay);
        await appGpuEngine.done();
        // The rest's word comes on a turn of this isolate's own.
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }

      expect(
        GpuEngine.debugPicturesWeighedAgainIsHeard,
        isFalse,
        reason: '⛔premise: no project is open',
      );
      final session = aProject();
      expect(GpuEngine.debugPicturesWeighedAgainIsHeard, isTrue);
      final scheduler = session.playbackRig.prerenderScheduler;
      var cameToRest = 0;
      scheduler.changes.addListener(() {
        if (scheduler.isResting) {
          cameToRest += 1;
        }
      });
      session.warmActiveCut();
      expect(
        await pollUntil(
          () => scheduler.progress.value.isComplete && scheduler.isResting,
        ),
        isTrue,
        reason: '⛔premise: the warmer rests, its pictures made',
      );
      // The warm's own composes are rested after too, before any count.
      await pollUntil(() => !appGpuEngine.debugRestOnItsWay);
      await appGpuEngine.done();
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // No kernel to fold by is compiled yet: the rest folds nothing,
      // weighs nothing, and says so.
      expect(appGpuFoldKernels.compiled, isNull, reason: '⛔premise');
      final rested = cameToRest;
      await aRestAfterACompose();
      expect(scheduler.isResting, isTrue);
      expect(cameToRest, rested, reason: 'a rest that weighed nothing');

      await appGpuFoldKernels.warm();
      await aRestAfterACompose();
      expect(
        await pollUntil(() => cameToRest == rested + 1),
        isTrue,
        reason: 'the warmer looked again, and came to rest once more',
      );

      session.dispose();
      expect(
        GpuEngine.debugPicturesWeighedAgainIsHeard,
        isFalse,
        reason: 'a project closed hears no rest: the ticks outlive it',
      );
    });
  });
}
