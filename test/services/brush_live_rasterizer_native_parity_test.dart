import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/native_engine_path.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/native/qa_engine_abi.dart';
import 'package:anicel/src/native/qa_native_engine.dart';
import 'package:anicel/src/services/brush_live_stroke_rasterizer.dart';
import 'package:anicel/src/services/brush_tip_stamp_cache.dart';

/// R21: the live stroke rasterizer's native path (the SAME C kernel the
/// commit uses, srcOver-only) must be byte-identical to the Dart loop —
/// randomized dabs, resolved through the tip-stamp cache exactly like
/// the real input funnel. Skips loudly without the locally built DLL.
void main() {
  // R26/2A: resolved per platform (and via QA_ENGINE_PATH on CI) so these
  // byte-parity pins are not silently Windows-only.
  final dllPath = nativeEngineLibraryPathOrNull();
  final available = dllPath != null;

  tearDown(() {
    QaNativeEngine.debugResetForTests();
    debugQaEngineLibraryPathOverride = null;
    QaNativeEngine.debugForceDartFallback = false;
  });

  test('native live blend == Dart live blend, byte for byte (randomized '
      'resolved dabs)', () {
    if (!available) {
      markTestSkipped(
        'qa_engine.dll not built — run: cmake -S packages/qa_native/src -B '
        'build/native_standalone && cmake --build build/native_standalone '
        '--config Release',
      );
      return;
    }
    const canvasSize = CanvasSize(width: 300, height: 200);
    final random = Random(20260715);
    final cache = BrushTipStampCache();
    final dabs = <BrushDab>[
      for (var i = 0; i < 24; i += 1)
        cache.resolveDab(
          BrushDab(
            center: CanvasPoint(
              x: random.nextDouble() * canvasSize.width,
              y: random.nextDouble() * canvasSize.height,
            ),
            color: 0xFF000000 | random.nextInt(0xFFFFFF),
            size: 4 + random.nextDouble() * 180,
            opacity: 0.3 + random.nextDouble() * 0.7,
            flow: 0.3 + random.nextDouble() * 0.7,
            hardness: random.nextDouble(),
            tipShape: random.nextBool()
                ? BrushTipShape.round
                : BrushTipShape.square,
            pressure: 1,
            sequence: i,
            roundness: 0.4 + random.nextDouble() * 0.6,
            angleDegrees: random.nextDouble() * 360,
          ),
        ),
    ];

    QaNativeEngine.debugResetForTests();
    QaNativeEngine.debugForceDartFallback = true;
    final dart = BrushLiveStrokeRasterizer(canvasSize: canvasSize)
      ..blendFrom(dabs, from: 0);
    final dartPixels = dart.strokePixelsWithinBounds();

    QaNativeEngine.debugResetForTests();
    debugQaEngineLibraryPathOverride = dllPath;
    QaNativeEngine.debugForceDartFallback = false;
    expect(QaNativeEngine.instance, isNotNull);
    final native = BrushLiveStrokeRasterizer(canvasSize: canvasSize)
      ..blendFrom(dabs, from: 0);
    final nativePixels = native.strokePixelsWithinBounds();
    expect(native.strokeBounds, dart.strokeBounds);
    expect(nativePixels, dartPixels, reason: 'live blend byte parity');
    native.clear();
  });
}
