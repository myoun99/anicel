/// These cases raster tiles for real and wait for landings off-frame — the
/// bound the other store files state, for their reason (under load the
/// 30s default dies bare).
@Timeout(Duration(minutes: 3))
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/native/app_gpu_engine.dart';
import 'package:anicel/src/native/engine_faces.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_tile_picture.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_tile_store.dart';
import 'package:anicel/src/ui/timeline/timeline_row_cells_painter.dart';

import '../../helpers/exposure_of.dart';
import '../../helpers/frame_name_of.dart';
import '../../helpers/tiles_drawn_off_the_paint.dart';
import 'tile_store_idle.dart';
import 'timeline_frame_geometry_probe.dart';

/// THE ONE WAIT A WORD THE ENGINE SETS STILL MAKES: the engine's faces,
/// read from the app's bundle once a process (`EngineFaces.bundled`) —
/// which a paint cannot wait for. Till they are read a tile that sets a
/// word is drawn off the paint, as one was for every word it had never
/// seen; from then on the engine bakes a word in the ask that sets it
/// (a-grid-row-paints-its-cells-on-a-canvas-beside-its-tiles-Q3 · Q4, 유저
/// 2026-11-15).
///
/// ⚠️A file of its own: the faces stay read for the process, so only its
/// first ask can meet them unread.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(openAppGpuEngine);

  final store = TimelineGridTileStore.instance;
  setUp(store.clear);
  tearDown(store.clear);

  /// A row of one span — four frames at 128px — with a block of two at its
  /// head, its cel named [name].
  TimelineRowCellsPainter rowNamed(String id, String name) =>
      TimelineRowCellsPainter(
        layer: Layer(
          id: LayerId(id),
          name: id,
          frames: [
            Frame(
              id: FrameId('$id-f'),
              duration: 1,
              strokes: const [],
              name: name,
            ),
          ],
          timeline: {0: TimelineExposure.drawing(FrameId('$id-f'), length: 2)},
        ),
        geometry: testFrameGeometry(
          frameCellExtent: 128,
          frameEndIndexExclusive: 4,
        ),
        crossAxisExtent: 28,
        exposureStateForLayer: exposureOf,
        frameNameForLayer: frameNameOf,
        colorScheme: const ColorScheme.dark(),
        baseTextStyle: const TextStyle(fontSize: 11),
        tileStore: store,
        substrateGeneration: 'faces',
      );

  TimelineGridTilePicture? ask(TimelineRowCellsPainter painter) =>
      store.tileFor(
        painter: painter,
        spanStartIndex: 0,
        spanEndIndexExclusive: 4,
        devicePixelRatio: 1.0,
      );

  test('till the engine\'s faces are read a word waits for them, drawn off '
      'the paint — by the engine all the same — and from then on a word '
      'never seen is baked in the ask that sets it', () async {
    expect(EngineFaces.areRead, isFalse, reason: '⛔premise: the first ask');
    final drawnOff = countTilesDrawnOffThePaint(store);

    final first = rowNamed('first', 'A1');
    expect(
      ask(first),
      isNull,
      reason: 'its faces are read from the bundle, which no ask waits for',
    );
    expect(store.debugBusy, isTrue, reason: 'the tile goes up off the paint');
    await tileStoreIdle(store);

    expect(EngineFaces.areRead, isTrue);
    expect(ask(first), isNotNull, reason: 'it landed');
    expect(drawnOff(), 1, reason: 'off the paint, once');
    final baked = store.debugWordsBakedOnTheEngine;
    expect(baked, isPositive, reason: 'by the engine: nothing was read back');

    final second = rowNamed('second', 'B2');
    expect(ask(second), isNotNull, reason: 'a word never seen, in the ask');
    expect(store.debugWordsBakedOnTheEngine, baked + 1);
    expect(store.debugBusy, isFalse, reason: 'nothing left for off-frame');
    await tileStoreIdle(store);
    expect(drawnOff(), 1, reason: 'none more off the paint');
  });
}
