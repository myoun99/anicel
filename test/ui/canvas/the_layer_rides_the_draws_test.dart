import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/models/rgba_color.dart';
import 'package:anicel/src/services/bitmap_tile_rgba.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/canvas/selection_float_overlay.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/bitmap_tile_image_cache.dart';

/// 🚨★★★THE LAYER RIDES THE DRAWS — and it is the same pixels the buffer made.
///
/// A layer's opacity and blend have to apply to the LAYER once. Wrapping the
/// painter in a `saveLayer` is one way; handing the same paint to each draw
/// is another. They agree exactly when no two draws land on the same pixel,
/// which is what [BitmapSurfacePainter.drawsDisjointCoverage] answers.
///
/// ⛔The law is not new. The overlay's own blend already rides it one level
/// down — *"BB-1: the brush blend previews live (tiles never overlap, so
/// per-tile draws blend each pixel exactly once)"*. This asks the same
/// question about the LAYER's paint.
///
/// ⚠️THE TILE PAINT IS WHY IT HOLDS. `isAntiAlias = false` +
/// `FilterQuality.none` is what makes adjacent tiles disjoint in DEVICE
/// pixels, not only in canvas units. A first draft of this comparison used
/// the default paint and saw seams at fractional scale — that was the
/// probe's antialiasing, not the painter's.
void main() {
  const canvasSize = CanvasSize(width: 64, height: 64);
  const tileSize = 16;

  BitmapSurface inkedSurface() {
    final tiles = <TileCoord, BitmapTile>{};
    for (var ty = 0; ty < 2; ty++) {
      for (var tx = 0; tx < 2; tx++) {
        final pixels = Uint8List(tileSize * tileSize * 4);
        for (var i = 0; i < tileSize * tileSize; i++) {
          // Straight bytes; a translucent fifth so the blend has alpha to
          // work with.
          final alpha = i % 5 == 0 ? 128 : 255;
          pixels[i * 4] = (tx * 71 + i * 3) % 256;
          pixels[i * 4 + 1] = (ty * 37 + i * 5) % 256;
          pixels[i * 4 + 2] = (tx * 13 + ty * 91 + i) % 256;
          pixels[i * 4 + 3] = alpha;
        }
        final coord = TileCoord(x: tx, y: ty);
        tiles[coord] = BitmapTile(
          coord: coord,
          size: tileSize,
          pixels: pixels,
        );
      }
    }
    return BitmapSurface(
      canvasSize: canvasSize,
      tileSize: tileSize,
      tiles: tiles,
    );
  }

  Future<Uint8List> render({
    required BitmapSurfacePainter painter,
    required Paint Function() layerPaint,
    required bool buffered,
    required double scale,
    required double phase,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    // A backdrop with structure, so a blend mode has something to read.
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 64, 64),
      Paint()..color = const Color(0xFF3070B0),
    );
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 32, 64),
      Paint()..color = const Color(0xFFC0D040),
    );
    canvas.save();
    canvas.translate(phase, phase);
    canvas.scale(scale);
    if (buffered) {
      canvas.saveLayer(painter.pasteboardRect, layerPaint());
    }
    canvas.save();
    canvas.clipRect(painter.pasteboardRect);
    painter.paintContentInto(
      canvas,
      layerPaint: buffered ? null : layerPaint(),
    );
    canvas.restore();
    if (buffered) {
      canvas.restore();
    }
    canvas.restore();
    final picture = recorder.endRecording();
    final image = picture.toImageSync(64, 64);
    picture.dispose();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    return bytes!.buffer.asUint8List();
  }

  // ⛔A FRESH CACHE PER RENDER. The painter STARTS decodes as it draws and
  // rations a per-pixel fallback budget, so a second render through the
  // same cache sees a different world than the first — the two would be
  // comparing different content and calling it a difference in the layer.
  BitmapSurfacePainter freshPainter() => BitmapSurfacePainter(
    surface: inkedSurface(),
    showTransparentBackground: false,
    tileImageCache: BitmapTileImageCache(),
  );

  Future<void> expectSamePixels(
    String what,
    Paint Function() layerPaint, {
    double scale = 1,
    double phase = 0,
  }) async {
    final painter = freshPainter();
    // ⛔The precondition, not an assumption: the whole equivalence is
    // conditional on it, so a fixture that quietly stopped being disjoint
    // would make every comparison below vacuous.
    expect(painter.drawsDisjointCoverage, isTrue, reason: '$what: fixture');
    final buffered = await render(
      painter: freshPainter(),
      layerPaint: layerPaint,
      buffered: true,
      scale: scale,
      phase: phase,
    );
    final riding = await render(
      painter: freshPainter(),
      layerPaint: layerPaint,
      buffered: false,
      scale: scale,
      phase: phase,
    );
    expect(
      buffered.any((byte) => byte != 0),
      isTrue,
      reason: '$what drew nothing at all',
    );
    var differing = 0;
    var worst = 0;
    for (var i = 0; i < buffered.length; i += 4) {
      var delta = 0;
      for (var c = 0; c < 4; c++) {
        final d = (buffered[i + c] - riding[i + c]).abs();
        if (d > delta) delta = d;
      }
      if (delta > 0) {
        differing += 1;
        if (delta > worst) worst = delta;
      }
    }
    expect(
      differing,
      0,
      reason: '$what: the layer riding the draws must be the buffer, pixel '
          'for pixel — $differing differ, worst channel delta $worst',
    );
  }

  group('the buffer and the riding paint are the same pixels', () {
    test('opacity', () async {
      await expectSamePixels(
        'opacity 0.5',
        () => Paint()..color = const Color(0x80000000),
      );
    });

    test('blend mode', () async {
      await expectSamePixels(
        'multiply',
        () => Paint()
          ..color = const Color(0xFF000000)
          ..blendMode = BlendMode.multiply,
      );
      await expectSamePixels(
        'screen',
        () => Paint()
          ..color = const Color(0xFF000000)
          ..blendMode = BlendMode.screen,
      );
    });

    test('blend and opacity together', () async {
      await expectSamePixels(
        'multiply at 0.5',
        () => Paint()
          ..color = const Color(0x80000000)
          ..blendMode = BlendMode.multiply,
      );
    });

    test('a colour filter rides too — it is per pixel', () async {
      await expectSamePixels(
        'saturation matrix at 0.5',
        () => Paint()
          ..color = const Color(0x80000000)
          ..colorFilter = const ColorFilter.matrix(<double>[
            0.6, 0.3, 0.1, 0, 0, //
            0.2, 0.7, 0.1, 0, 0, //
            0.2, 0.3, 0.5, 0, 0, //
            0, 0, 0, 1, 0, //
          ]),
      );
    });

    test('at fractional scale and phase, where a seam would show', () async {
      // 🚨THE CASE THE TILE PAINT EARNS. Adjacent tiles have to be disjoint
      // in DEVICE pixels, not only in canvas units.
      Paint multiplyHalf() => Paint()
        ..color = const Color(0x80000000)
        ..blendMode = BlendMode.multiply;
      await expectSamePixels('scale 1.37', multiplyHalf, scale: 1.37, phase: 0.42);
      await expectSamePixels('scale 0.63', multiplyHalf, scale: 0.63, phase: 0.17);
      await expectSamePixels('scale 2', multiplyHalf, scale: 2);
      await expectSamePixels('phase 0.5', multiplyHalf, phase: 0.5);
    });
  });

  group('when a pixel would be touched twice, the answer is no', () {
    test('the paper rect sits under every tile', () {
      final painter = BitmapSurfacePainter(
        surface: inkedSurface(),
        // The standalone route paints its own paper; the merged stack
        // passes false and paints paper itself.
        showTransparentBackground: true,
      );
      expect(painter.drawsDisjointCoverage, isFalse);
    });

    test('no overlay at all is disjoint', () {
      final painter = BitmapSurfacePainter(
        surface: inkedSurface(),
        showTransparentBackground: false,
      );
      expect(painter.drawsDisjointCoverage, isTrue);
    });
  });

  group('when the live layer opens a buffer, and when it does not', () {
    // 🚨THE DECISION, READ AT THE ROUTE. The two routes are the same pixels
    // — that is the point — so a pixel comparison cannot say WHICH ran.
    const canvasSize = CanvasSize(width: 64, height: 64);

    BitmapSurfacePainter inkedPainter() {
      var tile = BitmapTile.blank(coord: TileCoord(x: 0, y: 0), size: 16);
      tile = writeRgbaColorToBitmapTile(
        tile: tile,
        x: 4,
        y: 4,
        color: RgbaColor(r: 0, g: 0, b: 255, a: 255),
      );
      return BitmapSurfacePainter(
        surface: BitmapSurface(
          canvasSize: canvasSize,
          tileSize: 16,
          tiles: {tile.coord: tile},
        ),
        showTransparentBackground: false,
      );
    }

    Future<void> paintActive(
      WidgetTester tester, {
      required List<ResolvedLayerEffect> effects,
      double opacity = 0.5,
      SelectionFloatOverlay? floatOverlay,
    }) async {
      debugLiveLayerRodeTheDraws = null;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 200,
                height: 150,
                child: CanvasLayerStackView(
                  nodes: [
                    CanvasActiveLayerNode(opacity: opacity, effects: effects),
                  ],
                  imageCache: LayerFrameImageCache(
                    frameStore: BrushFrameStore(),
                  ),
                  canvasSize: canvasSize,
                  viewport: CanvasViewport(zoom: 1, panX: 0, panY: 0),
                  activeSurfacePainter: inkedPainter(),
                  paintPaper: true,
                  paperBackground: const ProjectBackground.color(0xFFFFFFFF),
                  floatOverlay: floatOverlay,
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
      const size = Size(200, 150);
      final recorder = ui.PictureRecorder();
      painted.first.painter!.paint(Canvas(recorder, Offset.zero & size), size);
      recorder.endRecording().dispose();
    }

    testWidgets('opacity alone rides the draws', (tester) async {
      await paintActive(tester, effects: const []);
      expect(
        debugLiveLayerRodeTheDraws,
        isTrue,
        reason: 'nothing here touches a pixel twice',
      );
    });

    testWidgets('a SPREADING filter still needs the buffer', (tester) async {
      // A blur has to see across the tile boundaries, which a per-draw paint
      // cannot do however disjoint the draws are.
      await paintActive(
        tester,
        effects: [
          ResolvedLayerEffect(
            kind: EffectKind.blur,
            values: const [4, 4],
          ),
        ],
      );
      expect(debugLiveLayerRodeTheDraws, isFalse);
    });

    testWidgets('a colour-only filter does NOT need it', (tester) async {
      // ⛔The other side of the same question: a matrix is per-pixel, so
      // "has effects" would have been the wrong test.
      await paintActive(
        tester,
        effects: [
          ResolvedLayerEffect(
            kind: EffectKind.brightnessContrast,
            values: const [0.2, 0],
          ),
        ],
      );
      expect(debugLiveLayerRodeTheDraws, isTrue);
    });

    testWidgets('a selection FLOAT still needs the buffer', (tester) async {
      // The float is this layer's own pixels lifted out and drawn back over
      // it — an overlap the painter cannot see because it is not the
      // painter's.
      final float = SelectionFloatOverlay(
        SelectionFloatPaint(surface: inkedPainter()),
      );
      addTearDown(float.dispose);
      await paintActive(tester, effects: const [], floatOverlay: float);
      expect(debugLiveLayerRodeTheDraws, isFalse);
    });

    testWidgets('an EMPTY float overlay does not', (tester) async {
      // Mounted with nothing in it: it draws nothing and overlaps nothing.
      final float = SelectionFloatOverlay(SelectionFloatPaint());
      addTearDown(float.dispose);
      await paintActive(tester, effects: const [], floatOverlay: float);
      expect(debugLiveLayerRodeTheDraws, isTrue);
    });
  });
}
