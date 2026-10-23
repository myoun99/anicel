import 'dart:math' as math;

import '../models/brush_dab.dart';
import '../models/brush_input_source.dart';
import '../models/brush_tip_mask.dart';
import '../models/brush_tip_order.dart';
import 'brush_pressure_dynamics.dart';

/// Which of a brush's tips each dab of ONE stroke takes, by its
/// [BrushTipOrder] (F-176-Q3) over turns of `BrushShape.tipsPerTurn` tips
/// (F-456-Q4).
///
/// Made afresh for every stroke — the canvas's with the stroke's dynamics
/// (`BrushStrokeDynamics`), the swatch's with its sample stroke — so the
/// turns start over at every press, and the swatch takes the turns the
/// canvas does: this is the only place the seven orders are written.
class BrushTipTurns {
  BrushTipTurns._(this._tips, this._order, this._tipsPerTurn, this._random);

  /// The turns of [tips] in [order], [tipsPerTurn] tips a turn, or `null`
  /// when every dab would take the first tip anyway — no tips, or one that
  /// never runs out — so a brush with no turns to take pays nothing per dab
  /// for them.
  static BrushTipTurns? of(
    List<BrushTipMask> tips,
    BrushTipOrder order, {
    int tipsPerTurn = 1,
    required math.Random random,
  }) {
    if (tips.isEmpty || (tips.length == 1 && !order.endsAfterOneLap)) {
      return null;
    }
    return BrushTipTurns._(tips, order, math.max(1, tipsPerTurn), random);
  }

  final List<BrushTipMask> _tips;
  final BrushTipOrder _order;
  final int _tipsPerTurn;
  final math.Random _random;
  int _taken = 0;
  List<int>? _lap;

  /// The tip [dab] takes, or `null` once a lap that does not come round
  /// again has run out — that dab is not drawn. [dab] answers only the
  /// pen's lean ([BrushTipOrder.lean]).
  BrushTipMask? next(BrushDab dab) {
    final count = (_tips.length + _tipsPerTurn - 1) ~/ _tipsPerTurn;
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
    return index == null ? null : _tips[_thrownIn(index)];
  }

  /// One of the tips turn [index] holds — thrown only when it holds more
  /// than one, so a brush of one tip a turn draws its dice as it always
  /// did.
  int _thrownIn(int index) {
    final first = index * _tipsPerTurn;
    final held = math.min(_tipsPerTurn, _tips.length - first);
    return held == 1 ? first : first + _random.nextInt(held);
  }

  /// The turn the lean of [dab] falls in, the turns cut evenly from upright
  /// to flat — the lean as every 傾き row reads it ([brushInputValue]).
  static int _byLean(BrushDab dab, int count) {
    final lean = brushInputValue(dab, BrushInputSource.tilt) ?? 0.0;
    return math.min((lean * count).floor(), count - 1);
  }

  /// 0, 1, 2, 1, 0, 1, … — the end turns once each, so a lap there and back
  /// is `2 * count - 2` turns long.
  static int _pingPong(int turn, int count) {
    if (count == 1) {
      return 0;
    }
    final period = 2 * count - 2;
    final step = turn % period;
    return step < count ? step : period - step;
  }

  /// Every turn once, in an order thrown by the stroke's dice.
  List<int> _shuffled(int count) =>
      [for (var index = 0; index < count; index += 1) index]..shuffle(_random);
}
