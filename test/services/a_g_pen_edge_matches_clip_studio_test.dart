// A G-PEN LINE IS CLIP STUDIO'S, SIZE FOR SIZE AND STEP FOR STEP (I-50 · Q4).
//
// 유저 2026-09-30: 「경도와 따로 — 단계마다 고정 폭, 클튜 샘플로 맞춤」, and
// 2026-10-25 (board a-one-pixel-dab-drops-out-by-where-it-lies Q3): 「표본을
// 넣는다」. The samples are their own Clip Studio G펜 lines — I-50's at size
// 10 and 50 (`参考/brush/cls_gpen_AA.png`), Q4's at sizes 1–8, 10 and 50,
// Q5's at 100 and 300 (「100 · 300px 표본을 더 준다」) — and
// `BrushAntiAlias.edge` is fitted to all of them at once. THIS is the
// pin that the fit still holds: lines drawn the way the canvas draws one
// (the interpolator's step, the stamp cache, the kernel and each dab's
// share of a stamp), measured the way the samples were.
//
// 📏Two measures. The INK of a column: a near-level line's coverage summed
// down each pixel column, over four sub-pixel phases and two slopes — how
// dark a line is, and the measure a 1px line fell apart on (Q4). And the
// slanted-edge BANDS: every row that crosses a slanted line's edge samples
// the edge profile at a new subpixel phase, so the line gives the profile
// at a fine pitch; the bands are the distance the coverage takes to fall
// from 90% to 10%, and from 254/255 to 1/255.
//
// ⚠️The tolerances are the fit's own residuals at landing (2026-10-25: ink
// within 0.28 a column; bands within 0.15 and 0.37 since Q5's refit, 0.10
// and 0.28 before it over 10 and 50 alone) — one law for every size leaves
// some, and they are the room a refit has, not noise.
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
import 'package:anicel/src/services/brush_dab_interpolator.dart';
import 'package:anicel/src/services/brush_tip_stamp_cache.dart';
import 'package:anicel/src/services/canvas_color_sampler.dart';

/// Clip Studio's G펜 rows at size 10 and 50, measured 2026-10-01 by the same
/// method (10–90% band, full band) — board I-50 — and at 100 and 300
/// (`参考/CSP_decode/1024_gpen`, board a-one-pixel-dab-drops-out-by-where-it-lies
/// Q5, 2026-10-25).
const _clipStudio = {
  10: {
    BrushAntiAlias.low: (tenToNinety: 0.79, full: 1.28),
    BrushAntiAlias.medium: (tenToNinety: 0.97, full: 1.86),
    BrushAntiAlias.high: (tenToNinety: 1.25, full: 2.37),
  },
  // ↩️The size-50 row held only once a big brush stopped piling its stamps a
  // pixel apart (`one-pixel-steps-change-a-brush-with-its-size` A).
  50: {
    BrushAntiAlias.low: (tenToNinety: 0.87, full: 1.49),
    BrushAntiAlias.medium: (tenToNinety: 1.22, full: 2.25),
    BrushAntiAlias.high: (tenToNinety: 1.69, full: 3.02),
  },
  // Q5 (2026-10-25): near-level strokes, so a column plays a row's part —
  // the edge drifts through every sub-pixel phase along the stroke, and its
  // place in each column is a local fit of the half-coverage crossings.
  100: {
    BrushAntiAlias.low: (tenToNinety: 0.98, full: 1.53),
    BrushAntiAlias.medium: (tenToNinety: 1.82, full: 2.72),
    BrushAntiAlias.high: (tenToNinety: 1.94, full: 3.43),
  },
  300: {
    BrushAntiAlias.low: (tenToNinety: 1.17, full: 1.60),
    BrushAntiAlias.medium: (tenToNinety: 1.86, full: 2.64),
    BrushAntiAlias.high: (tenToNinety: 2.47, full: 3.69),
  },
};

/// The ink of a column of Clip Studio's G펜 lines at 1단계 · 2단계 · 3단계 —
/// board a-one-pixel-dab-drops-out-by-where-it-lies Q4 (2026-10-25).
const _clipStudioInk = [
  (1.0, (0.50, 0.52, 0.48)),
  (1.5, (0.71, 0.74, 0.71)),
  (2.0, (1.00, 0.97, 0.93)),
  (3.0, (1.69, 1.73, 1.73)),
  (4.0, (2.90, 2.53, 2.59)),
  (5.0, (3.93, 3.51, 3.37)),
  (6.0, (4.91, 4.57, 4.34)),
  (8.0, (7.21, 6.68, 6.31)),
  (10.0, (9.14, 8.83, 8.55)),
  (50.0, (48.82, 48.40, 47.92)),
];

/// A G-pen dab of [size] at [step], centred at ([x], [y]).
BrushDab _gPen(BrushAntiAlias step, double size, double x, double y) =>
    BrushDab(
      center: CanvasPoint(x: x, y: y),
      color: 0xFF000000,
      size: size,
      opacity: 1,
      flow: 1,
      hardness: 1,
      pressure: 1,
      sequence: 0,
      tipShape: BrushTipShape.round,
      antiAlias: step,
    );

/// [first] to [last] laid by the interpolator the canvas uses at the
/// roster's finest spacing, resolved through the stamp cache and landed on
/// an empty surface of [width] × [height].
BitmapSurface _laid(BrushDab first, BrushDab last, int width, int height) {
  final dabs = [
    first,
    ...const BrushDabInterpolator().interpolate(
      previous: first,
      nextRaw: last,
      firstSequence: 1,
      spacingRatio: 0.01,
    ),
  ];
  return materializeBrushDabSequenceOnBitmapSurface(
    surface: BitmapSurface(
      canvasSize: CanvasSize(width: width, height: height),
      tileSize: 64,
    ),
    sequence: BrushDabSequence(BrushTipStampCache().resolveDabs(dabs)),
  ).surface;
}

/// The mean ink of a column of a near-level G-pen line of [size] at
/// [step], over four sub-pixel phases and two slopes.
double _ink(BrushAntiAlias step, double size) {
  const width = 220;
  const height = 160;
  var sum = 0.0;
  var count = 0;
  for (final phase in [0.0, 0.25, 0.5, 0.75]) {
    for (final degrees in [0.0, 1.7]) {
      final angle = degrees * math.pi / 180.0;
      BrushDab at(double t) => _gPen(
        step,
        size,
        width / 2 + t * math.cos(angle) + 0.137,
        height / 2 + t * math.sin(angle) + phase,
      );
      final surface = _laid(at(-90), at(90), width, height);
      for (var x = 50; x < width - 50; x += 1) {
        for (var y = 0; y < height; y += 1) {
          sum += ((surfacePixelRgba(surface, x, y) ?? 0) & 0xFF) / 255.0;
        }
        count += 1;
      }
    }
  }
  return sum / count;
}

/// A straight G-pen line at -62° ([_laid]), its alpha row by row on a
/// square canvas that holds its middle rows clear of its caps — 200 a side
/// up to size 50.
List<int> _line(BrushAntiAlias step, {double size = 10}) {
  final reach = math.max(60.0, size * 0.8);
  final side = math.max(200, (2 * (0.883 * reach + size / 2) + 20).ceil());
  BrushDab at(double t) {
    const angle = -62.0 * math.pi / 180.0;
    return _gPen(
      step,
      size,
      side / 2 + t * math.cos(angle) + 0.137,
      side / 2 + t * math.sin(angle) + 0.291,
    );
  }

  final surface = _laid(at(-reach), at(reach), side, side);
  return [
    for (var y = 0; y < side; y += 1)
      for (var x = 0; x < side; x += 1)
        (surfacePixelRgba(surface, x, y) ?? 0) & 0xFF,
  ];
}

/// The edge profile of a line [_line] drew — mean coverage against the
/// distance outward from each row's half-coverage crossing, both sides,
/// over the middle of the line — and the median width at half coverage.
({Map<int, double> profile, double width}) _profile(List<int> alpha) {
  const bin = 0.125;
  const sinTheta = 0.8829475928589269; // sin 62°
  final side = math.sqrt(alpha.length).round();
  final sum = <int, double>{};
  final count = <int, int>{};
  final widths = <double>[];
  for (var y = side ~/ 2 - 30; y <= side ~/ 2 + 30; y += 1) {
    final row = alpha.sublist(y * side, (y + 1) * side);
    final inked = [
      for (var x = 0; x < side; x += 1)
        if (row[x] > 0) x,
    ];
    if (inked.isEmpty) continue;
    double? left;
    double? right;
    for (var x = inked.first; x <= inked.last; x += 1) {
      if (row[x] >= 127.5) {
        final before = row[x - 1].toDouble();
        left = x - 0.5 + (127.5 - before) / (row[x] - before);
        break;
      }
    }
    for (var x = inked.last; x >= inked.first; x -= 1) {
      if (row[x] >= 127.5) {
        final after = row[x + 1].toDouble();
        right = x + 1.5 - (127.5 - after) / (row[x] - after);
        break;
      }
    }
    if (left == null || right == null) continue;
    widths.add((right - left) * sinTheta);
    for (var x = inked.first - 2; x <= inked.last + 2; x += 1) {
      final centre = x + 0.5;
      final d = centre < (left + right) / 2
          ? (left - centre) * sinTheta
          : (centre - right) * sinTheta;
      if (d.abs() > 5) continue;
      final b = (d / bin).floor();
      sum[b] = (sum[b] ?? 0) + row[x] / 255.0;
      count[b] = (count[b] ?? 0) + 1;
    }
  }
  widths.sort();
  return (
    profile: {for (final b in sum.keys) b: sum[b]! / count[b]!},
    width: widths[widths.length ~/ 2],
  );
}

/// Where the profile first falls below [level], walking outward.
double _crossing(Map<int, double> profile, double level) {
  const bin = 0.125;
  final bins = profile.keys.toList()..sort();
  for (var i = 1; i < bins.length; i += 1) {
    final a = profile[bins[i - 1]]!;
    final b = profile[bins[i]]!;
    if (a >= level && b < level) {
      final da = (bins[i - 1] + 0.5) * bin;
      final db = (bins[i] + 0.5) * bin;
      return da + (a - level) / (a - b) * (db - da);
    }
  }
  return double.nan;
}

void main() {
  for (final MapEntry(key: size, value: row) in _clipStudio.entries) {
    for (final MapEntry(key: step, value: target) in row.entries) {
      test('AA ${step.name}: the edge Clip Studio draws at size '
          '${size.toInt()}', () {
        final p = _profile(_line(step, size: size.toDouble())).profile;
        final tenToNinety = _crossing(p, 0.1) - _crossing(p, 0.9);
        final full = _crossing(p, 1 / 255) - _crossing(p, 254 / 255);
        // Landed 2026-10-25 (Q5's refit) at 0.87/1.34 · 1.08/1.97 ·
        // 1.29/2.29 (size 10), 0.90/1.36 · 1.32/2.32 · 1.66/2.65 (50),
        // 0.94/1.51 · 1.67/2.71 · 2.09/3.26 (100) and 1.05/1.84 · 1.81/2.85
        // · 2.45/3.74 (300).
        expect(tenToNinety, closeTo(target.tenToNinety, 0.16));
        expect(full, closeTo(target.full, 0.4));
      });
    }
  }

  for (final (size, row) in _clipStudioInk) {
    test('🚨the ink Clip Studio\'s line lays at size $size, at every step',
        () {
      final steps = [
        (BrushAntiAlias.low, row.$1),
        (BrushAntiAlias.medium, row.$2),
        (BrushAntiAlias.high, row.$3),
      ];
      for (final (step, target) in steps) {
        expect(_ink(step, size), closeTo(target, 0.3), reason: step.name);
      }
    });
  }

  test('🚨the ramp grows INWARD: each step up narrows the half-coverage '
      'width, as Clip Studio\'s lines do', () {
    final widths = [
      for (final step in [
        BrushAntiAlias.low,
        BrushAntiAlias.medium,
        BrushAntiAlias.high,
      ])
        _profile(_line(step)).width,
    ];
    for (var i = 1; i < widths.length; i += 1) {
      expect(widths[i], lessThan(widths[i - 1]), reason: 'step ${i + 1}');
    }
    expect(
      widths.last,
      lessThan(9.5),
      reason: 'at AA 3 the half-coverage width sits inside the nib, as Clip '
          'Studio\'s (8.55) does — a ramp centred on the rim drew it wider',
    );
    expect(
      _profile(_line(BrushAntiAlias.none)).width,
      closeTo(10, 0.5),
      reason: '없음 is the nib at its size',
    );
  });
}
