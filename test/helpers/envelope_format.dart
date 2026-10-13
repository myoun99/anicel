import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Picks the cut envelope's form the way a hand does: the panel's format
/// button, the window's list of forms, the form's row, and save.
Future<void> pickEnvelopeForm(WidgetTester tester, String formId) async {
  for (final key in [
    'envelope-format-button',
    'envelope-format-form',
    'envelope-format-form-$formId',
    'envelope-format-save-button',
  ]) {
    final target = find.byKey(ValueKey<String>(key));
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }
}
