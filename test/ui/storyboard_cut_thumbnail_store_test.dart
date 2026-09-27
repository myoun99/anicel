import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_frame_cache_invalidation.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_camera.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/services/playback/editor_cache_invalidation_hub.dart';
import 'package:anicel/src/ui/media/viewer_raster_budget.dart';
import 'package:anicel/src/ui/storyboard_cut_thumbnail_store.dart';

/// The camera frame every store here renders through.
ui.Size _original() => const ui.Size(1920, 1080);

void main() {
  Future<ui.Image> tinyImage() async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(const Rect.fromLTWH(0, 0, 2, 2), Paint());
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(2, 2);
    } finally {
      picture.dispose();
    }
  }

  Cut cut({bool layerVisible = true}) => Cut(
    id: const CutId('cut'),
    name: 'Cut',
    duration: 24,
    canvasSize: const CanvasSize(width: 8, height: 8),
    layers: [
      Layer(
        id: const LayerId('layer'),
        name: 'A',
        isVisible: layerVisible,
        frames: [
          Frame(id: const FrameId('f1'), duration: 1, strokes: const []),
        ],
      ),
    ],
  );

  testWidgets('renders lazily, once per signature', (tester) async {
    var renderCount = 0;
    final store = StoryboardCutThumbnailStore(
      originalSize: _original,
      render: (_, _, _) {
        renderCount += 1;
        return tinyImage();
      },
    );
    addTearDown(store.dispose);
    var notified = 0;
    store.addListener(() => notified += 1);

    await tester.runAsync(() async {
      expect(store.thumbnailFor(cut(), 0, shownHeight: 72), isNull);
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });

    expect(renderCount, 1);
    expect(notified, 1);
    expect(store.thumbnailFor(cut(), 0, shownHeight: 72), isNotNull);
    expect(renderCount, 1, reason: 'unchanged signature must not re-render');
  });

  testWidgets('what a surface is handed asks this store and hears its '
      'landings', (tester) async {
    final store = StoryboardCutThumbnailStore(
      originalSize: _original,
      render: (_, _, _) => tinyImage(),
    );
    addTearDown(store.dispose);
    final thumbnails = store.thumbnails;
    var landed = 0;
    thumbnails.landed.addListener(() => landed += 1);

    await tester.runAsync(() async {
      expect(
        thumbnails.resolve(cut(), 0, shownHeight: 72),
        isNull,
        reason: 'kicks a render',
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });

    expect(landed, 1, reason: 'the render that landed said so');
    expect(
      thumbnails.resolve(cut(), 0, shownHeight: 72),
      same(store.thumbnailFor(cut(), 0, shownHeight: 72)),
    );
    expect(store.thumbnails, same(thumbnails), reason: 'one value, kept');
  });

  testWidgets('the SIZE is part of the key: a picture renders at the width '
      'its shown height asks, on the viewer\'s ladder and never past the '
      'original (유저 09-25 「화면이 필요한 만큼(최대 원본)」)', (tester) async {
    final widths = <int>[];
    final store = StoryboardCutThumbnailStore(
      originalSize: _original,
      render: (_, _, width) {
        widths.add(width);
        return tinyImage();
      },
    );
    addTearDown(store.dispose);

    await tester.runAsync(() async {
      store.thumbnailFor(cut(), 0, shownHeight: 60); // a strip block
      store.thumbnailFor(cut(), 0, shownHeight: 400); // a conte cell
      store.thumbnailFor(cut(), 0, shownHeight: 5000); // zoomed far in
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });

    // 60 of 1080 → the ladder's floor, 1/16; 400 → up to 1/2; 5000 → the
    // original and no further.
    expect(widths, [120, 960, 1920]);
    // Each width caches on its own, and a height the ladder rounds to a
    // width already held renders nothing new.
    await tester.runAsync(() async {
      store.thumbnailFor(cut(), 0, shownHeight: 60);
      store.thumbnailFor(cut(), 0, shownHeight: 300);
      store.thumbnailFor(cut(), 0, shownHeight: 5000);
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    expect(widths, hasLength(3));
  });

  testWidgets('until its own width lands, a panel shows the SHARPEST picture '
      'it holds at another — a zoom never flashes an empty cell', (
    tester,
  ) async {
    Future<ui.Image> imageOf(int width) async {
      final recorder = ui.PictureRecorder();
      Canvas(
        recorder,
      ).drawRect(Rect.fromLTWH(0, 0, width.toDouble(), 2), Paint());
      final picture = recorder.endRecording();
      try {
        return await picture.toImage(width, 2);
      } finally {
        picture.dispose();
      }
    }

    final pending = <(int, int), Completer<ui.Image?>>{};
    final store = StoryboardCutThumbnailStore(
      originalSize: _original,
      render: (_, frame, width) =>
          (pending[(frame, width)] = Completer<ui.Image?>()).future,
    );
    addTearDown(store.dispose);

    late ui.Image small;
    late ui.Image whole;
    await tester.runAsync(() async {
      store.thumbnailFor(cut(), 0, shownHeight: 60);
      store.thumbnailFor(cut(), 0, shownHeight: 5000);
      pending[(0, 120)]!.complete(small = await imageOf(120));
      pending[(0, 1920)]!.complete(whole = await imageOf(1920));
      await Future<void>.delayed(Duration.zero);
    });

    expect(
      store.thumbnailFor(cut(), 0, shownHeight: 400),
      same(whole),
      reason: '960 is still rendering: the sharpest held stands in',
    );
    expect(
      store.thumbnailFor(cut(), 7, shownHeight: 400),
      isNull,
      reason: 'another panel\'s picture never stands in',
    );
    late ui.Image own;
    await tester.runAsync(() async {
      pending[(0, 960)]!.complete(own = await imageOf(960));
    });
    // The 960 render was asked in the test's fake zone, so its landing
    // waits in that zone's queue.
    await tester.pump();
    expect(store.thumbnailFor(cut(), 0, shownHeight: 400), same(own));
    expect(store.thumbnailFor(cut(), 0, shownHeight: 60), same(small));
  });

  testWidgets('layer visibility change re-renders', (tester) async {
    var renderCount = 0;
    final store = StoryboardCutThumbnailStore(
      originalSize: _original,
      render: (_, _, _) {
        renderCount += 1;
        return tinyImage();
      },
    );
    addTearDown(store.dispose);

    await tester.runAsync(() async {
      store.thumbnailFor(cut(), 0, shownHeight: 72);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      store.thumbnailFor(cut(layerVisible: false), 0, shownHeight: 72);
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    // The retired first image disposes on the next frame.
    await tester.pump();

    expect(renderCount, 2);
  });

  testWidgets('hub brush-frame events invalidate the cut', (tester) async {
    var renderCount = 0;
    final hub = EditorCacheInvalidationHub();
    final store = StoryboardCutThumbnailStore(
      originalSize: _original,
      render: (_, _, _) {
        renderCount += 1;
        return tinyImage();
      },
      invalidationHub: hub,
    );
    addTearDown(store.dispose);
    // ONE cut: a stroke leaves the model as it was — the pixels live
    // outside it — so the same instance is asked before and after.
    final shown = cut();

    await tester.runAsync(() async {
      store.thumbnailFor(shown, 0, shownHeight: 72);
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    expect(renderCount, 1);

    hub.invalidateBrushFrame(
      BrushFrameCacheInvalidation.wholeFrame(
        const BrushFrameKey(
          projectId: ProjectId('project'),
          trackId: TrackId('track'),
          cutId: CutId('cut'),
          layerId: LayerId('layer'),
          frameId: FrameId('f1'),
        ),
      ),
    );

    await tester.runAsync(() async {
      store.thumbnailFor(shown, 0, shownHeight: 72);
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pump();

    expect(renderCount, 2);
  });

  // I-22: at the ten-minute floor every panel of the film is asked for on
  // every paint.
  testWidgets('a cut is spelled once per edit, however many panels and '
      'paints ask', (tester) async {
    final hub = EditorCacheInvalidationHub();
    final store = StoryboardCutThumbnailStore(
      originalSize: _original,
      render: (_, _, _) => tinyImage(),
      invalidationHub: hub,
    );
    addTearDown(store.dispose);
    final shown = cut();

    await tester.runAsync(() async {
      for (var paint = 0; paint < 5; paint += 1) {
        for (final panel in [0, 8, 16]) {
          store.thumbnailFor(shown, panel, shownHeight: 72);
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    expect(store.debugSignaturesSpelled, 1);

    hub.invalidateBrushFrame(
      BrushFrameCacheInvalidation.wholeFrame(
        const BrushFrameKey(
          projectId: ProjectId('project'),
          trackId: TrackId('track'),
          cutId: CutId('cut'),
          layerId: LayerId('layer'),
          frameId: FrameId('f1'),
        ),
      ),
    );
    store.thumbnailFor(shown, 0, shownHeight: 72);
    expect(
      store.debugSignaturesSpelled,
      2,
      reason: 'a stroke moves the edit generation, and nothing else',
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
  });

  testWidgets('a null render result is cached, not retried per build', (
    tester,
  ) async {
    var renderCount = 0;
    final store = StoryboardCutThumbnailStore(
      originalSize: _original,
      render: (_, _, _) async {
        renderCount += 1;
        return null;
      },
    );
    addTearDown(store.dispose);

    await tester.runAsync(() async {
      store.thumbnailFor(cut(), 0, shownHeight: 72);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(store.thumbnailFor(cut(), 0, shownHeight: 72), isNull);
    });

    expect(renderCount, 1);
  });

  // R4-⑩ regression pins: everything the camera-view render consumes must
  // join the signature — these edits used to leave a permanently stale
  // (often permanently EMPTY) thumbnail.
  group('signature covers the full camera-view render input', () {
    Future<int> renderCountAfter(
      WidgetTester tester,
      Cut Function() before,
      Cut Function() after,
    ) async {
      var renderCount = 0;
      final store = StoryboardCutThumbnailStore(
        originalSize: _original,
        render: (_, _, _) {
          renderCount += 1;
          return tinyImage();
        },
      );
      addTearDown(store.dispose);
      await tester.runAsync(() async {
        store.thumbnailFor(before(), 0, shownHeight: 72);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        store.thumbnailFor(after(), 0, shownHeight: 72);
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pump();
      return renderCount;
    }

    testWidgets('camera keyframe edits re-render', (tester) async {
      expect(
        await renderCountAfter(
          tester,
          cut,
          () => cut().copyWith(
            camera: CutCamera(
              keyframes: {
                0: CameraPose(center: CanvasPoint(x: 1, y: 1), zoom: 2),
              },
            ),
          ),
        ),
        2,
      );
    });

    testWidgets('layer transform-lane edits re-render', (tester) async {
      expect(
        await renderCountAfter(tester, cut, () {
          final base = cut();
          return base.copyWith(
            layers: [
              base.layers.single.copyWith(
                transformTrack: TransformTrack(
                  keyframes: {
                    0: TransformPose(center: CanvasPoint(x: 9, y: 9)),
                  },
                ),
              ),
            ],
          );
        }),
        2,
      );
    });

    testWidgets('exposure-only timeline edits re-render', (tester) async {
      expect(
        await renderCountAfter(tester, cut, () {
          final base = cut();
          return base.copyWith(
            layers: [
              base.layers.single.copyWith(
                timeline: {
                  0: const TimelineExposure.drawing(FrameId('f1'), length: 4),
                },
              ),
            ],
          );
        }),
        2,
      );
    });

    testWidgets('an unchanged cut does NOT re-render — fades left the cut '
        'for the track (R4), so they no longer churn thumbnails', (
      tester,
    ) async {
      expect(await renderCountAfter(tester, cut, cut), 1);
    });
  });

  testWidgets('a FAILED render is remembered (no hot re-kick loop) and a '
      'content change retries', (tester) async {
    var renderCount = 0;
    var failFirst = true;
    final errors = <FlutterErrorDetails>[];
    final previousHandler = FlutterError.onError;
    FlutterError.onError = errors.add;
    addTearDown(() => FlutterError.onError = previousHandler);

    final store = StoryboardCutThumbnailStore(
      originalSize: _original,
      render: (_, _, _) async {
        renderCount += 1;
        if (failFirst) {
          failFirst = false;
          throw StateError('render exploded');
        }
        return tinyImage();
      },
    );
    addTearDown(store.dispose);

    await tester.runAsync(() async {
      store.thumbnailFor(cut(), 0, shownHeight: 72);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      // Same signature: the failure must NOT re-kick on every build.
      store.thumbnailFor(cut(), 0, shownHeight: 72);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(renderCount, 1);
      expect(errors, hasLength(1), reason: 'failures surface, never vanish');

      // A content change retries and succeeds.
      store.thumbnailFor(cut(layerVisible: false), 0, shownHeight: 72);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(renderCount, 2);
      expect(
        store.thumbnailFor(cut(layerVisible: false), 0, shownHeight: 72),
        isNotNull,
      );
    });
    await tester.pump();
  });

  // 2026-09-11: the store held every panel ever looked at, uncounted. It is
  // bounded now by ONE VIEWER'S SHARE (`ViewerRasterBudget`); its test seam
  // scales a "page" down so four 2×2 pictures fill the budget.
  group('bounded in bytes, like a viewer', () {
    // A 2×2 picture costs 16 bytes. A 16-byte page makes the budget four
    // pages (64 bytes, four pictures) and the pressure floor one picture.
    setUp(() => ViewerRasterBudget.debugPageBytesOverride = 16);
    tearDown(() => ViewerRasterBudget.debugPageBytesOverride = null);

    Future<void> ask(
      WidgetTester tester,
      StoryboardCutThumbnailStore store,
      List<int> frames,
    ) async {
      await tester.runAsync(() async {
        for (final frame in frames) {
          store.thumbnailFor(cut(), frame, shownHeight: 72);
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      // Pictures let go are disposed after the next frame.
      await tester.pump();
    }

    testWidgets('holds at most its budget: the least recently asked-for '
        'picture goes first, and comes back when asked again', (tester) async {
      var renders = 0;
      final reported = <int>[];
      final store = StoryboardCutThumbnailStore(
        originalSize: _original,
        render: (_, _, _) {
          renders += 1;
          return tinyImage();
        },
        onHeldBytesChanged: reported.add,
      );
      addTearDown(store.dispose);

      await ask(tester, store, [0, 1, 2, 3, 4]);
      expect(renders, 5);
      expect(store.thumbnailBytes, 64, reason: 'four pictures fit, not five');
      expect(reported.last, 64, reason: 'the census hears what is held');

      // Frame 0 was the least recently asked-for, so it went. Asking again
      // renders it again — an evicted panel must not stay empty for good.
      await ask(tester, store, [0]);
      expect(renders, 6, reason: 'the evicted panel came back');
      expect(store.thumbnailFor(cut(), 0, shownHeight: 72), isNotNull);
    });

    testWidgets('a picture asked for again is kept over one that was not', (
      tester,
    ) async {
      var renders = 0;
      final store = StoryboardCutThumbnailStore(
        originalSize: _original,
        render: (_, _, _) {
          renders += 1;
          return tinyImage();
        },
      );
      addTearDown(store.dispose);

      await ask(tester, store, [0, 1, 2, 3]);
      expect(store.thumbnailFor(cut(), 0, shownHeight: 72), isNotNull);
      // The fifth picture pushes out frame 1 — nobody asked for it since —
      // and not frame 0, which was just asked for.
      await ask(tester, store, [4]);
      expect(
        store.thumbnailFor(cut(), 0, shownHeight: 72),
        isNotNull,
        reason: 'kept',
      );
      expect(renders, 5, reason: 'frame 0 was still held — no re-render');
      await ask(tester, store, [1]);
      expect(renders, 6, reason: 'frame 1 went, so asking for it renders');
    });

    testWidgets('the memory warning halves it and gives pictures back, '
        'never below one page', (tester) async {
      final reported = <int>[];
      var notified = 0;
      final store = StoryboardCutThumbnailStore(
        originalSize: _original,
        render: (_, _, _) => tinyImage(),
        onHeldBytesChanged: reported.add,
      );
      addTearDown(store.dispose);

      await ask(tester, store, [0, 1, 2, 3]);
      store.addListener(() => notified += 1);
      store.respondToMemoryPressure();
      expect(store.thumbnailBytes, 32, reason: 'halved: two pictures left');
      expect(reported.last, 32);
      expect(
        notified,
        1,
        reason: 'panels still showing a dropped picture must rebuild',
      );
      await tester.pump();
      store
        ..respondToMemoryPressure()
        ..respondToMemoryPressure();
      expect(store.thumbnailBytes, 16, reason: 'never below one page');
      await tester.pump();
    });

    testWidgets('disposing tells the census nothing is held', (tester) async {
      final reported = <int>[];
      final store = StoryboardCutThumbnailStore(
        originalSize: _original,
        render: (_, _, _) => tinyImage(),
        onHeldBytesChanged: reported.add,
      );
      await ask(tester, store, [0]);
      expect(reported.last, 16);
      store.dispose();
      expect(reported.last, 0);
    });
  });
}
