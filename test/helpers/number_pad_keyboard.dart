import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The number at the top of the open number pad (`showNumberPad`).
final Finder theNumberPadsNumber = find.byWidgetPredicate(
  (widget) => switch (widget.key) {
    ValueKey<String>(:final value) => value.endsWith('-pad-number'),
    _ => false,
  },
);

/// Presses the number at the top of the number pad a pencil opened, which
/// brings the keyboard up on it, all of it selected — the way a hand types
/// a number with the keyboard (I-134). The field it types into keeps the
/// key its host gave it (`<keyValue>-input`).
Future<void> openThePadsKeyboard(WidgetTester tester) async {
  await tester.tap(theNumberPadsNumber);
  await tester.pump();
}
