import 'dart:math' as math;

import '../models/cel_text.dart';
import '../models/text_cel_style.dart';

/// THE EDITS A TEXT'S LETTERS TAKE (R9-rest, the text tool) — typing into
/// it, and changing how its letters are set — as values: a content in, a
/// content out, and the engine nowhere.
///
/// Places are counted the way the engine and the keyboard count them: in
/// UTF-16 code units of [CelTextContent.text].

/// A stretch of a text's letters: from [start] up to, not including, [end].
typedef CelTextRange = ({int start, int end});

/// The letters a LETTER SETTING speaks for, given what is selected in the
/// text: the selected letters — or, with none selected, every letter.
///
/// 🚨★★★THE ONE RULE EVERY LETTER SETTING KEEPS, read and written alike.
/// 🗣️유저 2026-10-02: 「선택해서 그 상태에서 도구설정에서 폰트바꾸면 해당
/// 텍스트박스 설정 자동으로 바꿈 … 텍스트를 선택하고 조절하면 일부만 텍스트
/// 조절」, and 2026-10-06 of the colour: 「선택안하고 색 바꾸면 해당 텍스트
/// 전체 색 바꾸고 선택하고 바꾸면 선택된부분만 바꾸는 **공용화할 텍스트
/// 도구설정 로직** 그대로 따라감」. So the value a setting SHOWS and the
/// letters a change of it REACHES are asked here, both, and no setting has a
/// rule of its own.
///
/// ⚠️A caret alone selects nothing: it is the whole text, as a text
/// selected by its box is. There is no 「the next letter typed」 to set —
/// a letter typed wears what stands beside it ([celTextWithLetters]).
CelTextRange celTextLettersSpokenFor(
  CelTextContent content, {
  required int selectionStart,
  required int selectionEnd,
}) => selectionStart == selectionEnd
    ? (start: 0, end: content.text.length)
    : (
        start: math.min(selectionStart, selectionEnd),
        end: math.max(selectionStart, selectionEnd),
      );

/// [content] with the letters of [range] gone and [letters] in their place.
///
/// What is typed wears what was there: over a selection, the first letter
/// it replaces; between letters, the one before it — at the very start,
/// the first. Only a text with NO letters has nothing to go by, and there
/// they wear [nextLetterStyle].
CelTextContent celTextWithLetters(
  CelTextContent content, {
  required CelTextRange range,
  required String letters,
  required TextLetterStyle nextLetterStyle,
}) {
  final length = content.text.length;
  RangeError.checkValidRange(range.start, range.end, length);
  final TextLetterStyle style;
  if (content.isEmpty) {
    style = nextLetterStyle;
  } else if (range.start < range.end) {
    style = _styleAt(content, range.start);
  } else {
    style = _styleAt(content, range.start == 0 ? 0 : range.start - 1);
  }
  return content.copyWith(
    spans: [
      ..._cut(content.spans, 0, range.start),
      CelTextSpan(text: letters, style: style),
      ..._cut(content.spans, range.end, length),
    ],
  );
}

/// [content] with each letter of [range] set as [change] makes of how it
/// was set — every letter keeps what [change] leaves alone, so a text in
/// three sizes given one colour is still in three sizes.
CelTextContent celTextRestyled(
  CelTextContent content, {
  required CelTextRange range,
  required TextLetterStyle Function(TextLetterStyle style) change,
}) {
  final length = content.text.length;
  RangeError.checkValidRange(range.start, range.end, length);
  return content.copyWith(
    spans: [
      ..._cut(content.spans, 0, range.start),
      for (final span in _cut(content.spans, range.start, range.end))
        CelTextSpan(text: span.text, style: change(span.style)),
      ..._cut(content.spans, range.end, length),
    ],
  );
}

/// How the letters of [range] are set: one style for each run of them, in
/// reading order — a single one when they are all set alike.
List<TextLetterStyle> celTextStylesOf(
  CelTextContent content,
  CelTextRange range,
) {
  RangeError.checkValidRange(range.start, range.end, content.text.length);
  return [
    for (final span in _cut(content.spans, range.start, range.end))
      span.style,
  ];
}

/// The ONE replacement that turns [before] into [after]: the letters of
/// the range, in [before], gave way to `letters`.
///
/// A keyboard — and an IME most of all — reports the text it left, not the
/// edit it made, so the edit is read back from the two.
///
/// [caretAfter] is where the caret stands in [after]. What follows a caret
/// was there before the edit, so the tail is matched first and only up to
/// it: typed into a run of the same letter, the new one is then the one AT
/// the caret, and wears what stands beside it there.
({CelTextRange range, String letters}) textReplacementBetween(
  String before,
  String after, {
  int? caretAfter,
}) {
  final shorter = math.min(before.length, after.length);
  final tailLimit = caretAfter == null
      ? shorter
      : math.min(shorter, after.length - caretAfter);
  var tail = 0;
  while (tail < tailLimit &&
      before.codeUnitAt(before.length - 1 - tail) ==
          after.codeUnitAt(after.length - 1 - tail)) {
    tail += 1;
  }
  var head = 0;
  while (head < shorter - tail &&
      before.codeUnitAt(head) == after.codeUnitAt(head)) {
    head += 1;
  }
  return (
    range: (start: head, end: before.length - tail),
    letters: after.substring(head, after.length - tail),
  );
}

/// The pieces of [spans] that lie from [from] up to [to].
List<CelTextSpan> _cut(List<CelTextSpan> spans, int from, int to) {
  final pieces = <CelTextSpan>[];
  var at = 0;
  for (final span in spans) {
    final end = at + span.text.length;
    final cutFrom = math.max(from, at);
    final cutTo = math.min(to, end);
    if (cutFrom < cutTo) {
      pieces.add(
        CelTextSpan(
          text: span.text.substring(cutFrom - at, cutTo - at),
          style: span.style,
        ),
      );
    }
    at = end;
  }
  return pieces;
}

/// How the letter at [offset] is set.
TextLetterStyle _styleAt(CelTextContent content, int offset) =>
    _cut(content.spans, offset, offset + 1).single.style;
