import 'dart:async';

import 'package:anicel/src/ui/dialogs/app_progress_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The window an OPEN puts up — the same window a save puts up, up from
/// the first frame.
///
/// 🪦Until 2026-09-13 an open was the one wait that stayed silent unless a
/// provider made it wait (`showWhen`), on the premise that an open is
/// instant and a window on every local open is noise. A 74MB project on a
/// cloud drive was not instant, said nothing, and the person could not tell
/// it from nothing (유저: 「로딩창 안 떠서 여는 중인지 아닌지 모르겠어」).
/// F-53 had already said what a wait window does: it goes up at once.
///
/// It still has to say WHOSE work the wait is (유저 2026-08-27):
/// 「여는 중」 over a provider download blames the app for the cloud's
/// work, and the person waiting cannot tell them apart unless told.
void main() {
  Future<
    ({
      Completer<String> task,
      Completer<void> closed,
      ValueNotifier<String> status,
      bool Function() cancelled,
    })
  >
  openOver(WidgetTester tester) async {
    final task = Completer<String>();
    final closed = Completer<void>();
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
        runningStatus: status,
        onCancel: () => cancelled = true,
        task: (_) => task.future,
      ).then((_) => closed.complete(), onError: (_) => closed.complete()),
    );
    await tester.pump();
    return (
      task: task,
      closed: closed,
      status: status,
      cancelled: () => cancelled,
    );
  }

  testWidgets('the window is up from the first frame, before the work has '
      'said anything — an open that says nothing cannot be told from '
      'nothing', (tester) async {
    final run = await openOver(tester);
    expect(
      find.byKey(const ValueKey<String>('open-progress-dialog')),
      findsOneWidget,
      reason: 'no grace period and no signal to wait for: the window is '
          'the answer to「is it opening?」',
    );
    expect(find.text('Opening…'), findsOneWidget);

    run.task.complete('opened');
    await tester.pumpAndSettle();
    await run.closed.future;
    expect(
      find.byKey(const ValueKey<String>('open-progress-dialog')),
      findsNothing,
    );
  });

  testWidgets('while a provider is asked for the bytes, the line says whose '
      'work the wait is', (tester) async {
    final run = await openOver(tester);
    run.status.value = '클라우드에서 내려받는 중 · 3초';
    await tester.pump();

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

    // The bytes are here: the fixed line is back for the app's own read.
    run.status.value = '';
    await tester.pump();
    expect(find.text('Opening…'), findsOneWidget);

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

    expect(run.cancelled(), isFalse);
    await tester.tap(find.byKey(const ValueKey<String>('app-progress-cancel')));
    await tester.pump();
    expect(run.cancelled(), isTrue);

    run.task.completeError(Exception('stopped'));
    await tester.pumpAndSettle();
    await run.closed.future;
  });

  // ⛔No test here that a SAVE shows instantly: that is pinned where it
  // belongs, by save_progress_dialog_test's 「the window is up before the
  // work is, with NO grace period」. Restating it through this file's
  // harness would be a second copy of one law, and the copy is the one
  // that goes stale.
}
