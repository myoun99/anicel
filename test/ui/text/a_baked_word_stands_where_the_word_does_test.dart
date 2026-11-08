import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/ui/text/word_bake.dart';
import 'package:anicel/src/ui/theme/app_theme.dart' show AppTypography;

import '../../helpers/app_faces.dart';

/// F-297 (유저 2026-10-05): 「3a로 글자가 폭이 부족해서 가로 짧아진다거나
/// 할때, 글자의 세로길이나 세로 중앙정렬이 이상해짐. 3a만 이상하게 중앙에서
/// 위에존재하고. 게다가 약간 흐려지는? 이런 문제 원천적으로 해결하고싶음」.
///
/// A name narrowed along its line is drawn from a bake that is rasterised
/// big and averaged down ([bakeWordCoverage]); the names beside it are not
/// narrowed. The two stand in one row only if narrowing a word ALONG its
/// line leaves it alone DOWN the line — the same rows of ink, the same
/// centre. It did not: both axes were oversampled by one scale that was no
/// whole number, and the margin was not scaled with it. 🧪A 12px word
/// narrowed to 0.7 came out 0.76px high, and at 0.85 its 12 rows of ink
/// were spread over 14 (2026-10-07).
///
/// ↩️2026-10-08: the first answer to that asked the RASTERISER for the
/// narrowed word, each axis at its own scale, and these pins were green on
/// Windows and red on the Linux runner — there a glyph drawn under a scale
/// that differs by axis stands a row off ("3" at 9px narrowed to 0.85: rows
/// 0–9 for 1–9). The word is rasterised un-narrowed now, at one scale, and
/// narrowed by the bake's own average.
///
/// ↩️2026-11-08: the GPU engine sets the word and rasters it itself
/// (word-bake-Q1), and the pins on its raster and its average went with it
/// (`kernels/letters/words/tests.rs`: the rows a narrowed word stands on,
/// its margin, the raster byte for byte where nothing is averaged). What
/// is held here is the hand-over — the narrowing the screen draws the word
/// at; where its letters stand, `a_word_goes_to_the_engine_as_it_is_laid
/// _test.dart`.
///
/// ⚠️THE ENGINE'S RASTER IS NOT FLUTTER'S, and word-bake-Q1 chose it so
/// (유저 2026-11-05, its cost said: a narrowed word beside un-narrowed ones
/// Flutter draws may stand off their line until every block word is the
/// engine's). 🔬Measured the same day (flutter_tester; 9–20 px × ratio 1–2
/// × 「3a」 · 「12」 · 「カット」 · 「셀번호」 × three narrowings, 216 bakes):
/// against the bake it replaces, Flutter's raster averaged, the engine's
/// stood −1.5 to +0.8 px off its centre — mostly higher — and inked 0.88 to
/// 1.34 times as much; 48 of the 216 inked the same rows. Flutter hints
/// (BIZ UDPGothic's 「3」 is 9.6 px tall at 12 px, and Flutter draws it 8.6)
/// and puts the baseline on a whole pixel; the engine draws the outline as
/// it is, where the layout put it.

/// [text] at [fontSize] in the app's face, as the Japanese UI sets it.
TextPainter _word(String text, double fontSize) => TextPainter(
  text: TextSpan(
    text: text,
    style: TextStyle(
      fontSize: fontSize,
      color: const Color(0xFF000000),
      fontFamily: AppTypography.familyFor(AppLanguage.ja),
      fontFamilyFallback: AppTypography.fallbackFor(AppLanguage.ja),
    ),
  ),
  textDirection: TextDirection.ltr,
)..layout();

/// Where a box's ink is: its weight and the centre of that weight — and
/// the box.
typedef _Ink = ({
  double sum,
  double cx,
  double cy,
  ({int width, int height}) box,
});

_Ink _inkOf(Uint8List alpha, int width, int height) {
  var sum = 0.0;
  var sumX = 0.0;
  var sumY = 0.0;
  for (var y = 0; y < height; y += 1) {
    for (var x = 0; x < width; x += 1) {
      final a = alpha[y * width + x];
      sum += a;
      sumX += a * (x + 0.5);
      sumY += a * (y + 0.5);
    }
  }
  return (
    sum: sum,
    cx: sumX / sum,
    cy: sumY / sum,
    box: (width: width, height: height),
  );
}

Future<_Ink> _baked(TextPainter word, _Fit fit, double dpr) async {
  final baked = (await bakeWordCoverage(
    word,
    fit: fit,
    dpr: dpr,
    fontSize: word.text!.style!.fontSize,
  ))!;
  return _inkOf(baked.alpha, baked.width, baked.height);
}

typedef _Fit = ({double x, double y});

void main() {
  setUpAll(loadTheAppFaces);

  testWidgets('a narrowed word is handed its narrowing — the box of the '
      'narrowed word and a pixel round, standing where it stood', (
    tester,
  ) async {
    await tester.runAsync(() async {
      for (final size in [9.0, 12.0]) {
        for (final dpr in [1.0, 1.5]) {
          final word = _word('3a', size);
          final whole = await _baked(word, (x: 1, y: 1), dpr);
          // A block word's 64ths, and a column's narrowing, which is none.
          for (final fit in [
            (x: 27 / 64, y: 1.0),
            (x: 0.85, y: 1.0),
            (x: 1.0, y: 0.5),
          ]) {
            final narrow = await _baked(word, fit, dpr);
            final why = '${size}px ×$fit at $dpr';
            expect(
              narrow.box,
              (
                width: (word.width * fit.x * dpr).ceil() + 2,
                height: (word.height * fit.y * dpr).ceil() + 2,
              ),
              reason: '$why: the box is the narrowed word and a pixel round',
            );
            // Where it stood on the axis left alone, and that narrower on
            // the other, from the margin's edge — what the bake's own pins
            // hold of its rows (`words/tests.rs`).
            final (alone, narrowed) = fit.y == 1
                ? ((narrow.cy, whole.cy), (narrow.cx, whole.cx, fit.x))
                : ((narrow.cx, whole.cx), (narrow.cy, whole.cy, fit.y));
            expect(alone.$1, closeTo(alone.$2, 0.02), reason: '$why: alone');
            expect(
              narrowed.$1 - 1,
              closeTo((narrowed.$2 - 1) * narrowed.$3, 0.1),
              reason: '$why: narrower',
            );
            expect(
              narrow.sum / (whole.sum * fit.x * fit.y),
              closeTo(1, 0.02),
              reason: '$why: as much ink as that',
            );
          }
        }
      }
    });
  });

  test('a word is drawn from its bake where some axis of it is under the '
      'legible size — its type times that axis\'s narrowing', () {
    expect(wordIsBaked(12, (x: 0.7, y: 1.0)), isTrue, reason: 'along');
    expect(wordIsBaked(12, (x: 1.0, y: 0.5)), isTrue, reason: 'down');
    expect(wordIsBaked(12, (x: 1.0, y: 1.0)), isFalse);
    expect(
      wordIsBaked(9, (x: 1.0, y: 1.0)),
      isTrue,
      reason: 'a type under the legible size is small on both axes',
    );
    expect(
      wordIsBaked(20, (x: 0.7, y: 1.0)),
      isFalse,
      reason: '14px along the line is drawn well as it is',
    );
    expect(wordIsBaked(20, (x: 0.5, y: 1.0)), isTrue);
    expect(
      wordIsBaked(24, (x: 0.5, y: 1.0)),
      isFalse,
      reason: 'exactly the legible size is legible',
    );
    expect(
      wordIsBaked(24, (x: 1.0, y: 0.5)),
      isFalse,
      reason: 'on either axis',
    );
    expect(wordIsBaked(null, (x: 1.0, y: 1.0)), isFalse);
    expect(
      wordIsBaked(null, (x: 0.99, y: 1.0)),
      isTrue,
      reason: 'a type left unsaid is taken for the legible size',
    );
  });

  test('an axis is oversampled a whole number of times, and only below '
      'the legible size', () {
    for (var type = 1.0; type < 24; type += 0.37) {
      final times = wordBakeScale(type);
      expect(times, times.roundToDouble(), reason: 'type $type');
      expect(times * type, greaterThanOrEqualTo(legibleBakeSize - 1e-9));
      expect(times, greaterThanOrEqualTo(1));
    }
    expect(wordBakeScale(8.4), 2, reason: '12px narrowed to 0.7');
    expect(wordBakeScale(3), 4);
    expect(wordBakeScale(legibleBakeSize), 1);
  });
}
