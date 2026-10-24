import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/brush_history_policy.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/playback_quality.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_edit_session_store.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';

import '../../helpers/settle_async.dart';

/// 🚨★★★BELOW 100% THE BUFFER IS A LEVEL (render round, 안 1 「선명」,
/// 2026-09-16). One composite image, one blit, at every zoom — and below
/// 100% that image is the artwork halved until the blit reduces it by
/// (0.5, 1]: the buffer is the screen's size, not the visible canvas's,
/// and every level pixel is the exact mean of its block.
///
/// The fixture is a 64×32 cel with an opaque black column every four
/// pixels, shown as a cached (non-active) layer. At 25% each device pixel
/// is a 4×4 block holding exactly one black column — a quarter ink — so the
/// level buffer reads 191 everywhere over white paper. The two ways of
/// getting it wrong read differently: a canvas-resolution buffer reduced by
/// one bilinear step samples a 2×2 window of each 4×4 block (255 or 128,
/// by phase), and nearest reads 0 or 255.
void main() {
  const canvasSize = CanvasSize(width: 64, height: 32);
  const projectId = ProjectId('project');
  const trackId = TrackId('track');
  const cutId = CutId('cut');
  const layerId = LayerId('layer');
  const frameId = FrameId('frame');
  const frameKey = BrushFrameKey(
    projectId: projectId,
    trackId: trackId,
    cutId: cutId,
    layerId: layerId,
    frameId: frameId,
  );

  /// A black column at every fourth x, one pixel wide, the cel's height.
  BrushFrameStore storeWithColumns() {
    final store = BrushFrameStore();
    var sequence = 0;
    BrushFrameEditingCoordinator(
      initialFrameKey: frameKey,
      frameStore: store,
      sessionStore: BrushFrameEditSessionStore(
        canvasSize: canvasSize,
        tileSize: 8,
      ),
      historyPolicy: const BrushHistoryPolicy(),
    ).commitSourceStroke(
      sourceDabs: [
        for (var x = 0; x < canvasSize.width; x += 4)
          for (var y = 0; y < canvasSize.height; y += 1)
            BrushDab(
              center: CanvasPoint(x: x + 0.5, y: y + 0.5),
              color: 0xFF000000,
              size: 1,
              opacity: 1,
              flow: 1,
              hardness: 1,
              tipShape: BrushTipShape.square,
              pressure: 1,
              sequence: sequence++,
            ),
      ],
    );
    return store;
  }

  /// The cel's image made at [quality] BEFORE the stack mounts, so its
  /// first paint already holds it.
  Future<LayerFrameImageCache> warmImages(
    WidgetTester tester,
    BrushFrameStore store,
    PlaybackQuality quality,
  ) async {
    final images = LayerFrameImageCache(frameStore: store);
    addTearDown(images.dispose);
    await tester.runAsync(
      () => images.prepare(
        key: frameKey,
        canvasSize: canvasSize,
        quality: quality,
        sourceEffects: const [],
      ),
    );
    return images;
  }

  Widget stackAt({
    required CanvasViewport viewport,
    required LayerFrameImageCache images,
    required Size logicalSize,
  }) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: logicalSize.width,
          height: logicalSize.height,
          child: CanvasLayerStackView(
            nodes: const [
              CompositeLeaf<CanvasStackRow>(
                CanvasLayerImageRequest(frameKey: frameKey, opacity: 1),
              ),
            ],
            imageCache: images,
            canvasSize: canvasSize,
            viewport: viewport,
            paintPaper: true,
            paperBackground: ProjectBackground.defaultBackground,
          ),
        ),
      ),
    ),
  );

  CustomPainter painterOf(WidgetTester tester) => tester
      .widgetList<CustomPaint>(
        find.descendant(
          of: find.byType(CanvasLayerStackView),
          matching: find.byType(CustomPaint),
        ),
      )
      .where((paint) => paint.painter != null)
      .first
      .painter!;

  Future<Uint8List> paintBytes(
    WidgetTester tester,
    CustomPainter painter,
    Size size,
  ) async {
    final bytes = await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      painter.paint(Canvas(recorder, Offset.zero & size), size);
      final picture = recorder.endRecording();
      final image = picture.toImageSync(
        size.width.round(),
        size.height.round(),
      );
      picture.dispose();
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return data!.buffer.asUint8List();
    });
    return bytes!;
  }

  testWidgets('at 25% the buffer is a level: every pixel is the mean of its '
      '4×4 block', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);
    final images = await warmImages(
      tester,
      storeWithColumns(),
      PlaybackQuality.quarter,
    );
    // Canvas x 16..48 × y 8..24 in an 8×4 logical view: one device pixel
    // per 4×4 block, and the cel's INTERIOR — inside a level buffer the
    // paper yields its outer level pixel (#15, `_paintPaperInto`), so the
    // edge ring is not paper and is not this test's question.
    const logicalSize = Size(8, 4);
    await tester.pumpWidget(
      stackAt(
        viewport: CanvasViewport(zoom: 0.25, panX: -4, panY: -2),
        images: images,
        logicalSize: logicalSize,
      ),
    );
    await tester.pumpAndSettle();
    final bytes = await paintBytes(tester, painterOf(tester), logicalSize);

    // ↩️The buffer's level and the bytes it held were read off the
    // canvas's buffer cache, until nothing kept a buffer
    // (one-picture-per-frame ②-5a): what each pixel reads tells a level
    // from the two ways of getting it wrong.
    for (var i = 0; i < bytes.length; i += 4) {
      expect(bytes[i + 3], 255, reason: 'pixel ${i ~/ 4} is opaque');
      expect(
        bytes[i],
        inInclusiveRange(189, 193),
        reason: 'pixel ${i ~/ 4}: a quarter of each 4×4 block is ink, so the '
            'level reads 191 — 255 or 128 is one bilinear step over the '
            'canvas-resolution picture, 0/255 is nearest',
      );
    }
  });

  testWidgets('the level image is asked of the cache at the level\'s '
      'quality — quarter at 25%, half at 40%, full at 60%', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final (zoom, quality) in [
      (0.25, PlaybackQuality.quarter),
      (0.4, PlaybackQuality.half),
      (0.6, PlaybackQuality.full),
    ]) {
      final store = storeWithColumns();
      final images = LayerFrameImageCache(frameStore: store);
      addTearDown(images.dispose);
      await tester.pumpWidget(
        stackAt(
          viewport: CanvasViewport(zoom: zoom),
          images: images,
          logicalSize: const Size(16, 8),
        ),
      );
      // The image is made off the frame ([LayerFrameImageCache.prepare]
      // awaits its raster): let real time pass for the engine and test
      // time for the frame until it lands.
      LayerFrameImage? made;
      await settleAsync(
        tester,
        () =>
            (made = images.validImageOrNull(
              frameKey,
              quality,
              canvasSize: canvasSize,
              sourceEffects: const [],
            )) !=
            null,
        step: const Duration(milliseconds: 50),
      );
      await tester.pumpAndSettle();
      expect(
        made,
        isNotNull,
        reason: 'zoom $zoom: the stack must have prepared the $quality image',
      );
      for (final other in PlaybackQuality.values) {
        if (other == quality) {
          continue;
        }
        expect(
          images.validImageOrNull(
            frameKey,
            other,
            canvasSize: canvasSize,
            sourceEffects: const [],
          ),
          isNull,
          reason: 'zoom $zoom: only the level\'s quality is prepared, not '
              '$other',
        );
      }
      await tester.pumpWidget(const SizedBox());
    }
  });

  // ↩️A pan by whole level pixels carried the kept level buffer and
  // composed only the band it exposed (`DisplayBufferCache`), until the
  // canvas that stands showed the frame's one picture and nothing kept a
  // buffer (one-picture-per-frame ②-5a).
}
