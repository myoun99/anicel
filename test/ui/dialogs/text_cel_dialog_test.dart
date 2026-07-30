import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/text_cel_style.dart';
import 'package:anicel/src/ui/dialogs/text_cel_dialog.dart';

/// The text cel editor dialog (R5): fields round-trip into a
/// [TextCelContent], style chips toggle the axes, cancel pops nothing.
void main() {
  Future<TextCelContent?> run(
    WidgetTester tester, {
    TextCelContent? initial,
    Future<void> Function()? interact,
  }) async {
    // A tall surface keeps the whole field column on screen — this test
    // pins the dialog's CONTRACT (fields → content), not its scrolling.
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    TextCelContent? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Center(
            child: OutlinedButton(
              key: const ValueKey<String>('open'),
              onPressed: () async {
                result = await showDialog<TextCelContent>(
                  context: context,
                  builder: (context) => TextCelDialog(
                    initialContent: initial,
                    creating: initial == null,
                    defaultPosition: const Offset(960, 540),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey<String>('open')));
    await tester.pumpAndSettle();
    if (interact != null) {
      await interact();
    }
    return result;
  }

  testWidgets('typing text and toggling style axes pops the content', (
    tester,
  ) async {
    final result = await run(
      tester,
      interact: () async {
        Future<void> tapVisible(String key) async {
          final finder = find.byKey(ValueKey<String>(key));
          await tester.ensureVisible(finder);
          await tester.pump();
          await tester.tap(finder);
          await tester.pump();
        }

        await tester.enterText(
          find.byKey(const ValueKey<String>('text-cel-text-field')),
          'カット 3',
        );
        await tapVisible('text-cel-size-96');
        await tapVisible('text-cel-bold-toggle');
        await tapVisible('text-cel-align-left');
        await tester.tap(
          find.byKey(const ValueKey<String>('instance-edit-ok-button')),
        );
        await tester.pumpAndSettle();
      },
    );

    expect(result, isNotNull);
    expect(result!.text, 'カット 3');
    expect(result.style.fontSize, 96);
    expect(result.style.bold, isTrue);
    expect(result.style.align, TextCelAlign.left);
    expect(
      result.position,
      const Offset(960, 540),
      reason: 'the default position seeds the fields',
    );
  });

  testWidgets('an existing cel loads its parameters; cancel pops nothing', (
    tester,
  ) async {
    const initial = TextCelContent(
      text: 'BG BOOK',
      style: TextCelStyle(fontSize: 160, backgroundColor: 0xFFC95C5C),
      position: Offset(10, 20),
    );
    final result = await run(
      tester,
      initial: initial,
      interact: () async {
        expect(find.text('BG BOOK'), findsWidgets);
        await tester.tap(
          find.byKey(const ValueKey<String>('instance-edit-cancel-button')),
        );
        await tester.pumpAndSettle();
      },
    );
    expect(result, isNull);
  });
}
