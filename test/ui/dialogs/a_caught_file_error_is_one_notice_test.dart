import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/dialogs/app_confirm_dialog.dart';
import 'package:anicel/src/ui/text/app_strings.dart';

/// `showFileError` — the one way a caught file error reaches the user. It
/// was three spellings in the top strip (a State method the two
/// module-level save/export functions could not call, so they re-typed
/// it), and nothing named it (the audit's clone scan, 2026-09-07).
void main() {
  Future<void> pumpAndFail(WidgetTester tester, Object error) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showFileError(context, error),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
  }

  testWidgets('the error arrives as the shared notice, under the common '
      'title, saying what it said', (tester) async {
    await pumpAndFail(tester, const FormatException('not a project'));

    expect(find.text(AppText.strings.commonNotice), findsOneWidget);
    expect(
      find.textContaining('not a project'),
      findsOneWidget,
      reason: "the error's own text is the message",
    );
    expect(find.byKey(const ValueKey<String>('app-notice-close')), findsOne);
  });

  testWidgets('a plain string error is reported the same way — the caller '
      'does not have to wrap it in an exception', (tester) async {
    await pumpAndFail(tester, 'Not found: /gone/project.anicel');

    expect(
      find.textContaining('Not found: /gone/project.anicel'),
      findsOneWidget,
    );
  });

  testWidgets('the notice is not awaited: the caller returns while it is '
      'still open', (tester) async {
    var returned = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () {
                showFileError(context, 'boom');
                returned = true;
              },
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(returned, isTrue, reason: 'fire-and-forget, by design');
    expect(find.textContaining('boom'), findsOneWidget);
  });
}
