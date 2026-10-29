import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/text/word_bake.dart';
import 'package:anicel/src/ui/text/word_condensation.dart';

import '../../helpers/word_bakes.dart';

/// 🔬frame-panels-build-in-one-frame (10-28) — a word painter that answers
/// what its picture is drawn from ([RepaintOnWordBakes.pictureKey]) draws
/// the picture kept for an equal answer instead of setting its words again:
/// a row built again — a tab opened again — draws what the row it replaces
/// set.

/// A word in a red ink, laid out.
TextPainter _word(String text) => TextPainter(
  text: TextSpan(
    text: text,
    style: const TextStyle(fontSize: 12, color: Color(0xFFD00000)),
  ),
  textDirection: TextDirection.ltr,
)..layout();

/// Counts its paints in [painted]; its picture is kept by [drawnFrom].
class _KeptWords extends CustomPainter with RepaintOnWordBakes {
  _KeptWords(
    this.drawnFrom,
    this.painted, {
    this.word,
    this.fit = wordFitsAsItIs,
    this.inside,
  });

  final Object? drawnFrom;
  final ValueNotifier<int> painted;
  final TextPainter? word;
  final WordFit fit;

  /// Another word painter this one paints into its own picture.
  final CustomPainter? inside;

  @override
  Object? get pictureKey => drawnFrom;

  @override
  void paintWords(Canvas canvas, Size size) {
    painted.value += 1;
    if (word case final word?) {
      paintFittedText(canvas, word, Offset.zero, fit);
    }
    inside?.paint(canvas, size);
  }

  @override
  bool shouldRepaint(_KeptWords oldDelegate) => true;
}

class _AnotherKind extends _KeptWords {
  _AnotherKind(super.drawnFrom, super.painted);
}

void main() {
  const size = Size(40, 20);
  const narrowed = (x: 0.25, y: 1.0);

  void paintOnce(CustomPainter painter, [Size at = size]) {
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder), at);
    recorder.endRecording().dispose();
  }

  Widget showing(CustomPainter painter) =>
      Center(child: CustomPaint(size: size, painter: painter));

  testWidgets('a painter draws the picture kept for an equal answer — by any '
      'painter of its kind — and paints its words for any other', (
    tester,
  ) async {
    final painted = ValueNotifier(0);
    paintOnce(_KeptWords(('row', 1), painted));
    paintOnce(_KeptWords(('row', 1), painted));
    expect(
      painted.value,
      1,
      reason: 'a painter built again draws what the one it replaces set',
    );
    paintOnce(_KeptWords(('row', 2), painted));
    expect(painted.value, 2, reason: 'another answer');
    paintOnce(_KeptWords(('row', 1), painted), const Size(40, 30));
    expect(painted.value, 3, reason: 'another size');
    paintOnce(_AnotherKind(('row', 1), painted));
    expect(
      painted.value,
      4,
      reason: 'an equal answer from another kind of painter is not its '
          'picture',
    );
    paintOnce(_KeptWords(null, painted));
    paintOnce(_KeptWords(null, painted));
    expect(painted.value, 6, reason: 'no answer paints at every paint');
  });

  testWidgets('the pixels a bake is cut for are in what a picture is drawn '
      'from', (tester) async {
    final painted = ValueNotifier(0);
    paintOnce(_KeptWords('a row over a screen', painted));
    final cutFor = wordBakePixelRatio();
    final another = cutFor == 2 ? 1.0 : 2.0;
    tester.view.devicePixelRatio = another;
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pump();
    expect(wordBakePixelRatio(), another, reason: 'fixture');
    paintOnce(_KeptWords('a row over a screen', painted));
    expect(painted.value, 2);
  });

  testWidgets('🚨a paint that drew a word from a stand-in is not kept — the '
      'paint its landing wakes is', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    final painted = ValueNotifier(0);
    _KeptWords row() => _KeptWords(
      'a row whose word is narrowed',
      painted,
      word: _word('ねこ'),
      fit: narrowed,
    );
    await tester.pumpWidget(showing(row()));
    await tester.pumpWidget(showing(row()));
    expect(
      painted.value,
      2,
      reason: 'the bake is on its way, and a kept stand-in would stand in '
          'for it for as long as the picture is kept',
    );
    await pumpUntilAWordBakeLands(tester);
    expect(painted.value, 3, reason: 'fixture: the landing paints it again');
    await tester.pumpWidget(showing(row()));
    expect(painted.value, 3, reason: 'drawn from its bake, it is kept');
  });

  testWidgets('a painter painted inside another drew its stand-ins into it: '
      'the outer picture is not kept either', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    final painted = ValueNotifier(0);
    _KeptWords row() => _KeptWords(
      'a row with a narrowed word inside it',
      painted,
      inside: _KeptWords(
        null,
        ValueNotifier(0),
        word: _word('いぬ'),
        fit: narrowed,
      ),
    );
    await tester.pumpWidget(showing(row()));
    await tester.pumpWidget(showing(row()));
    expect(painted.value, 2);
  });
}
