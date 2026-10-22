import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_frame_range.dart'
    show TimelineLaneSelection;
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_coordinate_policy.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_geometry.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_range_gesture.dart';
import 'package:anicel/src/ui/timeline/timeline_row_cells_painter.dart';

/// 🚨I-57 (10-13): EVERY PRESS ON A ROW READS THE CELL UNDER IT BY ONE LAW
/// ([frameAtVisibleX]) — the cells' pick, the range drag over them, a
/// lane's drag.
///
/// The zoom follows every percent (F-220), so a cell is seldom a whole
/// number of pixels and the law puts each boundary on the pixel nearest
/// it. The cells' range drag read its anchor by the plain quotient, which
/// puts the boundary where the arithmetic falls: a press a pixel short of
/// one picked a cell and anchored the drag on the next.
void main() {
  const cell = 7.3;
  // Frame 2's boundary is the law's pixel 15; the quotient's is 14.6.
  final shortOfTwo = timelineFrameEdge(2, cell) - 0.2;
  final layer = Layer(
    id: const LayerId('row'),
    name: 'Row',
    frames: const [],
    timeline: const {},
  );

  Widget strip(Widget layer) => MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 400,
          height: 24,
          child: Stack(children: [layer]),
        ),
      ),
    ),
  );

  Future<void> dragFrom(WidgetTester tester, double along) async {
    await tester.dragFrom(
      Offset(along, 12),
      const Offset(40, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
  }

  test('a press picks the cell the law puts there', () {
    expect(
      (shortOfTwo / cell).floor(),
      2,
      reason: 'premise: the quotient names the next cell there',
    );
    const frames = TimelineFrameGeometry(
      frameCellExtent: cell,
      frameStartIndex: 0,
      frameEndIndexExclusive: 40,
    );
    expect(frames.cellAt(shortOfTwo), 1);
  });

  testWidgets('the cells\' tap picks the cell the law puts there', (
    tester,
  ) async {
    final picks = <int>[];
    final geometry = ValueNotifier(
      const TimelineFrameGeometry(
        frameCellExtent: cell,
        frameStartIndex: 0,
        frameEndIndexExclusive: 40,
      ),
    );
    addTearDown(geometry.dispose);
    await tester.pumpWidget(
      strip(
        Builder(
          builder: (context) => timelineRowCellsPaintArea(
            context: context,
            keyPrefix: 'timeline',
            layer: layer,
            geometry: geometry,
            crossAxisExtent: 24,
            axis: Axis.horizontal,
            exposureStateForLayer: (_, _) =>
                TimelineCellExposureState.uncovered,
            onSelectLayer: (_) {},
            onSelectFrame: picks.add,
          ),
        ),
      ),
    );

    await tester.tapAt(
      Offset(shortOfTwo, 12),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();

    expect(picks, [1]);
  });

  testWidgets('the cells\' range drag anchors on the cell the press picks', (
    tester,
  ) async {
    final anchors = <int>[];
    await tester.pumpWidget(
      strip(
        TimelineFrameRangeGestureLayer(
          row: LayerRowAddress(layer.id),
          geometry: ValueNotifier(
            const TimelineFrameGeometry(
              frameCellExtent: cell,
              frameStartIndex: 0,
              frameEndIndexExclusive: 40,
            ),
          ),
          crossAxisExtent: 24,
          callbacks: TimelineRangeGestureCallbacks(
            isInSelection: (_, _) => false,
            onSelectUpdate: (_, anchor, _, _) => anchors.add(anchor),
            onTapClear: (_) {},
            onMoveBegin: (_, _) => false,
            onMoveUpdate: (_, _) {},
            onMoveEnd: () {},
            onMoveCancel: () {},
          ),
        ),
      ),
    );

    await dragFrom(tester, shortOfTwo);

    expect(anchors, isNotEmpty, reason: 'LIVENESS: the drag selected');
    expect(anchors.toSet(), {1});
  });

  testWidgets('a lane\'s range drag anchors on the same cell', (
    tester,
  ) async {
    final anchors = <int>[];
    final selection = ValueNotifier<TimelineLaneSelection?>(null);
    addTearDown(selection.dispose);
    await tester.pumpWidget(
      strip(
        TimelineLaneRangeGestureLayer(
          layer: layer,
          laneId: 'position',
          frameStartIndex: 0,
          leadingFrameSpacerWidth: 0,
          frameCellExtent: cell,
          crossAxisExtent: 24,
          callbacks: TimelineLaneRangeCallbacks(
            selection: selection,
            onSelectUpdate: (_, _, anchor, _, _) => anchors.add(anchor),
            onTapAt: (_, _, _) {},
            onTapClear: () {},
            onMoveBegin: () => false,
            onMoveUpdate: (_, {stretch, values}) {},
            onMoveEnd: () {},
            onMoveCancel: () {},
          ),
        ),
      ),
    );

    await dragFrom(tester, shortOfTwo);

    expect(anchors, isNotEmpty, reason: 'LIVENESS: the drag selected');
    expect(anchors.toSet(), {1});
  });
}
