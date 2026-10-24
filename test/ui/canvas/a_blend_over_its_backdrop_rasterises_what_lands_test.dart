@Tags(['impeller'])
library;

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/ui/canvas/layer_blend_shader.dart';
import 'package:anicel/src/ui/canvas/subtree_image_composite.dart';

/// 🚨A row composed over its backdrop rasterises only what the canvas still
/// shows ([drawBlendOverBackdrop]) — its clip, a stroke's patch while one is
/// drawn — and that part lands the bytes the whole would have there.
/// 🔬The whole buffer three times a step put a frame 49ms after its input
/// on the Windows app (10-22), against 12ms with the row normal.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(LayerBlendShader.load);

  const side = 64;
  final whole = Rect.fromLTWH(0, 0, side.toDouble(), side.toDouble());

  /// An opaque image whose every pixel differs from its neighbours, [width]
  /// × [height] texels.
  Future<ui.Image> imageOf(int seed, {int width = side, int height = side}) {
    final pixels = Uint8List(width * height * 4);
    for (var i = 0; i < width * height; i += 1) {
      pixels[i * 4] = (i * 7 + seed) & 0xFF;
      pixels[i * 4 + 1] = (i * 13 + seed * 3) & 0xFF;
      pixels[i * 4 + 2] = (i * 29 + seed * 5) & 0xFF;
      pixels[i * 4 + 3] = 255;
    }
    final done = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      pixels,
      width,
      height,
      ui.PixelFormat.rgba8888,
      done.complete,
    );
    return done.future;
  }

  /// The bytes the screen gets with the row drawn under [clip] at
  /// [rasterScale], the canvas under [transform], [outSide] pixels a side —
  /// the recording shown whole in that image, or within [shownWithin], or,
  /// [shownNowhere], somewhere it may be cut again. The row's image is the
  /// whole, [side] texels a side, or lies at [rowAt], [rasterScale] texels a
  /// canvas pixel; it is handed over as it is where [handedAsIs]. [cap] is
  /// the longest side a raster may take.
  Future<Uint8List> landed({
    required Rect clip,
    required double rasterScale,
    Matrix4? transform,
    int outSide = side,
    Rect? shownWithin,
    bool shownNowhere = false,
    Rect? rowAt,
    bool handedAsIs = false,
    int cap = maxSubtreeRasterSide,
  }) async {
    final at = rowAt ?? whole;
    final below = await imageOf(11);
    final row = rowAt == null
        ? await imageOf(97)
        : await imageOf(
            97,
            width: (rowAt.width * rasterScale).round(),
            height: (rowAt.height * rasterScale).round(),
          );
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    if (transform != null) {
      canvas.transform(transform.storage);
    }
    canvas.clipRect(clip);
    final output = Rect.fromLTWH(0, 0, outSide.toDouble(), outSide.toDouble());
    drawBlendOverBackdrop(
      canvas: canvas,
      bounds: whole,
      rasterScale: rasterScale,
      maxPixelSide: cap,
      paintBackdrop: (into, _) => into.drawImage(below, Offset.zero, Paint()),
      paintSource: (into, _) => into.drawImageRect(
        row,
        Offset.zero & Size(row.width.toDouble(), row.height.toDouble()),
        at,
        Paint(),
      ),
      sourceAsIs: handedAsIs ? (image: row, worldRect: at) : null,
      blendMode: LayerBlendMode.linearBurn,
      shownWithin: shownNowhere
          ? null
          : shownWithin ??
                (transform == null
                    ? output
                    : MatrixUtils.inverseTransformRect(transform, output)),
    );
    final picture = recorder.endRecording();
    final image = picture.toImageSync(outSide, outSide);
    picture.dispose();
    below.dispose();
    row.dispose();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    return bytes!.buffer.asUint8List();
  }

  /// The bytes of [bytes] inside [clip], row by row.
  List<int> inside(Uint8List bytes, Rect clip) => [
    for (var y = clip.top.toInt(); y < clip.bottom.toInt(); y += 1)
      for (var x = clip.left.toInt(); x < clip.right.toInt(); x += 1)
        for (var c = 0; c < 4; c += 1) bytes[(y * side + x) * 4 + c],
  ];

  const clip = Rect.fromLTWH(10, 20, 17, 13);

  test('only the part under the clip is rasterised', () async {
    await landed(clip: clip, rasterScale: 1);
    final plan = debugLastSubtreeRaster!;
    expect(
      (plan.pixelWidth, plan.pixelHeight),
      (17, 13),
      reason: 'the row\'s whole buffer is 64×64 — rasterised whole three '
          'times a step, wherever the stroke was',
    );
  });

  test('the part lands the bytes the whole lands there', () async {
    for (final scale in [1.0, 1.5]) {
      final part = await landed(clip: clip, rasterScale: scale);
      final all = await landed(clip: whole, rasterScale: scale);
      expect(
        inside(part, clip),
        inside(all, clip),
        reason: 'at ×$scale the part samples on the whole\'s grid',
      );
    }
  });

  test('where the frame is not read, the composite is drawn on the canvas, '
      'not rasterised to be blitted', () async {
    debugBlendsComposedInARaster = 0;
    await landed(clip: whole, rasterScale: 1.5, shownNowhere: true);
    expect(debugLastSubtreeRaster!.magnifies, isFalse, reason: 'premise');
    expect(
      debugBlendsComposedInARaster,
      0,
      reason: 'a third raster a step, only to land 1:1 (Q6, 10-23)',
    );

    await landed(
      clip: whole,
      rasterScale: 1,
      shownNowhere: true,
      cap: side ~/ 2,
    );
    expect(debugLastSubtreeRaster!.magnifies, isTrue, reason: 'premise');
    expect(
      debugBlendsComposedInARaster,
      1,
      reason: 'the capped blit filters, and must filter what was composed',
    );
  });

  // ⚠️IMPELLER ONLY: Skia has no shader filter, so on the default runner
  // every blend rasterises its backdrop and these skip.
  // `flutter test --enable-impeller` runs them (Vulkan) — the file's
  // `impeller` tag sends it there.
  group('read in the frame', () {
    final skip = ui.ImageFilter.isShaderFilterSupported
        ? false
        : 'the engine has no shader filter (Skia)';

    /// [landed] read in the frame where it can be, then with the backdrop
    /// rasterised.
    Future<(Uint8List, Uint8List)> bothRoutes({
      required Rect clip,
      required double rasterScale,
      required bool inTheFrame,
      Matrix4? transform,
      int outSide = side,
    }) async {
      debugBlendsReadInTheFrame = 0;
      final frame = await landed(
        clip: clip,
        rasterScale: rasterScale,
        transform: transform,
        outSide: outSide,
      );
      expect(
        debugBlendsReadInTheFrame,
        inTheFrame ? 1 : 0,
        reason: 'premise: ${inTheFrame ? 'in' : 'not in'} the frame',
      );
      debugBlendInTheFrame = false;
      try {
        final raster = await landed(
          clip: clip,
          rasterScale: rasterScale,
          transform: transform,
          outSide: outSide,
        );
        return (frame, raster);
      } finally {
        debugBlendInTheFrame = true;
      }
    }

    // Each with whether a clip off the raster's grid — on the device's
    // pixels, 10.5 at ×1 — is still read in the frame: not at ×2 drawn from
    // ×1, where the layer snapped out to the raster pokes past the clip.
    final upright = <String, (Matrix4?, double, int, bool)>{
      'at the identity': (null, 1, side, true),
      'a buffer\'s pixels at ×2': (
        Matrix4.diagonal3Values(2, 2, 1)..setTranslationRaw(6, 4, 0),
        2,
        side * 2 + 8,
        true,
      ),
      'a picture drawn on a screen at ×2': (
        Matrix4.diagonal3Values(2, 2, 1)..setTranslationRaw(6, 4, 0),
        1,
        side * 2 + 8,
        false,
      ),
    };
    for (final MapEntry(key: name, value: (transform, scale, out, offGrid))
        in upright.entries) {
      test('it lands the bytes its rastered backdrop does: $name', () async {
        final cuts = {
          whole: true,
          clip: true,
          const Rect.fromLTWH(10.5, 20, 17, 13): offGrid,
        };
        for (final MapEntry(key: at, value: inTheFrame) in cuts.entries) {
          final (frame, raster) = await bothRoutes(
            clip: at,
            rasterScale: scale,
            inTheFrame: inTheFrame,
            transform: transform,
            outSide: out,
          );
          expect(frame, raster, reason: 'under $at');
        }
      }, skip: skip);
    }

    final elsewhere = <String, Future<void> Function()>{
      'under a rotation': () => landed(
        clip: whole,
        rasterScale: 1,
        transform: Matrix4.rotationZ(1.5707963267948966)
          ..setTranslationRaw(64, 0, 0),
      ),
      'under a flip': () => landed(
        clip: whole,
        rasterScale: 1,
        transform: Matrix4.diagonal3Values(-1, 1, 1)
          ..setTranslationRaw(64, 0, 0),
      ),
      // Shown well past the layer, so the half pixel alone says no.
      'off a whole pixel': () => landed(
        clip: whole,
        rasterScale: 1,
        transform: Matrix4.translationValues(0.5, 0, 0),
        shownWithin: const Rect.fromLTWH(-8, -8, 80, 80),
      ),
      'where it is shown cut': () => landed(
        clip: whole,
        rasterScale: 1,
        shownWithin: const Rect.fromLTWH(0, 0, 32, 32),
      ),
      'where it may be cut again': () =>
          landed(clip: whole, rasterScale: 1, shownNowhere: true),
    };
    for (final MapEntry(key: name, value: draw) in elsewhere.entries) {
      test('it is not read in the frame $name', () async {
        debugBlendsReadInTheFrame = 0;
        await draw();
        expect(debugBlendsReadInTheFrame, 0);
      }, skip: skip);
    }
  });

  // ④ of a-blurred-folder-cut-by-the-view-moves-on-vulkan: a row that is one
  // image, laid texel for texel on the grid the shader draws, goes to it as
  // it is — the raster every step paid for it, whatever moved below it.
  // On the default runner the backdrop is rastered; under
  // `--enable-impeller` it is read in the frame, and the row's raster was
  // then the only one left.
  group('a row handed over as it is', () {
    const ink = Rect.fromLTWH(8, 12, 20, 16);
    final rows = <String, (Rect?, double, Matrix4?, int)>{
      'the whole at the identity': (null, 1, null, side),
      'an ink at the identity': (ink, 1, null, side),
      'an ink on a buffer\'s pixels at ×2': (
        ink,
        2,
        Matrix4.diagonal3Values(2, 2, 1)..setTranslationRaw(6, 4, 0),
        side * 2 + 8,
      ),
    };

    /// [landed] with the row handed over, then rastered: the bytes of each
    /// and how many rasters each made.
    Future<((Uint8List, int), (Uint8List, int))> bothRows({
      required Rect clip,
      required double rasterScale,
      Matrix4? transform,
      int outSide = side,
      required Rect? rowAt,
    }) async {
      Future<(Uint8List, int)> counted() async {
        debugSubtreeRasterCount = 0;
        final bytes = await landed(
          clip: clip,
          rasterScale: rasterScale,
          transform: transform,
          outSide: outSide,
          rowAt: rowAt,
          handedAsIs: true,
        );
        return (bytes, debugSubtreeRasterCount);
      }

      final handed = await counted();
      debugSourceAsIs = false;
      try {
        return (handed, await counted());
      } finally {
        debugSourceAsIs = true;
      }
    }

    for (final MapEntry(key: name, value: (rowAt, scale, transform, out))
        in rows.entries) {
      test('it lands the bytes its raster does, one raster fewer: $name',
          () async {
        for (final at in [whole, clip]) {
          final ((handed, handedRasters), (rastered, rasters)) =
              await bothRows(
                clip: at,
                rasterScale: scale,
                transform: transform,
                outSide: out,
                rowAt: rowAt,
              );
          expect(handed, rastered, reason: 'under $at');
          expect(handedRasters, rasters - 1, reason: 'under $at');
        }
      });
    }

    test('a row off the grid is rastered', () async {
      final ((handed, handedRasters), (rastered, rasters)) = await bothRows(
        clip: whole,
        rasterScale: 1,
        rowAt: const Rect.fromLTWH(8.5, 12, 20, 16),
      );
      expect(handedRasters, rasters, reason: 'half a pixel off its grid');
      expect(handed, rastered);
    });

    test('a row is rastered where the frame is read on a screen past the '
        'raster\'s scale', () async {
      final ((_, handedRasters), (_, rasters)) = await bothRows(
        clip: whole,
        rasterScale: 1,
        transform: Matrix4.diagonal3Values(2, 2, 1)
          ..setTranslationRaw(6, 4, 0),
        outSide: side * 2 + 8,
        rowAt: ink,
      );
      expect(
        handedRasters,
        rasters,
        reason: 'the layer is the screen\'s, two of its pixels a texel',
      );
    },
        skip: ui.ImageFilter.isShaderFilterSupported
            ? false
            : 'the engine has no shader filter (Skia)');
  });
}
