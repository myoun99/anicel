// A VALUE LABEL: A HORIZONTAL DRAG ADJUSTS BY WHOLE UNITS, A TAP OPENS THE
// INLINE FIELD AND ITS SUBMIT REACHES THE OWNER.
//
// No test named this widget (audit 2026-09-03) although the canvas angle
// and zoom readouts are made of it. These pins drive it as a user does.
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/theme/app_scroll_behavior.dart';
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
    // One gesture in steps: the early steps pay the slop a tap is allowed
    // (the scrub waits it out); once the value moves, every further step is
    // reported in full.
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

  /// 🚨H24 (유저 2026-09-15: 「뷰어쪽 줌 레일스크롤바랑 겹치는거」) — the
  /// label where the dock puts it when a panel is squeezed: at the top of a
  /// list that scrolls. The canvas zoom and angle readouts are this widget.
  Future<({List<double> deltas, List<String> edits, ScrollController scroll})>
  pumpInList(WidgetTester tester) async {
    final deltas = <double>[];
    final edits = <String>[];
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      MaterialApp(
        scrollBehavior: const AppScrollBehavior(),
        // A Scaffold: the inline field is a TextField and needs a Material
        // above it, or a tap that DID open the field fails the test.
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 300,
              height: 200,
              child: SingleChildScrollView(
                controller: scroll,
                child: Column(
                  children: [
                    DragValueLabel(
                      keyValue: 'zoom',
                      text: '100%',
                      onDragDelta: deltas.add,
                      onEditSubmit: edits.add,
                      unitsPerPixel: 1,
                      width: 64,
                    ),
                    const SizedBox(
                      key: ValueKey<String>('below-the-label'),
                      width: 300,
                      height: 600,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (deltas: deltas, edits: edits, scroll: scroll);
  }

  Future<void> dragUp(
    WidgetTester tester,
    Offset from,
    PointerDeviceKind kind,
  ) async {
    final gesture = await tester.startGesture(from, kind: kind);
    for (var step = 0; step < 6; step += 1) {
      await gesture.moveBy(const Offset(0, -24));
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();
  }

  group('inside a list that scrolls', () {
    testWidgets('⛔fixture premise: a drag off the label scrolls the list', (
      tester,
    ) async {
      final seen = await pumpInList(tester);
      await dragUp(
        tester,
        tester.getTopLeft(
              find.byKey(const ValueKey<String>('below-the-label')),
            ) +
            const Offset(150, 60),
        PointerDeviceKind.touch,
      );
      expect(seen.scroll.offset, greaterThan(0));
    });

    for (final kind in const [
      PointerDeviceKind.touch,
      PointerDeviceKind.stylus,
      PointerDeviceKind.mouse,
    ]) {
      testWidgets('a ${kind.name} drag that starts on the label and runs '
          'straight up is the label\'s — the list never moves', (tester) async {
        final seen = await pumpInList(tester);
        await dragUp(tester, tester.getCenter(find.text('100%')), kind);
        expect(seen.scroll.offset, 0);
        expect(
          find.byType(InlineNumericField),
          findsNothing,
          reason: 'it lifted outside the label',
        );
      });
    }

    testWidgets('a pen tap that wobbles opens the field and moves nothing', (
      tester,
    ) async {
      final seen = await pumpInList(tester);
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('100%')),
        kind: PointerDeviceKind.stylus,
      );
      // ⚠️In STEPS, the way a pen wobbles. The drag takes the arena on the
      // first movement and reports nothing for that one, so a single step
      // never reaches the slop the scrub waits out — a one-step wobble
      // passed with that slop deleted.
      for (final step in const [Offset(2, 1), Offset(3, 0), Offset(-2, 1)]) {
        await gesture.moveBy(step);
        await tester.pump();
      }
      await gesture.up();
      await tester.pump();
      expect(find.byType(InlineNumericField), findsOneWidget);
      expect(seen.deltas, isEmpty);
    });

    testWidgets('a scrub that moved the value does not open the field when '
        'it lifts', (tester) async {
      final seen = await pumpInList(tester);
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('100%')),
        kind: PointerDeviceKind.touch,
      );
      for (var step = 0; step < 6; step += 1) {
        await gesture.moveBy(const Offset(10, 0));
        await tester.pump();
      }
      await gesture.up();
      await tester.pump();
      expect(seen.deltas, isNotEmpty);
      expect(find.byType(InlineNumericField), findsNothing);
    });
  });
}
