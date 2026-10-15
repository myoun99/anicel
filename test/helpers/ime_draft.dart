import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Leaves [text] in [field] as a Japanese IME in 全角 holds what is typed: a
/// DRAFT it is still composing, not yet committed (F-355).
Future<void> composeDraft(
  WidgetTester tester,
  Finder field,
  String text,
) async {
  await tester.showKeyboard(field);
  tester.testTextInput.updateEditingValue(
    TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
      composing: TextRange(start: 0, end: text.length),
    ),
  );
  await tester.pump();
}

/// The IME commits [text], the draft [composeDraft] left — Enter, or its
/// own confirm.
Future<void> commitDraft(WidgetTester tester, String text) async {
  tester.testTextInput.updateEditingValue(
    TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    ),
  );
  await tester.pump();
}
