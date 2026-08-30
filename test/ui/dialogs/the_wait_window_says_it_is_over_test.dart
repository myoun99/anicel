import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/dialogs/app_progress_dialog.dart';

/// 🚨★★★THE END HAS A MARK NOW (유저 2026-08-31, F-53):
///
/// > 「로딩 완료 시 로딩 아이콘 위치에 **체크 아이콘 넣어서 완료됐단 느낌**
/// > 내고 싶음. 저장 완료 시나 그런 상황. **공통적으로 사용**」
///
/// ⛔It used to render NOTHING in that slot when the work was over — the slot
/// stayed reserved so the line would not shuffle, and then sat empty. The
/// only thing saying 「over」 was the label changing, which is the one part of
/// a progress window a person has stopped reading by then.
///
/// ⚠️This file also pins the OTHER half: the spinner is still there while the
/// work runs. A test that only checked for the check would pass on a window
/// that showed a check the whole time.
void main() {
  Future<void> pump(WidgetTester tester, ValueNotifier<AppProgress> p) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppProgressDialog(
              title: '저장',
              runningLabel: '저장하는 중',
              doneLabel: '저장했습니다',
              progress: p,
            ),
          ),
        ),
      );

  testWidgets('while it runs, the slot turns', (tester) async {
    final p = ValueNotifier(const AppProgress.running(null));
    addTearDown(p.dispose);
    await pump(tester, p);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('app-progress-done')),
      findsNothing,
    );
  });

  testWidgets('🚨when it is over, a check stands where the spinner was', (
    tester,
  ) async {
    final p = ValueNotifier<AppProgress>(const AppProgress.running(0.5));
    addTearDown(p.dispose);
    await pump(tester, p);
    p.value = const AppProgress.done();
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('app-progress-done')),
      findsOneWidget,
      reason: '유저: 「로딩 아이콘 위치에 체크 아이콘」',
    );
    expect(
      find.byType(CircularProgressIndicator),
      findsNothing,
      reason: '⛔and the spinner is gone — the slot holds one thing at a time',
    );
  });
}
