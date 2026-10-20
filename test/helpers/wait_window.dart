import 'package:flutter/widgets.dart' show ValueKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/dialogs/app_progress_dialog.dart';

import 'settle_async.dart';

/// Lends both clocks to work standing behind the app's wait window
/// (`runWithAppProgress`) until the window is gone ([settleAsync]): the
/// fake one for its frames and its `appProgressDoneLinger`, the real one
/// for work that hops to a file or an isolate. The linger itself goes in
/// one step ([passTheDoneLinger]).
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
  await settleAsync(
    tester,
    () => window.evaluate().isEmpty,
    beat: _hop,
    step: const Duration(milliseconds: 50),
    everyFrame: () => passTheDoneLinger(tester),
  );
  expect(window, findsNothing, reason: 'the wait window went');
}

/// The real time a round of [pumpPastTheWaitWindow] lends: a turn of the
/// real event loop, no more. What the window waits on is a chain of real
/// hops — a file read, a decode, a write — each finishing in a turn and
/// going on in the next pump, so the chain sets how many rounds it takes,
/// not how long each lends.
///
/// 🔬2026-10-20, a numbered run's four placements: 49~59 rounds at a beat
/// of 20, 4 or 1 ms and a step of 10 or 50 ms alike — and 7.3 s of placing
/// at 20ms against 3.4 s at 1ms. ⛔Not the shared beat: a window that waits
/// for something NOT to happen (`lendBothClocks`) is as long as its beats.
const _hop = Duration(milliseconds: 1);

/// Pumps a wait window's done line ([appProgressDoneLinger]) in ONE step,
/// once every [AppProgressDialog] standing SHOWS its work is over — its
/// check drawn: from there the window waits on the frame clock alone, and
/// a frame drawn on the way shows nothing the drawn one did not.
///
/// ⚠️Read off the screen, not off the window's `progress`: a value set
/// between two frames is not drawn yet, and a jump then skips the one frame
/// that says 「Saved」 (the iPad Save As test caught it).
///
/// 🔬↩️It was waited out a round at a time until 2026-10-20 — 50ms or 16ms
/// of clock a round, each a real beat and a frame of the whole tree — and
/// the linger alone was 0.97~1.12s of a test that imports one picture, all
/// but 0.1s of it (card heavy-tests-save).
Future<void> passTheDoneLinger(WidgetTester tester) async {
  final windows = find.byType(AppProgressDialog);
  final standing = windows.evaluate().length;
  final checked = find.descendant(
    of: windows,
    matching: find.byKey(const ValueKey<String>('app-progress-done')),
  );
  if (standing > 0 && checked.evaluate().length == standing) {
    await tester.pump(appProgressDoneLinger);
  }
}
