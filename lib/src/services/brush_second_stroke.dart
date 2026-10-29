import 'dart:math' as math;

import '../models/brush_dab.dart';
import '../models/brush_edit_canvas_input_settings.dart';
import '../models/brush_shape.dart';
import '../models/brush_tip_mask.dart';
import 'brush_dab_interpolator.dart';
import 'brush_stroke_dynamics.dart';

/// 🚨★★★THE SECOND TIP IS A SECOND STROKE (board
/// an-imported-pencil-drops-its-second-brush Q3 b, 유저 2026-10-25 「두 번째
/// 획으로 다시 만든다」) — what the stroke shows of it is beside
/// `qa_dual_view_rows` (qa_engine.c, ABI 60). This is where its dabs come
/// from, and the ONE place every producer makes them — the live stroke and
/// the brush list's swatch: the same interpolator the first tip's dabs come
/// out of walks the first tip's path at the second tip's own size and
/// spacing, and every dab it lays is an ordinary dab of the second tip
/// ([BrushDab.second]).
///
/// The path is the first tip's dabs as the path lays them, their pressure
/// read — before the stroke's dynamics scatter or turn them: the second
/// stroke follows the pen, not the first tip's spray.
///
/// A second tip's dab lays whole — colour, opacity and flow at one: how
/// hard it bites is the view's density, applied once over the stroke.
///
/// Its own way along the path — spacing, 向き, scatter — is the second
/// tip's ([BrushShape.secondTip]) through the code the first tip's goes
/// through: the same interpolator, then the same [BrushStrokeDynamics].
class BrushSecondStroke {
  BrushSecondStroke._(this._shape, this._view, this._tip, this._dynamics);

  /// The second stroke [shape]'s strokes draw, or null when it has no
  /// second tip. [random] throws its scatter and its turns.
  static BrushSecondStroke? of(BrushShape shape, {math.Random? random}) {
    final view = shape.dualView;
    final tip = shape.dualMask;
    final placement = shape.secondTip;
    if (view == null || tip == null || placement == null) {
      return null;
    }
    return BrushSecondStroke._(
      shape,
      view,
      tip,
      BrushStrokeDynamics(
        settings: BrushEditCanvasInputSettings.fromShape(placement),
        random: random,
      ),
    );
  }

  final BrushShape _shape;
  final BrushDualView _view;
  final BrushTipMask _tip;
  final BrushStrokeDynamics _dynamics;

  /// Whether the second stroke turns on the stroke's direction, as
  /// [BrushStrokeDynamics.readsDirection] says of the first: a press waits
  /// for it either way.
  bool get readsDirection => _dynamics.readsDirection;

  /// The second tip's dab before the next — where the walk stands.
  BrushDab? _previous;

  /// The second tip's dabs along [path], numbered from [firstSequence] — a
  /// segment's worth at a time, the walk carried over from the last.
  /// [directionDegrees] is the stroke's way at this step, which a turn to
  /// follow it or a scatter across it reads.
  List<BrushDab> follow(
    List<BrushDab> path, {
    required int firstSequence,
    double? directionDegrees,
  }) {
    final laid = <BrushDab>[];
    for (final dab in path) {
      final along = const BrushDabInterpolator().interpolate(
        previous: _previous,
        nextRaw: _secondOf(dab),
        firstSequence: firstSequence + laid.length,
        spacingRatio: math.max(_shape.dualSpacing, BrushShape.minSpacing),
      );
      if (along.isEmpty) {
        continue;
      }
      _previous = along.last;
      laid.addAll(along);
    }
    return _dynamics.apply(
      laid,
      firstSequence: firstSequence,
      directionDegrees: directionDegrees,
    );
  }

  BrushDab _secondOf(BrushDab dab) => BrushDab(
    center: dab.center,
    color: 0xFF000000,
    size: dab.size * _shape.dualMaskScale,
    opacity: 1,
    flow: 1,
    hardness: dab.hardness,
    pressure: dab.pressure,
    sequence: dab.sequence,
    roundness: _shape.dualRoundness,
    angleDegrees: _shape.dualAngleDegrees,
    tiltAzimuthDegrees: dab.tiltAzimuthDegrees,
    tiltAltitude: dab.tiltAltitude,
    twistDegrees: dab.twistDegrees,
    speed: dab.speed,
    tipMask: _tip,
    dual: _view,
    second: true,
    antiAlias: dab.antiAlias,
  );
}
