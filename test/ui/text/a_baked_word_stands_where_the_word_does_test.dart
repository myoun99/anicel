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

TextPainter _word(String text, double fontSize) => TextPainter(
  text: TextSpan(
    text: text,
    style: TextStyle(fontSize: fontSize, color: const Color(0xFF000000)),
  ),
  textDirection: TextDirection.ltr,
)..layout();

/// Where a box's ink is: its weight, the centre of that weight, and the
/// rows that hold any.
typedef _Ink = ({double sum, double cx, double cy, List<int> rows});

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
  return (sum: sum, cx: sumX / sum, cy: sumY / sum, rows: rows);
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
Future<_Ink> _drawnStraight(TextPainter word, double dpr) async {
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
  return _inkOf(alpha, width, height);
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
                closeTo((whole.cx - 1) * fx, 0.5),
                reason: '$why: along the line it is the same word, narrower',
              );
              expect(
                narrow.sum / (whole.sum * fx),
                closeTo(1, 0.25),
                reason: '$why: and as much ink as that',
              );
            }
          }
        }
      }
    });
  });

  testWidgets('at and above the legible size an un-narrowed word\'s bake '
      'is the word drawn straight', (tester) async {
    await tester.runAsync(() async {
      for (final size in [12.0, 13.0, 20.0]) {
        for (final dpr in [1.0, 1.5, 2.0]) {
          final word = _word('3a', size);
          final whole = await _baked(word, 1, dpr);
          final straight = await _drawnStraight(word, dpr);
          expect(whole.rows, straight.rows, reason: '${size}px at $dpr');
          expect(whole.sum, straight.sum, reason: '${size}px at $dpr');
          expect(whole.cy, straight.cy, reason: '${size}px at $dpr');
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
      expect(ink.cy - 1, closeTo((whole.cy - 1) * 0.5, 0.5));
      expect(ink.sum / (whole.sum * 0.5), closeTo(1, 0.25));
    });
  });

  test('each axis is oversampled by its own narrowing — along the line for '
      'a word narrowed along it, down it for one narrowed down it', () {
    expect(wordBakeTimes(12, (x: 0.7, y: 1.0)), (x: 2, y: 1));
    expect(wordBakeTimes(12, (x: 1.0, y: 0.5)), (x: 1, y: 2));
    expect(wordBakeTimes(12, (x: 0.25, y: 0.5)), (x: 4, y: 2));
    expect(wordBakeTimes(12, (x: 1.0, y: 1.0)), wordBakedAsItIs);
    expect(
      wordBakeTimes(9, (x: 1.0, y: 1.0)),
      (x: 2, y: 2),
      reason: 'a type under the legible size is small on both axes',
    );
    expect(wordBakeTimes(null, (x: 1.0, y: 1.0)), wordBakedAsItIs);
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
