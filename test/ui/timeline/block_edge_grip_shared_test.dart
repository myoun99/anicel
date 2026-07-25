import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_animaker_v2/src/models/layer_id.dart';
import 'package:quick_animaker_v2/src/models/timeline_coverage.dart';
import 'package:quick_animaker_v2/src/ui/timeline/timeline_exposure_comma_drag_handle.dart';
import 'package:quick_animaker_v2/src/ui/timeline/timeline_exposure_comma_drag_policy.dart';

/// R28 #3: the block edge grip is ONE widget with CONSTANT geometry.
///
/// Two contracts live here. The first is the user-visible rule — hovering
/// an edge may change its color and nothing else; the R27 #11 version grew
/// the bar on hover and that read as the block resizing under the pointer.
/// The second is structural: the storyboard's cut trim mounts the same
/// [BlockEdgeGrip], so the two surfaces cannot drift apart again (they had
/// — the storyboard's private copy never grew a hover state at all).
void main() {
  Widget harness({required BlockEdgeGripHooks hooks}) {
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 400,
          height: 60,
          child: Stack(
            children: [
              BlockEdgeGrip(
                positionedKey: const ValueKey<String>('grip'),
                edge: TimelineBlockEdge.end,
                blockStartOffset: 0,
                blockEndOffset: 120,
                frameCellExtent: 40,
                crossAxisExtent: 60,
                hitExtent: 12,
                hooks: hooks,
              ),
            ],
          ),
        ),
      ),
    );
  }

  BlockEdgeGripHooks inertHooks() => BlockEdgeGripHooks(
    onBegin: () => true,
    onUpdate: (_) {},
    onEnd: () {},
    onCancel: () {},
  );

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

  Size barSize(WidgetTester tester) => barPainter(tester).barRect.size;

  Color barColor(WidgetTester tester) =>
      blockEdgeGripBarColor(barPainter(tester).ink);

  testWidgets('R28 #3: hover changes the grip color, never its size', (
    tester,
  ) async {
    await tester.pumpWidget(harness(hooks: inertHooks()));
    await tester.pumpAndSettle();

    final restingSize = barSize(tester);
    final restingColor = barColor(tester);

    // Park a mouse pointer on the grip.
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.byType(BlockEdgeGrip)));
    await tester.pumpAndSettle();

    expect(
      barSize(tester),
      restingSize,
      reason: 'R28 #3: the hovered grip must keep its exact geometry',
    );
    expect(
      barColor(tester),
      isNot(restingColor),
      reason: 'the hover still has to READ — through ink alone',
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
            child: Stack(
              children: [
                TimelineBlockEdgeGrip(
                  layerId: const LayerId('a'),
                  blockStartIndex: 0,
                  blockOrdinal: 0,
                  edge: TimelineBlockEdge.start,
                  blockStartOffset: 0,
                  blockEndOffset: 120,
                  frameCellExtent: 40,
                  crossAxisExtent: 60,
                  callbacks: TimelineCommaDragCallbacks(
                    onBegin: (_, _, _) => true,
                    onUpdate: (_) {},
                    onEnd: () {},
                    onCancel: () {},
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
      find.byKey(
        const ValueKey<String>('timeline-block-edge-grip-start-a-0'),
      ),
      findsOneWidget,
      reason: 'the Positioned key format is unchanged by the extraction',
    );
  });
}
