// ONE MEASURE: a line of UI text measures as a Text lays it out in the same
// place — the context's text scaler and direction, in the style asked for —
// so a layout sized to its words (the import window's table and its column
// popup, the media pool's width floor) is sized to what it will show.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/text/text_measure.dart';

void main() {
  const style = TextStyle(fontSize: 12);

  /// Lays [words] out as Texts at [scale], and hands back a measure taken
  /// in the same place.
  Future<TextMeasure> measureBeside(
    WidgetTester tester, {
    required double scale,
    List<String> words = const [],
  }) async {
    late TextMeasure measure;
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Column(
            children: [
              for (final word in words) Text(word, style: style),
              Builder(
                builder: (context) {
                  measure = TextMeasure(context, style);
                  return const SizedBox.shrink();
                },
              ),
            ],
          ),
        ),
      ),
    );
    return measure;
  }

  testWidgets('a line measures as a Text lays it out beside it — at the '
      'scale the place reads its text at', (tester) async {
    const words = ['.wav', 'bg_street'];
    for (final scale in const [1.0, 2.0]) {
      final measure = await measureBeside(tester, scale: scale, words: words);
      for (final word in words) {
        expect(
          measure.size(word),
          tester.getSize(find.text(word)),
          reason: '"$word" at ×$scale',
        );
      }
    }
  });

  testWidgets('the widest of several lines is the widest one — and of none, '
      'nothing', (tester) async {
    final measure = await measureBeside(tester, scale: 1);

    expect(
      measure.widest(const ['ab', 'abcd', 'abc']),
      measure.size('abcd').width,
    );
    expect(measure.widest(const []), 0);
  });
}
