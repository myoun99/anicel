import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_double_tap.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_row_cells_painter.dart';

import 'timeline_frame_geometry_probe.dart';

/// R26 #37: the cell editor opens on two taps of the SAME cell only —
/// tapping two different frames of one block is two seeks (the double-tap
/// recognizer's 100px slop used to fuse them into a rename).
void main() {
  const layerId = LayerId('layer');
  const cellExtent = 24.0;
  final layer = Layer(
    id: layerId,
    name: 'A',
    frames: [
      Frame(id: const FrameId('cel'), duration: 6, strokes: const []),
    ],
    timeline: {0: const TimelineExposure.drawing(FrameId('cel'), length: 6)},
  );

  setUp(TimelineCellDoubleTapGate.reset);

  Future<void> pumpRow(
    WidgetTester tester, {
    required List<int> activations,
    required List<int> selections,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: Builder(
              builder: (context) => timelineRowCellsPaintArea(
                context: context,
                keyPrefix: 'timeline',
                layer: layer,
                active: true,
                playbackFrameCount: 6,
                geometry: testFrameGeometry(
                  frameCellExtent: cellExtent,
                  frameEndIndexExclusive: 6,
                ),
                crossAxisExtent: 24,
                axis: Axis.horizontal,
                exposureStateForLayer: (_, _) =>
                    TimelineCellExposureState.held,
                onSelectLayer: (_) {},
                onSelectFrame: selections.add,
                onActivateCell: (_, frameIndex) => activations.add(frameIndex),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Offset centerOf(int frameIndex) =>
      Offset(frameIndex * cellExtent + cellExtent / 2, 12);

  testWidgets('two taps on DIFFERENT frames of one block never activate the '
      'cell editor', (tester) async {
    final activations = <int>[];
    final selections = <int>[];
    await pumpRow(tester, activations: activations, selections: selections);

    await tester.tapAt(centerOf(0));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(centerOf(1));
    await tester.pump(const Duration(milliseconds: 700));

    expect(activations, isEmpty, reason: 'a seek, not a rename');
    expect(selections, containsAllInOrder(<int>[0, 1]));
  });

  testWidgets('two taps on the SAME frame still activate the cell editor', (
    tester,
  ) async {
    final activations = <int>[];
    final selections = <int>[];
    await pumpRow(tester, activations: activations, selections: selections);

    await tester.tapAt(centerOf(2));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(centerOf(2));
    await tester.pump(const Duration(milliseconds: 700));

    expect(activations, <int>[2]);
  });
}
