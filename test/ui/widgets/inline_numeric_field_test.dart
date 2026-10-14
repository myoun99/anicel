// THE ONE INLINE NUMERIC FIELD: ENTER SUBMITS THE TRIMMED TEXT, ESCAPE
// CANCELS WITHOUT SUBMITTING.
//
// No test named this widget (audit 2026-09-03) although every typed
// readout in the app goes through it. These pins drive it as a user does.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/widgets/inline_numeric_field.dart';

import '../../helpers/ime_draft.dart';

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

  // 🐛F-355 (유저 2026-10-13): 「５０이라고 입력할때 숫자가 두번 등록되는거같은?
  // 5500 이런식으로 … ５０인상태에도 엔터하면 50으로 등록되는? 그런거 원함」.
  group('a 全角 IME', () {
    String shown(WidgetTester tester) =>
        tester.widget<TextField>(find.byType(TextField)).controller!.text;

    testWidgets('🚨nothing goes back to it while it composes — on Windows '
        'that doubled what was typed next', (tester) async {
      await pump(tester);
      await tester.showKeyboard(find.byType(TextField));
      tester.testTextInput.log.clear();

      await composeDraft(tester, find.byType(TextField), '５０');

      expect(shown(tester), '５０', reason: '⛔fixture: the draft arrived');
      expect(
        tester.testTextInput.log.where(
          (call) => call.method == 'TextInput.setEditingState',
        ),
        isEmpty,
      );
    });

    testWidgets('what it commits shows half-width, and Enter submits it', (
      tester,
    ) async {
      final seen = await pump(tester);
      await composeDraft(tester, find.byType(TextField), '５０');

      await commitDraft(tester, '５０');
      expect(shown(tester), '50');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(seen.submitted, ['50']);
    });

    testWidgets('a tap away from a draft submits its numerals half-width', (
      tester,
    ) async {
      final seen = await pump(tester);
      await composeDraft(tester, find.byType(TextField), '５０');

      await tester.tapAt(const Offset(4, 4));
      await tester.pump();

      expect(seen.submitted, ['50']);
    });
  });
}
