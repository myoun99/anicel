import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/native/qa_native_engine.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_tile_store.dart';
import 'package:anicel/src/ui/timeline/timeline_row_cells_painter.dart';

import 'timeline_frame_geometry_probe.dart';

/// The timeline tile store is one per process, and a raster a test queued
/// drained inside the NEXT test — against the earlier test's painter and
/// resolvers (2026-09-26: a rows test failed on a raster the test before
/// it had queued). `flutter_test_config` empties the store after every
/// test. ⚠️The two tests run in this order on purpose: the first leaves a
/// raster queued, the second is where it would arrive.
void main() {
  testWidgets('a test that ends with a raster still queued…', (tester) async {
    if (QaNativeEngine.instance == null) {
      markTestSkipped('qa_engine.dll not built');
      return;
    }
    final store = TimelineGridTileStore.instance;
    store.tileFor(
      painter: TimelineRowCellsPainter(
        layer: Layer(
          id: const LayerId('left-behind'),
          name: 'A',
          frames: [
            Frame(id: const FrameId('cel'), duration: 1, strokes: const []),
          ],
          timeline: {
            0: const TimelineExposure.drawing(FrameId('cel'), length: 4),
          },
        ),
        geometry: testFrameGeometry(
          frameCellExtent: 24,
          frameEndIndexExclusive: 4,
        ),
        crossAxisExtent: 28,
        exposureStateForLayer: (layer, frameIndex) =>
            frameIndex == 0
            ? TimelineCellExposureState.drawingStart
            : TimelineCellExposureState.held,
        colorScheme: const ColorScheme.dark(),
        baseTextStyle: const TextStyle(fontSize: 11),
        tileStore: store,
      ),
      spanStartIndex: 0,
      spanEndIndexExclusive: 4,
      devicePixelRatio: 1,
    );
    expect(store.debugBusy, isTrue, reason: 'the premise: a raster queued');
  });

  testWidgets('…hands the next one an empty store', (tester) async {
    expect(TimelineGridTileStore.instance.debugBusy, isFalse);
  });
}
