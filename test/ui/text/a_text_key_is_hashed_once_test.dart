import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/text/laid_out_glyph.dart';
import 'package:anicel/src/ui/text/word_bake.dart';
import 'package:anicel/src/ui/text/word_condensation.dart';

import '../../helpers/word_bakes.dart';

/// The text caches find what a paint asks for by a key that is HASHED ONCE
/// a lookup (card frame-panels-build-in-one-frame, 2026-10-25): a style's
/// hash walks every field it has and a span's walks its style and every
/// child's, and a storyboard tab's reopen asked the glyph cache for 1,173
/// glyphs and the baked words for 305 — nearly every one a hit, each hashed
/// twice and more.

var _styleHashes = 0;

/// A style that counts its hashes.
class _CountedStyle extends TextStyle {
  const _CountedStyle({super.fontSize, super.color});

  @override
  int get hashCode {
    _styleHashes += 1;
    return super.hashCode;
  }

  @override
  bool operator ==(Object other) => other is _CountedStyle && super == other;
}

class _WordPainter extends CustomPainter with RepaintOnWordBakes {
  _WordPainter(this.word, this.fit);

  final TextPainter word;
  final WordFit fit;

  @override
  void paintWords(Canvas canvas, Size size) =>
      paintFittedText(canvas, word, Offset.zero, fit);

  @override
  bool shouldRepaint(_WordPainter oldDelegate) => false;
}

void main() {
  test('a glyph found in the cache hashes its style once', () {
    const style = _CountedStyle(fontSize: 13.5);
    final first = laidOutGlyph('hashed once', style);
    _styleHashes = 0;
    expect(laidOutGlyph('hashed once', style), same(first));
    expect(_styleHashes, 1);
  });

  testWidgets('a word drawn from its bake hashes its span once in its life', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    const fit = (x: 0.25, y: 1.0);
    // In the one ink its key is set in, so the key holds this very style
    // and its hashes are counted here.
    final word = TextPainter(
      text: const TextSpan(
        text: 'かぎ',
        style: _CountedStyle(fontSize: 12, color: Color(0xFF000000)),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    _styleHashes = 0;
    await tester.pumpWidget(
      Center(
        child: CustomPaint(
          size: const Size(40, 20),
          painter: _WordPainter(word, fit),
        ),
      ),
    );
    await pumpUntilAWordBakeLands(tester);

    expect(
      (Canvas canvas) => paintFittedText(canvas, word, Offset.zero, fit),
      paints..drawImageRect(),
      reason: 'fixture: the word is drawn from its bake',
    );
    for (var paint = 0; paint < 2; paint += 1) {
      final recorder = ui.PictureRecorder();
      paintFittedText(Canvas(recorder), word, Offset.zero, fit);
      recorder.endRecording().dispose();
    }
    expect(_styleHashes, 1);
  });
}
