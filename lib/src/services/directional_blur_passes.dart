import 'dart:math' as math;

import 'package:flutter/foundation.dart' show immutable;

/// One raster of a directional blur: every pixel the average of [taps]
/// samples [stepX], [stepY] raster pixels apart along its line, centred on
/// it (`shaders/directional_blur.frag`).
@immutable
class LineBoxPass {
  const LineBoxPass({
    required this.stepX,
    required this.stepY,
    required this.taps,
  });

  final double stepX;
  final double stepY;
  final int taps;

  @override
  bool operator ==(Object other) =>
      other is LineBoxPass &&
      other.stepX == stepX &&
      other.stepY == stepY &&
      other.taps == taps;

  @override
  int get hashCode => Object.hash(stepX, stepY, taps);

  @override
  String toString() => 'LineBoxPass($stepX, $stepY, $taps)';
}

/// The most taps one pass takes — the shader's loop bound.
const int lineBoxTapsAPass = 32;

/// A box [length] raster pixels long along ([dx], [dy]), a unit vector, as
/// the passes that make it: every pixel the average of the line through
/// it, [length] across and centred on it.
///
/// 📐N TAPS A PASS, EACH PASS N TIMES THE STEP OF THE ONE BEFORE: p passes
/// land N^p taps `length / N^p` apart across the length, each once — a box
/// of N^p samples for p·N a pixel. The fewest passes whose taps reach a
/// sample every pixel, so no length leaves a gap between two: a blur of
/// 500 pixels is two passes of 23, one of 2000 (a zoomed raster's) three
/// of 13.
List<LineBoxPass> directionalBlurPasses({
  required double dx,
  required double dy,
  required double length,
}) {
  var passes = 1;
  while (math.pow(lineBoxTapsAPass, passes) < length) {
    passes += 1;
  }
  final taps = (math.pow(length, 1 / passes) as double).ceil().clamp(
    1,
    lineBoxTapsAPass,
  );
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
