import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../core/bounded_memo.dart';

/// Where a [TextMeasure] lays a line out: everything but the line that
/// decides its size.
typedef _Ground = ({
  TextStyle? style,
  TextScaler scaler,
  TextDirection direction,
  int fonts,
});

/// The digits a decimal number is written in — [everyDigitIn]'s.
const String decimalDigits = '0123456789';

/// [shape] written with each of [digits] in turn: the numbers whose widest
/// is the widest [shape] can be set, for a box that has to hold whatever
/// number it will say. A face with proportional figures sets an 8 wider
/// than a 1, so no one number is the measure, and one that mixes them is
/// never wider than the widest of these.
///
/// 🚨ONE WALK OF THE DIGITS (F-383, 2026-10-17). The pill's zoom and angle
/// readouts, the colour bar's channels and hex, the battery and the frame
/// ruler each spelled the ten digits out for themselves, and the page
/// turner's readout was about to be the sixth.
List<String> everyDigitIn(
  String Function(String digit) shape, {
  String digits = decimalDigits,
}) => [for (final digit in digits.split('')) shape(digit)];

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
/// Remembers each text laid out where it measures, so a table that asks for
/// the same word on every row lays it out once.
///
/// 🚨LAID OUT ONCE WHEREVER IT IS ASKED (card frame-panels-build-in-one-frame,
/// 2026-10-24). A measure remembered only its own words, and a build makes a
/// new one each time it asks — so every rebuild laid the same lines out
/// again: the colour status bar's 29 probes each time a colour tab was
/// described (`ColorPickerPanel.minContentWidthIn` — three tabs, on every
/// rebuild of the workspace). 🔬Profile, a copy of AMMI OP: `size` was
/// 12–17% of the frames that bring a frame panel forward again (its tab
/// shown, the bottom region unfolded). What a line measures is decided by
/// the line, the style, the text scaler, the direction and the fonts there
/// are — so measures that agree on the last four share their sizes
/// ([_grounds]), and a font registered since is another key ([fontsNow]).
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

  /// The sizes laid out where this measure lays text out, shared with every
  /// measure taken there.
  late final BoundedMemo<String, Size> _measured = _grounds.resolve(
    (style: style, scaler: _scaler, direction: _direction, fonts: fontsNow),
    () => BoundedMemo(_linesPerGround),
  );

  static final BoundedMemo<_Ground, BoundedMemo<String, Size>> _grounds =
      BoundedMemo(64);
  static const int _linesPerGround = 1024;

  /// How many times the fonts have changed since the first measure — a face
  /// registered while the app runs (a canvas letter face) can set a line
  /// differently. A layout kept for its words is kept for this too (a text
  /// block's, `textCelLaidOut`).
  static int get fontsNow {
    if (!_hearingFonts) {
      _hearingFonts = true;
      PaintingBinding.instance.systemFonts.addListener(() => _fonts += 1);
    }
    return _fonts;
  }

  static int _fonts = 0;
  static bool _hearingFonts = false;

  /// The size [text] takes on one line.
  Size size(String text) => _measured.resolve(text, () {
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
