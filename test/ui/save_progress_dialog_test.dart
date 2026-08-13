import 'dart:async';
import 'dart:io' show FileSystemException;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/dialogs/app_progress_dialog.dart';

/// The window a manual save puts in front of itself.
///
/// The complaint it answers is not "saving is slow" — it is "I cannot tell
/// whether it saved". So the properties under test are about what the user
/// is able to CONCLUDE: that it appears at all for a save that finishes in
/// a blink, that it says so when the work is over, and that it gets out of
/// the way instead of hanging around after a failure.
void main() {
  /// A window over a task the test finishes by hand.
  Future<
    ({
      Completer<String> task,
      Completer<void> closed,
      void Function(double) report,
    })
  >
  showOver(WidgetTester tester) async {
    final task = Completer<String>();
    final closed = Completer<void>();
    late void Function(double) report;
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
        title: 'Save',
        runningLabel: 'Saving…',
        doneLabel: 'Saved',
        windowKey: const ValueKey<String>('save-progress-dialog'),
        doneLinger: const Duration(milliseconds: 40),
        task: (r) {
          report = r;
          return task.future;
        },
      ).then((_) => closed.complete(), onError: (_) => closed.complete()),
    );
    await tester.pump();
    await tester.pump();
    return (task: task, closed: closed, report: report);
  }

  testWidgets('the window is up before the work is, with NO grace period', (
    tester,
  ) async {
    // ⛔ The rejected design, pinned. A delayed window would skip exactly
    // the fast saves — and "did my Ctrl+S do anything?" IS the fast case.
    // Showing nothing for the first 200ms leaves that complaint standing.
    final run = await showOver(tester);
    expect(
      find.byKey(const ValueKey<String>('save-progress-dialog')),
      findsOneWidget,
    );
    expect(find.text('Saving…'), findsOneWidget);

    run.task.complete('written');
    await tester.pumpAndSettle();
  });

  testWidgets('it counts, and the count reads as a percentage', (tester) async {
    final run = await showOver(tester);
    // Nothing reported yet: the spinner turns, and no number is claimed.
    expect(find.byKey(const ValueKey<String>('app-progress-percent')), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    run.report(0.42);
    await tester.pump();
    expect(find.text('42%'), findsOneWidget);

    run.task.complete('written');
    await tester.pumpAndSettle();
  });

  testWidgets('it SAYS it finished, then leaves on its own', (tester) async {
    // The finished line is the whole point — the user asked to be told, not
    // to be left guessing at a window that vanished. And it leaves without
    // a click, because a save happens often enough that a dialog demanding
    // one every time would be worse than the silence it replaced.
    final run = await showOver(tester);
    run.task.complete('written');
    await tester.pump();

    expect(find.text('Saved'), findsOneWidget);
    expect(
      find.byType(CircularProgressIndicator),
      findsNothing,
      reason: 'nothing is still spinning once it is over',
    );

    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('save-progress-dialog')),
      findsNothing,
    );
  });

  testWidgets('a FAILED save takes the window down and comes back out', (
    tester,
  ) async {
    // Otherwise the failure is a spinner that turns for ever: the work is
    // over, nothing will report again, and the window has no way out. The
    // error has to reach the caller so it can be shown — and the caller
    // cannot show anything from behind a modal that never closed.
    final run = await showOver(tester);
    run.task.completeError(const FileSystemException('disk full'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('save-progress-dialog')),
      findsNothing,
    );
    expect(run.closed.isCompleted, isTrue);
  });

  testWidgets('🚨 a route pushed DURING the save does not strand the window', (
    tester,
  ) async {
    // The close used to be a plain `pop`, which takes whatever is on TOP.
    // Anything the app raises while the save runs — a prompt from a
    // lifecycle event, a second dialog — would be closed in this window's
    // place, leaving it up and the caller waiting on a route nobody was
    // going to remove. That is a hang, not a cosmetic slip.
    final run = await showOver(tester);
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    unawaited(
      showDialog<void>(
        context: navigator.context,
        builder: (_) => const AlertDialog(
          key: ValueKey<String>('interloper'),
          content: Text('something else'),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey<String>('interloper')), findsOneWidget);

    run.task.complete('written');
    await tester.pumpAndSettle();

    expect(
      run.closed.isCompleted,
      isTrue,
      reason: 'the caller never came back — it is waiting on its own route',
    );
    expect(
      find.byKey(const ValueKey<String>('save-progress-dialog')),
      findsNothing,
      reason: 'the wrong route was closed and this one was left behind',
    );
    expect(
      find.byKey(const ValueKey<String>('interloper')),
      findsOneWidget,
      reason: 'and the other dialog is not collateral damage',
    );
  });

  testWidgets('it cannot be dismissed while the write is running', (
    tester,
  ) async {
    // Closing it would only hide the write — the isolate keeps going either
    // way — and would hand back a screen that looks idle while the file is
    // still being rewritten under it.
    final run = await showOver(tester);
    await tester.tapAt(const Offset(4, 4)); // the barrier
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('save-progress-dialog')),
      findsOneWidget,
    );

    run.task.complete('written');
    await tester.pumpAndSettle();
  });
}
