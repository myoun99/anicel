// ONE MEASURE: a line of UI text measures as a Text lays it out in the same
// place — the context's text scaler and direction, in the style asked for —
// so a layout sized to its words (the import window's table and its column
// popup, the media pool's width floor) is sized to what it will show.
import 'package:flutter/services.dart';
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
    TextStyle measuredIn = style,
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
                  measure = TextMeasure(context, measuredIn);
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

  testWidgets('🚨two measures taken in the same place lay a line out once '
      'between them — a build makes a new measure each time it asks', (
    tester,
  ) async {
    // card frame-panels-build-in-one-frame (2026-10-24): the colour bar's
    // probes were laid out again on every rebuild of the workspace.
    final first = await measureBeside(tester, scale: 1);
    final again = await measureBeside(tester, scale: 1);
    expect(identical(first, again), isFalse, reason: '⛔전제: two measures');
    expect(
      identical(first.size('#000000'), again.size('#000000')),
      isTrue,
      reason: '🚨the second measure laid the line out again',
    );
  });

  testWidgets('a measure taken elsewhere lays the line out for itself — '
      'another scale, another style, or a font registered since', (
    tester,
  ) async {
    const line = '#000000';
    final here = (await measureBeside(tester, scale: 1)).size(line);
    expect(
      (await measureBeside(tester, scale: 2)).size(line),
      isNot(here),
      reason: '🚨a line at ×2 answered with its size at ×1',
    );
    expect(
      (await measureBeside(
        tester,
        scale: 1,
        measuredIn: const TextStyle(fontSize: 24),
      )).size(line),
      isNot(here),
      reason: '🚨a line in a larger style answered with its size in 12',
    );

    // A face registered while the app runs (a canvas letter face) tells
    // the binding the fonts changed — and can set a line differently.
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      SystemChannels.system.name,
      SystemChannels.system.codec.encodeMessage(<String, Object?>{
        'type': 'fontsChange',
      }),
      (_) {},
    );
    final later = (await measureBeside(tester, scale: 1)).size(line);
    expect(later, here, reason: '⛔전제: no face changed what it sets');
    expect(
      identical(later, here),
      isFalse,
      reason: '🚨a size laid out before the fonts changed outlived them',
    );
  });

  test('a number with every digit in turn: the ten, in order, in its shape — '
      'and the digits it is written in where they are not the ten', () {
    expect(
      everyDigitIn((digit) => '1$digit%').join(' '),
      '10% 11% 12% 13% 14% 15% 16% 17% 18% 19%',
    );
    expect(
      everyDigitIn((digit) => digit * 2, digits: '0F').join(' '),
      '00 FF',
    );
  });
}
