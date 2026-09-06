import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/dialogs/dialog_verb.dart';

/// 🚨WHAT A DIALOG'S ANSWER IS ALLOWED TO DO — the law twenty sites used
/// to write out by hand: ask, survive the await, drop a cancel, commit.
///
/// Written before those sites became one call, so the merge has something
/// to answer to. The torn-down case is the one that was forgotten in
/// practice (a `mounted` where the twin had `context.mounted`), so it is
/// pinned here rather than left to review.
void main() {
  /// A host with a button that runs [flow] on its own context; the
  /// dialog it opens has three ways out.
  Widget host(Future<void> Function(BuildContext context) flow) => MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => flow(context),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );

  Widget answers(BuildContext dialogContext) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      TextButton(
        onPressed: () => Navigator.of(dialogContext).pop('yes'),
        child: const Text('pop-value'),
      ),
      TextButton(
        onPressed: () => Navigator.of(dialogContext).pop(true),
        child: const Text('pop-true'),
      ),
      TextButton(
        onPressed: () => Navigator.of(dialogContext).pop(false),
        child: const Text('pop-false'),
      ),
      TextButton(
        onPressed: () => Navigator.of(dialogContext).pop(),
        child: const Text('pop-nothing'),
      ),
    ],
  );

  Future<void> open(WidgetTester tester, String answer) async {
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(answer));
    await tester.pumpAndSettle();
  }

  testWidgets('askThenCommit commits exactly the answer', (tester) async {
    final committed = <String>[];
    await tester.pumpWidget(
      host(
        (context) => askThenCommit<String>(
          context,
          dialog: (dialogContext) => Dialog(child: answers(dialogContext)),
          commit: committed.add,
        ),
      ),
    );
    await open(tester, 'pop-value');
    expect(committed, ['yes']);
  });

  testWidgets('a CANCELLED dialog commits nothing', (tester) async {
    final committed = <String>[];
    await tester.pumpWidget(
      host(
        (context) => askThenCommit<String>(
          context,
          dialog: (dialogContext) => Dialog(child: answers(dialogContext)),
          commit: committed.add,
        ),
      ),
    );
    await open(tester, 'pop-nothing');
    expect(committed, isEmpty);
  });

  testWidgets('a caller TORN DOWN while the dialog was open commits '
      'nothing, even though the dialog answered', (tester) async {
    final committed = <String>[];
    late BuildContext hostContext;
    var mountHost = true;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (_, setOuter) => MaterialApp(
          home: Scaffold(
            body: mountHost
                ? Builder(
                    builder: (context) {
                      hostContext = context;
                      return Center(
                        child: ElevatedButton(
                          onPressed: () => askThenCommit<String>(
                            context,
                            dialog: (dialogContext) => Dialog(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  TextButton(
                                    onPressed: () =>
                                        setOuter(() => mountHost = false),
                                    child: const Text('kill-host'),
                                  ),
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(dialogContext).pop('yes'),
                                    child: const Text('pop-value'),
                                  ),
                                ],
                              ),
                            ),
                            commit: committed.add,
                          ),
                          child: const Text('open'),
                        ),
                      );
                    },
                  )
                : const SizedBox.shrink(),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('kill-host'));
    await tester.pumpAndSettle();
    expect(hostContext.mounted, isFalse, reason: 'the host really went away');
    await tester.tap(find.text('pop-value'));
    await tester.pumpAndSettle();

    expect(
      committed,
      isEmpty,
      reason: 'the answer arrived after the caller was gone',
    );
  });

  testWidgets('confirmThenCommit runs on true and stands down on false', (
    tester,
  ) async {
    var runs = 0;
    Widget confirmHost() => host(
      (context) => confirmThenCommit(
        context,
        dialog: (dialogContext) => Dialog(child: answers(dialogContext)),
        commit: () => runs += 1,
      ),
    );

    await tester.pumpWidget(confirmHost());
    await open(tester, 'pop-false');
    expect(runs, 0, reason: 'decline pops false, and false is not a commit');

    await open(tester, 'pop-true');
    expect(runs, 1);

    await open(tester, 'pop-nothing');
    expect(runs, 1, reason: 'a dismissed confirm is a decline');
  });
}
