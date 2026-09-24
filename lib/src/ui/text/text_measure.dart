import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// How lines of UI text measure where a [BuildContext] lays text out — its
/// text scaler and its direction — in one style.
///
/// ⛔ONE MEASURE for every layout that sizes itself to its words. The import
/// window's table sized its columns this way, its column popup measured its
/// labels a second time with the same three inputs written out again, and the
/// media pool's width floor needed a third once a row's extension became a
/// fixed part (the name and the extension stand apart, and only the name is
/// cut short) — the rule of three.
///
/// Remembers each text it has laid out, so a table that asks for the same
/// word on every row lays it out once.
class TextMeasure {
  TextMeasure(BuildContext context, this.style)
    : _scaler = MediaQuery.textScalerOf(context),
      _direction = Directionality.of(context);

  TextMeasure._(this.style, this._scaler, this._direction);

  /// The same words measured the way they lay out at 1× — the ground every
  /// growth below is stated against.
  late final TextMeasure _atOne = TextMeasure._(
    style,
    TextScaler.noScaling,
    _direction,
  );

  /// A line in every script the app's labels write — Latin, Hangul, kana,
  /// kanji, a digit. The two faces set different line metrics, so a box
  /// sized for ONE of them is sized for whichever the language picks.
  static const String everyScript = 'Mg가あ漢1';

  final TextStyle? style;
  final TextScaler _scaler;
  final TextDirection _direction;
  final Map<String, Size> _measured = {};

  /// The size [text] takes on one line.
  Size size(String text) => _measured.putIfAbsent(text, () {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: _direction,
      textScaler: _scaler,
      maxLines: 1,
    )..layout();
    final size = painter.size;
    painter.dispose();
    return size;
  });

  /// The widest of [texts] on one line — 0 when there are none.
  double widest(Iterable<String> texts) =>
      texts.fold(0, (width, text) => math.max(width, size(text).width));

  /// How much taller one line of [text] stands here than it does at 1× —
  /// what a box drawn around that line at 1× has to add for the line to
  /// still fit.
  ///
  /// 🚨text-scale-fixed-height-bars (유저 2026-09-18, answering 「OS 글자
  /// 크기를 키웠을 때」: 「막대가 글자 크기를 따라 자란다」). A bar's height is
  /// the height it was drawn at PLUS this, which is 0 at 1× — so nothing
  /// drawn at 1× moves.
  double lineGrowthOf(String text) =>
      math.max(0, size(text).height - _atOne.size(text).height);

  /// How much wider the widest of [texts] runs here than at 1× — what a
  /// column sized around those words at 1× has to add for them to still
  /// fit. [lineGrowthOf] turned onto the other axis.
  ///
  /// 🚨text-scale-rail-columns (유저 2026-09-25, 「칸도 글자 따라
  /// 넓어진다」): 0 at 1×, so nothing drawn at 1× moves.
  double widthGrowthOf(Iterable<String> texts) =>
      math.max(0, widest(texts) - _atOne.widest(texts));
}
