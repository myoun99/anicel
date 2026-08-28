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

/// 🚨★★★A PAN REPAINTS. IT MUST NOT RE-COMPOSITE.
///
/// The composite key hashed the whole `CanvasViewport`, from the days when
/// the display buffer was `pasteboard ∩ visibleRect` — an extent the
/// viewport moved directly. #1301 made the extent CONTENT ∩ view, and the
/// cache has compared the rect all along, so the viewport reached these
/// pixels through the extent and nothing else.
///
/// ⛔THE PIXELS MAY NOT CHANGE. 유저 2026-08-28: 「화면에서 보이는건
/// 바뀌면안되고」. So the first test compares BYTES across a viewport move,
/// and the second one counts.
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
        BrushDab(
          center: CanvasPoint(x: 6, y: 6),
          color: 0xFF0000FF,
          size: 5,
          opacity: 1,
          flow: 1,
          hardness: 1,
          tipShape: BrushTipShape.round,
          pressure: 1,
          sequence: 0,
        ),
      ],
    );
    return LayerFrameImageCache(frameStore: store);
  }

  /// ⛔ONE painter for the whole test: a fresh `BitmapSurface` object has a
  /// fresh identity, and the buffer key hashes that on purpose (a stroke
  /// step is exactly "the surface changed and nothing else"). Rebuilding it
  /// per pump would invalidate the cache from the FIXTURE and hide whatever
  /// the code does.
  BitmapSurfacePainter buildLivePainter() {
    var tile = BitmapTile.blank(coord: TileCoord(x: 0, y: 0), size: 8);
    tile = writeRgbaColorToBitmapTile(
      tile: tile,
      x: 2,
      y: 2,
      color: RgbaColor(r: 255, g: 0, b: 0, a: 255),
    );
    return BitmapSurfacePainter(
      surface: BitmapSurface(
        canvasSize: canvasSize,
        tileSize: 8,
        tiles: {tile.coord: tile},
      ),
      showTransparentBackground: false,
    );
  }

  final live = buildLivePainter();

  /// ⛔ONE node list too: a fresh request object changes the tree signature,
  /// which is the key doing its job — and would hide what this test is for.
  final nodes = <CanvasLayerStackNode>[
    CanvasLayerImageNode(
      CanvasLayerImageRequest(frameKey: keyFor('under'), opacity: 1),
    ),
    const CanvasActiveLayerNode(opacity: 1),
  ];

  /// Mounts the stack at [viewport] and lets it paint ITSELF, once.
  ///
  /// ⛔The counting tests use this and not [screenAt]: replaying the painter
  /// by hand is a SECOND composite the app never performs, and it lands in
  /// the same counter.
  Future<void> pumpAt(
    WidgetTester tester, {
    required CanvasViewport viewport,
    required LayerFrameImageCache cache,
    required DisplayBufferCache buffers,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 160,
              height: 160,
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
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Paints the stack at [viewport] and hands back the bytes the SCREEN got.
  ///
  /// ⛔The whole picture, not the buffer: what the user sees is the buffer
  /// drawn through the CTM, and a cache that kept a stale image would show
  /// up here and nowhere else.
  Future<Uint8List> screenAt(
    WidgetTester tester, {
    required CanvasViewport viewport,
    required LayerFrameImageCache cache,
    required DisplayBufferCache buffers,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 160,
              height: 160,
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
      ),
    );
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
    const size = Size(160, 160);
    final recorder = ui.PictureRecorder();
    painted.first.painter!.paint(Canvas(recorder, Offset.zero & size), size);
    final picture = recorder.endRecording();
    final image = picture.toImageSync(160, 160);
    picture.dispose();
    final bytes = await tester.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
    );
    image.dispose();
    return bytes!.buffer.asUint8List();
  }

  testWidgets('panning while the page fits does not re-composite', (
    tester,
  ) async {
    final cache = cacheWithStroke('under');
    await tester.runAsync(
      () => cache.prepare(
        key: keyFor('under'),
        canvasSize: canvasSize,
        quality: PlaybackQuality.full,
        sourceEffects: const [],
      ),
    );
    final buffers = DisplayBufferCache();
    addTearDown(buffers.dispose);

    await pumpAt(
      tester,
      viewport: CanvasViewport(zoom: 1, panX: 0, panY: 0),
      cache: cache,
      buffers: buffers,
    );
    final composedOnce = buffers.fullCount + buffers.patchedCount;
    expect(
      composedOnce,
      greaterThan(0),
      reason: 'fixture: the first paint composited something',
    );

    // The page is 32x32 inside a 64x64 view, so it fits whole — the extent
    // is CONTENT-bounded and a pan does not move it.
    await pumpAt(
      tester,
      viewport: CanvasViewport(zoom: 1, panX: 4, panY: 3),
      cache: cache,
      buffers: buffers,
    );

    expect(
      buffers.fullCount + buffers.patchedCount,
      composedOnce,
      reason: 'the extent did not move, so the composite is still right — '
          'panning repaints, it does not re-composite',
    );
  });

  testWidgets('and the screen shows the SAME pixels the walk would', (
    tester,
  ) async {
    // ⛔THE POINT OF THE WHOLE CHANGE. 유저: 「화면에서 보이는건 바뀌면안되고」.
    // A cache that hands back an image it should have dropped looks exactly
    // like one that is right — until the bytes are compared.
    final cache = cacheWithStroke('under');
    await tester.runAsync(
      () => cache.prepare(
        key: keyFor('under'),
        canvasSize: canvasSize,
        quality: PlaybackQuality.full,
        sourceEffects: const [],
      ),
    );

    final moved = CanvasViewport(zoom: 1, panX: 4, panY: 3);

    // A: warm at one viewport, then move — the cached path.
    final warm = DisplayBufferCache();
    addTearDown(warm.dispose);
    await screenAt(
      tester,
      viewport: CanvasViewport(zoom: 1, panX: 0, panY: 0),
      cache: cache,
      buffers: warm,
    );
    final cached = await screenAt(
      tester,
      viewport: moved,
      cache: cache,
      buffers: warm,
    );

    // B: a COLD cache at the moved viewport — nothing kept, everything
    // composited from nothing.
    final cold = DisplayBufferCache();
    addTearDown(cold.dispose);
    final fresh = await screenAt(
      tester,
      viewport: moved,
      cache: cache,
      buffers: cold,
    );

    expect(
      cached,
      fresh,
      reason: 'the kept buffer draws the same screen a cold composite does — '
          'byte for byte, or the key dropped something it needed',
    );
  });

  testWidgets('a ZOOM that changes the extent still re-composites', (
    tester,
  ) async {
    // ⛔THE CONTROL, and the half that keeps this honest: the extent is
    // CONTENT ∩ VIEW, so a zoom that shrinks the view below the page moves
    // it — and then the buffer must be rebuilt. A key that never
    // invalidated would pass the two tests above and be wrong here.
    final cache = cacheWithStroke('under');
    await tester.runAsync(
      () => cache.prepare(
        key: keyFor('under'),
        canvasSize: canvasSize,
        quality: PlaybackQuality.full,
        sourceEffects: const [],
      ),
    );
    final buffers = DisplayBufferCache();
    addTearDown(buffers.dispose);

    await pumpAt(
      tester,
      viewport: CanvasViewport(zoom: 1, panX: 0, panY: 0),
      cache: cache,
      buffers: buffers,
    );
    final afterFirst = buffers.fullCount + buffers.patchedCount;

    // Zoom to 8x: the 160px view now sees 20 canvas px — LESS than the 32px
    // page — so the extent becomes the view, and it moved.
    // ⚠️4x was not enough and that is worth writing down: 160/4 = 40 canvas
    // px still holds the whole page, so the extent never moved and the
    // buffer was CORRECTLY kept. Zooming stops re-compositing too, for as
    // long as the page fits.
    await pumpAt(
      tester,
      viewport: CanvasViewport(zoom: 8, panX: 0, panY: 0),
      cache: cache,
      buffers: buffers,
    );

    expect(
      buffers.fullCount + buffers.patchedCount,
      greaterThan(afterFirst),
      reason: 'the extent moved, so the buffer had to be rebuilt — the rect '
          'is the guard, and it did its job',
    );
  });
}
