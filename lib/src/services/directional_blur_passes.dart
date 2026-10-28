import 'dart:math' as math;

import 'shaded_passes.dart';

/// The most taps one pass takes — the shader's loop bound.
const int lineBoxTapsAPass = 32;

/// How a box [length] raster pixels long is laid in passes: how many, and
/// the taps each takes.
///
/// 📐N TAPS A PASS, EACH PASS N TIMES THE STEP OF THE ONE BEFORE: p passes
/// land N^p taps `length / N^p` apart across the length, each once — a box
/// of N^p samples for p·N a pixel. The fewest passes whose taps reach a
/// sample every pixel, so no length leaves a gap between two: a blur of
/// 500 pixels is two passes of 23, one of 2000 (a zoomed raster's) three
/// of 13. [most] passes at most where given — a draft's one, its taps
/// further apart than a pixel. [tapsAPass] is N at most, the loop bound of
/// the shader the passes run — a row sum's (`rowSumPasses`) takes more.
({int passes, int taps}) lineBoxPlan(
  double length, {
  int? most,
  int tapsAPass = lineBoxTapsAPass,
}) {
  var passes = 1;
  while (math.pow(tapsAPass, passes) < length &&
      (most == null || passes < most)) {
    passes += 1;
  }
  final taps = (math.pow(length, 1 / passes) as double).ceil().clamp(
    1,
    tapsAPass,
  );
  return (passes: passes, taps: taps);
}

/// A box [length] raster pixels long along ([dx], [dy]), a unit vector, as
/// the passes that make it: every pixel the average of the line through
/// it, [length] across and centred on it ([lineBoxPlan]).
List<LineBoxPass> directionalBlurPasses({
  required double dx,
  required double dy,
  required double length,
}) {
  final (:passes, :taps) = lineBoxPlan(length);
  final spacing = length / math.pow(taps, passes);
  return [
    for (var pass = 0; pass < passes; pass += 1)
      LineBoxPass(
        stepX: dx * spacing * math.pow(taps, pass),
        stepY: dy * spacing * math.pow(taps, pass),
        taps: taps,
      ),
  ];
}

/// A radial blur about ([centerX], [centerY]), raster pixels, as the
/// passes that make it: every pixel the average of the arc through it
/// [across] radians long ([spin]), or of the ray through it [across] long
/// in the log of the way out — centred on it, each way — laid as a box is
/// ([lineBoxPlan]), finely enough for a sample every pixel at [farthest]
/// from the centre, the farthest a pixel it blurs lies. A [draft] takes
/// one pass: its taps further apart than a pixel out there, the grain
/// Adobe's help gives a radial blur at Draft.
List<LineBoxPass> radialBlurPasses({
  required double centerX,
  required double centerY,
  required bool spin,
  required double across,
  required double farthest,
  required bool draft,
}) {
  // The longest way a pixel's average runs, in pixels: the arc out there,
  // or the ray — from its pixel drawn in, to the one it reads out farthest.
  final length = spin
      ? across * farthest
      : farthest * (math.exp(across) - 1);
  final (:passes, :taps) = lineBoxPlan(length, most: draft ? 1 : null);
  final spacing = across / math.pow(taps, passes);
  return [
    for (var pass = 0; pass < passes; pass += 1)
      LineBoxPass(
        turn: spin ? spacing * math.pow(taps, pass) : 0,
        grow: spin ? 0 : spacing * math.pow(taps, pass),
        centerX: centerX,
        centerY: centerY,
        taps: taps,
      ),
  ];
}
