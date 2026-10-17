import 'dart:async';

// Apart from `settle_async.dart`, which lends a widget test's two clocks:
// what waits here turns no pumped clock, and the run's own clean-up waits
// with it too — `temp_dir.dart`, which the test config loads before every
// suite and which imports nothing but `dart:io` and this.

/// How long a wait for something to COME waits at most: real time.
///
/// 🚨★★★**A TIME, NOT A NUMBER OF ROUNDS** (board
/// `a-poll-that-counts-rounds-runs-out-under-load`). A round of real time
/// grows with the load — the decode, the file or the isolate it lends time
/// to shares the machine with every other run — so a count that sufficed
/// alone ran out in a batch beside other runs, and failed lanes that
/// touched nothing of it: the settings round trip (2026-09-24), the Drive
/// tab twice (10-06 · 10-07). A wait that passes returns the moment what it
/// waits for is there, so the ceiling costs nothing; it is only how long a
/// real failure takes to say so.
const waitPatience = Duration(seconds: 60);

/// Lets REAL time pass, [beat] at a time, until [ready], or until
/// [patience] has gone by, and answers whether it came — for whatever has
/// no pumped clock to turn: a plain `test`, the body of a `runAsync`, the
/// run's end.
Future<bool> pollUntil(
  FutureOr<bool> Function() ready, {
  Duration patience = waitPatience,
  Duration beat = const Duration(milliseconds: 10),
}) async {
  final deadline = DateTime.now().add(patience);
  while (!await ready()) {
    if (!DateTime.now().isBefore(deadline)) {
      return false;
    }
    await Future<void>.delayed(beat);
  }
  return true;
}

/// Waits for [future] at most [waitPatience], and fails with a
/// [TimeoutException] if it has not come by then: a future a test awaits
/// never hangs the run, and never lets the test go on as if it had come.
///
/// 🚨★**THE ONE CEILING FOR A FUTURE TOO** (board
/// `a-test-awaits-a-future-with-a-ceiling-of-its-own`, 2026-10-17). Tests
/// gave `.timeout(…)` a number of their own — thirty seconds, or ten — and
/// four went on when it ran out (`onTimeout: () {}`): on a busy machine a
/// walk still at work read as one at rest, and a test that says something
/// was NOT made would pass for it. As [pollUntil], for whatever has no
/// pumped clock to turn: a plain `test`, the body of a `runAsync`.
Future<T> patiently<T>(Future<T> future) => future.timeout(waitPatience);
