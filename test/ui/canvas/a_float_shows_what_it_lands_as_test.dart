import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/landing_preview.dart';
import 'package:anicel/src/ui/canvas/selection_float_overlay.dart';
import 'package:anicel/src/ui/canvas/tile_picture_budget.dart';

/// 🚨★★★F-240 — WHILE IT FLOATS, IT SHOWS WHAT IT LANDS AS, AT EVERY ZOOM.
///
/// 유저 2026-09-29: 「변형툴 변형도중이랑 확정이랑 그림 바뀌는 문제. 100%줌일땐
/// 괜찮은데 50%에서 변형중에 필터 없음으로 보임 … 변형중에도 필터 통일적용하도록
/// 근본/구조적 해결」.
///
/// Reduced, a landed cel shows as its tiles' pictures drawn by the display's
/// filter from their chains. A float laid over those tiles at `none` was
/// sampled one pixel in two instead, so the picture changed the moment it
/// landed. Here the SAME surface paint is asked twice: once holding the
/// float (while it floats), once holding a cel whose tiles are what 100%
/// showed with the float on it (after it lands) — and at the halvings and
/// between them the two must be the same bytes, on the tester's Skia and
/// on its Impeller (`--enable-impeller`). The cel and the float are opaque
/// high-frequency patterns, so nearest sampling and the mean disagree nearly
/// everywhere; the scene proves it can tell them apart before it is trusted.
///
/// ↩️⚠️WHERE IT WAS EXACT while a landed cel showed as level tiles
/// (measured 2026-09-30, until one-picture-per-frame ②-5b-2): the test
/// runner's Skia and the real Windows app (Impeller GLES) — 0 pixels apart,
/// all six cases. On Impeller Vulkan (`--enable-impeller`) it was RED by
/// 1/255 at 2–12 pixels: the floating region was halved as one image and the
/// landed cel tile by tile, and Vulkan's halving drifts with the size of
/// what it halves (board `halving-rounds-differently-per-engine`). The old
/// draw was 133–168/255 off on the same scene there.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const tile = 16;
  const width = 64;
  const height = 48;
  const canvasSize = CanvasSize(width: width, height: height);

  /// An opaque pattern that changes every pixel, keyed by [seed].
  Uint8List pattern(int w, int h, int seed) {
    final px = Uint8List(w * h * 4);
    for (var y = 0; y < h; y += 1) {
      for (var x = 0; x < w; x += 1) {
        final o = (y * w + x) * 4;
        px[o] = (x * 37 + y * 11 + seed * 7) % 256;
        px[o + 1] = (x * 5 + y * 53 + seed * 13) % 256;
        px[o + 2] = ((x ^ y) * 29 + seed * 31) % 256;
        px[o + 3] = 255;
      }
    }
    return px;
  }

  /// A cel of [w]×[h] straight pixels, cut into its tiles.
  BitmapSurface surfaceOf(Uint8List straight) {
    final tiles = <TileCoord, BitmapTile>{};
    for (var ty = 0; ty < height ~/ tile; ty += 1) {
      for (var tx = 0; tx < width ~/ tile; tx += 1) {
        final px = Uint8List(tile * tile * 4);
        for (var y = 0; y < tile; y += 1) {
          final from = ((ty * tile + y) * width + tx * tile) * 4;
          px.setRange(y * tile * 4, (y + 1) * tile * 4, straight, from);
        }
        tiles[TileCoord(x: tx, y: ty)] = BitmapTile(size: tile, pixels: px);
      }
    }
    return BitmapSurface(canvasSize: canvasSize, tileSize: tile, tiles: tiles);
  }

  Future<ui.Image> imageOf(Uint8List opaque, int w, int h) {
    final done = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      opaque,
      w,
      h,
      ui.PixelFormat.rgba8888,
      done.complete,
    );
    return done.future;
  }

  /// [painter]'s content at [scale], the float laid through the surface
  /// pass — or, [floatOnTop], drawn over it at `none` afterwards, the way
  /// the stack did before F-240 — the row's [layerPaint] riding the draws.
  Future<ui.Image> paint(
    BitmapSurfacePainter painter, {
    required double scale,
    LandingPreview? float,
    bool floatOnTop = false,
    ui.Paint? layerPaint,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder)
      ..scale(scale)
      ..clipRect(const ui.Rect.fromLTWH(0, 0, width * 1.0, height * 1.0));
    painter.paintContentInto(
      canvas,
      layerPaint: layerPaint,
      scale: scale,
      float: floatOnTop || float == null
          ? null
          : (preview: float, canvasToRow: null),
    );
    if (floatOnTop) {
      float!.paintInto(canvas);
    }
    final picture = recorder.endRecording();
    final image = await picture.toImage(
      (width * scale).ceil(),
      (height * scale).ceil(),
    );
    picture.dispose();
    return image;
  }

  Future<Uint8List> bytes(
    ui.Image image, {
    ui.ImageByteFormat format = ui.ImageByteFormat.rawRgba,
  }) async => (await image.toByteData(format: format))!.buffer.asUint8List();

  int differing(Uint8List a, Uint8List b) {
    var count = 0;
    for (var i = 0; i < a.length; i += 4) {
      if (a[i] != b[i] ||
          a[i + 1] != b[i + 1] ||
          a[i + 2] != b[i + 2] ||
          a[i + 3] != b[i + 3]) {
        count += 1;
      }
    }
    return count;
  }

  var lineages = 0;
  BitmapSurfacePainter painterOf(BitmapSurface surface) => BitmapSurfacePainter(
    surface: surface,
    showTransparentBackground: false,
    lineage: 'f240-${lineages++}',
  );

  /// While it floats and once it has landed, at [scale] on a row drawn with
  /// [layerPaint]: the floating paint, the landed paint, and what the old
  /// overlay drew. The landing writes what 100% shows of the cel itself.
  Future<({Uint8List floating, Uint8List landed, Uint8List old})> both(
    double scale, {
    required LandingPreview float,
    ui.Paint? layerPaint,
  }) async {
    final cel = surfaceOf(pattern(width, height, 1));
    final floating = painterOf(cel);
    // What 100% shows with the preview on it is what the landing writes.
    final atFull = await paint(floating, scale: 1, float: float);
    final landedCel = surfaceOf(
      await bytes(atFull, format: ui.ImageByteFormat.rawStraightRgba),
    );
    atFull.dispose();
    final whileFloating = await paint(
      floating,
      scale: scale,
      float: float,
      layerPaint: layerPaint,
    );
    final afterLanding = await paint(
      painterOf(landedCel),
      scale: scale,
      layerPaint: layerPaint,
    );
    final oldWay = await paint(
      painterOf(cel),
      scale: scale,
      float: float,
      floatOnTop: true,
      layerPaint: layerPaint,
    );
    final result = (
      floating: await bytes(whileFloating),
      landed: await bytes(afterLanding),
      old: await bytes(oldWay),
    );
    whileFloating.dispose();
    afterLanding.dispose();
    oldWay.dispose();
    return result;
  }

  // The halvings, and two reductions between them — where a tile's edge is
  // filtered on a band of its own (`chained_picture.dart`).
  for (final scale in [0.5, 0.25, 0.6, 0.3]) {
    final zoom = '${(scale * 100).round()}%';

    test('a TRANSFORM\'s float at $zoom shows the bytes it lands as', () async {
      final floatImage = await imageOf(pattern(22, 14, 2), 22, 14);
      final float = SelectionFloatPaint(
        image: floatImage,
        imageLeft: 13,
        imageTop: 9,
      );
      final seen = await both(scale, float: float);
      expect(
        differing(seen.old, seen.landed),
        greaterThan(20),
        reason: 'the scene must tell the old draw from the landing apart',
      );
      expect(
        differing(seen.floating, seen.landed),
        0,
        reason: 'while it floats the transform shows what it lands as',
      );
    });

    test('a MOVE\'s float at $zoom shows the bytes it lands as', () async {
      final lift = surfaceOf(pattern(width, height, 3));
      final float = SelectionFloatPaint(
        surface: BitmapSurfacePainter(
          surface: lift,
          showTransparentBackground: false,
          lineage: TilePictureBudget.noLineage,
        ),
        surfaceOffset: CanvasPoint(x: 5, y: 3),
        clip: const ui.Rect.fromLTWH(9, 7, 27, 19),
      );
      final seen = await both(scale, float: float);
      expect(differing(seen.old, seen.landed), greaterThan(20));
      expect(differing(seen.floating, seen.landed), 0);
    });

    // A row's opacity rides each tile's draw, so a tile the float touches
    // is drawn once — as the tile it lands as — and never under it too: a
    // pixel drawn twice at half reads three quarters.
    test('a TRANSFORM\'s float at $zoom on a row at half opacity shows the '
        'bytes it lands as', () async {
      final floatImage = await imageOf(pattern(22, 14, 2), 22, 14);
      final seen = await both(
        scale,
        float: SelectionFloatPaint(
          image: floatImage,
          imageLeft: 13,
          imageTop: 9,
        ),
        layerPaint: ui.Paint()..color = const ui.Color(0x80000000),
      );
      expect(differing(seen.old, seen.landed), greaterThan(20));
      expect(differing(seen.floating, seen.landed), 0);
    });

    // ↩️'a STAMP's ghost at $zoom shows the bytes it lands as' pinned the
    // painter's own ghost through this same halving. Since brush-fidelity-Q9
    // (유저 2026-10-18 「통일하면 좋음」) the ghost is the overlay's tiles —
    // the click's own bytes — so the painter draws no ghost to pin.
  }
}
