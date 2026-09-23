/// Pure layout math for the SE dialogue "fit" rule: the entry's dialogue
/// glyphs spread evenly across the whole block, like justified text on the
/// paper sheet's SE column. Shared by the timeline row overlay and the
/// timesheet painter, so screen and print distribute identically.
///
/// Returns the main-axis center for each glyph: glyph `i` of [glyphCount]
/// sits at `(i + 0.5) * mainExtent / glyphCount`. A single glyph centers in
/// the span; zero glyphs yield an empty list.
List<double> dialogueGlyphCenters({
  required int glyphCount,
  required double mainExtent,
}) {
  if (glyphCount <= 0) {
    return const [];
  }
  final step = dialogueGlyphCellExtent(
    glyphCount: glyphCount,
    mainExtent: mainExtent,
  );
  return [for (var i = 0; i < glyphCount; i += 1) (i + 0.5) * step];
}

/// The room ONE glyph has along the flow: the block split evenly, each
/// [dialogueGlyphCenters] centre in the middle of its cell. Zero glyphs have
/// no cell.
double dialogueGlyphCellExtent({
  required int glyphCount,
  required double mainExtent,
}) => glyphCount <= 0 ? 0 : mainExtent / glyphCount;

// 🪦`dialogueGlyphCondensation` — F-93's narrowing of a glyph into its cell —
// became every block word's rule and moved to `word_condensation.dart`
// (`wordCondensation`): the dialogue's glyphs spread one to a cell and narrow
// into it there, as a name narrows into its block.
