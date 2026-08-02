import 'dart:math' as math;
import 'dart:typed_data';

import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/native/qa_engine_abi.dart';
import 'package:anicel/src/native/qa_native_engine.dart';
import 'package:anicel/src/services/canvas_selection.dart';
import 'package:anicel/src/services/resample/resample_kernel.dart';
import 'package:anicel/src/services/resample/selection_resample.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/native_engine_path.dart';

/// Byte parity for the shared resampler.
///
/// The Dart reference is the definition and the C kernel is a mirror of it,
/// so "close enough" is not a passing grade: a single least-significant bit
/// of drift means an image resampled on a machine with the engine loaded
/// differs from the same image resampled without it, and the app is
/// supposed to fall back to Dart silently.
///
/// The failure mode this suite exists for has a precedent — #614, where
/// clang fused a multiply-add on Apple silicon and rounded once where Dart
/// rounded twice, producing 182 against the reference's 181. That is why
/// `-ffp-contract=off` has to be set in the CMake flags AND the Apple
/// podspec, and why this runs on every platform rather than just the one
/// the kernel was written on.
Uint8List _fixture(int width, int height, int seed) {
  final bytes = Uint8List(width * height * 4);
  final words = Uint32List.view(bytes.buffer);
  final random = math.Random(seed);
  // A palette rather than noise: line art is flat regions with hard edges,
  // and a random-per-pixel image would hide a footprint bug behind mush.
  const palette = <int>[
    0xffffffff,
    0xff101010,
    0xffc8dcf0,
    0xff604040,
    0x80305090,
    0x00000000,
  ];
  for (var i = 0; i < words.length; i += 1) {
    words[i] = palette[0];
  }
  for (var blob = 0; blob < 26; blob += 1) {
    final token = palette[random.nextInt(palette.length)];
    final left = random.nextInt(width);
    final top = random.nextInt(height);
    final w = 1 + random.nextInt(width ~/ 3);
    final h = 1 + random.nextInt(height ~/ 3);
    for (var y = top; y < math.min(top + h, height); y += 1) {
      for (var x = left; x < math.min(left + w, width); x += 1) {
        words[y * width + x] = token;
      }
    }
  }
  // Hairlines at odd angles, where the footprint maths actually bites.
  for (var x = 0; x < width; x += 1) {
    words[((x * 5 ~/ 3) % height) * width + x] = palette[1];
  }
  return bytes;
}

Float64List _inverseOf(ResampleTransform t) =>
    Float64List.fromList(<double>[t.a, t.b, t.c, t.d, t.e, t.f, t.g, t.h, t.i]);

ResampleTransform _rotationAbout(double degrees, double cx, double cy) {
  final theta = -degrees * math.pi / 180;
  final cos = math.cos(theta), sin = math.sin(theta);
  return ResampleTransform(
    a: cos,
    b: -sin,
    c: cx - cos * cx + sin * cy,
    d: sin,
    e: cos,
    f: cy - sin * cx - cos * cy,
  );
}

void main() {
  final libraryPath = nativeEngineLibraryPathOrNull();
  if (libraryPath == null) {
    if (nativeEngineRequired) {
      test('native engine is required but was not found', () {
        fail(nativeEngineMissingSkipReason);
      });
      return;
    }
    test('resample parity', () {}, skip: nativeEngineMissingSkipReason);
    return;
  }

  late QaNativeEngine engine;

  setUpAll(() {
    debugQaEngineLibraryPathOverride = libraryPath;
    QaNativeEngine.debugResetForTests();
    final loaded = QaNativeEngine.instance;
    expect(
      loaded,
      isNotNull,
      reason:
          'the engine at $libraryPath did not load — an ABI mismatch '
          'after a bump is the usual cause; rebuild the standalone binary',
    );
    engine = loaded!;
  });

  tearDownAll(() {
    debugQaEngineLibraryPathOverride = null;
    QaNativeEngine.debugResetForTests();
  });

  const width = 73;
  const height = 61;

  final transforms = <String, ResampleTransform>{
    'identity': ResampleTransform.identity(),
    'integer translation': ResampleTransform(
      a: 1,
      b: 0,
      c: -9,
      d: 0,
      e: 1,
      f: 4,
    ),
    'sub-pixel translation': ResampleTransform(
      a: 1,
      b: 0,
      c: -0.37,
      d: 0,
      e: 1,
      f: 0.62,
    ),
    'rotate 15': _rotationAbout(15, width / 2, height / 2),
    'rotate 37.4': _rotationAbout(37.4, width / 2, height / 2),
    'shrink 0.37': ResampleTransform.scaleTranslate(scale: 0.37),
    'shrink 0.8': ResampleTransform.scaleTranslate(scale: 0.8),
    'enlarge 2.5': ResampleTransform.scaleTranslate(scale: 2.5),
    'non-uniform': ResampleTransform(
      a: 1 / 0.6,
      b: 0,
      c: 0,
      d: 0,
      e: 1 / 1.3,
      f: 0,
    ),
    'shear': ResampleTransform(a: 1, b: 0.31, c: -4, d: 0.11, e: 1, f: -2),
    'perspective': ResampleTransform(
      a: 1,
      b: 0.12,
      c: -3,
      d: 0.05,
      e: 1,
      f: -2,
      g: 0.0012,
      h: 0.0007,
      i: 1,
    ),
    // P3a: matrices produced by the SELECTION TRANSFORM's own folds rather
    // than written by hand. Every case above is a literal, so none of them
    // exercises the arithmetic the tool actually feeds the kernel — and a
    // fold that lands a half pixel off would still be perfectly consistent
    // between the two implementations, so parity alone cannot catch it.
    // What these DO catch is the shape of the numbers the folds produce:
    // an offset built from a pivot and an AABB origin has a much larger
    // magnitude than the tidy literals above, which is where a float that
    // rounds differently on one side would show.
    'selection: rotate 21, non-uniform, off-origin AABB':
        selectionAffineResampleTransform(
          affine: SelectionAffine(
            pivot: CanvasPoint(x: width / 2, y: height / 2),
            sx: 1.3,
            sy: 0.8,
            rotationDegrees: 21,
            tx: 2.5,
            ty: -1.25,
          ),
          srcLeft: 12.5,
          srcTop: -7.25,
          outLeft: -6,
          outTop: 9,
        ),
    'selection: negative scale (a flipped box)':
        selectionAffineResampleTransform(
          affine: SelectionAffine(
            pivot: CanvasPoint(x: width / 2, y: height / 2),
            sx: -1.1,
            sy: 0.7,
            rotationDegrees: -47,
          ),
          srcLeft: 0,
          srcTop: 0,
          outLeft: -12,
          outTop: -8,
        ),
    'selection: perspective quad': selectionQuadResampleTransform(
      h: solveHomography(
        <CanvasPoint>[
          CanvasPoint(x: 6, y: 2),
          CanvasPoint(x: 64, y: 9),
          CanvasPoint(x: 71, y: 58),
          CanvasPoint(x: -3, y: 49),
        ],
        <CanvasPoint>[
          CanvasPoint(x: 0, y: 0),
          CanvasPoint(x: width.toDouble(), y: 0),
          CanvasPoint(x: width.toDouble(), y: height.toDouble()),
          CanvasPoint(x: 0, y: height.toDouble()),
        ],
      )!,
      srcLeft: 0,
      srcTop: 0,
      outLeft: -3,
      outTop: 2,
    ),
    'selection: one mesh triangle': selectionTriangleResampleTransform(
      d0: CanvasPoint(x: 2, y: 3),
      d1: CanvasPoint(x: 40, y: -4),
      d2: CanvasPoint(x: 9, y: 44),
      s0: CanvasPoint(x: 0, y: 0),
      s1: CanvasPoint(x: 36, y: 0),
      s2: CanvasPoint(x: 0, y: 30),
      // The cross product the rasteriser hands in, computed the same way.
      denominator: (40 - 2) * (44 - 3) - (9 - 2) * (-4 - 3),
      left: -1,
      top: -4,
      srcLeft: 0,
      srcTop: 0,
    ),
    // A quad steep enough that w falls to 0.06 across the frame. The gentle
    // case above never leaves the radius floor, so it could not have caught
    // either the cost blow-up or the int32 divergence at the ceiling.
    'steep perspective': ResampleTransform(
      a: 1,
      b: 0,
      c: 0,
      d: 0,
      e: 1,
      f: 0,
      g: 0,
      h: -0.94 / 61,
      i: 1,
    ),
    // P3e. Pick refines a TIED vote by re-sampling ONCE at twice the rate.
    // The cases above enter that loop only incidentally; these two enter
    // it by construction, on the axis-aligned hairline geometry the mode
    // exists for. An axis-aligned 0.7× splits a one-pixel line 0.5/0.2
    // across two destination rows, so the row holding 0.5 ties at every
    // rate and runs the refinement to its cap; 0.55× ties at the first
    // rate and is decided by the second.
    //
    // ⚠️ `scaleTranslate` takes the FORWARD scale and inverts it. These
    // said `1 / 0.7` once, which is a 1.43× magnification — it ties
    // nothing, reaches round two on zero pixels, and made the pair a pure
    // decoration of the comment above it.
    'tie: axis-aligned 0.7': ResampleTransform.scaleTranslate(scale: 0.7),
    'tie: axis-aligned 0.55': ResampleTransform.scaleTranslate(scale: 0.55),
    // Strong anisotropy WITH rotation: 5:1 across against 2× down. The
    // rate is per axis for exactly this shape — read from the area the two
    // multiply to, it comes out at 2.5 and undersamples the long axis by a
    // factor of three.
    'anisotropic 5:1 rotated 23': ResampleTransform(
      a: 5 * math.cos(23 * math.pi / 180),
      b: 5 * math.sin(23 * math.pi / 180),
      c: -11,
      d: -0.5 * math.sin(23 * math.pi / 180),
      e: 0.5 * math.cos(23 * math.pi / 180),
      f: 6,
    ),
    // Past int32. A C kernel that narrowed the offset would wrap this into
    // a small shift and copy real pixels where the reference copies none.
    'huge translation': ResampleTransform(
      a: 1,
      b: 0,
      c: 4294967296.0,
      d: 0,
      e: 1,
      f: 0,
    ),
    // Degenerate maps: both kernels must declare the pixel outside rather
    // than one throwing and the other returning success.
    'scale zero': ResampleTransform.scaleTranslate(scale: 0),
    'infinite a': ResampleTransform(
      a: double.infinity,
      b: 0,
      c: 0,
      d: 0,
      e: 1,
      f: 0,
    ),
    'NaN offset': ResampleTransform(
      a: 1,
      b: 0,
      c: double.nan,
      d: 0,
      e: 1,
      f: 0,
    ),
    'infinite offset': ResampleTransform(
      a: 1,
      b: 0,
      c: double.infinity,
      d: 0,
      e: 1,
      f: 0,
    ),
  };

  for (final mode in ResampleMode.values) {
    for (final entry in transforms.entries) {
      test('native matches the reference: ${entry.key} / ${mode.name}', () {
        final source = _fixture(width, height, 7);
        final expected = resampleRgbaReference(
          src: source,
          srcWidth: width,
          srcHeight: height,
          dstWidth: width,
          dstHeight: height,
          transform: entry.value,
          mode: mode,
        );
        final actual = engine.resampleRgbaBytes(
          src: source,
          srcWidth: width,
          srcHeight: height,
          dstWidth: width,
          dstHeight: height,
          inverse: _inverseOf(entry.value),
          radiusFloor: resampleRadiusFloor(mode),
          mode: mode == ResampleMode.pick ? 1 : 0,
        );
        expect(actual, isNotNull, reason: 'the kernel refused its arguments');
        expect(actual, expected);
      });
    }
  }

  test('a reduction to a different destination size matches', () {
    final source = _fixture(width, height, 11);
    const scale = 0.37;
    const outWidth = 27;
    const outHeight = 22;
    final transform = ResampleTransform.scaleTranslate(scale: scale);
    for (final mode in ResampleMode.values) {
      final expected = resampleRgbaReference(
        src: source,
        srcWidth: width,
        srcHeight: height,
        dstWidth: outWidth,
        dstHeight: outHeight,
        transform: transform,
        mode: mode,
      );
      final actual = engine.resampleRgbaBytes(
        src: source,
        srcWidth: width,
        srcHeight: height,
        dstWidth: outWidth,
        dstHeight: outHeight,
        inverse: _inverseOf(transform),
        radiusFloor: resampleRadiusFloor(mode),
        mode: mode == ResampleMode.pick ? 1 : 0,
      );
      expect(actual, expected, reason: '$mode drifted on a reduction');
    }
  });

  test('a destination taller than one band still matches', () {
    // The pooled split hands out 16 rows at a time, so a destination taller
    // than that is the case where a band boundary can be got wrong.
    const tallHeight = 51;
    final source = _fixture(width, height, 3);
    final transform = _rotationAbout(22.5, width / 2, height / 2);
    for (final mode in ResampleMode.values) {
      final expected = resampleRgbaReference(
        src: source,
        srcWidth: width,
        srcHeight: height,
        dstWidth: width,
        dstHeight: tallHeight,
        transform: transform,
        mode: mode,
      );
      final actual = engine.resampleRgbaBytes(
        src: source,
        srcWidth: width,
        srcHeight: height,
        dstWidth: width,
        dstHeight: tallHeight,
        inverse: _inverseOf(transform),
        radiusFloor: resampleRadiusFloor(mode),
        mode: mode == ResampleMode.pick ? 1 : 0,
      );
      expect(actual, expected, reason: '$mode differed across band bounds');
    }
  });

  test('a crowded footprint elects the same token in both kernels', () {
    // More distinct colours than the vote table has slots, so the eviction
    // policy and its re-weigh run. Without this the overflow branch is
    // dead code as far as the parity suite is concerned.
    const size = 64;
    final crowded = Uint8List(size * size * 4);
    final crowdedWords = Uint32List.view(crowded.buffer);
    for (var i = 0; i < crowdedWords.length; i += 1) {
      crowdedWords[i] = 0xff0000ff;
    }
    for (var i = 0; i < 20; i += 1) {
      crowdedWords[4 * size + (4 + i)] = 0xff000000 | (i * 0x080808);
      crowdedWords[5 * size + (4 + i)] = 0xff000000 | (i * 0x040404);
    }
    final transform = ResampleTransform.scaleTranslate(scale: 1 / 8);
    for (final mode in ResampleMode.values) {
      final expected = resampleRgbaReference(
        src: crowded,
        srcWidth: size,
        srcHeight: size,
        dstWidth: 8,
        dstHeight: 8,
        transform: transform,
        mode: mode,
      );
      final actual = engine.resampleRgbaBytes(
        src: crowded,
        srcWidth: size,
        srcHeight: size,
        dstWidth: 8,
        dstHeight: 8,
        inverse: _inverseOf(transform),
        radiusFloor: resampleRadiusFloor(mode),
        mode: mode == ResampleMode.pick ? 1 : 0,
      );
      expect(actual, expected, reason: '$mode drifted on vote overflow');
    }
  });

  test('a radius floor the caller chose is honoured natively', () {
    // The suite otherwise always passes resampleRadiusFloor(mode), so a C
    // kernel that ignored the argument entirely would stay green.
    //
    // BLEND, deliberately. The floor is Blend's radius now and Pick
    // ignores whatever it is handed, so running this loop on Pick pinned
    // nothing at all — three identical buffers compared three times. On
    // Blend the reference at 2.5 differs from the reference at 1.0 by
    // thousands of bytes, so a native kernel that hard-coded 1.0 dies on
    // the first iteration past it.
    //
    // Pick's complementary contract — that its bytes do NOT move with the
    // floor — is pinned in the kernel suite, where it can be stated as an
    // equality rather than smuggled in as a parity check.
    final source = _fixture(width, height, 5);
    final transform = _rotationAbout(15, width / 2, height / 2);
    for (final floor in <double>[1.0, 2.5, 4.0]) {
      final expected = resampleRgbaReference(
        src: source,
        srcWidth: width,
        srcHeight: height,
        dstWidth: width,
        dstHeight: height,
        transform: transform,
        mode: ResampleMode.blend,
        radiusFloor: floor,
      );
      final actual = engine.resampleRgbaBytes(
        src: source,
        srcWidth: width,
        srcHeight: height,
        dstWidth: width,
        dstHeight: height,
        inverse: _inverseOf(transform),
        radiusFloor: floor,
        mode: 0,
      );
      expect(actual, expected, reason: 'floor $floor drifted');
    }
  });

  test('whole-pixel translation matches at a different destination size', () {
    // The fast path indexes the SOURCE stride while writing the
    // DESTINATION stride; with both sizes equal a swap of the two is
    // invisible.
    final source = _fixture(width, height, 13);
    final transform = ResampleTransform(a: 1, b: 0, c: -5, d: 0, e: 1, f: 3);
    for (final mode in ResampleMode.values) {
      final expected = resampleRgbaReference(
        src: source,
        srcWidth: width,
        srcHeight: height,
        dstWidth: 41,
        dstHeight: 29,
        transform: transform,
        mode: mode,
      );
      final actual = engine.resampleRgbaBytes(
        src: source,
        srcWidth: width,
        srcHeight: height,
        dstWidth: 41,
        dstHeight: 29,
        inverse: _inverseOf(transform),
        radiusFloor: resampleRadiusFloor(mode),
        mode: mode == ResampleMode.pick ? 1 : 0,
      );
      expect(actual, expected, reason: '$mode drifted on a resized copy');
    }
  });

  test('magnification is block replication in both kernels', () {
    const size = 21;
    final tiny = Uint8List(size * size * 4);
    final tinyWords = Uint32List.view(tiny.buffer);
    for (var i = 0; i < tinyWords.length; i += 1) {
      tinyWords[i] = 0xffffffff;
    }
    tinyWords[10 * size + 10] = 0xff101010;
    final transform = ResampleTransform.scaleTranslate(scale: 8);
    final expected = resampleRgbaReference(
      src: tiny,
      srcWidth: size,
      srcHeight: size,
      dstWidth: size * 8,
      dstHeight: size * 8,
      transform: transform,
      mode: ResampleMode.pick,
    );
    final actual = engine.resampleRgbaBytes(
      src: tiny,
      srcWidth: size,
      srcHeight: size,
      dstWidth: size * 8,
      dstHeight: size * 8,
      inverse: _inverseOf(transform),
      radiusFloor: resampleRadiusFloor(ResampleMode.pick),
      mode: 1,
    );
    expect(actual, expected);
    expect(
      Uint32List.view(actual!.buffer).where((t) => t == 0xff101010).length,
      64,
    );
  });

  test('bad arguments are refused rather than guessed at', () {
    final source = _fixture(8, 8, 1);
    final identity = _inverseOf(ResampleTransform.identity());
    expect(
      engine.resampleRgbaBytes(
        src: source,
        srcWidth: 8,
        srcHeight: 8,
        dstWidth: 8,
        dstHeight: 8,
        inverse: identity,
        radiusFloor: 1,
        mode: 7,
      ),
      isNull,
      reason: 'an unknown mode must not silently pick one',
    );
    expect(
      engine.resampleRgbaBytes(
        src: source,
        srcWidth: 8,
        srcHeight: 8,
        dstWidth: 8,
        dstHeight: 8,
        inverse: identity,
        radiusFloor: 0.5,
        mode: 0,
      ),
      isNull,
      reason: 'a floor below 1 would sample nothing',
    );
    expect(
      engine.resampleRgbaBytes(
        src: source,
        srcWidth: 8,
        srcHeight: 8,
        dstWidth: 8,
        dstHeight: 8,
        inverse: Float64List.fromList(<double>[1, 0, 0, 0, 1, 0]),
        radiusFloor: 1,
        mode: 0,
      ),
      isNull,
      reason:
          'a six-element inverse would leave malloc bytes as the '
          'homogeneous row',
    );
  });
}
