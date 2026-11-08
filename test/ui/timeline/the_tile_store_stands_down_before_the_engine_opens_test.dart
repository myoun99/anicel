import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/native/app_gpu_engine.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_tile_store.dart';
import 'package:anicel/src/ui/timeline/timeline_row_cells_painter.dart';

import '../../helpers/exposure_of.dart';
import 'timeline_frame_geometry_probe.dart';

/// BEFORE THE APP'S ENGINE IS OPEN THE TILE STORE STANDS DOWN ENTIRELY
/// ([appGpuEngineOpen]): it answers no span and asks for none, and its
/// rows keep the classic paint — as every row does in a file that opens
/// no engine. A file of its own: an engine once open stays open.
void main() {
  test('a span asked for before the engine opens is none, and nothing is '
      'rastered for it', () async {
    final store = TimelineGridTileStore.instance;
    final revisionBefore = store.revision.value;
    expect(appGpuEngineOpen.value, isNull, reason: 'premise');

    final tile = store.tileFor(
      painter: TimelineRowCellsPainter(
        layer: Layer(
          id: const LayerId('layer-a'),
          name: 'A',
          frames: [
            Frame(id: const FrameId('f1'), duration: 1, strokes: const []),
          ],
          timeline: {
            0: const TimelineExposure.drawing(FrameId('f1'), length: 2),
          },
        ),
        geometry: testFrameGeometry(
          frameCellExtent: 24,
          frameEndIndexExclusive: 40,
        ),
        crossAxisExtent: 28,
        exposureStateForLayer: exposureOf,
        colorScheme: const ColorScheme.dark(),
        baseTextStyle: const TextStyle(fontSize: 11),
        tileStore: store,
      ),
      spanStartIndex: 0,
      spanEndIndexExclusive: 4,
      devicePixelRatio: 1.0,
    );
    await pumpEventQueue();

    expect(tile, isNull);
    expect(store.debugBusy, isFalse, reason: 'nothing asked for');
    expect(store.revision.value, revisionBefore);
  });
}
