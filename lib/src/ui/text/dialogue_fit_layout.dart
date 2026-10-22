/// Pure layout math for the SE dialogue "fit" rule: the entry's dialogue
/// glyphs spread evenly across the whole block, like justified text on the
/// paper sheet's SE column. Shared by the timeline row overlay and the
/// timesheet painter, so screen and print distribute identically — and a
/// part of the block seen through a window shows what the whole lays there
/// ([dialogueGlyphsShownIn]).
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

/// The glyphs a WINDOW `[from, to)` along a run [mainExtent] long shows, as
/// the indices `[first, end)` of those whose [dialogueGlyphCenters] centre
/// it holds — each still where the WHOLE run lays it.
///
/// 🗣️F-358 (유저 2026-10-14): 「여러 컷에 걸친 se블록이 있을때, 글로벌에선
/// e라는 글자가 보이는 구간인데 로컬에선 T라는게 보인다던가 … 위치는
/// 같도록. 글로벌기준으로」. A cut, or a page half, is a window on the
/// block's one layout. ↩️Each laid its share out again over its own
/// stretch: the cut a sound spilled into spread the whole line over the
/// frames it had left.
///
/// A glyph shows whole, in the one window holding its centre — no window
/// prints half a glyph, and none prints one twice.
({int first, int end}) dialogueGlyphsShownIn({
  required int glyphCount,
  required double mainExtent,
  double from = double.negativeInfinity,
  double to = double.infinity,
}) {
  final centres = dialogueGlyphCenters(
    glyphCount: glyphCount,
    mainExtent: mainExtent,
  );
  int firstAtOrPast(double at) {
    var index = 0;
    while (index < centres.length && centres[index] < at) {
      index += 1;
    }
    return index;
  }

  return (first: firstAtOrPast(from), end: firstAtOrPast(to));
}

// 🪦`dialogueGlyphCondensation` — F-93's narrowing of a glyph into its cell —
// became every block word's rule and moved to `word_condensation.dart`
// (`wordCondensation`): the dialogue's glyphs spread one to a cell and narrow
// into it there, as a name narrows into its block.
