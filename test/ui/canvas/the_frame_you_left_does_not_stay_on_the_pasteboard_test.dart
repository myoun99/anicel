import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/bitmap_tile_image_cache.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/canvas/display_buffer_cache.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';

/// 🚨★★★THE FRAME YOU LEFT DOES NOT STAY ON THE PASTEBOARD (F-104,
/// 2026-09-12).
///
/// 유저: 「페이스트 보드에 이전 프레임의 그림이 남아있음 … 그 위치에 선을
/// 그리면 사라짐. 즉 디스플레이에만 남아있는듯」 · 「그렇게 사라져도
/// 이전프레임 갔다가 다시 돌아오면 똑같이 그림이 남아있음」.
///
/// 🔬Reproduced here before the fix (2026-09-15): switching the active cel is
/// a change of the LIVE surface only, so the display buffer CARRIES the
/// buffer it made for the frame before and recomposes where the live surface
/// moved. The patch cleared that rect before painting it again; the scroll
/// carry — the route a changed extent takes — painted over what it carried
/// without clearing, so wherever the frame you went to draws nothing, the
/// frame you came from stayed. It shows on the pasteboard because that is
/// where two frames' extents differ: frame B's own ink stretches the buffer
/// over the spot where frame A had ink.
void main() {
  const canvasSize = CanvasSize(width: 32, height: 32);
  const tileSize = 16;
  const view = Size(96, 96);
  const backdrop = [128, 128, 128];

  Uint8List rgba(int r, int g, int b) {
    final bytes = Uint8List(tileSize * tileSize * 4);
    for (var i = 0; i < bytes.length; i += 4) {
      bytes[i] = r;
      bytes[i + 1] = g;
      bytes[i + 2] = b;
      bytes[i + 3] = 255;
    }
    return bytes;
  }

  BitmapSurface surfaceWith(Map<TileCoord, BitmapTile> tiles) =>
      BitmapSurface(canvasSize: canvasSize, tileSize: tileSize, tiles: tiles);

  for (final zoom in [1.0, 0.5]) {
    testWidgets('🚨at zoom $zoom, going A → B → A → B never shows A\'s ink '
        'where B has none', (tester) async {
      final tiles = BitmapTileImageCache();
      final cache = DisplayBufferCache();
      addTearDown(cache.dispose);
      // Frame A: red at tile (-1, 1), canvas (-16..0, 16..32).
      final frameA = surfaceWith({
        TileCoord(x: -1, y: 1): BitmapTile(
          size: tileSize,
          pixels: rgba(255, 0, 0),
        ),
      });
      // Frame B: nothing there, and blue ink of its own at tile (-2, 0) —
      // which is what stretches its extent over A's red.
      final frameB = surfaceWith({
        TileCoord(x: -2, y: 0): BitmapTile(
          size: tileSize,
          pixels: rgba(0, 0, 255),
        ),
      });
      await tester.runAsync(() async {
        final all = [...frameA.tiles.entries, ...frameB.tiles.entries];
        for (final entry in all) {
          tiles.pictureFor((coord: entry.key, tile: entry.value));
        }
        while (all.any((entry) => tiles.imageFor(entry.value) == null)) {
          await Future<void>.delayed(const Duration(milliseconds: 1));
        }
      });
      final viewport = CanvasViewport(zoom: zoom, panX: 32, panY: 32);
      Offset onScreen(double x, double y) =>
          Offset(32 + x * zoom, 32 + y * zoom);
      // The middle of A's red tile, and of B's blue one.
      final whereAWas = onScreen(-8, 24);
      final whereBIs = onScreen(-24, 8);

      Future<CustomPainter> show(BitmapSurface surface) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: view.width,
                  height: view.height,
                  child: CanvasLayerStackView(
                    nodes: const [
                      CompositeLeaf<CanvasStackRow>(
                        CanvasActiveLayerRow(opacity: 1),
                      ),
                    ],
                    imageCache: LayerFrameImageCache(
                      frameStore: BrushFrameStore(),
                    ),
                    canvasSize: canvasSize,
                    viewport: viewport,
                    activeSurfacePainter: BitmapSurfacePainter(
                      surface: surface,
                      tileImageCache: tiles,
                      showTransparentBackground: false,
                    ),
                    paintPaper: true,
                    paperBackground: ProjectBackground.defaultBackground,
                    debugBufferCache: cache,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
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

      /// [stack] painted over a grey backdrop, read at [at]: grey is
      /// "nothing drawn there" — the pasteboard is transparent in the stack.
      Future<List<int>> colorAt(CustomPainter stack, Offset at) async {
        final bytes = await tester.runAsync(() async {
          final recorder = ui.PictureRecorder();
          final canvas = Canvas(recorder);
          canvas.drawRect(
            Offset.zero & view,
            Paint()..color = const Color(0xFF808080),
          );
          stack.paint(canvas, view);
          final picture = recorder.endRecording();
          final image = picture.toImageSync(
            view.width.round(),
            view.height.round(),
          );
          picture.dispose();
          final data = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          image.dispose();
          return data!.buffer.asUint8List();
        });
        final i = (at.dy.round() * view.width.round() + at.dx.round()) * 4;
        return [bytes![i], bytes[i + 1], bytes[i + 2]];
      }

      for (final visit in [1, 2]) {
        final a = await show(frameA);
        expect(
          await colorAt(a, whereAWas),
          [255, 0, 0],
          reason: 'control (visit $visit): frame A has its ink there',
        );
        final carried = cache.scrolledCount;
        final b = await show(frameB);
        expect(
          await colorAt(b, whereBIs),
          [0, 0, 255],
          reason: 'control (visit $visit): the stack is showing frame B — '
              'its own ink is there',
        );
        expect(
          cache.scrolledCount,
          carried + 1,
          reason: 'control (visit $visit): frame B was composed by CARRYING '
              'frame A\'s buffer — a buffer rastered from nothing would '
              'pass the next line without testing anything',
        );
        expect(
          await colorAt(b, whereAWas),
          backdrop,
          reason: 'visit $visit: frame B has nothing where frame A had ink, '
              'so nothing may be drawn there — A\'s ink staying is F-104',
        );
      }
    });
  }
}
