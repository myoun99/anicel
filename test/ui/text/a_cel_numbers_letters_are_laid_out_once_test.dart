import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/cel_number_letters.dart';
import 'package:anicel/src/ui/text/cel_number_paint.dart';

/// 🔬card paint-walk-redoes-the-same-work-each-step (2026-10-27): a stroke's
/// every step laid each numbered row's letters out twice — the buffer's
/// bounds and the letters themselves — though only their text, their colour
/// and the fonts there are decide the layout. Where the letters stand and
/// how large is the paint's own transform.
///
/// The oracle is the paragraph a paint DRAWS: letters laid out once are the
/// same paragraph at every paint.
class _Paragraphs implements ui.Canvas {
  final drawn = <ui.Paragraph>[];

  @override
  void drawParagraph(ui.Paragraph paragraph, ui.Offset offset) =>
      drawn.add(paragraph);

  @override
  int getSaveCount() => 1;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

List<ui.Paragraph> _drawnBy(void Function(ui.Canvas canvas) paint) {
  final canvas = _Paragraphs();
  paint(canvas);
  return canvas.drawn;
}

CelNumberLetters _letters(
  String text, {
  int color = 0xFF000000,
  CanvasPoint? center,
  CanvasPoint? scale,
}) => CelNumberLetters(
  text: text,
  color: color,
  center: center ?? CanvasPoint(x: 40, y: 30),
  scale: scale ?? CanvasPoint(x: 1, y: 1),
);

void main() {
  testWidgets('the same letters anywhere, at any size, are the one '
      'layout', (tester) async {
    final here = celNumberLayoutOf(_letters('A1'));

    expect(
      celNumberLayoutOf(
        _letters(
          'A1',
          center: CanvasPoint(x: 400, y: 300),
          scale: CanvasPoint(x: 2, y: 3),
        ),
      ),
      same(here),
      reason: '🚨the letters were laid out again where they stand elsewhere',
    );
    expect(
      celNumberBox(_letters('A1', center: CanvasPoint(x: 400, y: 300))),
      isNot(celNumberBox(_letters('A1'))),
      reason: '⛔전제: where they stand is still theirs',
    );
  });

  testWidgets('another text, another colour, or a font registered since is '
      'another layout', (tester) async {
    final here = celNumberLayoutOf(_letters('B2'));

    expect(
      celNumberLayoutOf(_letters('B3')),
      isNot(same(here)),
      reason: '🚨another text answered with these letters',
    );
    expect(
      celNumberLayoutOf(_letters('B2', color: 0xFFFF0000)),
      isNot(same(here)),
      reason: '🚨another colour answered with these letters',
    );

    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      SystemChannels.system.name,
      SystemChannels.system.codec.encodeMessage(<String, Object?>{
        'type': 'fontsChange',
      }),
      (_) {},
    );

    expect(
      celNumberLayoutOf(_letters('B2')),
      isNot(same(here)),
      reason: '🚨letters laid out before the fonts changed outlived them',
    );
  });

  testWidgets('a cel number draws, at every paint, the letters it laid out '
      'once', (tester) async {
    List<ui.Paragraph> paint(CelNumberLetters letters) =>
        _drawnBy((canvas) => paintCelNumber(canvas, letters));

    final first = paint(_letters('C4'));

    expect(first, isNotEmpty, reason: 'LIVENESS: the letters painted');
    final again = paint(
      _letters('C4', center: CanvasPoint(x: 10, y: 90)),
    );
    expect(again, hasLength(first.length));
    for (var i = 0; i < first.length; i += 1) {
      expect(
        identical(again[i], first[i]),
        isTrue,
        reason: '🚨a second paint laid pass $i out again',
      );
    }
  });

  testWidgets('letters pushed out by 64 others are let go of', (
    tester,
  ) async {
    final drawn = _drawnBy(
      (canvas) => paintCelNumber(canvas, _letters('pushed out')),
    );
    expect(drawn, isNotEmpty, reason: 'LIVENESS: the letters painted');
    expect(drawn.first.debugDisposed, isFalse, reason: 'held');

    // Whatever another test left behind is older, and goes first.
    for (var i = 0; i < 64; i += 1) {
      celNumberLayoutOf(_letters('other $i'));
    }

    expect(
      drawn.first.debugDisposed,
      isTrue,
      reason: '🚨a layout let go of kept its painters',
    );
  });
}
