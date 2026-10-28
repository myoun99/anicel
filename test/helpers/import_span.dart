import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'number_pad_keyboard.dart';
import 'settle_async.dart';

/// Stands the import window preview's IN on [from] and its OUT on [to] —
/// one-based, as the transport shows them, each typed as a hand does — for
/// the row it previews.
///
/// ↩️Three files each typed it on their own until 2026-10-29.
Future<void> keepImportSpan(WidgetTester tester, int from, int to) async {
  await settleLoadedPages(tester);
  for (final (end, at) in [('in', from), ('out', to)]) {
    await tester.tap(find.byKey(ValueKey<String>('transport-$end-edit')));
    await tester.pump();
    await openThePadsKeyboard(tester);
    await tester.enterText(
      find.byKey(ValueKey<String>('transport-$end-input')),
      '$at',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settleLoadedPages(tester);
  }
}
