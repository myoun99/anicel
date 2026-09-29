import 'dart:ui';

import 'package:flutter/painting.dart' show TextPainter;

/// How far a WORD is narrowed along one axis so it keeps to its room — THE
/// rule every word in a block obeys, on each axis on its own.
///
/// F-93 (유저 2026-09-12): 「se블록의 대사 텍스트. 타임라인 줌을 낮추면 대사
/// 글자끼리 겹쳐져서 시인성이 안좋음. 이렇게 겹쳐질땐 글자 한글자의 좌우 길이?
/// 를 줄여서 한 칸에 한 글자라는 느낌이 나도록」. It was the SE dialogue's rule
/// alone until the user made it every block word's
/// (`block-word-size-at-zoom-Q1` 답 B, 2026-09-24): 「글자크기 그냥 유지하고
/// 블록의 모든 공간 쓸수있게하고, 블록보다 작아지면 가로크기만 줄인다」 —
/// 「법같은거 최대한 통일하면서. 컷블록의 텍스트든 se텍스트든 뭐든」.
/// ↩️A frame block's name and length used to SHRINK their type with the cell
/// (R26 #38, `timelineFittedGlyphFontSize`) — height and width together.
///
/// `1` while [extent] fits [room]; the ratio once it would run past it.
/// ⛔Never above `1`: a roomy block spreads nothing and stretches nothing.
/// ⚠️Quantised DOWN to 1/64 so the classic pass and a baked tile narrow a
/// word by the same factor — the tile's glyph bake is keyed on it — and
/// never below 1/64, because a word that fits nowhere still says it is
/// there (R26 #38: 「절대 안 사라지도록」).
double wordCondensation({required double extent, required double room}) {
  if (extent <= room || extent <= 0) {
    return 1.0;
  }
  final steps = (room / extent * _steps).floorToDouble();
  return (steps < 1 ? 1 : steps) / _steps;
}

const double _steps = 64;

/// How far each LETTER GAP of a word gives way before the word narrows — THE
/// tightening every word in a block keeps, along its line.
///
/// 🗣️F-234-Q1 (유저 2026-09-29, 「글자 사이부터 줄이기」): 「좁혀야 할 때 먼저
/// 글자 사이 간격만 줄이고(글자 모양은 또렷하게 그대로), 그래도 모자랄 때만
/// 좁힌다」. A narrowed glyph loses the font's pixel fitting and smears over
/// two pixels (measured: 「1」 one column and dark as it is, two columns and
/// grey at 6% narrowing), so a word a little too long for its block takes the
/// difference out of its letter gaps and keeps its shapes.
///
/// [extent] is the word's natural length along its line and [gaps] the gaps
/// between its letters — a one-letter word has none to give. A gap gives at
/// most [maxGapTightening], the measure the answer came with (「두세 글자
/// 이름엔 줄일 간격이 1~2px 뿐」), stepped up by a quarter pixel so a baked
/// word keys on few variants; [wordCondensation] narrows what is left.
double wordTightening({
  required double extent,
  required int gaps,
  required double room,
}) {
  if (extent <= room || gaps <= 0) {
    return 0;
  }
  final perGap = (extent - room) / gaps;
  final stepped = (perGap / _tighteningStep).ceilToDouble() * _tighteningStep;
  return stepped < maxGapTightening ? stepped : maxGapTightening;
}

/// The most one letter gap gives way ([wordTightening]).
const double maxGapTightening = 1;

const double _tighteningStep = 0.25;

/// The letter gaps of [text] — one fewer than its letters (code points).
int wordLetterGaps(String text) {
  final letters = text.runes.length;
  return letters > 1 ? letters - 1 : 0;
}

/// A word's narrowing on the two screen axes.
typedef WordFit = ({double x, double y});

/// No narrowing at all.
const WordFit wordFitsAsItIs = (x: 1.0, y: 1.0);

/// [word] narrowed onto [room], each axis on its own ([wordCondensation]).
WordFit wordFit(Size word, Size room) => (
  x: wordCondensation(extent: word.width, room: room.width),
  y: wordCondensation(extent: word.height, room: room.height),
);

/// Paints [painter] with its top-left at [origin], narrowed by [fit] — THE
/// way a word is set narrow, so no surface scales a word on its own.
void paintFittedText(
  Canvas canvas,
  TextPainter painter,
  Offset origin, [
  WordFit fit = wordFitsAsItIs,
]) {
  if (fit == wordFitsAsItIs) {
    painter.paint(canvas, origin);
    return;
  }
  canvas
    ..save()
    ..translate(origin.dx, origin.dy)
    ..scale(fit.x, fit.y);
  painter.paint(canvas, Offset.zero);
  canvas.restore();
}

/// Paints [painter] narrowed into [room] and centred in it — a word that
/// owns a box of its own: a flip slot, one glyph's share of a dialogue.
///
/// [word] is the length the word's ink runs, when that is not the painter's
/// own: a word set tighter ([wordTightening]) keeps its last letter's
/// negative spacing out of the ink.
void paintWordCentredIn(
  Canvas canvas,
  TextPainter painter,
  Rect room, {
  Size? word,
}) {
  final size = word ?? painter.size;
  final fit = wordFit(size, room.size);
  paintFittedText(
    canvas,
    painter,
    Offset(
      room.center.dx - size.width * fit.x / 2,
      room.center.dy - size.height * fit.y / 2,
    ),
    fit,
  );
}
