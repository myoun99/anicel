import 'dart:typed_data';

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
import 'package:anicel/src/models/playback_quality.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_edit_session_store.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/ui/playback/cut_frame_composite_cache.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';
import 'package:anicel/src/ui/playback/playback_prerender_scheduler.dart';

void main() {
  const canvasSize = CanvasSize(width: 8, height: 8);

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
          0: TimelineExposure.drawing(const FrameId('frame-a'), length: 1),
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
      historyPolicy: const BrushHistoryPolicy(
        userUndoLimit: 8,
        deferredBakeRatio: 0,
      ),
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
          0: TimelineExposure.drawing(const FrameId('frame-a'), length: 1),
          6: TimelineExposure.drawing(const FrameId('frame-a'), length: 1),
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
        quality: PlaybackQuality.quarter,
        aroundFrameIndex: 0,
      );
      await scheduler.idle;

      expect(
        f.composites.validCompositeOrNull(
          cut: runwayCut(),
          frameIndex: 6,
          quality: PlaybackQuality.quarter,
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
        quality: PlaybackQuality.quarter,
        aroundFrameIndex: 2,
      );
      await scheduler.idle;

      for (var index = 0; index < 4; index += 1) {
        expect(
          f.composites.validCompositeOrNull(
            cut: cut(),
            frameIndex: index,
            quality: PlaybackQuality.quarter,
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
        quality: PlaybackQuality.quarter,
      );
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(scheduler.progress.value.cached, 0);
      expect(
        f.composites.validCompositeOrNull(
          cut: cut(),
          frameIndex: 0,
          quality: PlaybackQuality.quarter,
        ),
        isNull,
      );

      scheduler.dispose();
      await scheduler.idle;
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
        quality: PlaybackQuality.quarter,
      );
      scheduler.requestWarmFrames(
        frames: const [(CutId('cut'), 0), (CutId('cut'), 1)],
        quality: PlaybackQuality.quarter,
      );
      await scheduler.idle;

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
        quality: PlaybackQuality.quarter,
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
          quality: PlaybackQuality.quarter,
        ),
        isNull,
      );

      scheduler.endInputHold();
      await scheduler.idle;

      expect(scheduler.progress.value.isComplete, isTrue);
      expect(
        f.composites.validCompositeOrNull(
          cut: cut(),
          frameIndex: 0,
          quality: PlaybackQuality.quarter,
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
        quality: PlaybackQuality.quarter,
      );
      await scheduler.idle;
      final before = f.composites.validCompositeOrNull(
        cut: cut(),
        frameIndex: 0,
        quality: PlaybackQuality.quarter,
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
          quality: PlaybackQuality.quarter,
        ),
        isNull,
      );

      scheduler.requestWarmCut(
        cutId: const CutId('cut'),
        quality: PlaybackQuality.quarter,
      );
      await scheduler.idle;

      final after = f.composites.validCompositeOrNull(
        cut: cut(),
        frameIndex: 0,
        quality: PlaybackQuality.quarter,
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
            coord: TileCoord(x: 0, y: 0),
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
        final resolved = <String>[];
        var recording = false;
        final scheduler = PlaybackPrerenderScheduler(
          composites: f.composites,
          resolveCut: (id) {
            if (recording) {
              resolved.add(id.value);
            }
            return id == const CutId('cut-b') ? nextCut() : cut();
          },
          idleDelay: Duration.zero,
        );

        scheduler.requestWarmCut(
          cutId: const CutId('cut'),
          quality: PlaybackQuality.quarter,
          aroundFrameIndex: 2,
          followedByCutId: const CutId('cut-b'),
        );
        // requestWarmCut resolves synchronously while building the order;
        // everything after this line is the RUN's own resolution sequence.
        recording = true;
        await scheduler.idle;

        for (var index = 0; index < 4; index += 1) {
          expect(
            f.composites.validCompositeOrNull(
              cut: nextCut(),
              frameIndex: index,
              quality: PlaybackQuality.quarter,
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
        final firstNext = resolved.indexOf('cut-b');
        expect(firstNext, isNot(-1));
        expect(
          resolved.sublist(firstNext).contains('cut'),
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
          quality: PlaybackQuality.quarter,
          followedByCutId: const CutId('cut'),
        );
        await scheduler.idle;
        expect(
          scheduler.progress.value.total,
          4,
          reason: 'a cut must not warm itself twice through the lookahead',
        );

        scheduler.requestWarmCut(
          cutId: const CutId('cut'),
          quality: PlaybackQuality.quarter,
          followedByCutId: const CutId('gone'),
        );
        await scheduler.idle;
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
}
