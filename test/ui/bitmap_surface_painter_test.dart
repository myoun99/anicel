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
import 'package:anicel/src/core/sync_image_upload.dart';
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
      // Wait in real TIME, not in event-loop turns. A hundred zero-length
      // delays can elapse in well under a millisecond while the engine's
      // decode is still running, which is how this went red on CI's
      // busiest job (the one that builds the native DLL alongside the
      // suite) and nowhere else. Ten milliseconds a turn is what the
      // sibling cache test already waits.
      for (var attempt = 0; attempt < 100; attempt += 1) {
        if (cache.allDecoded(surface.tiles.values)) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
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

  /// N4 ③: what the painter DRAWS for a tile whose own decode has not
  /// landed. The order is truth, then a picture of THIS tile, then a
  /// picture of a DIFFERENT one, then per-pixel, then nothing — and the
  /// two tests here are the two places that order is load-bearing.
  ///
  /// The stand-in is deliberately a colour the tile's own bytes do not
  /// contain, so the oracle can tell "drew the stand-in" apart from "drew
  /// its pixels" and from "drew the previous generation". A stand-in the
  /// same colour as the tile would make either outcome green.
  group('a tile stands in for itself (N4 ③)', () {
    ui.Image solid(int size, Color color) {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawRect(
        Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
        Paint()..color = color,
      );
      final picture = recorder.endRecording();
      final image = picture.toImageSync(size, size);
      picture.dispose();
      return image;
    }

    test('a stand-in outranks the previous generation at the same '
        'coordinate', () async {
      const scope = 'cel';
      final cache = BitmapTileImageCache();

      // The generation the user is looking at: BLUE, decoded, in the
      // coordinate bucket.
      final previous = _tile(
        coord: TileCoord(x: 0, y: 0),
        size: 2,
        colors: {const _Point(0, 0): RgbaColor(r: 0, g: 0, b: 255, a: 255)},
      );
      cache.adoptDecoded(
        previous,
        solid(2, const Color(0xFF0000FF)),
        staleScope: scope,
      );

      // The generation a commit just produced: a NEW tile object at the
      // same coordinate, so its image lookup misses by construction.
      final committed = _tile(
        coord: TileCoord(x: 0, y: 0),
        size: 2,
        colors: {const _Point(0, 0): RgbaColor(r: 255, g: 0, b: 0, a: 255)},
      );
      cache.putProvisional(committed, solid(2, const Color(0xFF00FF00)));

      final pixels = await _paintPixels(
        BitmapSurfacePainter(
          surface: BitmapSurface(
            canvasSize: CanvasSize(width: 2, height: 2),
            tileSize: 2,
            tiles: {committed.coord: committed},
          ),
          showTransparentBackground: false,
          staleScope: scope,
          tileImageCache: cache,
        ),
        width: 2,
        height: 2,
      );

      expect(
        _rgbaAt(pixels, width: 2, x: 0, y: 0),
        [0, 255, 0, 255],
        reason:
            'blue here is the stale-tile bug itself: the coordinate '
            'fallback answering for a tile with a DIFFERENT tile picture',
      );
    });

    test('the per-pixel budget cannot starve a stand-in', () async {
      // ⚠️ TEN tiles, not four. The painter draws at most four undecoded
      // tiles per paint, so a fixture inside that budget is drawn either
      // way and proves nothing — the same trap that made three earlier
      // fixtures in this program pass before their fix.
      const columns = 10;
      const tileSize = 2;
      final cache = BitmapTileImageCache();
      final tiles = <TileCoord, BitmapTile>{};
      for (var column = 0; column < columns; column += 1) {
        final coord = TileCoord(x: column, y: 0);
        final tile = _tile(
          coord: coord,
          size: tileSize,
          // Red ONLY at the tile's first pixel: the second pixel has no
          // ink at all, so it is drawn only by something that covers the
          // whole tile.
          colors: {const _Point(0, 0): RgbaColor(r: 255, g: 0, b: 0, a: 255)},
        );
        tiles[coord] = tile;
        cache.putProvisional(tile, solid(tileSize, const Color(0xFF00FF00)));
      }

      final pixels = await _paintPixels(
        BitmapSurfacePainter(
          surface: BitmapSurface(
            canvasSize: CanvasSize(width: columns * tileSize, height: tileSize),
            tileSize: tileSize,
            tiles: tiles,
          ),
          showTransparentBackground: false,
          tileImageCache: cache,
        ),
        width: columns * tileSize,
        height: tileSize,
      );

      // Read BOTH pixels of every tile: the inked one says which route
      // drew (stand-in vs the per-pixel budget), the blank one says
      // whether the coordinate was covered at all. One column of the
      // table alone cannot tell "the budget drew four" from "nothing
      // drew", and those are different failures.
      String glyph(int x) {
        final rgba = _rgbaAt(pixels, width: columns * tileSize, x: x, y: 0);
        if (rgba[3] == 0) {
          return '.';
        }
        if (rgba[0] == 0 && rgba[1] == 255) {
          return 'g';
        }
        if (rgba[0] == 255 && rgba[1] == 0) {
          return 'r';
        }
        return '?';
      }

      final inked = [for (var c = 0; c < columns; c += 1) glyph(c * tileSize)];
      final blank = [
        for (var c = 0; c < columns; c += 1) glyph(c * tileSize + 1),
      ];
      expect(
        '${inked.join()} / ${blank.join()}',
        '${'g' * columns} / ${'g' * columns}',
        reason:
            'every coordinate must show its own stand-in. "r" is the '
            'per-pixel budget drawing the tile bytes instead; "." is the '
            'hole it leaves once the budget is gone',
      );
    });
  });

  /// N4 ⑤: an engine that can turn BYTES into a picture within the frame.
  ///
  /// 🚨 Every machine that runs this suite says it cannot — Windows is
  /// Skia in every build, CI included — so these drive the cache's
  /// injection point. The uploader here is faithful: it draws the actual
  /// premultiplied bytes it is handed, so the raster below is the tile's
  /// own pixels and not a token standing for them.
  group('bytes become pictures within the frame (N4 ⑤)', () {
    tearDown(() => debugSyncImageUploadOverride = null);

    ui.Image fromPremultiplied(Uint8List pixels, int width, int height) {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final paint = Paint();
      for (var y = 0; y < height; y += 1) {
        for (var x = 0; x < width; x += 1) {
          final offset = (y * width + x) * 4;
          final alpha = pixels[offset + 3];
          if (alpha == 0) {
            continue;
          }
          int straight(int value) =>
              alpha == 255 ? value : ((value * 255) ~/ alpha).clamp(0, 255);
          paint.color = Color.fromARGB(
            alpha,
            straight(pixels[offset]),
            straight(pixels[offset + 1]),
            straight(pixels[offset + 2]),
          );
          canvas.drawRect(
            Rect.fromLTWH(x.toDouble(), y.toDouble(), 1, 1),
            paint,
          );
        }
      }
      final picture = recorder.endRecording();
      final image = picture.toImageSync(width, height);
      picture.dispose();
      return image;
    }

    test('an undecoded tile draws its OWN bytes instead of the previous '
        'generation', () async {
      // The stale-tile bug in one frame: a coordinate that HAS a previous
      // picture and a new tile that has none. Everything before this
      // could only choose which wrong-or-absent answer to give. With a
      // synchronous upload the right answer is simply available.
      const scope = 'cel';
      final cache = BitmapTileImageCache();
      debugSyncImageUploadOverride = fromPremultiplied;

      final previous = _tile(
        coord: TileCoord(x: 0, y: 0),
        size: 2,
        colors: {const _Point(0, 0): RgbaColor(r: 0, g: 0, b: 255, a: 255)},
      );
      cache.adoptDecoded(previous, await _solid2(const Color(0xFF0000FF)),
          staleScope: scope);

      final committed = _tile(
        coord: TileCoord(x: 0, y: 0),
        size: 2,
        colors: {const _Point(0, 0): RgbaColor(r: 255, g: 0, b: 0, a: 255)},
      );

      final pixels = await _paintPixels(
        BitmapSurfacePainter(
          surface: BitmapSurface(
            canvasSize: CanvasSize(width: 2, height: 2),
            tileSize: 2,
            tiles: {committed.coord: committed},
          ),
          showTransparentBackground: false,
          staleScope: scope,
          tileImageCache: cache,
        ),
        width: 2,
        height: 2,
      );

      expect(
        _rgbaAt(pixels, width: 2, x: 0, y: 0),
        [255, 0, 0, 255],
        reason:
            'blue is the borrow — the previous generation answering for a '
            'tile whose own bytes were available the whole time',
      );
      expect(
        cache.imageFor(committed),
        isNotNull,
        reason: 'and it is adopted, so the coordinate pays this once',
      );
    });

    test('the four-tile budget stops being the ceiling', () async {
      // Ten undecoded tiles and nothing to borrow. The per-pixel fallback
      // draws four of them and the rest are silent; an upload draws all
      // ten, which is what makes a whole-canvas landing appear at once
      // instead of converging tile by tile.
      const columns = 10;
      const tileSize = 2;
      final cache = BitmapTileImageCache();
      debugSyncImageUploadOverride = fromPremultiplied;
      final tiles = <TileCoord, BitmapTile>{};
      for (var column = 0; column < columns; column += 1) {
        final coord = TileCoord(x: column, y: 0);
        tiles[coord] = _tile(
          coord: coord,
          size: tileSize,
          colors: {const _Point(0, 0): RgbaColor(r: 255, g: 0, b: 0, a: 255)},
        );
      }

      final pixels = await _paintPixels(
        BitmapSurfacePainter(
          surface: BitmapSurface(
            canvasSize: CanvasSize(width: columns * tileSize, height: tileSize),
            tileSize: tileSize,
            tiles: tiles,
          ),
          showTransparentBackground: false,
          tileImageCache: cache,
        ),
        width: columns * tileSize,
        height: tileSize,
      );

      var drawn = 0;
      for (var column = 0; column < columns; column += 1) {
        if (_rgbaAt(
              pixels,
              width: columns * tileSize,
              x: column * tileSize,
              y: 0,
            )[3] !=
            0) {
          drawn += 1;
        }
      }
      expect(
        drawn,
        columns,
        reason: '$drawn of $columns drew — four means the budget is still '
            'the answer and the upload never ran',
      );
    });

    test('uploads are rationed per paint, and drain over the next ones', () {
      // An upload costs what a decode START costs — the 256KB tile copy
      // and premultiply — plus the upload. Unrationed, a zoomed-out paint
      // of a large cel would do the whole visible grid at once, which is
      // precisely the burst decodeStartBudget exists to spread out. This
      // is the one N4 ⑤ regression that could never show on the renderer
      // it was written on: Skia declines every call before the budget is
      // even consulted.
      const budget = BitmapSurfacePainter.decodeStartBudget;
      const columns = budget + 8;
      const tileSize = 2;
      final cache = BitmapTileImageCache();
      debugSyncImageUploadOverride = fromPremultiplied;
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
      final painter = BitmapSurfacePainter(
        surface: surface,
        showTransparentBackground: false,
        // Its own scope: a borrow would answer before the upload is ever
        // offered, and then this measures nothing.
        staleScope: Object(),
        tileImageCache: cache,
      );

      int uploaded() =>
          surface.tiles.values.where((t) => cache.imageFor(t) != null).length;

      void paintOnce() {
        final recorder = ui.PictureRecorder();
        final size = Size(
          (columns * tileSize).toDouble(),
          tileSize.toDouble(),
        );
        painter.paint(Canvas(recorder, Offset.zero & size), size);
        recorder.endRecording().dispose();
      }

      paintOnce();
      final afterFirst = uploaded();
      expect(
        afterFirst,
        budget,
        reason: 'one paint uploaded $afterFirst of $columns — the whole '
            'visible grid in one frame is the burst this rations',
      );

      paintOnce();
      expect(
        uploaded(),
        greaterThan(afterFirst),
        reason: 'the remainder must drain on later paints, not stall',
      );
      // ⚠️ NOT "all of them". The first paint's collect pass starts
      // asynchronous decodes for tiles it could not upload, and
      // `adoptSyncUpload` stands aside for an in-flight decode — that one
      // would land later and overwrite the entry, leaking the image it
      // displaced. So the tail arrives by decode rather than by upload,
      // and what has to be true is that NOTHING is left waiting for a
      // start that will never come.
      expect(
        surface.tiles.values.where(cache.needsDecodeStart).toList(),
        isEmpty,
        reason: 'a tile with neither a picture nor a decode in flight is a '
            'coordinate that has stopped converging',
      );
    });
  });
}

Future<ui.Image> _solid2(Color color) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    const Rect.fromLTWH(0, 0, 2, 2),
    Paint()..color = color,
  );
  final picture = recorder.endRecording();
  final image = picture.toImageSync(2, 2);
  picture.dispose();
  return image;
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
