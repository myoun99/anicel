import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/brush_history_policy.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_edit_session_store.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/playback/frame_demand.dart';
import 'package:anicel/src/ui/playback/cut_frame_composite_cache.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';
import 'package:anicel/src/ui/playback/playback_prerender_scheduler.dart';

void main() {
  const canvasSize = CanvasSize(width: 8, height: 8);

  /// The walk at rest — or ten seconds gone: a walk that never rests is a
  /// failure the test SAYS, not one it hangs on.
  Future<void> rested(PlaybackPrerenderScheduler scheduler) => scheduler.idle
      .timeout(const Duration(seconds: 10), onTimeout: () {});

  BrushFrameKey frameKey(Cut cut, LayerId layerId, FrameId frameId) =>
      BrushFrameKey(
        projectId: const ProjectId('project'),
        trackId: const TrackId('track'),
        cutId: cut.id,
        layerId: layerId,
        frameId: frameId,
      );

  Cut cut({int duration = 4}) => Cut(
    id: const CutId('cut'),
    name: 'Cut',
    duration: duration,
    canvasSize: canvasSize,
    layers: [
      Layer(
        id: const LayerId('layer'),
        name: 'A',
        frames: [
          Frame(id: const FrameId('frame-a'), duration: 1, strokes: const []),
        ],
        timeline: {
          0: const TimelineExposure.drawing(FrameId('frame-a'), length: 1),
        },
      ),
    ],
  );

  ({
    BrushFrameStore store,
    CutFrameCompositeCache composites,
    BrushFrameEditingCoordinator coordinator,
  })
  fixture() {
    final store = BrushFrameStore();
    final coordinator = BrushFrameEditingCoordinator(
      initialFrameKey: frameKey(
        cut(),
        const LayerId('layer'),
        const FrameId('frame-a'),
      ),
      frameStore: store,
      sessionStore: BrushFrameEditSessionStore(
        canvasSize: canvasSize,
        tileSize: 4,
      ),
      historyPolicy: const BrushHistoryPolicy(),
    );
    coordinator.commitSourceStroke(
      sourceDabs: [
        BrushDab(
          center: CanvasPoint(x: 1, y: 1),
          color: 0xFF000000,
          size: 2,
          opacity: 1,
          flow: 1,
          hardness: 1,
          tipShape: BrushTipShape.round,
          pressure: 1,
          sequence: 0,
        ),
      ],
    );
    final composites = CutFrameCompositeCache(
      layerImages: LayerFrameImageCache(frameStore: store),
      frameStore: store,
      frameKeyOf: frameKey,
    );
    return (store: store, composites: composites, coordinator: coordinator);
  }

  /// A cut drawn on PAST its 尺: the timeline's runway takes frames like
  /// any other, so the authored extent (7) outruns the duration (4).
  Cut runwayCut() => Cut(
    id: const CutId('cut'),
    name: 'Cut',
    duration: 4,
    canvasSize: canvasSize,
    layers: [
      Layer(
        id: const LayerId('layer'),
        name: 'A',
        frames: [
          Frame(id: const FrameId('frame-a'), duration: 1, strokes: const []),
        ],
        timeline: {
          0: const TimelineExposure.drawing(FrameId('frame-a'), length: 1),
          6: const TimelineExposure.drawing(FrameId('frame-a'), length: 1),
        },
      ),
    ],
  );

  testWidgets('the warm reaches a drawing OUT on the runway, past the cut\'s '
      'own length', (tester) async {
    await tester.runAsync(() async {
      final f = fixture();
      final scheduler = PlaybackPrerenderScheduler(
        composites: f.composites,
        resolveCut: (_) => runwayCut(),
        idleDelay: Duration.zero,
      );

      scheduler.requestWarmCut(
        cutId: const CutId('cut'),
        aroundFrameIndex: 0,
      );
      await rested(scheduler);

      expect(
        f.composites.validCompositeOrNull(
          cut: runwayCut(),
          frameIndex: 6,
        ),
        isNotNull,
        reason: 'a frame the warm never visits misses in the cache forever, '
            'which is how a runway drawing stayed invisible while scrubbing '
            'and appeared only on release',
      );
      expect(scheduler.progress.value.total, 7);
      scheduler.dispose();
      f.composites.dispose();
    });
  });

  testWidgets('what a frame reads from OUTSIDE the cel store is filled '
      'before it composes — the hook answers first, and every frame it '
      'answered for is warmed after (a reference movie\'s decode)', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final f = fixture();
      final filled = <int>[];
      final scheduler = PlaybackPrerenderScheduler(
        composites: f.composites,
        resolveCut: (_) => cut(),
        idleDelay: Duration.zero,
        beforeCompose: (asked, frameIndex) async {
          await Future<void>.delayed(Duration.zero);
          expect(
            f.composites.validCompositeOrNull(
              cut: asked,
              frameIndex: frameIndex,
            ),
            isNull,
            reason: 'nothing is composed before the hook has answered',
          );
          filled.add(frameIndex);
        },
      );

      scheduler.requestWarmCut(
        cutId: const CutId('cut'),
        aroundFrameIndex: 0,
      );
      await rested(scheduler);

      expect(filled, isNotEmpty);
      for (final frame in filled) {
        expect(
          f.composites.validCompositeOrNull(
            cut: cut(),
            frameIndex: frame,
          ),
          isNotNull,
          reason: 'frame $frame was answered for, so it was warmed',
        );
      }
      scheduler.dispose();
      f.composites.dispose();
    });
  });

  testWidgets('warms every frame of the cut', (tester) async {
    await tester.runAsync(() async {
      final f = fixture();
      final scheduler = PlaybackPrerenderScheduler(
        composites: f.composites,
        resolveCut: (_) => cut(),
        idleDelay: Duration.zero,
      );

      scheduler.requestWarmCut(
        cutId: const CutId('cut'),
        aroundFrameIndex: 2,
      );
      await rested(scheduler);

      for (var index = 0; index < 4; index += 1) {
        expect(
          f.composites.validCompositeOrNull(
            cut: cut(),
            frameIndex: index,
          ),
          isNotNull,
          reason: 'frame $index should be warmed',
        );
      }
      expect(
        scheduler.progress.value,
        const PrerenderProgress(cached: 4, total: 4),
      );
      scheduler.dispose();
      f.composites.dispose();
    });
  });

  // I-22: every report re-reads the green bar over the whole window — at
  // the ten-minute floor every cut of the film — and a playhead crossing
  // into a warmed cut queued it and the next again, a report a frame.
  testWidgets('a report is a frame warmed — a pass over frames already warm '
      'reports once', (tester) async {
    await tester.runAsync(() async {
      final f = fixture();
      var warmed = 0;
      final scheduler = PlaybackPrerenderScheduler(
        composites: f.composites,
        resolveCut: (_) => cut(),
        afterFrameCached: () => warmed += 1,
        idleDelay: Duration.zero,
      );
      var reports = 0;
      scheduler.progress.addListener(() => reports += 1);
      void warm() => scheduler.requestWarmCut(
        cutId: const CutId('cut'),
      );

      warm();
      await rested(scheduler);
      // The runway's empty frames share one picture, so fewer than four.
      expect(warmed, greaterThan(1), reason: 'the premise: frames to warm');
      expect(
        reports,
        greaterThanOrEqualTo(1 + warmed),
        reason: 'the request, then every frame it warmed',
      );

      reports = 0;
      final cold = warmed;
      warm();
      await rested(scheduler);
      expect(warmed, cold, reason: 'the second pass warmed nothing');
      expect(reports, 1 + 1, reason: 'the request, then the pass once');
      expect(
        scheduler.progress.value,
        const PrerenderProgress(cached: 4, total: 4),
      );
      scheduler.dispose();
      f.composites.dispose();
    });
  });

  testWidgets('edit activity pauses warming until the idle delay elapses', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final f = fixture();
      final scheduler = PlaybackPrerenderScheduler(
        composites: f.composites,
        resolveCut: (_) => cut(),
        idleDelay: const Duration(hours: 1),
      );

      scheduler.notifyEditActivity();
      scheduler.requestWarmCut(
        cutId: const CutId('cut'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(scheduler.progress.value.cached, 0);
      expect(
        f.composites.validCompositeOrNull(
          cut: cut(),
          frameIndex: 0,
        ),
        isNull,
      );

      scheduler.dispose();
      await rested(scheduler);
      f.composites.dispose();
    });
  });

  testWidgets('a new request cancels the previous generation', (tester) async {
    await tester.runAsync(() async {
      final f = fixture();
      final scheduler = PlaybackPrerenderScheduler(
        composites: f.composites,
        resolveCut: (_) => cut(duration: 40),
        idleDelay: Duration.zero,
      );

      scheduler.requestWarmCut(
        cutId: const CutId('cut'),
      );
      scheduler.follow(
        StandingDemand(
          cutId: const CutId('cut'),
          frameCount: 2,
          around: 0,
          resolveCut: (_) => cut(duration: 40),
        ),
      );
      await rested(scheduler);

      expect(scheduler.progress.value.total, 2);
      expect(scheduler.progress.value.isComplete, isTrue);
      scheduler.dispose();
      f.composites.dispose();
    });
  });

  testWidgets('an open input hold gates warming even past the idle delay '
      '(R13-3: pen-down stand-down)', (tester) async {
    await tester.runAsync(() async {
      final f = fixture();
      final scheduler = PlaybackPrerenderScheduler(
        composites: f.composites,
        resolveCut: (_) => cut(),
        idleDelay: Duration.zero,
      );

      scheduler.beginInputHold();
      scheduler.requestWarmCut(
        cutId: const CutId('cut'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(
        scheduler.progress.value.cached,
        0,
        reason: 'a live stroke must fully stand warming down',
      );
      expect(
        f.composites.validCompositeOrNull(
          cut: cut(),
          frameIndex: 0,
        ),
        isNull,
      );

      scheduler.endInputHold();
      await rested(scheduler);

      expect(scheduler.progress.value.isComplete, isTrue);
      expect(
        f.composites.validCompositeOrNull(
          cut: cut(),
          frameIndex: 0,
        ),
        isNotNull,
        reason: 'released holds resume the SAME queue to completion',
      );
      scheduler.dispose();
      f.composites.dispose();
    });
  });

  testWidgets('an invalidated frame re-warms with fresh content', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final f = fixture();
      final scheduler = PlaybackPrerenderScheduler(
        composites: f.composites,
        resolveCut: (_) => cut(),
        idleDelay: Duration.zero,
      );

      scheduler.requestWarmCut(
        cutId: const CutId('cut'),
      );
      await rested(scheduler);
      final before = f.composites.validCompositeOrNull(
        cut: cut(),
        frameIndex: 0,
      );

      // Edit: caches invalidate via revision, then re-warm.
      f.coordinator.commitSourceStroke(
        sourceDabs: [
          BrushDab(
            center: CanvasPoint(x: 5, y: 5),
            color: 0xFF000000,
            size: 2,
            opacity: 1,
            flow: 1,
            hardness: 1,
            tipShape: BrushTipShape.round,
            pressure: 1,
            sequence: 0,
          ),
        ],
      );
      expect(
        f.composites.validCompositeOrNull(
          cut: cut(),
          frameIndex: 0,
        ),
        isNull,
      );

      scheduler.requestWarmCut(
        cutId: const CutId('cut'),
      );
      await rested(scheduler);

      final after = f.composites.validCompositeOrNull(
        cut: cut(),
        frameIndex: 0,
      );
      expect(after, isNotNull);
      expect(identical(before, after), isFalse);
      scheduler.dispose();
      f.composites.dispose();
    });
  });

  group('#31 lookahead — the NEXT cut rides the same run', () {
    // Duration 2, but a drawing parked out at index 3: the lookahead must
    // obey the SAME warm law as the active cut ([cutWarmFrameCount], the
    // authored extent) — a next cut whose runway drawing never warms would
    // re-create the exact asymmetry B1 closed.
    Cut nextCut() => Cut(
      id: const CutId('cut-b'),
      name: 'Next',
      duration: 2,
      canvasSize: canvasSize,
      layers: [
        Layer(
          id: const LayerId('layer-b'),
          name: 'B',
          frames: [
            Frame(id: const FrameId('frame-b'), duration: 1, strokes: const []),
          ],
          timeline: {
            0: const TimelineExposure.drawing(FrameId('frame-b'), length: 1),
            3: const TimelineExposure.drawing(FrameId('frame-b'), length: 1),
          },
        ),
      ],
    );

    BitmapSurface inkedSurface() {
      final pixels = Uint8List(4 * 4 * 4);
      for (var i = 0; i < pixels.length; i += 1) {
        pixels[i] = (i * 31 + 7) & 0xFF;
      }
      return BitmapSurface(
        canvasSize: canvasSize,
        tileSize: 4,
        tiles: {
          TileCoord(x: 0, y: 0): BitmapTile(
            size: 4,
            pixels: pixels,
          ),
        },
      );
    }

    testWidgets('warms the next cut start-to-end, BEHIND every active '
        'frame', (tester) async {
      await tester.runAsync(() async {
        final f = fixture();
        // The next cut's content enters the shared store the way an open
        // does — a baked donation under ITS key.
        f.store.storeBakedSurface(
          frameKey(nextCut(), const LayerId('layer-b'), const FrameId('frame-b')),
          inkedSurface(),
        );
        // The order pictures were MADE in: the hook answers before each.
        final made = <String>[];
        final scheduler = PlaybackPrerenderScheduler(
          composites: f.composites,
          resolveCut: (id) => id == const CutId('cut-b') ? nextCut() : cut(),
          idleDelay: Duration.zero,
          beforeCompose: (asked, _) async => made.add(asked.id.value),
        );

        scheduler.requestWarmCut(
          cutId: const CutId('cut'),
          aroundFrameIndex: 2,
          followedByCutId: const CutId('cut-b'),
        );
        await rested(scheduler);

        for (var index = 0; index < 4; index += 1) {
          expect(
            f.composites.validCompositeOrNull(
              cut: nextCut(),
              frameIndex: index,
            ),
            isNotNull,
            reason: 'next-cut frame $index warms on the same run — index 3 '
                'is the RUNWAY drawing, covered because the lookahead reads '
                'the same warm law as the active cut',
          );
        }
        expect(
          scheduler.progress.value,
          const PrerenderProgress(cached: 8, total: 8),
          reason: '4 active + 4 next (duration 2, authored extent 4)',
        );
        final firstNext = made.indexOf('cut-b');
        expect(firstNext, isNot(-1));
        expect(made.sublist(0, firstNext), isNotEmpty);
        expect(
          made.sublist(firstNext).contains('cut'),
          isFalse,
          reason: 'PRIORITY: every active-cut frame precedes the first '
              'next-cut frame — the lookahead never steals the budget or '
              'the thread from the cut being edited',
        );
        scheduler.dispose();
        f.composites.dispose();
      });
    });

    testWidgets('a self or unresolvable lookahead adds nothing',
        (tester) async {
      await tester.runAsync(() async {
        final f = fixture();
        final scheduler = PlaybackPrerenderScheduler(
          composites: f.composites,
          resolveCut: (id) => id == const CutId('cut') ? cut() : null,
          idleDelay: Duration.zero,
        );

        scheduler.requestWarmCut(
          cutId: const CutId('cut'),
          followedByCutId: const CutId('cut'),
        );
        await rested(scheduler);
        expect(
          scheduler.progress.value.total,
          4,
          reason: 'a cut must not warm itself twice through the lookahead',
        );

        scheduler.requestWarmCut(
          cutId: const CutId('cut'),
          followedByCutId: const CutId('gone'),
        );
        await rested(scheduler);
        expect(
          scheduler.progress.value.total,
          4,
          reason: 'a deleted next cut degrades to no lookahead, not a crash',
        );
        scheduler.dispose();
        f.composites.dispose();
      });
    });
  });

  /// 유저 2026-10-08, the playback rework: 「1 재생누르면 바로 재생」 · 「4
  /// 허용치도 해결」 · 「통일할거 통일하면서 권장대로가자」. A run that plays is
  /// followed from the frame under its playhead, at once, and only as far as
  /// the allowance holds.
  group('a run that plays', () {
    const pictureBytes = 8 * 8 * 4;

    // Four frames, four pictures: each frame its own cel, so no two share a
    // composite and what was made says which frame was asked.
    Cut four() => Cut(
      id: const CutId('cut'),
      name: 'Cut',
      duration: 4,
      canvasSize: canvasSize,
      layers: [
        Layer(
          id: const LayerId('layer'),
          name: 'A',
          frames: [
            for (var index = 0; index < 4; index += 1)
              Frame(id: FrameId('f$index'), duration: 1, strokes: const []),
          ],
          timeline: {
            for (var index = 0; index < 4; index += 1)
              index: TimelineExposure.drawing(FrameId('f$index'), length: 1),
          },
        ),
      ],
    );

    var playhead = 0;
    setUp(() => playhead = 0);

    PlayingDemand run({int Function(Duration)? lead}) => PlayingDemand(
      totalFrames: 4,
      loops: () => true,
      playhead: () => playhead,
      picturesOf: (frame) => [(cut: four(), frameIndex: frame)],
      playlistFrameOf: (cutId, frameIndex) =>
          cutId == const CutId('cut') ? frameIndex : null,
      lead: lead,
    );

    List<bool> there(CutFrameCompositeCache composites) => [
      for (var frame = 0; frame < 4; frame += 1)
        composites.validCompositeOrNull(cut: four(), frameIndex: frame) !=
            null,
    ];

    testWidgets('🚨it is followed at once — the quiet window is for the hand '
        'that draws, and nothing draws under a run', (tester) async {
      await tester.runAsync(() async {
        final f = fixture();
        final scheduler = PlaybackPrerenderScheduler(
          composites: f.composites,
          resolveCut: (_) => four(),
          idleDelay: const Duration(hours: 1),
        );

        // The stroke or the seek just before play was pressed.
        scheduler.notifyEditActivity();
        scheduler.follow(run());
        await rested(scheduler);

        expect(there(f.composites), everyElement(isTrue));
        expect(
          scheduler.progress.value,
          const PrerenderProgress(cached: 4, total: 4),
        );
        scheduler.dispose();
        f.composites.dispose();
      });
    });

    testWidgets('the walk starts under the playhead and goes the way the '
        'run plays, round to the frame behind it', (tester) async {
      await tester.runAsync(() async {
        final f = fixture();
        final made = <int>[];
        var landings = 0;
        final scheduler = PlaybackPrerenderScheduler(
          composites: f.composites,
          resolveCut: (_) => four(),
          idleDelay: Duration.zero,
          beforeCompose: (_, frameIndex) async => made.add(frameIndex),
        );
        scheduler.landings.addListener(() => landings += 1);

        playhead = 2;
        scheduler.follow(run());
        expect(
          scheduler.progress.value,
          const PrerenderProgress(cached: 0, total: 4),
          reason: 'a new demand says at once how much is wanted — a run '
              'that renders first reads this the moment it begins',
        );
        await rested(scheduler);

        expect(made, [2, 3, 0, 1]);
        expect(landings, 4, reason: 'a landing is told once a picture');
        scheduler.dispose();
        f.composites.dispose();
      });
    });

    testWidgets('where the clock does not wait, a picture is started where '
        'the playhead will be when it lands', (tester) async {
      await tester.runAsync(() async {
        final f = fixture();
        final made = <int>[];
        final scheduler = PlaybackPrerenderScheduler(
          composites: f.composites,
          resolveCut: (_) => four(),
          idleDelay: Duration.zero,
          beforeCompose: (_, frameIndex) async => made.add(frameIndex),
        );

        final askedWith = <Duration>[];
        scheduler.follow(
          run(
            lead: (composeTime) {
              askedWith.add(composeTime);
              return 2;
            },
          ),
        );
        await rested(scheduler);

        expect(made, [2, 3, 0, 1], reason: 'two frames on, then the lap');
        expect(askedWith.first, Duration.zero, reason: 'nothing made yet');
        expect(
          askedWith.last,
          greaterThan(Duration.zero),
          reason: 'the lead is asked with how long a picture has been taking',
        );
        expect(askedWith.last, scheduler.composeTime);
        scheduler.dispose();
        f.composites.dispose();
      });
    });

    testWidgets('how long a picture takes is known from the first one', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final f = fixture();
        const slow = Duration(milliseconds: 40);
        final scheduler = PlaybackPrerenderScheduler(
          composites: f.composites,
          resolveCut: (_) => four(),
          idleDelay: Duration.zero,
          // What a frame reads from outside the cel store is part of what
          // making its picture takes.
          beforeCompose: (_, _) => Future<void>.delayed(slow),
        );
        expect(scheduler.composeTime, Duration.zero);

        scheduler.follow(
          PlayingDemand(
            totalFrames: 1,
            loops: () => true,
            playhead: () => 0,
            picturesOf: (frame) => [(cut: four(), frameIndex: frame)],
            playlistFrameOf: (_, frameIndex) => frameIndex,
          ),
        );
        await rested(scheduler);

        expect(
          scheduler.composeTime,
          greaterThanOrEqualTo(slow),
          reason: 'one picture made: the mean IS that one — a lead worked '
              'out from a fraction of it starts the next picture too late',
        );
        scheduler.dispose();
        f.composites.dispose();
      });
    });

    testWidgets('🚨it rests when no more fits, and walks on when the playhead '
        'does — each picture made once', (tester) async {
      await tester.runAsync(() async {
        final f = fixture();
        final room = _Room(f.composites, 2 * pictureBytes);
        final made = <int>[];
        final scheduler = PlaybackPrerenderScheduler(
          composites: f.composites,
          resolveCut: (_) => four(),
          room: room,
          idleDelay: Duration.zero,
          beforeCompose: (_, frameIndex) async => made.add(frameIndex),
        );
        room.demand = () => scheduler.demand;

        scheduler.follow(run());
        await rested(scheduler);
        expect(made, [0, 1], reason: 'two pictures fit');
        expect(there(f.composites), [true, true, false, false]);
        expect(
          scheduler.progress.value,
          const PrerenderProgress(cached: 2, total: 2),
          reason: 'what is held is the window: nothing in it is left to make',
        );
        expect(f.composites.estimatedBytes, 2 * pictureBytes);

        // One frame on: the frame that came into the window is made, out
        // of the room of the one that fell behind.
        playhead = 1;
        scheduler.wake();
        await rested(scheduler);
        expect(made, [0, 1, 2]);
        expect(there(f.composites), [false, true, true, false]);

        playhead = 2;
        scheduler.wake();
        await rested(scheduler);
        expect(
          made,
          [0, 1, 2, 3],
          reason: 'the window moved on with the playhead; it did not churn',
        );
        expect(there(f.composites), [false, false, true, true]);
        expect(f.composites.estimatedBytes, 2 * pictureBytes);
        scheduler.dispose();
        f.composites.dispose();
      });
    });

    testWidgets('while it fills, the walk says how many frames it expects '
        'to hold — every one wanted, or as many as the room has held so far', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final f = fixture();
        final room = _Room(f.composites, 2 * pictureBytes);
        final said = <PrerenderProgress>[];
        final scheduler = PlaybackPrerenderScheduler(
          composites: f.composites,
          resolveCut: (_) => four(),
          room: room,
          idleDelay: Duration.zero,
        );
        room.demand = () => scheduler.demand;
        scheduler.progress.addListener(
          () => said.add(scheduler.progress.value),
        );

        scheduler.follow(run());
        await rested(scheduler);

        expect(said, const [
          PrerenderProgress(cached: 0, total: 4),
          PrerenderProgress(cached: 1, total: 2),
          PrerenderProgress(cached: 2, total: 2),
        ]);
        scheduler.dispose();
        f.composites.dispose();
      });
    });

    testWidgets('the picture under the playhead is made whatever the room '
        '— a run that waits for it must not wait for good', (tester) async {
      await tester.runAsync(() async {
        final f = fixture();
        final room = _Room(f.composites, 0);
        final scheduler = PlaybackPrerenderScheduler(
          composites: f.composites,
          resolveCut: (_) => four(),
          room: room,
          idleDelay: Duration.zero,
        );
        room.demand = () => scheduler.demand;

        playhead = 1;
        scheduler.follow(run());
        await rested(scheduler);

        expect(there(f.composites), [false, true, false, false]);
        expect(
          scheduler.progress.value,
          const PrerenderProgress(cached: 1, total: 1),
          reason: 'and no other: for the next one there is no room',
        );
        scheduler.dispose();
        f.composites.dispose();
      });
    });

    testWidgets('a picture let go from under the playhead is made again — '
        'the frame the walk starts on is asked every time', (tester) async {
      await tester.runAsync(() async {
        final f = fixture();
        final scheduler = PlaybackPrerenderScheduler(
          composites: f.composites,
          resolveCut: (_) => four(),
          idleDelay: Duration.zero,
        );
        scheduler.follow(run());
        await rested(scheduler);
        expect(there(f.composites), everyElement(isTrue));

        // A memory warning's work: every picture goes.
        f.composites.enforceBudget(maxBytes: 0);
        expect(there(f.composites), everyElement(isFalse));

        scheduler.wake();
        await rested(scheduler);
        expect(there(f.composites), everyElement(isTrue));
        scheduler.dispose();
        f.composites.dispose();
      });
    });

    testWidgets('a playhead that moves on costs the walk a frame or two, not '
        'the window', (tester) async {
      await tester.runAsync(() async {
        final f = fixture();
        var asked = 0;
        final scheduler = PlaybackPrerenderScheduler(
          composites: f.composites,
          resolveCut: (_) => cut(duration: 40),
          idleDelay: Duration.zero,
        );
        scheduler.follow(
          PlayingDemand(
            totalFrames: 40,
            loops: () => true,
            playhead: () => playhead,
            picturesOf: (frame) {
              asked += 1;
              return [(cut: cut(duration: 40), frameIndex: frame)];
            },
            playlistFrameOf: (_, frameIndex) => frameIndex,
          ),
        );
        await rested(scheduler);
        expect(asked, greaterThanOrEqualTo(40), reason: 'the first walk');

        asked = 0;
        playhead = 1;
        scheduler.wake();
        await rested(scheduler);
        expect(
          asked,
          lessThanOrEqualTo(2),
          reason: 'the frame it stands on now, and the one that came into '
              'the window behind it',
        );
        scheduler.dispose();
        f.composites.dispose();
      });
    });

    testWidgets('what the walk has passed is taken as there until it is told '
        'the pictures changed — then it walks them again', (tester) async {
      await tester.runAsync(() async {
        final f = fixture();
        final scheduler = PlaybackPrerenderScheduler(
          composites: f.composites,
          resolveCut: (_) => four(),
          idleDelay: Duration.zero,
        );
        scheduler.follow(run());
        await rested(scheduler);

        f.composites.invalidateWhereLayerFrame(
          layerId: const LayerId('layer'),
          frameId: const FrameId('f2'),
        );
        expect(there(f.composites), [true, true, false, true]);

        scheduler.wake(fromTheStart: true);
        await rested(scheduler);
        expect(there(f.composites), everyElement(isTrue));
        scheduler.dispose();
        f.composites.dispose();
      });
    });

    testWidgets('a picture whose compose throws is not waited for, and is '
        'not paid for twice', (tester) async {
      await tester.runAsync(() async {
        final store = BrushFrameStore();
        final composites = _ThrowsAt(
          1,
          layerImages: LayerFrameImageCache(frameStore: store),
          frameStore: store,
          frameKeyOf: frameKey,
        );
        final reported = <Object>[];
        final previous = FlutterError.onError;
        FlutterError.onError = (details) => reported.add(details.exception);
        addTearDown(() => FlutterError.onError = previous);
        final scheduler = PlaybackPrerenderScheduler(
          composites: composites,
          resolveCut: (_) => four(),
          idleDelay: Duration.zero,
        );

        scheduler.follow(run());
        await rested(scheduler);
        // ⛔Handed back BEFORE anything is expected: a failed expectation is
        // reported through this same door, and a collector left on it
        // swallows the failure — the pin could not fail.
        FlutterError.onError = previous;

        expect(there(composites), [true, false, true, true]);
        expect(reported, hasLength(1), reason: 'the failure is said, once');
        expect(
          scheduler.has([(cut: four(), frameIndex: 1)]),
          isTrue,
          reason: 'nothing waits for a picture that cannot be made',
        );
        expect(
          scheduler.progress.value,
          const PrerenderProgress(cached: 4, total: 4),
          reason: 'one frame\'s failure is one frame\'s: the walk went on',
        );

        scheduler.wake(fromTheStart: true);
        await rested(scheduler);
        expect(composites.thrown, 1, reason: 'the same content is not retried');
        scheduler.dispose();
        composites.dispose();
      });
    });
  });
}

/// The room a test gives the warmer: [bytes] of composites, kept by the
/// cache's own law against whatever the warmer follows.
class _Room implements PictureRoom {
  _Room(this.composites, this.bytes);

  final CutFrameCompositeCache composites;

  @override
  final int bytes;

  FrameDemand? Function() demand = () => null;

  @override
  bool makeRoomFor({required int bytes, required int step}) =>
      composites.enforceBudget(
        maxBytes: this.bytes - bytes,
        stepOf: demand()?.stepOf,
        laterThan: step,
      );
}

/// A composite cache whose frame [frameIndex] cannot be made.
class _ThrowsAt extends CutFrameCompositeCache {
  _ThrowsAt(
    this.frameIndex, {
    required super.layerImages,
    required super.frameStore,
    required super.frameKeyOf,
  });

  final int frameIndex;
  int thrown = 0;

  @override
  Future<ui.Image?> prepareCompositeInterruptible({
    required Cut cut,
    required int frameIndex,
    required bool Function() shouldAbort,
  }) {
    if (frameIndex == this.frameIndex) {
      thrown += 1;
      throw StateError('the cel of frame $frameIndex cannot be read');
    }
    return super.prepareCompositeInterruptible(
      cut: cut,
      frameIndex: frameIndex,
      shouldAbort: shouldAbort,
    );
  }
}
