// A BRUSH PILES THE SAME AT EVERY SIZE (유저 2026-10-01
// `one-pixel-steps-change-a-brush-with-its-size`: Q1 「엔진이 쌓임을 환산 —
// 크기와 무관하게(클튜처럼)」, Q2 「환산은 커널에서 — 모든 브러시」).
//
// The interpolator lays dabs no closer than a pixel, so a big brush lays
// far more of them across its width than a small one: the same flow piled
// darker, and its ramps harder, the bigger the brush. A dab now lays its
// share of one stamp per tenth of its size (`stampShareOf`), in the kernel,
// on the laid alpha.
//
// 🧪THE CONTROL IS BUILT IN: a dab with no `pathStep` lays whole, which is
// exactly how every dab laid before, so each pin draws the same line both
// ways and the old way has to show the problem it fixes.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/brush_anti_alias.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_dab_sequence.dart';
import 'package:anicel/src/models/brush_settings.dart';
import 'package:anicel/src/models/brush_shape.dart';
import 'package:anicel/src/models/brush_tip_mask.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/services/bitmap_surface_brush_commit.dart';
import 'package:anicel/src/services/brush_dab_interpolator.dart';
import 'package:anicel/src/services/brush_dab_share.dart';
import 'package:anicel/src/services/brush_preset_defaults.dart';
import 'package:anicel/src/services/brush_tip_mask_defaults.dart';
import 'package:anicel/src/services/brush_tip_stamp_cache.dart';
import 'package:anicel/src/services/canvas_color_sampler.dart';
import 'package:anicel/src/ui/brush/brush_stroke_preview_cache.dart';

BrushDab _dab(
  double x,
  double size, {
  double hardness = 0.0,
  double flow = 0.3,
  BrushTipMask? tipMask,
  BrushTipMask? textureMask,
  BrushAntiAlias antiAlias = BrushAntiAlias.high,
}) => BrushDab(
  center: CanvasPoint(x: x, y: 200.3),
  color: 0xFF000000,
  size: size,
  opacity: 1,
  flow: flow,
  hardness: hardness,
  pressure: 1,
  sequence: 0,
  tipShape: BrushTipShape.round,
  tipMask: tipMask,
  textureMask: textureMask,
  antiAlias: antiAlias,
);

/// A straight line across the middle of a 400px canvas, laid by the canvas's
/// interpolator at the finest spacing; [evened] false strips the path step
/// the interpolator wrote, which is how every dab laid before.
List<BrushDab> _line(
  double size, {
  required bool evened,
  double flow = 0.3,
  double hardness = 0.0,
  BrushTipMask? tipMask,
  BrushTipMask? textureMask,
  BrushAntiAlias antiAlias = BrushAntiAlias.high,
}) {
  BrushDab at(double x) => _dab(
    x,
    size,
    flow: flow,
    hardness: hardness,
    tipMask: tipMask,
    textureMask: textureMask,
    antiAlias: antiAlias,
  );
  final first = at(40.2);
  final rest = const BrushDabInterpolator().interpolate(
    previous: first,
    nextRaw: at(360.2),
    firstSequence: 1,
    spacingRatio: 0.01,
  );
  return [
    first,
    for (final dab in rest)
      if (evened) dab else BrushDab.fromJson(dab.toJson()..remove('pathStep')),
  ];
}

/// The strongest alpha across the line at its middle.
double _pile(List<BrushDab> dabs) {
  final surface = materializeBrushDabSequenceOnBitmapSurface(
    surface: BitmapSurface(
      canvasSize: const CanvasSize(width: 400, height: 400),
      tileSize: 64,
    ),
    sequence: BrushDabSequence(BrushTipStampCache().resolveDabs(dabs)),
  ).surface;
  var strongest = 0;
  for (var y = 100; y < 300; y += 1) {
    strongest = math.max(
      strongest,
      (surfacePixelRgba(surface, 200, y) ?? 0) & 0xFF,
    );
  }
  return strongest / 255.0;
}

void main() {
  test('🚨a soft round brush piles the same at every size — and did not', () {
    // Flow 0.1: low enough that the old way does not saturate.
    const sizes = [10.0, 20.0, 50.0, 160.0];
    final before = [
      for (final s in sizes) _pile(_line(s, evened: false, flow: 0.1)),
    ];
    final now = [
      for (final s in sizes) _pile(_line(s, evened: true, flow: 0.1)),
    ];
    expect(
      before.last - before.first,
      greaterThan(0.3),
      reason: 'premise: the same flow piled darker the bigger the brush '
          '(${before.map((p) => p.toStringAsFixed(3))})',
    );
    expect(
      now.first,
      before.first,
      reason: 'a size-10 brush already lays a dab a tenth apart — its bytes '
          'stay',
    );
    for (var i = 1; i < sizes.length; i += 1) {
      expect(
        now[i],
        closeTo(now.first, 0.03),
        reason: 'size ${sizes[i]} against ${sizes.first}: '
            '${now.map((p) => p.toStringAsFixed(3))}',
      );
    }
  });

  test('🚨every tip piles the same at every size — a raster tip, a papered '
      'one and the edge set to none alike', () {
    // 「모든 브러시」: the share is read on the laid alpha after the whole
    // coverage cascade, so no kind of tip is left out. ↩️The first try baked
    // it into the round tip's table and could not reach these.
    final cases = <String, List<BrushDab> Function(double size, bool evened)>{
      'raster': (size, evened) => _line(
        size,
        evened: evened,
        flow: 0.03,
        tipMask: chalkBrushTipMask,
      ),
      'papered': (size, evened) => _line(
        size,
        evened: evened,
        flow: 0.03,
        textureMask: paperGrainTextureMask,
      ),
      'AA none': (size, evened) => _line(
        size,
        evened: evened,
        flow: 0.03,
        hardness: 1,
        antiAlias: BrushAntiAlias.none,
      ),
    };
    for (final MapEntry(key: name, value: line) in cases.entries) {
      final before = [_pile(line(20, false)), _pile(line(120, false))];
      final now = [_pile(line(20, true)), _pile(line(120, true))];
      expect(
        before.last - before.first,
        greaterThan(0.15),
        reason: '$name, premise: it piled darker the bigger it was ($before)',
      );
      expect(
        now.last,
        closeTo(now.first, 0.05),
        reason: '$name: $now',
      );
    }
  });

  test('every preset that lays a share at its own size lays there what it '
      'laid before', () {
    // The flows before a dab laid its share (2026-10-01, after F-218): what
    // one dab a pixel apart laid. A preset's flow now says what one stamp
    // per tenth of its size lays, so at its own size its share of that must
    // lay the old amount.
    const before = {
      'builtin-soft-brush': 0.394,
      'builtin-marker': 0.436,
      'builtin-crayon': 0.8,
      'builtin-graphite-stick': 0.75,
      'builtin-watercolor': 0.265,
      'builtin-analog-watercolor': 0.18,
      'builtin-wet-watercolor': 0.35,
      'builtin-dense-watercolor': 0.716,
      'builtin-flat-wash': 0.207,
      'builtin-flat-bristle': 0.75,
      'builtin-gouache': 0.853,
      'builtin-oil-brush': 0.9,
      'builtin-dry-brush': 0.75,
      'builtin-airbrush': 0.062,
      'builtin-grit-spray': 0.3,
      'builtin-blender': 0.7,
      'builtin-water-blend': 0.3,
      'builtin-blending-stump': 0.4,
      'builtin-hatching': 0.9,
      'builtin-concrete': 0.85,
    };
    final byId = {for (final p in defaultBrushPresets) p.id.value: p};
    for (final preset in defaultBrushPresets) {
      final s = preset.settings;
      final step = const BrushDabInterpolator().spacingForBrushSize(
        s.size,
        s.spacing,
      );
      final share = stampShareOf(_dab(0, s.size).copyWith(pathStep: step));
      final old = before[preset.id.value];
      if (old == null) {
        expect(
          share >= 1.0 || s.flow >= 1.0,
          isTrue,
          reason: '${preset.id.value} lays a share at its own size and is not '
              'in the table',
        );
        continue;
      }
      expect(share, lessThan(1.0), reason: '${preset.id.value} lays a share');
      expect(
        1 - math.pow(1 - byId[preset.id.value]!.settings.flow, share),
        closeTo(old, 0.0005),
        reason: '${preset.id.value} at ${s.size}px',
      );
    }
  });

  test('the swatch piles the same at every row height — it lays its dabs '
      'as the canvas does', () {
    // A swatch's nib is 0.62 of its row: a 40px row draws a 25px nib and a
    // 140px row an 87px one, both about a pixel a dab.
    final settings = BrushSettings(
      size: 40,
      hardness: 0,
      flow: 0.1,
      spacing: BrushShape.minSpacing,
    );
    double strongest(int height) =>
        rasterizeBrushStrokeSample(settings, height * 3, height).reduce(
          math.max,
        ) /
        255.0;
    expect(strongest(140), closeTo(strongest(40), 0.1));
  });

  group('who lays whole', () {
    test('a dab with no path step — a tap, the dab that opens a stroke', () {
      expect(stampShareOf(_dab(10, 50)), 1.0);
      expect(eveningTableOf(_dab(10, 50)), isNull);
    });

    test('a dab already a tenth of its size apart or more — a dotted brush '
        'keeps its dots', () {
      for (final step in [5.0, 12.0, 75.0]) {
        expect(
          stampShareOf(_dab(10, 50).copyWith(pathStep: step)),
          1.0,
          reason: 'step $step',
        );
      }
    });

    test('anything closer lays its share, quantized so the tables repeat', () {
      expect(
        stampShareOf(_dab(10, 50).copyWith(pathStep: 1.0)),
        (0.2 * shareSteps).round() / shareSteps,
      );
      expect(
        stampShareOf(_dab(10, 50).copyWith(pathStep: 1.3)),
        (0.26 * shareSteps).round() / shareSteps,
      );
      expect(
        identical(
          eveningTableOf(_dab(10, 50).copyWith(pathStep: 1.0)),
          eveningTableOf(_dab(20, 50).copyWith(pathStep: 1.0)),
        ),
        isTrue,
        reason: 'one share, one table',
      );
    });
  });

  group('the evening table', () {
    test('lays nothing for nothing and all for all', () {
      final table = eveningTableFor(0.1);
      expect(evenedLaid(table, 0.0), 0.0);
      expect(evenedLaid(table, 1.0), 1.0);
    });

    test('ten dabs of share 0.1 pile up as one dab — to a thousandth', () {
      final table = eveningTableFor(0.1);
      for (final whole in [0.02, 0.1, 0.3, 0.6, 0.9]) {
        var pile = 0.0;
        for (var i = 0; i < 10; i += 1) {
          final laid = evenedLaid(table, whole);
          pile = laid + pile * (1.0 - laid);
        }
        expect(pile, closeTo(whole, 1e-3), reason: 'whole $whole');
      }
    });

    test('reads between its entries linearly, never past the last', () {
      final table = eveningTableFor(0.5);
      const a = 0.25 + 0.5 / eveningTableSteps;
      final i = (a * eveningTableSteps).toInt();
      expect(
        evenedLaid(table, a),
        table[i] + (table[i + 1] - table[i]) * 0.5,
      );
      expect(evenedLaid(table, 1.5), table[eveningTableSteps]);
    });
  });

  test('a dab reads its path step back', () {
    final dab = _dab(10, 50).copyWith(pathStep: 1.5);
    expect(BrushDab.fromJson(dab.toJson()), dab);
    expect(BrushDab.fromJson(dab.toJson()).pathStep, 1.5);
  });

  test('the interpolator writes what each dab really stands for', () {
    // 11 px laid at a 2 px step: six dabs of 11/6 px each, not of 2 px.
    final dabs = const BrushDabInterpolator().interpolate(
      previous: _dab(0, 200),
      nextRaw: _dab(11, 200),
      firstSequence: 1,
      spacingRatio: 0.01,
    );
    expect(dabs, hasLength(6));
    for (final dab in dabs) {
      expect(dab.pathStep, closeTo(11 / 6, 1e-12));
    }
  });

  test('a table is the same numbers wherever it is built', () {
    // Both kernels read the table Dart built; the guard here is only that a
    // rebuilt table (after the cache let it go) is the same one.
    final first = Float64List.fromList(eveningTableFor(0.3));
    for (var share = 1; share < 200; share += 1) {
      eveningTableFor(share / shareSteps);
    }
    expect(eveningTableFor(0.3), first);
  });
}
