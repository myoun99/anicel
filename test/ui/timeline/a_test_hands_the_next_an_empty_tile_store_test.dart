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

/// The timeline tile store is one per process. A test's drain can stop on a
/// real await (a word's glyph bake) that its fake clock never finishes,
/// with rasters still queued behind it; the next test's first request
/// starts a drain of its own, which took the earlier test's rasters first
/// — against that test's painter and resolvers, in this test's zone
/// (2026-09-26: a rows test failed on a raster the test before it had
/// queued). `flutter_test_config` empties the store after every test.
/// ⚠️The two tests run in this order on purpose.
void main() {
  var leftBehindAsks = 0;
  var asksWhenItEnded = -1;

  /// A row of named blocks — every span it rasters bakes a word.
  TimelineRowCellsPainter row(String id, {void Function()? onAsk}) =>
      TimelineRowCellsPainter(
        layer: Layer(
          id: LayerId(id),
          name: id,
          frames: [
            Frame(
              id: const FrameId('cel'),
              duration: 1,
              strokes: const [],
              name: 'A1',
            ),
          ],
          timeline: {
            for (var start = 0; start < 12; start += 4)
              start: const TimelineExposure.drawing(FrameId('cel'), length: 4),
          },
        ),
        geometry: testFrameGeometry(
          frameCellExtent: 24,
          frameEndIndexExclusive: 12,
        ),
        crossAxisExtent: 28,
        exposureStateForLayer: (layer, frameIndex) {
          onAsk?.call();
          return frameIndex % 4 == 0
              ? TimelineCellExposureState.drawingStart
              : TimelineCellExposureState.held;
        },
        frameNameForLayer: (_, frameIndex) => frameIndex % 4 == 0 ? 'A1' : null,
        colorScheme: const ColorScheme.dark(),
        baseTextStyle: const TextStyle(fontSize: 11),
        tileStore: TimelineGridTileStore.instance,
      );

  void ask(TimelineRowCellsPainter painter, int span) =>
      TimelineGridTileStore.instance.tileFor(
        painter: painter,
        spanStartIndex: span * 4,
        spanEndIndexExclusive: span * 4 + 4,
        devicePixelRatio: 1,
      );

  testWidgets('a test that ends with its drain waiting and rasters queued…', (
    tester,
  ) async {
    if (QaNativeEngine.instance == null) {
      markTestSkipped('qa_engine.dll not built');
      return;
    }
    final leftBehind = row('left-behind', onAsk: () => leftBehindAsks += 1);
    for (var span = 0; span < 3; span += 1) {
      ask(leftBehind, span);
    }
    // The drain starts, rasters the first span and waits on its word.
    await tester.pump();
    expect(
      TimelineGridTileStore.instance.debugBusy,
      isTrue,
      reason: 'the premise: the drain is waiting with rasters behind it',
    );
    addTearDown(() => asksWhenItEnded = leftBehindAsks);
  });

  testWidgets('…hands the next test only its own rasters', (tester) async {
    if (QaNativeEngine.instance == null) {
      markTestSkipped('qa_engine.dll not built');
      return;
    }
    ask(row('own'), 0);
    await tester.pump();
    expect(
      leftBehindAsks,
      asksWhenItEnded,
      reason: 'the earlier test\'s rasters asked its resolvers in this one',
    );
  });
}
