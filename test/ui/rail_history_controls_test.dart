import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/brush/tools_panel.dart';
import 'package:anicel/src/ui/home_page.dart';

/// Undo, redo and the onion toggle moved from the top strip to the head of
/// the tool rail — the verbs a hand reaches for BETWEEN strokes belong
/// where the hand already is. The top strip is on its way out entirely, so
/// nothing may be left holding these there.
void main() {
  Future<void> pumpHome(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();
  }

  Finder railButton(String key) => find.byWidgetPredicate(
    (widget) => widget is RailButton && widget.keyValue == key,
  );

  testWidgets('undo, redo and onion sit on the rail — and only there', (
    tester,
  ) async {
    await pumpHome(tester);

    for (final key in [
      'undo-button',
      'redo-button',
      'rail-onion-skin-button',
    ]) {
      expect(railButton(key), findsOneWidget, reason: key);
    }

    // The keys are old ones a good number of tests hold; if the strip ever
    // grew them back, every one of those tests would start matching two
    // widgets instead of one.
    expect(find.byKey(const ValueKey<String>('undo-button')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('redo-button')), findsOneWidget);
  });

  testWidgets('undo is dead until there is something to undo', (tester) async {
    await pumpHome(tester);

    final undo = tester.widget<RailButton>(railButton('undo-button'));
    expect(undo.onPressed, isNull);
  });

  testWidgets(
    'the onion button reports the active layer, not a master switch',
    (tester) async {
      await pumpHome(tester);

      final before = tester.widget<RailButton>(
        railButton('rail-onion-skin-button'),
      );
      expect(before.selected, isFalse);

      await tester.tap(railButton('rail-onion-skin-button'));
      await tester.pumpAndSettle();

      final after = tester.widget<RailButton>(
        railButton('rail-onion-skin-button'),
      );
      expect(
        after.selected,
        isTrue,
        reason: 'onion is per layer — the button shows the ACTIVE row',
      );
    },
  );
}
