import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/dialogs/start_number_window.dart';

/// 🗣️I-18 (유저): 「누르면 숫자 편집하는 창 나와서 숫자만 입력가능. 드래그로
/// 조절하거나 수동입력. 기본값은 1인상태」.
void main() {
  const label = ValueKey<String>('auto-name-start');
  const input = ValueKey<String>('auto-name-start-input');

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
                builder: (_) => const StartNumberWindow(),
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

  testWidgets('a tap types the number — digits alone', (tester) async {
    final popped = await open(tester);
    await tester.tap(find.byKey(label));
    await tester.pumpAndSettle();

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
}
