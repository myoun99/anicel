import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/native/app_gpu_engine.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_tile_picture.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_tile_store.dart';
import 'package:anicel/src/ui/timeline/timeline_row_cells_painter.dart';

import '../../helpers/a_word_that_waits.dart';
import 'tile_store_idle.dart';
import 'timeline_frame_geometry_probe.dart';

/// The timeline tile store is one per process. A test's drain can stop on a
/// real await (a word's first bake reads its raster back) that its fake
/// clock never finishes, with rasters still queued behind it; the next
/// test's first request starts a drain of its own, which took the earlier
/// test's rasters first — against that test's painter and resolvers, in
/// this test's zone (2026-09-26: a rows test failed on a raster the test
/// before it had queued). `flutter_test_config` empties the store after
/// every test. ⚠️The two tests run in this order on purpose.
///
/// The first holds its drain where its drawing waits, on a wait that never
/// ends: ↩️an upload was that await until grid-on-the-engine ⑤.
///
/// The words its tiles are baked from are one per process too, and the
/// config forgets them after every test as well (the last two tests, in
/// this order on purpose): one a test baked stood baked in every test
/// after, where a span that was to wait for it was baked in its ask
/// (2026-11-23: a file naming its cel as the file run before it had).
void main() {
  setUpAll(openAppGpuEngine);
  var leftBehindAsks = 0;
  var asksWhenItEnded = -1;

  // A word its tile WAITS for, whatever ran in this process before: once
  // the engine's faces are read — once a process — a word of theirs is
  // baked in the ask, and no raster is queued for a drain to wait with.
  // ↩️'A1' waited only where this file was the first to ask (red in a
  // bundle behind a file that read the faces, 11-20).
  const word = 'A1$aLetterNoBundledFaceHas';

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
              name: word,
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
        frameNameForLayer: (_, frameIndex) => frameIndex % 4 == 0 ? word : null,
        colorScheme: const ColorScheme.dark(),
        baseTextStyle: const TextStyle(fontSize: 11),
        tileStore: TimelineGridTileStore.instance,
      );

  /// [painter]'s tile of [span], or null while it is waited for.
  TimelineGridTilePicture? ask(TimelineRowCellsPainter painter, int span) =>
      TimelineGridTileStore.instance.tileFor(
        painter: painter,
        spanStartIndex: span * 4,
        spanEndIndexExclusive: span * 4 + 4,
        devicePixelRatio: 1,
      );

  testWidgets('a test that ends with its drain waiting and rasters queued…', (
    tester,
  ) async {
    final store = TimelineGridTileStore.instance;
    store.debugBeforeDrawing = () => Completer<void>().future;
    addTearDown(() => store.debugBeforeDrawing = null);
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
    ask(row('own'), 0);
    await tester.pump();
    expect(
      leftBehindAsks,
      asksWhenItEnded,
      reason: 'the earlier test\'s rasters asked its resolvers in this one',
    );
  });

  test('a test that ends with the word of its tiles baked…', () async {
    expect(
      ask(row('first-to-set-it'), 0),
      isNull,
      reason: 'the premise: its word, never seen, is waited for',
    );
    await tileStoreIdle(TimelineGridTileStore.instance);
    expect(
      ask(row('second-to-set-it'), 0),
      isNotNull,
      reason: 'the premise: the word landed — a row that sets it now is '
          'baked in its ask',
    );
  });

  test('…hands the next test a store that has baked no word', () {
    expect(
      ask(row('own'), 0),
      isNull,
      reason: 'the earlier test\'s word stood baked in this one',
    );
  });
}
