import 'package:anicel/src/ui/timeline/timeline_edge_auto_pan.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 🚨A GRID REVEALS ITS SELECTION ON BOTH AXES WITH ONE LAW.
///
/// R5 (user, 2026-08-09): the arrow keys walk rows and frames, and the walk
/// used to leave the viewport behind. Both grids answered it, each spelling
/// the whole thing — the timeline with frames across and rows down, the
/// X-sheet with frames down and columns across (the audit's clone scan,
/// round 8). `revealSelectionOnBothAxes` answers both with one reveal, and
/// says nothing about which way a strip runs.
///
/// ↩️It said nothing about which axis was which either, until F-225 (유저
/// 2026-09-29: 「엔드라인 너머부분이 조작안하는거같음 … 언제든 넘어가도록
/// 통일」): the FRAME axis is endless and a walk reaches past its built end,
/// where the rows stop at theirs — so the two are named now.
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

  testWidgets('the same step on either axis lands the same offset — one '
      'reveal, whichever way the strip runs', (tester) async {
    final controllers = await pumpScrollables(tester);
    revealSelectionOnBothAxes(
      frames: (controller: controllers[Axis.horizontal]!, extent: 24, at: 40),
      rows: (controller: controllers[Axis.vertical]!, extent: 24, at: 40),
    );
    await tester.pump();

    expect(controllers[Axis.horizontal]!.offset, greaterThan(0));
    expect(
      controllers[Axis.vertical]!.offset,
      controllers[Axis.horizontal]!.offset,
      reason: 'one law, and it does not know which way the strip runs',
    );
  });

  testWidgets('the same when the frames run DOWN — the X-sheet hands its '
      'axes over the other way round', (tester) async {
    final controllers = await pumpScrollables(tester);
    revealSelectionOnBothAxes(
      frames: (controller: controllers[Axis.vertical]!, extent: 24, at: 40),
      rows: (controller: controllers[Axis.horizontal]!, extent: 24, at: 40),
    );
    await tester.pump();

    expect(controllers[Axis.vertical]!.offset, greaterThan(0));
    expect(
      controllers[Axis.horizontal]!.offset,
      controllers[Axis.vertical]!.offset,
    );
  });

  testWidgets('🚨F-225: a walk past the built end takes the FRAME axis past '
      'it; a ROW axis stops at its own end', (tester) async {
    final controllers = await pumpScrollables(tester);
    final frames = controllers[Axis.horizontal]!;
    final rows = controllers[Axis.vertical]!;
    // Step 100 of 24px is 2400px in: past the 2000px built.
    revealSelectionOnBothAxes(
      frames: (controller: frames, extent: 24, at: 100),
      rows: (controller: rows, extent: 24, at: 100),
    );

    // Read at once: a strip with no cells to grow springs back afterwards —
    // the axis's growth is what holds a real one there.
    expect(
      frames.offset,
      greaterThan(frames.position.maxScrollExtent),
      reason: '↩️held to the built end, the walk stopped at the cut\'s end '
          'while the playhead walked on',
    );
    expect(
      frames.offset + viewport,
      greaterThanOrEqualTo(101 * 24),
      reason: 'the step and its margin are in view',
    );
    expect(rows.offset, rows.position.maxScrollExtent, reason: 'no rows past');
    await tester.pumpAndSettle();
  });

  testWidgets('an axis the selection is not drawn on stays put, and the '
      'other still moves', (tester) async {
    final controllers = await pumpScrollables(tester);
    // ⚠️Scrolled AWAY first, on purpose. At offset 0 a "not drawn" step
    // reveals to a negative offset that the scrollable clamps back to 0, so
    // the guard and no guard look identical — a mutant that deleted it
    // survived exactly this way. Parked mid-strip, dropping the guard drags
    // the view back to the top.
    controllers[Axis.horizontal]!.jumpTo(600);
    await tester.pump();

    revealSelectionOnBothAxes(
      // -1 is what indexOfDisplayRow answers for "not drawn".
      frames: (controller: controllers[Axis.horizontal]!, extent: 24, at: -1),
      rows: (controller: controllers[Axis.vertical]!, extent: 24, at: 40),
    );
    await tester.pump();

    expect(controllers[Axis.horizontal]!.offset, 600);
    expect(controllers[Axis.vertical]!.offset, greaterThan(0));
  });

  testWidgets('a zero extent moves nothing — there is no step to reveal', (
    tester,
  ) async {
    final controllers = await pumpScrollables(tester);
    revealSelectionOnBothAxes(
      frames: (controller: controllers[Axis.horizontal]!, extent: 0, at: 40),
      rows: (controller: controllers[Axis.vertical]!, extent: 0, at: 40),
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
      frames: (controller: controllers[Axis.horizontal]!, extent: 24, at: 2),
      rows: (controller: controllers[Axis.vertical]!, extent: 24, at: 2),
    );
    await tester.pump();

    for (final axis in Axis.values) {
      expect(controllers[axis]!.offset, 0, reason: '$axis');
    }
  });
}
