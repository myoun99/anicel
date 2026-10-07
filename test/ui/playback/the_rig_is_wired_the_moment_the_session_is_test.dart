import 'package:anicel/src/controllers/default_project_helpers.dart';
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
import 'package:anicel/src/services/playback/frame_demand.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/playback/canvas_playback_controller.dart'
    show PlaybackScope;
import 'package:anicel/src/ui/session/playback_rig.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// What the playback rig owes the session — that it is wired the moment
/// the session exists, that it goes down with it, and that its warmer
/// follows a run for as long as the run plays — none of which had an
/// observer before this file: every body here could be emptied and every
/// suite stayed green.
/// The collaborator under test — named so `tool/mutation_run.dart` has a
/// suite to run for it.
PlaybackRig playbackRigOf(EditorSessionManager session) => session.playbackRig;

void main() {
  late EditorSessionManager session;

  setUp(() {
    session = EditorSessionManager(initialProject: createDefaultProject());
  });

  tearDown(() => session.dispose());

  test('the transport is ATTACHED: the controller holds an audio clock to '
      'read, so a run can ride the samples instead of the wall clock', () {
    expect(
      session.playbackRig.playback.resolveAudioClock,
      isNotNull,
      reason:
          'attach() is what hands the controller that clock. Without it '
          'every run derives the picture from the wall clock and the '
          'device transport can never carry one',
    );
  });

  test('the session going down takes the rig with it — the transport stops '
      'being usable, which is what says nothing is still listening', () {
    final own = EditorSessionManager(initialProject: createDefaultProject());
    final transport = own.playbackRig.playback;
    own.dispose();
    expect(
      () => transport.globalFrameIndexListenable.addListener(() {}),
      throwsA(isA<FlutterError>()),
      reason:
          'a transport the session forgot to dispose keeps its ticker and '
          'every listener alive for the life of the app',
    );
  });

  /// 유저 2026-10-08, the playback rework: the warmer follows what a run
  /// wants, from the frame under its playhead.
  test('the warmer follows a run from the moment it begins, keeps to it '
      'whatever warm is asked for under it, and lets it go when it ends', () {
    final rig = playbackRigOf(session);
    expect(rig.demand, isNot(isA<PlayingDemand>()));

    rig.playback.play(scope: PlaybackScope.activeCut);
    final followed = rig.demand;
    expect(followed, isA<PlayingDemand>());

    // A warm asked for under the run: a reference movie's frame decoded.
    session.warmActiveCut();
    expect(
      identical(rig.demand, followed),
      isTrue,
      reason: 'a standing warm that took the warmer would leave a run that '
          'waits for its picture waiting for good',
    );

    rig.playback.stop();
    expect(rig.demand, isNot(isA<PlayingDemand>()));
  });

  testWidgets('🚨the playhead moving on is what wakes the warmer: under an '
      'allowance of one picture, the picture held follows a seek', (
    tester,
  ) async {
    await tester.runAsync(() async {
      // Two pictures: a cel on frames 0..1, another on 2..3.
      Layer row() => Layer(
        id: const LayerId('layer'),
        name: 'A',
        frames: [
          Frame(id: const FrameId('a'), duration: 1, strokes: const []),
          Frame(id: const FrameId('b'), duration: 1, strokes: const []),
        ],
        timeline: {
          0: const TimelineExposure.drawing(FrameId('a'), length: 2),
          2: const TimelineExposure.drawing(FrameId('b'), length: 2),
        },
      );
      final s = EditorSessionManager(
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
                  duration: 4,
                  canvasSize: const CanvasSize(width: 8, height: 8),
                  layers: [row()],
                ),
              ],
            ),
          ],
        ),
      );
      addTearDown(s.dispose);
      final rig = playbackRigOf(s);
      rig.playbackCache.debugSetPlaybackCacheBudgetBytes(8 * 8 * 4);
      Future<void> rested() => rig.prerenderScheduler.idle.timeout(
        const Duration(seconds: 10),
        onTimeout: () {},
      );
      bool held(int frameIndex) =>
          s.renderCaches.cutFrameCompositeCache.validCompositeOrNull(
            cut: s.activeCutOrNull!,
            frameIndex: frameIndex,
          ) !=
          null;

      rig.playback.play(scope: PlaybackScope.activeCut);
      await rested();
      expect(
        [held(0), held(2)],
        [true, false],
        reason: 'one picture fits: the one under the playhead',
      );

      rig.playback.seekToGlobalFrame(2);
      await rested();
      expect([held(0), held(2)], [false, true]);

      rig.playback.stop();
    });
  });
}
