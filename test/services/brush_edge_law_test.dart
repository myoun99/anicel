// WHAT A DAB'S COVERAGE GOES THROUGH AFTER ITS TIP IS SAMPLED.
//
// Two laws share the four steps (I-50, 유저 2026-09-30 「경도와 따로 — 단계마다
// 고정 폭」): an analytic round tip already carries its edge — in its
// profile (`RoundTipProfile`) — and takes its coverage as it is; a square
// keeps the contrast ladder, which tightens the edge WITHOUT moving the
// half-coverage radius (유저 2026-09-08 「굵기 안바꾸고 가장자리만
// 조이는거였어」). 없음 cuts at half coverage whatever the tip.
//
// ↩️A raster tip kept the ladder too, until its greys turned out to be what
// the ladder wiped (board imported-water-blend-lays-almost-nothing,
// 2026-10-30): it takes its coverage as it is, as a round tip does.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_anti_alias.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_tip_mask.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/services/brush_dab_coverage.dart';
import 'package:anicel/src/services/brush_dab_tip_geometry.dart';
import 'package:anicel/src/services/brush_tip_stamp_cache.dart';

void main() {
  BrushDab dab(
    BrushAntiAlias step, {
    BrushTipShape tipShape = BrushTipShape.round,
    BrushTipMask? tipMask,
  }) => BrushDab(
    center: CanvasPoint(x: 10, y: 10),
    color: 0xFF000000,
    size: 9,
    opacity: 1,
    flow: 1,
    hardness: 1,
    pressure: 1,
    sequence: 0,
    tipShape: tipShape,
    antiAlias: step,
    tipMask: tipMask,
  );

  final rasterTip = BrushTipMask(
    id: 'raster',
    size: 4,
    alpha: Uint8List.fromList(List.filled(16, 200)),
  );

  /// [coverage] as a square dab at [step] lands it.
  double ladder(BrushAntiAlias step, double coverage) => brushEdgeApplied(
    brushDabEdgeLaw(dab(step, tipShape: BrushTipShape.square)),
    coverage,
  );

  group('which law a dab takes', () {
    test('an analytic round tip takes its coverage as it is at every step '
        'but 없음 — its edge is in its ramp', () {
      for (final step in [
        BrushAntiAlias.low,
        BrushAntiAlias.medium,
        BrushAntiAlias.high,
      ]) {
        final law = brushDabEdgeLaw(dab(step));
        expect(law.threshold, isFalse, reason: '$step');
        expect(law.contrast, 1.0, reason: '$step');
      }
    });

    test('a RESOLVED round dab is not baked — its edge stays in its profile, '
        'and it takes its coverage as it is', () {
      final resolved = BrushTipStampCache().resolveDab(dab(BrushAntiAlias.low));
      expect(resolved.tipMask, isNull, reason: 'premise');
      final law = brushDabEdgeLaw(resolved);
      expect(law.threshold, isFalse);
      expect(law.contrast, 1.0);
    });

    test('a round tip has a profile per STEP — the step is part of the tip',
        () {
      final low = brushDabTipGeometry(dab(BrushAntiAlias.low)).profile!;
      final high = brushDabTipGeometry(dab(BrushAntiAlias.high)).profile!;
      expect(low, isNot(same(high)));
      expect(low.coverage, isNot(high.coverage));
    });

    test('a raster tip takes its coverage as it is at every step but 없음 — '
        'resolved or not', () {
      for (final step in [BrushAntiAlias.low, BrushAntiAlias.medium]) {
        final raw = dab(step, tipMask: rasterTip);
        final resolved = BrushTipStampCache().resolveDab(raw);
        expect(resolved.tipMask, same(rasterTip), reason: 'premise');
        expect(brushDabEdgeLaw(raw).contrast, 1.0, reason: '$step');
        expect(
          brushDabEdgeLaw(resolved).contrast,
          1.0,
          reason: '$step resolved',
        );
      }
    });

    test('🚨a pale tip is not wiped — its greys are its picture, not an edge',
        () {
      // Clip Studio's 수채 섞기 at 1단계: the ladder took every grey under
      // 0.375 to nothing, and its tip peaks at 0.63 and averages 0.05.
      const grey = 64;
      final pale = BrushTipMask(
        id: 'pale',
        size: 4,
        alpha: Uint8List.fromList(List.filled(16, grey)),
      );
      for (final step in [
        BrushAntiAlias.low,
        BrushAntiAlias.medium,
        BrushAntiAlias.high,
      ]) {
        final laid = brushPixelCoveragesForDab(
          dab(step, tipMask: pale),
        ).map((pixel) => pixel.coverage).reduce(math.max);
        expect(laid, closeTo(grey / 255, 0.002), reason: '$step');
      }
    });

    test('a square keeps the ladder — the step never widened its edge', () {
      final raw = dab(BrushAntiAlias.low, tipShape: BrushTipShape.square);
      final resolved = BrushTipStampCache().resolveDab(raw);
      expect(resolved.tipMask, isNotNull, reason: 'premise');
      expect(brushDabEdgeLaw(raw).contrast, 4.0);
      expect(brushDabEdgeLaw(resolved).contrast, 4.0);
    });

    test('없음 cuts whatever the tip', () {
      for (final d in [
        dab(BrushAntiAlias.none),
        dab(BrushAntiAlias.none, tipMask: rasterTip),
        dab(BrushAntiAlias.none, tipShape: BrushTipShape.square),
        BrushTipStampCache().resolveDab(dab(BrushAntiAlias.none)),
      ]) {
        expect(brushDabEdgeLaw(d).threshold, isTrue);
      }
    });
  });

  group('the ladder', () {
    test('3단계 is the ramp a square always had', () {
      for (final coverage in [0.0, 0.13, 0.5, 0.87, 1.0]) {
        expect(ladder(BrushAntiAlias.high, coverage), coverage);
      }
    });

    test('🚨THE HALF-COVERAGE CROSSING DOES NOT MOVE', () {
      // ⛔The alpha-threshold shape the user ruled out fails exactly here —
      // raising its cut pushes the crossing inward.
      for (final step in BrushAntiAlias.values) {
        expect(ladder(step, 0.51), greaterThan(0.5), reason: '$step inside');
        expect(ladder(step, 0.49), lessThan(0.5), reason: '$step outside');
      }
      // The scaling steps hold 0.5 as an exact fixed point; 없음 is the one
      // discontinuity, and it resolves the tie by painting (`>=`), which is
      // what makes it a HARD edge rather than a half-lit ring.
      for (final step in [
        BrushAntiAlias.high,
        BrushAntiAlias.medium,
        BrushAntiAlias.low,
      ]) {
        expect(ladder(step, 0.5), 0.5, reason: '$step fixes the half point');
      }
      expect(ladder(BrushAntiAlias.none, 0.5), 1.0);
    });

    test('it tightens, step by step', () {
      const soft = 0.6;
      final ramp = [
        ladder(BrushAntiAlias.high, soft),
        ladder(BrushAntiAlias.medium, soft),
        ladder(BrushAntiAlias.low, soft),
        ladder(BrushAntiAlias.none, soft),
      ];
      expect(ramp[0], closeTo(0.6, 1e-12));
      expect(ramp[1], closeTo(0.7, 1e-12));
      expect(ramp[2], closeTo(0.9, 1e-12));
      expect(ramp[3], 1.0);
    });

    test('없음 is a hard cut', () {
      expect(ladder(BrushAntiAlias.none, 0.49), 0.0);
      expect(ladder(BrushAntiAlias.none, 0.5), 1.0);
    });

    test('the output never leaves the unit interval', () {
      for (final step in BrushAntiAlias.values) {
        for (var i = 0; i <= 20; i += 1) {
          expect(
            ladder(step, i / 20),
            inInclusiveRange(0.0, 1.0),
            reason: '$step at ${i / 20}',
          );
        }
      }
    });
  });
}
