import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
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

  /// The width of each pill of [labels], in a strip given [width] of room.
  Future<Map<String, double>> widthsIn(
    WidgetTester tester,
    double width,
    List<String> labels, {
    String? tooltipOn,
  }) async {
    await pump(
      tester,
      width,
      Align(
        alignment: Alignment.centerLeft,
        child: PillStrip(
          items: [
            for (final label in labels)
              PillItem(
                keyValue: label,
                label: label,
                selected: false,
                tooltip: label == tooltipOn ? 'said on hover' : null,
                onTap: () {},
              ),
          ],
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    return {
      for (final label in labels)
        label: tester.getSize(find.byKey(ValueKey<String>(label))).width,
    };
  }

  testWidgets('🚨across, a strip that FITS gives every pill its own width — '
      'a long word beside short ones is not cut to an equal share of the '
      'room', (tester) async {
    const labels = ['a', 'b', 'a long word'];
    final own = await widthsIn(tester, 2000, labels, tooltipOn: 'b');
    final strip = tester.getSize(find.byType(PillStrip)).width;
    expect(
      own['a long word'],
      greaterThan(strip / 3),
      reason: 'the fixture: the long pill is wider than a third of the strip',
    );

    // Exactly the room the strip asks for, and a little more.
    for (final room in [strip, strip + 20]) {
      expect(
        await widthsIn(tester, room, labels, tooltipOn: 'b'),
        own,
        reason: 'in $room',
      );
    }
    for (final label in labels) {
      final word = tester.renderObject<RenderParagraph>(find.text(label));
      expect(
        word.size.width,
        greaterThanOrEqualTo(word.getMaxIntrinsicWidth(double.infinity) - 0.01),
        reason: '「$label」 is cut short',
      );
    }
    // Side by side, each where the one before it ends — and drawn.
    Rect at(String label) =>
        tester.getRect(find.byKey(ValueKey<String>(label)));
    expect(at('b').left, at('a').right);
    expect(at('a long word').left, at('b').right);
    expect(
      find.byType(PillStrip),
      paints
        ..paragraph()
        ..paragraph()
        ..paragraph(),
    );
  });

  testWidgets('across, a strip that does NOT fit: the short words keep '
      'their width and the long ones share what is left, evenly — and the '
      'strip is as wide as its room', (tester) async {
    const labels = ['a', 'storyboard', 'direction'];
    final own = await widthsIn(tester, 2000, labels);
    final strip = tester.getSize(find.byType(PillStrip)).width;
    final room = strip - 60;

    final given = await widthsIn(tester, room, labels);
    expect(given['a'], own['a'], reason: 'the short word is whole');
    expect(given['storyboard'], lessThan(own['storyboard']!));
    expect(given['direction'], lessThan(own['direction']!));
    expect(
      given['storyboard'],
      closeTo(given['direction']!, 0.01),
      reason: 'one cap, shared',
    );
    expect(
      tester.getSize(find.byType(PillStrip)).width,
      closeTo(room, 0.01),
      reason: 'it gives up no more than it has to',
    );
    double sum(Map<String, double> widths) =>
        widths.values.fold(0.0, (all, width) => all + width);
    expect(
      sum(given),
      closeTo(room - (strip - sum(own)), 0.01),
      reason: 'the pills fill the strip — and do not run past its outline',
    );
  });

  testWidgets('across, a pill a HAIR over its share is kept whole — a word '
      'does not lose a glyph to save the others half a pixel', (tester) async {
    const labels = ['ab', 'cd', 'a long long word'];
    final own = await widthsIn(tester, 2000, labels);
    final strip = tester.getSize(find.byType(PillStrip)).width;
    final outline =
        strip - own.values.fold(0.0, (sum, width) => sum + width);
    // Once 「ab」 has its width, 「cd」 and the long word have half a pixel
    // less than two of 「cd」 between them.
    final room = own['ab']! + 2 * own['cd']! - 1 + outline;

    final given = await widthsIn(tester, room, labels);
    expect(given['ab'], own['ab']);
    expect(given['cd'], own['cd'], reason: 'half a pixel over: kept whole');
    expect(given['a long long word'], closeTo(own['cd']! - 1, 0.01));
  });

  testWidgets('across, a press on a pill is THAT pill\'s', (tester) async {
    final pressed = <String>[];
    await pump(
      tester,
      300,
      Align(
        alignment: Alignment.centerLeft,
        child: PillStrip(
          items: [
            for (final label in ['One', 'Two', 'Three'])
              PillItem(
                keyValue: label,
                label: label,
                selected: false,
                onTap: () => pressed.add(label),
              ),
          ],
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey<String>('Two')));
    await tester.tap(find.byKey(const ValueKey<String>('Three')));
    expect(pressed, ['Two', 'Three']);
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

  testWidgets('a chosen pill is tinted the accent — or its own tone where it '
      'has one, word and wash alike; a pill that is not chosen wears '
      'neither', (tester) async {
    const tone = Color(0xFFC95C5C);
    await pump(
      tester,
      400,
      Align(
        alignment: Alignment.centerLeft,
        child: PillStrip(
          items: [
            const PillItem(keyValue: 'plain', label: 'a', selected: true),
            const PillItem(
              keyValue: 'toned',
              label: 'b',
              selected: true,
              tone: tone,
            ),
            PillItem(
              keyValue: 'off',
              label: 'c',
              selected: false,
              tone: tone,
              onTap: () {},
            ),
          ],
        ),
      ),
    );
    final theme = Theme.of(tester.element(find.byType(PillStrip)));
    Color? wordOf(String key) => tester
        .widget<Text>(
          find.descendant(
            of: find.byKey(ValueKey<String>(key)),
            matching: find.byType(Text),
          ),
        )
        .style!
        .color;
    Color? washOf(String key) =>
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
            .color;

    final accent = theme.colorScheme.primary;
    expect(tone, isNot(accent));
    expect(
      (wordOf('plain'), washOf('plain')),
      (accent, accent.withValues(alpha: 0.14)),
    );
    expect(
      (wordOf('toned'), washOf('toned')),
      (tone, tone.withValues(alpha: 0.14)),
    );
    expect(
      (wordOf('off'), washOf('off')),
      (theme.colorScheme.onSurface, null),
    );
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
