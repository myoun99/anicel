import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../../models/text_cel_style.dart';
import '../theme/app_theme.dart' show AppTypography;

/// THE ENGINE STYLE A LETTER OF CANVAS TEXT IS SET IN — the one recipe the
/// SE name tag (`layoutTextCel`) and a text on a cel (`layoutCelText`) both
/// write with (R5 ⓣ: 「ONE canvas-text implementation」). Engine text in the
/// app's BUNDLED faces ([AppTypography.bundledFamily], 유저 2026-09-25:
/// 「글꼴 앱에서 정한거 통일」) behind whatever face was chosen, so a letter
/// the chosen face lacks is caught in the app's own order and a picture
/// prints the same letters on every machine.
///
/// 🚨EVERY VALUE IS SAID OUT LOUD — zero tracking included. A run that
/// leaves a value null does not get the engine's default for it: it gets
/// the value of the style it is NESTED IN (read in the engine,
/// `lib/ui/text/paragraph_builder.cc`: 「Set to use the properties of the
/// previous style if the property is not explicitly given」). A cel text's
/// runs are nested in the style of its last one (`layoutCelText`), so a run
/// left with no tracking would be set with the last run's.
///
/// [foreground] paints the letters in place of the style's own colour — the
/// outline pass ([canvasLetterOutlinePaint]). ⚠️For the same reason a style
/// that runs are nested in is never painted by one: the engine keeps a
/// foreground until another replaces it, and a colour does not.
TextStyle canvasLetterTextStyle(
  TextLetterStyle style, {
  required double lineHeight,
  double? fontSize,
  ui.Paint? foreground,
}) => TextStyle(
  color: foreground == null ? style.colorValue : null,
  foreground: foreground,
  fontSize: fontSize ?? style.fontSize,
  fontWeight: style.bold ? FontWeight.w700 : FontWeight.w400,
  letterSpacing: style.letterSpacing,
  fontFamily: style.fontFamily ?? AppTypography.bundledFamily,
  // CJK safety on every family choice: the app's bundled faces catch what
  // a chosen face misses, in the app's own order.
  fontFamilyFallback: const [
    AppTypography.bundledFamily,
    ...AppTypography.bundledFallback,
  ],
  height: lineHeight,
);

/// The paint [style]'s outline is stroked with, or null when it wears none.
///
/// Stroke UNDER fill — the timeline glyph outline recipe (#15: one rule on
/// every surface): the caller paints the whole text once with this and then
/// once more with its fill, so an outline never covers a letter.
ui.Paint? canvasLetterOutlinePaint(TextLetterStyle style) {
  final color = style.outlineColorValue;
  if (color == null || style.outlineWidth <= 0) {
    return null;
  }
  return ui.Paint()
    ..style = ui.PaintingStyle.stroke
    ..strokeWidth = style.outlineWidth
    ..strokeJoin = ui.StrokeJoin.round
    ..color = color;
}

/// The engine alignment of [align].
TextAlign canvasTextAlign(TextCelAlign align) => switch (align) {
  TextCelAlign.left => TextAlign.left,
  TextCelAlign.center => TextAlign.center,
  TextCelAlign.right => TextAlign.right,
};
