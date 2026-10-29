/// The tiled case rasters for real and waits for the landing off-frame, as
/// `a_tile_keeps_what_an_edit_left_alone` does.
@Timeout(Duration(minutes: 3))
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_coverage.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_repeat.dart';
import 'package:anicel/src/native/qa_engine_abi.dart';
import 'package:anicel/src/native/qa_native_engine.dart';
import 'package:anicel/src/ui/text/laid_out_glyph.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_tile_store.dart';
import 'package:anicel/src/ui/timeline/timeline_row_cells_painter.dart';

import '../../helpers/frame_name_of.dart';
import '../../helpers/native_engine_path.dart';
import '../../helpers/painted_glyph_boxes.dart';
import '../../helpers/run_edge_fixtures.dart';
import 'tile_store_idle.dart';
import 'timeline_frame_geometry_probe.dart';

/// 🗣️F-446 (유저 2026-10-23: 「타임라인패널에서 엔드라인 드래그로 조절하는게
/// 레이어가 많아질수록 렉이 심함」): A GHOST IS LAID OVER THE TILES.
///
/// A ghost is what the cut's length draws — the last run's fills to the
/// drawn end — so whatever a ghost inks moved at every step of the end
/// line, on every row of a TVPaint cut, and the tile it ended in baked
/// again. Its ink is the row's to lay over its tiles at every paint: the
/// words and marks of its cells, the X that closes it, and a hold's line
/// (`a_hold_is_one_line`). A tile bakes the rest, and each cell inks once.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const cut = 16;
  const built = 24;

  // The session's reading of a drawing row's cells, as the tile test reads
  // it (`ExposureVerbs.exposureStateForLayer`).
  TimelineCellExposureState stateFor(Layer layer, int frameIndex) {
    if (frameIndex >= 0 && (layer.timeline[frameIndex]?.isDrawing ?? false)) {
      return TimelineCellExposureState.drawingStart;
    }
    return frameIndex >= 0 &&
            coveringDrawingBlockAt(layer.timeline, frameIndex) != null
        ? TimelineCellExposureState.held
        : TimelineCellExposureState.uncovered;
  }

  Layer rowOf(
    Map<int, TimelineExposure> timeline, {
    (String, String) names = ('1', '2'),
  }) => rederiveRunBehaviors(
    Layer(
      id: const LayerId('row'),
      name: 'A',
      frames: [
        for (final (id, name) in [('a', names.$1), ('b', names.$2)])
          Frame(id: FrameId(id), duration: 1, strokes: const [], name: name),
      ],
      timeline: timeline,
    ),
    drawnFrameCount: cut,
  );

  // A run of two blocks, 0..3, that REPEATS to the cut's end: its ghost
  // prints the names 1 · 2 · 1 · 2 … from 4, and the X closes it at 16.
  Layer repeatedAs((String, String) names) => rowOf({
    0: const TimelineExposure.drawing(FrameId('a'), length: 2),
    2: const TimelineExposure.drawing(
      FrameId('b'),
      length: 2,
      endEdge: repeatMark,
    ),
  }, names: names);
  final repeated = repeatedAs(('1', '2'));
  // A block over 2..4 that HOLDS to the cut's end: its cells write nothing,
  // and the X closes it at 16.
  final held = rowOf({
    2: const TimelineExposure.drawing(
      FrameId('a'),
      length: 3,
      endEdge: holdMark,
    ),
  });

  TimelineRowCellsPainter painterFor(
    Layer layer, {
    TimelineGridTileStore? store,
    ValueNotifier<int>? bucket,
  }) => TimelineRowCellsPainter(
    layer: layer,
    geometry: testFrameGeometry(
      viewExtentPx: bucket == null ? 0 : 96,
      frameCellExtent: 24,
      frameEndIndexExclusive: built,
    ),
    crossAxisExtent: 28,
    exposureStateForLayer: stateFor,
    frameNameForLayer: frameNameOf,
    colorScheme: const ColorScheme.dark(),
    baseTextStyle: const TextStyle(fontSize: 11),
    tileStore: store,
    substrateGeneration: 'p:cut',
    windowBucket: bucket,
  );

  group('which cells ink a ghost', () {
    test("a repeat's names are its ghost's, and so is the X that closes it",
        () {
      final painter = painterFor(repeated);
      expect(
        painter.writingCellsIn(0, built).toList(),
        [0, 2, 4, 6, 8, 10, 12, 14, 16],
        reason: 'premise: the run, its ghost of six names, and the X',
      );
      expect(painter.ghostInkCellsIn(0, built).toList(), [
        4, 6, 8, 10, 12, 14, 16,
      ]);
      expect(painter.bakedWritingCellsIn(0, built).toList(), [0, 2]);
    });

    test("a hold's cells write nothing — only the X that closes it", () {
      final painter = painterFor(held);
      expect(painter.ghostInkCellsIn(0, built).toList(), [16]);
      expect(
        painter.bakedWritingCellsIn(0, built).toList(),
        [0, 2],
        reason: 'the X before the block, and its name',
      );
    });

    test('every cell that writes is the tile\'s or the ghost\'s, never '
        'both', () {
      for (final layer in [repeated, held]) {
        final painter = painterFor(layer);
        final baked = painter.bakedWritingCellsIn(0, built).toSet();
        final ghost = painter.ghostInkCellsIn(0, built).toSet();
        expect(baked.intersection(ghost), isEmpty);
        expect(
          {...baked, ...ghost},
          painter.writingCellsIn(0, built).toSet(),
        );
      }
    });

    test('a name the ghost writes is not a tile\'s lead into its span', () {
      final painter = painterFor(repeated);
      expect(
        painter.bakedWordGrowingInto(5),
        isNull,
        reason: 'the ghost\'s 1 at 4 is laid over the tiles whole',
      );
    });

    test('a ghost\'s name that grows into the window from before it is laid '
        'by the row, whole', () {
      final bucket = ValueNotifier<int>(2);
      addTearDown(bucket.dispose);
      // Wider than a cell, narrower than the two its ghost runs through.
      final painter = painterFor(
        repeatedAs(('1-2', '2-3')),
        bucket: bucket,
      );
      final window = painter.visibleFrameWindow();
      expect(window.startIndex, 6, reason: 'fixture');
      final model = painter.cellModelAt(4);
      final width = laidOutGlyph(
        model.glyph,
        painter.glyphStyleFor(model),
      ).width;
      expect(width, inExclusiveRange(24, 48), reason: 'fixture');
      expect(
        painter.bakedWordGrowingInto(6),
        isNull,
        reason: 'premise: the window\'s lead is a tile\'s, and no tile '
            'lays a ghost\'s word',
      );
      final spy = _PaintSpy();
      painter.paint(spy, const Size(built * 24, 28));
      expect(
        spy.boxes.map((box) => box.left),
        anyElement(closeTo(painter.cellRectFor(4).left, 0.5)),
      );
    });
  });

  group('the tiles and the row', () {
    final dllPath = nativeEngineLibraryPathOrNull();
    final store = TimelineGridTileStore.instance;

    setUp(() {
      QaNativeEngine.debugResetForTests();
      debugQaEngineLibraryPathOverride = dllPath;
      QaNativeEngine.debugForceDartFallback = false;
      store.clear();
    });

    tearDown(() {
      QaNativeEngine.debugResetForTests();
      debugQaEngineLibraryPathOverride = null;
      QaNativeEngine.debugForceDartFallback = false;
      store.clear();
    });

    Future<List<int>> opsOf(Layer layer, int from, int to) =>
        store.debugForegroundOps(
          painter: painterFor(layer),
          spanStartIndex: from,
          spanEndIndexExclusive: to,
          devicePixelRatio: 1,
        );

    test('a tile bakes none of a ghost\'s ink', () async {
      expect(
        await opsOf(repeated, 0, 4),
        isNotEmpty,
        reason: '⛔CONTROL: the run\'s own names are baked',
      );
      for (final (from, to) in [(4, 8), (8, 12), (12, 16), (16, 20)]) {
        expect(await opsOf(repeated, from, to), isEmpty, reason: '$from');
      }
    });

    test('over fresh tiles the row lays the ghost\'s ink once, and nothing '
        'else', () async {
      if (dllPath == null) {
        markTestSkipped('qa_engine.dll not built');
        return;
      }
      final painter = painterFor(repeated, store: store);
      const size = Size(built * 24, 28);
      painter.paint(_PaintSpy(), size);
      await tileStoreIdle(store);
      final spy = _PaintSpy();
      painter.paint(spy, size);
      expect(spy.tiles, built ~/ 4, reason: 'premise: every span is tiled');
      expect(
        spy.boxes,
        hasLength(painter.ghostInkCellsIn(0, built).length),
        reason: 'the six names and the X, and no word a tile holds',
      );
    });
  });
}

/// The words a paint sets itself, and the tiles it lays.
class _PaintSpy extends PaintedGlyphBoxes {
  int tiles = 0;

  @override
  void drawImageRect(ui.Image image, Rect src, Rect dst, Paint paint) {
    tiles += 1;
  }
}
