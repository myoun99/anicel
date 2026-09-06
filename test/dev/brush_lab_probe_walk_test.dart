// The brush lab reaches into the live element tree to find the canvas it
// is about to stroke. Three of its probes walked that tree by hand; the
// walk is now `firstElementUnder`, and this pins what the three relied on.
import 'package:anicel/dev/brush_lab_main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('DEPTH first: a deeper match under the earlier sibling beats '
      'a shallower one under the later sibling', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Column(
          children: [
            Column(children: [SizedBox(key: ValueKey('deep-but-earlier'))]),
            SizedBox(key: ValueKey('shallow-but-later')),
          ],
        ),
      ),
    );

    final found = firstElementUnder(
      tester.element(find.byType(MaterialApp)),
      (widget) => widget is SizedBox,
    );

    expect((found!.widget.key! as ValueKey<String>).value, 'deep-but-earlier');
  });

  testWidgets('a later sibling is reached when the earlier one has no match', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Column(
          children: [
            Text('no match here'),
            Column(children: [SizedBox(key: ValueKey('deep'))]),
          ],
        ),
      ),
    );

    final found = firstElementUnder(
      tester.element(find.byType(MaterialApp)),
      (widget) => widget is SizedBox,
    );

    expect((found!.widget.key! as ValueKey<String>).value, 'deep');
  });

  testWidgets('a scope never answers with itself', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Column(children: [Text('nothing nested')])),
    );

    // The Column IS the root handed in, and the probes rely on that not
    // counting: "the view under the canvas host" must not resolve to the
    // host.
    expect(
      firstElementUnder(
        tester.element(find.byType(Column)),
        (widget) => widget is Column,
      ),
      isNull,
    );
  });

  testWidgets('no match answers null, not a throw', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Text('bare')));

    expect(
      firstElementUnder(
        tester.element(find.byType(MaterialApp)),
        (widget) => widget is Slider,
      ),
      isNull,
    );
  });

  testWidgets('the walk stops at the first match — no sibling is visited '
      'after it', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Column(
          children: [
            SizedBox(key: ValueKey('first')),
            SizedBox(key: ValueKey('second')),
            SizedBox(key: ValueKey('third')),
          ],
        ),
      ),
    );

    var tested = 0;
    final found = firstElementUnder(
      tester.element(find.byType(Column)),
      (widget) {
        tested += 1;
        return widget is SizedBox;
      },
    );

    expect((found!.widget.key! as ValueKey<String>).value, 'first');
    expect(tested, 1, reason: 'early exit, not a full sweep');
  });
}
