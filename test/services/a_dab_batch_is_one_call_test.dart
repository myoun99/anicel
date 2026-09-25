import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_dab_sequence.dart';
import 'package:anicel/src/models/brush_stamp_image.dart';
import 'package:anicel/src/models/brush_tip_mask.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/native/qa_engine_abi.dart';
import 'package:anicel/src/native/qa_native_engine.dart';
import 'package:anicel/src/services/bitmap_surface_brush_commit.dart';
import 'package:anicel/src/services/brush_dab_kernel.dart';
import 'package:anicel/src/services/brush_live_stroke_rasterizer.dart';

import '../helpers/native_engine_path.dart';

/// 🚨A CALL IS A BATCH, NOT A DAB (ABI 38, 2026-09-24, board
/// `preset-spacing-minimum`). One pooled call per dab woke the engine's
/// workers once a dab, which at the 1% spacing cost as much as the dab.
/// The bytes cannot tell a batch from a dab at a time — the parity suites
/// pin those — so these count the calls.
void main() {
  const canvasSize = CanvasSize(width: 400, height: 300);
  final dllPath = nativeEngineLibraryPathOrNull();

  setUp(() {
    QaNativeEngine.debugResetForTests();
    QaNativeEngine.debugForceDartFallback = false;
    debugQaEngineLibraryPathOverride = dllPath;
    QaNativeEngine.debugDabBatchCalls = 0;
  });

  tearDown(() {
    QaNativeEngine.debugResetForTests();
    debugQaEngineLibraryPathOverride = null;
  });

  bool engineMissing() {
    if (dllPath != null && QaNativeEngine.instance != null) {
      return false;
    }
    if (nativeEngineRequired) {
      fail(nativeEngineMissingSkipReason);
    }
    markTestSkipped(nativeEngineMissingSkipReason);
    return true;
  }

  BrushDab dabAt(int i, {BrushTipMask? tip, double size = 60}) => BrushDab(
    center: CanvasPoint(x: 80.5 + i * 1.0, y: 120.25 + i * 0.4),
    color: 0xFF2A5599,
    size: size,
    opacity: 0.7,
    flow: 0.4,
    hardness: 0.5,
    tipShape: BrushTipShape.round,
    pressure: 1,
    sequence: i,
    tipMask: tip,
  );

  test('a run of the commit is one call per batch of dabs', () {
    if (engineMissing()) {
      return;
    }
    materializeBrushDabSequenceOnBitmapSurface(
      surface: BitmapSurface(canvasSize: canvasSize, tileSize: 256),
      sequence: BrushDabSequence([for (var i = 0; i < 150; i += 1) dabAt(i)]),
    );
    expect(NativeDabBatcher.maxDabs, 64);
    expect(QaNativeEngine.debugDabBatchCalls, 3, reason: '64 + 64 + 22');
  });

  test('masks past the upload allowance start the next call', () {
    if (engineMissing()) {
      return;
    }
    final allowance = QaNativeEngine.instance!.batchMaskAllowance.count;
    final tips = [
      for (var k = 0; k <= allowance; k += 1)
        BrushTipMask(
          id: 'batch-call-tip-$k',
          size: 8,
          alpha: Uint8List.fromList([
            for (var index = 0; index < 64; index += 1) (index * 3 + k) % 256,
          ]),
        ),
    ];
    materializeBrushDabSequenceOnBitmapSurface(
      surface: BitmapSurface(canvasSize: canvasSize, tileSize: 256),
      sequence: BrushDabSequence([
        for (var i = 0; i < tips.length; i += 1) dabAt(i, tip: tips[i]),
      ]),
    );
    expect(
      QaNativeEngine.debugDabBatchCalls,
      2,
      reason: 'the mask one past the allowance opens the second call',
    );
  });

  test('dabs whose tips change share the call while the cache holds them', () {
    if (engineMissing()) {
      return;
    }
    final tips = [
      for (var k = 0; k < 3; k += 1)
        BrushTipMask(
          id: 'batch-call-shared-$k',
          size: 8,
          alpha: Uint8List.fromList([
            for (var index = 0; index < 64; index += 1) (index * 5 + k) % 256,
          ]),
        ),
    ];
    materializeBrushDabSequenceOnBitmapSurface(
      surface: BitmapSurface(canvasSize: canvasSize, tileSize: 256),
      sequence: BrushDabSequence([
        for (var i = 0; i < 30; i += 1) dabAt(i, tip: tips[i % 3]),
      ]),
    );
    expect(QaNativeEngine.debugDabBatchCalls, 1);
  });

  test('a stamp lands on what the dabs before it left', () {
    // The only kind of dab that is not batched lands between two batches:
    // blended ahead of the dabs queued before it, the stamp would sit
    // UNDER them wherever the two overlap.
    if (engineMissing()) {
      return;
    }
    const width = 40;
    const height = 30;
    final stamp = BrushStampImage(
      id: 'batch-call-stamp',
      width: width,
      height: height,
      rgba: Uint8List.fromList([
        for (var p = 0; p < width * height; p += 1) ...[200, 40, 90, 150],
      ]),
    );
    final sequence = BrushDabSequence([
      for (var i = 0; i < 5; i += 1) dabAt(i),
      BrushDab(
        center: CanvasPoint(x: 84, y: 121),
        color: 0xFF000000,
        size: width.toDouble(),
        opacity: 1,
        flow: 1,
        hardness: 1,
        tipShape: BrushTipShape.square,
        pressure: 1,
        sequence: 5,
        stamp: stamp,
      ),
      for (var i = 6; i < 11; i += 1) dabAt(i),
    ]);
    BitmapSurface blank() =>
        BitmapSurface(canvasSize: canvasSize, tileSize: 256);

    final native = materializeBrushDabSequenceOnBitmapSurface(
      surface: blank(),
      sequence: sequence,
    );
    expect(QaNativeEngine.debugDabBatchCalls, 2);
    QaNativeEngine.debugForceDartFallback = true;
    final dart = materializeBrushDabSequenceOnBitmapSurface(
      surface: blank(),
      sequence: sequence,
    );
    expect(native.surface, dart.surface);
  });

  test('a frame of the live stroke is one call', () {
    if (engineMissing()) {
      return;
    }
    final dabs = [for (var i = 0; i < 60; i += 1) dabAt(i)];
    final raster = BrushLiveStrokeRasterizer(canvasSize: canvasSize);
    raster.blendFrom(dabs.sublist(0, 30));
    expect(QaNativeEngine.debugDabBatchCalls, 1);
    raster.blendFrom(dabs);
    expect(QaNativeEngine.debugDabBatchCalls, 2);
    raster.clear();
  });
}
