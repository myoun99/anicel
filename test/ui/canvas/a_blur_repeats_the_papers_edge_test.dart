import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/services/composite_effect_paint.dart';
import 'package:anicel/src/ui/canvas/colour_key_shader.dart';
import 'package:anicel/src/ui/canvas/subtree_image_composite.dart';

/// 🗣️I-132-Q14 a (유저 2026-10-28): a Gaussian's Repeat Edge Pixels repeats
/// the PAPER's edge — the canvas's, on a layer and a folder alike, as AE's
/// comp-sized solid and precomp — and what it draws stays on the paper.
///
/// Off, past the paper there is nothing and the edge fades into it; on, the
/// edge holds. Inside the paper the blur spreads as it always did: the edge
/// is the paper's, not the picture's.
void main() {
  setUpAll(ColourKeyShader.load);

  ResolvedLayerEffect gaussian({required bool repeats, double radius = 4}) =>
      ResolvedLayerEffect(
        kind: EffectKind.blur,
        values: [radius, 0, if (repeats) 1 else 0],
      );

  /// A [width]×[height] picture, white wherever [ink] covers and nothing
  /// elsewhere — all of it white without one.
  ui.Image picture(int width, int height, {Rect? ink}) {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(
      ink ?? Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      Paint()
        ..color = const Color(0xFFFFFFFF)
        ..isAntiAlias = false,
    );
    final drawn = recorder.endRecording();
    final image = drawn.toImageSync(width, height);
    drawn.dispose();
    return image;
  }

  Future<Uint8List> bytesOf(WidgetTester tester, ui.Image image) async {
    final data = await tester.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
    );
    return data!.buffer.asUint8List();
  }

  int alphaAt(Uint8List bytes, int width, int x, int y) =>
      bytes[(y * width + x) * 4 + 3];

  group('the step', () {
    testWidgets('on, a paper all ink stays all ink — its edge holds', (
      tester,
    ) async {
      final source = picture(32, 32);
      addTearDown(source.dispose);
      const paper = Rect.fromLTWH(0, 0, 32, 32);
      final out = steppedForChain(
        image: source,
        plan: resolveCompositeEffectPlan(
          [gaussian(repeats: true)],
          paper: paper,
        ),
        extent: paper,
        paper: paper,
      );
      addTearDown(out.dispose);
      expect(identical(out, source), isFalse, reason: '⛔전제: it is a step');
      expect(
        (await bytesOf(tester, out)).toSet(),
        {255},
        reason: 'every channel of every pixel, the corners too',
      );
    });

    testWidgets('nothing is drawn past the paper — ink on the pasteboard '
        'stays out of sight', (tester) async {
      // 48 pixels standing for the canvas's (−8, −8)…(40, 40): the paper's
      // 32 and a pasteboard of 8 round it, all ink.
      final source = picture(48, 48);
      addTearDown(source.dispose);
      final out = steppedForChain(
        image: source,
        plan: resolveCompositeEffectPlan(
          [gaussian(repeats: true)],
          paper: const Rect.fromLTWH(0, 0, 32, 32),
        ),
        extent: const Rect.fromLTWH(-8, -8, 48, 48),
        paper: const Rect.fromLTWH(0, 0, 32, 32),
      );
      addTearDown(out.dispose);
      final bytes = await bytesOf(tester, out);
      for (var y = 0; y < 48; y += 1) {
        for (var x = 0; x < 48; x += 1) {
          final onThePaper = x >= 8 && x < 40 && y >= 8 && y < 40;
          expect(
            alphaAt(bytes, 48, x, y),
            onThePaper ? 255 : 0,
            reason: '$x, $y',
          );
        }
      }
    });

    testWidgets('the edge is the paper\'s, not the picture\'s: ink clear of '
        'it blurs as it does off', (tester) async {
      final source = picture(32, 32, ink: const Rect.fromLTWH(12, 12, 8, 8));
      addTearDown(source.dispose);
      const paper = Rect.fromLTWH(0, 0, 32, 32);
      final on = steppedForChain(
        image: source,
        plan: resolveCompositeEffectPlan(
          [gaussian(repeats: true)],
          paper: paper,
        ),
        extent: paper,
        paper: paper,
      );
      addTearDown(on.dispose);
      // Off, the blur rides the draw.
      final off = resolveCompositeEffectPlan(
        [gaussian(repeats: false)],
        paper: paper,
      );
      expect(off.isSingleDraw, isTrue, reason: '⛔전제');
      final recorder = ui.PictureRecorder();
      final paint = Paint();
      off.finalPaint.applyTo(paint);
      Canvas(recorder).drawImage(source, Offset.zero, paint);
      final drawn = recorder.endRecording();
      final offImage = drawn.toImageSync(32, 32);
      drawn.dispose();
      addTearDown(offImage.dispose);

      final onBytes = await bytesOf(tester, on);
      final offBytes = await bytesOf(tester, offImage);
      // The pixel beside the ink: Impeller's Gaussian, the product's, ends
      // nearer than Skia's — three pixels off the ink it is 0 there, 7/255
      // under Skia (2026-10-30), on and off alike.
      expect(
        alphaAt(onBytes, 32, 11, 16),
        greaterThan(0),
        reason: 'it spreads past the ink, inside the paper',
      );
      for (var i = 0; i < onBytes.length; i += 1) {
        expect(onBytes[i], closeTo(offBytes[i], 1), reason: 'byte $i');
      }
    });

    testWidgets('on a raster at another scale, standing elsewhere, the paper '
        'is cut where it lies', (tester) async {
      // 64 pixels for the canvas's 32, from (−4, −4): the paper's 16 lie at
      // pixels 8…40.
      final source = picture(64, 64);
      addTearDown(source.dispose);
      final out = steppedForChain(
        image: source,
        plan: resolveCompositeEffectPlan(
          [gaussian(repeats: true)],
          paper: const Rect.fromLTWH(0, 0, 16, 16),
        ),
        extent: const Rect.fromLTWH(-4, -4, 32, 32),
        paper: const Rect.fromLTWH(0, 0, 16, 16),
      );
      addTearDown(out.dispose);
      final bytes = await bytesOf(tester, out);
      expect(
        [for (final x in [7, 8, 39, 40]) alphaAt(bytes, 64, x, 20)],
        [0, 255, 255, 0],
      );
      expect(
        [for (final y in [7, 8, 39, 40]) alphaAt(bytes, 64, 20, y)],
        [0, 255, 255, 0],
      );
    });

    testWidgets('a raster reaching past the paper repeats the paper\'s edge, '
        'not its own', (tester) async {
      // The editing view's usual raster: the page's ink, and round it a
      // pasteboard with nothing on it.
      final source = picture(48, 48, ink: const Rect.fromLTWH(8, 8, 32, 32));
      addTearDown(source.dispose);
      final out = steppedForChain(
        image: source,
        plan: resolveCompositeEffectPlan(
          [gaussian(repeats: true)],
          paper: const Rect.fromLTWH(0, 0, 32, 32),
        ),
        extent: const Rect.fromLTWH(-8, -8, 48, 48),
        paper: const Rect.fromLTWH(0, 0, 32, 32),
      );
      addTearDown(out.dispose);
      final bytes = await bytesOf(tester, out);
      expect(
        [
          for (final (x, y) in [(8, 8), (8, 24), (39, 39)])
            alphaAt(bytes, 48, x, y),
        ],
        everyElement(255),
        reason: 'the paper\'s edge held, not faded into the empty pasteboard',
      );
      expect(alphaAt(bytes, 48, 7, 24), 0, reason: 'past the paper');
    });

    testWidgets('a paper reaching past the raster is cut to the raster — '
        'what lies past it is out of sight, and nothing is made for it', (
      tester,
    ) async {
      final source = picture(48, 48);
      addTearDown(source.dispose);
      final out = steppedForChain(
        image: source,
        plan: resolveCompositeEffectPlan(
          [gaussian(repeats: true)],
          paper: const Rect.fromLTWH(0, 0, 100, 100),
        ),
        extent: const Rect.fromLTWH(-8, -8, 48, 48),
        paper: const Rect.fromLTWH(0, 0, 100, 100),
      );
      addTearDown(out.dispose);
      final bytes = await bytesOf(tester, out);
      expect(
        [
          for (final (x, y) in [(47, 24), (24, 47), (47, 47)])
            alphaAt(bytes, 48, x, y),
        ],
        everyElement(255),
        reason: 'the raster\'s edge held where the paper goes on past it',
      );
      expect(alphaAt(bytes, 48, 7, 24), 0, reason: 'past the paper');
    });

    testWidgets('what follows it in its step comes after it, on the paper '
        'alone', (tester) async {
      final source = picture(48, 48);
      addTearDown(source.dispose);
      final plan = resolveCompositeEffectPlan([
        gaussian(repeats: true),
        ResolvedLayerEffect(
          kind: EffectKind.brightnessContrast,
          values: const [-50, 0],
        ),
        // A key that finds nothing to take — it only closes the step.
        ResolvedLayerEffect(
          kind: EffectKind.colorKey,
          values: const [0, 0xFF000000, 0, 100],
        ),
      ], paper: const Rect.fromLTWH(0, 0, 32, 32));
      expect(
        plan.preSteps.first.lead,
        isA<PaperEdgeEffect>(),
        reason: '⛔전제',
      );
      expect(plan.preSteps.first.then, isNotEmpty, reason: '⛔전제');
      final out = steppedForChain(
        image: source,
        plan: plan,
        extent: const Rect.fromLTWH(-8, -8, 48, 48),
        paper: const Rect.fromLTWH(0, 0, 32, 32),
      );
      addTearDown(out.dispose);
      final bytes = await bytesOf(tester, out);
      const corner = (8 * 48 + 8) * 4;
      expect(bytes[corner + 3], 255);
      expect(bytes[corner], lessThan(255), reason: 'darkened after it');
      expect(
        bytes.sublist(corner, corner + 4),
        bytes.sublist((24 * 48 + 24) * 4, (24 * 48 + 24) * 4 + 4),
        reason: 'the corner as the middle: the edge held, then darkened',
      );
      expect(alphaAt(bytes, 48, 4, 24), 0, reason: 'past the paper');
    });
  });
}
