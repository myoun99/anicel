/// These cases raster tiles for real and wait for the landing off-frame —
/// the same bound as `timeline_grid_tile_open_staleness_test` and for the
/// same reason (under load the 30s default dies with a bare timeout).
@Timeout(Duration(minutes: 3))
library;

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_coverage.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/native/qa_engine_abi.dart';
import 'package:anicel/src/native/qa_native_engine.dart';
import 'package:anicel/src/ui/timeline/timeline_cel_content_source.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_tile_store.dart';
import 'package:anicel/src/ui/timeline/timeline_row_cells_painter.dart';

import '../../helpers/native_engine_path.dart';
import 'timeline_frame_geometry_probe.dart';

/// F-166: the unworked-block tint's revision is ONE number for the whole
/// timeline — it bumps when the pen goes down, when it comes up, and on
/// every committed stroke. Each bump used to stale every visible tile of
/// every row, and the drain re-rastered them all, at pen-down of all
/// moments. Only the cel under the pen can have changed, so only the tile
/// whose paper changed may re-raster; the rest keep their pixels.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final dllPath = nativeEngineLibraryPathOrNull();
  final available = dllPath != null;

  TimelineCellExposureState stateFor(Layer layer, int frameIndex) {
    if (layer.timeline[frameIndex]?.isDrawing ?? false) {
      return TimelineCellExposureState.drawingStart;
    }
    if (coveringDrawingBlockAt(layer.timeline, frameIndex) != null) {
      return TimelineCellExposureState.held;
    }
    return TimelineCellExposureState.uncovered;
  }

  // Two cels, one block each: f1 over cells 0..3, f2 over cells 4..7 — so
  // each span tile [0, 4) and [4, 8) stands on a cel of its own.
  Layer twoBlockLayer(String id) => Layer(
    id: LayerId(id),
    name: id,
    frames: [
      Frame(id: const FrameId('f1'), duration: 1, strokes: const []),
      Frame(id: const FrameId('f2'), duration: 1, strokes: const []),
    ],
    timeline: {
      0: const TimelineExposure.drawing(FrameId('f1'), length: 4),
      4: const TimelineExposure.drawing(FrameId('f2'), length: 4),
    },
  );

  setUp(() {
    QaNativeEngine.debugResetForTests();
    debugQaEngineLibraryPathOverride = dllPath;
    QaNativeEngine.debugForceDartFallback = false;
    TimelineGridTileStore.instance.clear();
  });

  tearDown(() {
    QaNativeEngine.debugResetForTests();
    debugQaEngineLibraryPathOverride = null;
    QaNativeEngine.debugForceDartFallback = false;
    TimelineGridTileStore.instance.clear();
  });

  test('a bump re-rasters only the tile whose paper it changed — every '
      'other tile keeps its pixels, and a bump that changed nothing '
      're-rasters nothing', () async {
    if (!available) {
      markTestSkipped('qa_engine.dll not built');
      return;
    }
    final store = TimelineGridTileStore.instance;
    var landings = 0;
    store.revision.addListener(() => landings += 1);
    // Idle is the store's word, not a timer's ([debugBusy]): a slow drain
    // on a loaded machine must not read as a finished one.
    Future<void> waitIdle() async {
      final deadline = DateTime.now().add(const Duration(seconds: 30));
      await Future<void>.delayed(Duration.zero);
      while (store.debugBusy) {
        if (DateTime.now().isAfter(deadline)) {
          fail('timed out waiting for the drain (have $landings landings)');
        }
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    }

    // The session's shape: a fact per cel and ONE revision for all of
    // them. Every cel starts drawn.
    final drawn = <(String, String), bool>{};
    final revision = ValueNotifier<int>(0);
    final celContent = TimelineCelContentSource(
      hasContent: (layer, frameIndex) =>
          drawn[(layer.id.value, frameIndex < 4 ? 'f1' : 'f2')] ?? true,
      revision: revision,
    );
    TimelineRowCellsPainter painterFor(Layer layer) => TimelineRowCellsPainter(
      layer: layer,
      geometry: testFrameGeometry(
        frameCellExtent: 24,
        frameEndIndexExclusive: 40,
      ),
      crossAxisExtent: 28,
      exposureStateForLayer: stateFor,
      celContent: celContent,
      colorScheme: const ColorScheme.dark(),
      baseTextStyle: const TextStyle(fontSize: 11),
      tileStore: store,
      substrateGeneration: 'p:cut',
    );
    final rows = [
      painterFor(twoBlockLayer('a')),
      painterFor(twoBlockLayer('b')),
    ];
    const spans = [(0, 4), (4, 8)];

    // Every tile, as the rows ask for them on a paint: (row, span) → image.
    Map<(int, int), Object?> paint() => {
      for (var row = 0; row < rows.length; row += 1)
        for (var span = 0; span < spans.length; span += 1)
          (row, span): store.tileFor(
            painter: rows[row],
            spanStartIndex: spans[span].$1,
            spanEndIndexExclusive: spans[span].$2,
            devicePixelRatio: 1.0,
          ),
    };

    expect(paint().values, everyElement(isNull), reason: 'all cold');
    await waitIdle();
    expect(landings, 4);
    final warm = paint();
    expect(warm.values, everyElement(isNotNull));

    // ① The pen goes down on a cel that is already drawn: the revision
    // moves, no answer does.
    revision.value += 1;
    final afterEmptyBump = paint();
    for (final key in warm.keys) {
      expect(
        identical(afterEmptyBump[key], warm[key]),
        isTrue,
        reason: 'tile $key: nothing it shows changed',
      );
    }
    await waitIdle();
    expect(landings, 4, reason: 'a bump that changed no paper rasters none');

    // ② Row a's f1 goes empty — its block turns grey — and nothing else.
    drawn[('a', 'f1')] = false;
    revision.value += 1;
    final afterFlip = paint();
    for (final key in warm.keys.where((key) => key != (0, 0))) {
      expect(
        identical(afterFlip[key], warm[key]),
        isTrue,
        reason: 'tile $key: its paper did not change',
      );
    }
    await waitIdle();
    expect(landings, 5, reason: 'exactly the one tile whose paper changed');
    final healed = paint();
    expect(
      identical(healed[(0, 0)], warm[(0, 0)]),
      isFalse,
      reason: 'row a, cells 0..3: re-rastered with the grey paper',
    );
    for (final key in warm.keys.where((key) => key != (0, 0))) {
      expect(identical(healed[key], warm[key]), isTrue);
    }
  });
}
