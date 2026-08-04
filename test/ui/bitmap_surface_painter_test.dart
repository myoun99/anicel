import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/dirty_region.dart';
import 'package:anicel/src/models/rgba_color.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/bitmap_tile_rgba.dart';
import 'package:anicel/src/services/brush_live_stroke_rasterizer.dart'
    show ActiveStrokePixelSource;
import 'package:anicel/src/ui/canvas/active_stroke_overlay.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/debug/measurement_mode.dart';
import 'package:anicel/src/ui/canvas/bitmap_tile_image_cache.dart';
import 'package:anicel/src/ui/canvas/viewport_canvas_transform.dart';

void main() {
  group('BitmapSurfacePainter', () {
    test('repaints when surface or transparent background setting changes', () {
      final surface = BitmapSurface(
        canvasSize: CanvasSize(width: 2, height: 2),
      );
      final same = BitmapSurfacePainter(surface: surface);

      expect(
        BitmapSurfacePainter(surface: surface).shouldRepaint(same),
        isFalse,
      );
      expect(
        BitmapSurfacePainter(
          surface: surface,
          showTransparentBackground: false,
        ).shouldRepaint(same),
        isTrue,
      );
      expect(
        BitmapSurfacePainter(
          surface: surface.copyWith(tileSize: 1),
        ).shouldRepaint(same),
        isTrue,
      );
    });

    test('does not depend on active stroke path or overlay state', () {
      final surface = BitmapSurface(
        canvasSize: CanvasSize(width: 2, height: 2),
      );
      final painter = BitmapSurfacePainter(surface: surface);

      expect(
        painter.shouldRepaint(BitmapSurfacePainter(surface: surface)),
        isFalse,
      );
    });

    test('draws RGBA tile pixels at global tile coordinates', () async {
      final firstTile = _tile(
        coord: TileCoord(x: 0, y: 0),
        size: 2,
        colors: {
          const _Point(1, 0): RgbaColor(r: 255, g: 0, b: 0, a: 255),
          const _Point(0, 1): RgbaColor(r: 0, g: 255, b: 0, a: 255),
        },
      );
      final secondTile = _tile(
        coord: TileCoord(x: 1, y: 0),
        size: 2,
        colors: {const _Point(0, 1): RgbaColor(r: 0, g: 0, b: 255, a: 255)},
      );
      final surface = BitmapSurface(
        canvasSize: CanvasSize(width: 4, height: 2),
        tileSize: 2,
        tiles: {firstTile.coord: firstTile, secondTile.coord: secondTile},
      );

      final pixels = await _paintPixels(
        BitmapSurfacePainter(
          surface: surface,
          showTransparentBackground: false,
        ),
        width: 4,
        height: 2,
      );

      expect(_rgbaAt(pixels, width: 4, x: 1, y: 0), [255, 0, 0, 255]);
      expect(_rgbaAt(pixels, width: 4, x: 0, y: 1), [0, 255, 0, 255]);
      expect(_rgbaAt(pixels, width: 4, x: 2, y: 1), [0, 0, 255, 255]);
      expect(_rgbaAt(pixels, width: 4, x: 0, y: 0), [0, 0, 0, 0]);
    });

    test('the per-pixel budget is spent on tiles that DREW, so empty ones '
        'earlier in raster order cannot eat it', () async {
      // Measured on a Ctrl+T confirm: the walk is raster order, the
      // landing sat below a blank pasteboard row, and all four budget
      // slots went to tiles with no ink in them — the float contributed
      // zero pixels while five inked tiles drew nothing.
      //
      // Five empty tiles first, then five inked ones, none decoded. With
      // the budget spent on the attempt, only the empties are visited and
      // nothing appears. Spent on the result, the ink does.
      const tileSize = 2;
      const columns = 10;
      final tiles = <TileCoord, BitmapTile>{};
      for (var column = 0; column < columns; column += 1) {
        final coord = TileCoord(x: column, y: 0);
        tiles[coord] = _tile(
          coord: coord,
          size: tileSize,
          colors: column < 5
              ? const {}
              : {const _Point(0, 0): RgbaColor(r: 255, g: 0, b: 0, a: 255)},
        );
      }
      final surface = BitmapSurface(
        canvasSize: CanvasSize(width: columns * tileSize, height: tileSize),
        tileSize: tileSize,
        tiles: tiles,
      );

      final pixels = await _paintPixels(
        BitmapSurfacePainter(
          surface: surface,
          showTransparentBackground: false,
          // A scope of its own: a borrow would answer before the
          // per-pixel path is ever reached, and then this proves nothing.
          staleScope: Object(),
        ),
        width: columns * tileSize,
        height: tileSize,
      );

      var inked = 0;
      for (var column = 5; column < columns; column += 1) {
        if (_rgbaAt(pixels, width: columns * tileSize, x: column * tileSize, y: 0)[3] !=
            0) {
          inked += 1;
        }
      }
      expect(
        inked,
        4,
        reason:
            'the four budget slots went to empty tiles instead of the '
            'inked ones behind them ($inked of 5 inked tiles drawn)',
      );
    });

    test('Show Unpainted Tiles marks the coordinates the painter could not '
        'draw, and only those', () async {
      // The switch exists because this event is silent: the painter's
      // answer to "I have no picture here" is to draw nothing, so every
      // artifact in this family had to be found by hand from a real
      // session. Magenta means "no picture", never "no artwork" — an
      // empty coordinate is never drawn and must never flash.
      addTearDown(MeasurementMode.reset);
      const tileSize = 2;
      const columns = 8;
      final tiles = <TileCoord, BitmapTile>{};
      for (var column = 0; column < columns; column += 1) {
        final coord = TileCoord(x: column, y: 0);
        tiles[coord] = _tile(
          coord: coord,
          size: tileSize,
          colors: {const _Point(0, 0): RgbaColor(r: 255, g: 0, b: 0, a: 255)},
        );
      }
      final surface = BitmapSurface(
        canvasSize: CanvasSize(width: columns * tileSize, height: tileSize),
        tileSize: tileSize,
        tiles: tiles,
      );
      BitmapSurfacePainter painter() => BitmapSurfacePainter(
        surface: surface,
        showTransparentBackground: false,
        staleScope: Object(),
      );

      int magentaCount(Uint8List pixels) {
        var magenta = 0;
        for (var x = 0; x < columns * tileSize; x += 1) {
          final rgba = _rgbaAt(pixels, width: columns * tileSize, x: x, y: 1);
          if (rgba[3] != 0 && rgba[0] > 100 && rgba[2] > 100 && rgba[1] < 80) {
            magenta += 1;
          }
        }
        return magenta;
      }

      final off = await _paintPixels(
        painter(),
        width: columns * tileSize,
        height: tileSize,
      );
      expect(magentaCount(off), 0, reason: 'inert until asked for');

      MeasurementMode.showUnpaintedTiles.value = true;
      final on = await _paintPixels(
        painter(),
        width: columns * tileSize,
        height: tileSize,
      );
      // Eight inked tiles, a budget of four: the four the budget could not
      // reach are marked, and the four it drew are not.
      expect(
        magentaCount(on),
        (columns - 4) * tileSize,
        reason:
            'the marker should cover exactly the tiles the budget could not '
            'reach — ${magentaCount(on)} px of a possible '
            '${(columns - 4) * tileSize}',
      );
    });

    // Committed strokes are now materialized into the surface on commit and
    // painted from tile pixels; the painter no longer draws source-dab
    // stamps, so the old committedSourceDabStrokes square test was removed.

    // The live overlay now paints exact rasterized region sprites; its
    // rendering guarantees are covered by active_stroke_overlay_parity_test.

    test('draws deterministic neutral background when enabled', () async {
      final surface = BitmapSurface(
        canvasSize: CanvasSize(width: 1, height: 1),
      );

      final pixels = await _paintPixels(
        BitmapSurfacePainter(surface: surface),
        width: 1,
        height: 1,
      );

      // R28 #9: the paper is PURE white now, from the one constant.
      expect(_rgbaAt(pixels, width: 1, x: 0, y: 0), [255, 255, 255, 255]);
    });
  });

  group('settle hold', () {
    final coord = TileCoord(x: 0, y: 0);
    final green = RgbaColor(r: 0, g: 255, b: 0, a: 255);
    final red = RgbaColor(r: 255, g: 0, b: 0, a: 255);
    final blue = RgbaColor(r: 0, g: 0, b: 255, a: 255);

    // The committed tile already contains the stroke (red); the pinned
    // pre-stroke tile does not (green). Painting the committed tile during
    // settling is what double-blended it with the overlay.
    BitmapSurface surface() {
      final newTile = _tile(
        coord: coord,
        size: 2,
        colors: {const _Point(0, 0): red},
      );
      final sideTile = _tile(
        coord: TileCoord(x: 1, y: 0),
        size: 2,
        colors: {const _Point(0, 1): blue},
      );
      return BitmapSurface(
        canvasSize: CanvasSize(width: 4, height: 2),
        tileSize: 2,
        tiles: {newTile.coord: newTile, sideTile.coord: sideTile},
      );
    }

    Future<Uint8List> paint(ActiveStrokeOverlayModel overlay) {
      return _paintPixels(
        BitmapSurfacePainter(
          surface: surface(),
          overlayModel: overlay,
          showTransparentBackground: false,
          tileImageCache: BitmapTileImageCache(),
        ),
        width: 4,
        height: 2,
      );
    }

    test('a pinned coordinate draws its PRE-stroke tile, not the committed '
        'one; unpinned coordinates are untouched', () async {
      final overlay = ActiveStrokeOverlayModel();
      addTearDown(overlay.dispose);
      overlay.holdPreStrokeTiles({
        coord: _tile(
          coord: coord,
          size: 2,
          colors: {const _Point(0, 0): green},
        ),
      });

      final pixels = await paint(overlay);

      expect(_rgbaAt(pixels, width: 4, x: 0, y: 0), [0, 255, 0, 255]);
      expect(_rgbaAt(pixels, width: 4, x: 2, y: 1), [0, 0, 255, 255]);
    });

    test('a coordinate that was empty pre-stroke draws nothing while '
        'pinned', () async {
      final overlay = ActiveStrokeOverlayModel();
      addTearDown(overlay.dispose);
      overlay.holdPreStrokeTiles({coord: null});

      final pixels = await paint(overlay);

      expect(_rgbaAt(pixels, width: 4, x: 0, y: 0), [0, 0, 0, 0]);
    });

    test('reset releases the pin and the committed tile shows', () async {
      final overlay = ActiveStrokeOverlayModel();
      addTearDown(overlay.dispose);
      overlay.holdPreStrokeTiles({coord: null});
      overlay.reset();

      final pixels = await paint(overlay);

      expect(_rgbaAt(pixels, width: 4, x: 0, y: 0), [255, 0, 0, 255]);
    });
  });

  group('decode-start chunking (R18 B-1)', () {
    // 10×8 tile grid (80 tiles) — well over the per-paint start budget.
    BitmapSurface grid() {
      final tiles = <TileCoord, BitmapTile>{};
      for (var y = 0; y < 8; y += 1) {
        for (var x = 0; x < 10; x += 1) {
          final coord = TileCoord(x: x, y: y);
          tiles[coord] = BitmapTile.blank(coord: coord, size: 2);
        }
      }
      return BitmapSurface(
        canvasSize: CanvasSize(width: 20, height: 16),
        tileSize: 2,
        tiles: tiles,
      );
    }

    int pendingCount(BitmapTileImageCache cache, BitmapSurface surface) {
      var count = 0;
      for (final tile in surface.tiles.values) {
        if (cache.needsDecodeStart(tile)) {
          count += 1;
        }
      }
      return count;
    }

    // The cull rect is what the painter reads its visible range from (the
    // engine gives a layer's recorder the paint bounds), so the harness
    // has to supply one — an unbounded recorder would report a giant clip
    // and call every tile visible.
    void paintOnce(CustomPainter painter, Size size) {
      final recorder = ui.PictureRecorder();
      painter.paint(Canvas(recorder, Offset.zero & size), size);
      recorder.endRecording().dispose();
    }

    test('one paint starts at most decodeStartBudget decodes; repeated '
        'paints drain the rest', () {
      final cache = BitmapTileImageCache();
      final surface = grid();
      final painter = BitmapSurfacePainter(
        surface: surface,
        showTransparentBackground: false,
        tileImageCache: cache,
      );
      const budget = BitmapSurfacePainter.decodeStartBudget;

      expect(pendingCount(cache, surface), 80);
      paintOnce(painter, const Size(20, 16));
      expect(pendingCount(cache, surface), 80 - budget);
      paintOnce(painter, const Size(20, 16));
      expect(pendingCount(cache, surface), 80 - 2 * budget);
      paintOnce(painter, const Size(20, 16));
      expect(pendingCount(cache, surface), 0);
    });

    test('visible tiles start strictly before off-screen tiles', () {
      final cache = BitmapTileImageCache();
      final surface = grid();
      final painter = BitmapSurfacePainter(
        surface: surface,
        showTransparentBackground: false,
        tileImageCache: cache,
      );

      // Viewport-less paint sized to the left fifth of the canvas:
      // tiles at x∈{0,1} are visible (16), the other 64 are off-screen —
      // fewer visible tiles than the budget, so ALL of them must be in
      // the first chunk.
      paintOnce(painter, const Size(4, 16));

      for (final tile in surface.tiles.values) {
        if (tile.coord.x < 2) {
          expect(
            cache.needsDecodeStart(tile),
            isFalse,
            reason:
                'visible tile ${tile.coord} must start in the first '
                'chunk',
          );
        }
      }
      expect(
        pendingCount(cache, surface),
        80 - BitmapSurfacePainter.decodeStartBudget,
      );
    });

    test('a zoomed viewport prioritizes the tiles it actually shows', () {
      final cache = BitmapTileImageCache();
      final surface = grid();
      final painter = BitmapSurfacePainter(
        surface: surface,
        viewport: CanvasViewport(zoom: 4.0),
        showTransparentBackground: false,
        tileImageCache: cache,
      );

      // At zoom 4 a 4×8 widget shows canvas rect (0,0)-(1,2): only tile
      // (0,0) overlaps it — it must be in the first chunk.
      paintOnce(painter, const Size(4, 8));

      expect(
        cache.needsDecodeStart(surface.tiles[TileCoord(x: 0, y: 0)]!),
        isFalse,
        reason: 'the one visible tile must start in the first chunk',
      );
      expect(
        pendingCount(cache, surface),
        80 - BitmapSurfacePainter.decodeStartBudget,
      );
    });
  });

  // The draw walk visits only the tile coordinates the view covers, and
  // "the view" has to be read in CANVAS space. Two production routes hand
  // this painter a canvas somebody else transformed:
  //
  //   * the MERGED editing canvas — the layer stack painter applies the
  //     viewport itself and builds this painter with `viewport: null`, so
  //     the active layer is drawn inside the composite tree (a folder's
  //     group buffer has to be able to enclose it);
  //   * the selection FLOAT — a drag/warp Transform stacks on top of the
  //     viewport.
  //
  // Deriving the range from `viewport` + the widget size read a SCREEN
  // rect as canvas space in both, and culled tiles that were on screen:
  // the active layer blanked wherever pan/zoom moved the view off the
  // origin. These pin the fix at the pixel level.
  group('visible-tile range is read in canvas space', () {
    const tileSize = 4;

    /// Four opaque red tiles in a row: canvas x 0..16, one tile tall.
    BitmapSurface stripe() {
      final tiles = <TileCoord, BitmapTile>{};
      for (var x = 0; x < 4; x += 1) {
        final pixels = Uint8List(tileSize * tileSize * 4);
        for (var i = 0; i < pixels.length; i += 4) {
          pixels[i] = 255;
          pixels[i + 3] = 255;
        }
        final tile = BitmapTile(
          coord: TileCoord(x: x, y: 0),
          size: tileSize,
          pixels: pixels,
        );
        tiles[tile.coord] = tile;
      }
      return BitmapSurface(
        canvasSize: CanvasSize(width: 16, height: 4),
        tileSize: tileSize,
        tiles: tiles,
      );
    }

    /// Every tile decoded up front: this has to exercise the drawImage
    /// route, not the per-pixel fallback.
    Future<BitmapTileImageCache> decodedCache(BitmapSurface surface) async {
      final cache = BitmapTileImageCache();
      for (final tile in surface.tiles.values) {
        cache.ensureDecoded(tile);
      }
      for (var attempt = 0; attempt < 100; attempt += 1) {
        if (cache.allDecoded(surface.tiles.values)) {
          break;
        }
        await Future<void>.delayed(Duration.zero);
      }
      expect(
        cache.allDecoded(surface.tiles.values),
        isTrue,
        reason: 'setup: every tile must have an image',
      );
      return cache;
    }

    Future<Uint8List> rasterize(
      void Function(Canvas canvas) body, {
      required int width,
      required int height,
    }) async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(
        recorder,
        Offset.zero & Size(width.toDouble(), height.toDouble()),
      );
      body(canvas);
      final image = await recorder.endRecording().toImage(width, height);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      return bytes!.buffer.asUint8List();
    }

    /// The merged route verbatim: _LayerStackPainter.paint applies the
    /// viewport and clips, then the _PaintActiveSurface case calls
    /// paintContentInto on that canvas.
    Future<Uint8List> paintMerged(
      BitmapSurfacePainter painter,
      CanvasViewport viewport, {
      required int width,
      required int height,
    }) {
      return rasterize(
        (canvas) {
          canvas.save();
          canvas.clipRect(
            Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
          );
          applyViewportTransform(canvas, viewport);
          canvas.save();
          canvas.clipRect(painter.pasteboardRect);
          painter.paintContentInto(canvas);
          canvas.restore();
          canvas.restore();
        },
        width: width,
        height: height,
      );
    }

    test('merged route, PANNED: the half of the cel the view moved to is '
        'drawn', () async {
      final surface = stripe();
      // No viewport on the painter — exactly what the merged canvas builds
      // (BrushCanvasPanel._activeSurfacePainterFor).
      final painter = BitmapSurfacePainter(
        surface: surface,
        showTransparentBackground: false,
        tileImageCache: await decodedCache(surface),
      );

      // Canvas x 8..16 fills the 8-wide view.
      final pixels = await paintMerged(
        painter,
        CanvasViewport(panX: -8),
        width: 8,
        height: 4,
      );

      expect(
        _rgbaAt(pixels, width: 8, x: 0, y: 0),
        [255, 0, 0, 255],
        reason: 'canvas x=8 shows at screen x=0',
      );
      expect(
        _rgbaAt(pixels, width: 8, x: 7, y: 3),
        [255, 0, 0, 255],
        reason: 'canvas x=15 shows at screen x=7',
      );
    });

    test('merged route, ZOOMED OUT: the far side of the cel is drawn', () async {
      final surface = stripe();
      final painter = BitmapSurfacePainter(
        surface: surface,
        showTransparentBackground: false,
        tileImageCache: await decodedCache(surface),
      );

      // Fit: the whole 16-wide cel inside an 8-wide view.
      final pixels = await paintMerged(
        painter,
        CanvasViewport(zoom: 0.5),
        width: 8,
        height: 2,
      );

      expect(
        _rgbaAt(pixels, width: 8, x: 7, y: 0),
        [255, 0, 0, 255],
        reason: 'canvas x=15 shows at screen x=7 under a 0.5 zoom',
      );
    });

    test('selection float: a Transform above the painter moves what is '
        'visible', () async {
      final surface = stripe();
      final painter = BitmapSurfacePainter(
        surface: surface,
        viewport: CanvasViewport(panX: -8),
        showTransparentBackground: false,
        tileImageCache: await decodedCache(surface),
      );

      // CanvasSelectionLayer wraps the float painter in a Transform
      // carrying the live drag delta; here it drags the float 8px right,
      // which brings canvas x 0..8 (screen -8..0) back into view.
      final pixels = await rasterize(
        (canvas) {
          canvas.save();
          canvas.translate(8, 0);
          painter.paint(canvas, const Size(8, 4));
          canvas.restore();
        },
        width: 8,
        height: 4,
      );

      expect(
        _rgbaAt(pixels, width: 8, x: 4, y: 0),
        [255, 0, 0, 255],
        reason: 'the dragged float must draw where the drag put it',
      );
    });
  });

  group('live erase isolation (R14-⑤)', () {
    test('an erase overlay removes committed pixels but NEVER punches '
        'through content below the painter in the same buffer', () async {
      // Committed red pixel at (0,0).
      final tile = _tile(
        coord: TileCoord(x: 0, y: 0),
        size: 2,
        colors: {const _Point(0, 0): RgbaColor(r: 255, g: 0, b: 0, a: 255)},
      );
      final surface = BitmapSurface(
        canvasSize: CanvasSize(width: 2, height: 2),
        tileSize: 2,
        tiles: {tile.coord: tile},
      );

      // A live ERASE stroke covering (0,0) at full alpha.
      final overlay = ActiveStrokeOverlayModel();
      addTearDown(overlay.dispose);
      overlay.erase = true;
      overlay.updateRegion(
        source: _AlphaAtOriginSource(),
        region: DirtyRegion(
          left: 0,
          top: 0,
          rightExclusive: 1,
          bottomExclusive: 1,
        ),
      );
      await overlay.waitForPendingDecodes();

      // The production layout: paper/panel pixels live BELOW the painter
      // in the same compositing buffer (the painter paints no background of
      // its own). Without the erase saveLayer isolation, dstOut punched
      // through the white too and the live stroke showed as the (dark)
      // panel background — the user's black-line eraser.
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, 2, 2),
        Paint()..color = const Color(0xFFFFFFFF),
      );
      BitmapSurfacePainter(
        surface: surface,
        overlayModel: overlay,
        showTransparentBackground: false,
        tileImageCache: BitmapTileImageCache(),
      ).paint(canvas, const Size(2, 2));
      final image = await recorder.endRecording().toImage(2, 2);
      final byteData = await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      final pixels = byteData!.buffer.asUint8List();

      expect(
        _rgbaAt(pixels, width: 2, x: 0, y: 0),
        [255, 255, 255, 255],
        reason: 'the committed red erases; the white below survives',
      );
      expect(
        _rgbaAt(pixels, width: 2, x: 1, y: 1),
        [255, 255, 255, 255],
        reason: 'pixels the stroke never touched are unchanged',
      );
    });
  });
}

/// Full-alpha stroke coverage at canvas (0,0) only — a minimal live ERASE
/// stroke feed.
class _AlphaAtOriginSource implements ActiveStrokePixelSource {
  @override
  int get canvasWidth => 2;

  @override
  int get canvasHeight => 2;

  @override
  void copyRow(int x, int y, int count, Uint8List target, int targetOffset) {
    for (var i = 0; i < count; i += 1) {
      final offset = targetOffset + i * 4;
      final covered = (x + i) == 0 && y == 0;
      target[offset] = 0;
      target[offset + 1] = 0;
      target[offset + 2] = 0;
      target[offset + 3] = covered ? 255 : 0;
    }
  }
}

BitmapTile _tile({
  required TileCoord coord,
  required int size,
  required Map<_Point, RgbaColor> colors,
}) {
  var tile = BitmapTile.blank(coord: coord, size: size);
  for (final entry in colors.entries) {
    tile = writeRgbaColorToBitmapTile(
      tile: tile,
      x: entry.key.x,
      y: entry.key.y,
      color: entry.value,
    );
  }
  return tile;
}

Future<Uint8List> _paintPixels(
  CustomPainter painter, {
  required int width,
  required int height,
}) async {
  final recorder = ui.PictureRecorder();
  final size = Size(width.toDouble(), height.toDouble());
  // Cull rect like the engine's: the painter reads its visible range from
  // the canvas clip.
  final canvas = Canvas(recorder, Offset.zero & size);
  painter.paint(canvas, size);
  final image = await recorder.endRecording().toImage(width, height);
  final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  return byteData!.buffer.asUint8List();
}

List<int> _rgbaAt(
  Uint8List pixels, {
  required int width,
  required int x,
  required int y,
}) {
  final offset = (y * width + x) * 4;
  return pixels.sublist(offset, offset + 4);
}

class _Point {
  const _Point(this.x, this.y);

  final int x;
  final int y;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is _Point && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);
}
