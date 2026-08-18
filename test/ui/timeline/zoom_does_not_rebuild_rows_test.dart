import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timeline_coverage.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/ui/timeline/property_lane_model.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_cells_row.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_rows_scroll_body.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';
import 'package:anicel/src/ui/timeline/timeline_row_run_labels_painter.dart';

import 'timeline_cell_probe.dart';

/// R28 #4: a ZOOM STEP MUST NOT REBUILD A PAINTED ROW.
///
/// `frameCellWidth` used to sit in the row memo key, so one zoom step missed
/// the memo on every visible row at once and rebuilt each row's whole
/// subtree. The frame-axis geometry travels as a listenable now: the painted
/// rows hold the handle, their memo keys on its identity, and the step lands
/// as a repaint plus one box relayout.
///
/// The guard is the widget INSTANCE. A memo hit hands the same object back,
/// so `identical` before and after is exactly "this row did not rebuild" —
/// and the geometry assertions below stop it passing vacuously.
void main() {
  Layer drawingLayer(String id) => Layer(
    id: LayerId(id),
    name: id,
    frames: [Frame(id: FrameId('$id-f1'), duration: 1, strokes: const [])],
    timeline: {0: TimelineExposure.drawing(FrameId('$id-f1'), length: 4)},
  );

  /// A sparse (widget-cell) kind, for the contrast case.
  Layer seLayer(String id) => Layer(
    id: LayerId(id),
    name: id,
    kind: LayerKind.se,
    frames: const [],
    timeline: {0: const TimelineExposure.drawing(FrameId('se-f1'), length: 3)},
  );

  TimelineCellExposureState stateFor(Layer layer, int frameIndex) {
    if (layer.timeline[frameIndex]?.isDrawing ?? false) {
      return TimelineCellExposureState.drawingStart;
    }
    if (coveringDrawingBlockAt(layer.timeline, frameIndex) != null) {
      return TimelineCellExposureState.held;
    }
    return TimelineCellExposureState.uncovered;
  }

  Widget harness(
    List<Layer> layers,
    double cellWidth, {
    bool showSeconds = false,
  }) => MaterialApp(
    home: Scaffold(
      body: Material(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: TimelineFrameRowsScrollBody(
            rows: [
              for (var i = 0; i < layers.length; i += 1)
                TimelineDisplayRow.layer(layers[i], layerIndex: i),
            ],
            activeLayerId: layers.first.id,
            playbackFrameCount: 12,
            frameStartIndex: 0,
            frameEndIndexExclusive: 12,
            leadingFrameSpacerWidth: 0,
            trailingFrameSpacerWidth: 0,
            totalFrameContentWidth: 12 * cellWidth,
            metrics: TimelineGridMetrics(
              frameCellWidth: cellWidth,
              layerRowHeight: 28,
            ),
            exposureStateForLayer: stateFor,
            onSelectLayer: (_) {},
            onSelectFrame: (_) {},
            showSeconds: showSeconds,
          ),
        ),
      ),
    ),
  );

  /// The row widget object currently mounted for [layerId].
  TimelineFrameCellsRow rowWidget(WidgetTester tester, String layerId) =>
      tester.widgetList<TimelineFrameCellsRow>(
        find.byType(TimelineFrameCellsRow),
      ).firstWhere((row) => row.layer.id.value == layerId);

  testWidgets('a zoom step does not rebuild a painted drawing row, and the '
      'cells still move', (tester) async {
    final layers = [drawingLayer('a'), drawingLayer('b'), drawingLayer('c')];
    await tester.pumpWidget(harness(layers, 24));

    final before = [
      for (final layer in layers) rowWidget(tester, layer.id.value),
    ];
    final cellBefore = timelineCellGlobalRect(tester, 'b', 2);
    expect(cellBefore.width, 24);

    // The SAME layers, a different zoom.
    await tester.pumpWidget(harness(layers, 40));

    for (var i = 0; i < layers.length; i += 1) {
      expect(
        identical(rowWidget(tester, layers[i].id.value), before[i]),
        isTrue,
        reason:
            'row ${layers[i].id.value} rebuilt for a zoom step — the memo key '
            'took the geometry back',
      );
    }

    // Not vacuous: the row is showing the NEW geometry without having been
    // rebuilt, which is the whole point.
    final cellAfter = timelineCellGlobalRect(tester, 'b', 2);
    expect(cellAfter.width, 40);
    expect(cellAfter.left, 80, reason: 'cell 2 at 40px cells');
  });

  testWidgets('a SPARSE row survives a zoom step too — its span overlays are '
      'placed at layout time', (tester) async {
    final layers = [seLayer('se-1')];
    await tester.pumpWidget(harness(layers, 24));
    final before = rowWidget(tester, 'se-1');
    final spanFinder = find.byKey(
      const ValueKey<String>('timeline-se-label-se-1-0'),
    );
    expect(tester.getSize(spanFinder).width, 3 * 24);

    await tester.pumpWidget(harness(layers, 40));

    expect(
      identical(rowWidget(tester, 'se-1'), before),
      isTrue,
      reason: 'the SE row used to read geometry at build time and miss the '
          'memo; its overlays follow the live handle now',
    );
    // Not vacuous: the overlay moved with the zoom without being rebuilt.
    expect(
      tester.getSize(spanFinder).width,
      3 * 40,
      reason: 'the span still stretches with the cells',
    );
  });

  testWidgets('a rebuild that is NOT a zoom still reuses the row', (
    tester,
  ) async {
    final layers = [drawingLayer('a')];
    await tester.pumpWidget(harness(layers, 24));
    final before = rowWidget(tester, 'a');

    await tester.pumpWidget(harness(layers, 24));

    expect(identical(rowWidget(tester, 'a'), before), isTrue);
  });

  // A1 (2026-08-17): the frames/seconds toggle is a DISPLAY FACT and must
  // MISS the memo — the run-duration labels ride the row as a foreground
  // painter, so a memo hit handed back the identical widget and the block
  // text stayed in the old mode until an unrelated token field moved
  // (activating a layer was the user's observed workaround). The direct
  // TimelineFrameCellsRow tests could never catch this: they bypass the
  // memoized body, which is exactly where the bug lived.
  testWidgets('A1: the seconds toggle rebuilds the rows and the block text '
      'follows', (tester) async {
    List<String> labelTexts() =>
        (tester
                    .widget<CustomPaint>(
                      find.byKey(
                        const ValueKey<String>('timeline-row-cells-a'),
                      ),
                    )
                    .foregroundPainter!
                as TimelineRowRunLabelsPainter)
            .runLabels()
            .map((label) => label.text)
            .toList();

    final layers = [drawingLayer('a')];
    await tester.pumpWidget(harness(layers, 24));
    final before = rowWidget(tester, 'a');
    expect(labelTexts(), ['4']);

    await tester.pumpWidget(harness(layers, 24, showSeconds: true));

    expect(
      identical(rowWidget(tester, 'a'), before),
      isFalse,
      reason:
          'the display mode joined the memo token — a toggle must rebuild '
          'the row (the memo-token discipline, same as seClipMarkerTooltip '
          'and THE RESIZE LAW)',
    );
    expect(labelTexts(), ['0+4'], reason: 'and the text actually switched');
  });
}
