import 'dart:async';

import 'package:anicel/src/ui/media/viewer_page_loading.dart';
import 'package:flutter_test/flutter_test.dart';

import 'poll_until.dart';

/// Interleaves REAL time with pumped time until [ready], or until
/// [patience] has gone by, and answers whether it came.
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
/// to move on between them — and [beat] the real time before it. [everyFrame]
/// watches each frame drawn on the way, or answers what the frame put up (a
/// notice to close). [ready] may read the disk itself — inside `runAsync`,
/// as any real IO in a widget test.
///
/// ↩️It counted `attempts` until 2026-10-16 — 「generous where a test waits
/// for something to LAND … where a test waits for something NOT to happen,
/// a shorter window is honest」. That one number answered two questions;
/// the second is [lendBothClocks] now, and this one waits by [waitPatience].
Future<bool> settleAsync(
  WidgetTester tester,
  FutureOr<bool> Function() ready, {
  Duration patience = waitPatience,
  Duration beat = _beat,
  Duration step = Duration.zero,
  FutureOr<void> Function()? everyFrame,
}) async {
  final deadline = DateTime.now().add(patience);
  while (!await ready()) {
    if (!DateTime.now().isBefore(deadline)) {
      return false;
    }
    await _lendBoth(tester, beat, step, everyFrame);
  }
  return true;
}

/// Lends both clocks [rounds] times, each round [beat] of real time and
/// then a frame [step] on: a WINDOW — what a test watches for something NOT
/// to happen in, or what it gives work that never says it is done.
///
/// ⛔**A NUMBER OF ROUNDS, NOT A TIME** — the other way round from
/// [settleAsync], because it answers the other question. Under load fewer
/// rounds fit in a time, and a window that sees less passes what it is
/// there to catch: a clock here would turn a real failure into a pass on a
/// busy machine.
///
/// ⚠️Work given a window is the fragile kind: a busy machine can shut the
/// window on it unfinished. Whatever can say it is done waits for that in
/// [settleAsync] instead.
Future<void> lendBothClocks(
  WidgetTester tester, {
  required int rounds,
  Duration beat = _beat,
  Duration step = Duration.zero,
  FutureOr<void> Function()? everyFrame,
}) async {
  for (var round = 0; round < rounds; round += 1) {
    await _lendBoth(tester, beat, step, everyFrame);
  }
}

const _beat = Duration(milliseconds: 20);

Future<void> _lendBoth(
  WidgetTester tester,
  Duration beat,
  Duration step,
  FutureOr<void> Function()? everyFrame,
) async {
  await tester.runAsync(() => Future<void>.delayed(beat));
  await tester.pump(step);
  await everyFrame?.call();
}

/// Lands what the surfaces showing a document's pages asked for — in real
/// time ([settleAsync]) — until none of them says it is loading, and then
/// settles the frames.
///
/// 🚨F-315: a surface whose page has not landed stands a spinner at its
/// middle ([ViewerPageLoading]), an animation that never stops — so
/// `pumpAndSettle` waits on it for good, and a pumped clock never lands the
/// page that would take it down. A test that settled straight after a file
/// opened waits for its page first.
///
/// ⚠️It pumps before it asks: a tree not built since the file was asked for
/// holds no spinner yet, and the wait would end before it began.
Future<void> settleLoadedPages(WidgetTester tester) async {
  await tester.pump();
  final drawn = await settleAsync(
    tester,
    () => find.byType(ViewerPageLoading).evaluate().isEmpty,
  );
  expect(drawn, isTrue, reason: 'a page never landed: the spinner stayed up');
  await tester.pumpAndSettle();
}
