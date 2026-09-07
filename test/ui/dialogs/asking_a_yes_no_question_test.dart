import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/dialogs/app_confirm_dialog.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/widgets/app_window.dart';

/// `askConfirm` — THE door into the two-button confirm, the way
/// `showAppNotice` is the door into the one-button one. Eight sites opened
/// that window by hand before (the audit's clone scan, 2026-09-07); this
/// names what they all relied on.
void main() {
  const keys = (
    window: ValueKey<String>('ask-dialog'),
    decline: ValueKey<String>('ask-cancel'),
    accept: ValueKey<String>('ask-ok'),
  );

  Future<bool?> ask(
    WidgetTester tester, {
    ConfirmChoice? decline,
    AppWindowActionEmphasis? acceptEmphasis,
  }) async {
    bool? answer;
    var answered = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                answer = await askConfirm(
                  context,
                  const ConfirmQuestion(
                    keys: keys,
                    title: 'Delete it?',
                    message: 'This cannot be undone.',
                  ),
                  decline: decline,
                  accept: ConfirmChoice('Delete', emphasis: acceptEmphasis),
                );
                answered = true;
              },
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(answered, isFalse, reason: 'fixture premise: still open');
    return answer;
  }

  Future<bool?> answerWith(WidgetTester tester, Finder tapping) async {
    await tester.tap(tapping);
    await tester.pumpAndSettle();
    return null;
  }

  testWidgets('THE THREE ANSWERS: accept is true, decline is false, and a '
      'dismissal is NULL — not false', (tester) async {
    // The raw bool? is the point of the helper's shape: the selection-move
    // confirm reads `== false` and the recovery gate reads `== null`, so
    // folding a dismissal into "no" would silently change both.
    bool? accepted;
    bool? declined;
    bool? dismissed;

    Future<void> run(void Function(bool?) sink, Future<void> Function() act) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async => sink(
                  await askConfirm(
                    context,
                    const ConfirmQuestion(
                      keys: keys,
                      title: 'Delete it?',
                      message: 'This cannot be undone.',
                    ),
                    accept: const ConfirmChoice('Delete'),
                  ),
                ),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      await act();
      await tester.pumpAndSettle();
    }

    await run((value) => accepted = value, () async {
      await tester.tap(find.byKey(keys.accept));
    });
    await run((value) => declined = value, () async {
      await tester.tap(find.byKey(keys.decline));
    });
    await run((value) => dismissed = value, () async {
      Navigator.of(tester.element(find.byKey(keys.window))).pop();
    });

    expect(accepted, isTrue);
    expect(declined, isFalse);
    expect(dismissed, isNull);
  });

  testWidgets('the decline label defaults to Cancel — the eight sites that '
      'said nothing all meant that one', (tester) async {
    await ask(tester);
    expect(
      find.descendant(
        of: find.byKey(keys.decline),
        matching: find.text(AppText.strings.commonCancel),
      ),
      findsOneWidget,
    );
    await answerWith(tester, find.byKey(keys.decline));
  });

  testWidgets('an unspoken emphasis is the ROLE\'s — the accept is the '
      'accent-filled one and the decline the quiet one', (tester) async {
    // A [ConfirmChoice] carries no emphasis of its own until a caller
    // names one; six of the eight sites name none, and they all mean this.
    await ask(tester);

    expect(tester.widget(find.byKey(keys.accept)), isA<FilledButton>());
    expect(
      tester.widget<TextButton>(find.byKey(keys.decline)).style
          ?.foregroundColor,
      isNull,
      reason: 'quiet, not danger: danger is the only one that inks the label',
    );
    await answerWith(tester, find.byKey(keys.decline));
  });

  testWidgets('a given decline label wins over the default', (tester) async {
    await ask(tester, decline: const ConfirmChoice('Keep it'));
    expect(find.text('Keep it'), findsOneWidget);
    expect(find.text(AppText.strings.commonCancel), findsNothing);
    await answerWith(tester, find.byKey(keys.decline));
  });

  testWidgets('DANGER ink reaches the accept button — a destructive confirm '
      'must not read like an ordinary one', (tester) async {
    await ask(tester, acceptEmphasis: AppWindowActionEmphasis.danger);

    final accept = find.byKey(keys.accept);
    final scheme = Theme.of(tester.element(accept)).colorScheme;
    expect(
      tester.widget<TextButton>(accept).style?.foregroundColor?.resolve({}),
      scheme.error,
    );
    await answerWith(tester, accept);
  });

  testWidgets('DANGER ink reaches the decline button too — the recovery '
      'gate\'s "open the saved one" throws work away', (tester) async {
    await ask(
      tester,
      decline: const ConfirmChoice(
        'Open the saved one',
        emphasis: AppWindowActionEmphasis.danger,
      ),
    );

    final decline = find.byKey(keys.decline);
    final scheme = Theme.of(tester.element(decline)).colorScheme;
    expect(
      tester.widget<TextButton>(decline).style?.foregroundColor?.resolve({}),
      scheme.error,
    );
    await answerWith(tester, decline);
  });
}
