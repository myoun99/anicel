import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/playback_mode.dart';
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

  const picture = 8 * 8 * 4;

  /// A session on one cut of four frames and TWO pictures: a cel on frames
  /// 0..1, another on 2..3.
  EditorSessionManager twoPictures() => EditorSessionManager(
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
              layers: [
                Layer(
                  id: const LayerId('layer'),
                  name: 'A',
                  frames: [
                    Frame(
                      id: const FrameId('a'),
                      duration: 1,
                      strokes: const [],
                    ),
                    Frame(
                      id: const FrameId('b'),
                      duration: 1,
                      strokes: const [],
                    ),
                  ],
                  timeline: {
                    0: const TimelineExposure.drawing(FrameId('a'), length: 2),
                    2: const TimelineExposure.drawing(FrameId('b'), length: 2),
                  },
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  );

  /// The warmer at rest — or ten seconds gone, which the test then says.
  Future<void> rested(PlaybackRig rig) => rig.prerenderScheduler.idle.timeout(
    const Duration(seconds: 10),
    onTimeout: () {},
  );

  bool held(EditorSessionManager s, int frameIndex) =>
      s.renderCaches.cutFrameCompositeCache.validCompositeOrNull(
        cut: s.activeCutOrNull!,
        frameIndex: frameIndex,
      ) !=
      null;

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

  test('the playback mode is a setting: it starts as every picture, a new '
      'one lands and announces, the same one changes nothing', () {
    var notices = 0;
    session.addListener(() => notices += 1);
    final rig = playbackRigOf(session);
    expect(
      rig.playbackMode,
      PlaybackMode.everyPicture,
      reason: '유저 2026-10-08: 「기본값 모든그림」',
    );

    rig.setPlaybackMode(PlaybackMode.renderFirst);
    expect(rig.playbackMode, PlaybackMode.renderFirst);
    expect(
      notices,
      greaterThan(0),
      reason: 'the settings row reads the mode',
    );

    final after = notices;
    rig.setPlaybackMode(PlaybackMode.renderFirst);
    expect(notices, after, reason: 'the mode it already has is not an event');
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

  test('🚨a run that ends is let go AT ONCE, by the rig — not when the '
      'session next says what is wanted', () {
    // The session says so on most stops: its seek to the frame the playhead
    // lands on warms that cut. Not on all of them — a run that ends over a
    // gap parks with no cut to warm, and one that ends a voice take says
    // nothing until the take has landed — and a run that is followed has no
    // idle gate: left followed, its pictures would be made under the pen.
    final rig = playbackRigOf(session);
    final wantedAsItEnded = <FrameDemand?>[];
    rig.playback.isActiveListenable.addListener(() {
      if (!rig.playback.isActive) {
        wantedAsItEnded.add(rig.demand);
      }
    });

    rig.playback.play(scope: PlaybackScope.activeCut);
    expect(rig.demand, isA<PlayingDemand>(), reason: '⛔premise');
    rig.playback.stop();

    expect(wantedAsItEnded, [null]);
  });

  testWidgets('🚨the playhead moving on is what wakes the warmer: under an '
      'allowance of one picture, the picture held follows a seek', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final s = twoPictures();
      addTearDown(s.dispose);
      final rig = playbackRigOf(s);
      rig.playbackCache.debugSetPlaybackCacheBudgetBytes(picture);

      rig.playback.play(scope: PlaybackScope.activeCut);
      await rested(rig);
      expect(
        [held(s, 0), held(s, 2)],
        [true, false],
        reason: 'one picture fits: the one under the playhead',
      );

      rig.playback.seekToGlobalFrame(2);
      await rested(rig);
      expect([held(s, 0), held(s, 2)], [false, true]);

      rig.playback.stop();
    });
  });

  /// 유저 2026-10-08: 「세개 두면 좋을거같긴하고」 · 「기본값 모든그림」 —
  /// the three modes, through the session's own warmer.
  group('how a run waits for its picture', () {
    /// Whether the run waited, read at the press and then each time the
    /// warmer said the answer may have changed.
    Future<List<bool>> waitedAtEachChange(
      EditorSessionManager s, {
      int budget = 16 * picture,
    }) async {
      final rig = playbackRigOf(s);
      rig.playbackCache.debugSetPlaybackCacheBudgetBytes(budget);
      final waited = <bool>[];
      // After the rig's own listener, which is what lets the run go on.
      rig.prerenderScheduler.changes.addListener(
        () => waited.add(rig.playback.isWaiting),
      );
      rig.playback.play(scope: PlaybackScope.activeCut);
      waited.insert(0, rig.playback.isWaiting);
      await rested(rig);
      return waited;
    }

    testWidgets('🚨every picture (the default): the run waits on its first '
        'frame until THAT picture is made, and then goes', (tester) async {
      await tester.runAsync(() async {
        final s = twoPictures();
        addTearDown(s.dispose);

        final waited = await waitedAtEachChange(s);

        expect(
          waited,
          [true, false, false, false],
          reason: 'at the press, nothing is made; one picture later it goes '
              '— the second picture is not waited for, nor the rest',
        );
        expect(playbackRigOf(s).playback.isWaiting, isFalse);
        expect(playbackRigOf(s).demand!.leadFor(const Duration(seconds: 1)), 0);
        playbackRigOf(s).playback.stop();
      });
    });

    testWidgets('🚨rendering first: the run waits until what lies ahead is '
        'made — its first picture is not enough', (tester) async {
      await tester.runAsync(() async {
        final s = twoPictures();
        addTearDown(s.dispose);
        playbackRigOf(s).setPlaybackMode(PlaybackMode.renderFirst);

        final waited = await waitedAtEachChange(s);

        expect(
          waited,
          [true, true, true, false],
          reason: 'still waiting as each of the two pictures lands: it goes '
              'when the warmer has come to rest',
        );
        expect([held(s, 0), held(s, 2)], [true, true]);
        playbackRigOf(s).playback.stop();
      });
    });

    testWidgets('🚨rendering first, a run dragged somewhere else fills again '
        'before it goes — onto a frame whose picture is there, too: what '
        'was filled was filled for where it stood', (tester) async {
      await tester.runAsync(() async {
        final s = twoPictures();
        addTearDown(s.dispose);
        final rig = playbackRigOf(s)
          ..setPlaybackMode(PlaybackMode.renderFirst);
        await waitedAtEachChange(s);
        expect(rig.playback.isWaiting, isFalse, reason: '⛔premise: it goes');
        expect(held(s, 2), isTrue, reason: '⛔premise: frame 2 is there');

        rig.playback.seekToGlobalFrame(2);
        expect(rig.playback.isWaiting, isTrue);
        await rested(rig);
        expect(rig.playback.isWaiting, isFalse);

        // 🚨Onto the frame it already stands on: the playhead does not
        // move, so nothing else wakes the warmer — and a warmer left at
        // rest never says it has come to rest.
        rig.playback.seekToGlobalFrame(2);
        expect(rig.playback.isWaiting, isTrue);
        await rested(rig);
        expect(
          rig.playback.isWaiting,
          isFalse,
          reason: 'the rig wakes the warmer for a run that was put',
        );
        rig.playback.stop();
      });
    });

    testWidgets('showing every picture, a run dragged onto a frame whose '
        'picture is there goes on at once', (tester) async {
      await tester.runAsync(() async {
        final s = twoPictures();
        addTearDown(s.dispose);
        final rig = playbackRigOf(s);
        await waitedAtEachChange(s);
        expect(held(s, 2), isTrue, reason: '⛔premise: frame 2 is there');

        rig.playback.seekToGlobalFrame(2);
        expect(rig.playback.isWaiting, isFalse);
        rig.playback.stop();
      });
    });

    testWidgets('rendering first under an allowance of one picture: what is '
        'held is all there is to wait for', (tester) async {
      await tester.runAsync(() async {
        final s = twoPictures();
        addTearDown(s.dispose);
        playbackRigOf(s).setPlaybackMode(PlaybackMode.renderFirst);

        await waitedAtEachChange(s, budget: picture);

        expect(
          playbackRigOf(s).playback.isWaiting,
          isFalse,
          reason: 'a film is not baked whole: the window filled, and it goes',
        );
        expect([held(s, 0), held(s, 2)], [true, false]);
        playbackRigOf(s).playback.stop();
      });
    });

    testWidgets('skipping frames: the run never waits, and starts each '
        'picture where the playhead will be when it lands', (tester) async {
      await tester.runAsync(() async {
        final s = twoPictures();
        addTearDown(s.dispose);
        final rig = playbackRigOf(s)..setPlaybackMode(PlaybackMode.skipFrames);

        final waited = await waitedAtEachChange(s);

        expect(
          waited.length,
          greaterThan(1),
          reason: '⛔premise: it was asked as pictures landed',
        );
        expect(waited, everyElement(isFalse));
        expect(
          rig.demand!.leadFor(const Duration(seconds: 1)),
          s.projectSettings.projectFrameRate.frameAtElapsed(
            const Duration(seconds: 1),
          ),
          reason: 'a second to make a picture is a second\'s frames of lead',
        );
        rig.playback.stop();
      });
    });

    testWidgets('a mode picked under a run that waits is looked at there and '
        'then', (tester) async {
      await tester.runAsync(() async {
        final s = twoPictures();
        addTearDown(s.dispose);
        final rig = playbackRigOf(s);

        rig.playback.play(scope: PlaybackScope.activeCut);
        expect(rig.playback.isWaiting, isTrue, reason: '⛔premise');
        rig.setPlaybackMode(PlaybackMode.skipFrames);

        expect(rig.playback.isWaiting, isFalse);
        rig.playback.stop();
      });
    });
  });
}
