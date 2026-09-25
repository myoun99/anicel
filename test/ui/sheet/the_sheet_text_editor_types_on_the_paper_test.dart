import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/ui/sheet/sheet_text_edit_layer.dart';

/// The sheets' ONE in-place editor ([SheetTextEditLayer] — the timesheet's
/// header and memo, the conte's ACTION): a tap on a target puts a field ON
/// the printed words, at the view's zoom, in the face the sheet prints.
void main() {
  final viewport = CanvasViewport(zoom: 2, panX: 10, panY: 20);
  const style = TextStyle(fontSize: 8, color: Color(0xFF101010));

  Future<List<String>> pumpLayer(WidgetTester tester) async {
    final committed = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned.fill(
                child: SheetTextEditLayer(
                  viewport: viewport,
                  fieldKey: 'field',
                  barrierKey: 'barrier',
                  targets: [
                    SheetTextTarget(
                      keyValue: 'target',
                      box: const Rect.fromLTWH(0, 0, 100, 40),
                      textRect: const Rect.fromLTWH(4, 4, 92, 32),
                      text: 'A',
                      style: style,
                      multiline: true,
                      onCommitted: committed.add,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return committed;
  }

  testWidgets('the field lands on the printed words, at the view\'s zoom, in '
      'the sheet\'s own face', (tester) async {
    await pumpLayer(tester);
    await tester.tap(find.byKey(const ValueKey<String>('target')));
    await tester.pumpAndSettle();

    final field = find.byKey(const ValueKey<String>('field'));
    expect(field, findsOneWidget);
    // Paper (4, 4) under zoom 2 and pan (10, 20).
    expect(tester.getTopLeft(field), const Offset(18, 28));
    final typed = tester.widget<TextField>(field).style!;
    expect(typed.fontSize, 16, reason: 'the printed 8, at zoom 2');
    expect(typed.color, style.color);
  });

  testWidgets('a tap away commits only what changed; Esc takes it back', (
    tester,
  ) async {
    final committed = await pumpLayer(tester);
    final target = find.byKey(const ValueKey<String>('target'));
    final field = find.byKey(const ValueKey<String>('field'));
    final barrier = find.byKey(const ValueKey<String>('barrier'));

    await tester.tap(target);
    await tester.pumpAndSettle();
    await tester.tap(barrier, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(committed, isEmpty, reason: 'nothing typed, nothing written');

    await tester.tap(target);
    await tester.pumpAndSettle();
    await tester.enterText(field, 'B');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(committed, isEmpty, reason: 'Esc cancels');
    expect(field, findsNothing);

    await tester.tap(target);
    await tester.pumpAndSettle();
    await tester.enterText(field, 'C');
    await tester.tap(barrier, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(committed, ['C']);
  });
}
