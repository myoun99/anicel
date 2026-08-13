@Tags(['benchmark'])
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_stamp_image.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/native/qa_engine_abi.dart';
import 'package:anicel/src/native/qa_native_engine.dart';
import 'package:anicel/src/services/canvas_selection.dart';
import 'package:anicel/src/services/resample/resample_kernel.dart';

import '../helpers/native_engine_path.dart';

/// What ONE pointer move of a transform drag costs, and what that cost
/// follows.
///
/// 유저 피드백 ⑤ was "변형시 쉬프트누르면 렉이 심함". Shift no longer does
/// anything — the aspect lock moved into 일반변형, which is the DEFAULT —
/// so the symptom has moved rather than gone: whatever Shift was paying
/// for, the ordinary transform now pays by itself. This measures what
/// that is before anything is changed to make it smaller.
///
/// Three questions, in the order that matters:
///
///   1. what does the resample cost, and does it follow the OUTPUT area?
///   2. what else rides on the same pointer move (the premultiply)?
///   3. how much bigger does the uniform (aspect-locked) solve make that
///      output than the free one, for the same hand movement?
///
/// Prints; asserts only that the work happened. Run it alone.
void main() {
  final dllPath = nativeEngineLibraryPathOrNull();

  tearDown(() {
    QaNativeEngine.debugResetForTests();
    debugQaEngineLibraryPathOverride = null;
    QaNativeEngine.debugForceDartFallback = false;
  });

  /// A stamp of [width]×[height] with mixed alpha, so neither the opaque
  /// nor the transparent early-out carries the whole run.
  BrushDab stampDab(int width, int height) {
    final rgba = Uint8List(width * height * 4);
    for (var i = 0; i < rgba.length; i += 4) {
      rgba[i] = i % 251;
      rgba[i + 1] = i % 241;
      rgba[i + 2] = i % 239;
      rgba[i + 3] = (i ~/ 4) % 3 == 0 ? 255 : ((i ~/ 4) % 3 == 1 ? 0 : 128);
    }
    return BrushDab(
      center: CanvasPoint(x: width / 2, y: height / 2),
      color: 0xFFFFFFFF,
      size: 1,
      opacity: 1,
      flow: 1,
      hardness: 1,
      tipShape: BrushTipShape.square,
      pressure: 1,
      sequence: 0,
      stamp: BrushStampImage(
        id: 'bench-$width-$height',
        width: width,
        height: height,
        rgba: rgba,
      ),
    );
  }

  /// A LINE ART stamp: mostly transparent, with thin opaque strokes.
  ///
  /// The other fixture gives every pixel a different word, which is the
  /// worst case for Pick and a case no drawing produces. Pick's kernel has
  /// a flat-support probe — where every source pixel in reach holds the
  /// same word, both modes must return that word, so it returns it without
  /// sampling — and on a drawing that probe carries most of the frame.
  /// Measuring only the noise fixture would send a fix at a cost the real
  /// work never pays.
  BrushDab lineArtDab(int width, int height) {
    final rgba = Uint8List(width * height * 4);
    void plot(int x, int y) {
      if (x < 0 || y < 0 || x >= width || y >= height) {
        return;
      }
      final offset = (y * width + x) * 4;
      rgba[offset + 3] = 255; // opaque black
    }

    // A loose grid of strokes plus two diagonals: enough edge to keep the
    // flat probe honest, sparse enough to look like a drawing.
    for (var y = 0; y < height; y += 1) {
      for (var x = 0; x < width; x += 1) {
        if (x % 97 < 2 || y % 89 < 2) {
          plot(x, y);
        }
      }
    }
    for (var t = 0; t < width && t < height; t += 1) {
      plot(t, t);
      plot(t, height - 1 - t);
      plot(t + 1, t);
    }
    return BrushDab(
      center: CanvasPoint(x: width / 2, y: height / 2),
      color: 0xFF000000,
      size: 1,
      opacity: 1,
      flow: 1,
      hardness: 1,
      tipShape: BrushTipShape.square,
      pressure: 1,
      sequence: 0,
      stamp: BrushStampImage(
        id: 'lineart-$width-$height',
        width: width,
        height: height,
        rgba: rgba,
      ),
    );
  }

  double millisPer(int rounds, void Function() body) {
    for (var i = 0; i < math.max(1, rounds ~/ 4); i += 1) {
      body(); // warmup, discarded
    }
    final watch = Stopwatch()..start();
    for (var i = 0; i < rounds; i += 1) {
      body();
    }
    watch.stop();
    return watch.elapsedMicroseconds / rounds / 1000;
  }

  test('the resample is the pointer move, and it follows the OUTPUT area', () {
    if (dllPath == null) {
      markTestSkipped(nativeEngineMissingSkipReason);
      return;
    }
    QaNativeEngine.debugResetForTests();
    debugQaEngineLibraryPathOverride = dllPath;
    QaNativeEngine.debugForceDartFallback = false;

    // Three sizes: a modest selection, a 1080p-ish cel, and the whole
    // picture on the default canvas — which is what an unselected
    // transform box opens on, and so the common case rather than the
    // extreme one.
    const sources = <(String, int, int)>[
      ('selection 512²', 512, 512),
      ('cel 1920×1080', 1920, 1080),
      ('whole picture 2340×1654', 2340, 1654),
    ];
    // A scale and a rotation, because an axis-aligned scale can take
    // short cuts a real drag does not.
    const scales = <double>[0.75, 1.25, 2.0];

    for (final mode in ResampleMode.values) {
      for (final (label, width, height) in sources) {
        final dab = stampDab(width, height);
        for (final scale in scales) {
          final affine = SelectionAffine(
            pivot: CanvasPoint(x: width / 2, y: height / 2),
            sx: scale,
            sy: scale,
            rotationDegrees: 12,
          );
          BrushDab? out;
          final ms = millisPer(
            4,
            () => out = transformStampDab(dab, affine, mode: mode),
          );
          final result = out!.stamp!;
          final megapixels = result.width * result.height / 1e6;
          debugPrint(
            '[resample ${mode.name}] $label ×$scale  '
            '→ ${result.width}×${result.height} '
            '(${megapixels.toStringAsFixed(2)} MP, '
            '${(result.rgba.length / 1e6).toStringAsFixed(1)} MB)  '
            '${ms.toStringAsFixed(1)} ms  '
            '${(megapixels / ms * 1000).toStringAsFixed(0)} MP/s',
          );
          expect(result.width, greaterThan(0));
        }
      }
    }
  });

  test('the premultiply that rides the same pointer move', () {
    if (dllPath == null) {
      markTestSkipped(nativeEngineMissingSkipReason);
      return;
    }
    QaNativeEngine.debugResetForTests();
    debugQaEngineLibraryPathOverride = dllPath;
    QaNativeEngine.debugForceDartFallback = false;

    // Every resample is followed by a premultiplied copy for the decode.
    // It is a second full pass over the OUTPUT, so it belongs in the
    // per-move total even though it is not the resample.
    final native = QaNativeEngine.instance;
    expect(native, isNotNull, reason: 'the native engine is the fast path');
    for (final (label, width, height) in const <(String, int, int)>[
      ('selection 512²', 512, 512),
      ('whole picture 2340×1654', 2340, 1654),
    ]) {
      final rgba = stampDab(width, height).stamp!.rgba;
      final ms = millisPer(4, () {
        final scratch = native!.premultipliedStampCopy(rgba);
        scratch.free();
      });
      debugPrint(
        '[premultiply] $label  ${ms.toStringAsFixed(2)} ms  '
        '(${(rgba.length / 1e6).toStringAsFixed(1)} MB)',
      );
      expect(ms, greaterThanOrEqualTo(0));
    }
  });

  test('what the viewport clip buys: the same drag, only the visible part', () {
    if (dllPath == null) {
      markTestSkipped(nativeEngineMissingSkipReason);
      return;
    }
    QaNativeEngine.debugResetForTests();
    debugQaEngineLibraryPathOverride = dllPath;
    QaNativeEngine.debugForceDartFallback = false;

    // A whole-picture transform against a 1600×1000 window — a laptop
    // canvas pane over the default 2340×1654 canvas, which is the case
    // the tool is slowest in and the case a user hits by pressing Ctrl+T
    // with nothing selected.
    const width = 2340;
    const height = 1654;
    for (final mode in ResampleMode.values) {
      final art = lineArtDab(width, height);
      final affine = SelectionAffine(
        pivot: CanvasPoint(x: width / 2, y: height / 2),
        sx: 1.25,
        sy: 1.25,
        rotationDegrees: 12,
      );
      final full = transformStampDab(art, affine, mode: mode);
      final fullStamp = full.stamp!;
      final left = full.center.x - fullStamp.width / 2;
      final top = full.center.y - fullStamp.height / 2;
      final visible = (
        left: left + (fullStamp.width - 1600) / 2,
        top: top + (fullStamp.height - 1000) / 2,
        right: left + (fullStamp.width + 1600) / 2,
        bottom: top + (fullStamp.height + 1000) / 2,
      );

      final wholeMs = millisPer(
        3,
        () => transformStampDab(art, affine, mode: mode),
      );
      final clippedMs = millisPer(
        3,
        () => transformStampDab(art, affine, mode: mode, visible: visible),
      );
      final clipped = transformStampDab(
        art,
        affine,
        mode: mode,
        visible: visible,
      ).stamp!;
      debugPrint(
        '[viewport clip ${mode.name}] whole '
        '${fullStamp.width}×${fullStamp.height} '
        '${wholeMs.toStringAsFixed(1)} ms  →  window '
        '${clipped.width}×${clipped.height} '
        '${clippedMs.toStringAsFixed(1)} ms  '
        '= ${(wholeMs / clippedMs).toStringAsFixed(1)}× faster per pointer '
        'move',
      );
      expect(clipped.width, lessThan(fullStamp.width));
    }
  });

  test('the same drag on LINE ART, which is what the tool is for', () {
    if (dllPath == null) {
      markTestSkipped(nativeEngineMissingSkipReason);
      return;
    }
    QaNativeEngine.debugResetForTests();
    debugQaEngineLibraryPathOverride = dllPath;
    QaNativeEngine.debugForceDartFallback = false;

    for (final mode in ResampleMode.values) {
      for (final (label, width, height) in const <(String, int, int)>[
        ('selection 512²', 512, 512),
        ('whole picture 2340×1654', 2340, 1654),
      ]) {
        final noise = stampDab(width, height);
        final art = lineArtDab(width, height);
        final affine = SelectionAffine(
          pivot: CanvasPoint(x: width / 2, y: height / 2),
          sx: 1.25,
          sy: 1.25,
          rotationDegrees: 12,
        );
        final noiseMs = millisPer(
          3,
          () => transformStampDab(noise, affine, mode: mode),
        );
        final artMs = millisPer(
          3,
          () => transformStampDab(art, affine, mode: mode),
        );
        debugPrint(
          '[line art ${mode.name}] $label ×1.25  '
          'noise ${noiseMs.toStringAsFixed(1)} ms  '
          'line art ${artMs.toStringAsFixed(1)} ms  '
          '→ ${(noiseMs / artMs).toStringAsFixed(1)}× cheaper on a drawing',
        );
        expect(artMs, greaterThan(0));
      }
    }
  });

  test('the instrument first: is the "native" number actually native?', () {
    if (dllPath == null) {
      markTestSkipped(nativeEngineMissingSkipReason);
      return;
    }
    // `resampleSelectionInto` falls back to the Dart reference silently
    // when the engine is missing OR when the binding returns false, and
    // the two produce identical bytes by contract — so nothing about the
    // RESULT says which one ran. Only the clock does, which is exactly
    // what a benchmark must not take on trust.
    final dab = stampDab(1024, 1024);
    final affine = SelectionAffine(
      pivot: CanvasPoint(x: 512, y: 512),
      sx: 1.25,
      sy: 1.25,
      rotationDegrees: 12,
    );

    QaNativeEngine.debugResetForTests();
    debugQaEngineLibraryPathOverride = dllPath;
    QaNativeEngine.debugForceDartFallback = false;
    final native = millisPer(3, () => transformStampDab(dab, affine));

    QaNativeEngine.debugResetForTests();
    debugQaEngineLibraryPathOverride = dllPath;
    QaNativeEngine.debugForceDartFallback = true;
    final dart = millisPer(3, () => transformStampDab(dab, affine));

    debugPrint(
      '[instrument] 1024² ×1.25 blend  native ${native.toStringAsFixed(1)} ms  '
      'dart ${dart.toStringAsFixed(1)} ms  '
      '→ ${(dart / native).toStringAsFixed(1)}× '
      '${(dart / native) < 2 ? "(SUSPECT: the fast path may not be running)" : "(native is running)"}',
    );
    expect(native, greaterThan(0));
  });

  test('what the aspect LOCK adds: the uniform solve takes the larger axis, '
      'so the output grows with the drag angle', () {
    // No timing here — this is the multiplier the timings above get
    // applied to. The uniform solve is
    //   magnitude = max(|sx|, |sy|)
    // so a drag that is not exactly along the box diagonal scales the
    // SHORT axis up to the long one. Output area is proportional to
    // sx·sy, which makes the penalty max²/(sx·sy).
    //
    // A perfectly diagonal drag pays nothing; the question is what an
    // ordinary hand pays.
    for (final (label, sx, sy) in const <(String, double, double)>[
      ('on the diagonal', 1.50, 1.50),
      ('10% off', 1.50, 1.35),
      ('25% off', 1.50, 1.125),
      ('50% off', 1.50, 0.75),
      ('mostly one axis', 1.50, 0.30),
    ]) {
      final magnitude = math.max(sx, sy);
      final locked = magnitude * magnitude;
      final free = sx * sy;
      debugPrint(
        '[aspect lock] $label  free ${free.toStringAsFixed(2)}× area  '
        'locked ${locked.toStringAsFixed(2)}×  '
        '→ ${(locked / free).toStringAsFixed(2)}× the pixels to resample',
      );
      expect(locked, greaterThanOrEqualTo(free));
    }
  });
}
