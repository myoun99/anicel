import 'dart:async';

import 'package:anicel/src/ui/dialogs/app_progress_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The window an OPEN puts up, which is the opposite trade from a save's.
///
/// A save is rare, slow and asked about, so its window appears instantly
/// (pinned in save_progress_dialog_test, and deliberately kept). An open
/// is constant and usually instant: a window that blinks on every local
/// open is noise about a thing nobody doubted. So an open waits a beat —
/// and the moment it is NOT instant, the window is the only thing that
/// separates 「waiting」 from 「broken」.
///
/// It also has to say WHOSE work the wait is (유저 2026-08-27):
/// 「여는 중」 over a provider download blames the app for the cloud's
/// work, and the person waiting cannot tell them apart unless told.
void main() {
  Future<
    ({
      Completer<String> task,
      Completer<void> closed,
      Completer<void> waiting,
      ValueNotifier<String> status,
      bool Function() cancelled,
    })
  >
  openOver(WidgetTester tester) async {
    final task = Completer<String>();
    final closed = Completer<void>();
    // The work's own signal: completed when it starts waiting on someone
    // else's bytes. Nothing else raises the window.
    final waiting = Completer<void>();
    final status = ValueNotifier<String>('');
    var cancelled = false;
    late BuildContext pageContext;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            pageContext = context;
            return const Scaffold(body: SizedBox());
          },
        ),
      ),
    );

    unawaited(
      runWithAppProgress<String>(
        context: pageContext,
        title: 'Open',
        runningLabel: 'Opening…',
        doneLabel: 'Opened',
        windowKey: const ValueKey<String>('open-progress-dialog'),
        doneLinger: Duration.zero,
        showWhen: waiting.future,
        runningStatus: status,
        onCancel: () => cancelled = true,
        task: (_) => task.future,
      ).then((_) => closed.complete(), onError: (_) => closed.complete()),
    );
    await tester.pump();
    return (
      task: task,
      closed: closed,
      waiting: waiting,
      status: status,
      cancelled: () => cancelled,
    );
  }

  testWidgets('an open that never says it is waiting draws NOTHING', (
    tester,
  ) async {
    // 🚨And time may pass freely: the window is raised by the WORK saying
    // it has started waiting, never by a stopwatch. A clock-triggered
    // window blinks on a local open that merely lost a race with the
    // frame budget — which is exactly how every open-driving widget test
    // went red before this trigger replaced the delay.
    final run = await openOver(tester);

    run.task.complete('opened');
    // Frame by frame: a window that flashes for even one of them is a
    // window the user saw. Checking only at the END would pass against
    // code that shows one and closes it again.
    for (var frame = 0; frame < 8; frame += 1) {
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        find.byKey(const ValueKey<String>('open-progress-dialog')),
        findsNothing,
        reason: 'nothing ever waited, so no window may exist on any frame',
      );
    }
    await tester.pumpAndSettle();
    await run.closed.future;
  });

  testWidgets('an open that says it is WAITING raises the window, and the '
      'line says whose work the wait is', (tester) async {
    final run = await openOver(tester);
    run.status.value = '클라우드에서 내려받는 중 · 3초';
    run.waiting.complete();

    await tester.pump();
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('open-progress-dialog')),
      findsOneWidget,
    );
    expect(
      find.text('클라우드에서 내려받는 중 · 3초'),
      findsOneWidget,
      reason: 'the changing line wins over the fixed one while running',
    );
    expect(find.text('Opening…'), findsNothing);

    // And it keeps up: the same window says the newer thing.
    run.status.value = '12초째 도착하지 않았습니다';
    await tester.pump();
    expect(find.text('12초째 도착하지 않았습니다'), findsOneWidget);

    run.task.complete('opened');
    await tester.pumpAndSettle();
    await run.closed.future;
  });

  testWidgets('🚨 the wait can be STOPPED — a cancel the work honours',
      (tester) async {
    // Honest here in a way it is not for a save: the bytes are not ours,
    // nothing has been applied, and abandoning leaves the app where it
    // was. The button only reports the press; the work is what ends.
    final run = await openOver(tester);
    run.waiting.complete();
    await tester.pump();
    await tester.pump();

    expect(run.cancelled(), isFalse);
    await tester.tap(find.byKey(const ValueKey<String>('app-progress-cancel')));
    await tester.pump();
    expect(run.cancelled(), isTrue);

    run.task.completeError(Exception('stopped'));
    await tester.pumpAndSettle();
    await run.closed.future;
  });

  // ⛔No test here that a SAVE still shows instantly: `showAfter` is opt-in
  // and the default path is pinned where it belongs, by
  // save_progress_dialog_test's 「the window is up before the work is, with
  // NO grace period」. Restating it through this file's harness would be a
  // second copy of one law, and the copy is the one that goes stale.
}
