// A G-PEN LINE'S EDGE IS CLIP STUDIO'S, STEP FOR STEP (I-50).
//
// 유저 2026-09-30: 「경도와 따로 — 단계마다 고정 폭, 클튜 샘플로 맞춤」, and the
// sample was their own Clip Studio G펜 lines (`参考/brush/cls_gpen_AA.png`,
// size 10 and 50 at every step). The widths in `BrushAntiAlias.edgeWidth`
// were fitted to the size-10 row; THIS is the pin that the fit still holds
// — a line drawn the way the canvas draws one (the interpolator's step, the
// stamp cache, the kernel), measured the way the sample was.
//
// 📏The measure is the slanted-edge method: every row that crosses the edge
// samples the edge profile at a new subpixel phase, so a slanted line gives
// the profile at a fine pitch. The bands are the distance the coverage
// takes to fall from 90% to 10%, and from 254/255 to 1/255.
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

/// Clip Studio's size-10 G펜 row, measured 2026-10-01 by the same method
/// (10–90% band, full band) — board I-50.
const _clipStudio = {
  BrushAntiAlias.low: (tenToNinety: 0.79, full: 1.28),
  BrushAntiAlias.medium: (tenToNinety: 0.97, full: 1.86),
  BrushAntiAlias.high: (tenToNinety: 1.25, full: 2.37),
};

const _side = 200;

/// A straight size-10 G-pen line at -62°, laid by the interpolator the
/// canvas uses at the roster's finest spacing and resolved through the
/// stamp cache, landed on an empty surface.
List<int> _line(BrushAntiAlias step) {
  BrushDab at(double t) {
    const angle = -62.0 * math.pi / 180.0;
    return BrushDab(
      center: CanvasPoint(
        x: _side / 2 + t * math.cos(angle) + 0.137,
        y: _side / 2 + t * math.sin(angle) + 0.291,
      ),
      color: 0xFF000000,
      size: 10,
      opacity: 1,
      flow: 1,
      hardness: 1,
      pressure: 1,
      sequence: 0,
      tipShape: BrushTipShape.round,
      antiAlias: step,
    );
  }

  final first = at(-60);
  final dabs = [
    first,
    ...const BrushDabInterpolator().interpolate(
      previous: first,
      nextRaw: at(60),
      firstSequence: 1,
      spacingRatio: 0.01,
    ),
  ];
  final surface = materializeBrushDabSequenceOnBitmapSurface(
    surface: BitmapSurface(
      canvasSize: const CanvasSize(width: _side, height: _side),
      tileSize: 64,
    ),
    sequence: BrushDabSequence(BrushTipStampCache().resolveDabs(dabs)),
  ).surface;
  return [
    for (var y = 0; y < _side; y += 1)
      for (var x = 0; x < _side; x += 1)
        (surfacePixelRgba(surface, x, y) ?? 0) & 0xFF,
  ];
}

/// The edge profile — mean coverage against the distance outward from each
/// row's half-coverage crossing, both sides, over the middle of the line —
/// and the median width at half coverage.
({Map<int, double> profile, double width}) _profile(List<int> alpha) {
  const bin = 0.125;
  const sinTheta = 0.8829475928589269; // sin 62°
  final sum = <int, double>{};
  final count = <int, int>{};
  final widths = <double>[];
  for (var y = 70; y <= 130; y += 1) {
    final row = alpha.sublist(y * _side, (y + 1) * _side);
    final inked = [
      for (var x = 0; x < _side; x += 1)
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
  for (final step in _clipStudio.keys) {
    test('AA ${step.name}: the edge Clip Studio draws at size 10', () {
      final p = _profile(_line(step)).profile;
      final tenToNinety = _crossing(p, 0.1) - _crossing(p, 0.9);
      final full = _crossing(p, 1 / 255) - _crossing(p, 254 / 255);
      final target = _clipStudio[step]!;
      // Landed 2026-10-01 at 0.79/1.11 · 0.98/2.05 · 1.18/2.54 — the fit is
      // of the whole profile, so neither band is exact on its own.
      expect(tenToNinety, closeTo(target.tenToNinety, 0.1));
      expect(full, closeTo(target.full, 0.25));
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
