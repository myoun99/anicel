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
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/models/playback_quality.dart';
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
import 'package:anicel/src/ui/canvas/subtree_image_composite.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';

/// 🚨★★★THE GROUP CACHE ALREADY EXISTS, AND MAKING A GROUP AN IMAGE IS WHAT
/// FINISHED IT.
///
/// `StaticCompositeBake` records the part of the composite a stroke cannot
/// change into a `ui.Picture` and replays it. While a folder was a
/// `saveLayer`, replaying that picture re-executed the offscreen every frame
/// — the bake's own note said so: *"What it does NOT skip is the ENGINE
/// replaying the display list: … every stroke step still re-executes 500
/// draws and every folder's `saveLayer`."*
///
/// A folder is a `ui.Image` now, and a recorded picture holds its own
/// reference to the images it draws. So the replay redraws a finished image
/// and the folder's raster happens ONCE — which is what a per-group cache
/// would have been built to do. Building a second one would be a copy.
///
/// ⛔A COUNT, not a comparison. A cache that worked and one that did not draw
/// the same picture, so pixels cannot tell them apart.
void main() {
  const canvasSize = CanvasSize(width: 8, height: 8);
  const projectId = ProjectId('p');
  const cutId = CutId('c');
  const trackId = TrackId('t');

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
        tileSize: 4,
      ),
      historyPolicy: const BrushHistoryPolicy(
        userUndoLimit: 8,
        deferredBakeRatio: 0,
      ),
    ).commitSourceStroke(
      sourceDabs: [
        BrushDab(
          center: CanvasPoint(x: 1, y: 1),
          color: 0xFF0000FF,
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
    return LayerFrameImageCache(frameStore: store);
  }

  BitmapSurfacePainter livePainter(int inkX) {
    var tile = BitmapTile.blank(coord: TileCoord(x: 0, y: 0), size: 4);
    tile = writeRgbaColorToBitmapTile(
      tile: tile,
      x: inkX,
      y: 0,
      color: RgbaColor(r: 255, g: 0, b: 0, a: 255),
    );
    return BitmapSurfacePainter(
      surface: BitmapSurface(
        canvasSize: canvasSize,
        tileSize: 4,
        tiles: {tile.coord: tile},
      ),
      showTransparentBackground: false,
    );
  }

  /// A folder holding a DRAWN row — content a stroke on another layer cannot
  /// move — under the live layer.
  CanvasLayerStackNode staticFolder(String id) => CanvasLayerGroupNode(
    children: [
      CanvasLayerImageNode(
        CanvasLayerImageRequest(frameKey: keyFor(id), opacity: 1),
      ),
    ],
    opacity: 0.5,
    blendMode: LayerBlendMode.multiply,
  );

  /// 🚨A STROKE STEP, as the stack sees one: the live surface's pixels move
  /// and NOTHING else does. That is what the composite key leaves the active
  /// surface out for, and it is the only way to make the display buffer miss
  /// while the bake still holds.
  Future<void> strokeStep(
    WidgetTester tester, {
    required List<CanvasLayerStackNode> tree,
    required LayerFrameImageCache cache,
    required int inkX,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 64,
              height: 64,
              child: CanvasLayerStackView(
                nodes: tree,
                imageCache: cache,
                canvasSize: canvasSize,
                viewport: CanvasViewport(zoom: 1, panX: 0, panY: 0),
                activeSurfacePainter: livePainter(inkX),
                paintPaper: true,
                paperBackground: ProjectBackground.defaultBackground,
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
    const size = Size(64, 64);
    final recorder = ui.PictureRecorder();
    painted.first.painter!.paint(
      Canvas(recorder, Offset.zero & size),
      size,
    );
    recorder.endRecording().dispose();
  }

  testWidgets('a folder a stroke cannot change rasterises ONCE across steps', (
    tester,
  ) async {
    final cache = cacheWithStroke('under');
    final tree = [
      staticFolder('under'),
      const CanvasActiveLayerNode(opacity: 1),
    ];
    // ⚠️Warm the row's image first: the cache builds it across a real async
    // round trip, and an unresolved row is DROPPED from the tree — the
    // folder would then be empty and never raster at all.
    await tester.runAsync(
      () => cache.prepare(
        key: keyFor('under'),
        canvasSize: canvasSize,
        quality: PlaybackQuality.full,
        sourceEffects: const [],
      ),
    );
    debugSubtreeRasterCount = 0;
    for (var step = 0; step < 4; step++) {
      await strokeStep(tester, tree: tree, cache: cache, inkX: step);
    }
    // ⛔EXACTLY ONE, counted from before the first step — "it did not grow"
    // would pass on a scene where the folder never rastered at all.
    expect(
      debugSubtreeRasterCount,
      1,
      reason: 'one folder, four stroke steps: the bake holds it as a '
          'finished image and the replay redraws that image',
    );
  });

  testWidgets('a folder that HOLDS the live layer rasters every step', (
    tester,
  ) async {
    // ⛔The control, and the reason a per-group cache keyed on the tree would
    // be wrong: the composite key leaves the ACTIVE surface out on purpose
    // (a stroke changes its pixels and nothing else), so a folder around it
    // has content that key cannot see. It is not baked, and must not be.
    final cache = cacheWithStroke('unused');
    final tree = [
      const CanvasLayerGroupNode(
        children: [CanvasActiveLayerNode(opacity: 1)],
        opacity: 0.5,
        blendMode: LayerBlendMode.multiply,
      ),
    ];
    debugSubtreeRasterCount = 0;
    for (var step = 0; step < 4; step++) {
      await strokeStep(tester, tree: tree, cache: cache, inkX: step);
    }
    expect(
      debugSubtreeRasterCount,
      4,
      reason: 'the live layer is inside this folder, so every step is a '
          'different picture',
    );
  });
}
