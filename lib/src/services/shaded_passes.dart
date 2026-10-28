import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show immutable;

import '../core/collection_equality.dart';

/// One raster of a step a fragment shader draws ([ShadedEffect]): the whole
/// raster at the identity, over the picture the raster before it made
/// (`applyEffectSteps`). A kind is drawn in these when it reads past the
/// pixel and no `ui.ImageFilter` carries it.
@immutable
sealed class ShadedPass {
  const ShadedPass();
}

/// One raster of a blur along a way through every pixel: each the average
/// of [taps] samples along it, centred on it (`shaders/directional_blur.frag`)
/// — a line's, [stepX], [stepY] raster pixels apart (a directional blur),
/// or, about ([centerX], [centerY]) in raster pixels, a circle's [turn]
/// radians apart (a spin) or a ray's [grow] apart in the log of the way out
/// (a zoom).
///
/// ⛔ONE KIND OF PASS: a line, a circle and a ray are each a way a tap
/// steps by the same map — a shift, a turn, a scale about the centre — so
/// one shader walks all three, and one plan (`lineBoxPlan`) lays their
/// passes.
final class LineBoxPass extends ShadedPass {
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

/// How a camera lens blur reads the light it spreads
/// (`shaders/lens_light.glsl`): in [linear] light or as the picture is
/// stored, and every pixel brighter than [threshold] (0…1) boosted by
/// [gain] times how far past it it is, the boost [saturation] (0…1) its
/// own colour and the rest white.
typedef LensLight = ({
  double gain,
  double threshold,
  double saturation,
  bool linear,
});

/// One raster of a ROW SUM: every texel the sum of [taps] texels [stride]
/// apart along its row — itself, then the ones to its left, none past the
/// raster's edge (`shaders/row_sum.frag`). Strides 1, taps, taps², … make
/// each texel the sum of its row up to it (`rowSumPasses`), as a box's
/// passes make its average (`lineBoxPlan`).
///
/// [light] is how the pass reads the texels it sums — the first pass's, of
/// the step's own picture — and null where it sums them as they are.
///
/// 🚨LAID IN FLOATS: a sum runs past 1, and a byte would clamp it.
final class RowSumPass extends ShadedPass {
  const RowSumPass({required this.stride, required this.taps, this.light});

  final int stride;
  final int taps;
  final LensLight? light;

  @override
  bool operator ==(Object other) =>
      other is RowSumPass &&
      other.stride == stride &&
      other.taps == taps &&
      other.light == light;

  @override
  int get hashCode => Object.hash(stride, taps, light);

  @override
  String toString() => 'RowSumPass($stride, $taps, light: $light)';
}

/// The columns about a pixel one row of an iris covers, [left] to [right]
/// — none where [left] is past [right].
typedef IrisSpan = ({int left, int right});

/// A camera lens blur's iris gathered out of its row sums
/// (`shaders/iris_gather.frag`, after [RowSumPass]es): every pixel the
/// weighted mean of the pixels the iris covers about it — the ones of each
/// row two reads of its sums.
///
/// [outline] is the rows the iris covers, [core] the rows of the same iris
/// drawn smaller — the inside a diffraction fringe pushes [fringe] of the
/// light out of, to the edge — each `2 · reach + 1` rows from `-reach`
/// down. [weight] is what every pixel's weights add up to.
///
/// [paper] is the paper on whole pixels where the iris repeats its edge
/// pixels past it — read where it reads past the paper, and cut to it —
/// and null where past the raster there is nothing to read.
///
/// [light] is how its sums read the light ([RowSumPass.light]): the edge
/// pixels it reads are read so too, and what it draws is put back as a
/// picture is stored. Null where the sums are of the picture as it is.
final class IrisGatherPass extends ShadedPass {
  const IrisGatherPass({
    required this.reach,
    required this.outline,
    required this.core,
    required this.fringe,
    required this.weight,
    required this.paper,
    required this.light,
  });

  final int reach;
  final List<IrisSpan> outline;
  final List<IrisSpan> core;

  /// How much of its core's light an iris's edge takes, 0 to 1 — 0 where it
  /// has no fringe, and [core] is then read for nothing.
  final double fringe;
  final double weight;
  final ui.Rect? paper;
  final LensLight? light;

  @override
  bool operator ==(Object other) =>
      other is IrisGatherPass &&
      other.reach == reach &&
      listEquals(other.outline, outline) &&
      listEquals(other.core, core) &&
      other.fringe == fringe &&
      other.weight == weight &&
      other.paper == paper &&
      other.light == light;

  @override
  int get hashCode => Object.hash(
    reach,
    Object.hashAll(outline),
    Object.hashAll(core),
    fringe,
    weight,
    paper,
    light,
  );

  @override
  String toString() =>
      'IrisGatherPass(reach: $reach, fringe: $fringe, weight: $weight, '
      'paper: $paper, light: $light)';
}
