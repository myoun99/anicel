import 'dart:math' as math;

import '../models/brush_dab.dart';
import '../models/pasteboard_bounds.dart';
import 'brush_dab_kernel.dart';

/// 🗣️I-75 흐리기 — THE LAW EVERY ROUTE THAT LAYS A BLUR STROKE RUNS: the
/// live display, the pen-up landing and the stroke re-derived from its dabs
/// (the commit after the cel moved, 확정 on another cel) all reach it
/// through the one `BrushLiveStrokeRasterizer` that holds the stroke.
///
/// ⛔NOT THE PAINT LAW. A painting stroke piles its dabs on an EMPTY buffer
/// and composites it once (`brushCommitResultForBrushDabSequenceOnBitmapSurface`).
/// A blur has nothing to pile: 유저 Q4 「문지를수록 더 흐려짐」 asks every dab to
/// read the picture the dabs before it left. So the stroke holds a COPY of
/// the cel where it has been, and each dab rewrites it in place:
///
///     picture ← picture + (blurred(picture) − picture) × laid
///
/// - `laid` is what the dab would have laid as paint onto nothing — its
///   flow, pressure, hardness, texture and spacing share — MEASURED by the
///   dab's own plan, opaque ([coverageOf]), so a blur brush answers every
///   brush setting the way a paint brush does with no second copy of the
///   coverage law (Q3: no slider of its own).
/// - `blurred` is the picture smoothed at a radius the brush's size sets
///   (Q3, [blurRadiusOf]) — three box passes along each axis, the usual
///   stand-in for a Gaussian, so one tap leaves a round mark rather than a
///   square one. All three along the rows first, then all three along the
///   columns: that order is part of the law (each pass rounds).
/// - PREMULTIPLIED, so a transparent pixel carries no colour into its
///   neighbours: a line blurred over nothing fades, it does not darken.
/// - Integers throughout (16-bit planes, means rounded half up, moves
///   rounded half away from zero), so the kernel is pinned byte for byte
///   (dab/blur_tests.rs).
/// - No channel ever passes its alpha, with nothing holding it there: a
///   rounded mean of premultiplied pixels keeps every channel at or under
///   its alpha, and a channel and its alpha moved by one share toward a
///   blur that keeps that order land — each rounded to nearest — in that
///   order still. A cap would be code that cannot run (I-75 뮤턴트 M9).
///
/// The tool's OPACITY and the SELECTION are not here: they cap how far the
/// finished picture may move from the cel, exactly as they cap a paint
/// stroke's accumulated buffer (the landing's opacity and mask).
///
/// THE STROKE IS THE ENGINE'S (flip lane ⓒ — dab/blur.rs, on the stroke's
/// own pages). ↩️Till 2026-11-14 the passes ran here too, off the engine's
/// grid — a Dart copy of the kernel the engine was held to; that grid is
/// refused now (board `the-off-engine-cpu-commit-lives-only-for-tests`).
abstract final class BrushBlurPicture {
  /// The radius of each box pass for [dab]: a sixth of its size, so the
  /// blur's reach (3r) is the dab's own radius and its spread
  /// (σ ≈ √(r(r+1))) a third of it — the brush's own size sets how far it
  /// smears (I-75 설계: 「흐림 반경 = 붓 반지름」), and a dab smears what lies
  /// under it rather than pulling colour in from beyond its edge.
  static int blurRadiusOf(BrushDab dab) => math.max(1, (dab.size / 6).round());

  /// [dab] as the dab kernel lays it onto nothing — what its blur moves
  /// the picture by — or null where it lays nothing.
  static BrushDabPlan? coverageOf(
    BrushDab dab, {
    required PasteboardWall wall,
    required int tileSize,
  }) => BrushDabPlan.of(
    // The colour is not this dab's to lay; opaque, so what it measures is
    // its coverage alone.
    dab.copyWith(color: 0xFFFFFFFF, erase: false),
    wall: wall,
    tileSize: tileSize,
    erase: false,
  );
}
