import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/dialogs/app_progress_dialog.dart';

/// Lends both clocks to work standing behind the app's wait window
/// (`runWithAppProgress`) until the window is gone: the fake one for its
/// frames and its `appProgressDoneLinger`, the real one for work that hops
/// to a file or an isolate.
///
/// ⛔A turning spinner never settles, so `pumpAndSettle` cannot be the wait,
/// and a bare `pump()` never reaches the linger's end.
Future<void> pumpPastTheWaitWindow(WidgetTester tester) async {
  final window = find.byType(AppProgressDialog);
  await tester.pump();
  for (
    var attempt = 0;
    attempt < 600 && window.evaluate().isNotEmpty;
    attempt += 1
  ) {
    await tester.pump(const Duration(milliseconds: 50));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  expect(window, findsNothing, reason: 'the wait window went');
}
