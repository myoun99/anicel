import 'package:flutter_test/flutter_test.dart';

/// Interleaves REAL time with pumped time until [ready], and answers whether
/// it came.
///
/// 🚨★★★**A PUMPED CLOCK DOES NOT DECODE AN IMAGE, NOR FINISH REAL IO.** A
/// page render ends in an engine decode on a real thread, and a file read
/// completes inside `runAsync` — `pump()` advances the fake clock and drains
/// microtasks, and neither of those is either. So a buffer refilled only by
/// pumping never refills, no matter how many ticks.
///
/// 🪦That cost a round once: pumping 300 times and seeing nothing land, a
/// test, a commit and a board card called 「the viewer never comes back from
/// a dry buffer」 a PRODUCT BUG. It was the bench. And then there were four
/// of these, one per file that met it, each spelled a little differently.
///
/// [step] is the pumped time per round — a run's tick, where the run has
/// to move on between them. [everyFrame] watches each frame drawn on the
/// way.
///
/// ⚠️[attempts] is generous where a test waits for something to LAND. Real
/// time means real load: at 60×10ms one file passed alone and failed inside
/// a 317-test run, which is a flake, and a flaky nail is not a nail. Where a
/// test waits for something NOT to happen, a shorter window is honest and
/// keeps the suite quick.
Future<bool> settleAsync(
  WidgetTester tester,
  bool Function() ready, {
  int attempts = 60,
  Duration step = Duration.zero,
  void Function()? everyFrame,
}) async {
  for (var i = 0; i < attempts && !ready(); i += 1) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(step);
    everyFrame?.call();
  }
  return ready();
}
