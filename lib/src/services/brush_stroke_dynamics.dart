import 'dart:math' as math;

import '../models/brush_dab.dart';
import '../models/brush_tip_rotation_mode.dart';
import '../models/canvas_point.dart';
import '../models/brush_edit_canvas_input_settings.dart';
import 'brush_tip_turns.dart';

/// Applies placement-time stroke dynamics — scatter, the tip's 向き (a fixed
/// angle, the stroke's direction or the pen's, plus its random turn), and
/// which of several tips each dab takes ([BrushTipTurns]) — to interpolated
/// dabs.
///
/// Dynamics run once, when dabs are GENERATED: the emitted dabs carry their
/// final randomized values, and since committed source dabs are the durable
/// source of truth, re-rendering (commit, undo/redo) replays exactly the
/// pixels that were on screen. The rasterizers and their parity guarantees
/// are untouched by design.
///
/// ↩️Size, opacity and roundness jitter used to be thrown here too. They are
/// the ランダム row of each setting's curves now (F-176-Q2), thrown where the
/// other inputs are read (`applyBrushInputDynamics`).
class BrushStrokeDynamics {
  /// [tipRandom] throws the tips' random turns apart from [random], so a
  /// brush's scatter lands where it did whatever order its tips take.
  BrushStrokeDynamics({
    required this.settings,
    math.Random? random,
    math.Random? tipRandom,
  }) : _random = random ?? math.Random(),
       _tipTurns = BrushTipTurns.of(
         settings.tips,
         settings.tipOrder,
         random: tipRandom ?? math.Random(),
       );

  final BrushEditCanvasInputSettings settings;
  final math.Random _random;

  /// One stroke's turns, so they start over with the stroke.
  final BrushTipTurns? _tipTurns;

  /// Whether any dynamic is active for [settings]; when false the input
  /// dabs pass through untouched.
  bool get isActive =>
      settings.rotationMode != BrushTipRotationMode.fixed ||
      settings.angleJitter > 0.0 ||
      (settings.scatterRadiusRatio > 0.0 || settings.scatterCount > 1) ||
      _tipTurns != null;

  /// Whether a dab's placement turns on the stroke's DIRECTION — a tip that
  /// follows it, or scatter thrown across it rather than all around — so a
  /// press, which has no direction yet, waits for the first move's (H43:
  /// the press is drawn with every input its brush reads).
  bool get readsDirection =>
      settings.rotationMode == BrushTipRotationMode.direction ||
      (_scatters && !settings.scatterBothAxes);

  bool get _scatters =>
      settings.scatterRadiusRatio > 0.0 && settings.scatterCount >= 1;

  /// Transforms [dabs] (renumbering from [firstSequence]) using the stroke
  /// direction at this step, in degrees of visual counterclockwise rotation
  /// from the horizontal (`null` while the direction is still unknown, e.g.
  /// a tap that never moved).
  List<BrushDab> apply(
    List<BrushDab> dabs, {
    required int firstSequence,
    double? directionDegrees,
  }) {
    if (!isActive || dabs.isEmpty) {
      return dabs;
    }
    final scatterActive = _scatters;
    final tipTurns = _tipTurns;
    final emitted = <BrushDab>[];
    var sequence = firstSequence;

    for (final dab in dabs) {
      final copies = scatterActive ? settings.scatterCount : 1;
      for (var copy = 0; copy < copies; copy += 1) {
        // Every dab takes a turn — each of a spray's too (F-176-Q3: 「dab
        // 하나마다 다음 장으로」).
        final tip = tipTurns == null ? dab.tipMask : tipTurns.next();
        if (tip == null && tipTurns != null) {
          continue;
        }
        var center = dab.center;
        if (scatterActive) {
          center = _scatteredCenter(
            dab.center,
            dabSize: dab.size,
            directionDegrees: directionDegrees,
          );
        }

        var angle = dab.angleDegrees;
        final turn = tipTurnDegrees(
          settings.rotationMode,
          dab,
          directionDegrees: directionDegrees,
        );
        if (turn != null) {
          angle += turn;
        }
        if (settings.angleJitter > 0.0) {
          angle +=
              (_random.nextDouble() * 2.0 - 1.0) * settings.angleJitter * 180.0;
        }

        emitted.add(
          dab.copyWith(
            center: center,
            angleDegrees: _normalizeAngle(angle),
            sequence: sequence,
            tipMask: tip,
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

/// How far the 向き base [mode] turns [dab]'s tip from its own angle, in
/// dab degrees — null where it turns nothing: a fixed tip, or a base that
/// cannot say yet (no [directionDegrees] before the stroke moves, a pen that
/// reports no lean or no twist).
///
/// The one answer to "which way does the tip point": a stroke's dabs and
/// the brush cursor (`poisedTip`, F-176-Q7) both ask it.
double? tipTurnDegrees(
  BrushTipRotationMode mode,
  BrushDab dab, {
  required double? directionDegrees,
}) => switch (mode) {
  BrushTipRotationMode.fixed => null,
  BrushTipRotationMode.direction => directionDegrees,
  BrushTipRotationMode.penTilt => penDirectionDegrees(dab),
  BrushTipRotationMode.penTwist => penTwistDegrees(dab),
};

/// Which way the pen leans, as a dab angle — visual counterclockwise degrees
/// from the horizontal, the way [BrushDab.angleDegrees] runs — or `null`
/// when the pen cannot say: a device with no tilt, or a pen held upright,
/// which leans nowhere ([BrushDab.tiltAzimuthDegrees] is meaningless there).
///
/// 🚨THE SIGN FLIPS. The azimuth runs CLOCKWISE from +x (`PenLean`) and a
/// dab's angle counterclockwise, so the same lean is the negated number.
///
/// 유저 2026-10-18 (F-176-Q4, of the tilted pencil): 「펜 실제 각도에 따라
/// dab 각도 바뀌는건가했는데 그거조차도아님. 가능하도록」 — Clip Studio's
/// 向き 「ペンの方向」.
double? penDirectionDegrees(BrushDab dab) {
  final altitude = dab.tiltAltitude;
  if (altitude == null || altitude >= 1.0) {
    return null;
  }
  return -dab.tiltAzimuthDegrees;
}

/// How far the pen is turned about its barrel, as a dab angle — or `null`
/// when the device reported no turn ([BrushDab.twistDegrees]).
///
/// 🚨THE SIGN FLIPS, as for [penDirectionDegrees]: a pen's twist runs
/// CLOCKWISE and a dab's angle counterclockwise, so a pen turned clockwise
/// turns its tip clockwise on the canvas.
///
/// 유저 2026-10-21 (F-176-Q9): 「클튜처럼 — 방향의 기준 「펜 축 회전」 하나」.
double? penTwistDegrees(BrushDab dab) {
  final twist = dab.twistDegrees;
  return twist == null ? null : -twist;
}
