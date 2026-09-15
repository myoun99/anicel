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

/// How far a glyph is narrowed ALONG the flow so it keeps to its cell.
///
/// F-93 (유저 2026-09-12): 「se블록의 대사 텍스트. 타임라인 줌을 낮추면 대사
/// 글자끼리 겹쳐져서 시인성이 안좋음. 이렇게 겹쳐질땐 글자 한글자의 좌우 길이?
/// 를 줄여서 한 칸에 한 글자라는 느낌이 나도록」. The glyphs were spread one
/// to a cell and painted at their own size, so a zoomed-out block ran them
/// into each other.
///
/// `1` while [glyphExtent] — the glyph's advance along the flow — fits
/// [cellExtent]; the ratio once it would run past it. Along the flow only:
/// across it the glyph keeps its size. ⛔Never above `1` — a roomy cell
/// spreads the glyphs apart, which is the centres' job, and does not
/// stretch them.
double dialogueGlyphCondensation({
  required double glyphExtent,
  required double cellExtent,
}) => glyphExtent > cellExtent && glyphExtent > 0
    ? cellExtent / glyphExtent
    : 1.0;
