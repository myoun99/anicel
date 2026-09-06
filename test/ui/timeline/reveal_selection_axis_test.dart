import 'package:anicel/src/ui/timeline/timeline_edge_auto_pan.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 🚨A GRID REVEALS ITS SELECTION ON BOTH AXES, AND NEITHER AXIS IS NAMED.
///
/// R5 (user, 2026-08-09): the arrow keys walk rows and frames, and the walk
/// used to leave the viewport behind. Both grids answered it, each spelling
/// the whole thing — the timeline with frames across and rows down, the
/// X-sheet with frames down and columns across (the audit's clone scan,
/// round 8). `revealSelectionOnBothAxes` takes two [RevealedStep]s and says
/// nothing about which is which, so a grid hands its two scrollables in
/// whichever order it holds them and gets the same answer.
void main() {
  const viewport = 200.0;
  const content = 2000.0;

  Future<Map<Axis, ScrollController>> pumpScrollables(
    WidgetTester tester,
  ) async {
    final controllers = {
      Axis.horizontal: ScrollController(),
      Axis.vertical: ScrollController(),
    };
    addTearDown(() {
      for (final controller in controllers.values) {
        controller.dispose();
      }
    });
    await tester.binding.setSurfaceSize(const Size(600, 400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              for (final axis in Axis.values)
                SizedBox(
                  width: viewport,
                  height: viewport,
                  child: SingleChildScrollView(
                    scrollDirection: axis,
                    controller: controllers[axis],
                    child: SizedBox(
                      width: axis == Axis.horizontal ? content : viewport,
                      height: axis == Axis.horizontal ? viewport : content,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    return controllers;
  }

  testWidgets('the same step on either axis lands the same offset', (
    tester,
  ) async {
    final controllers = await pumpScrollables(tester);
    revealSelectionOnBothAxes(
      (controller: controllers[Axis.horizontal]!, extent: 24, at: 40),
      (controller: controllers[Axis.vertical]!, extent: 24, at: 40),
    );
    await tester.pump();

    expect(controllers[Axis.horizontal]!.offset, greaterThan(0));
    expect(
      controllers[Axis.vertical]!.offset,
      controllers[Axis.horizontal]!.offset,
      reason: 'one law, and it does not know which way the strip runs',
    );
  });

  testWidgets('the ORDER of the two axes changes nothing — a grid hands '
      'them over as it holds them', (tester) async {
    final first = await pumpScrollables(tester);
    revealSelectionOnBothAxes(
      (controller: first[Axis.horizontal]!, extent: 24, at: 40),
      (controller: first[Axis.vertical]!, extent: 10, at: 30),
    );
    await tester.pump();
    final asHeld = (
      first[Axis.horizontal]!.offset,
      first[Axis.vertical]!.offset,
    );

    final swapped = await pumpScrollables(tester);
    revealSelectionOnBothAxes(
      (controller: swapped[Axis.vertical]!, extent: 10, at: 30),
      (controller: swapped[Axis.horizontal]!, extent: 24, at: 40),
    );
    await tester.pump();

    expect(swapped[Axis.horizontal]!.offset, asHeld.$1);
    expect(swapped[Axis.vertical]!.offset, asHeld.$2);
  });

  testWidgets('an axis the selection is not drawn on stays put, and the '
      'other still moves', (tester) async {
    final controllers = await pumpScrollables(tester);
    revealSelectionOnBothAxes(
      // -1 is what indexOfDisplayRow answers for "not drawn".
      (controller: controllers[Axis.horizontal]!, extent: 24, at: -1),
      (controller: controllers[Axis.vertical]!, extent: 24, at: 40),
    );
    await tester.pump();

    expect(controllers[Axis.horizontal]!.offset, 0);
    expect(controllers[Axis.vertical]!.offset, greaterThan(0));
  });

  testWidgets('a zero extent moves nothing — there is no step to reveal', (
    tester,
  ) async {
    final controllers = await pumpScrollables(tester);
    revealSelectionOnBothAxes(
      (controller: controllers[Axis.horizontal]!, extent: 0, at: 40),
      (controller: controllers[Axis.vertical]!, extent: 0, at: 40),
    );
    await tester.pump();

    for (final axis in Axis.values) {
      expect(controllers[axis]!.offset, 0, reason: '$axis');
    }
  });

  testWidgets('a step already on screen is left alone — the reveal moves '
      'the least it can', (tester) async {
    final controllers = await pumpScrollables(tester);
    revealSelectionOnBothAxes(
      (controller: controllers[Axis.horizontal]!, extent: 24, at: 2),
      (controller: controllers[Axis.vertical]!, extent: 24, at: 2),
    );
    await tester.pump();

    for (final axis in Axis.values) {
      expect(controllers[axis]!.offset, 0, reason: '$axis');
    }
  });
}
