// 🗣️F-524 (유저 2026-11-01): 「텍스트도구나 다른곳에서등 텍스트 쓸때, 2~4를
// 쓴다치면 물결표모양이 위에 붙어서 써짐. 폰트때문인가? 중앙에 써졌으면하는데
// 원인이궁금」 · F-524-Q1: 「나눔고딕의 물결을 쓴다」.
//
// The bundled BIZ files have U+007E taken out of their cmaps, so the order
// sends the keyboard's tilde on to 나눔고딕 ([AppTypography]). What these pin
// is the files themselves: a fresh copy of BIZ brings the high tilde back,
// with nothing else to say so.
//
// By the advance at 100, in the faces the app wears: 나눔고딕's `~` is 65.4,
// BIZ's own was 50.
import 'dart:io';
import 'dart:typed_data';

import 'package:anicel/src/ui/theme/app_theme.dart' show AppTypography;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart' show TtfParser;

import '../../helpers/app_faces.dart';

void main() {
  setUpAll(loadTheAppFaces);

  double widthOf(String text, FontWeight weight) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: AppTypography.bundledFamily,
          fontFamilyFallback: AppTypography.bundledFallback,
          fontSize: 100,
          fontWeight: weight,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    addTearDown(painter.dispose);
    return painter.width;
  }

  for (final weight in const [FontWeight.w400, FontWeight.w700]) {
    testWidgets('the app\'s text sets `~` in 나눔고딕, and what stands round it '
        'in BIZ ($weight)', (tester) async {
      expect(widthOf('~', weight), closeTo(65.4, 0.1));
      expect(widthOf('2', weight), closeTo(76, 0.1), reason: 'BIZ\'s digit');
      for (final wave in ['〜', '～']) {
        expect(
          widthOf(wave, weight),
          closeTo(100, 0.1),
          reason: 'U+${wave.runes.single.toRadixString(16)}: BIZ\'s own, '
              'which sits in the middle',
        );
      }
    });
  }

  // The PDF picks a face by what the file's cmap covers
  // (`_ContePdfPageWriter._covers`), so the same files send it the same way.
  // By their paths: a test that reads a file by a written path runs when the
  // file changes (`affected_tests`), and these files are what it is here for.
  const biz = [
    'assets/fonts/BIZUDPGothic-Regular.ttf',
    'assets/fonts/BIZUDPGothic-Bold.ttf',
  ];
  const nanum = [
    'assets/fonts/NanumGothic-Regular.ttf',
    'assets/fonts/NanumGothic-Bold.ttf',
  ];

  bool covers(String path, String letter) {
    final file = ByteData.view(File(path).readAsBytesSync().buffer);
    return TtfParser(
      file,
    ).charToGlyphIndexMap.containsKey(letter.runes.single);
  }

  test('the PDF reads no `~` in BIZ, and one in 나눔고딕 behind it', () {
    for (final path in biz) {
      expect(covers(path, '~'), isFalse, reason: path);
      expect(covers(path, '}'), isTrue, reason: '$path: the letter before it');
      expect(covers(path, '〜'), isTrue, reason: path);
    }
    for (final path in nanum) {
      expect(covers(path, '~'), isTrue, reason: path);
    }
  });
}
