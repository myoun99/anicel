import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/widgets/pill_strip.dart';

/// The app's one grouped choice (board `pill-group-everywhere`), laid
/// across — the export window's first shape — or down, for answers too long
/// to sit side by side in a panel's width (the tool settings' read source).
void main() {
  List<PillItem> items(List<String> labels) => [
    for (final label in labels)
      PillItem(keyValue: label, label: label, selected: false, onTap: () {}),
  ];

  Future<void> pump(WidgetTester tester, double width, Widget strip) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(width: width, child: strip),
            ),
          ),
        ),
      );

  Border lineOf(WidgetTester tester, String key) =>
      (tester
                  .widget<Container>(
                    find
                        .descendant(
                          of: find.byKey(ValueKey<String>(key)),
                          matching: find.byType(Container),
                        )
                        .first,
                  )
                  .decoration!
              as BoxDecoration)
          .border!
          as Border;

  testWidgets('across, a strip narrower than its pills gives width up — '
      'its words ellipsise, it never overflows its column', (tester) async {
    await pump(
      tester,
      120,
      Align(
        alignment: Alignment.centerLeft,
        child: PillStrip(
          items: items(['Transparent', 'Background', 'Everything', 'Nothing']),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(PillStrip)).width, lessThanOrEqualTo(120));
  });

  testWidgets('across, the line between two pills runs down the left of the '
      'second', (tester) async {
    await pump(
      tester,
      400,
      Align(
        alignment: Alignment.centerLeft,
        child: PillStrip(items: items(['a', 'b'])),
      ),
    );

    final line = lineOf(tester, 'b');
    expect((line.left.style, line.top.style), (
      BorderStyle.solid,
      BorderStyle.none,
    ));
  });

  testWidgets('down, each pill spans the strip, and the line between two '
      'pills runs across the top of the second', (tester) async {
    await pump(
      tester,
      200,
      PillStrip(axis: Axis.vertical, items: items(['a', 'b', 'c'])),
    );

    final strip = tester.getSize(find.byType(PillStrip)).width;
    for (final key in ['a', 'b', 'c']) {
      final pill = find.byKey(ValueKey<String>(key));
      expect(
        tester.getSize(pill).width,
        closeTo(strip, 2.01),
        reason: 'the outline takes a pixel each side',
      );
      // The word's own box, not a line as wide as the pill: a word laid
      // across the whole pill reads centred here while its glyphs sit at
      // the left edge (a mutant that dropped the alignment did exactly
      // that, and survived the first version of this check).
      final word = find.text(key);
      expect(tester.getSize(word).width, lessThan(strip / 2));
      expect(
        tester.getCenter(word).dx,
        closeTo(tester.getCenter(pill).dx, 0.5),
        reason: 'its word in the middle, as in a pill as wide as its word',
      );
    }
    final line = lineOf(tester, 'b');
    expect((line.top.style, line.left.style), (
      BorderStyle.solid,
      BorderStyle.none,
    ));
  });
}
