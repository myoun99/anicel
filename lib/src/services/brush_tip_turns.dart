import 'dart:math' as math;

import '../models/brush_dab.dart';
import '../models/brush_input_source.dart';
import '../models/brush_tip_mask.dart';
import '../models/brush_tip_order.dart';
import 'brush_pressure_dynamics.dart';

/// Which of a brush's tips each dab of ONE stroke takes, by its
/// [BrushTipOrder] (F-176-Q3).
///
/// Made afresh for every stroke — the canvas's with the stroke's dynamics
/// (`BrushStrokeDynamics`), the swatch's with its sample stroke — so the
/// turns start over at every press, and the swatch takes the turns the
/// canvas does: this is the only place the seven orders are written.
class BrushTipTurns {
  BrushTipTurns._(this._tips, this._order, this._random);

  /// The turns of [tips] in [order], or `null` when every dab would take
  /// the first tip anyway — no tips, or one that never runs out — so a
  /// brush with no turns to take pays nothing per dab for them.
  static BrushTipTurns? of(
    List<BrushTipMask> tips,
    BrushTipOrder order, {
    required math.Random random,
  }) {
    if (tips.isEmpty || (tips.length == 1 && !order.endsAfterOneLap)) {
      return null;
    }
    return BrushTipTurns._(tips, order, random);
  }

  final List<BrushTipMask> _tips;
  final BrushTipOrder _order;
  final math.Random _random;
  int _taken = 0;
  List<int>? _lap;

  /// The tip [dab] takes, or `null` once a lap that does not come round
  /// again has run out — that dab is not drawn. [dab] answers only the
  /// pen's lean ([BrushTipOrder.lean]).
  BrushTipMask? next(BrushDab dab) {
    final count = _tips.length;
    final turn = _taken;
    _taken += 1;
    final index = switch (_order) {
      BrushTipOrder.repeat => turn % count,
      BrushTipOrder.pingPong => _pingPong(turn, count),
      BrushTipOrder.holdLast => math.min(turn, count - 1),
      BrushTipOrder.random => _random.nextInt(count),
      BrushTipOrder.oneLap => turn < count ? turn : null,
      BrushTipOrder.shuffledLap =>
        turn < count ? (_lap ??= _shuffled(count))[turn] : null,
      BrushTipOrder.lean => _byLean(dab, count),
    };
    return index == null ? null : _tips[index];
  }

  /// The tip the lean of [dab] falls in, the list cut evenly from upright
  /// to flat — the lean as every 傾き row reads it ([brushInputValue]).
  static int _byLean(BrushDab dab, int count) {
    final lean = brushInputValue(dab, BrushInputSource.tilt) ?? 0.0;
    return math.min((lean * count).floor(), count - 1);
  }

  /// 0, 1, 2, 1, 0, 1, … — the end tips once each, so a lap there and back
  /// is `2 * count - 2` turns long.
  static int _pingPong(int turn, int count) {
    if (count == 1) {
      return 0;
    }
    final period = 2 * count - 2;
    final step = turn % period;
    return step < count ? step : period - step;
  }

  /// Every tip index once, in an order thrown by the stroke's dice.
  List<int> _shuffled(int count) =>
      [for (var index = 0; index < count; index += 1) index]..shuffle(_random);
}
