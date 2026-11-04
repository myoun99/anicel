import 'dart:math' as math;

import 'brush_dab.dart';

/// How a brush's line comes in and goes out — Clip Studio's 入り抜き: thin
/// and faint where it starts, full along the way, thin and faint again
/// where it ends.
///
/// 🗣️유저 2026-11-01 (brush-in-and-out-Q1 「크기 · 농도, 길이 지정 하나」):
/// the 入り and the 抜き are lengths along the line, in canvas pixels, and
/// what they take away is the size and the 濃度 — Clip Studio's ブラシ濃度,
/// which is our [BrushDab.flow] (`BrushFlow`) — each down to a minimum of
/// its own. 入り runs from the minimum to 100%, 抜き from 100% back to it.
/// ⛔No パーセント指定, no フェード, and none of the other eighteen settings
/// Clip Studio lets it reach (F-418-Q9 「굳이 이렇게 심하게 만들 필요는
/// 없어보임 적당하게만」).
///
/// ⚠️Where Clip Studio has a switch and a value under it, ours is the value
/// with nothing at the end of its scale, as the 後補正 is
/// ([BrushCorrection]): a length of 0 does not come in or go out, a
/// minimum of 100% takes nothing away.
class BrushInAndOut {
  const BrushInAndOut({
    this.inLength = 0,
    this.outLength = 0,
    this.sizeMinimum = 0,
    this.flowMinimum = 1,
  });

  /// 入り: how far, in canvas pixels, the line takes to come in — 0 for a
  /// line that starts at full.
  final double inLength;

  /// 抜き: how far before its end the line starts to go out — 0 for a line
  /// that ends at full.
  ///
  /// 🗣️Laid when the pen lifts (brush-in-and-out-Q2 「뗄 때 고쳐 깐다」):
  /// where a line ends is known only then, so the line drawn so far is laid
  /// again with its end going out, as the 後補正 lays its line again.
  final double outLength;

  /// What is left of the size where the line comes in and goes out, 0..1.
  ///
  /// ⚠️Its 0 and [flowMinimum]'s 1 are mine: the size thins to nothing and
  /// the 濃度 stays, the taper a line is drawn with when nothing else is
  /// asked for.
  final double sizeMinimum;

  /// What is left of the flow (Clip Studio's ブラシ濃度) where the line comes
  /// in and goes out, 0..1.
  final double flowMinimum;

  /// A brush whose line comes in and goes out at full.
  static const BrushInAndOut none = BrushInAndOut();

  /// The longest [inLength] and [outLength].
  ///
  /// ⚠️Mine: no source says how long Clip Studio lets them run.
  static const double maxLength = 1000;

  /// Whether a line comes in thinner or fainter than it goes on.
  bool get comesIn => inLength > 0 && _takesAway;

  /// Whether a line goes out thinner or fainter than it went on — which is
  /// laid when the pen lifts ([outLength]).
  bool get goesOut => outLength > 0 && _takesAway;

  bool get _takesAway => sizeMinimum < 1 || flowMinimum < 1;

  /// How far along its way in or out a point [travelled] along a line is:
  /// 0 at the line's ends, 1 once it is in and until it starts to go out.
  /// The way out is counted only when the line's whole [length] is known.
  ///
  /// 🗣️Where the 入り and the 抜き meet on a short line, the lower of the two
  /// (brush-in-and-out-Q1: 「짧은 획에서 入り 와 抜き 가 겹치면 낮은 쪽」).
  /// ⚠️Straight from the minimum to 100% is mine: Clip Studio shows no curve
  /// for it.
  double reachAt(double travelled, {double? length}) {
    var reach = 1.0;
    if (inLength > 0 && travelled < inLength) {
      reach = travelled / inLength;
    }
    if (outLength > 0 && length != null) {
      final left = length - travelled;
      if (left < outLength) {
        reach = math.min(reach, left / outLength);
      }
    }
    return reach.clamp(0.0, 1.0).toDouble();
  }

  /// [dab] as thin and as faint as [reach] along the way in or out
  /// ([reachAt]) leaves it.
  BrushDab taper(BrushDab dab, double reach) => reach >= 1
      ? dab
      : dab.copyWith(
          size: dab.size * (sizeMinimum + (1 - sizeMinimum) * reach),
          flow: dab.flow * (flowMinimum + (1 - flowMinimum) * reach),
        );

  BrushInAndOut copyWith({
    double? inLength,
    double? outLength,
    double? sizeMinimum,
    double? flowMinimum,
  }) => BrushInAndOut(
    inLength: inLength ?? this.inLength,
    outLength: outLength ?? this.outLength,
    sizeMinimum: sizeMinimum ?? this.sizeMinimum,
    flowMinimum: flowMinimum ?? this.flowMinimum,
  );

  Map<String, Object?> toJson() => {
    'inLength': inLength,
    'outLength': outLength,
    'sizeMinimum': sizeMinimum,
    'flowMinimum': flowMinimum,
  };

  /// Reads what [toJson] wrote; a part that is absent keeps its default.
  static BrushInAndOut fromJson(Object? json) {
    const fallback = BrushInAndOut.none;
    if (json is! Map) {
      return fallback;
    }
    double number(String key, double otherwise) =>
        (json[key] as num?)?.toDouble() ?? otherwise;
    return BrushInAndOut(
      inLength: number('inLength', fallback.inLength),
      outLength: number('outLength', fallback.outLength),
      sizeMinimum: number('sizeMinimum', fallback.sizeMinimum),
      flowMinimum: number('flowMinimum', fallback.flowMinimum),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BrushInAndOut &&
          other.inLength == inLength &&
          other.outLength == outLength &&
          other.sizeMinimum == sizeMinimum &&
          other.flowMinimum == flowMinimum;

  @override
  int get hashCode =>
      Object.hash(inLength, outLength, sizeMinimum, flowMinimum);

  @override
  String toString() =>
      'BrushInAndOut(inLength: $inLength, outLength: $outLength, '
      'sizeMinimum: $sizeMinimum, flowMinimum: $flowMinimum)';
}
