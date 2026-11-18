import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/native/lost_screen.dart';
import 'package:anicel/src/ui/dialogs/app_confirm_dialog.dart';
import 'package:anicel/src/ui/dialogs/app_progress_dialog.dart';
import 'package:anicel/src/ui/text/app_strings.dart';

/// 🗣️a-lost-gpu-leaves-the-window-unpainted-Q1 (유저 2026-11-16): 「윈도
/// 창으로 알리고 저장하고 다시 시작할지 묻는다」 — once the screen's device
/// went nothing Flutter draws is seen, and the save of 「저장하고 다시 시작」
/// opens the app's windows on its way: whether to replace a file, what a
/// save could not carry, its wait. So the three doors those windows open by
/// ask with a window Windows draws instead ([LostScreen]), each answering
/// as its own window would — and before the screen went, none does.
void main() {
  late List<MethodCall> asked;
  late List<int> presses;

  setUp(() {
    asked = [];
    presses = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(LostScreen.channel, (call) async {
          asked.add(call);
          return presses.isEmpty ? -1 : presses.removeAt(0);
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(LostScreen.channel, null);
      LostScreen.debugForget();
    });
  });

  Future<BuildContext> pumpContext(WidgetTester tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (built) {
            context = built;
            return const SizedBox();
          },
        ),
      ),
    );
    return context;
  }

  const question = ConfirmQuestion(
    keys: (
      window: ValueKey<String>('q'),
      decline: ValueKey<String>('q-no'),
      accept: ValueKey<String>('q-yes'),
    ),
    title: 'Replace?',
    message: 'It is there.',
  );

  testWidgets('a question: Windows asks it, the accept answers true, the '
      'decline false, a window closed without either null — and no window '
      'of the app opens', (tester) async {
    final context = await pumpContext(tester);
    LostScreen.debugGo();

    for (final (press, answer) in const [(0, true), (1, false), (-1, null)]) {
      presses.add(press);
      expect(
        await askConfirm(
          context,
          question,
          accept: const ConfirmChoice('Replace'),
          decline: const ConfirmChoice('Keep'),
        ),
        answer,
      );
      presses.add(press);
      expect(
        await askUntilAnswered(
          context,
          question,
          accept: const ConfirmChoice('Replace'),
          decline: const ConfirmChoice('Keep'),
        ),
        answer,
      );
    }
    expect(asked, hasLength(6));
    for (final call in asked) {
      expect(call.method, LostScreen.askMethod);
      expect(call.arguments, ['Replace?', 'It is there.', 'Replace', 'Keep']);
    }

    await askConfirm(context, question, accept: const ConfirmChoice('Yes'));
    expect(asked.last.arguments, [
      'Replace?',
      'It is there.',
      'Yes',
      AppText.strings.commonCancel,
    ], reason: 'the decline it names where its caller names none');
    await tester.pump();
    expect(find.byType(AppConfirmDialog), findsNothing);
  });

  testWidgets('a notice: Windows says it, the lines it is about under '
      'their heading, with Close alone', (tester) async {
    final context = await pumpContext(tester);
    LostScreen.debugGo();

    await showAppNotice(
      context,
      title: 'Notice',
      message: 'Not saved.',
      details: const [
        NoticeDetails(['FNK_02'], heading: 'Projects'),
      ],
    );
    expect(asked.single.method, LostScreen.askMethod);
    expect(asked.single.arguments, [
      'Notice',
      'Not saved.\n\nProjects\nFNK_02',
      AppText.strings.commonClose,
    ]);
    await tester.pump();
    expect(find.byType(AppConfirmDialog), findsNothing);
  });

  testWidgets('a wait: its work runs bare, behind no window — a window '
      'that waits for a frame would never let it start', (tester) async {
    final context = await pumpContext(tester);
    LostScreen.debugGo();

    final done = await runWithAppProgress<String>(
      context: context,
      title: 'Save',
      runningLabel: 'Saving',
      task: (report) async {
        report(0.5);
        return 'done';
      },
    );
    expect(done, 'done');
    await tester.pump();
    expect(find.byType(AppProgressDialog), findsNothing);
    expect(asked, isEmpty);
  });

  testWidgets('before the screen went, the app asks in its own window and '
      'Windows asks nothing', (tester) async {
    final context = await pumpContext(tester);

    final answer = askConfirm(
      context,
      question,
      accept: const ConfirmChoice('Replace'),
    );
    await tester.pump();
    expect(find.byType(AppConfirmDialog), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('q-yes')));
    await tester.pump();
    expect(await answer, isTrue);

    final notice = showAppNotice(context, title: 'Notice', message: 'M');
    await tester.pump();
    expect(find.byType(AppConfirmDialog), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('app-notice-close')));
    await tester.pumpAndSettle();
    await notice;
    expect(asked, isEmpty);
  });
}
