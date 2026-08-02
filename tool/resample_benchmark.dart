// Resample kernel benchmark (2-value preserving transform, P1).
//
// Measures the shared resampler on the shapes the app actually asks it for:
// a transform-tool rotation at 1:1, and the on-screen minifications the
// canvas performs when you zoom out. Both the native kernel and the Dart
// reference are timed, because the app runs the reference whenever the
// engine cannot be loaded and a "fast enough" claim has to name which one.
//
// The budget these numbers are measured against: a drag preview has to land
// inside 16.6 ms (60 fps), and the transform tool resamples the SELECTION
// bounding box rather than the whole canvas — so the canvas-sized rows here
// are the pessimistic end, not the expected one.
//
// Run with:
//   cmake -S packages/qa_native/src -B build/native_standalone
//   cmake --build build/native_standalone --config Release
//   dart run tool/resample_benchmark.dart
//
// Dev tool only: not imported by lib/ or test/ runtime code.
// ignore_for_file: avoid_print
import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:anicel/src/native/qa_engine_abi.dart';
import 'package:anicel/src/native/qa_native_engine.dart';
import 'package:anicel/src/services/resample/resample_kernel.dart';
import 'package:ffi/ffi.dart';

/// A stand-in for a production cel: mostly flat ground with hard-edged
/// strokes. The flat fraction matters — it is what the flat-support
/// early-out feeds on, and a noise image would understate the kernel by
/// removing it.
Uint8List _cel(int width, int height) {
  final bytes = Uint8List(width * height * 4);
  final words = Uint32List.view(bytes.buffer);
  const white = 0xffffffff;
  const ink = 0xff101010;
  const skin = 0xffc8dcf0;
  const cloth = 0xff604040;
  for (var i = 0; i < words.length; i += 1) {
    words[i] = white;
  }
  for (var y = height ~/ 4; y < height * 3 ~/ 4; y += 1) {
    for (var x = width ~/ 4; x < width * 3 ~/ 4; x += 1) {
      words[y * width + x] = (y < height ~/ 2) ? skin : cloth;
    }
  }
  for (var x = 0; x < width; x += 1) {
    words[((x * 7 ~/ 5) % height) * width + x] = ink;
    words[(height ~/ 2) * width + x] = ink;
  }
  for (var y = 0; y < height; y += 1) {
    words[y * width + (y * 3 ~/ 7) % width] = ink;
  }
  return bytes;
}

double _flatFraction(Uint8List bytes) {
  final words = Uint32List.view(bytes.buffer);
  var white = 0;
  for (final word in words) {
    if (word == 0xffffffff) white += 1;
  }
  return white / words.length;
}

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

String _ms(int microseconds) =>
    (microseconds / 1000).toStringAsFixed(2).padLeft(8);

int _best(int reps, void Function() body) {
  body(); // warm up
  var best = 1 << 62;
  for (var i = 0; i < reps; i += 1) {
    final watch = Stopwatch()..start();
    body();
    watch.stop();
    if (watch.elapsedMicroseconds < best) best = watch.elapsedMicroseconds;
  }
  return best;
}

String? _enginePath() {
  final override = Platform.environment['QA_ENGINE_PATH'];
  if (override != null && override.isNotEmpty && File(override).existsSync()) {
    return override;
  }
  final root = Directory.current.path;
  final candidates = <String>[
    if (Platform.isWindows)
      '$root\\build\\native_standalone\\Release\\qa_engine.dll',
    if (Platform.isMacOS) '$root/build/native_standalone/libqa_engine.dylib',
    if (Platform.isLinux) '$root/build/native_standalone/libqa_engine.so',
  ];
  for (final candidate in candidates) {
    if (File(candidate).existsSync()) return candidate;
  }
  return null;
}

class _Scenario {
  const _Scenario(this.name, this.transform, this.dstWidth, this.dstHeight);
  final String name;
  final ResampleTransform transform;
  final int dstWidth;
  final int dstHeight;
}

void main() {
  const width = 2150;
  const height = 1518;
  final source = _cel(width, height);
  print('source ${width}x$height '
      '(${(width * height / 1e6).toStringAsFixed(2)} Mpx), '
      'flat ${(_flatFraction(source) * 100).toStringAsFixed(1)}%');

  final enginePath = _enginePath();
  if (enginePath == null) {
    print('\nNO NATIVE ENGINE — Dart reference only. Build it with:');
    print('  cmake -S packages/qa_native/src -B build/native_standalone && '
        'cmake --build build/native_standalone --config Release');
  } else {
    debugQaEngineLibraryPathOverride = enginePath;
    QaNativeEngine.debugResetForTests();
  }
  final engine = QaNativeEngine.instance;
  if (enginePath != null && engine == null) {
    print('\nENGINE FOUND BUT REFUSED (ABI mismatch?): $enginePath');
  }

  final scenarios = <_Scenario>[
    _Scenario(
      'transform: rotate 15 at 1:1',
      _rotationAbout(15, width / 2, height / 2),
      width,
      height,
    ),
    _Scenario(
      'screen: minify to 50%',
      ResampleTransform.scaleTranslate(scale: 0.5),
      (width * 0.5).round(),
      (height * 0.5).round(),
    ),
    _Scenario(
      'screen: minify to 25%',
      ResampleTransform.scaleTranslate(scale: 0.25),
      (width * 0.25).round(),
      (height * 0.25).round(),
    ),
    _Scenario(
      'screen: minify to 10% (r=10, the tap blow-up)',
      ResampleTransform.scaleTranslate(scale: 0.1),
      (width * 0.1).round(),
      (height * 0.1).round(),
    ),
  ];

  const reps = 3;
  for (final scenario in scenarios) {
    print('\n--- ${scenario.name} '
        '(out ${scenario.dstWidth}x${scenario.dstHeight}) ---');
    for (final mode in ResampleMode.values) {
      final dartTime = _best(reps, () {
        resampleRgbaReference(
          src: source,
          srcWidth: width,
          srcHeight: height,
          dstWidth: scenario.dstWidth,
          dstHeight: scenario.dstHeight,
          transform: scenario.transform,
          mode: mode,
        );
      });
      var line = '  ${mode.name.padRight(6)} dart ${_ms(dartTime)} ms';

      if (engine != null) {
        final t = scenario.transform;
        final srcNative = malloc<Uint8>(source.length);
        final dstNative =
            malloc<Uint8>(scenario.dstWidth * scenario.dstHeight * 4);
        final inverse = malloc<Double>(9);
        try {
          srcNative.asTypedList(source.length).setAll(0, source);
          inverse.asTypedList(9).setAll(
            0,
            <double>[t.a, t.b, t.c, t.d, t.e, t.f, t.g, t.h, t.i],
          );
          final nativeTime = _best(reps, () {
            engine.resampleRgba(
              src: srcNative,
              srcWidth: width,
              srcHeight: height,
              dst: dstNative,
              dstWidth: scenario.dstWidth,
              dstHeight: scenario.dstHeight,
              inverse: inverse,
              radiusFloor: resampleRadiusFloor(mode),
              mode: mode == ResampleMode.pick ? 1 : 0,
            );
          });
          line += '   native ${_ms(nativeTime)} ms'
              '   x${(dartTime / nativeTime).toStringAsFixed(1)}';
        } finally {
          malloc.free(srcNative);
          malloc.free(dstNative);
          malloc.free(inverse);
        }
      }
      print(line);
    }
  }

  print('\nnote: the transform tool resamples the selection bbox, not the '
      'whole canvas — on the reference cel the ink bounds are about a tenth '
      'of the frame, so divide the rotation row accordingly.');
}
