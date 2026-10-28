/// 🚨THE 30-SECOND DEFAULT IS NOT THIS FILE'S BOUND — these cases raster
/// tiles for real and wait for the landing off-frame, as
/// `timeline_grid_tile_generation_test` does.
@Timeout(Duration(minutes: 3))
library;

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
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_tile_store.dart';
import 'package:anicel/src/ui/timeline/timeline_row_cells_painter.dart';

import '../../helpers/native_engine_path.dart';
import '../../helpers/poll_until.dart';
import 'timeline_frame_geometry_probe.dart';

/// A panel opened again builds its rows anew, and reads the theme's colour
/// scheme as a NEW instance of the same colours. The store asked whether it
/// was the SAME instance, so every tile the panel had went stale at every
/// opening and was baked again — 🔬~84 on the timeline tab and ~42 on the
/// storyboard's (10-24, frame-panels-build-in-one-frame): the same fault
/// R9 #16 took out of the resolvers.
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

  final layer = Layer(
    id: const LayerId('layer-a'),
    name: 'A',
    frames: [Frame(id: const FrameId('f1'), duration: 1, strokes: const [])],
    timeline: {0: const TimelineExposure.drawing(FrameId('f1'), length: 2)},
  );

  TimelineRowCellsPainter painterIn(ColorScheme scheme) =>
      TimelineRowCellsPainter(
        layer: layer,
        geometry: testFrameGeometry(
          frameCellExtent: 24,
          frameEndIndexExclusive: 40,
        ),
        crossAxisExtent: 28,
        exposureStateForLayer: stateFor,
        colorScheme: scheme,
        baseTextStyle: const TextStyle(fontSize: 11),
        tileStore: TimelineGridTileStore.instance,
        substrateGeneration: 'p:cut-a',
      );

  Object? ask(TimelineRowCellsPainter painter) =>
      TimelineGridTileStore.instance.tileFor(
        painter: painter,
        spanStartIndex: 0,
        spanEndIndexExclusive: 4,
        devicePixelRatio: 1.0,
      );

  /// The tile of the row baked under the dark scheme, the store idle.
  Future<Object?> bakedInTheDark() async {
    final store = TimelineGridTileStore.instance;
    var landings = 0;
    void landed() => landings += 1;
    store.revision.addListener(landed);
    addTearDown(() => store.revision.removeListener(landed));
    ask(painterIn(const ColorScheme.dark()));
    await pollUntil(() => landings > 0 && !store.debugBusy);
    expect(landings, 1, reason: 'premise: the tile landed');
    return ask(painterIn(const ColorScheme.dark()));
  }

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

  test('a scheme of the same colours, read anew, is served the tile it '
      'had — nothing is baked again', () async {
    if (!available) {
      markTestSkipped('qa_engine.dll not built');
      return;
    }
    final dark = await bakedInTheDark();
    final anew = const ColorScheme.dark().copyWith();
    expect(anew, isNot(same(const ColorScheme.dark())), reason: 'premise');
    expect(anew, const ColorScheme.dark(), reason: 'premise');

    // The tile itself, not a busy store: a look the store takes for new is
    // baked in the ask that brings it (F-314), and leaves nothing queued.
    expect(
      ask(painterIn(anew)),
      same(dark),
      reason: '↩️the store took the new instance for a new look: the tile '
          'went stale and was baked again',
    );
    expect(TimelineGridTileStore.instance.debugBusy, isFalse);
  });

  test('a scheme of other colours still bakes the tile again', () async {
    if (!available) {
      markTestSkipped('qa_engine.dll not built');
      return;
    }
    final dark = await bakedInTheDark();

    final light = ask(painterIn(const ColorScheme.light()));
    expect(light, isNotNull);
    expect(
      light,
      isNot(same(dark)),
      reason: 'the colours are baked into the tile: other colours are '
          'another look',
    );
  });
}
