import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/playback_mode.dart';
import 'package:anicel/src/models/playback_quality.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/playback/frame_demand.dart';
import 'package:anicel/src/ui/canvas/canvas_look.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/playback/canvas_playback_controller.dart'
    show PlaybackScope;
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';
import 'package:anicel/src/ui/session/playback_rig.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/draw_on_current_frame.dart';

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

  // One picture: a cut's composite, and the canvas's image of a cel inked over
  // it — the canvas is one tile, so both are its size.
  const picture = 256 * 256 * 4;

  /// [twoPictures]' cut, its two cels not inked yet.
  EditorSessionManager twoBareCels() => EditorSessionManager(
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
              canvasSize: const CanvasSize(width: 256, height: 256),
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

  /// A session on one cut of four frames and TWO pictures: a cel on frames
  /// 0..1, another on 2..3 — each inked, so either screen has a picture to
  /// make of it.
  ///
  /// ⚠️The ink stays INSIDE the canvas: a dab past its edge puts the cel on
  /// the pasteboard's tiles, and the canvas's image of it is then the size
  /// of those tiles — no longer the one picture's worth [picture] counts.
  EditorSessionManager twoPictures() {
    final s = twoBareCels();
    for (final cel in ['a', 'b']) {
      inkCel(
        s,
        s.brushFrameKeyForCut(
          s.requireActiveCut,
          const LayerId('layer'),
          FrameId(cel),
        ),
        canvasSize: const CanvasSize(width: 256, height: 256),
        at: CanvasPoint(x: 128, y: 128),
        size: 254,
        tipShape: BrushTipShape.square,
      );
    }
    return s;
  }

  /// The warmer at rest — or ten seconds gone, which the test then says.
  Future<void> rested(PlaybackRig rig) => rig.prerenderScheduler.idle.timeout(
    const Duration(seconds: 10),
    onTimeout: () {},
  );

  /// Whether frame [frameIndex]'s picture is there, as the screen it is
  /// shown on counts it.
  bool held(EditorSessionManager s, int frameIndex) => s
      .playbackRig
      .canvasPictures
      .has((cut: s.activeCutOrNull!, frameIndex: frameIndex));

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
  // The same laws on both screens a run is shown on: the canvas, from its
  // own pictures, for a cut played alone — through the camera or not
  // (playback-plays-the-screen-material) — and the track stack the whole
  // film still plays on, from composites.
  for (final scope in [PlaybackScope.activeCut, PlaybackScope.allCuts]) {
    group(
      scope == PlaybackScope.activeCut
          ? 'a cut played alone, shown on the canvas'
          : 'the whole film, shown on the track stack',
      () {
        testWidgets('🚨the playhead moving on is what wakes the warmer: under an '
            'allowance of one picture, the picture held follows a seek', (
          tester,
        ) async {
          await tester.runAsync(() async {
            final s = twoPictures();
            addTearDown(s.dispose);
            final rig = playbackRigOf(s);
            rig.playbackCache.debugSetPlaybackCacheBudgetBytes(picture);

            rig.playback.play(scope: scope);
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
            rig.playback.play(scope: scope);
            waited.insert(0, rig.playback.isWaiting);
            await rested(rig);
            return waited;
          }

          testWidgets('🚨every picture (the default): the run waits on its first '
              'frame until THAT picture is made, and then goes', (tester) async {
            await tester.runAsync(() async {
              final s = twoPictures();
              addTearDown(s.dispose);
              final rig = playbackRigOf(s);
              rig.playbackCache.debugSetPlaybackCacheBudgetBytes(16 * picture);
              // Read as waitedAtEachChange reads, with whether frame 0's
              // picture is there beside it: the pictures after it are made
              // beside it (asked for ahead) and land in either order.
              final seen = <({bool waited, bool there})>[];
              ({bool waited, bool there}) now() =>
                  (waited: rig.playback.isWaiting, there: held(s, 0));
              rig.prerenderScheduler.changes.addListener(() => seen.add(now()));
              rig.playback.play(scope: scope);
              seen.insert(0, now());
              await rested(rig);

              final made = seen.indexWhere((at) => at.there);
              expect(made, greaterThan(0), reason: 'at the press, nothing is made');
              expect(
                [for (final at in seen.take(made)) at.waited],
                everyElement(isTrue),
                reason: 'it waits while its first picture is not there',
              );
              expect(
                seen[made].waited,
                isFalse,
                reason: 'and goes the moment it is — the second picture is not '
                    'waited for, nor the rest',
              );
              expect(playbackRigOf(s).playback.isWaiting, isFalse);
              expect(
                playbackRigOf(s).demand!.leadFor(const Duration(seconds: 1)),
                isNull,
                reason: 'the clock waits: the walk starts where the run would '
                    'wait, not where a picture would land',
              );
              expect(
                playbackRigOf(s).playbackCache.playbackReadyRuns(0, 4),
                [(startIndex: 0, endIndexExclusive: 4)],
                reason: 'the ruler\'s bar counts what the screen shows',
              );
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

          /// 유저 2026-10-15, F-365-Q1 「직전 프레임에 서서 기다린다」: the run
          /// stands before a frame that is not there and waits for it — so
          /// that picture is made whatever the room, or a picture bigger
          /// than half the line stands the run for good (F-365: a 47MB cut
          /// head under a 64MB line).
          for (final mode in [
            PlaybackMode.everyPicture,
            PlaybackMode.renderFirst,
          ]) {
            testWidgets('🚨${mode.name}: under a line of one picture, a run on '
                'the last frame of one picture has the next one made too — '
                'it is what the run will stand before and wait for', (
              tester,
            ) async {
              await tester.runAsync(() async {
                final s = twoPictures();
                addTearDown(s.dispose);
                final rig = playbackRigOf(s)..setPlaybackMode(mode);
                rig.playbackCache.debugSetPlaybackCacheBudgetBytes(picture);

                rig.playback.play(scope: scope, startGlobalFrame: 1);
                await rested(rig);

                expect(
                  [held(s, 1), held(s, 2)],
                  [true, true],
                  reason: 'frame 2 is a picture over the line, and the one '
                      'the run waits for when its clock reaches it',
                );
                expect(rig.playback.isWaiting, isFalse);
                rig.playback.stop();
              });
            });
          }

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

              rig.playback.play(scope: scope);
              expect(rig.playback.isWaiting, isTrue, reason: '⛔premise');
              rig.setPlaybackMode(PlaybackMode.skipFrames);

              expect(rig.playback.isWaiting, isFalse);
              rig.playback.stop();
            });
          });
        });
      },
    );
  }

  /// The screen changing what it shows a frame from — the whole film
  /// stopped, the canvas drawing at another level.
  group('when the screen changes', () {
    testWidgets('🚨the whole film plays from the canvas\'s own pictures — '
        'nothing is made for it that the canvas does not hold', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final s = twoPictures();
        addTearDown(s.dispose);
        final rig = playbackRigOf(s);
        rig.playbackCache.debugSetPlaybackCacheBudgetBytes(4 * picture);
        rig.playback.play(scope: PlaybackScope.allCuts);
        await rested(rig);
        expect([held(s, 0), held(s, 2)], [true, true], reason: '⛔premise');
        rig.playback.stop();

        await rested(rig);
        expect(
          [held(s, 0), held(s, 2)],
          [true, true],
          reason: 'the canvas shows a frame from what the film made',
        );
        expect(
          s.renderCaches.layerFrameImageCache.estimatedBytes,
          2 * picture,
          reason: 'the two cels\' images, and nothing beside them. ↩️The '
              'film made a composite of each of its frames too, until '
              '2026-10-10',
        );

        // An export run borrows half the line.
        rig.playbackCache.lend(2 * picture);
        expect(
          [held(s, 0), held(s, 2)],
          [true, true],
          reason: 'what is left of the line holds them',
        );
        rig.playbackCache.lend(0);
      });
    });

    testWidgets('🚨the canvas drawing at another level, the warmer makes the '
        'images it will ask for', (tester) async {
      await tester.runAsync(() async {
        final s = twoPictures();
        addTearDown(s.dispose);
        final rig = playbackRigOf(s);
        rig.playback.play(scope: PlaybackScope.activeCut);
        await rested(rig);
        expect(held(s, 0), isTrue, reason: '⛔premise');

        s.renderCaches.canvasLook.value = CanvasLook(
          view: CanvasViewport(zoom: 0.4),
          devicePixelRatio: 1,
        );
        expect(held(s, 0), isFalse, reason: 'nothing is made at half yet');
        await rested(rig);
        expect([held(s, 0), held(s, 2)], [true, true]);
        rig.playback.stop();
      });
    });

    testWidgets('🚨seen through a camera that zooms out in the middle of the '
        'cut, each frame is made at the level the camera shows it at', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final s = twoPictures();
        addTearDown(s.dispose);
        final rig = playbackRigOf(s);
        final cut = s.requireActiveCut;
        // Frames 0..1 at the camera's own size, 2..3 at 40% of it.
        s.renderCaches.canvasLook.value = CanvasLook(
          view: CanvasViewport(),
          devicePixelRatio: 1,
          camera: (
            poseOf: (cut, frame) => CameraPose(
              center: CanvasPoint(x: 128, y: 128),
              zoom: frame < 2 ? 1 : 0.4,
            ),
            frameSize: cut.canvasSize,
          ),
        );
        rig.playback.play(scope: PlaybackScope.activeCut);
        await rested(rig);

        LayerFrameImage? imageOf(String cel, PlaybackQuality level) =>
            s.renderCaches.layerFrameImageCache.peek(
              s.brushFrameKeyForCut(
                cut,
                const LayerId('layer'),
                FrameId(cel),
              ),
              level,
              canvasSize: cut.canvasSize,
              sourceEffects: const [],
              inkSuffices: true,
            );
        expect([held(s, 0), held(s, 2)], [true, true]);
        expect(
          [
            imageOf('a', PlaybackQuality.full) != null,
            imageOf('b', PlaybackQuality.half) != null,
          ],
          [true, true],
          reason: 'each cel at the level of the frames that show it',
        );
        expect(
          [
            imageOf('a', PlaybackQuality.half) != null,
            imageOf('b', PlaybackQuality.full) != null,
          ],
          [false, false],
          reason: 'and at no other: a cel made at another level is a second '
              'picture of it',
        );
        rig.playback.stop();
      });
    });

    testWidgets('a screen\'s pins are inside the line — the room is the line '
        'less what is lent, whatever plays', (tester) async {
      await tester.runAsync(() async {
        final s = twoPictures();
        addTearDown(s.dispose);
        final rig = playbackRigOf(s);
        rig.playbackCache.debugSetPlaybackCacheBudgetBytes(4 * picture);
        await rig.canvasPictures.make(
          (cut: s.requireActiveCut, frameIndex: 0),
          shouldAbort: () => false,
        );
        s.renderCaches.layerFrameImageCache.retainPin(
          s.brushFrameKeyForCut(
            s.requireActiveCut,
            const LayerId('layer'),
            const FrameId('a'),
          ),
          PlaybackQuality.full,
        );
        expect(
          s.renderCaches.layerFrameImageCache.pinnedBytes,
          picture,
          reason: '⛔premise: a screen holds one picture',
        );

        expect(rig.playbackCache.bytes, 4 * picture);
        rig.playback.play(scope: PlaybackScope.allCuts);
        expect(
          rig.playbackCache.bytes,
          4 * picture,
          reason: 'the whole film plays from the same pictures: nothing '
              'comes off the line for it. ↩️It played from composites, and '
              'the canvas\'s pins came off their room (until 2026-10-10)',
        );
        rig.playback.stop();
      });
    });
  });
}
