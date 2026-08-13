import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_frame_range.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/ui/timeline/property_lane_model.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_style.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_cursor_layer.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';
import 'package:anicel/src/ui/timeline/transform_lane_policy.dart'
    show transformGroupHeaderLane, transformLaneDisplayOrder;

/// R27 #14: a LANE (fx/key) span and a CELL span are the same selection
/// idea, so they draw the same band — same overlay, same geometry, same
/// decoration. The lane rows used to paint their own flat rectangle.
void main() {
  const metrics = TimelineGridMetrics(frameCellWidth: 24, layerRowHeight: 28);

  final layer = Layer(
    id: const LayerId('a'),
    name: 'A',
    frames: const [],
  );

  List<TimelineDisplayRow> rowsWithLanes() => [
    TimelineDisplayRow.layer(layer, layerIndex: 0),
    TimelineDisplayRow.lane(
      layer,
      const PropertyLaneRow(laneId: 'position', label: 'Position', keyedFrames: {}),
      layerIndex: 0,
    ),
    TimelineDisplayRow.lane(
      layer,
      const PropertyLaneRow(laneId: 'scale', label: 'Scale', keyedFrames: {}),
      layerIndex: 0,
    ),
    TimelineDisplayRow.lane(
      layer,
      const PropertyLaneRow(laneId: 'opacity', label: 'Opacity', keyedFrames: {}),
      layerIndex: 0,
    ),
  ];

  Future<void> pump(
    WidgetTester tester, {
    TimelineFrameRangeSelection? cells,
    TimelineLaneSelection? lanes,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            height: 200,
            child: Stack(
              children: [
                TimelineCursorLayer(
                  frameCursor: ValueNotifier<int>(0),
                  rows: rowsWithLanes(),
                  activeLayerId: const LayerId('a'),
                  frameStartIndex: 0,
                  frameEndIndexExclusive: 20,
                  leadingFrameSpacerWidth: 0,
                  metrics: metrics,
                  exposureStateForLayer: (_, _) =>
                      TimelineCellExposureState.uncovered,
                  crossAxisExtent: 4 * metrics.layerRowHeight,
                  frameRangeSelection:
                      ValueNotifier<TimelineFrameRangeSelection?>(cells),
                  laneRangeSelection:
                      ValueNotifier<TimelineLaneSelection?>(lanes),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  BoxDecoration decorationOf(WidgetTester tester, String key) {
    final box = tester.widget<DecoratedBox>(
      find
          .descendant(
            of: find.byKey(ValueKey<String>(key)),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    return box.decoration as BoxDecoration;
  }

  testWidgets('the lane band and the cell band are the SAME decoration', (
    tester,
  ) async {
    // ⚠️CONTRACT CHANGED (T6, 2026-08-13): the two are no longer asked for at
    // once. There is ONE selected state at a time ([claimSelection]), and in
    // the one case where a mixed cell drag ends up owning lane state too both
    // bands covered the same rows and stacked their fills — the same span
    // reading darker for having been described twice. They are still the same
    // decoration, which is what this test is for; it asks each on its own now.
    await pump(
      tester,
      lanes: const TimelineLaneSelection(
        layerId: LayerId('a'),
        laneId: 'position',
        startIndex: 2,
        endIndexExclusive: 5,
      ),
    );
    final laneBand = decorationOf(tester, 'timeline-lane-range-selection');

    await pump(
      tester,
      cells: const TimelineFrameRangeSelection(
        layerId: LayerId('a'),
        startIndex: 2,
        endIndexExclusive: 5,
      ),
    );
    final cellBand = decorationOf(tester, 'timeline-frame-range-selection');

    expect(laneBand.color, cellBand.color);
    expect(laneBand.border, cellBand.border);
    expect(laneBand.borderRadius, cellBand.borderRadius);
    expect(laneBand, timelineRangeSelectionBandDecoration);
  });

  /// 🚨T6 (유저 2026-08-13): 「트랜스폼 헤더행, 여전히 프레임 셀 선택범위가
  /// 혼자만 규칙 이상함. **몇번이나 말할까? 통일하라고** … 내부적으로 선택된
  /// 상태일지 몰라도 **ui는 적어도 그렇게 안 되고 있음**」.
  testWidgets('ONE band: a cell span that swept lane rows covers them itself, '
      'and the lane band stands down', (tester) async {
    await pump(
      tester,
      cells: const TimelineFrameRangeSelection(
        layerId: LayerId('a'),
        startIndex: 2,
        endIndexExclusive: 5,
      ),
      lanes: const TimelineLaneSelection(
        layerId: LayerId('a'),
        laneId: 'position',
        startIndex: 2,
        endIndexExclusive: 5,
      ),
    );

    expect(
      find.byKey(const ValueKey<String>('timeline-frame-range-selection')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('timeline-lane-range-selection')),
      findsNothing,
      reason: 'two bands over the same rows stack their fills, and the span '
          'reads darker for having been described twice',
    );
  });

  /// The other half of T6, and the one the user described: a cell span that
  /// ran through a lane or a header must BAND those rows.
  ///
  /// ⛔The band loop used to read `!isLane && coversLayer(...)`, two mistakes
  /// in one condition — it skipped every lane the drag had swept, and it
  /// asked the DERIVED layer list, which cannot spell a header at all. ③ made
  /// `rows` the authority in the model and the drawing never followed, which
  /// is exactly 「내부적으로 선택된 상태일지 몰라도 ui는 그렇게 안 되고 있음」.
  testWidgets('a cell span that ran through a LANE row bands it too', (
    tester,
  ) async {
    await pump(
      tester,
      cells: TimelineFrameRangeSelection(
        layerId: const LayerId('a'),
        startIndex: 2,
        endIndexExclusive: 5,
        rows: [
          const LayerRowAddress(LayerId('a')),
          const LaneRowAddress(LayerId('a'), 'position'),
        ],
      ),
    );

    final band = tester.getRect(
      find.byKey(const ValueKey<String>('timeline-frame-range-selection')),
    );
    expect(
      band.height,
      metrics.layerRowHeight * 2,
      reason: 'the layer row and the lane row it swept — one band over both, '
          'not one band and a skipped row',
    );
  });

  testWidgets('the lane band covers exactly the spanned lane ROWS', (
    tester,
  ) async {
    await pump(
      tester,
      lanes: const TimelineLaneSelection(
        layerId: LayerId('a'),
        laneId: 'position',
        startIndex: 1,
        endIndexExclusive: 4,
        laneIds: ['position', 'scale'],
      ),
    );

    final rect = tester.getRect(
      find.byKey(const ValueKey<String>('timeline-lane-range-selection')),
    );
    final origin = tester.getTopLeft(find.byType(TimelineCursorLayer));
    // Rows: layer(0), position(1), scale(2) → band starts at row 1 and is
    // two rows tall.
    expect(rect.top - origin.dy, moreOrLessEquals(metrics.layerRowHeight));
    expect(rect.height, moreOrLessEquals(2 * metrics.layerRowHeight));
    // Frames 1..4 at 24px cells.
    expect(rect.left - origin.dx, moreOrLessEquals(24));
    expect(rect.width, moreOrLessEquals(72));
  });

  testWidgets('no lane selection paints no lane band', (tester) async {
    await pump(tester);
    expect(
      find.byKey(const ValueKey<String>('timeline-lane-range-selection')),
      findsNothing,
    );
  });

  testWidgets('a whole-group selection bands the HEADER row when the group '
      'is COLLAPSED — the header is the only lane row on screen (R4b fix: '
      'the raw span check left no band at all)', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            height: 200,
            child: Stack(
              children: [
                TimelineCursorLayer(
                  frameCursor: ValueNotifier<int>(0),
                  rows: [
                    TimelineDisplayRow.layer(layer, layerIndex: 0),
                    TimelineDisplayRow.lane(
                      layer,
                      transformGroupHeaderLane,
                      layerIndex: 0,
                    ),
                  ],
                  activeLayerId: const LayerId('a'),
                  frameStartIndex: 0,
                  frameEndIndexExclusive: 20,
                  leadingFrameSpacerWidth: 0,
                  metrics: metrics,
                  exposureStateForLayer: (_, _) =>
                      TimelineCellExposureState.uncovered,
                  crossAxisExtent: 2 * metrics.layerRowHeight,
                  frameRangeSelection:
                      ValueNotifier<TimelineFrameRangeSelection?>(null),
                  laneRangeSelection: ValueNotifier<TimelineLaneSelection?>(
                    const TimelineLaneSelection(
                      layerId: LayerId('a'),
                      // R9 #20: the header is IN the span now — which is
                      // what a real drag produces here, since a collapsed
                      // group shows no member row to start one from.
                      laneId: 'transform-group',
                      startIndex: 1,
                      endIndexExclusive: 4,
                      laneIds: [
                        'transform-group',
                        ...transformLaneDisplayOrder,
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final rect = tester.getRect(
      find.byKey(const ValueKey<String>('timeline-lane-range-selection')),
    );
    final origin = tester.getTopLeft(find.byType(TimelineCursorLayer));
    // Rows: layer(0), group header(1) → the band sits on the header row.
    expect(rect.top - origin.dy, moreOrLessEquals(metrics.layerRowHeight));
    expect(rect.height, moreOrLessEquals(metrics.layerRowHeight));
  });
}
