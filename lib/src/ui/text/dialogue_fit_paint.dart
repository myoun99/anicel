import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/se_dialogue_spacing.dart';
import '../timeline/timeline_cell_style.dart'
    show TimelineBlockWordGrowth, timelineBlockWordStart;
import 'dialogue_fit_layout.dart';
import 'laid_out_glyph.dart';
import 'word_condensation.dart';
import 'vertical_writing.dart' show VerticalTextCell;
import 'vertical_writing_text.dart';

/// SE dialogue down the covered rows — each glyph on the row its block's
/// [spacing] stands it on, sharing [dialogueGlyphSlots] with the timeline
/// overlay so screen and print place glyphs identically (F-496 ③). Never
/// truncates: a glyph the rows have no room for narrows into what is left.
///
/// The FORMS come from the app's one vertical-writing table, like every
/// other column on this sheet. They used not to — this placer stacked
/// every glyph upright, so a `ー` inside dialogue lay across the column
/// while the notation word two columns over rotated it.
///
/// A glyph is a block word down the column ([timelineBlockWordStart]):
/// centred on its row while it fits it, and past that it grows down from
/// the row's top into the rows its koma give it — narrowing, by the row's
/// own [wordCondensation] (F-93), only past those.
///
/// [topCenter] is the top of the column on its centre line and [extent]
/// how far down its [frames] rows run; [style] carries the whole look, so
/// the screen's w600 12pt and the sheet's regular 9pt are values rather
/// than two placers. `style.fontSize` must be set — the vertical cell
/// sizes against it. [setWord] is how the host sets a glyph
/// ([WordSetter]).
///
/// [shownFrom] and [shownTo], down from [topCenter], are a WINDOW on the
/// column: the text is still laid out over all of [extent], and only the
/// glyphs whose row the window holds are painted, each whole and where
/// that layout lays it ([dialogueGlyphsShownIn]) — a cut, or a page half,
/// sees its part of a block that runs on past it (F-358).
void paintDialogueFitColumn(
  Canvas canvas,
  String text, {
  required Offset topCenter,
  required double extent,
  required int frames,
  required SeDialogueSpacing spacing,
  required TextStyle style,
  required WordSetter setWord,
  double maxCrossExtent = double.infinity,
  double shownFrom = double.negativeInfinity,
  double shownTo = double.infinity,
}) {
  final glyphs = text.characters.toList(growable: false);
  final slots = dialogueGlyphSlots(
    glyphCount: glyphs.length,
    frames: frames,
    mainExtent: extent,
    spacing: spacing,
  );
  final shown = dialogueGlyphsShownIn(slots, from: shownFrom, to: shownTo);
  final fontSize = style.fontSize!;
  for (var i = shown.first; i < shown.end; i += 1) {
    final cell = verticalGlyphCell(glyphs[i]);
    final painter = laidOutGlyph(glyphs[i], style);
    final slot = slots[i];
    final advance = _advanceDownColumn(
      cell,
      painter,
      fontSize: fontSize,
      maxCrossExtent: maxCrossExtent,
    );
    final condense = wordCondensation(extent: advance, room: slot.roomExtent);
    final laid = advance * condense;
    final start = timelineBlockWordStart(
      cellStart: slot.cellStart,
      cellExtent: slot.cellExtent,
      wordExtent: laid,
      growth: TimelineBlockWordGrowth.towardBlockEnd,
    );
    paintVerticalTextCell(
      canvas,
      cell,
      painter: painter,
      center: Offset(topCenter.dx, topCenter.dy + start + laid / 2),
      fontSize: fontSize,
      setWord: setWord,
      maxCrossExtent: maxCrossExtent,
      alongColumnScale: (_) => condense,
    );
  }
}

/// How long the longest glyph of [text] runs along [axis] at its natural
/// size — none narrowed: the length past which a glyph's room
/// ([dialogueGlyphSlots]) starts narrowing the dialogue. [maxCrossExtent]
/// is a column's width, which a glyph standing in it is fitted to first
/// ([verticalGlyphFit]).
double dialogueLongestGlyph(
  String text, {
  required Axis axis,
  required TextStyle style,
  double maxCrossExtent = double.infinity,
}) {
  var longest = 0.0;
  for (final glyph in text.characters) {
    final painter = laidOutGlyph(glyph, style);
    longest = math.max(
      longest,
      axis == Axis.horizontal
          ? painter.width
          : _advanceDownColumn(
              verticalGlyphCell(glyph),
              painter,
              fontSize: style.fontSize!,
              maxCrossExtent: maxCrossExtent,
            ),
    );
  }
  return longest;
}

/// How far [cell] runs down a column [maxCrossExtent] wide at its natural
/// size: its form, fitted to the width first ([verticalGlyphFit]) — what
/// [paintVerticalTextCell] lays it at.
double _advanceDownColumn(
  VerticalTextCell cell,
  TextPainter painter, {
  required double fontSize,
  required double maxCrossExtent,
}) {
  final (:turned, :scale) = verticalGlyphFit(
    cell,
    painter: painter,
    fontSize: fontSize,
    room: (across: maxCrossExtent, span: 0),
  );
  return verticalGlyphAdvance(
    turned: turned,
    painter: painter,
    fontSize: fontSize,
    scale: scale,
  );
}
