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
import 'package:anicel/src/ui/storyboard_cut_thumbnail_store.dart';

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
      render: (_, _) {
        renderCount += 1;
        return tinyImage();
      },
    );
    addTearDown(store.dispose);
    var notified = 0;
    store.addListener(() => notified += 1);

    await tester.runAsync(() async {
      expect(store.thumbnailFor(cut(), 0), isNull);
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });

    expect(renderCount, 1);
    expect(notified, 1);
    expect(store.thumbnailFor(cut(), 0), isNotNull);
    expect(renderCount, 1, reason: 'unchanged signature must not re-render');
  });

  testWidgets('layer visibility change re-renders', (tester) async {
    var renderCount = 0;
    final store = StoryboardCutThumbnailStore(
      render: (_, _) {
        renderCount += 1;
        return tinyImage();
      },
    );
    addTearDown(store.dispose);

    await tester.runAsync(() async {
      store.thumbnailFor(cut(), 0);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      store.thumbnailFor(cut(layerVisible: false), 0);
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
      render: (_, _) {
        renderCount += 1;
        return tinyImage();
      },
      invalidationHub: hub,
    );
    addTearDown(store.dispose);

    await tester.runAsync(() async {
      store.thumbnailFor(cut(), 0);
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
      store.thumbnailFor(cut(), 0);
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pump();

    expect(renderCount, 2);
  });

  testWidgets('a null render result is cached, not retried per build', (
    tester,
  ) async {
    var renderCount = 0;
    final store = StoryboardCutThumbnailStore(
      render: (_, _) async {
        renderCount += 1;
        return null;
      },
    );
    addTearDown(store.dispose);

    await tester.runAsync(() async {
      store.thumbnailFor(cut(), 0);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(store.thumbnailFor(cut(), 0), isNull);
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
        render: (_, _) {
          renderCount += 1;
          return tinyImage();
        },
      );
      addTearDown(store.dispose);
      await tester.runAsync(() async {
        store.thumbnailFor(before(), 0);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        store.thumbnailFor(after(), 0);
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
      render: (_, _) async {
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
      store.thumbnailFor(cut(), 0);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      // Same signature: the failure must NOT re-kick on every build.
      store.thumbnailFor(cut(), 0);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(renderCount, 1);
      expect(errors, hasLength(1), reason: 'failures surface, never vanish');

      // A content change retries and succeeds.
      store.thumbnailFor(cut(layerVisible: false), 0);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(renderCount, 2);
      expect(store.thumbnailFor(cut(layerVisible: false), 0), isNotNull);
    });
    await tester.pump();
  });
}
