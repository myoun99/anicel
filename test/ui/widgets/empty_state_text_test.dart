// A PANEL'S EMPTY LINE IS ONE WIDGET: one look, in the place the panel's
// content would take.
//
// 유저 2026-09-15: 「공용 위젯 하나 + 짧은 한 줄」 (empty-state-law-Q1) and
// 「내용이 올 자리에」 (empty-state-placement-Q1).
//
// ↩️`settings_prompt_text_test` pinned the top-left half of this when the
// widget was the settings panels' prompt line alone.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/widgets/empty_state_text.dart';

void main() {
  Future<void> pumpLine(WidgetTester tester, EmptyStatePlace place) =>
      tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(),
          home: Scaffold(
            body: SizedBox(
              width: 200,
              height: 100,
              child: EmptyStateText('Nothing here', place: place),
            ),
          ),
        ),
      );

  Align alignOf(WidgetTester tester) => tester.widget<Align>(
    find
        .ancestor(of: find.text('Nothing here'), matching: find.byType(Align))
        .first,
  );

  testWidgets('a LIST says it where its first row would be', (tester) async {
    await pumpLine(tester, EmptyStatePlace.list);
    expect(alignOf(tester).alignment, Alignment.topLeft);
    expect(
      tester.widget<Text>(find.text('Nothing here')).textAlign,
      TextAlign.start,
    );
  });

  testWidgets('a STAGE says it in the middle', (tester) async {
    await pumpLine(tester, EmptyStatePlace.stage);
    expect(alignOf(tester).alignment, Alignment.center);
    expect(
      tester.widget<Text>(find.text('Nothing here')).textAlign,
      TextAlign.center,
    );
  });

  for (final place in EmptyStatePlace.values) {
    testWidgets('${place.name}: the same small muted type — the size and the '
        'colour are never the panel\'s', (tester) async {
      await pumpLine(tester, place);
      final text = tester.widget<Text>(find.text('Nothing here'));
      final resolved = Theme.of(tester.element(find.text('Nothing here')));
      expect(text.style?.fontSize, resolved.textTheme.bodySmall?.fontSize);
      expect(text.style?.color, resolved.colorScheme.onSurfaceVariant);
    });
  }
}
