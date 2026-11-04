import 'dart:async';

import 'package:flutter/widgets.dart' show ValueKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/dialogs/app_progress_dialog.dart';

import 'settle_async.dart';

/// Lends both clocks to work standing behind the app's wait window
/// (`runWithAppProgress`) until the window is gone
/// ([settleBehindTheWaitWindow]): the fake one for its frames, the real one
/// for work that hops to a file or an isolate.
///
/// ⛔A turning spinner never settles, so `pumpAndSettle` cannot be the wait.
///
/// 🚨A TEST THAT WAITS HERE ENDS BY STOPPING PLAYBACK'S WARMER
/// (`session.playbackRig.prerenderScheduler.cancel()`). The real clock this
/// lends is what the warmer starts on — after 400ms of real quiet — and a
/// walk caught between two pictures holds a timer past the body, which
/// fails the test before its tear-downs run: 「A Timer is still pending」,
/// the busier the machine the likelier (2026-10-08 — 3 runs in 16 on one
/// master). `a_run_the_window_waits_out_stops_the_warmer_test` holds every
/// caller to it.
/// Every share of the bar a wait window tells — read off the window's own
/// listenable, not off its frames, so no report falls between two of them.
///
/// Called before the frame that puts the window up, it listens from inside
/// that frame: the window starts its work right after it (`endOfFrame`),
/// and a stretch that takes no real time — a pool registering small files
/// — has told all of itself before a test body after `pump()` can listen.
List<double> watchTheBar(WidgetTester tester) {
  final told = <double>[];
  _listenFromItsFirstFrame(tester, (window) {
    final progress = window.progress;
    void record() {
      if (progress.value case final fraction?) {
        told.add(fraction);
      }
    }

    record();
    progress.addListener(record);
  });
  return told;
}

/// Every line a wait window's running status says (F-494: the stretch
/// under way), listened to as [watchTheBar] listens — the one it opens on
/// first.
List<String> watchTheLine(WidgetTester tester) {
  final said = <String>[];
  _listenFromItsFirstFrame(tester, (window) {
    final line = window.runningStatus!;
    void record() => said.add(line.value);

    record();
    line.addListener(record);
  });
  return said;
}

/// [listen] handed the wait window from inside the frame that puts it up,
/// or at once when it is up already.
void _listenFromItsFirstFrame(
  WidgetTester tester,
  void Function(AppProgressDialog window) listen,
) {
  final window = find.byType(AppProgressDialog);
  void atTheFrame(Duration _) => window.evaluate().isEmpty
      ? tester.binding.addPostFrameCallback(atTheFrame)
      : listen(tester.widget<AppProgressDialog>(window));
  if (window.evaluate().isEmpty) {
    tester.binding.addPostFrameCallback(atTheFrame);
  } else {
    listen(tester.widget<AppProgressDialog>(window));
  }
}

/// [told] as one bar for a whole run: it never runs back, and it passes
/// every share in [stops] on its way, in order.
void expectOneBar(List<double> told, List<double> stops) {
  for (var at = 1; at < told.length; at += 1) {
    expect(told[at], greaterThanOrEqualTo(told[at - 1]), reason: '$told');
  }
  expect(
    told,
    containsAllInOrder([for (final stop in stops) closeTo(stop, 1e-9)]),
    reason: '$told',
  );
}

/// The wait window [press] stood behind — read while it was up, and gone
/// now — or null when the press stood behind none.
///
/// For a step that runs on the frame clock alone (F-551's doors: a step
/// taken whole on the UI thread once the window is drawn); work that hops
/// to a file or an isolate waits with [settleBehindTheWaitWindow].
Future<AppProgressDialog?> windowBehind(
  WidgetTester tester,
  Future<void> Function() press,
) async {
  final stood = await stepBehind(tester, press);
  if (stood != null) {
    await tester.pump();
    expect(
      find.byType(AppProgressDialog),
      findsNothing,
      reason: 'the window went once its step did',
    );
  }
  return stood;
}

/// The wait window a press's own frame put up, waited out and let go
/// ([windowBehind]) — nothing at all when none is up, so a helper that
/// presses a key can call it after every press.
Future<void> waitOutTheWaitWindow(WidgetTester tester) async {
  if (find.byType(AppProgressDialog).evaluate().isNotEmpty) {
    await windowBehind(tester, () async {});
  }
}

/// [windowBehind]'s first half: [press], and frames until the step behind
/// the window it put up is over and drawn, for a test that reads the frames
/// the step landed in. The window goes with its step
/// (bundle-red-paste-behind-the-wait-window-Q1), so it is read on a frame
/// it was up in.
Future<AppProgressDialog?> stepBehind(
  WidgetTester tester,
  Future<void> Function() press,
) async {
  final seen = _WindowSeen(tester);
  await press();
  final window = find.byType(AppProgressDialog);
  bool over() => seen.window != null && window.evaluate().isEmpty;
  // Frames counted, not settled: the spinner turns until the step is over,
  // and a canvas may keep an animation of its own going under it. A list
  // closing before its row runs takes a few of them.
  for (var frame = 0; frame < 30 && !over(); frame += 1) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  seen.stop();
  final stood = seen.window;
  if (stood == null) {
    return null;
  }
  expect(over(), isTrue, reason: 'the step behind the window was over');
  return stood;
}

/// The first wait window up from now on — read at once when one is up
/// already, and after each frame until [stop]: a window that goes with its
/// step may be up and gone between two of a test's own looks.
final class _WindowSeen {
  _WindowSeen(this._tester) {
    _look(Duration.zero);
  }

  final WidgetTester _tester;
  AppProgressDialog? window;
  bool _stopped = false;

  void stop() => _stopped = true;

  void _look(Duration _) {
    if (_stopped || window != null) {
      return;
    }
    final up = find.byType(AppProgressDialog).evaluate();
    if (up.isNotEmpty) {
      window = up.first.widget as AppProgressDialog;
      return;
    }
    _tester.binding.addPostFrameCallback(_look);
  }
}

/// The wait window a tap on [key] stood behind ([windowBehind]).
Future<AppProgressDialog?> windowBehindTheTap(
  WidgetTester tester,
  ValueKey<String> key,
) {
  final found = find.byKey(key);
  return windowBehind(tester, () async {
    await tester.ensureVisible(found);
    await tester.pumpAndSettle();
    await tester.tap(found);
  });
}

Future<void> pumpPastTheWaitWindow(WidgetTester tester) async {
  final window = find.byType(AppProgressDialog);
  await tester.pump();
  await settleBehindTheWaitWindow(
    tester,
    () => window.evaluate().isEmpty,
    reason: 'the wait window went',
  );
}

/// [settleAsync] for work that may stand behind the app's wait window —
/// an import, an open, a save — until [ready]: a round lends a turn of the
/// real loop ([_hop]) and a frame 50ms on.
///
/// ↩️It answered whether [ready] came until 2026-10-31, and a wait that ran
/// out went on quietly: a merge test whose button was cut off waited its
/// minute and passed, on the weak line after it (I-78 ③ mutants, board
/// `wait-window-settle-returns-quietly`). One caller in 28 read the answer,
/// and only to assert it, so the wait asserts it now.
Future<void> settleBehindTheWaitWindow(
  WidgetTester tester,
  FutureOr<bool> Function() ready, {
  String reason = 'what stood behind the wait window came',
}) async {
  expect(
    await settleAsync(
      tester,
      ready,
      beat: _hop,
      step: const Duration(milliseconds: 50),
    ),
    isTrue,
    reason: reason,
  );
}

/// The real time a round of [settleBehindTheWaitWindow] lends: a turn of the
/// real event loop, no more. What the window waits on is a chain of real
/// hops — a file read, a decode, a write — each finishing in a turn and
/// going on in the next pump, so the chain sets how many rounds it takes,
/// not how long each lends.
///
/// 🔬2026-10-20, a numbered run's four placements: 49~59 rounds at a beat
/// of 20, 4 or 1 ms and a step of 10 or 50 ms alike — and 7.3 s of placing
/// at 20ms against 3.4 s at 1ms; an open from the recents, 8 rounds at 20ms
/// and 1ms alike. ⛔Not the shared beat: a window that waits for something
/// NOT to happen (`lendBothClocks`) is as long as its beats.
const _hop = Duration(milliseconds: 1);
