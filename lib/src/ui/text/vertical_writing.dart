import 'dart:math' as math;

// For `String.characters` — grapheme clusters, so a combining voiced mark
// rides its base character instead of claiming a cell.
import 'package:flutter/widgets.dart';

/// Japanese VERTICAL WRITING (縦書き) — one table for the whole app.
///
/// Before R10 R6 this knowledge existed twice and disagreed: the timesheet
/// painter carried a seven-character rotation set (UI-R13 #3) while the
/// section band's widget stacked raw glyphs, so `ー` stayed a horizontal
/// bar there. Two tables means the bug is always in the one nobody looked
/// at, so the table moved here and both surfaces read it.
///
/// The rules are the standard ones — JIS X 4051 / the W3C's Requirements
/// for Japanese Text Layout — the same set Photoshop, CSP and InDesign
/// implement. A character in a vertical column does one of four things:
///
/// 1. [VerticalGlyphForm.rotated] — turns 90° clockwise. The long-vowel bar
///    and the whole bracket family read as strokes ALONG the column, so
///    stacking them un-rotated is 가로쓰기 in disguise.
/// 2. [VerticalGlyphForm.shifted] — stays upright but moves to the opposite
///    corner of its em box. `。` sits bottom-left when set horizontally and
///    top-right when set vertically; fonts ship this as the `vert` feature,
///    which we cannot count on reaching every glyph through Flutter's
///    shaper, so we move it ourselves.
/// 3. [VerticalGlyphForm.tateChuYoko] — 縦中横: a short run of digits is set
///    HORIZONTALLY inside a single cell. This is not a trick to save space;
///    it is how a paper timesheet writes a cel number, and it is why `A12`
///    costs two cells here instead of three.
/// 4. [VerticalGlyphForm.upright] — everything else: kanji, kana, 々〆〇,
///    single roman letters.
///
/// This library is pure: it decides WHAT each cell is and HOW BIG the cells
/// are. Drawing lives in `vertical_writing_text.dart`, which is the one
/// renderer both the widget and the timesheet painter go through.

/// What a character does when the column runs top-to-bottom.
enum VerticalGlyphForm {
  /// Set as-is, centered in its cell.
  upright,

  /// Turned 90° clockwise.
  rotated,

  /// Upright, but moved to the top-right of its cell.
  shifted,

  /// A digit run set horizontally inside one cell.
  tateChuYoko,
}

/// Characters that ROTATE 90°.
///
/// Long vowels and dashes first (the original timesheet set, kept whole),
/// then the bracket families — those were missing everywhere, and the
/// user's real cut folders carry process names like `[연출]` and `[작감]`,
/// so an un-rotated `[` is not a corner case.
const Set<String> verticalRotatedChars = {
  // Long vowels, dashes, tildes, low lines.
  'ー', 'ｰ', '－', '‐', '‑', '‒', '–', '—', '―', '~', '〜', '～', '＿', '_', '-',
  // Brackets and quotes — both widths of each pair.
  '（', '）', '(', ')',
  '〔', '〕',
  '［', '］', '[', ']',
  '｛', '｝', '{', '}',
  '〈', '〉',
  '《', '》',
  '「', '」',
  '『', '』',
  '【', '】',
  '〖', '〗',
  '〘', '〙',
  '〚', '〛',
  '＜', '＞', '<', '>',
  // Ellipses.
  '…', '‥', '⋯',
  // Equals and colons.
  '＝', '=', '：', '；', '‖', '∥',
};

/// Full-width punctuation: swaps corners outright, bottom-left to top-right.
const Set<String> verticalCornerShiftedChars = {'、', '。', '，', '．'};

/// Small kana and the voiced-sound marks: these only LEAN toward the
/// top-right, so they move by [verticalSmallKanaShiftEm], not a half em.
const Set<String> verticalLeaningChars = {
  'ぁ', 'ぃ', 'ぅ', 'ぇ', 'ぉ', 'っ', 'ゃ', 'ゅ', 'ょ', 'ゎ', 'ゕ', 'ゖ',
  'ァ', 'ィ', 'ゥ', 'ェ', 'ォ', 'ッ', 'ャ', 'ュ', 'ョ', 'ヮ', 'ヵ', 'ヶ',
  '゛', '゜', '゙', '゚',
};

/// How far a corner-swapping glyph moves — right and up by half its em, the
/// distance between the bottom-left and top-right quadrants of the box.
const double verticalCornerShiftEm = 0.5;

/// How far a leaning glyph moves. Small kana are drawn near the middle of
/// their box already, so the vertical form is a nudge, not a swap.
const double verticalSmallKanaShiftEm = 0.15;

/// The default 縦中横 run length. Two is the JIS rule and the number the
/// user confirmed: `A12` becomes `A` + `12`. Longer runs stay upright one
/// digit per cell rather than being cut at an arbitrary place.
const int verticalTateChuYokoDigits = 2;

bool _isDigit(String char) {
  if (char.length != 1) {
    return false;
  }
  final code = char.codeUnitAt(0);
  // ASCII 0-9, then full-width ０-９.
  return (code >= 0x30 && code <= 0x39) || (code >= 0xFF10 && code <= 0xFF19);
}

/// The form [char] takes on its own — [VerticalGlyphForm.tateChuYoko] is
/// never returned here because it is a property of a RUN, not a character.
VerticalGlyphForm verticalGlyphForm(String char) {
  if (verticalRotatedChars.contains(char)) {
    return VerticalGlyphForm.rotated;
  }
  if (verticalCornerShiftedChars.contains(char) ||
      verticalLeaningChars.contains(char)) {
    return VerticalGlyphForm.shifted;
  }
  return VerticalGlyphForm.upright;
}

/// The em fraction [char] moves right and up. Zero unless it is shifted.
double verticalGlyphShiftEm(String char) {
  if (verticalCornerShiftedChars.contains(char)) {
    return verticalCornerShiftEm;
  }
  if (verticalLeaningChars.contains(char)) {
    return verticalSmallKanaShiftEm;
  }
  return 0;
}

/// One cell of a vertical column: the text that goes in it and what that
/// text does. Cells are the unit the fit math counts — which is the whole
/// point of 縦中横, since it makes a two-digit number cost one cell.
class VerticalTextCell {
  const VerticalTextCell({
    required this.text,
    required this.form,
    this.shiftEm = 0,
  });

  final String text;
  final VerticalGlyphForm form;

  /// Right-and-up offset as a fraction of the font size; see
  /// [verticalGlyphShiftEm].
  final double shiftEm;

  @override
  String toString() => 'VerticalTextCell($text, ${form.name})';

  @override
  bool operator ==(Object other) =>
      other is VerticalTextCell &&
      other.text == text &&
      other.form == form &&
      other.shiftEm == shiftEm;

  @override
  int get hashCode => Object.hash(text, form, shiftEm);
}

/// Splits [text] into the cells of one vertical column, top to bottom.
///
/// Runs of at most [tateChuYokoDigits] digits collapse into a single
/// horizontal cell; everything else is one character per cell. Iterates
/// grapheme clusters, so a combining voiced mark rides its base character
/// instead of claiming a cell of its own.
List<VerticalTextCell> verticalTextCells(
  String text, {
  int tateChuYokoDigits = verticalTateChuYokoDigits,
}) {
  if (text.isEmpty) {
    return const [];
  }
  final glyphs = text.characters.toList(growable: false);
  final cells = <VerticalTextCell>[];
  var index = 0;
  while (index < glyphs.length) {
    final glyph = glyphs[index];
    if (tateChuYokoDigits >= 2 && _isDigit(glyph)) {
      var end = index;
      while (end < glyphs.length && _isDigit(glyphs[end])) {
        end += 1;
      }
      final runLength = end - index;
      if (runLength >= 2 && runLength <= tateChuYokoDigits) {
        cells.add(
          VerticalTextCell(
            text: glyphs.sublist(index, end).join(),
            form: VerticalGlyphForm.tateChuYoko,
          ),
        );
        index = end;
        continue;
      }
      // A lone digit, or a run too long to condense: upright, one per cell.
      for (var i = index; i < end; i += 1) {
        cells.add(
          VerticalTextCell(text: glyphs[i], form: VerticalGlyphForm.upright),
        );
      }
      index = end;
      continue;
    }
    cells.add(
      VerticalTextCell(
        text: glyph,
        form: verticalGlyphForm(glyph),
        shiftEm: verticalGlyphShiftEm(glyph),
      ),
    );
    index += 1;
  }
  return cells;
}

/// The size a vertical column settles on: how tall each cell is, how big
/// the glyphs are, and how much of the host the column fills.
class VerticalTextFit {
  const VerticalTextFit({
    required this.cellExtent,
    required this.fontSize,
    required this.totalExtent,
  });

  final double cellExtent;
  final double fontSize;
  final double totalExtent;
}

/// The SHRINK rule, shared so screen and print pack a column identically.
///
/// Cells take their natural extent until there are more of them than the
/// span holds, at which point they pack evenly and the glyphs shrink with
/// them. [cellPadding] is the leading the host wants kept between glyphs:
/// the timesheet's is an absolute 3px (its rows are a fixed height), the
/// widget's is whatever its line-height factor works out to.
VerticalTextFit verticalTextFit({
  required int cellCount,
  required double mainExtent,
  required double naturalCellExtent,
  required double maxFontSize,
  double minFontSize = 4,
  double cellPadding = 3,
}) {
  if (cellCount <= 0 || maxFontSize <= 0) {
    return VerticalTextFit(
      cellExtent: 0,
      fontSize: maxFontSize,
      totalExtent: 0,
    );
  }
  final cellExtent = math.min(naturalCellExtent, mainExtent / cellCount);
  final fontSize = math
      .min(maxFontSize, cellExtent - cellPadding)
      .clamp(math.min(minFontSize, maxFontSize), maxFontSize)
      .toDouble();
  return VerticalTextFit(
    cellExtent: cellExtent,
    fontSize: fontSize,
    totalExtent: cellExtent * cellCount,
  );
}
