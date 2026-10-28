import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsAction;
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/input/control_press_claim.dart'
    show DragVerbClaim;
import 'package:anicel/src/ui/input/value_control_pointers.dart'
    show valueControlOwnsPointer;
import 'package:anicel/src/ui/widgets/axis_bar_gesture.dart';
import 'package:anicel/src/ui/widgets/owning_axis_grip.dart';

/// A GRIP is ONE render object (card frame-panels-build-in-one-frame,
/// 2026-10-25), where the claim and a detector of one `Owning*` recogniser
/// were five elements — and the bar, the scrubbable number, the colour wheel
/// and the pressure curve wrote that pair by hand.
///
/// Every case is asked of the grip and of the pair it replaced, and the two
/// must answer alike.
void main() {
  const childKey = ValueKey<String>('grip-child');

  // Half of it takes a press of its own and half takes none, so the
  // grip's hit behaviour has somewhere to show.
  const child = SizedBox(
    key: childKey,
    width: 80,
    height: 40,
    child: Row(
      children: [
        ColoredBox(
          color: Color(0xFF000000),
          child: SizedBox(width: 40, height: 40),
        ),
        SizedBox(width: 40, height: 40),
      ],
    ),
  );

  // The pair, as `OwningAxisGrip` and the four hand-written sites spelled it.
  Widget pair({
    required Axis? axis,
    required HitTestBehavior behavior,
    required void Function(DragGestureRecognizer recognizer)? configure,
  }) {
    GestureRecognizerFactory one<T extends DragGestureRecognizer>(
      T Function() make,
    ) => GestureRecognizerFactoryWithHandlers<T>(make, (r) => configure!(r));
    final gestures = configure == null
        ? <Type, GestureRecognizerFactory>{}
        : switch (axis) {
            null => {
              OwningPanGestureRecognizer: one(OwningPanGestureRecognizer.new),
            },
            Axis.horizontal => {
              OwningHorizontalDragGestureRecognizer: one(
                OwningHorizontalDragGestureRecognizer.new,
              ),
            },
            Axis.vertical => {
              OwningVerticalDragGestureRecognizer: one(
                OwningVerticalDragGestureRecognizer.new,
              ),
            },
          };
    return DragVerbClaim(
      behavior: behavior,
      child: RawGestureDetector(
        behavior: behavior,
        gestures: gestures,
        child: child,
      ),
    );
  }

  Widget holder(
    bool grip, {
    required Axis? axis,
    required HitTestBehavior behavior,
    required void Function(DragGestureRecognizer recognizer)? configure,
  }) => grip
      ? OwningAxisGrip(
          axis: axis,
          behavior: behavior,
          configure: configure,
          child: child,
        )
      : pair(axis: axis, behavior: behavior, configure: configure);

  // A listener under the holder hears what the holder lets through.
  Future<void> pump(WidgetTester tester, Widget box, List<String> log) =>
      tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Stack(
            children: [
              Positioned.fill(
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (_) => log.add('under'),
                ),
              ),
              Center(child: box),
            ],
          ),
        ),
      );

  var pointer = 1;

  // Presses on the half that is hit, the half that is not and beside the
  // box, each dragged along x and along y — rebuilt mid-drag, as a bar is
  // for every value it is handed.
  Future<void> press(
    WidgetTester tester,
    List<String> log,
    Widget Function() build,
  ) async {
    await pump(tester, build(), log);
    final origin = tester.getTopLeft(find.byKey(childKey));
    for (final at in const [Offset(20, 20), Offset(60, 20), Offset(100, 20)]) {
      for (final by in const [Offset(10, 0), Offset(0, 10)]) {
        pointer += 1;
        log.add('— at $at by $by');
        final gesture = await tester.startGesture(
          origin + at,
          pointer: pointer,
          kind: PointerDeviceKind.mouse,
        );
        log.add('claimed ${valueControlOwnsPointer(pointer)}');
        await gesture.moveBy(by);
        await tester.pump();
        await pump(tester, build(), log);
        await gesture.moveBy(by);
        await tester.pump();
        await gesture.up();
        await tester.pump();
        log.add('released ${!valueControlOwnsPointer(pointer)}');
        await gesture.removePointer();
      }
    }
  }

  void Function(DragGestureRecognizer recognizer) logging(List<String> log) =>
      (recognizer) => recognizer
        ..dragStartBehavior = DragStartBehavior.down
        ..onDown = ((details) => log.add('down ${details.localPosition}'))
        ..onStart = ((details) => log.add('start ${details.localPosition}'))
        ..onUpdate = ((details) =>
            log.add('update ${details.delta} ${details.primaryDelta}'))
        ..onEnd = ((_) => log.add('end'))
        ..onCancel = (() => log.add('cancel'));

  // Every case in ONE tree, so a case after a case finds the box the last
  // one left — an axis that turns, a verb that comes and goes.
  Future<Map<String, String>> everyCase(WidgetTester tester, bool grip) async {
    final logs = <String, String>{};
    for (final enabled in const [true, false, true]) {
      for (final axis in const [Axis.horizontal, null, Axis.vertical]) {
        for (final behavior in HitTestBehavior.values) {
          final log = <String>[];
          await press(
            tester,
            log,
            () => holder(
              grip,
              axis: axis,
              behavior: behavior,
              configure: enabled ? logging(log) : null,
            ),
          );
          logs['$enabled $axis $behavior'] = log.join('\n');
        }
      }
    }
    await tester.pumpWidget(const SizedBox());
    return logs;
  }

  testWidgets('🚨a press and its drag go where the pair sent them — every '
      'axis, every hit behaviour, with a verb and without', (tester) async {
    final gripLogs = await everyCase(tester, true);
    final pairLogs = await everyCase(tester, false);
    expect(gripLogs, pairLogs);

    // ⛔CONTROLS, so that alike is not alike in nothing: the cases tell
    // apart what they ask about.
    String at(bool enabled, Axis? axis, HitTestBehavior behavior) =>
        gripLogs['$enabled $axis $behavior']!;
    final behaviours = {
      for (final b in HitTestBehavior.values) at(true, Axis.horizontal, b),
    };
    expect(behaviours, hasLength(HitTestBehavior.values.length));
    final axes = {
      for (final a in const [Axis.horizontal, null, Axis.vertical])
        at(true, a, HitTestBehavior.opaque),
    };
    expect(axes, hasLength(3));
    expect(
      at(false, Axis.horizontal, HitTestBehavior.opaque),
      allOf(contains('claimed true'), isNot(contains('update'))),
      reason: 'without a verb the press is still claimed, and drags nothing',
    );
    expect(
      at(true, Axis.horizontal, HitTestBehavior.opaque),
      allOf(contains('update'), isNot(contains('released false'))),
    );
  });

  testWidgets('a grip whose axis turns drags along its new one', (
    tester,
  ) async {
    final along = <double?>[];
    Widget grip(Axis axis) => OwningAxisGrip(
      axis: axis,
      configure: (recognizer) => recognizer.onUpdate = (details) =>
          along.add(details.primaryDelta),
      child: child,
    );
    await pump(tester, grip(Axis.horizontal), <String>[]);
    await pump(tester, grip(Axis.vertical), <String>[]);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(childKey)),
      kind: PointerDeviceKind.mouse,
    );
    for (var i = 0; i < 3; i += 1) {
      await gesture.moveBy(const Offset(0, 10));
      await tester.pump();
    }
    await gesture.up();
    expect(along, isNotEmpty);
    expect(along.fold<double>(0, (sum, d) => sum + d!), 30);
  });

  testWidgets('a grip is one element, and one box over its child', (
    tester,
  ) async {
    await pump(
      tester,
      OwningAxisGrip(
        axis: Axis.horizontal,
        configure: (_) {},
        child: child,
      ),
      <String>[],
    );
    final grip = tester.element(find.byType(OwningAxisGrip));
    final children = <Element>[];
    grip.visitChildren(children.add);
    expect([for (final e in children) e.widget.key], [childKey]);
    expect(
      tester.renderObject(find.byKey(childKey)).parent,
      same(tester.renderObject(find.byType(OwningAxisGrip))),
    );
    expect(find.byType(RawGestureDetector), findsNothing);
    expect(find.byType(DragVerbClaim), findsNothing);
  });

  testWidgets('a screen reader is told of a grip what it was told of the '
      'pair — nothing to act on', (tester) async {
    final handle = tester.ensureSemantics();
    Future<int> actions(bool grip) async {
      await pump(
        tester,
        Semantics(
          container: true,
          label: 'grip',
          child: holder(
            grip,
            axis: Axis.horizontal,
            behavior: HitTestBehavior.opaque,
            configure: (_) {},
          ),
        ),
        <String>[],
      );
      final data = tester
          .getSemantics(find.bySemanticsLabel('grip'))
          .getSemanticsData();
      expect(data.hasAction(SemanticsAction.scrollLeft), isFalse);
      return data.actions;
    }

    expect(await actions(true), await actions(false));
    handle.dispose();
  });
}
