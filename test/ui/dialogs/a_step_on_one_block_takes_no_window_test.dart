import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/dialogs/app_progress_dialog.dart';
import 'package:anicel/src/ui/dialogs/behind_the_wait_window.dart';

/// 🗣️F-566 (유저 2026-11-05): 「변형도 셀 하나만 할때는 진행창안띄움. 다른
/// 블록에 걸쳐서 변형할때만 진행창뜸. 그러니 우리도 색변환이던 뭐던 …
/// 대상이 여러블록일때만 띄우도록. 대상이 한 블록이면 안띄움」.
///
/// The doors' one entrance: a step on one block is taken at the press, with
/// no window on any frame; a step on two stands behind it. Work ahead off
/// the UI thread stands behind it whatever it reaches — a wait.
void main() {
  Future<BuildContext> pump(WidgetTester tester) async {
    late BuildContext pressedIn;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            pressedIn = context;
            return const SizedBox();
          },
        ),
      ),
    );
    return pressedIn;
  }

  /// How many of the next frames the wait window was up in.
  Future<int> framesUp(WidgetTester tester) async {
    var up = 0;
    for (var frame = 0; frame < 6; frame += 1) {
      await tester.pump(const Duration(milliseconds: 16));
      if (find.byType(AppProgressDialog).evaluate().isNotEmpty) {
        up += 1;
      }
    }
    return up;
  }

  testWidgets('one block, named on every frame of its hold: taken at the '
      'press, and no window is ever up', (tester) async {
    final context = await pump(tester);
    var steps = 0;
    final taken = takeBehindTheWaitWindow(
      context,
      () => steps += 1,
      window: AppWaitWindow.working('work'),
      blocks: const ['A1', 'A1', 'A1'],
    );
    expect(steps, 1, reason: 'taken at the press, before any frame');
    expect(await framesUp(tester), 0);
    await taken;
  });

  testWidgets('two blocks: the step waits for the window\'s first frame, '
      'and the window is up', (tester) async {
    final context = await pump(tester);
    var steps = 0;
    final taken = takeBehindTheWaitWindow(
      context,
      () => steps += 1,
      window: AppWaitWindow.working('work'),
      blocks: const ['A1', 'B1'],
    );
    expect(steps, 0, reason: 'the window is drawn first');
    expect(await framesUp(tester), greaterThan(0));
    expect(steps, 1);
    await taken;
  });

  testWidgets('work ahead stands behind the window, on one block too', (
    tester,
  ) async {
    final context = await pump(tester);
    var steps = 0;
    final taken = workAheadBehindTheWaitWindow(
      context,
      () => steps += 1,
      window: AppWaitWindow.working('work'),
      ahead: (_) async {},
    );
    expect(await framesUp(tester), greaterThan(0));
    expect(steps, 1);
    await taken;
  });
}
