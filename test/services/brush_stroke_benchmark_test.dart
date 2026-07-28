@Tags(['benchmark'])
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_tip_mask.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/services/brush_live_stroke_rasterizer.dart';

/// Live-stroke hot-path microbenchmark (not a correctness test): prints
/// per-dab blend cost for representative brush configurations so lag work
/// is measured, not guessed. Run with `flutter test` (JIT numbers are
/// pessimistic vs release AOT but hotspots rank the same).
void main() {
  BrushTipMask mask(int size, {String id = 'bench'}) {
    final alpha = Uint8List(size * size);
    final center = (size - 1) / 2.0;
    for (var y = 0; y < size; y += 1) {
      for (var x = 0; x < size; x += 1) {
        final dx = (x - center) / center;
        final dy = (y - center) / center;
        final d = math.sqrt(dx * dx + dy * dy);
        alpha[y * size + x] = d >= 1.0 ? 0 : ((1.0 - d) * 255).round();
      }
    }
    return BrushTipMask(id: id, size: size, alpha: alpha);
  }

  List<BrushDab> stroke({
    required double size,
    double hardness = 0.3,
    BrushTipMask? tipMask,
    BrushTipMask? dualMask,
    BrushTipMask? textureMask,
    int count = 40,
    double step = 10,
  }) {
    return [
      for (var index = 0; index < count; index += 1)
        BrushDab(
          center: CanvasPoint(
            x: 150.0 + index * step,
            y: 150.0 + index * step * 0.6,
          ),
          color: 0xE6224488,
          size: size,
          opacity: 0.85,
          flow: 0.7,
          hardness: hardness,
          tipShape: BrushTipShape.round,
          pressure: 1,
          sequence: index,
          tipMask: tipMask,
          dualMask: dualMask,
          dualMaskScale: 1.0,
          dualOffsetU: 0.3,
          dualOffsetV: 0.7,
          textureMask: textureMask,
          textureScale: 1.0,
          textureDensity: 0.8,
        ),
    ];
  }

  void bench(String label, List<BrushDab> dabs) {
    final canvas = const CanvasSize(width: 1280, height: 720);
    // Warm up JIT.
    BrushLiveStrokeRasterizer(canvasSize: canvas).blendFrom(dabs);
    final rasterizer = BrushLiveStrokeRasterizer(canvasSize: canvas);
    final watch = Stopwatch()..start();
    rasterizer.blendFrom(dabs);
    watch.stop();
    final area = dabs.first.size * dabs.first.size * dabs.length;
    final msPerDab = watch.elapsedMicroseconds / 1000.0 / dabs.length;
    final mpxPerSec = area / watch.elapsedMicroseconds;
    // ignore: avoid_print
    print(
      '[bench] $label: ${watch.elapsedMilliseconds}ms total, '
      '${msPerDab.toStringAsFixed(2)}ms/dab, '
      '${mpxPerSec.toStringAsFixed(1)}Mpx/s',
    );
  }

  test(
    'live rasterizer blend cost per brush configuration',
    () {
      final tip = mask(256, id: 'tip');
      final dual = mask(128, id: 'dual');
      final texture = mask(256, id: 'texture');

      bench('plain soft round 60px', stroke(size: 60));
      bench('plain soft round 200px', stroke(size: 200));
      bench('tipMask 200px', stroke(size: 200, tipMask: tip));
      bench(
        'tipMask+dual+texture 200px (watercolor-like)',
        stroke(size: 200, tipMask: tip, dualMask: dual, textureMask: texture),
      );
      bench(
        'tipMask+dual+texture 60px',
        stroke(size: 60, tipMask: tip, dualMask: dual, textureMask: texture),
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
