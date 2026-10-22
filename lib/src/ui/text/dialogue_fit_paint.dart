import 'package:flutter/material.dart';

import 'dialogue_fit_layout.dart';
import 'laid_out_glyph.dart';
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
/// against it. [setWord] is how the host sets a glyph ([WordSetter]).
///
/// [shownFrom] and [shownTo], down from [topCenter], are a WINDOW on the
/// column: the text is still laid out over all of [extent], and only the
/// glyphs whose centre the window holds are painted, each whole and where
/// that layout lays it ([dialogueGlyphsShownIn]) — a cut, or a page half,
/// sees its part of a block that runs on past it (F-358).
void paintDialogueFitColumn(
  Canvas canvas,
  String text, {
  required Offset topCenter,
  required double extent,
  required TextStyle style,
  required WordSetter setWord,
  double maxCrossExtent = double.infinity,
  double shownFrom = double.negativeInfinity,
  double shownTo = double.infinity,
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
  final shown = dialogueGlyphsShownIn(
    glyphCount: glyphs.length,
    mainExtent: extent,
    from: shownFrom,
    to: shownTo,
  );
  double condense(double extentAlongColumn) =>
      wordCondensation(extent: extentAlongColumn, room: cellExtent);
  for (var i = shown.first; i < shown.end; i += 1) {
    final painter = laidOutGlyph(glyphs[i], style);
    paintVerticalTextCell(
      canvas,
      verticalGlyphCell(glyphs[i]),
      painter: painter,
      center: Offset(topCenter.dx, topCenter.dy + centers[i]),
      fontSize: style.fontSize!,
      setWord: setWord,
      maxCrossExtent: maxCrossExtent,
      alongColumnScale: condense,
    );
  }
}

/// How long [text] runs along [axis] at its natural size — its glyphs one
/// after another, none spread over a block and none narrowed into one: the
/// length below which the placers above start narrowing it. [maxCrossExtent]
/// is a column's width, which a glyph standing in it is fitted to first
/// ([verticalGlyphFit]).
double dialogueNaturalExtent(
  String text, {
  required Axis axis,
  required TextStyle style,
  double maxCrossExtent = double.infinity,
}) {
  var extent = 0.0;
  for (final glyph in text.characters) {
    final painter = laidOutGlyph(glyph, style);
    if (axis == Axis.horizontal) {
      extent += painter.width;
      continue;
    }
    final (:turned, :scale) = verticalGlyphFit(
      verticalGlyphCell(glyph),
      painter: painter,
      fontSize: style.fontSize!,
      room: (across: maxCrossExtent, span: 0),
    );
    extent += verticalGlyphAdvance(
      turned: turned,
      painter: painter,
      fontSize: style.fontSize!,
      scale: scale,
    );
  }
  return extent;
}
