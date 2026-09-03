// THE ONE INLINE NUMERIC FIELD: ENTER SUBMITS THE TRIMMED TEXT, ESCAPE
// CANCELS WITHOUT SUBMITTING.
//
// No test named this widget (audit 2026-09-03) although every typed
// readout in the app goes through it. These pins drive it as a user does.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/widgets/inline_numeric_field.dart';

void main() {
  Future<({List<String> submitted, List<int> cancelled})> pump(
    WidgetTester tester,
  ) async {
    final submitted = <String>[];
    final cancelled = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 80,
              child: InlineNumericField(
                initialText: '12',
                onSubmit: submitted.add,
                onCancel: () => cancelled.add(1),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return (submitted: submitted, cancelled: cancelled);
  }

  testWidgets('Enter submits the trimmed text', (tester) async {
    final seen = await pump(tester);
    await tester.enterText(find.byType(TextField), ' 34 ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(seen.submitted, ['34']);
    expect(seen.cancelled, isEmpty);
  });

  testWidgets('Escape cancels and submits nothing', (tester) async {
    final seen = await pump(tester);
    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(seen.cancelled, hasLength(1));
    expect(seen.submitted, isEmpty);
  });
}
