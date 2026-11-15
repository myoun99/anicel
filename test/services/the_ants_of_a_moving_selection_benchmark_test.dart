@Tags(['benchmark'])
library;

import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/services/canvas_selection.dart';
import 'package:anicel/src/services/canvas_selection_region.dart';

/// What the ants on the pixel grid cost a frame of a transform's drag
/// (F-591): each frame the session maps its selection anew, a region of its
/// own, and its pixel outline is walked from the engine's runs — no memo
/// to hit. Beside it, the polygon traced as it was while the drag lasted.
///
/// ⚠️READ THE RATIO AND THE ORDER, NOT THE MILLISECONDS ALONE: the machine
/// runs other lanes' work. Prints; asserts only that the work happened.
void main() {
  /// A lasso of [points] points round an ellipse [rx] × [ry] about
  /// (cx, cy), its radius wobbling as a hand's does.
  CanvasSelectionRegion lasso({
    required double cx,
    required double cy,
    required double rx,
    required double ry,
    int points = 1200,
  }) {
    final random = math.Random(7);
    return CanvasSelectionRegion.shape(
      CanvasSelectionShape([
        for (var i = 0; i < points; i += 1)
          () {
            final angle = 2 * math.pi * i / points;
            final wobble = 1 + (random.nextDouble() - 0.5) * 0.04;
            return CanvasPoint(
              x: cx + rx * wobble * math.cos(angle),
              y: cy + ry * wobble * math.sin(angle),
            );
          }(),
      ]),
    );
  }

  /// The [frame]th step of a drag that turns and grows about (cx, cy).
  CanvasPoint Function(CanvasPoint) step(int frame, double cx, double cy) {
    final angle = frame * 0.7 * math.pi / 180;
    final scale = 1 + frame * 0.003;
    final c = math.cos(angle) * scale, s = math.sin(angle) * scale;
    return (p) => CanvasPoint(
      x: cx + (p.x - cx) * c - (p.y - cy) * s + frame * 0.37,
      y: cy + (p.x - cx) * s + (p.y - cy) * c + frame * 0.21,
    );
  }

  /// The median and the longest of [frames] frames, each a region mapped
  /// anew and [work] done on it, after two frames untimed.
  ({double median, double longest}) perFrame(
    CanvasSelectionRegion region,
    double cx,
    double cy,
    void Function(CanvasSelectionRegion moved) work, {
    int frames = 30,
  }) {
    for (var frame = 0; frame < 2; frame += 1) {
      work(region.mapped(step(frame, cx, cy)));
    }
    final times = <int>[];
    for (var frame = 2; frame < frames + 2; frame += 1) {
      final moved = region.mapped(step(frame, cx, cy));
      final watch = Stopwatch()..start();
      work(moved);
      times.add(watch.elapsedMicroseconds);
    }
    times.sort();
    return (
      median: times[times.length ~/ 2] / 1000,
      longest: times.last / 1000,
    );
  }

  for (final (name, cx, cy, rx, ry) in [
    ('a lasso 400×300', 900.0, 500.0, 200.0, 150.0),
    ('a lasso 1400×800', 960.0, 540.0, 700.0, 400.0),
    ('a lasso 3200×1800 (a 4K canvas)', 1920.0, 1080.0, 1600.0, 900.0),
  ]) {
    test('the ants of $name, a frame of its drag', () {
      final region = lasso(cx: cx, cy: cy, rx: rx, ry: ry);
      var contours = 0;
      final pixels = perFrame(region, cx, cy, (moved) {
        contours = moved.pixelOutlineContours.length;
      });
      // The engine's half alone — the mask's runs, read back — of the walk
      // above, so the rest is the contours' on the CPU.
      final runs = perFrame(region, cx, cy, (moved) {
        final bounds = moved.selectedBounds;
        final left = (bounds.left - 0.5).floor();
        final top = (bounds.top - 0.5).floor();
        moved.pixelRunsFor(
          left: left,
          top: top,
          width: (bounds.right + 0.5).ceil() - left,
          height: (bounds.bottom + 0.5).ceil() - top,
        );
      });
      final polygon = perFrame(region, cx, cy, (moved) {
        moved.pathIn((point) => Offset(point.x, point.y)).getBounds();
      });
      debugPrint(
        '$name: on the pixels ${pixels.median} ms (longest '
        '${pixels.longest}) — of which the runs ${runs.median} ms (longest '
        '${runs.longest}) · the polygon ${polygon.median} ms (longest '
        '${polygon.longest}) · $contours contour(s)',
      );
      expect(contours, greaterThan(0), reason: 'the walk ran');
    });
  }
}
