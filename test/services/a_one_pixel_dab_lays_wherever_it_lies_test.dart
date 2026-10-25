// A ONE-PIXEL DAB LAYS WHEREVER IT LIES, AND ITS EDGE DOES NOT PILE
// (board a-one-pixel-dab-drops-out-by-where-it-lies, Q4 — 유저 2026-10-25
// 「AA 가장자리는 쌓이지 않는다」).
//
// A round tip sampled at pixel centres drew nothing where a one-pixel dab
// fell between them, and a line of such dabs beaded and dropped out by
// where it lay. A round tip is read under a pixel's square now
// (`RoundTipProfile`), its edge sets the level a stroke may come up to
// instead of piling (`edgeCeiling`), and a small brush steps a tenth of
// its size (`finestDabStep`) — these pin what each of the three is for.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/brush_anti_alias.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_dab_sequence.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/native/qa_native_engine.dart';
import 'package:anicel/src/services/bitmap_surface_brush_commit.dart';
import 'package:anicel/src/services/brush_dab_coverage.dart';
import 'package:anicel/src/services/brush_dab_interpolator.dart';
import 'package:anicel/src/services/brush_tip_stamp_cache.dart';
import 'package:anicel/src/services/canvas_color_sampler.dart';

BrushDab _dab(
  double x,
  double y, {
  double size = 1,
  double opacity = 1,
  int sequence = 0,
}) => BrushDab(
  center: CanvasPoint(x: x, y: y),
  color: 0xFF000000,
  size: size,
  opacity: opacity,
  flow: 1,
  hardness: 1,
  pressure: 1,
  sequence: sequence,
  tipShape: BrushTipShape.round,
  antiAlias: BrushAntiAlias.high,
);

const _side = 64;

List<int> _alpha(List<BrushDab> dabs) {
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

void main() {
  setUp(() {
    QaNativeEngine.debugResetForTests();
    QaNativeEngine.debugForceDartFallback = true;
  });

  test('🚨a one-pixel dab never drops out — between pixel centres it lays '
      'most of what it lays on one', () {
    // ⚠️Not all of it: the square is read along the radius, which a line's
    // cross-section is exactly and a lone dab only nearly — on a pixel
    // corner it lays 0.31 of a centred dab's 0.48 (2026-10-25). Whether a
    // lone small dab should lay alike everywhere is the board's (Q6).
    final inks = [
      for (var i = 0; i < 10; i += 1)
        for (var j = 0; j < 10; j += 1)
          brushPixelCoveragesForDab(
            _dab(10 + i / 10, 10 + j / 10),
          ).fold(0.0, (sum, c) => sum + c.coverage),
    ];
    final least = inks.reduce(math.min);
    final most = inks.reduce(math.max);
    expect(least, greaterThan(0.3), reason: 'it never drops out');
    expect(least / most, greaterThan(0.6), reason: '$least … $most');
  });

  test('🚨a one-pixel line neither beads nor drops out, wherever it lies',
      () {
    for (final phase in [0.0, 0.25, 0.5, 0.75]) {
      final first = _dab(4, 30 + phase);
      final alpha = _alpha([
        first,
        ...const BrushDabInterpolator().interpolate(
          previous: first,
          nextRaw: _dab(60, 30 + phase),
          firstSequence: 1,
          spacingRatio: 0.01,
        ),
      ]);
      final columns = [
        for (var x = 10; x < 54; x += 1)
          [
            for (var y = 0; y < _side; y += 1) alpha[y * _side + x] / 255.0,
          ].reduce((a, b) => a + b),
      ];
      final mean = columns.reduce((a, b) => a + b) / columns.length;
      expect(mean, greaterThan(0.4), reason: 'at $phase');
      for (final (i, ink) in columns.indexed) {
        expect(
          ink,
          closeTo(mean, 0.05),
          reason: 'column ${i + 10} at phase $phase',
        );
      }
    }
  });

  test('🚨a hard nib laid twenty times over itself is the nib laid once — '
      'its edge does not pile', () {
    final once = _alpha([_dab(30.3, 30.6, size: 9)]);
    final twenty = _alpha([
      for (var i = 0; i < 20; i += 1)
        _dab(30.3, 30.6, size: 9, sequence: i),
    ]);
    expect(once.where((a) => a > 0 && a < 255), isNotEmpty, reason: 'premise');
    expect(twenty, once);
  });

  test('and under an opacity, its edge settles at its share of it', () {
    final once = _alpha([_dab(30.3, 30.6, size: 9)]);
    final twenty = _alpha([
      for (var i = 0; i < 20; i += 1)
        _dab(30.3, 30.6, size: 9, opacity: 0.5, sequence: i),
    ]);
    for (var i = 0; i < once.length; i += 1) {
      expect(
        twenty[i],
        lessThanOrEqualTo((once[i] * 0.5).round() + 1),
        reason: 'pixel ${i % _side}, ${i ~/ _side}',
      );
    }
  });
}
