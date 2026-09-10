import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/models/rgba_color.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/bitmap_tile_rgba.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/canvas/selection_float_overlay.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';

/// 🚨F-68 ③ (유저 2026-09-11, Windows debug AND iPad release): 「축소시
/// 변형툴 밖의 이전그림 위치에 그림 생기는건 여전히 존재. 펜으로 바꿔서
/// 그부분 그리려하면 정상적으로 사라짐. 진짜 보이는거만 문제인듯.」
///
/// The display buffer patches a miss over the KEPT image, repainting only
/// where the live surface changed. It asked "changed since when?" of
/// tokens it re-recorded on EVERY paint — including the paints that kept
/// nothing (a floating selection makes the buffer uncacheable for the
/// whole session). So after a lift (erase, float up: nothing kept) and a
/// confirm (float gone: cacheable again), the base was the buffer from
/// BEFORE the lift and the dirty rect was only what the confirm changed:
/// the erased ring came back from the old buffer, and stayed until
/// something else repainted it — the pen, another transform, a full
/// raster. Every platform, because this is the buffer and not the tiles.
///
/// The tokens belong to the KEPT image now: written with it, in `store`,
/// and never by a paint that keeps nothing.
void main() {
  // Two tiles across, one down — a ring needs a tile the landing does not
  // touch, or the dirty rect is the whole canvas and nothing can go stale.
  const canvasSize = CanvasSize(width: 8, height: 4);
  final red = RgbaColor(r: 255, g: 0, b: 0, a: 255);
  final blue = RgbaColor(r: 0, g: 0, b: 255, a: 255);

  BitmapTile inked(int x, int y, RgbaColor color) => writeRgbaColorToBitmapTile(
    tile: BitmapTile.blank(size: 4),
    x: x,
    y: y,
    color: color,
  );

  BitmapSurfacePainter painterOf(Map<TileCoord, BitmapTile> tiles) =>
      BitmapSurfacePainter(
        surface: BitmapSurface(
          canvasSize: canvasSize,
          tileSize: 4,
          tiles: tiles,
        ),
        showTransparentBackground: false,
      );

  testWidgets('a patch repaints everything that changed since the KEPT '
      'buffer, not since the last paint', (tester) async {
    final float = SelectionFloatOverlay(null);
    addTearDown(float.dispose);

    Future<void> pumpWith(BitmapSurfacePainter active) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 8,
                height: 4,
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
                  viewport: CanvasViewport(),
                  activeSurfacePainter: active,
                  floatOverlay: float,
                  paintPaper: true,
                  paperBackground: const ProjectBackground.color(0xFF00FF00),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    CustomPainter painter() => tester
        .widgetList<CustomPaint>(
          find.descendant(
            of: find.byType(CanvasLayerStackView),
            matching: find.byType(CustomPaint),
          ),
        )
        .where((paint) => paint.painter != null)
        .first
        .painter!;

    Future<Uint8List> shot() async =>
        (await tester.runAsync(() => _rasterize(painter())))!;
    bool isRed(Uint8List px, int x, int y) =>
        px[(y * 8 + x) * 4] > 200 && px[(y * 8 + x) * 4 + 1] < 60;

    // The picture before the lift: red in the LEFT tile, blue in the
    // right. Warm until the buffer holds it — the first paint is a cold
    // miss and the next misses again when the decodes land.
    final left = inked(1, 1, red);
    final right = inked(1, 1, blue);
    await pumpWith(painterOf({TileCoord(x: 0, y: 0): left, TileCoord(x: 1, y: 0): right}));
    var before = await shot();
    for (var i = 0; i < 6 && !isRed(before, 1, 1); i += 1) {
      before = await shot();
    }
    expect(isRed(before, 1, 1), isTrue, reason: 'the red pixel never reached the buffer — bad premise');

    // The LIFT: the left tile is erased (dropped) and its pixels float,
    // drawn one tile to the right. A floating selection keeps the buffer
    // from being stored, so this paint keeps nothing.
    float.value = SelectionFloatPaint(
      surface: painterOf({TileCoord(x: 0, y: 0): left}),
      surfaceOffset: CanvasPoint(x: 4, y: 0),
    );
    await pumpWith(painterOf({TileCoord(x: 1, y: 0): right}));
    final lifted = await shot();
    expect(isRed(lifted, 1, 1), isFalse, reason: 'the erase did not show — bad premise');
    expect(isRed(lifted, 5, 1), isTrue, reason: 'the float did not show — bad premise');

    // The CONFIRM: the float lands in the RIGHT tile (a new tile object
    // there) and the float goes. The left tile stays erased — nothing on
    // this paint touches it, and that is the whole point.
    float.value = null;
    final landed = writeRgbaColorToBitmapTile(tile: right, x: 1, y: 1, color: red);
    await pumpWith(painterOf({TileCoord(x: 1, y: 0): landed}));
    final confirmed = await shot();
    expect(
      isRed(confirmed, 1, 1),
      isFalse,
      reason:
          'the erased tile shows the picture from BEFORE the lift: the '
          'patch measured its dirty rect from the last paint instead of '
          'from the kept buffer',
    );
  });
}

Future<Uint8List> _rasterize(CustomPainter painter) async {
  final recorder = ui.PictureRecorder();
  const size = Size(8, 4);
  final canvas = Canvas(recorder, Offset.zero & size);
  painter.paint(canvas, size);
  final image = await recorder.endRecording().toImage(8, 4);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  return bytes!.buffer.asUint8List();
}
