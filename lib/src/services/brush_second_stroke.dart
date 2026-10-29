import 'dart:math' as math;

import '../models/brush_dab.dart';
import '../models/brush_shape.dart';
import '../models/brush_tip_mask.dart';
import 'brush_dab_interpolator.dart';

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
class BrushSecondStroke {
  BrushSecondStroke._(this._shape, this._view, this._tip);

  /// The second stroke [shape]'s strokes draw, or null when it has no
  /// second tip.
  static BrushSecondStroke? of(BrushShape shape) {
    final view = shape.dualView;
    final tip = shape.dualMask;
    if (view == null || tip == null) {
      return null;
    }
    return BrushSecondStroke._(shape, view, tip);
  }

  final BrushShape _shape;
  final BrushDualView _view;
  final BrushTipMask _tip;

  /// The second tip's dab before the next — where the walk stands.
  BrushDab? _previous;

  /// The second tip's dabs along [path], numbered from [firstSequence] — a
  /// segment's worth at a time, the walk carried over from the last.
  List<BrushDab> follow(List<BrushDab> path, {required int firstSequence}) {
    final laid = <BrushDab>[];
    for (final dab in path) {
      final along = const BrushDabInterpolator().interpolate(
        previous: _previous,
        nextRaw: _secondOf(dab),
        firstSequence: firstSequence + laid.length,
        spacingRatio: math.max(_shape.spacing, BrushShape.minSpacing),
      );
      if (along.isEmpty) {
        continue;
      }
      _previous = along.last;
      laid.addAll(along);
    }
    return laid;
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
