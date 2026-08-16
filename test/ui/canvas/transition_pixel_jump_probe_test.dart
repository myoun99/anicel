import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/dirty_region.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/brush_live_stroke_rasterizer.dart'
    show ActiveStrokePixelSource;
import 'package:anicel/src/ui/canvas/active_stroke_overlay.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/bitmap_tile_image_cache.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/canvas/display_buffer_cache.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';

/// PROBE (not a contract): reproduce the one-frame ~1px edge jump seen on
/// Windows at zoom >= 100% with a fractional pan, at pen-down / pen-up /
/// layer-switch moments.
///
/// The fixture walks the display-buffer compose
/// (`canvas_layer_stack_view.dart _composeDisplayBuffer`) through every
/// state the transition moments put it in — kept-buffer serve, patched
/// compose, uncached full compose (settling), dirty-refused full compose
/// (stamp), and the direct walk — while the COMMITTED PICTURE never
/// changes. Every snapshot is byte-compared against the steady baseline;
/// any nonzero diff is a repro of a one-frame jump, and the phase where
/// it appears names the mechanism.
///
/// Output goes through debugPrint as `PROBE ...` lines; the hard
/// assertions are baseline stability (two steady paints byte-identical)
/// and the route flip (step 8): buffer route vs direct walk must be
/// byte-identical at ANY pan phase. Pre-snap, the fractional-pan run put
/// a one-pixel 290px strip between the routes while the integer-pan run
/// read zero — the render translation is snapped to whole device pixels
/// now ([renderSnappedViewport]), so both runs must read zero.
void main() {
  const canvasSize = CanvasSize(width: 512, height: 512);
  const tileSize = 256;
  const screen = Size(300, 200);
  final tileCache = BitmapTileImageCache.instance;

  // White everywhere; 1px black lines every 64 canvas px (at offset 32),
  // both horizontal and vertical — axis-aligned hard edges all over the
  // visible rect.
  Uint8List linePixels(int tx, int ty) {
    final pixels = Uint8List(tileSize * tileSize * 4);
    for (var y = 0; y < tileSize; y += 1) {
      final gy = ty * tileSize + y;
      for (var x = 0; x < tileSize; x += 1) {
        final gx = tx * tileSize + x;
        final i = (y * tileSize + x) * 4;
        final black = gx % 64 == 32 || gy % 64 == 32;
        pixels[i] = black ? 0 : 255;
        pixels[i + 1] = black ? 0 : 255;
        pixels[i + 2] = black ? 0 : 255;
        pixels[i + 3] = 255;
      }
    }
    return pixels;
  }

  Map<TileCoord, BitmapTile> freshTiles() => {
    for (var ty = 0; ty < 2; ty += 1)
      for (var tx = 0; tx < 2; tx += 1)
        TileCoord(x: tx, y: ty): BitmapTile(
          coord: TileCoord(x: tx, y: ty),
          size: tileSize,
          pixels: linePixels(tx, ty),
        ),
  };

  BitmapSurface surfaceOf(Map<TileCoord, BitmapTile> tiles) =>
      BitmapSurface(canvasSize: canvasSize, tileSize: tileSize, tiles: tiles);

  Future<void> decodeAll(WidgetTester tester, BitmapSurface surface) {
    return tester.runAsync(() async {
      for (final tile in surface.tiles.values) {
        tileCache.ensureDecoded(tile);
      }
      while (surface.tiles.values.any((t) => tileCache.imageFor(t) == null)) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
    });
  }

  Future<Uint8List> paintBytes(WidgetTester tester, CustomPainter painter) {
    return tester
        .runAsync(() async {
          final recorder = ui.PictureRecorder();
          painter.paint(Canvas(recorder), screen);
          final picture = recorder.endRecording();
          final image = picture.toImageSync(
            screen.width.round(),
            screen.height.round(),
          );
          picture.dispose();
          final data = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          image.dispose();
          return data!.buffer.asUint8List();
        })
        .then((bytes) => bytes!);
  }

  Future<void> runSequence(
    WidgetTester tester, {
    required String tag,
    required CanvasViewport viewport,
  }) async {
    final cache = DisplayBufferCache();
    final imageCache = LayerFrameImageCache(frameStore: BrushFrameStore());
    final overlay = ActiveStrokeOverlayModel(tileSize: tileSize);
    addTearDown(overlay.dispose);

    final zoom = viewport.zoom;
    final panX = viewport.panX;
    final panY = viewport.panY;

    // The compose rect the buffer path derives (whole canvas pixels): the
    // screen rect pulled back to canvas space, intersected with the
    // pasteboard, floored/ceiled — same math as _composeDisplayBuffer.
    final visible = Rect.fromLTRB(
      (0 - panX) / zoom,
      (0 - panY) / zoom,
      (screen.width - panX) / zoom,
      (screen.height - panY) / zoom,
    );
    final pasteboard = Rect.fromLTRB(
      canvasSize.pasteboardLeft.toDouble(),
      canvasSize.pasteboardTop.toDouble(),
      canvasSize.pasteboardRightExclusive.toDouble(),
      canvasSize.pasteboardBottomExclusive.toDouble(),
    );
    final bounds = pasteboard.intersect(visible);
    final composeRect = Rect.fromLTRB(
      bounds.left.floorToDouble(),
      bounds.top.floorToDouble(),
      bounds.right.ceilToDouble(),
      bounds.bottom.ceilToDouble(),
    );
    debugPrint(
      'PROBE[$tag] viewport zoom=$zoom pan=($panX,$panY) '
      'visible=$visible composeRect=$composeRect',
    );

    Future<CustomPainter> pumpWith(
      BitmapSurfacePainter surfacePainter, {
      bool disableBuffer = false,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: screen.width,
                height: screen.height,
                child: CanvasLayerStackView(
                  nodes: const [CanvasActiveLayerNode(opacity: 1)],
                  imageCache: imageCache,
                  canvasSize: canvasSize,
                  viewport: viewport,
                  activeSurfacePainter: surfacePainter,
                  paintPaper: true,
                  paperBackground: const ProjectBackground.color(0xFFFFFFFF),
                  debugBufferCache: cache,
                  debugDisableSingleBuffer: disableBuffer,
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

    Uint8List? baseline;

    int report(String phase, Uint8List probe) {
      final base = baseline;
      if (base == null) {
        return 0;
      }
      var diff = 0;
      var onLineEdge = 0;
      var onTileBoundary = 0;
      var fullFlips = 0;
      final samples = <String>[];
      final w = screen.width.round();
      final h = screen.height.round();
      double axisEdgeDist(double v) {
        // Line body occupies [32, 33) mod 64 — its edges are at 32 and 33.
        final m = v % 64.0;
        final d1 = (m - 32.0).abs();
        final d2 = (m - 33.0).abs();
        return d1 < d2 ? d1 : d2;
      }

      double tileEdgeDist(double v) {
        final m = v % tileSize.toDouble();
        return m < tileSize - m ? m : tileSize - m;
      }

      for (var y = 0; y < h; y += 1) {
        for (var x = 0; x < w; x += 1) {
          final i = (y * w + x) * 4;
          if (base[i] == probe[i] &&
              base[i + 1] == probe[i + 1] &&
              base[i + 2] == probe[i + 2] &&
              base[i + 3] == probe[i + 3]) {
            continue;
          }
          diff += 1;
          final cx = (x + 0.5 - panX) / zoom;
          final cy = (y + 0.5 - panY) / zoom;
          if (axisEdgeDist(cx) <= 1.5 || axisEdgeDist(cy) <= 1.5) {
            onLineEdge += 1;
          }
          if (tileEdgeDist(cx) <= 1.5 || tileEdgeDist(cy) <= 1.5) {
            onTileBoundary += 1;
          }
          final baseWhite = base[i] == 255 && base[i + 1] == 255;
          final baseBlack = base[i] == 0 && base[i + 3] == 255;
          final probeWhite = probe[i] == 255 && probe[i + 1] == 255;
          final probeBlack = probe[i] == 0 && probe[i + 3] == 255;
          if ((baseWhite && probeBlack) || (baseBlack && probeWhite)) {
            fullFlips += 1;
          }
          if (samples.length < 16) {
            samples.add(
              '($x,$y)[${base[i]},${base[i + 1]},${base[i + 2]},'
              '${base[i + 3]}->${probe[i]},${probe[i + 1]},${probe[i + 2]},'
              '${probe[i + 3]}]',
            );
          }
        }
      }
      debugPrint(
        'PROBE[$tag] $phase: diff=$diff onLineEdge=$onLineEdge '
        'onTileBoundary=$onTileBoundary fullFlips=$fullFlips '
        'full=${cache.fullCount} patched=${cache.patchedCount} '
        'dirty=${cache.lastDirtyRect} '
        '${samples.isEmpty ? '' : 'samples=${samples.join(' ')}'}',
      );
      return diff;
    }

    // ------------------------------------------------------------------
    // Fixture surfaces: identical bytes, distinct identities.
    final tilesV1 = freshTiles();
    final surface1 = surfaceOf(tilesV1);
    final coord00 = TileCoord(x: 0, y: 0);
    final tile00V2 = BitmapTile(
      coord: coord00,
      size: tileSize,
      pixels: linePixels(0, 0),
    );
    final surface2 = surfaceOf({...tilesV1, coord00: tile00V2});
    final surface3 = surfaceOf(freshTiles());
    await decodeAll(tester, surface1);
    await decodeAll(tester, surface2);
    await decodeAll(tester, surface3);

    BitmapSurfacePainter painterFor(BitmapSurface surface) =>
        BitmapSurfacePainter(
          surface: surface,
          overlayModel: overlay,
          showTransparentBackground: false,
        );

    // 1. steady: two paints of an untouched view must be byte-identical.
    final painter1 = await pumpWith(painterFor(surface1));
    final steadyA = await paintBytes(tester, painter1);
    final steadyB = await paintBytes(tester, painter1);
    expect(
      steadyA,
      equals(steadyB),
      reason: 'steady-state double paint must hold — otherwise every later '
          'comparison is noise',
    );
    baseline = steadyA;
    debugPrint(
      'PROBE[$tag] steady: baseline stable, full=${cache.fullCount} '
      'patched=${cache.patchedCount}',
    );

    // 2. pen-down arm: what interactive_brush_edit_canvas_view.dart:735
    //    does before any dab lands. Committed pixels untouched.
    overlay.preBlendBase = surface1;
    report('pen-down-arm(preBlendBase)', await paintBytes(tester, painter1));

    // 3. first dab, zero ink: a transparent stroke snapshot pre-blends to
    //    exactly the committed bytes, so the overlay tile REPLACES the
    //    committed tile with identical content. This is the pen-down
    //    frame where the buffer key first misses and the PATCH path runs.
    overlay.updateRegion(
      source: _TransparentStrokeSource(canvasSize),
      region: DirtyRegion(
        left: 10,
        top: 10,
        rightExclusive: 11,
        bottomExclusive: 11,
      ),
    );
    await tester.runAsync(() => overlay.waitForPendingDecodes());
    report('first-dab(patch)', await paintBytes(tester, painter1));

    // 4. pen-up: commit lands (tile 0,0 replaced by an identical-bytes new
    //    tile), overlay flips to settling with a stand-in and the
    //    pre-stroke pin — _bufferKey() answers null, so every paint here
    //    is an UNCACHED full compose.
    overlay.settling = true;
    overlay.markStandIn(coord00);
    overlay.holdPreStrokeTiles({coord00: tilesV1[coord00]});
    final painter2 = await pumpWith(painterFor(surface2));
    final settling1 = await paintBytes(tester, painter2);
    report('pen-up-settling#1(uncached-full)', settling1);
    final settling2 = await paintBytes(tester, painter2);
    report('pen-up-settling#2(uncached-full)', settling2);
    debugPrint(
      'PROBE[$tag] settling#1 vs settling#2 identical: '
      '${_bytesEqual(settling1, settling2)}',
    );

    // 5. settle release: overlay drops, the kept buffer is a stroke
    //    behind — the next paint patches the released coordinate back.
    overlay.reset();
    report('settle-release(patch)', await paintBytes(tester, painter2));

    // 6. layer switch analogue: a different painter instance carrying a
    //    surface with identical bytes but all-new tile identities. Every
    //    coordinate reads dirty, so the compose patches the whole canvas.
    final painter3 = await pumpWith(painterFor(surface3));
    report('layer-switch(all-dirty-patch)', await paintBytes(tester, painter3));

    // 7. fill-tap arm: a stamp overlay makes _liveDirtyCanvasRect refuse
    //    (null) while the patch base still exists — a FULL compose is
    //    forced with the picture unchanged (the stamp is transparent).
    final stamp = await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder);
      final picture = recorder.endRecording();
      final image = picture.toImageSync(1, 1);
      picture.dispose();
      return image;
    });
    overlay.setStampOverlay(stamp!, Offset.zero);
    report('stamp-arm(dirty-refused-full)', await paintBytes(tester, painter3));
    overlay.reset();
    report('stamp-release(full)', await paintBytes(tester, painter3));

    // 8. the ROUTE FLIP measured directly: the same picture through the
    //    direct walk instead of the buffer. If a transition frame ever
    //    falls off the buffer route, THIS is the picture it swaps to.
    final walkPainter = await pumpWith(
      painterFor(surface3),
      disableBuffer: true,
    );
    final walkDiff = report(
      'direct-walk(route-flip)',
      await paintBytes(tester, walkPainter),
    );
    // The pan-phase snap's oracle: both routes render under the SAME
    // snapped translation, so the fractional-pan strip cannot exist any
    // more — it is structurally impossible, not merely unobserved. The
    // integer-pan run pins the zero the routes always had.
    expect(
      walkDiff,
      0,
      reason: 'buffer route vs direct walk must be byte-identical at any '
          'pan phase — a nonzero diff is the transition route-flip jump',
    );
  }

  // Logical == device pixels for both probes: [paintBytes] rasterises at
  // the LOGICAL size, while the painter's snap counts DEVICE pixels
  // through MediaQuery's DPR — at the test binding's default DPR of 3 the
  // snapped phase would still be fractional in the 1:1 raster, a mixed
  // geometry no screen shows.
  testWidgets('fractional pan: zoom 1.5, pan (10.37, 3.71)', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);
    await runSequence(
      tester,
      tag: 'frac',
      viewport: CanvasViewport(zoom: 1.5, panX: 10.37, panY: 3.71),
    );
  });

  testWidgets('integer pan: zoom 1.5, pan (10, 4)', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);
    await runSequence(
      tester,
      tag: 'int',
      viewport: CanvasViewport(zoom: 1.5, panX: 10, panY: 4),
    );
  });
}

bool _bytesEqual(Uint8List a, Uint8List b) {
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i += 1) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}

/// A stroke source whose every pixel is transparent: the pre-blend of
/// "no ink yet" against the committed tile is exactly the committed tile,
/// so the overlay's replacement tile carries identical bytes and any
/// screen diff is the compose path's own doing.
class _TransparentStrokeSource implements ActiveStrokePixelSource {
  _TransparentStrokeSource(this.canvasSize);

  final CanvasSize canvasSize;

  @override
  int get canvasWidth => canvasSize.width;

  @override
  int get canvasHeight => canvasSize.height;

  @override
  void copyRow(int x, int y, int count, Uint8List target, int targetOffset) {
    target.fillRange(targetOffset, targetOffset + count * 4, 0);
  }
}
