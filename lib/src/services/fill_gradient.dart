import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset;

import '../core/argb_channels.dart';
import '../core/segment_share.dart';
import '../models/canvas_point.dart';

/// The shapes a fill's gradient takes — 유저 답 I-160-Q4 「직선 + 원형」, the
/// two Clip Studio and Photoshop share.
enum FillGradientShape { linear, radial }

/// What a fill's gradient runs to from the main colour — 유저 답 I-160-Q3
/// (「애초에 앱에 서브색있음. 그거로하거나 투명으로하거나 여러설정가능하게.
/// 클튜나 포토샵 참고」): the two Clip Studio (メインカラー→サブカラー ·
/// 描画色→透明色) and Photoshop (foreground → background · foreground →
/// transparent) share.
enum FillGradientEnd { sub, transparent }

/// The fill tool's gradient knobs (I-160): with [enabled], a fill's press
/// picks the range and the next press lays a gradient across it, from
/// where it lands to where it lifts.
class FillGradientOptions {
  const FillGradientOptions({
    this.enabled = false,
    this.end = FillGradientEnd.sub,
    this.reversed = false,
    this.shape = FillGradientShape.linear,
  });

  final bool enabled;
  final FillGradientEnd end;

  /// The two colours swapped — Photoshop's Reverse.
  final bool reversed;
  final FillGradientShape shape;

  /// The gradient a drag from [from] to [to] lays, in [main] and the sub
  /// colour [sub]. ⚠️The clear end is [main] at no alpha, not black at none:
  /// the channels run straight, and a black one would darken the colour on
  /// its way out.
  FillGradient between(
    CanvasPoint from,
    CanvasPoint to, {
    required int main,
    required int sub,
  }) {
    final far = switch (end) {
      FillGradientEnd.sub => sub,
      FillGradientEnd.transparent => main & 0x00FFFFFF,
    };
    return FillGradient(
      shape: shape,
      from: from,
      to: to,
      startColor: reversed ? far : main,
      endColor: reversed ? main : far,
    );
  }

  FillGradientOptions copyWith({
    bool? enabled,
    FillGradientEnd? end,
    bool? reversed,
    FillGradientShape? shape,
  }) => FillGradientOptions(
    enabled: enabled ?? this.enabled,
    end: end ?? this.end,
    reversed: reversed ?? this.reversed,
    shape: shape ?? this.shape,
  );

  @override
  bool operator ==(Object other) =>
      other is FillGradientOptions &&
      other.enabled == enabled &&
      other.end == end &&
      other.reversed == reversed &&
      other.shape == shape;

  @override
  int get hashCode => Object.hash(enabled, end, reversed, shape);
}

/// One gradient laid across a fill's range: [startColor] at [from],
/// [endColor] at [to] and past it — and, along a line, [startColor] behind
/// [from].
final class FillGradient {
  FillGradient({
    required this.shape,
    required this.from,
    required this.to,
    required this.startColor,
    required this.endColor,
  }) : _a = Offset(from.x, from.y),
       _b = Offset(to.x, to.y);

  final FillGradientShape shape;
  final CanvasPoint from;
  final CanvasPoint to;

  /// Straight `0xAARRGGBB`.
  final int startColor;
  final int endColor;

  final Offset _a;
  final Offset _b;

  /// Where ([x], [y]) lies along the gradient: 0 at [from], 1 at [to] and
  /// past it.
  ///
  /// A line's is the point's projection onto it — the one projection
  /// ([shareAlongSegment]), whose answer for a line of no length is 0. A
  /// circle's is its distance from [from] over the radius, and a circle of
  /// no radius answers as that line does: a press that never moved lays
  /// [startColor] whatever the shape (I-160-Q5 — a press that never moved
  /// is a gradient too, made nothing special of).
  double at(double x, double y) {
    final along = switch (shape) {
      FillGradientShape.linear => shareAlongSegment(Offset(x, y), _a, _b),
      FillGradientShape.radial => _radius == 0
          ? 0.0
          : math.sqrt(
                  (x - _a.dx) * (x - _a.dx) + (y - _a.dy) * (y - _a.dy),
                ) /
                _radius,
    };
    return along.clamp(0.0, 1.0);
  }

  late final double _radius = (_b - _a).distance;

  /// The colour [t] of the way along — each straight channel between the
  /// two, rounded.
  int colorAt(double t) {
    int channel(int Function(int argb) of) {
      final start = of(startColor);
      return (start + (of(endColor) - start) * t).round();
    }

    return channel(argbAlpha) << 24 |
        channel(argbRed) << 16 |
        channel(argbGreen) << 8 |
        channel(argbBlue);
  }

  /// [colorAt] at [steps] even stops from 0 to 1 — what a stamp looks a
  /// pixel's colour up in, so a pixel pays one [at] and not four channels
  /// mixed.
  Uint32List stops(int steps) => Uint32List.fromList([
    for (var i = 0; i < steps; i += 1) colorAt(i / (steps - 1)),
  ]);

  @override
  bool operator ==(Object other) =>
      other is FillGradient &&
      other.shape == shape &&
      other.from == from &&
      other.to == to &&
      other.startColor == startColor &&
      other.endColor == endColor;

  @override
  int get hashCode => Object.hash(shape, from, to, startColor, endColor);
}
