import 'dart:math' as math;

import 'package:flutter/foundation.dart' show immutable;

/// One raster of a blur along a way through every pixel: each the average
/// of [taps] samples along it, centred on it (`shaders/directional_blur.frag`)
/// — a line's, [stepX], [stepY] raster pixels apart (a directional blur),
/// or, about ([centerX], [centerY]) in raster pixels, a circle's [turn]
/// radians apart (a spin) or a ray's [grow] apart in the log of the way out
/// (a zoom).
///
/// ⛔ONE KIND OF PASS: a line, a circle and a ray are each a way a tap
/// steps by the same map — a shift, a turn, a scale about the centre — so
/// one shader walks all three, and one plan ([lineBoxPlan]) lays their
/// passes.
@immutable
class LineBoxPass {
  const LineBoxPass({
    this.stepX = 0,
    this.stepY = 0,
    this.turn = 0,
    this.grow = 0,
    this.centerX = 0,
    this.centerY = 0,
    required this.taps,
  });

  final double stepX;
  final double stepY;
  final double turn;
  final double grow;
  final double centerX;
  final double centerY;
  final int taps;

  @override
  bool operator ==(Object other) =>
      other is LineBoxPass &&
      other.stepX == stepX &&
      other.stepY == stepY &&
      other.turn == turn &&
      other.grow == grow &&
      other.centerX == centerX &&
      other.centerY == centerY &&
      other.taps == taps;

  @override
  int get hashCode =>
      Object.hash(stepX, stepY, turn, grow, centerX, centerY, taps);

  @override
  String toString() =>
      'LineBoxPass($stepX, $stepY, turn: $turn, grow: $grow, '
      'about: ($centerX, $centerY), $taps)';
}

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
/// further apart than a pixel.
({int passes, int taps}) lineBoxPlan(double length, {int? most}) {
  var passes = 1;
  while (math.pow(lineBoxTapsAPass, passes) < length &&
      (most == null || passes < most)) {
    passes += 1;
  }
  final taps = (math.pow(length, 1 / passes) as double).ceil().clamp(
    1,
    lineBoxTapsAPass,
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
