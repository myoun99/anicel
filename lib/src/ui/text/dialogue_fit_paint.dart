import 'package:flutter/material.dart';

import 'dialogue_fit_layout.dart';
import 'word_condensation.dart';
import 'vertical_writing_text.dart';

/// SE dialogue distributed evenly over the covered rows — the sheet's
/// "fit" rule, sharing [dialogueGlyphCenters] with the timeline overlay so
/// screen and print place glyphs identically. Never truncates: the
/// dialogue owns its whole block, exactly like the paper column.
///
/// The FORMS come from the app's one vertical-writing table, like every
/// other column on this sheet. They used not to — this placer stacked
/// every glyph upright, so a `ー` inside dialogue lay across the column
/// while the notation word two columns over rotated it.
///
/// A glyph longer than its cell narrows down the column into it, by the
/// row's own [wordCondensation] (F-93): the sheet and a vertical
/// timeline keep the rule the user gave for the zoomed-out row.
///
/// [topCenter] is the top of the column on its centre line and [extent]
/// how far down it runs; [style] carries the whole look, so the screen's
/// w600 12pt and the sheet's regular 9pt are values rather than two
/// placers. `style.fontSize` must be set — the vertical cell sizes
/// against it.
void paintDialogueFitColumn(
  Canvas canvas,
  String text, {
  required Offset topCenter,
  required double extent,
  required TextStyle style,
  double maxCrossExtent = double.infinity,
}) {
  final glyphs = text.characters.toList(growable: false);
  final centers = dialogueGlyphCenters(
    glyphCount: glyphs.length,
    mainExtent: extent,
  );
  final cellExtent = dialogueGlyphCellExtent(
    glyphCount: glyphs.length,
    mainExtent: extent,
  );
  double condense(double extentAlongColumn) =>
      wordCondensation(extent: extentAlongColumn, room: cellExtent);
  for (var i = 0; i < glyphs.length; i += 1) {
    final painter = TextPainter(
      text: TextSpan(text: glyphs[i], style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    paintVerticalTextCell(
      canvas,
      verticalGlyphCell(glyphs[i]),
      painter: painter,
      center: Offset(topCenter.dx, topCenter.dy + centers[i]),
      fontSize: style.fontSize!,
      maxCrossExtent: maxCrossExtent,
      alongColumnScale: condense,
    );
  }
}
