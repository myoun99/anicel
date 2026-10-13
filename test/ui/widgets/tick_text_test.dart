import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/widgets/tick_text.dart';

import '../../helpers/frame_census.dart';

/// I-57 (10-14): a line a tick changes hears the tick itself, and paints
/// itself alone while it keeps its size — set as a `Text` would set it.
void main() {
  final words = ValueNotifier<String>('1');
  tearDown(() => words.value = '1');

  const style = TextStyle(fontSize: 10);

  /// The line in a row beside a word that never changes, on one layer.
  Widget row() => Directionality(
    textDirection: TextDirection.ltr,
    child: Align(
      alignment: Alignment.topLeft,
      child: RepaintBoundary(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TickText(ticks: words, words: () => words.value, style: style),
            const Text('beside'),
          ],
        ),
      ),
    ),
  );

  RenderTickText line(WidgetTester tester) =>
      tester.renderObject<RenderTickText>(find.byType(TickText));

  /// What a tick to [data] asks for before its frame — the line's paint
  /// and layout, the row's layout and the row's layer's paint — and what
  /// that frame builds and paints.
  Future<
    ({
      bool linePainted,
      bool lineLaidOut,
      bool rowLaidOut,
      bool layerPainted,
      List<Type> rebuilt,
      List<RenderObject> painted,
    })
  >
  tick(WidgetTester tester, String data) async {
    final rowBox = tester.renderObject(find.byType(Row));
    final layer = tester.renderObject(
      find.ancestor(
        of: find.byType(Row),
        matching: find.byType(RepaintBoundary),
      ),
    );
    late bool linePainted;
    late bool lineLaidOut;
    late bool rowLaidOut;
    late bool layerPainted;
    final frame = await frameCensus(tester, () {
      words.value = data;
      linePainted = line(tester).debugNeedsPaint;
      lineLaidOut = line(tester).debugNeedsLayout;
      rowLaidOut = rowBox.debugNeedsLayout;
      layerPainted = layer.debugNeedsPaint;
    });
    expect(line(tester).data, data, reason: 'premise: the line heard it');
    return (
      linePainted: linePainted,
      lineLaidOut: lineLaidOut,
      rowLaidOut: rowLaidOut,
      layerPainted: layerPainted,
      rebuilt: frame.rebuilt,
      painted: frame.painted,
    );
  }

  testWidgets('a tick that keeps the line\'s size paints the line alone, '
      'and builds and lays out nothing', (tester) async {
    await tester.pumpWidget(row());

    final asked = await tick(tester, '2');

    expect(asked.linePainted, isTrue);
    expect(asked.lineLaidOut, isFalse);
    expect(asked.rowLaidOut, isFalse);
    expect(asked.layerPainted, isFalse);
    expect(asked.rebuilt, isEmpty);
    expect(
      asked.painted,
      isEmpty,
      reason: 'the line repaints as a layer of its own — nothing round it '
          'paints it',
    );
  });

  testWidgets('CONTROL: a tick that changes its size lays the row out and '
      'paints it', (tester) async {
    await tester.pumpWidget(row());
    final beside = tester.renderObject(find.text('beside'));
    final width = tester.getSize(find.byType(TickText)).width;

    final asked = await tick(tester, '10');

    expect(asked.rowLaidOut, isTrue);
    expect(asked.painted, contains(same(beside)));
    expect(tester.getSize(find.byType(TickText)).width, greaterThan(width));
  });

  testWidgets('a build reads the words anew', (tester) async {
    var prefix = 'a';
    Widget host() => Directionality(
      textDirection: TextDirection.ltr,
      child: TickText(
        ticks: words,
        words: () => '$prefix${words.value}',
        style: style,
      ),
    );
    await tester.pumpWidget(host());
    expect(line(tester).data, 'a1');

    prefix = 'b';
    await tester.pumpWidget(host());

    expect(line(tester).data, 'b1');
  });

  testWidgets('a line taken away stops hearing the ticks', (tester) async {
    final key = GlobalKey();
    Widget host({required bool shown}) => Directionality(
      textDirection: TextDirection.ltr,
      child: Column(
        children: [
          if (shown)
            TickText(
              key: key,
              ticks: words,
              words: () => words.value,
              style: style,
            ),
        ],
      ),
    );
    await tester.pumpWidget(host(shown: true));
    final first = line(tester);

    await tester.pumpWidget(host(shown: false));
    words.value = '5';
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(host(shown: true));
    expect(line(tester).data, '5');
    expect(first.data, '1', reason: 'the line taken away heard the tick');
  });

  /// [data] as a [TickText] and as a `Text` of the same [style], one over
  /// the other, at [scale] — with bold text asked for when [bold] is.
  Widget pair(String data, {double scale = 1, bool bold = false}) =>
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TickText(words: () => data, style: style),
                  Text(data, style: style),
                ],
              ),
            ),
          ),
        ),
      );

  void expectSetAsAText(WidgetTester tester) => expect(
    tester.getSize(find.byType(TickText)),
    tester.getSize(find.byType(Text)),
  );

  testWidgets('it is set as a Text is: over the ambient style, at the text '
      'scale, in bold where bold text is asked for', (tester) async {
    for (final (scale, bold) in [(1.0, false), (1.5, false), (1.0, true)]) {
      await tester.pumpWidget(pair('120', scale: scale, bold: bold));
      expectSetAsAText(tester);
    }
  });

  testWidgets('and set again when the scale changes under it', (
    tester,
  ) async {
    await tester.pumpWidget(pair('120'));
    final atOne = tester.getSize(find.byType(TickText));

    await tester.pumpWidget(pair('120', scale: 2));

    expect(tester.getSize(find.byType(TickText)), isNot(atOne));
    expectSetAsAText(tester);
  });

  testWidgets('it reads as its words, described on its own', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(row());

    words.value = '7';
    await tester.pump();

    expect(tester.getSemantics(find.byType(TickText)).label, '7');
    semantics.dispose();
  });
}
