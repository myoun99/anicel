import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/ui/timeline/property_lane_model.dart';
import 'package:anicel/src/ui/timeline/timeline_cells_row_facts.dart';
import 'package:anicel/src/ui/timeline/timeline_drag_preview.dart';

/// 🚨F-195 (measured 2026-09-27): a DRAG STEP REBUILDS NO LANE IT LEFT ALONE.
///
/// An edit in flight hands every row of its layer a new Layer through the
/// row gates, and a lane row that gated on the whole layer rebuilt at every
/// step of an edit it did not show — fourteen lane rows, 646 widgets a step,
/// to redraw two. A lane row gates on its own part of the layer
/// ([laneRowSlice]) through the gate both grids put every row behind
/// ([timelineGatedRow]); a cells row, whose part IS the layer, gates on it.
void main() {
  testWidgets('a cells drag step rebuilds the layer\'s cells row and not its '
      'position lane', (tester) async {
    final layer = Layer(
      id: const LayerId('a'),
      name: 'A',
      frames: [Frame(id: const FrameId('a-1'), duration: 1, strokes: const [])],
      timeline: const {0: TimelineExposure.drawing(FrameId('a-1'), length: 2)},
    );
    const position = PropertyLaneRow(
      laneId: 'position',
      label: 'Position',
      keyedFrames: {},
    );
    final preview = ValueNotifier<TimelineDragPreview?>(null);
    addTearDown(preview.dispose);
    var cellsBuilds = 0;
    var laneBuilds = 0;

    // A tick layer takes a tight box, as a grid's row gives it.
    Widget slot(Widget row) => SizedBox(width: 200, height: 20, child: row);
    await tester.pumpWidget(
      MaterialApp(
        home: Column(
          children: [
            slot(
              timelineGatedRow(
                TimelineDisplayRow.layer(layer, layerIndex: 0),
                preview,
                (context, shown) {
                  cellsBuilds += 1;
                  return const SizedBox.expand();
                },
              ),
            ),
            slot(
              timelineGatedRow(
                TimelineDisplayRow.lane(layer, position, layerIndex: 0),
                preview,
                (context, shown) {
                  laneBuilds += 1;
                  return const SizedBox.expand();
                },
              ),
            ),
          ],
        ),
      ),
    );
    final cellsBefore = cellsBuilds;
    final laneBefore = laneBuilds;

    // A comma drag's step: the block runs on — the transform track is the
    // same object, as `copyWith` keeps what an edit did not touch.
    preview.value = ExposureEdgeDragPreview(
      previewLayer: layer.copyWith(
        timeline: const {
          0: TimelineExposure.drawing(FrameId('a-1'), length: 4),
        },
      ),
    );
    await tester.pump();

    expect(
      cellsBuilds,
      greaterThan(cellsBefore),
      reason: 'premise: the step reached the layer\'s rows',
    );
    expect(
      laneBuilds,
      laneBefore,
      reason: 'the position lane shows nothing the step changed',
    );
  });
}
