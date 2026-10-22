import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The import window's 「N warnings」 — the status line's button, while it
/// shows (F-370-Q1).
final importWarningsButton = find
    .byKey(const ValueKey<String>('import-warnings-button'))
    .hitTestable();

/// Opens the notice the import window's warnings are read in, and answers
/// where it stands.
Future<Finder> openImportWarnings(WidgetTester tester) async {
  await tester.tap(importWarningsButton);
  await tester.pumpAndSettle();
  return find.byKey(const ValueKey<String>('import-warnings-notice'));
}
