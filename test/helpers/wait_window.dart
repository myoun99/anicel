import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/dialogs/app_progress_dialog.dart';

/// Lends both clocks to work standing behind the app's wait window
/// (`runWithAppProgress`) until the window is gone: the fake one for its
/// frames and its `appProgressDoneLinger`, the real one for work that hops
/// to a file or an isolate.
///
/// ⛔A turning spinner never settles, so `pumpAndSettle` cannot be the wait,
/// and a bare `pump()` never reaches the linger's end.
///
/// 🚨A TEST THAT WAITS HERE ENDS BY STOPPING PLAYBACK'S WARMER
/// (`session.playbackRig.prerenderScheduler.cancel()`). The real clock this
/// lends is what the warmer starts on — after 400ms of real quiet — and a
/// walk caught between two pictures holds a timer past the body, which
/// fails the test before its tear-downs run: 「A Timer is still pending」,
/// the busier the machine the likelier (2026-10-08 — 3 runs in 16 on one
/// master). `a_run_the_window_waits_out_stops_the_warmer_test` holds every
/// caller to it.
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
