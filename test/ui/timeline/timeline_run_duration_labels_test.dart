import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_cells_row.dart';

import 'timeline_cell_probe.dart';
import 'timeline_frame_geometry_probe.dart';
import 'package:anicel/src/ui/timeline/timeline_row_run_labels_painter.dart';

/// R26 #7 + R27 #3: every frame block prints ITS OWN length — one label
/// per block (never the glued run's total), bare number (no `f`), bold,
/// bottom-CENTRE of the block's last cell.
///
/// R28 #4 painterized these (a `Positioned` per block made a zoom step
/// re-lay-out rows x blocks boxes), so the assertions read the painter's
/// resolved labels instead of hunting `Text` widgets — the same probe shape
/// the cells and ruler painters already use.
void main() {
  /// The row's labels painter, or null when the row draws none. It rides the
  /// cells painter as a FOREGROUND pass now — same geometry, two fewer render
  /// objects per row to lay out on a zoom step.
  TimelineRowRunLabelsPainter? painterOf(
    WidgetTester tester, {
    String layerId = 'a-1',
  }) =>
      tester
              .widget<CustomPaint>(
                find.byKey(ValueKey<String>('timeline-row-cells-$layerId')),
              )
              .foregroundPainter
          as TimelineRowRunLabelsPainter?;

  /// The row's resolved labels, in block order.
  List<TimelineRunLabel> labelsOf(
    WidgetTester tester, {
    String layerId = 'a-1',
  }) => painterOf(tester, layerId: layerId)!.runLabels();

  List<String> textsOf(WidgetTester tester, {String layerId = 'a-1'}) =>
      labelsOf(tester, layerId: layerId).map((label) => label.text).toList();

  Layer drawingLayer(Map<int, TimelineExposure> timeline) => Layer(
    id: const LayerId('a-1'),
    name: 'A',
    kind: LayerKind.animation,
    frames: const [],
    timeline: timeline,
  );

  TimelineCellExposureState stateFor(Layer layer, int frameIndex) =>
      TimelineCellExposureState.uncovered;

  const cellWidth = 48.0;

  Widget harness({required Layer layer, bool showSeconds = false}) {
    return MaterialApp(
      home: Scaffold(
        body: Material(
          child: TimelineFrameCellsRow(
            layer: layer,
            active: true,
            playbackFrameCount: 12,
            geometry: testFrameGeometry(
              frameCellExtent: cellWidth,
              frameEndIndexExclusive: 12,
            ),
            crossAxisExtent: 52,
            exposureStateForLayer: stateFor,
            onSelectLayer: (_) {},
            onSelectFrame: (_) {},
            showSeconds: showSeconds,
          ),
        ),
      ),
    );
  }

  testWidgets('a block prints its frame count as a bare bold number', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        layer: drawingLayer({
          2: const TimelineExposure.drawing(FrameId('f1'), length: 6),
        }),
      ),
    );
    expect(textsOf(tester), ['6'], reason: 'bare number, never "6f"');

    expect(painterOf(tester)!.labelStyle.fontWeight, FontWeight.w700);

    // The label's a11y node survives riding the cells painter as a
    // FOREGROUND pass — RenderCustomPaint builds semantics for both
    // painters, and nothing here asserted that before.
    final semantics = tester.ensureSemantics();
    await tester.pumpAndSettle();
    expect(timelineCellSemanticsLabels(tester, 'a-1'), contains('6'));
    semantics.dispose();
  });

  testWidgets('the seconds toggle switches the label to seconds+frames', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        layer: drawingLayer({
          2: const TimelineExposure.drawing(FrameId('f1'), length: 6),
        }),
        showSeconds: true,
      ),
    );
    // 6 frames at the default 24-base: under a second. Bare digits, the
    // conte sheet's notation (feedback #12) — this used to read `0+06`.
    expect(textsOf(tester), ['0+6']);
  });

  testWidgets('R27 #3: GLUED blocks each label their own length', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        layer: drawingLayer({
          // Two blocks that touch — the glued run totals 5, which must
          // NOT be what shows.
          0: const TimelineExposure.drawing(FrameId('f1'), length: 2),
          2: const TimelineExposure.drawing(FrameId('f2'), length: 3),
        }),
      ),
    );
    expect(textsOf(tester), ['2', '3'], reason: 'never the glued total 5');
  });

  testWidgets('R27 #3: the label centres on the block LAST cell', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        layer: drawingLayer({
          0: const TimelineExposure.drawing(FrameId('f1'), length: 4),
        }),
      ),
    );
    // Block spans frames 0..4 → last cell is [144, 192), centre 168.
    final label = labelsOf(tester).single;
    expect(label.text, '4');
    expect(label.anchor.dx, closeTo(168, 1.5));
    // Bottom-anchored inside the row (52 tall; the glyph insets 1px above).
    expect(label.anchor.dy, 52);
  });

  testWidgets('separate blocks label separately; SE rows stay clean', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        layer: drawingLayer({
          0: const TimelineExposure.drawing(FrameId('f1'), length: 2),
          4: const TimelineExposure.drawing(FrameId('f2'), length: 3),
        }),
      ),
    );
    expect(textsOf(tester), ['2', '3']);

    await tester.pumpWidget(
      harness(
        layer: Layer(
          id: const LayerId('se-1'),
          name: 'S1',
          kind: LayerKind.se,
          frames: const [],
          timeline: {
            0: const TimelineExposure.drawing(FrameId('f1'), length: 4),
          },
        ),
      ),
    );
    expect(
      painterOf(tester, layerId: 'se-1'),
      isNull,
      reason:
          'SE sheet rows carry dialogue and waveforms, not exposure durations',
    );
  });
}
