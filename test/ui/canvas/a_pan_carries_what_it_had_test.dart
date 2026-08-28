import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/brush_history_policy.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/playback_quality.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/rgba_color.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/bitmap_tile_rgba.dart';
import 'package:anicel/src/services/brush_frame_edit_session_store.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/canvas/display_buffer_cache.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';

/// 🚨★★★A PAN CARRIES WHAT IT ALREADY HAD.
///
/// When the extent MOVES, the previous buffer is not wrong — it is OFFSET.
/// The buffer is canvas resolution, so one buffer pixel is one canvas pixel
/// at every zoom, and the overlap belongs exactly where the new rect says.
/// What is left to composite is the band the pan exposed.
///
/// ⛔ONE IMAGE STILL. The blit and the band go into the same recorder and
/// come out of one `toImageSync`, so there is no boundary at paint time for
/// a fractional scale to seam — which is what the tile grid was rejected for
/// and what a base-drawn-beside-a-patch would bring back.
///
/// 유저 2026-08-28: 「화면에서 보이는건 바뀌면안되고」. So the test that
/// matters is bytes: a carried buffer must draw what a cold composite draws.
void main() {
  const canvasSize = CanvasSize(width: 32, height: 32);
  final projectId = ProjectId('p');
  final cutId = CutId('c');
  final trackId = TrackId('t');

  BrushFrameKey keyFor(String id) => BrushFrameKey(
    projectId: projectId,
    cutId: cutId,
    trackId: trackId,
    layerId: LayerId(id),
    frameId: FrameId(id),
  );

  LayerFrameImageCache cacheWithStroke(String id) {
    final store = BrushFrameStore();
    BrushFrameEditingCoordinator(
      initialFrameKey: keyFor(id),
      frameStore: store,
      sessionStore: BrushFrameEditSessionStore(
        canvasSize: canvasSize,
        tileSize: 8,
      ),
      historyPolicy: const BrushHistoryPolicy(
        userUndoLimit: 8,
        deferredBakeRatio: 0,
      ),
    ).commitSourceStroke(
      sourceDabs: [
        for (var i = 0; i < 4; i += 1)
          BrushDab(
            center: CanvasPoint(x: 4.0 + i * 7, y: 5.0 + i * 6),
            color: 0xFF0000FF,
            size: 5,
            opacity: 1,
            flow: 1,
            hardness: 1,
            tipShape: BrushTipShape.round,
            pressure: 1,
            sequence: i,
          ),
      ],
    );
    return LayerFrameImageCache(frameStore: store);
  }

  BitmapSurfacePainter buildLive() {
    var tile = BitmapTile.blank(coord: TileCoord(x: 0, y: 0), size: 8);
    for (var i = 0; i < 6; i += 1) {
      tile = writeRgbaColorToBitmapTile(
        tile: tile,
        x: i,
        y: i,
        color: RgbaColor(r: 255, g: 0, b: 0, a: 255),
      );
    }
    return BitmapSurfacePainter(
      surface: BitmapSurface(
        canvasSize: canvasSize,
        tileSize: 8,
        tiles: {tile.coord: tile},
      ),
      showTransparentBackground: false,
    );
  }

  final live = buildLive();
  final nodes = <CanvasLayerStackNode>[
    CanvasLayerImageNode(
      CanvasLayerImageRequest(frameKey: keyFor('under'), opacity: 1),
    ),
    const CanvasActiveLayerNode(opacity: 1),
  ];

  Future<LayerFrameImageCache> warmCache(WidgetTester tester) async {
    final cache = cacheWithStroke('under');
    await tester.runAsync(
      () => cache.prepare(
        key: keyFor('under'),
        canvasSize: canvasSize,
        quality: PlaybackQuality.full,
        sourceEffects: const [],
      ),
    );
    return cache;
  }

  Widget stackAt(
    CanvasViewport viewport,
    LayerFrameImageCache cache,
    DisplayBufferCache buffers,
  ) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          // ⛔SMALL, so a pan actually moves the extent: the extent is
          // CONTENT ∩ VIEW, and a view that holds the whole page never
          // moves it (that case is `a_pan_is_not_a_recomposite_test`).
          width: 40,
          height: 40,
          child: CanvasLayerStackView(
            nodes: nodes,
            imageCache: cache,
            debugBufferCache: buffers,
            canvasSize: canvasSize,
            viewport: viewport,
            activeSurfacePainter: live,
            paintPaper: true,
            paperBackground: const ProjectBackground.color(0xFFFFFFFF),
          ),
        ),
      ),
    ),
  );

  Future<Uint8List> screenAt(
    WidgetTester tester,
    CanvasViewport viewport,
    LayerFrameImageCache cache,
    DisplayBufferCache buffers,
  ) async {
    await tester.pumpWidget(stackAt(viewport, cache, buffers));
    await tester.pumpAndSettle();
    final painted = tester
        .widgetList<CustomPaint>(
          find.descendant(
            of: find.byType(CanvasLayerStackView),
            matching: find.byType(CustomPaint),
          ),
        )
        .where((paint) => paint.painter != null)
        .toList();
    expect(painted, isNotEmpty);
    const size = Size(40, 40);
    final recorder = ui.PictureRecorder();
    painted.first.painter!.paint(Canvas(recorder, Offset.zero & size), size);
    final picture = recorder.endRecording();
    final image = picture.toImageSync(40, 40);
    picture.dispose();
    final bytes = await tester.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
    );
    image.dispose();
    return bytes!.buffer.asUint8List();
  }

  testWidgets('a carried buffer draws what a cold composite draws', (
    tester,
  ) async {
    final cache = await warmCache(tester);
    final moved = CanvasViewport(zoom: 2, panX: 5, panY: 4);

    final warm = DisplayBufferCache();
    addTearDown(warm.dispose);
    await screenAt(
      tester,
      CanvasViewport(zoom: 2, panX: 0, panY: 0),
      cache,
      warm,
    );
    final carried = await screenAt(tester, moved, cache, warm);

    final cold = DisplayBufferCache();
    addTearDown(cold.dispose);
    final fresh = await screenAt(tester, moved, cache, cold);

    expect(
      carried,
      fresh,
      reason: 'the band the pan exposed was composited and the rest was '
          'carried — byte for byte, or the carry moved pixels it should not '
          'have',
    );
  });

  testWidgets('the carry actually ran, and it is not the patch path', (
    tester,
  ) async {
    final cache = await warmCache(tester);
    final buffers = DisplayBufferCache();
    addTearDown(buffers.dispose);

    await tester.pumpWidget(
      stackAt(CanvasViewport(zoom: 2, panX: 0, panY: 0), cache, buffers),
    );
    await tester.pumpAndSettle();
    expect(
      buffers.scrolledCount,
      0,
      reason: 'fixture: nothing to carry on the first composite',
    );

    await tester.pumpWidget(
      stackAt(CanvasViewport(zoom: 2, panX: 5, panY: 4), cache, buffers),
    );
    await tester.pumpAndSettle();

    expect(
      buffers.scrolledCount,
      greaterThan(0),
      reason: 'the extent moved and overlapped, so the buffer was carried '
          'rather than composited whole',
    );
  });

  testWidgets('a pan that clears the old rect entirely composites whole', (
    tester,
  ) async {
    // ⛔THE CONTROL. With no overlap there is nothing to carry, and the code
    // must say so rather than blitting an empty rect and leaving a hole.
    final cache = await warmCache(tester);
    final buffers = DisplayBufferCache();
    addTearDown(buffers.dispose);

    await tester.pumpWidget(
      stackAt(CanvasViewport(zoom: 4, panX: 0, panY: 0), cache, buffers),
    );
    await tester.pumpAndSettle();
    final carriedBefore = buffers.scrolledCount;

    // Far enough that the visible window shares no canvas pixel with the
    // first one.
    await tester.pumpWidget(
      stackAt(CanvasViewport(zoom: 4, panX: -400, panY: -400), cache, buffers),
    );
    await tester.pumpAndSettle();

    expect(
      buffers.scrolledCount,
      carriedBefore,
      reason: 'nothing overlapped, so nothing was carried',
    );
  });

  testWidgets('the carry composites LESS than the whole rect', (tester) async {
    // 🚨THE COUNTER SAYS IT RAN; THIS SAYS IT SAVED SOMETHING. 🧪A mutation
    // that dropped the subtraction left the clip covering the whole rect:
    // correct pixels, no saving, and every other test green. That is the
    // shape this file exists to refuse.
    final cache = await warmCache(tester);
    final buffers = DisplayBufferCache();
    addTearDown(buffers.dispose);

    await tester.pumpWidget(
      stackAt(CanvasViewport(zoom: 2, panX: 0, panY: 0), cache, buffers),
    );
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      stackAt(CanvasViewport(zoom: 2, panX: 5, panY: 4), cache, buffers),
    );
    await tester.pumpAndSettle();

    final area = buffers.lastComposedArea;
    expect(area, isNotNull, reason: 'fixture: a carry happened');
    // ⛔ZERO IS THE BEST ANSWER, not a failure: when the new extent is a
    // SUBSET of the old one the whole rect is carried and nothing is
    // composited at all. 🧪The first version of this test demanded area > 0
    // and failed on exactly that case.
    //
    // The claim is the ceiling: the window is 40 logical px at zoom 2 = 20
    // canvas px a side, so a carry that composites near 400 has carried
    // nothing in practice.
    expect(
      area!,
      lessThan(20 * 20 * 0.75),
      reason: 'a carry that composites nearly the whole rect is a carry in '
          'name only',
    );
  });
}
