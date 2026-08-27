import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/canvas/subtree_image_composite.dart';

/// 🚨★★★A GROUP IS AN IMAGE — AND IT IS THE SAME PIXELS `saveLayer` MADE.
///
/// The editing stack used to composite a folder with `saveLayer`. It now
/// rasterises the folder to a `ui.Image` and blits it, because a saveLayer
/// offscreen belongs to Skia and nobody can sample it: a fragment shader on
/// a FOLDER needs the group as pixels, and so does a per-group cache.
///
/// ⚠️The existing route-parity tests cannot certify that swap. They compare
/// the buffered route against the direct walk — and BOTH changed, so a
/// systematic error would agree with itself. This file compares the new
/// technique against the old one directly, in isolation, at the geometry
/// the stack actually uses.
///
/// 📐The stack's normal route composites into a recorder whose CTM is
/// `translate(-rect.left, -rect.top)` with an INTEGER rect and scale 1, so
/// the group blit is 1:1 on the device grid. That is the class this file
/// pins as an identity. A fractional device phase is measured separately
/// and stated rather than assumed.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const deviceWidth = 96;
  const deviceHeight = 64;

  void drawBackdrop(Canvas canvas, double scale) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, deviceWidth / scale, deviceHeight / scale),
      Paint()
        ..color = const Color(0xFF204060)
        ..isAntiAlias = false,
    );
  }

  // ⛔Anti-aliasing OFF and edges on whole units: this file is about the
  // COMPOSITE, and an aliased edge would fold rasterisation phase into the
  // same number and make a pass or a fail impossible to attribute.
  void drawChildren(Canvas canvas) {
    canvas.drawRect(
      const Rect.fromLTWH(10, 8, 24, 20),
      Paint()
        ..color = const Color(0xFFE04030)
        ..isAntiAlias = false,
    );
    canvas.drawRect(
      const Rect.fromLTWH(26, 18, 20, 22),
      Paint()
        ..color = const Color(0x8030A0FF)
        ..isAntiAlias = false,
    );
  }

  // ⛔THE PRODUCTION FUNCTION, not a copy of it. A second copy of this
  // arithmetic here would certify the copy and let the original drift —
  // mutate [drawSubtreeAsImage] and this file must go red.
  void drawGroupAsImage(
    Canvas canvas,
    Rect groupRect,
    Paint paint,
    double scale,
    int maxPixelSide,
  ) => drawSubtreeAsImage(
    canvas: canvas,
    bounds: groupRect,
    paint: paint,
    rasterScale: scale,
    maxPixelSide: maxPixelSide,
    paintSubtree: (into, _) => drawChildren(into),
  );

  Future<Uint8List> render({
    required Paint groupPaint,
    required Rect groupRect,
    required bool asImage,
    double scale = 1,
    double devicePhase = 0,
    int maxPixelSide = 8192,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.translate(devicePhase, devicePhase);
    canvas.scale(scale);
    drawBackdrop(canvas, scale);
    if (asImage) {
      drawGroupAsImage(canvas, groupRect, groupPaint, scale, maxPixelSide);
    } else {
      canvas.saveLayer(groupRect, groupPaint);
      drawChildren(canvas);
      canvas.restore();
    }
    final picture = recorder.endRecording();
    final image = picture.toImageSync(deviceWidth, deviceHeight);
    picture.dispose();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    return bytes!.buffer.asUint8List();
  }

  int differingPixels(Uint8List a, Uint8List b) {
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

  Future<void> expectSamePixels(
    String what, {
    required Paint Function() groupPaint,
    Rect groupRect = const Rect.fromLTWH(6, 4, 46, 42),
    double scale = 1,
  }) async {
    final layered = await render(
      groupPaint: groupPaint(),
      groupRect: groupRect,
      asImage: false,
      scale: scale,
    );
    final imaged = await render(
      groupPaint: groupPaint(),
      groupRect: groupRect,
      asImage: true,
      scale: scale,
    );
    // ⛔An all-transparent pair would pass this trivially. Prove the scene
    // actually drew before believing the two agree about it.
    expect(
      layered.any((byte) => byte != 0),
      isTrue,
      reason: '$what drew nothing at all',
    );
    expect(
      differingPixels(layered, imaged),
      0,
      reason: '$what: the image blit must be the saveLayer, pixel for pixel',
    );
  }

  group('the group image is the saveLayer it replaced', () {
    test('plain — no opacity, no blend, no effect', () async {
      await expectSamePixels(
        'plain',
        groupPaint: () => Paint()..color = const Color(0xFF000000),
      );
    });

    test('folder opacity', () async {
      await expectSamePixels(
        'opacity 0.5',
        groupPaint: () => Paint()..color = const Color(0x80000000),
      );
    });

    test('folder blend mode', () async {
      await expectSamePixels(
        'multiply',
        groupPaint: () => Paint()
          ..color = const Color(0xFF000000)
          ..blendMode = BlendMode.multiply,
      );
      await expectSamePixels(
        'screen at half opacity',
        groupPaint: () => Paint()
          ..color = const Color(0x80000000)
          ..blendMode = BlendMode.screen,
      );
    });

    test('folder colour filter', () async {
      await expectSamePixels(
        'saturation matrix',
        groupPaint: () => Paint()
          ..color = const Color(0xFF000000)
          ..colorFilter = const ColorFilter.matrix(<double>[
            0.6, 0.3, 0.1, 0, 0, //
            0.2, 0.7, 0.1, 0, 0, //
            0.2, 0.3, 0.5, 0, 0, //
            0, 0, 0, 1, 0, //
          ]),
      );
    });

    test(
      'folder blur — the case the bounds clip is load-bearing for',
      () async {
        // The stack inflates the group rect by the blur's spread before it
        // gets here ([effectBufferBounds]), so this rect is what the stack
        // would hand in: content plus spread.
        await expectSamePixels(
          'blur sigma 3',
          groupRect: const Rect.fromLTWH(-3, -5, 64, 60),
          groupPaint: () => Paint()
            ..color = const Color(0xFF000000)
            ..imageFilter = ui.ImageFilter.blur(sigmaX: 3, sigmaY: 3),
        );
      },
    );

    test('a fractional group rect still lands on the same pixels', () async {
      await expectSamePixels(
        'fractional bounds',
        groupRect: const Rect.fromLTWH(6.37, 4.82, 46.4, 42.1),
        groupPaint: () => Paint()
          ..color = const Color(0xC0000000)
          ..blendMode = BlendMode.multiply,
      );
    });

    test('above 100% — every device pixel still matches', () async {
      await expectSamePixels(
        'scale 2',
        scale: 2,
        groupPaint: () => Paint()
          ..color = const Color(0xC0000000)
          ..blendMode = BlendMode.multiply,
      );
    });
  });

  test('the cap clamps the raster instead of refusing to draw', () async {
    // ⛔THE ONE ARM THAT IS NOT AN IDENTITY, and it must still be a DRAW. A
    // refusal here would be a second code path — the path where a folder's
    // effect silently does not apply — so the cap shrinks the raster the way
    // the display buffer does and keeps one way to composite a group.
    const rect = Rect.fromLTWH(6, 4, 46, 42);
    final clamped = await render(
      groupPaint: Paint()..color = const Color(0xFF000000),
      groupRect: rect,
      asImage: true,
      // 46px of group through a 16px cap: the blit magnifies ~2.9×.
      maxPixelSide: 16,
    );
    var drewInside = 0;
    var escaped = 0;
    for (var y = 0; y < deviceHeight; y++) {
      for (var x = 0; x < deviceWidth; x++) {
        final at = (y * deviceWidth + x) * 4;
        final isBackdrop =
            clamped[at] == 0x20 &&
            clamped[at + 1] == 0x40 &&
            clamped[at + 2] == 0x60 &&
            clamped[at + 3] == 0xFF;
        if (rect.contains(Offset(x + 0.5, y + 0.5))) {
          if (!isBackdrop) {
            drewInside += 1;
          }
        } else if (!isBackdrop) {
          escaped += 1;
        }
      }
    }
    expect(drewInside, greaterThan(200), reason: 'the clamped group must '
        'still draw, not silently vanish');
    expect(escaped, 0, reason: 'the clamped blit must stay inside the bounds '
        'the saveLayer clipped to');
  });

  test('a fractional DEVICE phase never changes the body of the group', () async {
    // 📐STATED, NOT ASSUMED. Placed at a fractional device offset, an image
    // blit resamples where vector content would have rasterised at the true
    // phase. The stack's canvas-resolution buffer records under
    // `translate(-integer, -integer)` at scale 1, so it never asks this
    // question — but the number belongs on the record rather than in an
    // argument, and this fails loudly if the geometry ever drifts far
    // enough to make the difference more than an edge.
    Paint paint() => Paint()..color = const Color(0xFF000000);
    const rect = Rect.fromLTWH(6, 4, 46, 42);
    final layered = await render(
      groupPaint: paint(),
      groupRect: rect,
      asImage: false,
      devicePhase: 0.5,
    );
    final imaged = await render(
      groupPaint: paint(),
      groupRect: rect,
      asImage: true,
      devicePhase: 0.5,
    );
    expect(
      differingPixels(layered, imaged),
      lessThan(deviceWidth * deviceHeight ~/ 8),
      reason: 'a half-pixel phase may soften edges; it must never change '
          'the body of the group',
    );
  });
}
