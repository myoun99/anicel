import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/dialogs/app_progress_dialog.dart';
import 'package:anicel/src/ui/dialogs/behind_the_wait_window.dart';

/// 🗣️bundle-red-paste-behind-the-wait-window-Q1 (유저 2026-11-05):
/// 「완료비표시 진행창은 로딩창만 보여주고 끝나면 그냥 바로 사라짐」.
///
/// The step windows held a done line for 0.9s under their barrier, and a
/// second Ctrl+Z pressed in it went nowhere (the 11-04 bundle red). The
/// frames counted here are a fraction of that line: a window still up at
/// their end is one that lingers.
void main() {
  const stepKey = ValueKey<String>('take-the-step');
  const pressKey = ValueKey<String>('press-after');

  testWidgets('a step\'s window never says it is over, and a press right '
      'after the step goes through', (tester) async {
    var steps = 0;
    var presses = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Column(
              children: [
                TextButton(
                  key: stepKey,
                  onPressed: () => takeBehindTheWaitWindow(
                    context,
                    () => steps += 1,
                    window: AppWaitWindow.working('work'),
                  ),
                  child: const Text('step'),
                ),
                TextButton(
                  key: pressKey,
                  onPressed: () => presses += 1,
                  child: const Text('press'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final window = find.byType(AppProgressDialog);
    final checked = find.byKey(const ValueKey<String>('app-progress-done'));
    var framesUp = 0;
    var everChecked = false;

    await tester.tap(find.byKey(stepKey));
    for (var frame = 0; frame < 10; frame += 1) {
      await tester.pump(const Duration(milliseconds: 16));
      if (window.evaluate().isNotEmpty) {
        framesUp += 1;
      }
      everChecked = everChecked || checked.evaluate().isNotEmpty;
    }

    expect(
      framesUp,
      greaterThan(0),
      reason: '⛔CONTROL: the step stood behind a window',
    );
    expect(steps, 1);
    expect(everChecked, isFalse, reason: '「로딩창만 보여주고」');
    expect(window, findsNothing, reason: '「끝나면 그냥 바로 사라짐」');

    await tester.tap(find.byKey(pressKey));
    await tester.pump();
    expect(presses, 1, reason: 'no barrier stands past the step');
  });
}
