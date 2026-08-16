import 'dart:io';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_coverage.dart';
import 'package:anicel/src/ui/timeline/timeline_exposure_comma_drag_handle.dart';
import 'package:anicel/src/ui/timeline/timeline_exposure_comma_drag_policy.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_geometry.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_span_layout.dart';

/// R28 #3: the block edge grip is ONE widget with CONSTANT geometry.
///
/// Two contracts live here. The first is the user-visible rule — hovering an
/// edge may change its color and nothing else; the R27 #11 version grew the
/// bar on hover and that read as the block resizing under the pointer. The
/// second is structural: the storyboard's cut trim mounts the same
/// [BlockEdgeGrip], so the two surfaces cannot drift apart again (they had —
/// the storyboard's private copy never grew a hover state at all).
///
/// The grip FILLS whatever box its mount hands it (zoom round): placement
/// moved out to the mount, so the sparse rows can place theirs by frame span
/// and stop rebuilding on every zoom step. Its bar is read off its own size.
void main() {
  BlockEdgeGripHooks inertHooks() => BlockEdgeGripHooks(
    onBegin: () => true,
    onUpdate: (_) {},
    onEnd: () {},
    onCancel: () {},
  );

  Widget harness({required BlockEdgeGripHooks hooks}) {
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 400,
          height: 60,
          child: Stack(
            children: [
              Positioned(
                left: 108,
                top: 0,
                width: 12,
                height: 60,
                child: BlockEdgeGrip(
                  edge: TimelineBlockEdge.end,
                  resolveFrameCellExtent: () => 40,
                  hooks: hooks,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The grip's bar is PAINTED (R28 #4 tier 2) through the same helpers the
  /// dense rows' chrome painter uses, so both reads come off the painter.
  BlockEdgeGripBarPainter barPainter(WidgetTester tester) {
    final paint = find.descendant(
      of: find.byType(BlockEdgeGrip),
      matching: find.byType(CustomPaint),
    );
    return tester.widget<CustomPaint>(paint.first).painter!
        as BlockEdgeGripBarPainter;
  }

  Size gripSize(WidgetTester tester) =>
      tester.getSize(find.byType(BlockEdgeGrip));

  Color barColor(WidgetTester tester) =>
      blockEdgeGripBarColor(barPainter(tester).ink);

  testWidgets('R28 #3: hover changes the grip color, never its size', (
    tester,
  ) async {
    await tester.pumpWidget(harness(hooks: inertHooks()));
    await tester.pumpAndSettle();

    final restingSize = gripSize(tester);
    final restingColor = barColor(tester);

    // Park a mouse pointer on the grip.
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.byType(BlockEdgeGrip)));
    await tester.pumpAndSettle();

    expect(
      gripSize(tester),
      restingSize,
      reason: 'R28 #3: the hovered grip must keep its exact geometry',
    );
    expect(
      barColor(tester),
      isNot(restingColor),
      reason: 'the hover still has to READ — through ink alone',
    );
  });

  testWidgets('R9 #12: the grip reads engaged from the pointer DOWN, and '
      'lets go on the pointer UP', (tester) async {
    var began = 0;
    await tester.pumpWidget(
      harness(
        hooks: BlockEdgeGripHooks(
          onBegin: () {
            began += 1;
            return true;
          },
          onUpdate: (_) {},
          onEnd: () {},
          onCancel: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(barPainter(tester).ink, BlockEdgeGripInk.rest);

    // Press and HOLD — no movement at all, so no drag recognizer has won.
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(BlockEdgeGrip)),
    );
    await tester.pump();
    expect(
      barPainter(tester).ink,
      BlockEdgeGripInk.dragging,
      reason:
          'the accent used to wait for the drag to win the arena, which '
          'is after the slop — so a press looked like nothing was grabbed',
    );
    expect(began, greaterThanOrEqualTo(0));

    await gesture.up();
    await tester.pumpAndSettle();
    expect(
      barPainter(tester).ink,
      BlockEdgeGripInk.rest,
      reason: 'the release path #12 found missing',
    );
  });

  testWidgets('2026-08-17: the grip bar\'s OUTLINE arm is gone — the bar '
      'reads by the text\'s own ground law, no white silhouette left on '
      'any block ("애초에 통일하기로 했잖아")', (tester) async {
    await tester.pumpWidget(harness(hooks: inertHooks()));
    await tester.pumpAndSettle();

    // The core geometry did not move with the outline's removal.
    final bar = blockEdgeGripBarRect(
      edge: TimelineBlockEdge.end,
      hitExtent: 12,
      crossAxisExtent: 60,
      axis: Axis.horizontal,
    );
    expect(bar.width, 3.5);

    // THE edge pin: the drawing source has exactly one arm — the ground-law
    // fill. A stroke pass or the outline pair coming back is the white
    // silhouette coming back.
    final source = File(
      'lib/src/ui/timeline/timeline_exposure_comma_drag_handle.dart',
    ).readAsStringSync();
    expect(
      source,
      isNot(contains('PaintingStyle.stroke')),
      reason: 'no stroke pass in the grip bar painter',
    );
    expect(
      source,
      isNot(contains('blockEdgeGripOutlineColor')),
      reason: 'the outline ink left with the outline',
    );
    expect(
      source,
      isNot(contains('timelineOutlineWidthFor')),
      reason: 'the outline width rule has no wearer left',
    );
    expect(
      source,
      contains('timelineTextOnColor'),
      reason:
          'the bar\'s ink is the ground law\'s pick, unified with the '
          'block text',
    );
  });

  testWidgets('R28 #3: the timeline binder mounts the shared grip', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 60,
            child: TimelineFixedFrameSpanLayer(
              geometry: const TimelineFrameGeometry(
                frameCellExtent: 40,
                frameStartIndex: 0,
                frameEndIndexExclusive: 10,
              ),
              crossAxisExtent: 60,
              axis: Axis.horizontal,
              children: [
                TimelineFrameSpan(
                  placement: timelineBlockEdgeGripPlacement(
                    edge: TimelineBlockEdge.start,
                    startIndex: 0,
                    endIndexExclusive: 3,
                  ),
                  child: TimelineBlockEdgeGrip(
                    layerId: const LayerId('a'),
                    blockStartIndex: 0,
                    blockOrdinal: 0,
                    edge: TimelineBlockEdge.start,
                    resolveFrameCellExtent: () => 40,
                    callbacks: TimelineCommaDragCallbacks(
                      onBegin: (_, _, _) => true,
                      onUpdate: (_) {},
                      onEnd: () {},
                      onCancel: () {},
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(BlockEdgeGrip), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('timeline-block-edge-grip-start-a-0')),
      findsOneWidget,
      reason: 'the grip key format is unchanged by the extraction',
    );
    // The placement is the pixel rule in frame terms: a third of the edge
    // cell, capped at the nominal hit extent.
    expect(
      tester.getSize(find.byType(BlockEdgeGrip)).width,
      blockEdgeGripHitExtent(40),
    );
    expect(tester.getTopLeft(find.byType(BlockEdgeGrip)).dx, 0);
  });

  testWidgets('the END grip hangs off the block\'s trailing edge', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 60,
            child: TimelineFixedFrameSpanLayer(
              geometry: const TimelineFrameGeometry(
                frameCellExtent: 40,
                frameStartIndex: 0,
                frameEndIndexExclusive: 10,
              ),
              crossAxisExtent: 60,
              axis: Axis.horizontal,
              children: [
                TimelineFrameSpan(
                  placement: timelineBlockEdgeGripPlacement(
                    edge: TimelineBlockEdge.end,
                    startIndex: 0,
                    endIndexExclusive: 3,
                  ),
                  child: BlockEdgeGrip(
                    edge: TimelineBlockEdge.end,
                    resolveFrameCellExtent: () => 40,
                    hooks: inertHooks(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final hit = blockEdgeGripHitExtent(40);
    expect(
      tester.getTopLeft(find.byType(BlockEdgeGrip)).dx,
      moreOrLessEquals(3 * 40 - hit, epsilon: 0.01),
    );
  });
}
