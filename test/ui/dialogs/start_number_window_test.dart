import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/dialogs/start_number_window.dart';
import 'package:anicel/src/ui/widgets/drag_value_label.dart';
import '../../helpers/number_pad_keyboard.dart';

/// 🗣️I-18 (유저): 「누르면 숫자 편집하는 창 나와서 숫자만 입력가능. 드래그로
/// 조절하거나 수동입력. 기본값은 1인상태」.
void main() {
  const label = ValueKey<String>('auto-name-start');
  const input = ValueKey<String>('auto-name-start-input');
  const pencil = ValueKey<String>('auto-name-start-edit');

  /// Opens the window; the answer reads what it popped.
  Future<int? Function()> open(WidgetTester tester) async {
    int? popped;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              popped = await showDialog<int>(
                context: context,
                builder: (_) => const StartNumberWindow(target: 'Frame'),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return () => popped;
  }

  String shown(WidgetTester tester) => tester
      .widget<Text>(
        find.descendant(of: find.byKey(label), matching: find.byType(Text)),
      )
      .data!;

  testWidgets('it opens at 1, and Apply answers the number', (tester) async {
    final popped = await open(tester);
    expect(
      find.byKey(const ValueKey<String>('auto-name-dialog')),
      findsOneWidget,
    );
    expect(shown(tester), '1', reason: '「기본값은 1인상태」');

    await tester.tap(
      find.byKey(const ValueKey<String>('auto-name-apply-button')),
    );
    await tester.pumpAndSettle();
    expect(popped(), 1);
  });

  testWidgets('a drag to the right counts up, and one to the left stops at '
      'zero', (tester) async {
    await open(tester);

    await tester.drag(find.byKey(label), const Offset(120, 0));
    await tester.pumpAndSettle();
    expect(int.parse(shown(tester)), greaterThan(1));

    await tester.drag(find.byKey(label), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(shown(tester), '0');
  });

  testWidgets('its pencil types the number — digits alone', (tester) async {
    final popped = await open(tester);
    await tester.tap(find.byKey(pencil));
    await tester.pumpAndSettle();

    await openThePadsKeyboard(tester);
    await tester.enterText(find.byKey(input), 'a');
    await tester.pump();
    expect(find.text('a'), findsNothing, reason: '「숫자만 입력가능」');

    await tester.enterText(find.byKey(input), '12');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(shown(tester), '12');

    await tester.tap(
      find.byKey(const ValueKey<String>('auto-name-apply-button')),
    );
    await tester.pumpAndSettle();
    expect(popped(), 12);
  });

  testWidgets('Cancel answers nothing', (tester) async {
    final popped = await open(tester);
    await tester.tap(
      find.byKey(const ValueKey<String>('auto-name-cancel-button')),
    );
    await tester.pumpAndSettle();
    expect(popped(), isNull);
    expect(
      find.byKey(const ValueKey<String>('auto-name-dialog')),
      findsNothing,
    );
  });

  /// 🗣️tool-settings-panel-tidy (유저 2026-10-10): 「숫자 뒤에 ±와 연필」 —
  /// the start number's ± are the settings bars' own pair.
  testWidgets('its ± step it a number at a time, and stop at zero', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(
      find.byKey(const ValueKey<String>('auto-name-start-step-up')),
    );
    await tester.pumpAndSettle();
    expect(shown(tester), '2');
    final down = find.byKey(
      const ValueKey<String>('auto-name-start-step-down'),
    );
    for (var step = 0; step < 3; step += 1) {
      await tester.tap(down);
      await tester.pumpAndSettle();
    }
    expect(shown(tester), '0');
  });

  // 🗣️F-507 (유저 2026-10-29): 「자동이름조정 왼쪽정렬인거 이상하니
  // 중앙정렬」.
  testWidgets('its number stands in the middle of the window', (tester) async {
    await open(tester);
    expect(
      tester.getCenter(find.byType(DragValueLabel)).dx,
      moreOrLessEquals(
        tester
            .getCenter(find.byKey(const ValueKey<String>('auto-name-dialog')))
            .dx,
      ),
    );
  });
}
