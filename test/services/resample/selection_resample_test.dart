import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_stamp_image.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/native/qa_engine_abi.dart';
import 'package:anicel/src/native/qa_native_engine.dart';
import 'package:anicel/src/services/canvas_selection.dart';
import 'package:anicel/src/services/resample/resample_kernel.dart';
import 'package:anicel/src/services/resample/selection_resample.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/native_engine_path.dart';

/// The folds that carry the transform tool's geometry into the shared
/// resampler.
///
/// These are the tests that catch the failure the swap is most exposed to:
/// a fold that is off by half a pixel, or by the sign of one sine, produces
/// a picture that looks entirely plausible and is simply in the wrong
/// place. Nothing downstream notices — the AABB is right, the alpha is
/// right, the colours are right. So the oracle here is not "does it look
/// like a transform", it is "does it agree, to floating-point noise, with
/// the arithmetic the tool has always used".
void main() {
  /// The kernel's destination-index → source-index map, evaluated the way
  /// the kernel evaluates it (`resample_kernel.dart`).
  ({double u, double v}) kernelSample(ResampleTransform t, int ox, int oy) {
    final x = ox + 0.5;
    final y = oy + 0.5;
    if (t.isAffine) {
      return (
        u: t.a * x + t.b * y + t.c - 0.5,
        v: t.d * x + t.e * y + t.f - 0.5,
      );
    }
    final w = t.g * x + t.h * y + t.i;
    return (
      u: (t.a * x + t.b * y + t.c) / w - 0.5,
      v: (t.d * x + t.e * y + t.f) / w - 0.5,
    );
  }

  group('affine fold', () {
    test('agrees with the tool\'s own inverse over random parameters', () {
      final random = math.Random(20260802);
      var worst = 0.0;
      for (var trial = 0; trial < 400; trial += 1) {
        final pivot = CanvasPoint(
          x: random.nextDouble() * 400 - 200,
          y: random.nextDouble() * 400 - 200,
        );
        // Negative scales are reachable: dragging a corner handle past its
        // opposite flips the box and the clamp preserves the sign.
        final sx = (random.nextDouble() * 4 - 2).clamp(-2.0, 2.0);
        final sy = (random.nextDouble() * 4 - 2).clamp(-2.0, 2.0);
        if (sx.abs() < 0.05 || sy.abs() < 0.05) {
          continue;
        }
        final affine = SelectionAffine(
          pivot: pivot,
          sx: sx,
          sy: sy,
          rotationDegrees: random.nextDouble() * 720 - 360,
          tx: random.nextDouble() * 200 - 100,
          ty: random.nextDouble() * 200 - 100,
        );
        final srcLeft = random.nextDouble() * 200 - 100;
        final srcTop = random.nextDouble() * 200 - 100;
        final outLeft = random.nextInt(400) - 200;
        final outTop = random.nextInt(400) - 200;
        final folded = selectionAffineResampleTransform(
          affine: affine,
          srcLeft: srcLeft,
          srcTop: srcTop,
          outLeft: outLeft,
          outTop: outTop,
        );

        final cos = affine.cosTheta;
        final sin = affine.sinTheta;
        final invSx = 1 / affine.sx;
        final invSy = 1 / affine.sy;
        for (var i = 0; i < 5; i += 1) {
          final ox = random.nextInt(64);
          final oy = random.nextInt(64);
          // The pre-P3a arithmetic, verbatim: canvas-space inverse, then
          // the sampler's own origin and half-pixel shift.
          final qx = outLeft + ox + 0.5 - affine.pivot.x - affine.tx;
          final qy = outTop + oy + 0.5 - affine.pivot.y - affine.ty;
          final px = (qx * cos + qy * sin) * invSx + affine.pivot.x;
          final py = (-qx * sin + qy * cos) * invSy + affine.pivot.y;
          final expectedU = px - srcLeft - 0.5;
          final expectedV = py - srcTop - 0.5;
          final got = kernelSample(folded, ox, oy);
          worst = math.max(worst, (got.u - expectedU).abs());
          worst = math.max(worst, (got.v - expectedV).abs());
        }
      }
      // A sign flip on b/d costs ~1.8 px and dropping the inverse scale
      // from the offset bracket ~0.9 px, so this bound is four orders of
      // magnitude below either mistake.
      expect(worst, lessThan(1e-6));
    });

    test('a quarter turn is EXACT, not merely close', () {
      // math.cos(pi/2) is 6.1e-17. Left alone it moves every destination
      // pixel centre a hair off its source pixel centre, and "rotating by
      // 90 degrees returns the same pixels" stops being a guarantee and
      // becomes a rounding accident.
      for (final degrees in <double>[0, 90, 180, 270, 360, -90, 450]) {
        final affine = SelectionAffine(
          pivot: CanvasPoint(x: 8, y: 8),
          rotationDegrees: degrees,
        );
        expect(affine.cosTheta.abs(), anyOf(0.0, 1.0), reason: '$degrees');
        expect(affine.sinTheta.abs(), anyOf(0.0, 1.0), reason: '$degrees');
        final folded = selectionAffineResampleTransform(
          affine: affine,
          srcLeft: 4,
          srcTop: 4,
          outLeft: 4,
          outTop: 4,
        );
        for (final value in <double>[folded.a, folded.b, folded.d, folded.e]) {
          expect(value.abs(), anyOf(0.0, 1.0), reason: '$degrees');
        }
        // Whole-number offsets: the fold lands on the source lattice.
        expect(folded.c, folded.c.roundToDouble(), reason: '$degrees');
        expect(folded.f, folded.f.roundToDouble(), reason: '$degrees');
      }
      // 89.999 is NOT a quarter turn and must go through libm untouched.
      final near = SelectionAffine(
        pivot: CanvasPoint(x: 8, y: 8),
        rotationDegrees: 89.999,
      );
      expect(near.cosTheta, isNot(0.0));
    });
  });

  group('quad fold', () {
    test('agrees with the tool\'s own homography evaluation', () {
      final random = math.Random(7788);
      var worst = 0.0;
      for (var trial = 0; trial < 300; trial += 1) {
        final srcLeft = random.nextDouble() * 100 - 50;
        final srcTop = random.nextDouble() * 100 - 50;
        const width = 32.0;
        const height = 24.0;
        final base = <CanvasPoint>[
          CanvasPoint(x: srcLeft, y: srcTop),
          CanvasPoint(x: srcLeft + width, y: srcTop),
          CanvasPoint(x: srcLeft + width, y: srcTop + height),
          CanvasPoint(x: srcLeft, y: srcTop + height),
        ];
        // Jitter every corner independently: that is what makes it a
        // perspective quad rather than an affine one.
        final corners = <CanvasPoint>[
          for (final point in base)
            CanvasPoint(
              x: point.x + random.nextDouble() * 20 - 10,
              y: point.y + random.nextDouble() * 20 - 10,
            ),
        ];
        final h = solveHomography(corners, base);
        if (h == null) {
          continue;
        }
        final outLeft = random.nextInt(100) - 50;
        final outTop = random.nextInt(100) - 50;
        final folded = selectionQuadResampleTransform(
          h: h,
          srcLeft: srcLeft,
          srcTop: srcTop,
          outLeft: outLeft,
          outTop: outTop,
        );
        for (var i = 0; i < 5; i += 1) {
          final ox = random.nextInt(48);
          final oy = random.nextInt(48);
          final qx = outLeft + ox + 0.5;
          final qy = outTop + oy + 0.5;
          final w = h[6] * qx + h[7] * qy + h[8];
          if (w.abs() < 1e-6) {
            continue;
          }
          final px = (h[0] * qx + h[1] * qy + h[2]) / w;
          final py = (h[3] * qx + h[4] * qy + h[5]) / w;
          final got = kernelSample(folded, ox, oy);
          worst = math.max(worst, (got.u - (px - srcLeft - 0.5)).abs());
          worst = math.max(worst, (got.v - (py - srcTop - 0.5)).abs());
        }
      }
      expect(worst, lessThan(1e-6));
    });

    test('the fold introduces no perspective of its own', () {
      // Handed an exactly affine map, the fold must leave i exactly 1 —
      // not 0.9999, which would move a perspective-free warp onto the
      // divide path and change its rounding.
      final h = Float64List.fromList(<double>[2, 0, 5, 0, 3, -7, 0, 0, 1]);
      final folded = selectionQuadResampleTransform(
        h: h,
        srcLeft: 1.5,
        srcTop: -2.5,
        outLeft: 9,
        outTop: -4,
      );
      expect(folded.isAffine, isTrue);
      expect(folded.i, 1.0);
    });

    test('a quad the user dragged flat is NOT exactly affine, which is why '
        'the pure-translation case needs its own short circuit', () {
      // solveHomography runs partial-pivot Gaussian elimination, and even
      // a plain scale-and-move quad comes back with ~1e-17 in the
      // perspective row. Downstream that is harmless (the kernel just
      // takes its divide path), but it does mean the kernel's own
      // whole-pixel-translation circuit can never fire on this path —
      // hence the explicit common-delta check in transformStampDabQuad.
      final base = <CanvasPoint>[
        CanvasPoint(x: 0, y: 0),
        CanvasPoint(x: 10, y: 0),
        CanvasPoint(x: 10, y: 10),
        CanvasPoint(x: 0, y: 10),
      ];
      final corners = <CanvasPoint>[
        CanvasPoint(x: 2, y: 3),
        CanvasPoint(x: 22, y: 3),
        CanvasPoint(x: 22, y: 23),
        CanvasPoint(x: 2, y: 23),
      ];
      final h = solveHomography(corners, base)!;
      final folded = selectionQuadResampleTransform(
        h: h,
        srcLeft: 0,
        srcTop: 0,
        outLeft: 2,
        outTop: 3,
      );
      expect(folded.i, closeTo(1, 1e-9));
      expect(folded.g.abs(), lessThan(1e-9));
      expect(folded.h.abs(), lessThan(1e-9));
    });
  });

  group('triangle fold', () {
    test('reproduces barycentric interpolation exactly', () {
      final random = math.Random(31337);
      var worst = 0.0;
      for (var trial = 0; trial < 300; trial += 1) {
        CanvasPoint point() => CanvasPoint(
          x: random.nextDouble() * 60 - 30,
          y: random.nextDouble() * 60 - 30,
        );
        final d0 = point(), d1 = point(), d2 = point();
        final s0 = point(), s1 = point(), s2 = point();
        final denominator =
            (d1.x - d0.x) * (d2.y - d0.y) - (d2.x - d0.x) * (d1.y - d0.y);
        if (denominator.abs() < 1) {
          continue; // Near-degenerate: the tool refuses these too.
        }
        final left = random.nextInt(40) - 20;
        final top = random.nextInt(40) - 20;
        const srcLeft = 3.5;
        const srcTop = -2.25;
        final folded = selectionTriangleResampleTransform(
          d0: d0,
          d1: d1,
          d2: d2,
          s0: s0,
          s1: s1,
          s2: s2,
          denominator: denominator,
          left: left,
          top: top,
          srcLeft: srcLeft,
          srcTop: srcTop,
        );
        for (var i = 0; i < 5; i += 1) {
          final ox = random.nextInt(20);
          final oy = random.nextInt(20);
          final qx = left + ox + 0.5;
          final qy = top + oy + 0.5;
          // The rasteriser's own barycentric interpolation, verbatim.
          final w1 =
              ((qx - d0.x) * (d2.y - d0.y) - (d2.x - d0.x) * (qy - d0.y)) /
              denominator;
          final w2 =
              ((d1.x - d0.x) * (qy - d0.y) - (qx - d0.x) * (d1.y - d0.y)) /
              denominator;
          final w0 = 1.0 - w1 - w2;
          final px = s0.x * w0 + s1.x * w1 + s2.x * w2;
          final py = s0.y * w0 + s1.y * w1 + s2.y * w2;
          final got = kernelSample(folded, ox, oy);
          worst = math.max(worst, (got.u - (px - srcLeft - 0.5)).abs());
          worst = math.max(worst, (got.v - (py - srcTop - 0.5)).abs());
        }
      }
      expect(worst, lessThan(1e-6));
    });
  });

  group('the crop invariant', () {
    test('resampling a sub-rect gives exactly the bytes cropping the whole '
        'result would', () {
      // This is what lets the preview resample only what is on screen
      // while the commit resamples everything, and still promises the two
      // agree. It is a property of the fold: the output origin enters the
      // matrix, so shifting it shifts the destination index by the same
      // amount and every pixel's source coordinate is unchanged.
      //
      // Without this pinned, "a clipped preview is a crop" is an argument
      // about arithmetic rather than a fact about the code, and the first
      // person to change how the offset is folded breaks it silently —
      // the preview would look right and Enter would land something
      // shifted.
      final source = Uint8List(64 * 64 * 4);
      final words = Uint32List.view(source.buffer);
      for (var i = 0; i < words.length; i += 1) {
        words[i] = 0xffffffff;
      }
      for (var i = 0; i < 64; i += 1) {
        words[i * 64 + i] = 0xff101010;
        words[i * 64 + 20] = 0xff3050a0;
        words[40 * 64 + i] = 0xff70b040;
      }

      final affine = SelectionAffine(
        pivot: CanvasPoint(x: 32, y: 32),
        sx: 1.7,
        sy: 0.9,
        rotationDegrees: 33,
        tx: 3.5,
        ty: -2.25,
      );
      const fullLeft = -20;
      const fullTop = -14;
      const fullWidth = 110;
      const fullHeight = 96;

      for (final mode in ResampleMode.values) {
        final whole = Uint8List(fullWidth * fullHeight * 4);
        resampleSelectionInto(
          src: source,
          srcWidth: 64,
          srcHeight: 64,
          dst: whole,
          dstWidth: fullWidth,
          dstHeight: fullHeight,
          transform: selectionAffineResampleTransform(
            affine: affine,
            srcLeft: 0,
            srcTop: 0,
            outLeft: fullLeft,
            outTop: fullTop,
          ),
          mode: mode,
        );

        // An off-centre window, so a sign error in the offset cannot pass
        // by symmetry.
        const cropLeft = fullLeft + 17;
        const cropTop = fullTop + 29;
        const cropWidth = 41;
        const cropHeight = 33;
        final crop = Uint8List(cropWidth * cropHeight * 4);
        resampleSelectionInto(
          src: source,
          srcWidth: 64,
          srcHeight: 64,
          dst: crop,
          dstWidth: cropWidth,
          dstHeight: cropHeight,
          transform: selectionAffineResampleTransform(
            affine: affine,
            srcLeft: 0,
            srcTop: 0,
            outLeft: cropLeft,
            outTop: cropTop,
          ),
          mode: mode,
        );

        final wholeWords = Uint32List.view(whole.buffer);
        final cropWords = Uint32List.view(crop.buffer);
        for (var y = 0; y < cropHeight; y += 1) {
          for (var x = 0; x < cropWidth; x += 1) {
            expect(
              cropWords[y * cropWidth + x],
              wholeWords[(y + cropTop - fullTop) * fullWidth +
                  x +
                  cropLeft -
                  fullLeft],
              reason: '${mode.name} disagreed at ($x,$y)',
            );
          }
        }
      }
    });

    test('the warp functions honour a clip the same way', () {
      final rgba = Uint8List(32 * 32 * 4);
      final words = Uint32List.view(rgba.buffer);
      for (var i = 0; i < words.length; i += 1) {
        words[i] = 0xffffffff;
      }
      for (var i = 0; i < 32; i += 1) {
        words[i * 32 + i] = 0xff101010;
      }
      final dab = BrushDab(
        center: CanvasPoint(x: 16, y: 16),
        color: 0xFFFFFFFF,
        size: 32,
        opacity: 1,
        flow: 1,
        hardness: 1,
        tipShape: BrushTipShape.square,
        pressure: 1,
        sequence: 0,
        stamp: BrushStampImage(id: 'clip', width: 32, height: 32, rgba: rgba),
      );
      final affine = SelectionAffine(
        pivot: CanvasPoint(x: 16, y: 16),
        rotationDegrees: 26,
        sx: 1.4,
        sy: 1.4,
      );
      final whole = transformStampDab(dab, affine, mode: ResampleMode.pick);
      final clip = Rect.fromLTRB(6, 4, 30, 27);
      final clipped = transformStampDab(
        dab,
        affine,
        mode: ResampleMode.pick,
        clip: clip,
      );

      final wholeStamp = whole.stamp!;
      final clippedStamp = clipped.stamp!;
      expect(
        clippedStamp.width * clippedStamp.height,
        lessThan(wholeStamp.width * wholeStamp.height),
        reason: 'the clip did not actually narrow anything',
      );
      final wholeLeft = (whole.center.x - wholeStamp.width / 2).round();
      final wholeTop = (whole.center.y - wholeStamp.height / 2).round();
      final clippedLeft = (clipped.center.x - clippedStamp.width / 2).round();
      final clippedTop = (clipped.center.y - clippedStamp.height / 2).round();
      final wholeWords = Uint32List.view(wholeStamp.rgba.buffer);
      final clippedWords = Uint32List.view(clippedStamp.rgba.buffer);
      for (var y = 0; y < clippedStamp.height; y += 1) {
        for (var x = 0; x < clippedStamp.width; x += 1) {
          expect(
            clippedWords[y * clippedStamp.width + x],
            wholeWords[(y + clippedTop - wholeTop) * wholeStamp.width +
                x +
                clippedLeft -
                wholeLeft],
            reason: 'clipped warp disagreed at ($x,$y)',
          );
        }
      }
    });
  });

  group('the router', () {
    test('native and the Dart reference produce the same bytes', () {
      // The whole point of routing through one function: which kernel ran
      // must be invisible in the result. Without the engine LOADED this
      // would compare the reference with itself and pass while proving
      // nothing, so the engine is wired here explicitly and the test skips
      // loudly when there is none to wire.
      final path = nativeEngineLibraryPathOrNull();
      if (path == null) {
        markTestSkipped(nativeEngineMissingSkipReason);
        expect(nativeEngineRequired, isFalse, reason: 'QA_REQUIRE_NATIVE=1');
        return;
      }
      debugQaEngineLibraryPathOverride = path;
      QaNativeEngine.debugResetForTests();
      addTearDown(() {
        debugQaEngineLibraryPathOverride = null;
        QaNativeEngine.debugResetForTests();
      });
      expect(
        QaNativeEngine.instance,
        isNotNull,
        reason: 'the engine at $path refused to load (ABI mismatch?)',
      );

      final source = Uint8List(32 * 32 * 4);
      final words = Uint32List.view(source.buffer);
      for (var i = 0; i < words.length; i += 1) {
        words[i] = 0xffffffff;
      }
      for (var i = 0; i < 32; i += 1) {
        words[i * 32 + i] = 0xff101010;
        words[i * 32 + 16] = 0xff3050a0;
      }
      final affine = SelectionAffine(
        pivot: CanvasPoint(x: 16, y: 16),
        sx: 1.3,
        sy: 0.8,
        rotationDegrees: 21,
        tx: 2.5,
        ty: -1.25,
      );
      final transform = selectionAffineResampleTransform(
        affine: affine,
        srcLeft: 0,
        srcTop: 0,
        outLeft: -4,
        outTop: -4,
      );
      for (final mode in ResampleMode.values) {
        final routed = Uint8List(40 * 40 * 4);
        resampleSelectionInto(
          src: source,
          srcWidth: 32,
          srcHeight: 32,
          dst: routed,
          dstWidth: 40,
          dstHeight: 40,
          transform: transform,
          mode: mode,
        );
        final reference = resampleRgbaReference(
          src: source,
          srcWidth: 32,
          srcHeight: 32,
          dstWidth: 40,
          dstHeight: 40,
          transform: transform,
          mode: mode,
          radiusFloor: kSelectionResampleRadiusFloor,
        );
        expect(routed, reference, reason: mode.name);
      }
    });

    test('the floor it passes matches the kernel default, and raising it '
        'would delete line art', () {
      // The floor is 1.0 for both modes now. It used to be 1.5 for Pick,
      // which stopped meaning anything when the weight became coverage: a
      // floor above the true extent claims the preimage reaches further
      // than it does, so the vote counts area the destination pixel never
      // covered. The second assertion is the guard — it fails the day
      // somebody reintroduces a wider ring as a "quality" knob.
      expect(kSelectionResampleRadiusFloor, 1.0);
      expect(resampleRadiusFloor(ResampleMode.pick), 1.0);
      expect(resampleRadiusFloor(ResampleMode.blend), 1.0);

      const size = 40;
      final source = Uint8List(size * size * 4);
      final words = Uint32List.view(source.buffer);
      const white = 0xffffffff;
      const ink = 0xff101010;
      for (var i = 0; i < words.length; i += 1) {
        words[i] = white;
      }
      for (var i = 4; i < size - 4; i += 1) {
        words[i * size + i] = ink; // 1px diagonal
        words[i * size + 20] = ink; // 1px vertical
      }
      final expected = words.where((word) => word == ink).length;

      final transform = selectionAffineResampleTransform(
        affine: SelectionAffine(
          pivot: CanvasPoint(x: size / 2, y: size / 2),
          rotationDegrees: 90,
        ),
        srcLeft: 0,
        srcTop: 0,
        outLeft: 0,
        outTop: 0,
      );
      int inkCount(double floor) {
        final out = resampleRgbaReference(
          src: source,
          srcWidth: size,
          srcHeight: size,
          dstWidth: size,
          dstHeight: size,
          transform: transform,
          mode: ResampleMode.pick,
          radiusFloor: floor,
        );
        return Uint32List.view(out.buffer).where((word) => word == ink).length;
      }

      expect(
        inkCount(kSelectionResampleRadiusFloor),
        expected,
        reason: 'a quarter turn must be an exact permutation',
      );
      expect(
        inkCount(1.5),
        lessThan(expected),
        reason: 'if this ever stops being true, the override is free to go',
      );
    });
  });
}
