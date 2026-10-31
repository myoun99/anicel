import 'dart:math' as math;

import 'package:flutter/painting.dart';

/// How a sheet sets the words of a text box — the form the field types them
/// in, so the editing happens on the printed glyphs.
enum SheetTextForm {
  /// From the top left of the rect, wrapped at its width: a memo, an ACTION.
  paragraph,

  /// One line centred across the rect, from its top: a header box's value.
  centredLine,

  /// One line from the rect's left, from its top: an envelope box's value
  /// its form sets left (I-127-Q1).
  leftLine,

  /// One line up to the rect's right, from its top.
  rightLine;

  /// Whether the words are one line, whole in the rect ([SheetLinePlace]).
  bool get isLine => this != paragraph;

  /// How far across the room a rect leaves its words stand: 0 at its left,
  /// 1 at its right.
  double get along => switch (this) {
    SheetTextForm.paragraph || SheetTextForm.leftLine => 0,
    SheetTextForm.centredLine => 0.5,
    SheetTextForm.rightLine => 1,
  };
}

/// [text] laid out on one line, as wide as it runs — what [SheetLinePlace]
/// stands in a box. The caller disposes it.
TextPainter sheetLine(String text, TextStyle style) => TextPainter(
  text: TextSpan(text: text, style: style),
  textDirection: TextDirection.ltr,
  maxLines: 1,
)..layout();

/// Where a [sheetLine] stands in the rect a sheet sets it in — one answer for
/// the printer, for what the open field hides, and for the field itself.
///
/// 🗣️I-127-Q4 (유저 2026-11-01): 「글자를 줄여 칸에 맞춘다」 — a line wider
/// than its rect stands whole in it, smaller, on the paper and while it is
/// typed. ↩️It was cut with a `…`.
///
/// ⚠️Scaled as a picture, not set again at a smaller size: the printer and
/// the field then lay a line out once, the same way, and a long one never
/// comes to the sizes a line cannot be measured at (`CutEnvelopeEditLayer`).
class SheetLinePlace {
  const SheetLinePlace._(this.rect, this.scale);

  /// [line]'s place in [slot], whose top it stands from. Scaled about its
  /// own middle, so a line that shrinks stays on the row it was on.
  factory SheetLinePlace.of(Size line, Rect slot, SheetTextForm form) {
    final room = math.max(0.0, slot.width);
    final scale = line.width > room ? room / line.width : 1.0;
    final shown = line * scale;
    return SheetLinePlace._(
      Rect.fromLTWH(
        slot.left + (room - shown.width) * form.along,
        slot.top + (line.height - shown.height) / 2,
        shown.width,
        shown.height,
      ),
      scale,
    );
  }

  /// The line as it stands, in paper units.
  final Rect rect;

  /// How far it is scaled down: 1 where it fits.
  final double scale;

  /// Prints [line] here.
  void paint(Canvas canvas, TextPainter line) {
    if (scale == 1) {
      line.paint(canvas, rect.topLeft);
      return;
    }
    canvas
      ..save()
      ..translate(rect.left, rect.top)
      ..scale(scale);
    line.paint(canvas, Offset.zero);
    canvas.restore();
  }
}
