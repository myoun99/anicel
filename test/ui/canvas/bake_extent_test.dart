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
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_edit_session_store.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/canvas/static_composite_bake.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';

/// 🚨A3 — THE BAKE'S RECORDINGS DEPEND ON THE EXTENT, AND THE KEY CANNOT
/// SAY SO.
///
/// [StaticCompositeBake.keepFor]'s key is built at BUILD time from widget
/// fields; the visible rect is a LAYOUT fact. Resize the panel at a fixed
/// zoom and the key is unchanged while every recording is wrong: the
/// record closures captured the old bounds, and `drawRaster` blitted the
/// OLD image with a src rect computed from the NEW dimensions. Same
/// document, two pictures, decided by resize history.
///
/// The law being defended is I2: a rendered pixel is a function of
/// (artwork, viewport, canvas size) — never of what the panel did five
/// minutes ago.
void main() {
  Future<Uint8List> rasterBytes(
    void Function(Canvas canvas) paintBody,
    int width,
    int height,
  ) async {
    final recorder = ui.PictureRecorder();
    paintBody(Canvas(recorder));
    final picture = recorder.endRecording();
    final image = picture.toImageSync(width, height);
    picture.dispose();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    return bytes!.buffer.asUint8List();
  }

  test('a changed extent re-records the raster instead of stretching the '
      'old one', () async {
    final bake = StaticCompositeBake();
    addTearDown(bake.dispose);
    bake.keepFor('key');

    // The world is 8 wide: a red field recorded over it.
    const narrow = Rect.fromLTWH(0, 0, 8, 8);
    void recordNarrow(Canvas canvas) {
      canvas.drawRect(narrow, Paint()..color = const Color(0xFFFF0000));
    }

    await rasterBytes(
      (canvas) {
        bake.ensureExtent(narrow);
        bake.drawRaster(canvas, 'd0', narrow, recordNarrow);
      },
      8,
      8,
    );
    expect(bake.rasterCount, 1);

    // The panel widens: the same key, a new extent, new content out to 16.
    const wide = Rect.fromLTWH(0, 0, 16, 8);
    void recordWide(Canvas canvas) {
      canvas.drawRect(wide, Paint()..color = const Color(0xFFFF0000));
    }

    final resized = await rasterBytes(
      (canvas) {
        bake.ensureExtent(wide);
        bake.drawRaster(canvas, 'd0', wide, recordWide);
      },
      16,
      8,
    );
    final fresh = await rasterBytes(
      (canvas) {
        final freshBake = StaticCompositeBake()..keepFor('key');
        freshBake.ensureExtent(wide);
        freshBake.drawRaster(canvas, 'd0', wide, recordWide);
        freshBake.dispose();
      },
      16,
      8,
    );
    expect(
      resized,
      fresh,
      reason: 'after a resize the replay must equal a fresh recording — '
          'the old 8-wide raster stretched over 16 is the I2 violation '
          'this exists to stop',
    );
    // And the right corner really is covered — the assertion above cannot
    // be vacuous against an all-transparent pair.
    final corner = ((4 * 16) + 15) * 4;
    expect(fresh[corner + 3], 255, reason: 'the wide record reaches x=15');
  });

  testWidgets('the painter declares its extent — a resized paint equals a '
      'fresh paint at the new size', (tester) async {
    // A 16-wide canvas with INK ON THE RIGHT: the narrow paint's backdrop
    // raster never contains it, so a stale replay after widening is
    // visibly missing the dab. ⛔Uniform paper cannot anchor this test —
    // a clipped stale blit of a solid colour reproduces the fresh render
    // by accident, and the wiring mutation stays green. Measured.
    const canvasSize = CanvasSize(width: 16, height: 8);
    final frameKey = BrushFrameKey(
      projectId: const ProjectId('p'),
      trackId: const TrackId('t'),
      cutId: const CutId('c'),
      layerId: const LayerId('l'),
      frameId: const FrameId('f'),
    );

    LayerFrameImageCache cacheWithRightDab() {
      final store = BrushFrameStore();
      BrushFrameEditingCoordinator(
        initialFrameKey: frameKey,
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
            center: CanvasPoint(x: 13, y: 4),
            color: 0xFF0000FF,
            size: 3,
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

    Future<CustomPainter> pump(double width) async {
      // ⛔The cache is warmed BEFORE the widget mounts, so the stack's
      // synchronous sweep captures the image at first build. Relying on
      // the widget's async resolve under the fake clock is a race — this
      // test lost the dab on one side or the other depending on where the
      // pumps sat relative to runAsync. Measured, twice.
      final cache = cacheWithRightDab();
      await tester.runAsync(
        () => cache.prepare(
          key: frameKey,
          canvasSize: canvasSize,
          quality: PlaybackQuality.full,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: width,
                height: 8,
                child: CanvasLayerStackView(
                  nodes: [
                    CanvasLayerImageNode(
                      CanvasLayerImageRequest(frameKey: frameKey, opacity: 1),
                    ),
                    const CanvasActiveLayerNode(opacity: 1),
                  ],
                  imageCache: cache,
                  canvasSize: canvasSize,
                  viewport: CanvasViewport(),
                  // ⛔A live surface is load-bearing for this test: with
                  // no activeSurfacePainter the stack takes the plain walk
                  // and the bake never engages — the wiring mutation
                  // stayed green against a paper-only fixture. Measured.
                  activeSurfacePainter: BitmapSurfacePainter(
                    surface: BitmapSurface(
                      canvasSize: canvasSize,
                      tileSize: 8,
                      tiles: {
                        for (var x = 0; x < 2; x += 1)
                          TileCoord(x: x, y: 0): BitmapTile.blank(
                            coord: TileCoord(x: x, y: 0),
                            size: 8,
                          ),
                      },
                    ),
                    showTransparentBackground: false,
                  ),
                  paintPaper: true,
                  paperBackground: const ProjectBackground.color(0xFF00FF00),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return tester
          .widgetList<CustomPaint>(
            find.descendant(
              of: find.byType(CanvasLayerStackView),
              matching: find.byType(CustomPaint),
            ),
          )
          .where((paint) => paint.painter != null)
          .first
          .painter!;
    }

    Future<Uint8List> paintAt(CustomPainter painter, Size size) async {
      return rasterBytes(
        (canvas) => painter.paint(canvas, size),
        size.width.round(),
        size.height.round(),
      );
    }

    // Pumps stay OUTSIDE runAsync (the parity suite's discipline): the
    // widget's image-resolve pass needs the test's frame pump, and only
    // the toImage round-trips belong in real-async.
    final narrowPainter = await pump(8);
    final resized = await tester.runAsync(() async {
      // Warm at the narrow size — the backdrop world without the dab —
      // then paint the SAME state wider: the resize path.
      await paintAt(narrowPainter, const Size(8, 8));
      return paintAt(narrowPainter, const Size(16, 8));
    });

    // A fresh state at the wide size is the truth to match.
    final widePainter = await pump(16);
    final fresh = await tester.runAsync(
      () => paintAt(widePainter, const Size(16, 8)),
    );

    bool hasBlue(Uint8List bytes) {
      for (var i = 0; i < bytes.length; i += 4) {
        if (bytes[i + 2] > 128 && bytes[i] < 100 && bytes[i + 1] < 200) {
          return true;
        }
      }
      return false;
    }

    expect(
      hasBlue(fresh!),
      isTrue,
      reason: 'anchor: the wide render actually shows the right-side dab — '
          'without this the equality below could hold between two renders '
          'that both silently lost it',
    );
    expect(
      resized,
      fresh,
      reason: 'same document, same viewport, same canvas — the picture may '
          'not depend on which size was painted first',
    );
  });
}
