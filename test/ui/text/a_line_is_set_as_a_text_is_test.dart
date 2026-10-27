import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/text/text_line.dart';

/// A line a box sets itself is set as a `Text` of the same style would be
/// ([textLineTypeIn]) — over the ambient style, at the text scale, in bold
/// where bold text is asked for. ↩️Pinned through the frame counter's line
/// (`TickText`) until F-463 took the counter off.
void main() {
  const style = TextStyle(fontSize: 10);

  /// A `Text` of [style] at [scale] — with bold text asked for when [bold]
  /// is — and the type a line beside it is set in.
  Future<TextLineType> pumpBesideAText(
    WidgetTester tester, {
    double scale = 1,
    bool bold = false,
  }) async {
    late TextLineType type;
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(
          textScaler: TextScaler.linear(scale),
          boldText: bold,
        ),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: DefaultTextStyle(
            style: const TextStyle(fontSize: 14, height: 1.3),
            child: Align(
              alignment: Alignment.topLeft,
              child: Builder(
                builder: (context) {
                  type = textLineTypeIn(context, style);
                  return const Text('120', style: style);
                },
              ),
            ),
          ),
        ),
      ),
    );
    return type;
  }

  testWidgets('it is set as a Text is: over the ambient style, at the text '
      'scale, in bold where bold text is asked for', (tester) async {
    for (final (scale, bold) in [(1.0, false), (1.5, false), (1.0, true)]) {
      final type = await pumpBesideAText(tester, scale: scale, bold: bold);
      final line = textLineIn('120', type)..layout();
      addTearDown(line.dispose);

      expect(line.size, tester.getSize(find.byType(Text)), reason: '$scale');
      // The test font sets bold as wide as plain: the type says it.
      expect(
        type.style,
        tester.renderObject<RenderParagraph>(find.byType(RichText)).text.style,
        reason: 'bold: $bold',
      );
    }
  });
}
