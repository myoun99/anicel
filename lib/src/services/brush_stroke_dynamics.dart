import 'dart:math' as math;

import '../models/brush_dab.dart';
import '../models/brush_tip_rotation_mode.dart';
import '../models/canvas_point.dart';
import '../ui/canvas/brush_edit_canvas_input_settings.dart';

/// Applies placement-time stroke dynamics — scatter, size/opacity/angle
/// jitter, and direction-following tip rotation — to interpolated dabs.
///
/// Dynamics run once, when dabs are GENERATED: the emitted dabs carry their
/// final randomized values, and since committed source dabs are the durable
/// source of truth, re-rendering (commit, undo/redo) replays exactly the
/// pixels that were on screen. The rasterizers and their parity guarantees
/// are untouched by design.
class BrushStrokeDynamics {
  BrushStrokeDynamics({required this.settings, math.Random? random})
    : _random = random ?? math.Random();

  final BrushEditCanvasInputSettings settings;
  final math.Random _random;

  /// Whether any dynamic is active for [settings]; when false the input
  /// dabs pass through untouched.
  bool get isActive =>
      settings.rotationMode != BrushTipRotationMode.fixed ||
      settings.sizeJitter > 0.0 ||
      settings.opacityJitter > 0.0 ||
      settings.angleJitter > 0.0 ||
      settings.roundnessJitter > 0.0 ||
      (settings.scatterRadiusRatio > 0.0 || settings.scatterCount > 1);

  /// Transforms [dabs] (renumbering from [firstSequence]) using the stroke
  /// direction at this step, in degrees of visual counterclockwise rotation
  /// from the horizontal (`null` while the direction is still unknown, e.g.
  /// the very first dab of a stroke).
  List<BrushDab> apply(
    List<BrushDab> dabs, {
    required int firstSequence,
    double? directionDegrees,
  }) {
    if (!isActive || dabs.isEmpty) {
      return dabs;
    }
    final scatterActive =
        settings.scatterRadiusRatio > 0.0 && settings.scatterCount >= 1;
    final emitted = <BrushDab>[];
    var sequence = firstSequence;

    for (final dab in dabs) {
      final copies = scatterActive ? settings.scatterCount : 1;
      for (var copy = 0; copy < copies; copy += 1) {
        var center = dab.center;
        if (scatterActive) {
          center = _scatteredCenter(
            dab.center,
            dabSize: dab.size,
            directionDegrees: directionDegrees,
          );
        }

        var angle = dab.angleDegrees;
        if (settings.rotationMode == BrushTipRotationMode.direction &&
            directionDegrees != null) {
          angle = dab.angleDegrees + directionDegrees;
        }
        if (settings.angleJitter > 0.0) {
          angle +=
              (_random.nextDouble() * 2.0 - 1.0) * settings.angleJitter * 180.0;
        }

        var size = dab.size;
        if (settings.sizeJitter > 0.0) {
          size *= 1.0 - settings.sizeJitter * _random.nextDouble();
        }
        var opacity = dab.opacity;
        if (settings.opacityJitter > 0.0) {
          opacity *= 1.0 - settings.opacityJitter * _random.nextDouble();
        }
        var roundness = dab.roundness;
        if (settings.roundnessJitter > 0.0) {
          roundness *= 1.0 - settings.roundnessJitter * _random.nextDouble();
        }

        emitted.add(
          dab.copyWith(
            center: center,
            size: size,
            opacity: opacity.clamp(0.0, 1.0).toDouble(),
            // Roundness is a ratio in (0, 1]; a fully-squashed tip would be
            // a degenerate zero-width ellipse, so it keeps a hair of width.
            roundness: roundness.clamp(0.01, 1.0).toDouble(),
            angleDegrees: _normalizeAngle(angle),
            sequence: sequence,
          ),
        );
        sequence += 1;
      }
    }
    return emitted;
  }

  CanvasPoint _scatteredCenter(
    CanvasPoint center, {
    required double dabSize,
    required double? directionDegrees,
  }) {
    final radius = settings.scatterRadiusRatio * dabSize;
    final amount = (_random.nextDouble() * 2.0 - 1.0) * radius;
    if (settings.scatterBothAxes || directionDegrees == null) {
      final angle = _random.nextDouble() * 2.0 * math.pi;
      final distance = _random.nextDouble() * radius;
      return CanvasPoint(
        x: center.x + math.cos(angle) * distance,
        y: center.y + math.sin(angle) * distance,
      );
    }
    // Single-axis scatter spreads perpendicular to the stroke direction
    // (visual CCW angle in y-down coordinates).
    final radians = directionDegrees * math.pi / 180.0;
    final perpendicularX = math.sin(radians);
    final perpendicularY = math.cos(radians);
    return CanvasPoint(
      x: center.x + perpendicularX * amount,
      y: center.y + perpendicularY * amount,
    );
  }

  /// Keeps emitted angles finite and within a stable range.
  double _normalizeAngle(double degrees) {
    if (!degrees.isFinite) {
      return 0.0;
    }
    return ((degrees % 360.0) + 360.0) % 360.0;
  }
}

/// Visual counterclockwise direction (degrees from the horizontal) of the
/// segment from [from] to [to] in y-down canvas coordinates, or `null` for
/// a degenerate segment.
double? strokeDirectionDegrees({
  required CanvasPoint from,
  required CanvasPoint to,
}) {
  final dx = to.x - from.x;
  final dy = to.y - from.y;
  if (dx == 0.0 && dy == 0.0) {
    return null;
  }
  return math.atan2(-dy, dx) * 180.0 / math.pi;
}
