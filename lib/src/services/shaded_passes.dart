import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show immutable;

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

/// A camera lens blur's Iris Properties, as Adobe's help names them (read
/// 2026-10-28): its Shape's [sides], its [roundness] (0…1), its [aspect] —
/// how wide it is to how tall — its [rotation], clockwise in radians, and
/// its Diffraction [fringe] (0…500).
typedef IrisProperties = ({
  int sides,
  double roundness,
  double aspect,
  double rotation,
  double fringe,
});

/// What of a blur map's pixel a camera lens blur reads — AE's Channel:
/// its luma, or one of its channels, as the weights [r], [g], [b] and [a]
/// of its premultiplied red, green, blue and alpha.
enum IrisMapChannel {
  luminance(0.2126, 0.7152, 0.0722, 0),
  red(1, 0, 0, 0),
  green(0, 1, 0, 0),
  blue(0, 0, 1, 0),
  alpha(0, 0, 0, 1);

  const IrisMapChannel(this.r, this.g, this.b, this.a);

  final double r;
  final double g;
  final double b;
  final double a;
}

/// How a camera lens blur reads a blur map: its [channel], and the value
/// of it (0…255) that is in focus — its Blur Focal Distance. Each pixel's
/// radius is the blur's times how far its map's value, or the inverse of
/// it where it [inverts], lies from [focal], over 255.
typedef IrisMap = ({IrisMapChannel channel, double focal, bool inverts});

/// What a camera lens blur's table of its iris's rows is laid of
/// (`iris_table.frag`), and all it is laid of: its [radius], its iris's
/// shape — [sides], [roundness], [aspect], [rotation] — and where it reads
/// a blur map its [levels]: the map's focal distance and whether it
/// inverts. Its fringe, paper, light and the map's channel are the gather's.
typedef IrisRows = ({
  double radius,
  int sides,
  double roundness,
  double aspect,
  double rotation,
  ({double focal, bool inverts})? levels,
});

/// A camera lens blur's iris gathered out of its row sums
/// (`shaders/iris_gather.frag`, after [RowSumPass]es): every pixel the
/// mean of the pixels the iris covers about it — the ones of each row two
/// reads of its sums. Its rows are laid by the GPU (`iris_table.frag`):
/// the iris [radius] raster pixels out, as its [iris] shapes it, at one
/// level, or — where it reads a blur [map] — at each of the map's 256.
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
    required this.radius,
    required this.iris,
    required this.paper,
    required this.light,
    this.map,
  });

  final double radius;
  final IrisProperties iris;
  final ui.Rect? paper;
  final LensLight? light;
  final IrisMap? map;

  /// How many rows the iris spans either way of its pixel, at the most.
  int get reach => radius.floor();

  /// What its table of rows is laid of ([IrisRows]).
  IrisRows get rows => (
    radius: radius,
    sides: iris.sides,
    roundness: iris.roundness,
    aspect: iris.aspect,
    rotation: iris.rotation,
    levels: switch (map) {
      final map? => (focal: map.focal, inverts: map.inverts),
      null => null,
    },
  );

  /// This pass reading no blur map: every pixel at the whole [radius] —
  /// where the row it reads is none to what draws it.
  IrisGatherPass get unmapped => map == null
      ? this
      : IrisGatherPass(radius: radius, iris: iris, paper: paper, light: light);

  @override
  bool operator ==(Object other) =>
      other is IrisGatherPass &&
      other.radius == radius &&
      other.iris == iris &&
      other.paper == paper &&
      other.light == light &&
      other.map == map;

  @override
  int get hashCode => Object.hash(radius, iris, paper, light, map);

  @override
  String toString() =>
      'IrisGatherPass(radius: $radius, iris: $iris, paper: $paper, '
      'light: $light, map: $map)';
}
