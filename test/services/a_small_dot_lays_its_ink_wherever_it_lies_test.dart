import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/brush_anti_alias.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_dab_sequence.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/services/bitmap_surface_brush_commit.dart';
import 'package:anicel/src/services/brush_dab_dirty_region.dart';
import 'package:anicel/src/services/brush_dab_interpolator.dart';
import 'package:anicel/src/services/brush_dab_tip_geometry.dart';
import 'package:anicel/src/services/brush_tip_stamp_cache.dart';
import 'package:anicel/src/services/canvas_color_sampler.dart';

/// A SMALL CIRCLE LAYS ITS AREA (board a-one-pixel-dab-drops-out-by-where-
/// it-lies Q6, 유저 2026-10-25 「클튜 점 표본을 보고 정한다」 → b): up to a
/// 5px nib a pixel lays what its whole square covers of the tip
/// (`RoundTipProfile.rowLength`), so a dot lays the same ink wherever its
/// centre falls — as Clip Studio's G펜 taps do (1px: 0.526±0.024, centred
/// and off-centre alike) — and a level line still lays the column ink the
/// edge was fitted to (Q4 · Q5), read along the radius.
void main() {
  const sizes = [0.7, 1.0, 1.5, 2.0, 3.0, 5.0];

  BrushDab gPen(
    BrushAntiAlias step,
    double size,
    double x,
    double y, {
    double hardness = 1,
  }) => BrushDab(
    center: CanvasPoint(x: x, y: y),
    color: 0xFF000000,
    size: size,
    opacity: 1,
    flow: 1,
    hardness: hardness,
    pressure: 1,
    sequence: 0,
    tipShape: BrushTipShape.round,
    antiAlias: step,
  );

  /// What a dab at (`8 + fx`, `8 + fy`) covers, summed over every pixel
  /// within six of it — and over its dirty region alone.
  ({double all, double inRegion}) inkOf(BrushDab dab) {
    final tip = brushDabTipGeometry(dab);
    final region = dirtyRegionForBrushDab(dab)!;
    var all = 0.0;
    var inRegion = 0.0;
    for (var y = 2; y < 14; y += 1) {
      for (var x = 2; x < 14; x += 1) {
        final coverage = tipCoverageAt(
          tip,
          x + 0.5 - dab.center.x,
          y + 0.5 - dab.center.y,
        );
        all += coverage;
        if (x >= region.left &&
            x < region.rightExclusive &&
            y >= region.top &&
            y < region.bottomExclusive) {
          inRegion += coverage;
        }
      }
    }
    return (all: all, inRegion: inRegion);
  }

  const phases = [0.0, 0.25, 0.5, 0.75];

  for (final step in BrushAntiAlias.values.where(
    (step) => step != BrushAntiAlias.none,
  )) {
    for (final hardness in [1.0, 0.5]) {
      test('🚨a dot lays the same ink wherever its centre falls — '
          '${step.name}, hardness $hardness', () {
        for (final size in sizes) {
          final inks = [
            for (final fx in phases)
              for (final fy in phases)
                inkOf(
                  gPen(
                    step,
                    size,
                    8 + fx + 0.0137,
                    8 + fy + 0.0291,
                    hardness: hardness,
                  ),
                ),
          ];
          final all = [for (final ink in inks) ink.all];
          // What is left is the table's sixteenth-pixel grid, read
          // bilinearly; read along the radius the spread was ~0.2.
          expect(
            all.reduce(math.max) - all.reduce(math.min),
            lessThan(0.003),
            reason: 'size $size: ${all.map((v) => v.toStringAsFixed(4))}',
          );
          for (final ink in inks) {
            expect(
              ink.inRegion,
              ink.all,
              reason: 'size $size: a small dot lays nothing past its box',
            );
          }
        }
      });
    }
  }

  test('🚨a 1px dot LAID lays the same ink wherever it lies', () {
    double laid(double fx, double fy) {
      final surface = materializeBrushDabSequenceOnBitmapSurface(
        surface: BitmapSurface(
          canvasSize: const CanvasSize(width: 16, height: 16),
          tileSize: 16,
        ),
        sequence: BrushDabSequence(
          BrushTipStampCache().resolveDabs([
            gPen(BrushAntiAlias.medium, 1.0, 8 + fx, 8 + fy),
          ]),
        ),
      ).surface;
      var sum = 0.0;
      for (var y = 0; y < 16; y += 1) {
        for (var x = 0; x < 16; x += 1) {
          sum += ((surfacePixelRgba(surface, x, y) ?? 0) & 0xFF) / 255.0;
        }
      }
      return sum;
    }

    final centred = laid(0.0, 0.0);
    for (final (fx, fy) in [(0.5, 0.0), (0.5, 0.5), (0.27, 0.71)]) {
      // Each pixel rounds to a byte on its own.
      expect(laid(fx, fy), closeTo(centred, 0.012), reason: '($fx, $fy)');
    }
    // Clip Studio's 1px G펜 tap at 2단계: 0.526 (Q6).
    expect(centred, closeTo(0.526, 0.08));
  });

  const lineSteps = [
    BrushAntiAlias.low,
    BrushAntiAlias.medium,
    BrushAntiAlias.high,
  ];
  const lineSizes = [0.7, 1.0, 1.5, 2.0, 2.5];

  test('🚨a small nib\'s column lays the line ink the edge was fitted to, '
      'wherever the line lies', () {
    // Read along the radius a line's column lays the profile across it:
    // the edge's rim plus its hard part (`BrushAntiAlias.edge`). Read by
    // the square, a dab's column is the strip of the tip it crosses —
    // whole at every phase of the line across the pixels.
    double fitted(BrushAntiAlias step, double size) {
      final edge = step.edge;
      final radius = size / 2;
      final rim =
          radius - edge.inset * math.min(1.0, radius / edge.insetReach);
      final width =
          edge.width +
          edge.widthPerRadius * math.min(radius, edge.widthReach);
      return rim + math.max(0.0, rim - width);
    }

    for (final step in lineSteps) {
      for (final size in lineSizes) {
        final tip = brushDabTipGeometry(gPen(step, size, 0, 0));
        for (final phase in [0.0, 0.13, 0.37, 0.5, 0.81]) {
          var column = 0.0;
          for (var k = -4; k <= 4; k += 1) {
            column += tipCoverageAt(tip, 0, k + phase);
          }
          expect(
            column,
            closeTo(fitted(step, size), 0.001),
            reason: '${step.name} size $size, phase $phase',
          );
        }
      }
    }
  });

  test('🚨a small nib\'s line LAID lays what the radial read of it lays', () {
    // The edge was fitted (Q4 · Q5) on lines read along the radius; a
    // roundness short of one is still read so. Shifting the line by
    // eighths of the quarter-pixel dab step walks every phase of the dabs
    // against the pixels — one line alone sits on a few of them.
    double laidInk(BrushAntiAlias step, double size, double roundness) {
      const width = 220;
      const height = 80;
      const angle = 1.7 * math.pi / 180.0;
      var sum = 0.0;
      var columns = 0;
      for (var shift = 0; shift < 8; shift += 1) {
        BrushDab at(double t) => gPen(
          step,
          size,
          width / 2 + t * math.cos(angle) + 0.137 + shift / 32,
          height / 2 + t * math.sin(angle) + 0.29,
        ).copyWith(roundness: roundness);
        final first = at(-90);
        final surface = materializeBrushDabSequenceOnBitmapSurface(
          surface: BitmapSurface(
            canvasSize: const CanvasSize(width: width, height: height),
            tileSize: 64,
          ),
          sequence: BrushDabSequence(
            BrushTipStampCache().resolveDabs([
              first,
              ...const BrushDabInterpolator().interpolate(
                previous: first,
                nextRaw: at(90),
                firstSequence: 1,
                spacingRatio: 0.01,
              ),
            ]),
          ),
        ).surface;
        for (var x = 50; x < width - 50; x += 1) {
          for (var y = 0; y < height; y += 1) {
            sum += ((surfacePixelRgba(surface, x, y) ?? 0) & 0xFF) / 255.0;
          }
          columns += 1;
        }
      }
      return sum / columns;
    }

    for (final step in lineSteps) {
      for (final size in lineSizes) {
        expect(
          laidInk(step, size, 1.0),
          closeTo(laidInk(step, size, 0.99999), 0.008),
          reason: '${step.name} size $size',
        );
      }
    }
  });
}
