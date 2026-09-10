import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/debug/input_inspector.dart';

/// PEN-1: the input inspector — the pen program's diagnosis overlay.
void main() {
  tearDown(InputInspector.reset);

  Widget harness() => MaterialApp(
    home: Scaffold(
      body: InputInspectorHost(
        child: SizedBox.expand(
          key: const ValueKey<String>('inspector-probe-area'),
          child: GestureDetector(onTap: () {}),
        ),
      ),
    ),
  );

  testWidgets('inert until toggled; the card appears and closes', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    expect(
      find.byKey(const ValueKey<String>('input-inspector-card')),
      findsNothing,
    );
    // While hidden, no listener records anything.
    await tester.tap(
      find.byKey(const ValueKey<String>('inspector-probe-area')),
    );
    expect(InputInspector.samples, isEmpty);

    InputInspector.visible.value = true;
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('input-inspector-card')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('input-inspector-close')),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('input-inspector-card')),
      findsNothing,
    );
    expect(InputInspector.visible.value, isFalse);
  });

  testWidgets('records kinds live — a stylus drag shows as stylus rows', (
    tester,
  ) async {
    InputInspector.visible.value = true;
    await tester.pumpWidget(harness());

    final gesture = await tester.startGesture(
      const Offset(120, 200),
      kind: PointerDeviceKind.stylus,
    );
    await gesture.moveBy(const Offset(30, 0));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(InputInspector.samples, isNotEmpty);
    expect(InputInspector.samples.map((sample) => sample.kind).toSet(), {
      PointerDeviceKind.stylus,
    });
    expect(
      InputInspector.samples.map((sample) => sample.phase),
      containsAll(<String>['down', 'move', 'up']),
    );
    // The card renders the rows (kind name visible in the readout).
    expect(find.textContaining('stylus'), findsWidgets);
  });

  test('peak pressure tracks CONTACT pressure only and clears', () {
    InputInspector.record(
      const PointerDownEvent(kind: PointerDeviceKind.stylus, pressure: 0.42),
    );
    InputInspector.record(
      const PointerMoveEvent(kind: PointerDeviceKind.stylus, pressure: 0.87),
    );
    // Hover pressure never counts toward the peak.
    InputInspector.record(
      const PointerHoverEvent(kind: PointerDeviceKind.stylus),
    );
    expect(InputInspector.peakPressure, 0.87);

    InputInspector.clear();
    expect(InputInspector.peakPressure, 0);
    expect(InputInspector.samples, isEmpty);
  });

  test('the ring stays bounded', () {
    for (var i = 0; i < InputInspector.capacity + 40; i += 1) {
      InputInspector.record(const PointerHoverEvent());
    }
    expect(InputInspector.samples.length, InputInspector.capacity);
  });

  test('PEN-10: touch-down counter + probe notes count, gate and clear', () {
    // Touch downs count; other kinds/phases do not.
    InputInspector.record(const PointerDownEvent());
    InputInspector.record(const PointerDownEvent());
    InputInspector.record(
      const PointerDownEvent(kind: PointerDeviceKind.stylus),
    );
    InputInspector.record(const PointerMoveEvent());
    expect(InputInspector.touchDownCount, 2);

    // Notes only land while the inspector is visible, and stay bounded.
    InputInspector.note('hidden — dropped');
    expect(InputInspector.notes, isEmpty);
    InputInspector.visible.value = true;
    for (var i = 0; i < InputInspector.notesCapacity + 3; i += 1) {
      InputInspector.note('probe $i');
    }
    expect(InputInspector.notes.length, InputInspector.notesCapacity);
    expect(
      InputInspector.notes.last,
      'probe ${InputInspector.notesCapacity + 2}',
    );

    InputInspector.clear();
    expect(InputInspector.touchDownCount, 0);
    expect(InputInspector.notes, isEmpty);
    InputInspector.reset();
  });

  testWidgets('a PINNED line is state: on the card above the rows, and it '
      'outlives the notes and the clear', (tester) async {
    // F-67 hands-on (2026-09-11): the layout probe went through `note`,
    // and the paint probes pushed it out of the five-line ring before the
    // screenshot — the card came back without the one number it was
    // opened for. A layout fact is not an event.
    InputInspector.pin('grid', 'hidden — dropped');
    expect(InputInspector.pinned, isEmpty);

    InputInspector.visible.value = true;
    await tester.pumpWidget(harness());
    InputInspector.pin('grid', 'grid frac=(0.250, 0.000)');
    for (var i = 0; i < InputInspector.notesCapacity + 3; i += 1) {
      InputInspector.note('paint $i');
    }
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('input-inspector-pin-grid')),
      findsOneWidget,
    );
    expect(find.text('grid frac=(0.250, 0.000)'), findsOneWidget);

    InputInspector.clear();
    await tester.pump();
    expect(InputInspector.notes, isEmpty);
    expect(find.text('grid frac=(0.250, 0.000)'), findsOneWidget);

    // Overwritten in place, never a second row.
    InputInspector.pin('grid', 'grid frac=(0.000, 0.000)');
    await tester.pump();
    expect(find.text('grid frac=(0.250, 0.000)'), findsNothing);
    expect(find.text('grid frac=(0.000, 0.000)'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('input-inspector-pin-grid')),
      findsOneWidget,
    );
  });

  test('describe() carries the diagnosis fields', () {
    const event = PointerDownEvent(
      kind: PointerDeviceKind.stylus,
      pressure: 0.5,
      buttons: kPrimaryButton,
      position: Offset(10, 20),
    );
    final line = InputInspectorSample.of(event, 'down').describe();
    expect(line, contains('stylus'));
    expect(line, contains('down'));
    expect(line, contains('p=0.50'));
    expect(line, contains('btn=1'));
    expect(line, contains('(10,20)'));
  });
}
