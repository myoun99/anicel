/// The tile case rasters for real and waits for the landing, which under a
/// loaded machine crosses the test package's default 30s — see the head of
/// `timeline_grid_tile_store_test.dart` for the bound and the open round.
@Timeout(Duration(minutes: 3))
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/native/qa_engine_abi.dart';
import 'package:anicel/src/native/qa_native_engine.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_tile_store.dart';
import 'package:anicel/src/ui/timeline/timeline_row_cells_painter.dart';

import '../../helpers/exposure_of.dart';
import '../../helpers/native_engine_path.dart';
import 'timeline_frame_geometry_probe.dart';

/// I-22 ③: A ROW READS EACH CELL ONCE A PASS.
///
/// A zoom past the reach of the stale tiles repaints every row the classic
/// way, and the frame after it costs what that pass reads (~190ms at
/// 0.8px/frame, debug). A cell's model asks its own exposure and both its
/// neighbours', the models beside it ask them again, a word's room walks
/// them once more, and a frame line asked a whole model of its own cell —
/// so a cell's state was read several times a pass, each read a search of
/// the layer's blocks. The tile a span bakes read its paper in one pass and
/// its ink outside any.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final dllPath = nativeEngineLibraryPathOrNull();
  final available = dllPath != null;

  /// Blocks of several lengths from frame 0, each named, then empty frames.
  Layer rowLayer({List<int> lengths = const [3, 7, 2, 12, 5]}) {
    final timeline = <int, TimelineExposure>{};
    var start = 0;
    for (final length in lengths) {
      timeline[start] = TimelineExposure.drawing(
        const FrameId('f'),
        length: length,
      );
      start += length;
    }
    return Layer(
      id: const LayerId('row'),
      name: 'row',
      frames: [Frame(id: const FrameId('f'), duration: 1, strokes: const [])],
      timeline: timeline,
    );
  }

  /// A row whose exposure resolver counts what it is asked, frame by frame.
  ({TimelineRowCellsPainter painter, Map<int, int> asked}) countedRow(
    Layer layer, {
    required double cellExtent,
    required int frames,
    TimelineGridTileStore? tileStore,
    bool blockFrameLines = false,
  }) {
    final asked = <int, int>{};
    return (
      painter: TimelineRowCellsPainter(
        layer: layer,
        geometry: testFrameGeometry(
          frameCellExtent: cellExtent,
          frameEndIndexExclusive: frames,
        ),
        crossAxisExtent: 28,
        exposureStateForLayer: (layer, frame) {
          asked[frame] = (asked[frame] ?? 0) + 1;
          return exposureOf(layer, frame);
        },
        // A word in every covered cell that starts one, wider than the
        // cell at a narrow zoom — so it grows into its block.
        frameNameForLayer: (layer, frame) => 'ABCD',
        colorScheme: const ColorScheme.dark(),
        baseTextStyle: const TextStyle(fontSize: 11),
        tileStore: tileStore,
        substrateGeneration: tileStore == null ? '' : 'i22',
        blockFrameLines: blockFrameLines,
        framesPerSecond: 24,
      ),
      asked: asked,
    );
  }

  void paintRow(TimelineRowCellsPainter painter, int frames, double extent) {
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder), Size(frames * extent, 28));
    recorder.endRecording().dispose();
  }

  test('a paint asks each cell for its exposure once — however many of its '
      'neighbours, words and lines ask about it', () {
    // 4px a frame: every word outgrows its cell and walks into its block.
    final (:painter, :asked) = countedRow(
      rowLayer(),
      cellExtent: 4,
      frames: 40,
      blockFrameLines: true,
    );
    paintRow(painter, 40, 4);

    expect(asked, isNotEmpty, reason: 'premise: the paint read the row');
    expect(
      {
        for (final MapEntry(key: frame, value: times) in asked.entries)
          if (times > 1) frame: times,
      },
      isEmpty,
      reason: 'a cell asked twice in one pass is a second search of the '
          "layer's blocks for the same answer",
    );
  });

  test('a frame line inside a block asks no cell of its own — its stretch '
      'answers for it', () {
    // One long block at 24px a frame, the lines on: a line at every
    // boundary the cadence draws, all of them inside the one block.
    final (:painter, :asked) = countedRow(
      rowLayer(lengths: const [120]),
      cellExtent: 24,
      frames: 120,
      blockFrameLines: true,
    );
    paintRow(painter, 120, 24);

    expect(
      asked.keys.where((frame) => frame > 3 && frame < 116),
      isEmpty,
      reason: 'only the cells about the block\'s two edges paint differently '
          'from their neighbours; every line between them stands on paper '
          'the block\'s own stretch already answered',
    );
  });

  test('a tile asks each of its cells once — its paper and its ink are ONE '
      'pass, as a paint is', () async {
    if (!available) {
      markTestSkipped('qa_engine.dll not built');
      return;
    }
    QaNativeEngine.debugResetForTests();
    debugQaEngineLibraryPathOverride = dllPath;
    QaNativeEngine.debugForceDartFallback = false;
    final store = TimelineGridTileStore.instance..clear();
    addTearDown(() {
      QaNativeEngine.debugResetForTests();
      debugQaEngineLibraryPathOverride = null;
      store.clear();
    });
    final (:painter, :asked) = countedRow(
      rowLayer(),
      cellExtent: 4,
      frames: 40,
      tileStore: store,
      blockFrameLines: true,
    );

    // One span, asked for directly: every read below is the raster's.
    const span = (start: 0, end: 24);
    expect(
      store.tileFor(
        painter: painter,
        spanStartIndex: span.start,
        spanEndIndexExclusive: span.end,
        devicePixelRatio: 1,
      ),
      isNull,
      reason: 'premise: cold',
    );
    while (store.debugBusy) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }

    expect(asked, isNotEmpty, reason: 'premise: the raster read the row');
    expect(
      {
        for (final MapEntry(key: frame, value: times) in asked.entries)
          if (times > 1) frame: times,
      },
      isEmpty,
    );
  });
}
