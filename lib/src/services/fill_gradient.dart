import 'package:gpu_engine/gpu_engine.dart' show GpuGradient, GpuGradientShape;

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
  });

  final FillGradientShape shape;
  final CanvasPoint from;
  final CanvasPoint to;

  /// Straight `0xAARRGGBB`.
  final int startColor;
  final int endColor;

  /// This gradient as the engine paints it ([GpuGradient]): each pixel the
  /// colour at its centre — along a line its projection, held to the two
  /// ends; in a circle its distance over the radius; a press that never
  /// moved its start colour whatever the shape (I-160-Q5) — each straight
  /// channel between the two, rounded.
  ///
  /// ↩️Till 2026-11-15 that was worked out here, a pixel at a time, at
  /// every frame a gradient was dragged (board `a-gradient-fill-preview-
  /// paints-its-range-on-the-cpu-every-frame`): the engine's stamp.wgsl is
  /// the one spelling of it now.
  GpuGradient get onEngine => GpuGradient(
    shape: switch (shape) {
      FillGradientShape.linear => GpuGradientShape.line,
      FillGradientShape.radial => GpuGradientShape.circle,
    },
    from: (from.x, from.y),
    to: (to.x, to.y),
    start: startColor,
    end: endColor,
  );

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
