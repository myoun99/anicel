// Brush commit-path benchmark harness (audit: brush efficiency P0).
//
// Measures wall time of `materializeBrushDabSequenceOnBitmapSurface` — the
// production stroke-commit rasterization path — across representative stroke
// shapes, so P1..P3 optimizations can prove before/after with real numbers.
//
// Run with:
//   dart run tool/brush_commit_benchmark.dart
//
// This is a dev tool only: it is not imported by lib/ or test/ runtime code
// and does not change runtime behavior.
// ignore_for_file: avoid_print
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_dab_sequence.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/services/bitmap_surface_brush_commit.dart';

class BenchmarkScenario {
  const BenchmarkScenario({
    required this.name,
    required this.brushSize,
    required this.dabCount,
    this.hardness = 0.8,
    this.iterations = 3,
  });

  final String name;
  final double brushSize;
  final int dabCount;
  final double hardness;
  final int iterations;
}

const scenarios = [
  BenchmarkScenario(
    name: 'small  (size  8, 50 dabs)',
    brushSize: 8,
    dabCount: 50,
    iterations: 10,
  ),
  BenchmarkScenario(
    name: 'medium (size 16, 100 dabs)',
    brushSize: 16,
    dabCount: 100,
    iterations: 5,
  ),
  BenchmarkScenario(
    name: 'large  (size 32, 100 dabs)',
    brushSize: 32,
    dabCount: 100,
  ),
  BenchmarkScenario(
    name: 'xl     (size 64, 50 dabs)',
    brushSize: 64,
    dabCount: 50,
  ),
  // Long dense stroke at 5% spacing (user-reported freeze scenario).
  BenchmarkScenario(
    name: 'dense  (size 64, 940 dabs)',
    brushSize: 64,
    dabCount: 940,
    iterations: 2,
  ),
  BenchmarkScenario(
    name: 'dense+ (size 128, 900 dabs)',
    brushSize: 128,
    dabCount: 900,
    iterations: 2,
  ),
];

BrushDabSequence strokeFor(BenchmarkScenario scenario) {
  // Diagonal stroke across the canvas with production-like spacing
  // (spacing ratio 0.25 -> step = size * 0.25), crossing tile boundaries.
  final step = scenario.brushSize * 0.25;
  final dabs = <BrushDab>[];
  for (var i = 0; i < scenario.dabCount; i += 1) {
    dabs.add(
      BrushDab(
        center: CanvasPoint(x: 40.0 + i * step, y: 40.0 + i * step * 0.6),
        color: 0xFF223344,
        size: scenario.brushSize,
        opacity: 0.9,
        flow: 0.85,
        hardness: scenario.hardness,
        tipShape: BrushTipShape.round,
        pressure: 1.0,
        sequence: i,
      ),
    );
  }
  return BrushDabSequence(dabs);
}

void main() {
  const canvasSize = CanvasSize(width: 1280, height: 720);

  print('Brush commit benchmark (materializeBrushDabSequenceOnBitmapSurface)');
  print('canvas ${canvasSize.width}x${canvasSize.height}, tileSize 256\n');

  for (final scenario in scenarios) {
    final sequence = strokeFor(scenario);

    // Warmup (JIT) + correctness sanity: the stroke must touch tiles.
    final warmupSurface = BitmapSurface(canvasSize: canvasSize);
    final warmup = materializeBrushDabSequenceOnBitmapSurface(
      surface: warmupSurface,
      sequence: sequence,
    );
    if (!warmup.hasChanges) {
      throw StateError(
        'Benchmark stroke produced no changes: ${scenario.name}',
      );
    }

    // Timed runs on fresh blank surfaces (first-stroke commit) ...
    final blankWatch = Stopwatch()..start();
    for (var i = 0; i < scenario.iterations; i += 1) {
      materializeBrushDabSequenceOnBitmapSurface(
        surface: BitmapSurface(canvasSize: canvasSize),
        sequence: sequence,
      );
    }
    blankWatch.stop();

    // ... and on an already-painted surface (later strokes read existing
    // tiles, which is where per-pixel tile reads dominate).
    final paintedSurface = warmup.surface;
    final paintedWatch = Stopwatch()..start();
    for (var i = 0; i < scenario.iterations; i += 1) {
      materializeBrushDabSequenceOnBitmapSurface(
        surface: paintedSurface,
        sequence: sequence,
      );
    }
    paintedWatch.stop();

    final blankMs =
        blankWatch.elapsedMicroseconds / 1000.0 / scenario.iterations;
    final paintedMs =
        paintedWatch.elapsedMicroseconds / 1000.0 / scenario.iterations;
    print(scenario.name);
    print('  blank surface  : ${blankMs.toStringAsFixed(1)} ms/stroke');
    print('  painted surface: ${paintedMs.toStringAsFixed(1)} ms/stroke');
    print('  dirty tiles    : ${warmup.dirtyTiles.length}\n');
  }
}
