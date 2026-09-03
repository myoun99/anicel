// A VALUE LABEL: A HORIZONTAL DRAG ADJUSTS BY WHOLE UNITS, A TAP OPENS THE
// INLINE FIELD AND ITS SUBMIT REACHES THE OWNER.
//
// No test named this widget (audit 2026-09-03) although the canvas angle
// and zoom readouts are made of it. These pins drive it as a user does.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/widgets/drag_value_label.dart';
import 'package:anicel/src/ui/widgets/inline_numeric_field.dart';

void main() {
  Future<({List<double> deltas, List<String> edits})> pump(
    WidgetTester tester,
  ) async {
    final deltas = <double>[];
    final edits = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: DragValueLabel(
              keyValue: 'zoom',
              text: '100%',
              onDragDelta: deltas.add,
              onEditSubmit: edits.add,
              unitsPerPixel: 1,
              width: 64,
            ),
          ),
        ),
      ),
    );
    return (deltas: deltas, edits: edits);
  }

  testWidgets('a horizontal drag reports whole units that add up', (
    tester,
  ) async {
    final seen = await pump(tester);
    // One gesture in steps: the early steps pay the recogniser's slop; once
    // the drag is under way, every further step is reported in full.
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('100%')),
    );
    for (var step = 0; step < 6; step += 1) {
      await gesture.moveBy(const Offset(10, 0));
      await tester.pump();
    }
    final afterWarmUp = seen.deltas.fold(0.0, (a, b) => a + b);
    expect(afterWarmUp, greaterThan(0));

    await gesture.moveBy(const Offset(10, 0));
    await tester.pump();
    await gesture.up();
    expect(seen.deltas.fold(0.0, (a, b) => a + b), afterWarmUp + 10);
    for (final delta in seen.deltas) {
      expect(delta, delta.roundToDouble(), reason: 'whole units only');
    }
    expect(seen.edits, isEmpty);
  });

  testWidgets('a tap opens the inline field and its submit reaches the owner', (
    tester,
  ) async {
    final seen = await pump(tester);
    expect(find.byType(InlineNumericField), findsNothing);

    await tester.tap(find.text('100%'));
    await tester.pump();
    expect(find.byType(InlineNumericField), findsOneWidget);

    await tester.enterText(find.byType(TextField), '250');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(seen.edits, ['250']);
    expect(find.byType(InlineNumericField), findsNothing);
    expect(seen.deltas, isEmpty);
  });
}
