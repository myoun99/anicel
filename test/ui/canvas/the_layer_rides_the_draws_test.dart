import 'package:flutter/foundation.dart' show ValueListenable;
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/brush_blend_mode.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/dirty_region.dart';
import 'package:anicel/src/services/brush_live_stroke_rasterizer.dart';
import 'package:anicel/src/ui/canvas/active_stroke_overlay.dart';
import 'package:anicel/src/models/brush_stamp_image.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/cut_piece.dart';
import 'package:anicel/src/ui/brush/cut_piece_preview.dart';
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
import 'package:anicel/src/models/composite_tree.dart';

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

  // 🚨DECODED TILES, NOT THE PER-PIXEL FALLBACK. The production path draws
  // each tile as a decoded IMAGE; the pixel fallback is the first-frame
  // stand-in. A comparison that only ever took the fallback would leave the
  // path that actually runs untested — a mutation that dropped the layer
  // from the tile paint survived exactly that gap.
  final cache = BitmapTileImageCache();

  Future<void> decodeAll(BitmapSurface surface) async {
    for (final entry in surface.tiles.entries) {
      cache.ensureDecoded((coord: entry.key, tile: entry.value));
    }
    while (surface.tiles.values.any((tile) => cache.imageFor(tile) == null)) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
  }

  BitmapSurfacePainter painterOver(BitmapSurface surface) =>
      BitmapSurfacePainter(
        surface: surface,
        showTransparentBackground: false,
        tileImageCache: cache,
      );

  Future<void> expectSamePixels(
    String what,
    Paint Function() layerPaint, {
    double scale = 1,
    double phase = 0,
  }) async {
    final surface = inkedSurface();
    await decodeAll(surface);
    final painter = painterOver(surface);
    // ⛔The precondition, not an assumption: the whole equivalence is
    // conditional on it, so a fixture that quietly stopped being disjoint
    // would make every comparison below vacuous.
    expect(painter.drawsDisjointCoverage, isTrue, reason: '$what: fixture');
    final buffered = await render(
      painter: painter,
      layerPaint: layerPaint,
      buffered: true,
      scale: scale,
      phase: phase,
    );
    final riding = await render(
      painter: painter,
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
        tileImageCache: cache,
      );
      expect(painter.drawsDisjointCoverage, isFalse);
    });


    test('a fill stamp is placed OVER whatever a coordinate holds', () async {
      final surface = inkedSurface();
      await decodeAll(surface);
      final overlay = ActiveStrokeOverlayModel(tileSize: tileSize);
      addTearDown(overlay.dispose);
      // ⛔The fixture has to make the stamp the ONLY reason. Without a
      // pre-blend base on a matching grid the answer falls through to the
      // replacement question and comes back false anyway — so removing the
      // stamp check entirely would still pass, and it did.
      overlay.preBlendBase = surface;
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawRect(
        const Rect.fromLTWH(0, 0, 8, 8),
        Paint()..color = const Color(0xFF00FF00),
      );
      final picture = recorder.endRecording();
      overlay.setStampOverlay(picture.toImageSync(8, 8), Offset.zero);
      picture.dispose();
      final painter = BitmapSurfacePainter(
        surface: surface,
        showTransparentBackground: false,
        overlayModel: overlay,
        tileImageCache: cache,
      );
      expect(
        overlay.preBlended && overlay.tileSize == surface.tileSize,
        isTrue,
        reason: 'fixture: without this the stamp check is redundant',
      );
      expect(painter.drawsDisjointCoverage, isFalse);
    });

    test('an overlay that cannot replace a coordinate composes against it',
        () async {
      // Its isolation layer exists precisely because it blends with the
      // committed pixels — so the layer paint cannot ride the draws.
      final surface = inkedSurface();
      await decodeAll(surface);
      // A MISMATCHED grid is the case the replacement route refuses.
      final overlay = ActiveStrokeOverlayModel(tileSize: tileSize ~/ 2);
      addTearDown(overlay.dispose);
      overlay.preBlendBase = surface;
      final rasterizer = BrushLiveStrokeRasterizer(canvasSize: canvasSize);
      rasterizer.blendFrom([
        BrushDab(
          center: CanvasPoint(x: 4, y: 4),
          color: 0xFF000000,
          size: 3,
          opacity: 1,
          flow: 1,
          hardness: 1,
          tipShape: BrushTipShape.round,
          pressure: 1,
          sequence: 0,
        ),
      ], from: 0);
      overlay.updateRegion(
        source: rasterizer,
        region: DirtyRegion.fromXYWH(x: 0, y: 0, width: 8, height: 8),
      );
      await overlay.waitForPendingDecodes();
      final painter = BitmapSurfacePainter(
        surface: surface,
        showTransparentBackground: false,
        overlayModel: overlay,
        tileImageCache: cache,
      );
      // ⛔The fixture has to actually BE the refused case, or this passes
      // for the wrong reason.
      expect(overlay.hasStrokeContent, isTrue, reason: 'fixture');
      expect(painter.drawsDisjointCoverage, isFalse);
    });
    test('no overlay at all is disjoint', () {
      expect(painterOver(inkedSurface()).drawsDisjointCoverage, isTrue);
    });
  });

  group('when the live layer opens a buffer, and when it does not', () {
    // 🚨THE DECISION, READ AT THE ROUTE. The two routes are the same pixels
    // — that is the point — so a pixel comparison cannot say WHICH ran.
    const canvasSize = CanvasSize(width: 64, height: 64);

    // 🚨ONE TILE OBJECT FOR EVERY PAINT (F-67). `BitmapTileImageCache` keys
    // on the tile OBJECT and the painter reads the SINGLETON: a fixture that
    // minted a fresh tile per paint left the singleton empty, and every
    // comparison silently drew the tile from the per-pixel fallback on one
    // reading and from its picture on the next — which the probe now says
    // out loud.
    var sharedTile = BitmapTile.blank(size: 16);
    sharedTile = writeRgbaColorToBitmapTile(
      tile: sharedTile,
      x: 4,
      y: 4,
      color: RgbaColor(r: 0, g: 0, b: 255, a: 255),
    );

    BitmapSurfacePainter inkedPainter({
      ValueListenable<CutStampPreview?>? stampPreview,
    }) {
      final tile = sharedTile;
      return BitmapSurfacePainter(
        surface: BitmapSurface(
          canvasSize: canvasSize,
          tileSize: 16,
          tiles: {TileCoord(x: 0, y: 0): tile},
        ),
        showTransparentBackground: false,
        stampPreview: stampPreview,
      );
    }

    Future<void> paintActive(
      WidgetTester tester, {
      required List<ResolvedLayerEffect> effects,
      double opacity = 0.5,
      double zoom = 1,
      bool disableBuffer = false,
      SelectionFloatOverlay? floatOverlay,
      ValueListenable<CutStampPreview?>? stampPreview,
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
                    CompositeLeaf<CanvasStackRow>(CanvasActiveLayerRow(opacity: opacity, effects: effects)),
                  ],
                  imageCache: LayerFrameImageCache(
                    frameStore: BrushFrameStore(),
                  ),
                  canvasSize: canvasSize,
                  viewport: CanvasViewport(zoom: zoom, panX: 0, panY: 0),
                  activeSurfacePainter: inkedPainter(
                    stampPreview: stampPreview,
                  ),
                  paintPaper: true,
                  paperBackground: ProjectBackground.defaultBackground,
                  floatOverlay: floatOverlay,
                  debugDisableSingleBuffer: disableBuffer,
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


    testWidgets('the opacity actually reaches the pixels', (tester) async {
      // 🚨THE GAP A DECISION SEAM LEAVES. Reading "it rode the draws" says
      // nothing about whether anything was handed to them — a route that
      // reported "rode" and passed no paint would drop the layer's opacity
      // entirely, and every equivalence above still passes because they
      // call the painter directly.
      Future<Uint8List> pixelsAt(double opacity) async {
        await paintActive(tester, effects: const [], opacity: opacity);
        final painted = tester
            .widgetList<CustomPaint>(
              find.descendant(
                of: find.byType(CanvasLayerStackView),
                matching: find.byType(CustomPaint),
              ),
            )
            .where((paint) => paint.painter != null)
            .toList();
        const size = Size(200, 150);
        final recorder = ui.PictureRecorder();
        painted.first.painter!.paint(
          Canvas(recorder, Offset.zero & size),
          size,
        );
        final picture = recorder.endRecording();
        final image = picture.toImageSync(200, 150);
        picture.dispose();
        // ⚠️`runAsync`: a widget test's fake clock never completes a real
        // async read, and the first draft of this hung for ten minutes.
        final bytes = await tester.runAsync(
          () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
        );
        image.dispose();
        return bytes!.buffer.asUint8List();
      }

      final half = await pixelsAt(0.5);
      final full = await pixelsAt(1);
      var differing = 0;
      for (var i = 0; i < half.length; i += 4) {
        if (half[i] != full[i] ||
            half[i + 1] != full[i + 1] ||
            half[i + 2] != full[i + 2] ||
            half[i + 3] != full[i + 3]) {
          differing += 1;
        }
      }
      expect(
        differing,
        greaterThan(0),
        reason: 'a layer at half opacity must not look like one at full — '
            'if it does, the paint reached nothing',
      );
    });
    testWidgets('🚨F-67: the two routes agree on the pixels neither of them '
        'was asked to change', (tester) async {
      // 유저 F-67: 「툴을 바꾸거나 선을 그리기 시작하거나 화면을 팬으로
      // 이동할때, 그 때만. 그릴때는 펜 다운때 시작해서, 펜 업때 원래대로
      // 돌아오는. 즉 일부 정해진 픽셀이 반픽셀? 움직였다가 돌아오는 현상」.
      //
      // 🎯WHY THIS IS THE EXPERIMENT. `needsBuffer` decides whether the
      // active layer is drawn through a `saveLayer` — an offscreen aligned
      // to DEVICE pixels — or straight under the fractional CTM. It reads
      // `drawsDisjointCoverage`, and that flips on exactly the moments 유저
      // named: pen down (the overlay gains content), pen up (it loses it),
      // a stamp ghost appearing. If the two routes rasterise the SAME
      // artwork differently, the flip is the shift.
      //
      // 🚨AND THE ONLY MEASUREMENT ON RECORD COVERS TILES. The painter's own
      // comment says the routes agree to the byte 「with the tile paint this
      // class actually uses (`isAntiAlias = false`, `FilterQuality.none`)
      // … 0 of 19200 pixels differ」 — and then names its limit:
      // 「Antialiased draws do NOT agree」. A REDUCED view is blitted
      // bilinearly from the level buffer, which is not that paint.
      //
      // ⚠️ZOOM 0.63, one of the values that measurement used, and reduced on
      // purpose: it is where the display law asks for filtering.
      Future<Uint8List> capture({
        required bool ghost,
        required bool disableBuffer,
      }) async {
        final preview = ghost
            ? ValueNotifier<CutStampPreview?>(
                CutStampPreview(
                  piece: CutPiece(
                    image: BrushStampImage(
                      id: 'ghost',
                      width: 4,
                      height: 4,
                      rgba: Uint8List(4 * 4 * 4)..fillRange(0, 4 * 4 * 4, 200),
                    ),
                    originLeft: 0,
                    originTop: 0,
                  ),
                  image: await tester.runAsync(_decodedSquare),
                  canvasRect: const Rect.fromLTWH(0, 0, 4, 4),
                  opacity: 1,
                  blendMode: BrushBlendMode.color,
                ),
              )
            : null;
        if (preview != null) {
          addTearDown(preview.dispose);
        }
        await paintActive(
          tester,
          effects: const [],
          zoom: 0.63,
          disableBuffer: disableBuffer,
          stampPreview: preview,
        );
        expect(
          debugLiveLayerRodeTheDraws,
          ghost ? isFalse : isTrue,
          reason: 'fixture premise: the ghost is what flips the route',
        );
        // 🚨AND WHICH DRAW IT WAS. The active layer reaches the screen two
        // ways (the stand-in, its tiles); a comparison must say which it
        // took. The first version of this test could not, and nothing in
        // the result could say so.
        expect(
          debugActiveSlotDraw,
          isNotNull,
          reason: 'the active slot painted nothing at all',
        );
        final painted = tester
            .widgetList<CustomPaint>(
              find.descendant(
                of: find.byType(CanvasLayerStackView),
                matching: find.byType(CustomPaint),
              ),
            )
            .where((paint) => paint.painter != null)
            .toList();
        const size = Size(200, 150);
        final recorder = ui.PictureRecorder();
        painted.first.painter!.paint(
          Canvas(recorder, Offset.zero & size),
          size,
        );
        final picture = recorder.endRecording();
        final image = picture.toImageSync(200, 150);
        picture.dispose();
        final bytes = await tester.runAsync(
          () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
        );
        image.dispose();
        return bytes!.buffer.asUint8List();
      }

      for (final disableBuffer in [false, true]) {
      // ⛔THE DEVICE RATIO IS 1, WHICH IS NOT COSMETIC. The display scale is
      // `zoom · dpr`, and a widget test's view reports 3 — so at zoom 0.63
      // the product would be 1.89, a MAGNIFIED view sampling nearest, and a
      // comparison there says nothing about the reduced one this test is
      // about. At ratio 1 the scale is 0.63: a level-1 buffer, blitted
      // bilinearly by its residual (2026-09-16).
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      // ⛔AND THE TILE HAS TO BE DECODED IN THE SINGLETON, or the slot draws
      // it per pixel out of the fallback budget on one reading and from its
      // picture on the next. `runAsync` because the upload lands on the
      // engine, which a widget test's fake clock never completes.
      await tester.runAsync(() async {
        BitmapTileImageCache.instance.ensureDecoded(
          (coord: TileCoord(x: 0, y: 0), tile: sharedTile),
        );
        while (BitmapTileImageCache.instance.imageFor(sharedTile) == null) {
          await Future<void>.delayed(const Duration(milliseconds: 1));
        }
      });
      expect(
        BitmapTileImageCache.instance.imageFor(sharedTile),
        isNotNull,
        reason: 'fixture premise: the tile draws from its own picture',
      );
      debugActiveSlotDraw = null;
      final rode = await capture(ghost: false, disableBuffer: disableBuffer);
      final rodeDraw = debugActiveSlotDraw;
      final buffered = await capture(ghost: true, disableBuffer: disableBuffer);
      final bufferedDraw = debugActiveSlotDraw;

      // ⛔ONLY THE PIXELS NEITHER ROUTE WAS ASKED TO CHANGE. The ghost sits
      // at canvas (0,0,4,4); at 0.63 that is a handful of screen pixels in
      // the top-left, and of course they differ — one render has a ghost in
      // it. Everything from x = 40 on is the same artwork drawn twice, and
      // it is the only region that can say anything about SAMPLING.
      var differing = 0;
      var first = '';
      for (var y = 0; y < 150; y += 1) {
        for (var x = 40; x < 200; x += 1) {
          final i = (y * 200 + x) * 4;
          if (rode[i] != buffered[i] ||
              rode[i + 1] != buffered[i + 1] ||
              rode[i + 2] != buffered[i + 2] ||
              rode[i + 3] != buffered[i + 3]) {
            differing += 1;
            first = first.isEmpty
                ? '($x,$y) ${rode.sublist(i, i + 4)} vs '
                      '${buffered.sublist(i, i + 4)}'
                : first;
          }
        }
      }
      expect(
        differing,
        0,
        reason: 'the same artwork rasterised two ways at a reduced zoom '
            '(buffer disabled: $disableBuffer) — a pixel that differs here '
            'is a half-pixel that appears when the route flips at pen down '
            'and disappears when it flips back. First: $first',
      );

      // 📏WHICH DRAW THIS COMPARED — the question the first version could
      // not answer (F-67), and nothing in a green could say which it was.
      //
      // ⛔BOTH RENDERS MUST HAVE TAKEN THE SAME ARM. Otherwise this compares
      // two rasterizers rather than two routes, and agreeing would be luck.
      expect(
        rodeDraw,
        bufferedDraw,
        reason: 'the two renders took different draws in the active slot '
            '($rodeDraw vs $bufferedDraw) — that is a comparison of two '
            'rasterizers, not of the two routes',
      );
      // 📏WHICH DRAW EACH READING REACHES (corrected 2026-09-10, again
      // 2026-09-16 when the knee's flat projection went with the level
      // buffer). Buffer ON: the slot draws its TILES into the level-1
      // buffer, and the buffer's one blit is the bilinear sample F-67
      // suspected — the same blit for both renders, so the pixels above
      // agree to the byte. Buffer OFF: the walk draws the same tiles under
      // the CTM, the painter's own byte-parity route.
      //
      // 🪦The first probe run was recorded as "it says tiles", and F-67 was
      // left open on the flat blit because of it. It was reading this loop's
      // LAST reading — buffer off, whose answer is tiles by construction.
      // Naming the buffer state in the reason is what showed it.
      expect(
        rodeDraw,
        ActiveSlotDraw.tiles,
        reason: 'buffer ${disableBuffer ? 'off' : 'on'}: the slot has to take '
            'the draw this reading exists to compare — it took $rodeDraw',
      );
      }
    });

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

    testWidgets('🚨F-33: a STAMP GHOST takes the buffer, which is how it '
        'gets the layer at all', (tester) async {
      // 유저: 「레이어 블렌드모드나 **합성같은게 다** 반영되는」 프리뷰.
      //
      // The ghost used to be a `Positioned` widget ON TOP of the canvas,
      // where the only thing it could honour was the stamp's own opacity.
      // It is a painter's draw now — and this is the line that makes that
      // mean something: a ghost overlaps the committed pixels, so the
      // painter reports NON-disjoint coverage, so the stack assembles the
      // layer into a buffer and puts the layer's opacity and blend on the
      // BUFFER. Everything inside it, ghost included, composites as that
      // layer.
      //
      // ⛔If this ever says true the ghost rides the per-draw path with no
      // layer paint of its own, and F-33 is silently back.
      final preview = ValueNotifier<CutStampPreview?>(
        CutStampPreview(
          piece: CutPiece(
            image: BrushStampImage(
              id: 'ghost',
              width: 4,
              height: 4,
              rgba: Uint8List(4 * 4 * 4)..fillRange(0, 4 * 4 * 4, 200),
            ),
            originLeft: 0,
            originTop: 0,
          ),
          // ⚠️:  goes through the engine
          // and never completes inside the test's fake-async zone.
          image: await tester.runAsync(_decodedSquare),
          canvasRect: const Rect.fromLTWH(8, 8, 4, 4),
          opacity: 1,
          blendMode: BrushBlendMode.color,
        ),
      );
      addTearDown(preview.dispose);

      await paintActive(tester, effects: const [], stampPreview: preview);
      expect(debugLiveLayerRodeTheDraws, isFalse);

      // The other side: with nothing held there is nothing overlapping, so
      // the cheap path comes back.
      preview.value = null;
      await paintActive(tester, effects: const [], stampPreview: preview);
      expect(
        debugLiveLayerRodeTheDraws,
        isTrue,
        reason: 'a hover that ended must not leave the layer buffered',
      );
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
/// A tiny decoded image for the stamp-ghost case.
///
/// The ghost's own pixels are not what that case measures — the ROUTE is —
/// so this is the smallest thing that makes `image != null` true.
Future<ui.Image> _decodedSquare() {
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    Uint8List(4 * 4 * 4)..fillRange(0, 4 * 4 * 4, 255),
    4,
    4,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}
