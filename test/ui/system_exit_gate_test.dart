import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/home_page.dart';

/// PEN-11: the Android back button never silently kills the editor — a
/// system pop lands in the exit dialog, and Cancel keeps the app alive.
/// R26 #43: the dialog only appears when the project was EDITED, and it
/// offers Save / Save As alongside Cancel and Close.
void main() {
  Future<void> makeDirty(WidgetTester tester) async {
    // Any command marks the session dirty (the history manager raises the
    // flag) — creating a drawing is the cheapest one from the toolbar.
    // The toolbar scrolls horizontally and grew a blend dropdown (R26
    // #30-1), so the button must scroll into view at the test width.
    final button = find.byKey(const ValueKey<String>('new-frame-button'));
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  testWidgets('an EDITED project: system back opens the gate with all four '
      'answers; Cancel stays', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pump();
    await makeDirty(tester);

    final popped = await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(popped, isTrue, reason: 'the pop is consumed by the gate');
    expect(
      find.byKey(const ValueKey<String>('system-exit-dialog')),
      findsOneWidget,
    );
    for (final key in const [
      'system-exit-cancel',
      'system-exit-save',
      'system-exit-save-as',
      'system-exit-close',
    ]) {
      expect(find.byKey(ValueKey<String>(key)), findsOneWidget, reason: key);
    }

    await tester.tap(find.byKey(const ValueKey<String>('system-exit-cancel')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('system-exit-dialog')),
      findsNothing,
    );
    expect(find.byType(HomePage), findsOneWidget);
  });

  testWidgets('R26 #43: an UNEDITED project never asks — there is nothing '
      'to lose', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pump();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('system-exit-dialog')),
      findsNothing,
    );
  });
}
