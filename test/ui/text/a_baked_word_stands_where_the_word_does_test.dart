import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/text/word_bake.dart';

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
/// narrowed by the bake's own average; the pin that says so on EVERY
/// machine is the one on the transform below.

TextPainter _word(String text, double fontSize) => TextPainter(
  text: TextSpan(
    text: text,
    style: TextStyle(fontSize: fontSize, color: const Color(0xFF000000)),
  ),
  textDirection: TextDirection.ltr,
)..layout();

/// A word whose ink hangs one device pixel past its box on every side — a
/// solid block from a pixel before it to a pixel after.
class _OverhungWord extends TextPainter {
  _OverhungWord(double fontSize, this.dpr)
    : super(
        text: TextSpan(
          text: '3a',
          style: TextStyle(fontSize: fontSize, color: const Color(0xFF000000)),
        ),
        textDirection: TextDirection.ltr,
      );

  final double dpr;

  @override
  void paint(Canvas canvas, Offset offset) {
    final pixel = 1 / dpr;
    canvas.drawRect(
      Rect.fromLTRB(-pixel, -pixel, width + pixel, height + pixel),
      Paint()..color = const Color(0xFF000000),
    );
  }
}

/// A word that keeps the transform it was asked to paint under.
class _WatchedWord extends TextPainter {
  _WatchedWord(String text, double fontSize)
    : super(
        text: TextSpan(
          text: text,
          style: TextStyle(fontSize: fontSize, color: const Color(0xFF000000)),
        ),
        textDirection: TextDirection.ltr,
      );

  Float64List? paintedUnder;

  @override
  void paint(Canvas canvas, Offset offset) {
    paintedUnder = canvas.getTransform();
    super.paint(canvas, offset);
  }
}

/// Where a box's ink is: its weight, the centre of that weight, and the
/// rows that hold any — and the box.
typedef _Ink = ({
  double sum,
  double cx,
  double cy,
  List<int> rows,
  ({int width, int height}) box,
});

_Ink _inkOf(Uint8List alpha, int width, int height) {
  var sum = 0.0;
  var sumX = 0.0;
  var sumY = 0.0;
  final rows = <int>[];
  for (var y = 0; y < height; y += 1) {
    var inked = false;
    for (var x = 0; x < width; x += 1) {
      final a = alpha[y * width + x];
      sum += a;
      sumX += a * (x + 0.5);
      sumY += a * (y + 0.5);
      inked = inked || a > 0;
    }
    if (inked) {
      rows.add(y);
    }
  }
  return (
    sum: sum,
    cx: sumX / sum,
    cy: sumY / sum,
    rows: rows,
    box: (width: width, height: height),
  );
}

Future<_Ink> _baked(TextPainter word, double fx, double dpr) async {
  final baked = (await bakeWordCoverage(
    word,
    fit: (x: fx, y: 1.0),
    dpr: dpr,
    fontSize: word.text!.style!.fontSize,
  ))!;
  return _inkOf(baked.alpha, baked.width, baked.height);
}

/// The word drawn straight into the box its un-narrowed bake has: one pixel
/// of margin, then the word.
Future<Uint8List> _drawnStraight(TextPainter word, double dpr) async {
  final width = (word.width * dpr).ceil() + 2;
  final height = (word.height * dpr).ceil() + 2;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)
    ..translate(1, 1)
    ..scale(dpr);
  word.paint(canvas, Offset.zero);
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  picture.dispose();
  final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  image.dispose();
  final alpha = Uint8List(width * height);
  for (var i = 0; i < alpha.length; i += 1) {
    alpha[i] = data.getUint8(i * 4 + 3);
  }
  return alpha;
}

void main() {
  testWidgets('a word narrowed along its line stands on the rows it stood '
      'on — the same ink down the line, at every narrowing, type and '
      'pixel ratio', (tester) async {
    await tester.runAsync(() async {
      for (final size in [9.0, 11.0, 12.0, 13.0]) {
        for (final dpr in [1.0, 1.25, 1.5, 2.0]) {
          for (final text in ['3', '3a']) {
            final word = _word(text, size);
            final whole = await _baked(word, 1, dpr);
            for (final fx in [0.85, 0.7, 0.5, 0.3]) {
              final narrow = await _baked(word, fx, dpr);
              final why = '"$text" ${size}px ×$fx at $dpr';
              expect(
                narrow.box,
                (
                  width: (word.width * fx * dpr).ceil() + 2,
                  height: whole.box.height,
                ),
                reason: '$why: the box is the narrowed word and a pixel round',
              );
              expect(
                narrow.rows,
                whole.rows,
                reason: '$why: 「세로길이」 — the rows were averaged with '
                    'the columns, and 12 rows of ink came out over 14',
              );
              expect(
                narrow.cy,
                closeTo(whole.cy, 0.01),
                reason: '$why: 「3a만 … 위에」 — it stood up to 1.24px high',
              );
              expect(
                narrow.cx - 1,
                closeTo((whole.cx - 1) * fx, 0.1),
                reason: '$why: along the line it is the same word, narrower',
              );
              expect(
                narrow.sum / (whole.sum * fx),
                closeTo(1, 0.02),
                reason: '$why: and as much ink as that',
              );
            }
          }
        }
      }
    });
  });

  testWidgets('at and above the legible size an un-narrowed word\'s bake '
      'is the word drawn straight — byte for byte', (tester) async {
    // 유저 2026-08-28: 「줌인하면 텍스트는 선명하게 보고싶다」. No arm of the
    // bake says so any more — the average of one pixel is that pixel — so
    // this is where it is held.
    await tester.runAsync(() async {
      for (final size in [12.0, 13.0, 20.0]) {
        for (final dpr in [1.0, 1.5, 2.0]) {
          final word = _word('3a', size);
          final whole = (await bakeWordCoverage(
            word,
            fit: (x: 1.0, y: 1.0),
            dpr: dpr,
            fontSize: size,
          ))!;
          final straight = await _drawnStraight(word, dpr);
          expect(
            _inkOf(straight, whole.width, whole.height).sum,
            greaterThan(0),
            reason: 'LIVENESS ${size}px at $dpr: there is a word to compare',
          );
          expect(whole.alpha, straight, reason: '${size}px at $dpr');
        }
      }
    });
  });

  testWidgets('a word narrowed DOWN its line alone is averaged down it — '
      'the other axis\'s turn', (tester) async {
    await tester.runAsync(() async {
      final word = _word('3a', 12);
      final whole = await _baked(word, 1, 1);
      final squat = (await bakeWordCoverage(
        word,
        fit: (x: 1.0, y: 0.5),
        dpr: 1,
        fontSize: 12,
      ))!;
      expect(
        squat.alpha,
        hasLength(squat.width * squat.height),
        reason: 'the box it is blitted by, not the raster it came from',
      );
      final ink = _inkOf(squat.alpha, squat.width, squat.height);
      expect(ink.cx, closeTo(whole.cx, 0.01), reason: 'along: left alone');
      expect(ink.cy - 1, closeTo((whole.cy - 1) * 0.5, 0.1));
      expect(ink.sum / (whole.sum * 0.5), closeTo(1, 0.02));
    });
  });

  testWidgets('the rasteriser is asked for the word as it stands — one '
      'scale for both axes, its type\'s own, whatever the narrowing', (
    tester,
  ) async {
    // ↩️Each axis had its own scale (its own narrowing's) until 2026-10-08,
    // and where a glyph lands under such a scale is the font backend's to
    // say: this is the pin that is red on the old bake on every machine.
    await tester.runAsync(() async {
      for (final (size, times) in [(12.0, 1.0), (9.0, 2.0), (3.0, 4.0)]) {
        for (final dpr in [1.0, 1.5]) {
          for (final fit in [
            (x: 1.0, y: 1.0),
            (x: 0.85, y: 1.0),
            (x: 0.3, y: 1.0),
            (x: 1.0, y: 0.5),
            (x: 0.25, y: 0.5),
          ]) {
            final word = _WatchedWord('3a', size)..layout();
            await bakeWordCoverage(word, fit: fit, dpr: dpr, fontSize: size);
            final under = word.paintedUnder!;
            final why = '${size}px ×$fit at $dpr';
            expect(under[0], dpr * times, reason: '$why: along the line');
            expect(under[5], dpr * times, reason: '$why: down it');
            expect(
              (under[12], under[13]),
              (times, times),
              reason: '$why: one final pixel of margin, in the raster\'s own',
            );
          }
        }
      }
    });
  });

  testWidgets('the bake keeps a pixel of margin on every side — ink that '
      'hangs past the word\'s box is in it, where it hung', (tester) async {
    await tester.runAsync(() async {
      // Un-narrowed, the block fills the box to its last pixel: at a type
      // the rasteriser draws well, and at one rasterised twice over (whose
      // margin is two of the raster's pixels).
      for (final size in [12.0, 9.0]) {
        final word = _OverhungWord(size, 1)..layout();
        final baked = (await bakeWordCoverage(
          word,
          fit: (x: 1.0, y: 1.0),
          dpr: 1,
          fontSize: size,
        ))!;
        expect(
          (baked.width, baked.height),
          (word.width.ceil() + 2, word.height.ceil() + 2),
          reason: 'fixture ${size}px: the word is a whole number of pixels',
        );
        expect(
          baked.alpha.toSet(),
          {255},
          reason: '${size}px: ink to the edge of the box, every side',
        );
      }

      // Narrowed to a half, the margin pixel is half overhang and half what
      // lies past the raster — which is nothing.
      final word = _OverhungWord(12, 1)..layout();
      final baked = (await bakeWordCoverage(
        word,
        fit: (x: 0.5, y: 1.0),
        dpr: 1,
        fontSize: 12,
      ))!;
      final row = baked.alpha.sublist(0, baked.width);
      expect(row.first, 127, reason: 'the margin before the word');
      expect(row.last, 127, reason: 'and the one after it');
      expect(
        row.sublist(1, row.length - 1).toSet(),
        {255},
        reason: 'the word between them',
      );
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
