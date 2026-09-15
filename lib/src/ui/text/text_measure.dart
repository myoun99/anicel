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
}
