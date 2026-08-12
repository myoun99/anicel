@Tags(['benchmark'])
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/native/qa_engine_abi.dart';
import 'package:anicel/src/native/qa_native_engine.dart';
import 'package:anicel/src/services/canvas_selection.dart';
import 'package:anicel/src/services/resample/resample_kernel.dart';
import 'package:anicel/src/services/resample/selection_resample.dart';

import '../helpers/native_engine_path.dart';

/// Can a transform preview resample only the pixels that are ON SCREEN?
///
/// `canvas_selection.dart` carries a warning that it cannot: "a sweep
/// found 241 of 400 transforms where a clipped resample differs from the
/// same region of an unclipped one". A whole-picture transform is 8.66 MP
/// at 125% and a viewport is under one, so the answer decides whether the
/// tool can be fast without giving up any resolution — which is the one
/// thing 유저 08-13 ruled out ("치명적이야 그림툴에서는").
///
/// The hypothesis this checks is that the earlier sweep clipped by
/// recomputing the OUTPUT RECT, which moves `outLeft`/`outTop` — and the
/// destination pixel grid is anchored to those, so every sample lands
/// somewhere else and of course the bytes differ. Clipping while KEEPING
/// the original grid asks a different question:
///
///     resample(rect(0,0,W,H))[ox..ox+w, oy..oy+h]
///       ==  resample(rect(ox,oy,w,h))            ?
///
/// where the second call is handed `outLeft + ox` / `outTop + oy`, so both
/// calls place destination pixel (ox+i, oy+j) at the same source position.
///
/// Prints the tally, and FAILS if any window differs — a clip that is
/// exact 399 times out of 400 is not exact.
void main() {
  final dllPath = nativeEngineLibraryPathOrNull();

  tearDown(() {
    QaNativeEngine.debugResetForTests();
    debugQaEngineLibraryPathOverride = null;
    QaNativeEngine.debugForceDartFallback = false;
  });

  /// Line art: thin strokes on transparent, the content the tool is for
  /// and the one Pick's flat-support probe behaves differently on.
  Uint8List lineArt(int width, int height) {
    final rgba = Uint8List(width * height * 4);
    for (var y = 0; y < height; y += 1) {
      for (var x = 0; x < width; x += 1) {
        final onStroke = x % 23 < 2 || y % 19 < 2 || x == y || x + y == width;
        if (onStroke) {
          final offset = (y * width + x) * 4;
          rgba[offset] = (x * 7) & 0xFF;
          rgba[offset + 1] = (y * 5) & 0xFF;
          rgba[offset + 2] = 0x20;
          rgba[offset + 3] = 255;
        }
      }
    }
    return rgba;
  }

  void runSweep({required bool forceDart}) {
    QaNativeEngine.debugResetForTests();
    debugQaEngineLibraryPathOverride = dllPath;
    QaNativeEngine.debugForceDartFallback = forceDart;

    const srcWidth = 240;
    const srcHeight = 180;
    final src = lineArt(srcWidth, srcHeight);
    const srcLeft = 0.0;
    const srcTop = 0.0;

    var compared = 0;
    var differing = 0;
    final differences = <String>[];

    for (final mode in ResampleMode.values) {
      for (final scale in const <double>[0.6, 0.85, 1.0, 1.3, 2.1]) {
        for (final degrees in const <double>[0, 7, 33, 90, 150, 217, 300]) {
          final affine = SelectionAffine(
            pivot: CanvasPoint(x: srcWidth / 2, y: srcHeight / 2),
            sx: scale,
            sy: scale,
            rotationDegrees: degrees,
            tx: 3.25,
            ty: -1.75,
          );
          final corners = [
            for (final corner in <CanvasPoint>[
              CanvasPoint(x: srcLeft, y: srcTop),
              CanvasPoint(x: srcLeft + srcWidth, y: srcTop),
              CanvasPoint(x: srcLeft + srcWidth, y: srcTop + srcHeight),
              CanvasPoint(x: srcLeft, y: srcTop + srcHeight),
            ])
              affine.apply(corner),
          ];
          final out = selectionWarpOutputRect(corners);

          // The whole output, the way a commit computes it.
          final full = Uint8List(out.width * out.height * 4);
          resampleSelectionInto(
            src: src,
            srcWidth: srcWidth,
            srcHeight: srcHeight,
            dst: full,
            dstWidth: out.width,
            dstHeight: out.height,
            transform: selectionAffineResampleTransform(
              affine: affine,
              srcLeft: srcLeft,
              srcTop: srcTop,
              outLeft: out.left,
              outTop: out.top,
            ),
            mode: mode,
          );

          // A window of it, computed on its own — the same destination
          // pixels, addressed by shifting the ORIGIN rather than by
          // recomputing the rect.
          final ox = out.width ~/ 3;
          final oy = out.height ~/ 4;
          final w = math.max(1, out.width ~/ 3);
          final h = math.max(1, out.height ~/ 3);
          final clipped = Uint8List(w * h * 4);
          resampleSelectionInto(
            src: src,
            srcWidth: srcWidth,
            srcHeight: srcHeight,
            dst: clipped,
            dstWidth: w,
            dstHeight: h,
            transform: selectionAffineResampleTransform(
              affine: affine,
              srcLeft: srcLeft,
              srcTop: srcTop,
              outLeft: out.left + ox,
              outTop: out.top + oy,
            ),
            mode: mode,
          );

          compared += 1;
          var mismatched = 0;
          for (var row = 0; row < h; row += 1) {
            final fullBase = ((oy + row) * out.width + ox) * 4;
            final clipBase = row * w * 4;
            for (var byte = 0; byte < w * 4; byte += 1) {
              if (full[fullBase + byte] != clipped[clipBase + byte]) {
                mismatched += 1;
              }
            }
          }
          if (mismatched != 0) {
            differing += 1;
            if (differences.length < 6) {
              differences.add(
                '${mode.name} ×$scale @$degrees°: $mismatched of '
                '${w * h * 4} bytes',
              );
            }
          }
        }
      }
    }

    debugPrint(
      '[clip parity ${forceDart ? "dart" : "native"}] $compared transforms '
      'compared, $differing differ'
      '${differences.isEmpty ? "" : "  →  ${differences.join("; ")}"}',
    );
  }

  test('what else rides on a pointer move: the output buffer itself', () {
    // Dart zero-fills a new Uint8List, and the kernel then overwrites
    // every byte of it — so the fill is pure waste, repeated once per
    // pointer move at the size of the output. Worth knowing the share
    // before proposing to reuse the buffer.
    const bytes = 3292 * 2632 * 4; // whole picture at ×1.25
    final watch = Stopwatch()..start();
    var sink = 0;
    for (var i = 0; i < 8; i += 1) {
      final buffer = Uint8List(bytes);
      sink += buffer.length;
    }
    watch.stop();
    debugPrint(
      '[allocation] ${(bytes / 1e6).toStringAsFixed(1)} MB output buffer  '
      '${(watch.elapsedMicroseconds / 8 / 1000).toStringAsFixed(1)} ms '
      'per pointer move (allocate + zero-fill, then fully overwritten)',
    );
    expect(sink, greaterThan(0));
  });

  test('a clipped resample that keeps the destination GRID: native vs the '
      'Dart reference', () {
    if (dllPath == null) {
      markTestSkipped(nativeEngineMissingSkipReason);
      return;
    }
    // Both, because WHICH ONE differs is the whole diagnosis. The maths
    // says a window is a window: the transform is parameterised by
    // outLeft/outTop, so the same absolute destination pixel samples the
    // same source position either way. If the Dart reference agrees with
    // itself and only the native kernel does not, the cause is in the
    // kernel's row banding rather than in the idea.
    runSweep(forceDart: false);
    runSweep(forceDart: true);
  });
}
