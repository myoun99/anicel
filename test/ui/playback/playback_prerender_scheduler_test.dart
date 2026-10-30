import 'dart:async';
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
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_edit_session_store.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/playback/frame_demand.dart';
import 'package:anicel/src/services/cut_frame_composite_plan.dart'
    show resolveExposedFrameAt;
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart'
    show CanvasLayerImageRequest, CanvasStackRow;
import 'package:anicel/src/ui/playback/frame_picture_gpu.dart';
import 'package:anicel/src/models/rgba_image_bytes.dart';
import 'package:anicel/src/ui/playback/frame_picture_store.dart';
import 'package:anicel/src/ui/playback/frame_pictures.dart';
import 'package:anicel/src/ui/playback/stacked_frame_picture.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';
import 'package:anicel/src/ui/playback/playback_prerender_scheduler.dart';

import '../../helpers/cels_kept_in_a_file.dart';
import '../../helpers/draw_on_current_frame.dart';
import '../../helpers/poll_until.dart';

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
          0: const TimelineExposure.drawing(FrameId('frame-a'), length: 1),
        },
      ),
    ],
  );

  /// What a frame of [cut] draws: one image per layer showing a cel there.
  List<CanvasLayerImageRequest> rowsOf(Cut cut, int frameIndex) => [
    for (final layer in cut.layers)
      if (resolveExposedFrameAt(layer, frameIndex) case final frame?)
        CanvasLayerImageRequest(
          frameKey: frameKey(cut, layer.id, frame.id),
          opacity: 1,
        ),
  ];

  /// The screen's pictures over [layerImages]: each frame one picture of
  /// its rows, on its paper — and nothing ghosting over it.
  FramePictures picturesOver(
    LayerFrameImageCache layerImages, {
    FramePictureGpu? gpu,
  }) {
    final store = FramePictureStore<FramePictureKey>(gpu: gpu);
    addTearDown(store.dispose);
    return FramePictures(
      store: store,
      layerImages: layerImages,
      stackOf: (picture) => [
        if (picture.ghosts == FrameGhosts.none)
          for (final row in rowsOf(picture.cut, picture.frameIndex))
            CompositeLeaf<CanvasStackRow>(row),
      ],
      pageOf: (picture) => (
        canvasSize: picture.cut.canvasSize,
        pasteboardReach: PasteboardReach.whole,
        paintPaper: picture.paintPaper,
        paperBackground: ProjectBackground.defaultBackground,
      ),
    );
  }

  /// The picture frame [frameIndex] of [cut] shows, or null while it is not
  /// made.
  ui.Image? shownAt(FramePictures pictures, Cut cut, int frameIndex) =>
      pictures.store
          .peek(
            pictures.keyOf((
              cut: cut,
              frameIndex: frameIndex,
              paintPaper: true,
              ghosts: FrameGhosts.none,
            )),
          )
          ?.image;

  /// A cel's pixels as an open donates them — baked, under a key no
  /// coordinator drew on.
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

  ({
    BrushFrameStore store,
    LayerFrameImageCache layerImages,
    FramePictures pictures,
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
    final layerImages = LayerFrameImageCache(frameStore: store);
    return (
      store: store,
      layerImages: layerImages,
      pictures: picturesOver(layerImages),
      coordinator: coordinator,
    );
  }

  /// A cut drawn on PAST its 尺: the timeline's runway takes frames like
  /// any other, so the authored extent (7) outruns the duration (4). The
  /// runway's cel is its own — frame 0's cel out there would be made by
  /// frame 0, and say nothing of whether the warm reached the runway.
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
          Frame(id: const FrameId('frame-r'), duration: 1, strokes: const []),
        ],
        timeline: {
          0: const TimelineExposure.drawing(FrameId('frame-a'), length: 1),
          6: const TimelineExposure.drawing(FrameId('frame-r'), length: 1),
        },
      ),
    ],
  );

  testWidgets('the warm reaches a drawing OUT on the runway, past the cut\'s '
      'own length', (tester) async {
    await tester.runAsync(() async {
      final f = fixture();
      f.store.storeBakedSurface(
        frameKey(runwayCut(), const LayerId('layer'), const FrameId('frame-r')),
        inkedSurface(),
      );
      expect(
        f.pictures.has((
          cut: runwayCut(),
          frameIndex: 6,
          paintPaper: true,
          ghosts: FrameGhosts.none,
        )),
        isFalse,
        reason: '⛔premise: the runway has a picture to make',
      );
      final scheduler = PlaybackPrerenderScheduler(
        pictures: f.pictures,
        resolveCut: (_) => runwayCut(),
        idleDelay: Duration.zero,
      );

      scheduler.requestWarmCut(
        cutId: const CutId('cut'),
        aroundFrameIndex: 0,
      );
      await patiently(scheduler.idle);

      expect(
        shownAt(f.pictures, runwayCut(), 6),
        isNotNull,
        reason: 'a frame the warm never visits misses in the cache forever, '
            'which is how a runway drawing stayed invisible while scrubbing '
            'and appeared only on release',
      );
      expect(scheduler.progress.value.total, 7);
      scheduler.dispose();
      f.layerImages.dispose();
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
        pictures: f.pictures,
        resolveCut: (_) => cut(),
        idleDelay: Duration.zero,
        beforeCompose: (asked, frameIndex) async {
          await Future<void>.delayed(Duration.zero);
          expect(
            shownAt(f.pictures, asked, frameIndex),
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
      await patiently(scheduler.idle);

      expect(filled, isNotEmpty);
      for (final frame in filled) {
        expect(
          shownAt(f.pictures, cut(), frame),
          isNotNull,
          reason: 'frame $frame was answered for, so it was warmed',
        );
      }
      scheduler.dispose();
      f.layerImages.dispose();
    });
  });

  testWidgets('warms every frame of the cut', (tester) async {
    await tester.runAsync(() async {
      final f = fixture();
      final scheduler = PlaybackPrerenderScheduler(
        pictures: f.pictures,
        resolveCut: (_) => cut(),
        idleDelay: Duration.zero,
      );

      expect(
        f.pictures.has((
          cut: cut(),
          frameIndex: 0,
          paintPaper: true,
          ghosts: FrameGhosts.none,
        )),
        isFalse,
        reason: '⛔premise: frame 0 has a picture to make',
      );
      scheduler.requestWarmCut(
        cutId: const CutId('cut'),
        aroundFrameIndex: 2,
      );
      await patiently(scheduler.idle);

      for (var index = 0; index < 4; index += 1) {
        expect(
          f.pictures.has((
            cut: cut(),
            frameIndex: index,
            paintPaper: true,
            ghosts: FrameGhosts.none,
          )),
          isTrue,
          reason: 'frame $index should be warmed — 1..3 show no cel: their '
              'page alone, there by definition',
        );
      }
      expect(
        scheduler.progress.value,
        const PrerenderProgress(cached: 4, total: 4),
      );
      scheduler.dispose();
      f.layerImages.dispose();
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
        pictures: f.pictures,
        resolveCut: (_) => cut(),
        idleDelay: Duration.zero,
      );
      scheduler.landings.addListener(() => warmed += 1);
      var reports = 0;
      scheduler.progress.addListener(() => reports += 1);
      void warm() => scheduler.requestWarmCut(
        cutId: const CutId('cut'),
      );

      warm();
      await patiently(scheduler.idle);
      // The empty frames are their page alone, there by definition: one to
      // make.
      expect(warmed, 1, reason: 'the premise: one picture to make');
      expect(
        reports,
        greaterThan(1),
        reason: 'the request, then what it warmed',
      );

      reports = 0;
      final cold = warmed;
      warm();
      await patiently(scheduler.idle);
      expect(warmed, cold, reason: 'the second pass warmed nothing');
      expect(reports, 1 + 1, reason: 'the request, then the pass once');
      expect(
        scheduler.progress.value,
        const PrerenderProgress(cached: 4, total: 4),
      );
      scheduler.dispose();
      f.layerImages.dispose();
    });
  });

  testWidgets('edit activity pauses warming until the idle delay elapses', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final f = fixture();
      final scheduler = PlaybackPrerenderScheduler(
        pictures: f.pictures,
        resolveCut: (_) => cut(),
        idleDelay: const Duration(hours: 1),
      );

      scheduler.notifyEditActivity();
      scheduler.requestWarmCut(
        cutId: const CutId('cut'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(
        scheduler.progress.value,
        const PrerenderProgress(cached: 0, total: 4),
        reason: 'held behind the quiet window, it says how much is wanted. '
            'A bar that read 「all made」 here would fall back the moment '
            'the warm began',
      );
      expect(
        shownAt(f.pictures, cut(), 0),
        isNull,
      );

      scheduler.dispose();
      await patiently(scheduler.idle);
      f.layerImages.dispose();
    });
  });

  testWidgets('a new request cancels the previous generation', (tester) async {
    await tester.runAsync(() async {
      final f = fixture();
      final scheduler = PlaybackPrerenderScheduler(
        pictures: f.pictures,
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
      await patiently(scheduler.idle);

      expect(scheduler.progress.value.total, 2);
      expect(scheduler.progress.value.isComplete, isTrue);
      scheduler.dispose();
      f.layerImages.dispose();
    });
  });

  testWidgets('an open input hold gates warming even past the idle delay '
      '(R13-3: pen-down stand-down)', (tester) async {
    await tester.runAsync(() async {
      final f = fixture();
      final scheduler = PlaybackPrerenderScheduler(
        pictures: f.pictures,
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
        shownAt(f.pictures, cut(), 0),
        isNull,
      );

      scheduler.endInputHold();
      await patiently(scheduler.idle);

      expect(scheduler.progress.value.isComplete, isTrue);
      expect(
        shownAt(f.pictures, cut(), 0),
        isNotNull,
        reason: 'released holds resume the SAME queue to completion',
      );
      scheduler.dispose();
      f.layerImages.dispose();
    });
  });

  testWidgets('an invalidated frame re-warms with fresh content', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final f = fixture();
      final scheduler = PlaybackPrerenderScheduler(
        pictures: f.pictures,
        resolveCut: (_) => cut(),
        idleDelay: Duration.zero,
      );

      scheduler.requestWarmCut(
        cutId: const CutId('cut'),
      );
      await patiently(scheduler.idle);
      final before = shownAt(f.pictures, cut(), 0);

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
        shownAt(f.pictures, cut(), 0),
        isNull,
      );

      scheduler.requestWarmCut(
        cutId: const CutId('cut'),
      );
      await patiently(scheduler.idle);

      final after = shownAt(f.pictures, cut(), 0);
      expect(after, isNotNull);
      expect(identical(before, after), isFalse);
      scheduler.dispose();
      f.layerImages.dispose();
    });
  });

  group('#31 lookahead — the NEXT cut rides the same run', () {
    // Duration 2, but a drawing parked out at index 3: the lookahead must
    // obey the SAME warm law as the active cut ([cutWarmFrameCount], the
    // authored extent) — a next cut whose runway drawing never warms would
    // re-create the exact asymmetry B1 closed. The runway's cel is its own,
    // so its picture says the walk reached it.
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
            Frame(id: const FrameId('frame-b3'), duration: 1, strokes: const []),
          ],
          timeline: {
            0: const TimelineExposure.drawing(FrameId('frame-b'), length: 1),
            3: const TimelineExposure.drawing(FrameId('frame-b3'), length: 1),
          },
        ),
      ],
    );

    testWidgets('warms the next cut start-to-end, BEHIND every active '
        'frame', (tester) async {
      await tester.runAsync(() async {
        final f = fixture();
        // The next cut's content enters the shared store the way an open
        // does — a baked donation under ITS keys.
        for (final cel in ['frame-b', 'frame-b3']) {
          f.store.storeBakedSurface(
            frameKey(nextCut(), const LayerId('layer-b'), FrameId(cel)),
            inkedSurface(),
          );
        }
        expect(
          f.pictures.has((
            cut: nextCut(),
            frameIndex: 3,
            paintPaper: true,
            ghosts: FrameGhosts.none,
          )),
          isFalse,
          reason: '⛔premise: the runway has a picture to make',
        );
        // The order pictures were MADE in: the hook answers before each.
        final made = <String>[];
        final scheduler = PlaybackPrerenderScheduler(
          pictures: f.pictures,
          resolveCut: (id) => id == const CutId('cut-b') ? nextCut() : cut(),
          idleDelay: Duration.zero,
          beforeCompose: (asked, _) async => made.add(asked.id.value),
        );

        scheduler.requestWarmCut(
          cutId: const CutId('cut'),
          aroundFrameIndex: 2,
          followedByCutId: const CutId('cut-b'),
        );
        await patiently(scheduler.idle);

        for (var index = 0; index < 4; index += 1) {
          expect(
            f.pictures.has((
              cut: nextCut(),
              frameIndex: index,
              paintPaper: true,
              ghosts: FrameGhosts.none,
            )),
            isTrue,
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
        f.layerImages.dispose();
      });
    });

    testWidgets('a self or unresolvable lookahead adds nothing',
        (tester) async {
      await tester.runAsync(() async {
        final f = fixture();
        final scheduler = PlaybackPrerenderScheduler(
          pictures: f.pictures,
          resolveCut: (id) => id == const CutId('cut') ? cut() : null,
          idleDelay: Duration.zero,
        );

        scheduler.requestWarmCut(
          cutId: const CutId('cut'),
          followedByCutId: const CutId('cut'),
        );
        await patiently(scheduler.idle);
        expect(
          scheduler.progress.value.total,
          4,
          reason: 'a cut must not warm itself twice through the lookahead',
        );

        scheduler.requestWarmCut(
          cutId: const CutId('cut'),
          followedByCutId: const CutId('gone'),
        );
        await patiently(scheduler.idle);
        expect(
          scheduler.progress.value.total,
          4,
          reason: 'a deleted next cut degrades to no lookahead, not a crash',
        );
        scheduler.dispose();
        f.layerImages.dispose();
      });
    });
  });

  /// 유저 2026-10-08, the playback rework: 「1 재생누르면 바로 재생」 · 「4
  /// 허용치도 해결」 · 「통일할거 통일하면서 권장대로가자」. A run that plays is
  /// followed from the frame under its playhead, at once, and only as far as
  /// the allowance holds.
  group('a run that plays', () {
    // A frame of the page as its picture lies ([pictureExtentOf]).
    final pictureBytes = estimatedImageBytes(
      pictureExtentOf(canvasSize.canvasRect).width.round(),
      pictureExtentOf(canvasSize.canvasRect).height.round(),
    );

    // Four frames, four pictures: each frame its own cel, so no two share a
    // picture and what was made says which frame was asked.
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
      picturesOf: (frame) => [(
        cut: four(),
        frameIndex: frame,
        paintPaper: true,
        ghosts: FrameGhosts.none,
      )],
      playlistFrameOf: (cutId, frameIndex) =>
          cutId == const CutId('cut') ? frameIndex : null,
      lead: lead,
    );

    List<bool> there(FramePictures pictures) => [
      for (var frame = 0; frame < 4; frame += 1)
        pictures.has((
          cut: four(),
          frameIndex: frame,
          paintPaper: true,
          ghosts: FrameGhosts.none,
        )),
    ];

    /// A cel inked across [four]'s canvas, and [past] tiles past every edge.
    BitmapSurface inkedOut(int past) => BitmapSurface(
      canvasSize: canvasSize,
      tileSize: 4,
      tiles: {
        for (var y = -past; y <= 1 + past; y += 1)
          for (var x = -past; x <= 1 + past; x += 1)
            TileCoord(x: x, y: y): BitmapTile(
              size: 4,
              pixels: Uint8List.fromList([
                for (var i = 0; i < 4 * 4; i += 1) ...[0, 0, 0, 255],
              ]),
            ),
      },
    );

    /// Every one of [four]'s cels drawn on — across all four of its tiles
    /// and inside its canvas, so each frame has a picture of the canvas's
    /// size ([pictureBytes]) to make — but [gone]'s, kept as an opened
    /// project keeps a cel, in a stretch of a file that is no longer there:
    /// its bytes cannot be read.
    ({
      BrushFrameStore store,
      LayerFrameImageCache layerImages,
      FramePictures pictures,
    })
    inked({FrameId? gone}) {
      final store = BrushFrameStore();
      if (gone != null) {
        keepInAFileThatIsGone(store, {
          frameKey(four(), const LayerId('layer'), gone): inkedOut(0),
        });
      }
      for (var index = 0; index < 4; index += 1) {
        if (FrameId('f$index') == gone) {
          continue;
        }
        BrushFrameEditingCoordinator(
          initialFrameKey: frameKey(
            four(),
            const LayerId('layer'),
            FrameId('f$index'),
          ),
          frameStore: store,
          sessionStore: BrushFrameEditSessionStore(
            canvasSize: canvasSize,
            tileSize: 4,
          ),
          historyPolicy: const BrushHistoryPolicy(),
        ).commitSourceStroke(
          sourceDabs: [
            BrushDab(
              center: CanvasPoint(x: 4, y: 4),
              color: 0xFF000000,
              size: 6,
              opacity: 1,
              flow: 1,
              hardness: 1,
              tipShape: BrushTipShape.square,
              pressure: 1,
              sequence: 0,
            ),
          ],
        );
      }
      final layerImages = LayerFrameImageCache(frameStore: store);
      return (
        store: store,
        layerImages: layerImages,
        pictures: picturesOver(layerImages),
      );
    }

    /// [four]'s cels kept as an opened project keeps them — in its file, not
    /// read yet — each inked across its canvas, and [heavy]'s past every
    /// edge as well: before it is read it is weighed as its canvas, and it
    /// weighs four times that.
    ({
      BrushFrameStore store,
      LayerFrameImageCache layerImages,
      FramePictures pictures,
    })
    keptInked({required int heavy}) {
      final store = BrushFrameStore();
      keepInAFile(store, {
        for (var index = 0; index < 4; index += 1)
          frameKey(four(), const LayerId('layer'), FrameId('f$index')):
              inkedOut(index == heavy ? 1 : 0),
      });
      final layerImages = LayerFrameImageCache(frameStore: store);
      return (
        store: store,
        layerImages: layerImages,
        pictures: picturesOver(layerImages),
      );
    }

    /// A picture waits for its raster to come back; asked for meanwhile, the
    /// next missing pictures' rasters queue behind it. Measured 10-10: the
    /// whole cut made 7–30% sooner.
    testWidgets('🚨it asks for the next two missing pictures before the one '
        'it waits for comes back', (tester) async {
      await tester.runAsync(() async {
        final f = inked();
        final gpu = _RastersInTurn();
        final asked = <FrameId>{};
        final scheduler = PlaybackPrerenderScheduler(
          pictures: picturesOver(f.layerImages, gpu: gpu),
          resolveCut: (_) => four(),
          idleDelay: Duration.zero,
          beforeCompose: (_, frameIndex) async =>
              asked.add(FrameId('f$frameIndex')),
        );

        scheduler.follow(run());
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(gpu.rastered, 0, reason: '⛔premise: the first raster waits');
        expect(
          asked,
          {for (var index = 0; index < 3; index += 1) FrameId('f$index')},
          reason: 'the frame waited for, and the two after it',
        );

        for (var index = 0; index < 4; index += 1) {
          gpu.letThrough(index);
        }
        await patiently(scheduler.idle);
        scheduler.dispose();
        f.layerImages.dispose();
      });
    });

    /// The walk reaching a picture it asked for ahead waits for it — and
    /// asks past it while it waits, so as many stay on their way rather
    /// than the asks running dry until the walk makes one of its own.
    testWidgets('waiting for a picture it asked for ahead, it keeps asking '
        'past it — as many stay on their way', (tester) async {
      await tester.runAsync(() async {
        Cut six() => Cut(
          id: const CutId('cut'),
          name: 'Cut',
          duration: 6,
          canvasSize: canvasSize,
          layers: [
            Layer(
              id: const LayerId('layer'),
              name: 'A',
              frames: [
                for (var index = 0; index < 6; index += 1)
                  Frame(id: FrameId('f$index'), duration: 1, strokes: const []),
              ],
              timeline: {
                for (var index = 0; index < 6; index += 1)
                  index: TimelineExposure.drawing(
                    FrameId('f$index'),
                    length: 1,
                  ),
              },
            ),
          ],
        );
        final store = BrushFrameStore();
        for (var index = 0; index < 6; index += 1) {
          inkCelIn(
            store,
            frameKey(six(), const LayerId('layer'), FrameId('f$index')),
            canvasSize: canvasSize,
            at: CanvasPoint(x: 4, y: 4),
            size: 6,
            tileSize: 4,
          );
        }
        final images = LayerFrameImageCache(frameStore: store);
        final gpu = _RastersInTurn();
        final asked = <FrameId>{};
        Future<void> letThrough(FrameId frame) async {
          gpu.letThrough(int.parse(frame.value.substring(1)));
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }

        final scheduler = PlaybackPrerenderScheduler(
          pictures: picturesOver(images, gpu: gpu),
          resolveCut: (_) => six(),
          idleDelay: Duration.zero,
          beforeCompose: (_, frameIndex) async =>
              asked.add(FrameId('f$frameIndex')),
        );
        scheduler.follow(
          PlayingDemand(
            totalFrames: 6,
            loops: () => true,
            playhead: () => 0,
            picturesOf: (frame) => [(
              cut: six(),
              frameIndex: frame,
              paintPaper: true,
              ghosts: FrameGhosts.none,
            )],
            playlistFrameOf: (cutId, frameIndex) =>
                cutId == const CutId('cut') ? frameIndex : null,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(
          asked,
          {for (var index = 0; index < 3; index += 1) FrameId('f$index')},
          reason: '⛔premise: its own, and two ahead',
        );

        await letThrough(const FrameId('f0'));
        expect(
          asked,
          contains(const FrameId('f3')),
          reason: 'waiting for frame 1, asked ahead, it asked past it',
        );

        await letThrough(const FrameId('f1'));
        await letThrough(const FrameId('f2'));
        expect(
          asked,
          containsAll([const FrameId('f4'), const FrameId('f5')]),
          reason: 'and a picture asked ahead gives its place back when it '
              'comes back',
        );

        for (final frame in ['f3', 'f4', 'f5']) {
          await letThrough(FrameId(frame));
        }
        await patiently(scheduler.idle);
        scheduler.dispose();
        images.dispose();
      });
    });

    testWidgets('🚨it is followed at once — the quiet window is for the hand '
        'that draws, and nothing draws under a run', (tester) async {
      await tester.runAsync(() async {
        final f = inked();
        final scheduler = PlaybackPrerenderScheduler(
          pictures: f.pictures,
          resolveCut: (_) => four(),
          idleDelay: const Duration(hours: 1),
        );

        // The stroke or the seek just before play was pressed.
        scheduler.notifyEditActivity();
        scheduler.follow(run());
        await patiently(scheduler.idle);

        expect(there(f.pictures), everyElement(isTrue));
        expect(
          scheduler.progress.value,
          const PrerenderProgress(cached: 4, total: 4),
        );
        scheduler.dispose();
        f.layerImages.dispose();
      });
    });

    testWidgets('the walk starts under the playhead and goes the way the '
        'run plays, round to the frame behind it', (tester) async {
      await tester.runAsync(() async {
        final f = inked();
        final made = <int>[];
        var landings = 0;
        final scheduler = PlaybackPrerenderScheduler(
          pictures: f.pictures,
          resolveCut: (_) => four(),
          idleDelay: Duration.zero,
          beforeCompose: (_, frameIndex) async => made.add(frameIndex),
        );
        scheduler.landings.addListener(() => landings += 1);

        playhead = 2;
        scheduler.follow(run());
        await patiently(scheduler.idle);

        expect(made, [2, 3, 0, 1]);
        expect(landings, 4, reason: 'a landing is told once a picture');
        scheduler.dispose();
        f.layerImages.dispose();
      });
    });

    /// What a run that waits looks again on.
    testWidgets('🚨it says each time the answer a waiting run waits for may '
        'have changed — at every picture that lands, and when it comes to '
        'rest: there it IS at rest, and woken, it is not', (tester) async {
      await tester.runAsync(() async {
        final f = inked();
        final scheduler = PlaybackPrerenderScheduler(
          pictures: f.pictures,
          resolveCut: (_) => four(),
          idleDelay: Duration.zero,
        );
        final restingAtEach = <bool>[];
        scheduler.changes.addListener(
          () => restingAtEach.add(scheduler.isResting),
        );

        scheduler.follow(run());
        expect(scheduler.isResting, isFalse);
        await patiently(scheduler.idle);
        expect(
          restingAtEach,
          [false, false, false, false, true],
          reason: 'four pictures landed, and then it rested',
        );

        // A film that is all made: woken, the walk rests on the same count
        // again. The progress value does not change, and tells nobody —
        // which left a run that fills before it goes standing for good.
        restingAtEach.clear();
        final before = scheduler.progress.value;
        var progressSaid = 0;
        scheduler.progress.addListener(() => progressSaid += 1);
        scheduler.wake();
        expect(scheduler.isResting, isFalse, reason: 'it has not looked yet');
        await patiently(scheduler.idle);
        expect(scheduler.progress.value, before, reason: '⛔premise');
        expect(progressSaid, 0, reason: '⛔premise');
        expect(restingAtEach, [true], reason: 'a rest is told every time');
        scheduler.dispose();
        f.layerImages.dispose();
      });
    });

    testWidgets('where the clock does not wait, a picture is started where '
        'the playhead will be when it lands', (tester) async {
      await tester.runAsync(() async {
        final f = inked();
        final made = <int>[];
        final scheduler = PlaybackPrerenderScheduler(
          pictures: f.pictures,
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
        await patiently(scheduler.idle);

        expect(made, [2, 3, 0, 1], reason: 'two frames on, then the lap');
        expect(askedWith.first, Duration.zero, reason: 'nothing made yet');
        expect(
          askedWith.last,
          greaterThan(Duration.zero),
          reason: 'the lead is asked with how long a picture has been taking',
        );
        expect(askedWith.last, scheduler.composeTime);
        scheduler.dispose();
        f.layerImages.dispose();
      });
    });

    testWidgets('how long a picture takes is known from the first one', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final f = inked();
        const slow = Duration(milliseconds: 40);
        final scheduler = PlaybackPrerenderScheduler(
          pictures: f.pictures,
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
            picturesOf: (frame) => [(
              cut: four(),
              frameIndex: frame,
              paintPaper: true,
              ghosts: FrameGhosts.none,
            )],
            playlistFrameOf: (_, frameIndex) => frameIndex,
          ),
        );
        await patiently(scheduler.idle);

        expect(
          scheduler.composeTime,
          greaterThanOrEqualTo(slow),
          reason: 'one picture made: the mean IS that one — a lead worked '
              'out from a fraction of it starts the next picture too late',
        );
        scheduler.dispose();
        f.layerImages.dispose();
      });
    });

    testWidgets('🚨it rests when no more fits, and walks on when the playhead '
        'does — each picture made once', (tester) async {
      await tester.runAsync(() async {
        final f = inked();
        final room = _Room(f.pictures, 2 * pictureBytes);
        final made = <int>[];
        final scheduler = PlaybackPrerenderScheduler(
          pictures: f.pictures,
          resolveCut: (_) => four(),
          room: room,
          idleDelay: Duration.zero,
          beforeCompose: (_, frameIndex) async => made.add(frameIndex),
        );
        room.demand = () => scheduler.demand;

        scheduler.follow(run());
        await patiently(scheduler.idle);
        expect(made, [0, 1], reason: 'two pictures fit');
        expect(there(f.pictures), [true, true, false, false]);
        expect(
          scheduler.progress.value,
          const PrerenderProgress(cached: 2, total: 2),
          reason: 'what is held is the window: nothing in it is left to make',
        );
        expect(f.pictures.store.estimatedBytes, 2 * pictureBytes);

        // One frame on: the frame that came into the window is made, out
        // of the room of the one that fell behind.
        playhead = 1;
        scheduler.wake();
        await patiently(scheduler.idle);
        expect(made, [0, 1, 2]);
        expect(there(f.pictures), [false, true, true, false]);

        playhead = 2;
        scheduler.wake();
        await patiently(scheduler.idle);
        expect(
          made,
          [0, 1, 2, 3],
          reason: 'the window moved on with the playhead; it did not churn',
        );
        expect(there(f.pictures), [false, false, true, true]);
        expect(f.pictures.store.estimatedBytes, 2 * pictureBytes);
        scheduler.dispose();
        f.layerImages.dispose();
      });
    });

    testWidgets('while it fills, the walk says how many frames it expects '
        'to hold — every one wanted, or as many as the room has held so far', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final f = inked();
        final room = _Room(f.pictures, 2 * pictureBytes);
        final said = <PrerenderProgress>[];
        final scheduler = PlaybackPrerenderScheduler(
          pictures: f.pictures,
          resolveCut: (_) => four(),
          room: room,
          idleDelay: Duration.zero,
        );
        room.demand = () => scheduler.demand;
        scheduler.progress.addListener(
          () => said.add(scheduler.progress.value),
        );

        scheduler.follow(run());
        await patiently(scheduler.idle);

        expect(
          said.first,
          const PrerenderProgress(cached: 0, total: 4),
          reason: 'nothing weighed yet: every frame wanted',
        );
        expect(
          said.skip(1).map((progress) => progress.total),
          everyElement(2),
          reason: 'a picture weighed, it expects what the room holds. '
              '↩️(1/2) then (2/2) while the walk asked for one picture at a '
              'time; asked for ahead, the second may be there before the '
              'walk looks (10-10)',
        );
        expect(
          said.last,
          const PrerenderProgress(cached: 2, total: 2),
          reason: 'and holds it',
        );
        scheduler.dispose();
        f.layerImages.dispose();
      });
    });

    /// 유저 2026-10-15, F-365-Q1 「직전 프레임에 서서 기다린다」: a run whose
    /// clock waits stands BEFORE a frame that is not there, and waits for
    /// that one — the frame after the one under its playhead.
    testWidgets('🚨what a run that waits waits for is made whatever the room: '
        'the picture under the playhead, and the one after it — a run that '
        'waits for either must not wait for good', (tester) async {
      await tester.runAsync(() async {
        final f = inked();
        final room = _Room(f.pictures, 0);
        final scheduler = PlaybackPrerenderScheduler(
          pictures: f.pictures,
          resolveCut: (_) => four(),
          room: room,
          idleDelay: Duration.zero,
        );
        room.demand = () => scheduler.demand;

        playhead = 1;
        scheduler.follow(run());
        await patiently(scheduler.idle);

        expect(
          there(f.pictures),
          [false, true, true, false],
          reason: '↩️only frame 1\'s was made, and a run standing on it '
              'waited for frame 2 for good (F-365, a 47MB cut head under a '
              '64MB line)',
        );
        expect(
          scheduler.progress.value,
          const PrerenderProgress(cached: 2, total: 2),
          reason: 'and no other: for the one after there is no room',
        );
        scheduler.dispose();
        f.layerImages.dispose();
      });
    });

    testWidgets('a picture heavier than its room makes room for itself once '
        'it lands — out of the pictures wanted after it, never itself '
        '(F-365)', (tester) async {
      await tester.runAsync(() async {
        final f = keptInked(heavy: 1);
        await f.pictures.make((
          cut: four(),
          frameIndex: 2,
          paintPaper: true,
          ghosts: FrameGhosts.none,
        ), shouldAbort: () => false);
        final room = _Room(f.pictures, 3 * pictureBytes);
        final scheduler = PlaybackPrerenderScheduler(
          pictures: f.pictures,
          resolveCut: (_) => four(),
          room: room,
          idleDelay: Duration.zero,
        );
        room.demand = () => scheduler.demand;

        scheduler.follow(run());
        await patiently(scheduler.idle);

        expect(
          there(f.pictures),
          [true, true, false, false],
          reason: 'frame 1 came heavier than the room it was asked by: the '
              'picture wanted after it went, and the walk rests',
        );
        expect(
          f.pictures.store.estimatedBytes,
          greaterThan(3 * pictureBytes),
          reason: '⛔premise: over the line by what the estimate missed',
        );
        scheduler.dispose();
        f.layerImages.dispose();
      });
    });

    testWidgets('where the clock does not wait, the picture the walk starts '
        'on is made whatever the room — a run that never waits still shows '
        'something new (F-365)', (tester) async {
      await tester.runAsync(() async {
        final f = inked();
        final room = _Room(f.pictures, 0);
        final scheduler = PlaybackPrerenderScheduler(
          pictures: f.pictures,
          resolveCut: (_) => four(),
          room: room,
          idleDelay: Duration.zero,
        );
        room.demand = () => scheduler.demand;

        playhead = 1;
        scheduler.follow(run(lead: (_) => 2));
        await patiently(scheduler.idle);

        expect(
          there(f.pictures),
          [false, false, false, true],
          reason: 'two frames on from the playhead',
        );
        expect(
          scheduler.progress.value,
          const PrerenderProgress(cached: 1, total: 1),
          reason: 'and no other: for the next one there is no room',
        );
        scheduler.dispose();
        f.layerImages.dispose();
      });
    });

    testWidgets('a picture let go from under the playhead is made again — '
        'the frame the walk starts on is asked every time', (tester) async {
      await tester.runAsync(() async {
        final f = inked();
        final scheduler = PlaybackPrerenderScheduler(
          pictures: f.pictures,
          resolveCut: (_) => four(),
          idleDelay: Duration.zero,
        );
        scheduler.follow(run());
        await patiently(scheduler.idle);
        expect(there(f.pictures), everyElement(isTrue));

        // A memory warning's work: every picture goes.
        f.pictures.store.enforceBudget(maxBytes: 0);
        expect(there(f.pictures), everyElement(isFalse));

        scheduler.wake();
        await patiently(scheduler.idle);
        expect(there(f.pictures), everyElement(isTrue));
        scheduler.dispose();
        f.layerImages.dispose();
      });
    });

    testWidgets('a playhead that moves on costs the walk a frame or two, not '
        'the window', (tester) async {
      await tester.runAsync(() async {
        final f = inked();
        var asked = 0;
        final scheduler = PlaybackPrerenderScheduler(
          pictures: f.pictures,
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
              return [(
                cut: cut(duration: 40),
                frameIndex: frame,
                paintPaper: true,
                ghosts: FrameGhosts.none,
              )];
            },
            playlistFrameOf: (_, frameIndex) => frameIndex,
          ),
        );
        await patiently(scheduler.idle);
        expect(asked, greaterThanOrEqualTo(40), reason: 'the first walk');

        asked = 0;
        playhead = 1;
        scheduler.wake();
        await patiently(scheduler.idle);
        expect(
          asked,
          lessThanOrEqualTo(2),
          reason: 'the frame it stands on now, and the one that came into '
              'the window behind it',
        );
        scheduler.dispose();
        f.layerImages.dispose();
      });
    });

    testWidgets('what the walk has passed is taken as there until it is told '
        'the pictures changed — then it walks them again', (tester) async {
      await tester.runAsync(() async {
        final f = inked();
        final scheduler = PlaybackPrerenderScheduler(
          pictures: f.pictures,
          resolveCut: (_) => four(),
          idleDelay: Duration.zero,
        );
        scheduler.follow(run());
        await patiently(scheduler.idle);

        // Frame 2's cel drawn on: its picture is another.
        f.store.markCelEdited(
          frameKey(four(), const LayerId('layer'), const FrameId('f2')),
        );
        expect(there(f.pictures), [true, true, false, true]);

        scheduler.wake(fromTheStart: true);
        await patiently(scheduler.idle);
        expect(there(f.pictures), everyElement(isTrue));
        scheduler.dispose();
        f.layerImages.dispose();
      });
    });

    // Where a frame stands is read off one walk of its stack (card frame-
    // panels-build-in-one-frame, 2026-10-28): the walk below lays a frame
    // whose cel will not read WITHOUT it, so its picture comes — this is a
    // frame given up on outright.
    testWidgets('a run waits for a picture still to come, and not for one '
        'given up on', (tester) async {
      final f = inked();
      final scheduler = PlaybackPrerenderScheduler(
        pictures: f.pictures,
        resolveCut: (_) => four(),
        idleDelay: Duration.zero,
      );
      addTearDown(() {
        scheduler.dispose();
        f.layerImages.dispose();
      });
      final shown = [
        (
          cut: four(),
          frameIndex: 1,
          paintPaper: true,
          ghosts: FrameGhosts.none,
        ),
      ];
      expect(scheduler.has(shown), isFalse, reason: 'still to come');

      f.pictures.noteFailure(shown.single);
      expect(
        scheduler.has(shown),
        isTrue,
        reason: 'nothing waits for a picture that cannot be made',
      );
    });

    testWidgets('a picture whose compose throws is not waited for, and is '
        'not paid for twice', (tester) async {
      await tester.runAsync(() async {
        final f = inked(gone: const FrameId('f1'));
        final layerImages = _CountsReadings(
          const FrameId('f1'),
          frameStore: f.store,
        );
        final pictures = picturesOver(layerImages);
        final reported = <Object>[];
        final previous = FlutterError.onError;
        FlutterError.onError = (details) => reported.add(details.exception);
        addTearDown(() => FlutterError.onError = previous);
        final scheduler = PlaybackPrerenderScheduler(
          pictures: pictures,
          resolveCut: (_) => four(),
          idleDelay: Duration.zero,
        );
        final passedAtEach = <bool>[];
        scheduler.changes.addListener(
          () => passedAtEach.add(scheduler.has([(
            cut: four(),
            frameIndex: 1,
            paintPaper: true,
            ghosts: FrameGhosts.none,
          )])),
        );

        scheduler.follow(run());
        await patiently(scheduler.idle);
        // ⛔Handed back BEFORE anything is expected: a failed expectation is
        // reported through this same door, and a collector left on it
        // swallows the failure — the pin could not fail.
        FlutterError.onError = previous;

        expect(
          there(pictures),
          everyElement(isTrue),
          reason: 'frame 1 is laid without the cel that would not read',
        );
        expect(
          pictures.standingOf((
            cut: four(),
            frameIndex: 1,
            paintPaper: true,
            ghosts: FrameGhosts.none,
          )).cannotRead,
          isTrue,
        );
        expect(reported, hasLength(1), reason: 'the failure is said, once');
        expect(
          passedAtEach,
          hasLength(5),
          reason: 'a word for each picture that came back, given up on or '
              'landed, and one when it rested',
        );
        expect(
          passedAtEach.take(passedAtEach.length - 1),
          contains(true),
          reason: 'frame 1 was given up on, and THAT is told — a run that '
              'waits for it goes on then, not when the walk rests. ↩️It was '
              'told second, after frame 0, while the walk asked for one '
              'picture at a time; asked for ahead, its failure may come back '
              'first (10-10)',
        );
        expect(
          scheduler.has([(
            cut: four(),
            frameIndex: 1,
            paintPaper: true,
            ghosts: FrameGhosts.none,
          )]),
          isTrue,
          reason: 'nothing waits for a picture that cannot be made',
        );
        expect(
          scheduler.progress.value,
          const PrerenderProgress(cached: 4, total: 4),
          reason: 'one frame\'s failure is one frame\'s: the walk went on',
        );

        scheduler.wake(fromTheStart: true);
        await patiently(scheduler.idle);
        expect(layerImages.asked, 1, reason: 'the same content is not retried');
        scheduler.dispose();
        layerImages.dispose();
      });
    });
  });
}

/// The room a test gives the warmer: [bytes] of the frames' pictures, kept
/// by the store's own law against whatever the warmer follows.
class _Room implements PictureRoom {
  _Room(this.pictures, this.bytes);

  final FramePictures pictures;

  @override
  final int bytes;

  FrameDemand? Function() demand = () => null;

  @override
  bool makeRoomFor({required int bytes, required int step}) =>
      pictures.store.enforceBudget(
        maxBytes: this.bytes - bytes,
        wantedAt: pictures.wantedAt(demand()),
        laterThan: step,
      );
}

/// A GPU whose rasters come back each when it is let through, by the order
/// they were asked in ([letThrough]) — the store lays one at a time, so the
/// first waits and the rest queue behind it. It holds no texture: no patch
/// is written here.
class _RastersInTurn implements FramePictureGpu {
  final _turns = <int, Completer<void>>{};
  int _asked = 0;

  /// How many rasters came back.
  int rastered = 0;

  /// Lets the [turn]th raster asked for come back — now, or once asked.
  void letThrough(int turn) =>
      _turns.putIfAbsent(turn, Completer<void>.new).complete();

  @override
  Future<ui.Image> render(ui.Picture picture, int width, int height) async {
    await _turns.putIfAbsent(_asked++, Completer<void>.new).future;
    rastered += 1;
    return picture.toImage(width, height);
  }

  @override
  Object? hold(ui.Image image) => null;

  @override
  int levelsOf(Object held) => 1;

  @override
  ui.Image imageOf(Object held) => throw UnsupportedError('holds no texture');

  @override
  Future<bool> write(Object held, List<BaseWrite> base, LevelWrites? levels) =>
      throw UnsupportedError('holds no texture');
}

/// An image cache that counts the readings of the cel [frameId]'s stored
/// pixels.
///
/// ⚠️IT READS THEM AS ANY CACHE DOES: what a cel that could not be read is
/// remembered by is the cache's record ([LayerFrameImageCache.unreadable]),
/// kept by its reading — a stand-in for the reading would stand in for the
/// record as well.
class _CountsReadings extends LayerFrameImageCache {
  _CountsReadings(this.frameId, {required super.frameStore});

  final FrameId frameId;
  int asked = 0;

  @override
  BitmapSurface? storedSurfaceOrNull(
    BrushFrameKey key, {
    required CanvasSize canvasSize,
  }) {
    if (key.frameId == frameId) {
      asked += 1;
    }
    return super.storedSurfaceOrNull(key, canvasSize: canvasSize);
  }
}
