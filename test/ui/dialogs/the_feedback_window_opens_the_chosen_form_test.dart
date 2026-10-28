import 'package:anicel/src/core/build_stamp.dart';
import 'package:anicel/src/services/feedback/feedback_forms.dart';
import 'package:anicel/src/ui/dialogs/feedback_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 🗣️I-139-Q2 (유저 2026-10-28): 「의견 보내기」 is one row and a window that
/// chooses between the two forms; either opens with the device and the
/// build answered.
void main() {
  const device = (
    model: 'Microsoft Corporation Surface Pro, 11th Edition',
    os: FeedbackOs.windows,
    osVersion: '11 25H2 (26200.6899)',
  );

  Future<List<Uri>> choose(WidgetTester tester, String key) async {
    final opened = <Uri>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showFeedbackWindow(
              context,
              open: (link) async => opened.add(link),
              describe: () => device,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('feedback-window')), findsOneWidget);
    await tester.tap(find.byKey(ValueKey(key)));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('feedback-window')),
      findsNothing,
      reason: '고르면 창은 닫힌다',
    );
    return opened;
  }

  testWidgets('text only opens the text form, answered', (tester) async {
    expect(await choose(tester, 'feedback-text-only'), [
      FeedbackForm.text.prefilled(device, buildStamp),
    ]);
  });

  testWidgets('with files opens the file form, answered', (tester) async {
    expect(await choose(tester, 'feedback-with-files'), [
      FeedbackForm.files.prefilled(device, buildStamp),
    ]);
  });
}
