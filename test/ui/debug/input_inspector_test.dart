import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_input_settings.dart';
import 'package:anicel/src/native/qa_tablet_bridge.dart';
import 'package:anicel/src/services/input/wintab_pen_service.dart';
import 'package:anicel/src/ui/debug/input_inspector.dart';

import '../../helpers/fake_tablet_bridge.dart';

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
    expect(InputInspector.events, isEmpty);

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

  testWidgets('the strip says how far the driver\'s newest packet ran '
      'behind the mouse, and what its queue lost', (tester) async {
    final service = WintabPenService.instance;
    addTearDown(service.debugReset);
    service.debugBridge = FakeTabletBridge();
    service.start();
    service.freshPacket();
    service.debugInjectPacket(
      const QaTabletPacket(pressure: 0.4, timeMs: 0, buttons: 1),
    );
    InputInspector.visible.value = true;
    await tester.pumpWidget(harness());

    String said(String key) =>
        tester.widget<Text>(find.byKey(ValueKey<String>(key))).data!;
    expect(said('input-inspector-wintab'), 'wt p=0.40');
    expect(said('input-inspector-touch-count'), endsWith(' wt gap=7 over=3'));
    // The poll timer must die before the binding's pending-timer check.
    service.debugReset();
  });

  testWidgets('h61-wintab-sometimes-not-engaged-at-launch: the card shows '
      'how the driver\'s stream started — kept from before it opened, and '
      'not cleared by ⟲ — and, while the context is still refused, the '
      'tries and why', (tester) async {
    final service = WintabPenService.instance;
    addTearDown(service.debugReset);
    WintabPenService.debugClockOverride = () => DateTime(2026);
    service.debugBridge = FakeTabletBridge()
      ..refusals.addAll([QaTabletOpen.noWindow, QaTabletOpen.noWindow]);
    service.apply(const AppInputSettings(tabletService: TabletService.wintab));
    service.freshPacket();
    service.freshPacket();
    InputInspector.visible.value = true;
    await tester.pumpWidget(harness());

    String said(String key) =>
        tester.widget<Text>(find.byKey(ValueKey<String>(key))).data!;
    final steps = [
      'wt +0ms APPLY wintab running=false',
      'wt +0ms START timer',
      'wt +0ms OPEN no try=1 noWindow',
    ];
    expect([for (var i = 0; i < 3; i += 1) said(_startStep(i))], steps);
    expect(find.byKey(ValueKey<String>(_startStep(3))), findsNothing);
    expect(
      said('input-inspector-touch-count'),
      endsWith(' wt open try=2 noWindow'),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('input-inspector-clear')),
    );
    await tester.pump();
    expect([for (var i = 0; i < 3; i += 1) said(_startStep(i))], steps);
    // The poll timer must die before the binding's pending-timer check.
    service.debugReset();
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

    expect(InputInspector.events, isNotEmpty);
    expect(
      InputInspector.events.values.map((sample) => sample.kind).toSet(),
      {PointerDeviceKind.stylus},
    );
    expect(
      InputInspector.events.values.map((sample) => sample.phase),
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
    expect(InputInspector.events, isEmpty);
  });

  test('one slot per kind and phase — the latest event of each, in the '
      'order they first came', () {
    InputInspector.visible.value = true;
    InputInspector.record(
      const PointerHoverEvent(
        kind: PointerDeviceKind.stylus,
        position: Offset(1, 0),
      ),
    );
    InputInspector.record(const PointerDownEvent(position: Offset(2, 0)));
    for (var i = 0; i < 40; i += 1) {
      InputInspector.record(
        PointerHoverEvent(
          kind: PointerDeviceKind.stylus,
          position: Offset(3 + i.toDouble(), 0),
        ),
      );
    }
    expect(
      InputInspector.events.keys,
      orderedEquals(['stylus hover', 'touch down']),
    );
    final events = InputInspector.events;
    expect(events['stylus hover']!.position, const Offset(42, 0));
    expect(events['touch down']!.position, const Offset(2, 0));
  });

  test('PEN-10: touch-down counter + probe notes — gated, one slot per '
      'emitter, cleared', () {
    // Touch downs count; other kinds/phases do not.
    InputInspector.record(const PointerDownEvent());
    InputInspector.record(const PointerDownEvent());
    InputInspector.record(
      const PointerDownEvent(kind: PointerDeviceKind.stylus),
    );
    InputInspector.record(const PointerMoveEvent());
    expect(InputInspector.touchDownCount, 2);

    // Notes only land while the inspector is visible, and each EMITTER
    // (the line's first token) holds one slot: a loud one overwrites its
    // own slot and never evicts another's, and the rows keep the order the
    // emitters first spoke in (유저 2026-09-13: 「발화자마다 한 칸」).
    InputInspector.note('hidden — dropped');
    expect(InputInspector.notes, isEmpty);
    InputInspector.visible.value = true;
    InputInspector.note('geom view=8x8');
    for (var i = 0; i < 8; i += 1) {
      InputInspector.note('probe $i');
    }
    expect(
      InputInspector.notes.values,
      orderedEquals(['geom view=8x8', 'probe 7']),
    );
    InputInspector.note('geom view=9x9');
    expect(
      InputInspector.notes.values,
      orderedEquals(['geom view=9x9', 'probe 7']),
      reason: 'a slot keeps its row when it is overwritten',
    );
    // The same line again is not a change the card needs to draw.
    final revision = InputInspector.revision.value;
    InputInspector.note('probe 7');
    expect(InputInspector.revision.value, revision);

    InputInspector.clear();
    expect(InputInspector.touchDownCount, 0);
    expect(InputInspector.notes, isEmpty);
    InputInspector.reset();
  });

  testWidgets('a PINNED line is state: on the card, and it '
      'outlives the notes and the clear', (tester) async {
    // F-67 hands-on (2026-09-11): the layout probe went through `note`,
    // and the paint probes pushed it out of the ring (five lines then)
    // before the screenshot — the card came back without the one number
    // it was opened for. A layout fact is not an event: the ring is keyed
    // per emitter now and cannot evict, but ⟲ still clears it.
    InputInspector.pin('grid', 'hidden — dropped');
    expect(InputInspector.pinned, isEmpty);

    InputInspector.visible.value = true;
    await tester.pumpWidget(harness());
    InputInspector.pin('grid', 'grid frac=(0.250, 0.000)');
    for (var i = 0; i < 8; i += 1) {
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

/// The key of the start record's [i]th step on the card.
String _startStep(int i) => 'input-inspector-wintab-start-$i';
