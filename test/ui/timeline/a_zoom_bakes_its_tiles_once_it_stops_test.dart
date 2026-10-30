import 'dart:ui' as ui;

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

/// 🗣️A zoom's tiles are rastered once it stops (유저 2026-10-30,
/// zoom-step-lays-out-five-times-the-07-25-count-Q1: 「줌이 멈출 때까지
/// 늘린 옛 타일만 보여 준다」): every step shows the old tile scaled (R27 #10)
/// and rasters nothing; once the zoom stands still, each span it stretched
/// is rastered once, at the extent it stopped at. Past twice the old
/// tile's extent a step is rastered then, as before.
///
/// ↩️Each step queued every shown span at its own extent: ~145 tiles a step
/// on S5_BA's cut 352, rastered in the frames after it and thrown away by
/// the next step.
///
/// The stop waits [TimelineGridTileStore.debugZoomSettles]: two seconds
/// where the zoom has to stop, an hour where it must not have to — a
/// loaded machine stretches the steps' gaps, never by that much.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final dllPath = nativeEngineLibraryPathOrNull();
  final store = TimelineGridTileStore.instance;
  var landings = 0;
  void landed() => landings += 1;

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

  TimelineRowCellsPainter at(double extent, {Layer? of}) =>
      TimelineRowCellsPainter(
        layer: of ?? layer,
        geometry: testFrameGeometry(
          frameCellExtent: extent,
          frameEndIndexExclusive: 40,
        ),
        crossAxisExtent: 28,
        exposureStateForLayer: stateFor,
        colorScheme: const ColorScheme.dark(),
        baseTextStyle: const TextStyle(fontSize: 11),
        tileStore: store,
      );

  /// The tile of the span from [start] four cells long, its cells [extent].
  ui.Image? ask(double extent, {int start = 0}) => store.tileFor(
    painter: at(extent),
    spanStartIndex: start,
    spanEndIndexExclusive: start + 4,
    devicePixelRatio: 2.0,
  );

  /// The span from [start], baked at [extent] — the tiles a zoom stretches.
  Future<ui.Image> baked(double extent, {int start = 0}) async {
    final before = landings;
    expect(ask(extent, start: start), isNull, reason: '⛔전제: a cold span');
    expect(await pollUntil(() => landings > before), isTrue);
    return ask(extent, start: start)!;
  }

  /// Lets the store's drain and warm-ups run a while, short of any stop.
  Future<void> aWhile() =>
      Future<void>.delayed(const Duration(milliseconds: 300));

  /// Whether this machine has no engine to raster with — the case is
  /// skipped, said as such.
  bool skipped() {
    if (dllPath != null) {
      return false;
    }
    markTestSkipped('qa_engine.dll not built');
    return true;
  }

  setUp(() {
    QaNativeEngine.debugResetForTests();
    debugQaEngineLibraryPathOverride = dllPath;
    QaNativeEngine.debugForceDartFallback = false;
    store.clear();
    store.revision.addListener(landed);
    landings = 0;
  });

  tearDown(() {
    store.revision.removeListener(landed);
    store.debugZoomSettles = TimelineGridTileStore.zoomSettles;
    QaNativeEngine.debugResetForTests();
    debugQaEngineLibraryPathOverride = null;
    QaNativeEngine.debugForceDartFallback = false;
    store.clear();
  });

  test('a zoom\'s steps show the old tile and raster nothing; stopped, the '
      'span is rastered once at the extent it stopped at', () async {
    if (skipped()) {
      return;
    }
    store.debugZoomSettles = const Duration(seconds: 2);
    final old = await baked(24);

    for (final extent in [20.0, 16.0, 14.0, 12.0]) {
      expect(ask(extent), same(old), reason: 'the old tile, scaled');
    }
    await aWhile();
    expect(landings, 1, reason: 'nothing rastered at a step\'s extent');
    expect(store.debugBusy, isTrue, reason: 'the span waits for the stop');

    expect(await pollUntil(() => landings == 2), isTrue);
    final crisp = ask(12);
    expect(crisp, isNot(same(old)));
    expect(crisp!.width, 4 * 12 * 2, reason: 'at the extent it stopped at');
    await aWhile();
    expect(landings, 2, reason: 'once');
  });

  test('past twice the old tile\'s extent a step is rastered then', () async {
    if (skipped()) {
      return;
    }
    store.debugZoomSettles = const Duration(hours: 1);
    await baked(24);

    expect(ask(10), isNull, reason: 'the classic paint covers the step');
    expect(await pollUntil(() => landings == 2), isTrue);
    expect(ask(10)!.width, 4 * 10 * 2);
  });

  test('a span a zoom left waiting and a jump then took past twice is '
      'rastered at the jump, and not again when the zoom stops', () async {
    if (skipped()) {
      return;
    }
    store.debugZoomSettles = const Duration(seconds: 2);
    await baked(24);

    ask(16);
    expect(ask(10), isNull);
    expect(await pollUntil(() => landings == 2), isTrue);
    await Future<void>.delayed(const Duration(seconds: 3));
    expect(landings, 2, reason: 'the stop finds nothing waiting');
    expect(ask(10)!.width, 4 * 10 * 2, reason: 'the jump\'s tile stays');
  });

  test('a zoom that comes back to the tile\'s extent stretches it no more '
      '— the stop rasters nothing', () async {
    if (skipped()) {
      return;
    }
    store.debugZoomSettles = const Duration(seconds: 2);
    final old = await baked(24);

    ask(16);
    expect(ask(24), same(old), reason: 'the tile shows its extent again');
    await Future<void>.delayed(const Duration(seconds: 3));
    expect(landings, 1);
    expect(ask(24), same(old), reason: 'it was not rastered over');
  });

  test('once the zoom stopped, a span it did not reach is asked at the '
      'extent it stopped at as any other', () async {
    if (skipped()) {
      return;
    }
    store.debugZoomSettles = const Duration(seconds: 2);
    await baked(24);
    await baked(24, start: 4);
    ask(16);
    ask(12);
    expect(await pollUntil(() => landings == 3), isTrue);

    store.debugZoomSettles = const Duration(hours: 1);
    expect(ask(12, start: 4), isNotNull, reason: 'its old tile, scaled');
    expect(await pollUntil(() => landings == 4), isTrue);
    expect(ask(12, start: 4)!.width, 4 * 12 * 2);
  });

  test('a warm-up waits for the zoom too — and what a step asked of it at '
      'another extent is let go', () async {
    if (skipped()) {
      return;
    }
    store.debugZoomSettles = const Duration(seconds: 2);
    await baked(24);

    ask(20);
    store.warmAhead(
      painter: at(20),
      spanStartIndex: 4,
      spanEndIndexExclusive: 8,
      devicePixelRatio: 2.0,
    );
    ask(16);
    await aWhile();
    expect(landings, 1, reason: 'the warm-up waits for the stop');

    expect(await pollUntil(() => landings == 2), isTrue);
    await aWhile();
    expect(
      landings,
      2,
      reason: 'the span past the edge was asked at a step\'s extent',
    );
  });

  test('a span a step stretched and the last step did not ask for is let '
      'go at the stop, not rastered at that step\'s extent', () async {
    if (skipped()) {
      return;
    }
    store.debugZoomSettles = const Duration(seconds: 2);
    await baked(24);
    await baked(24, start: 4);

    ask(16);
    ask(16, start: 4);
    ask(12);
    expect(await pollUntil(() => landings == 3), isTrue);
    await aWhile();
    expect(landings, 3, reason: 'the span left behind at 16 is let go');
  });

  test('a span waiting for the stop is not warmed beside it', () async {
    if (skipped()) {
      return;
    }
    store.debugZoomSettles = const Duration(seconds: 2);
    await baked(24);

    ask(16);
    store.warmAhead(
      painter: at(16),
      spanStartIndex: 0,
      spanEndIndexExclusive: 4,
      devicePixelRatio: 2.0,
    );
    expect(await pollUntil(() => landings == 2), isTrue);
    await aWhile();
    expect(landings, 2, reason: 'rastered once, for the stop');
  });

  test('a span the zoom came back to with an edit is baked in that ask, '
      'and not rastered over at the stop', () async {
    if (skipped()) {
      return;
    }
    store.debugZoomSettles = const Duration(seconds: 2);
    await baked(24);

    ask(16);
    final edited = Layer(
      id: layer.id,
      name: layer.name,
      frames: layer.frames,
      timeline: {0: const TimelineExposure.drawing(FrameId('f1'), length: 3)},
    );
    store.tileFor(
      painter: at(24, of: edited),
      spanStartIndex: 0,
      spanEndIndexExclusive: 4,
      devicePixelRatio: 2.0,
    );
    expect(landings, 2, reason: '⛔전제: the edit is baked in its ask');
    await Future<void>.delayed(const Duration(seconds: 3));
    expect(landings, 2, reason: 'the stop finds nothing waiting');
  });

  test('a clear lets go of a zoom under way and of where the cells stood '
      'still', () async {
    if (skipped()) {
      return;
    }
    store.debugZoomSettles = const Duration(seconds: 2);
    await baked(24);
    ask(16);
    expect(await pollUntil(() => landings == 2), isTrue);
    ask(20);

    store.clear();
    expect(store.debugBusy, isFalse, reason: 'nothing waits past a clear');
    store.debugZoomSettles = const Duration(hours: 1);
    await baked(24);
    ask(16);
    await Future<void>.delayed(const Duration(seconds: 3));
    expect(
      landings,
      3,
      reason: 'a zoom to 16 begun afresh waits, and no stop from before '
          'the clear ends it',
    );
  });

  test('a zoom begun after a clear stops as any other', () async {
    if (skipped()) {
      return;
    }
    store.debugZoomSettles = const Duration(seconds: 2);
    await baked(24);
    ask(20);

    store.clear();
    await baked(24);
    ask(20);
    expect(await pollUntil(() => landings == 3), isTrue);
  });

  test('a span queued at a jump and stretched by the next step waits for '
      'the stop — the jump\'s raster is not made', () async {
    if (skipped()) {
      return;
    }
    store.debugZoomSettles = const Duration(seconds: 2);
    await baked(24);

    expect(ask(10), isNull, reason: '⛔전제: queued, past twice');
    ask(16);
    expect(await pollUntil(() => landings == 2), isTrue);
    await Future<void>.delayed(const Duration(seconds: 3));
    expect(landings, 2, reason: 'one raster, at the stop');
    expect(ask(16)!.width, 4 * 16 * 2);
  });

  test('each step puts the stop off — a zoom that goes on is not stopped '
      'by the time since its first step', () async {
    if (skipped()) {
      return;
    }
    store.debugZoomSettles = const Duration(seconds: 4);
    await baked(24);

    ask(20);
    await Future<void>.delayed(const Duration(seconds: 3));
    ask(16);
    await Future<void>.delayed(const Duration(seconds: 2));
    expect(landings, 1, reason: 'four seconds have not passed since a step');
    expect(await pollUntil(() => landings == 2), isTrue);
    expect(ask(16)!.width, 4 * 16 * 2);
  });

  test('a zoom that came back stands where its paint last asked — a '
      'warm-up a step asked is let go', () async {
    if (skipped()) {
      return;
    }
    store.debugZoomSettles = const Duration(seconds: 2);
    final old = await baked(24);

    ask(16);
    store.warmAhead(
      painter: at(16),
      spanStartIndex: 4,
      spanEndIndexExclusive: 8,
      devicePixelRatio: 2.0,
    );
    await aWhile();
    expect(ask(24), same(old));
    await Future<void>.delayed(const Duration(seconds: 3));
    expect(landings, 1, reason: 'the span past the edge was asked at 16');
  });

  test('a warm-up the zoom held goes on when it stops, though nothing it '
      'stretched is left to raster', () async {
    if (skipped()) {
      return;
    }
    store.debugZoomSettles = const Duration(seconds: 2);
    await baked(24);
    await baked(12, start: 4);

    ask(16);
    store.warmAhead(
      painter: at(12),
      spanStartIndex: 8,
      spanEndIndexExclusive: 12,
      devicePixelRatio: 2.0,
    );
    await aWhile();
    expect(landings, 2, reason: '⛔전제: the warm-up waits for the stop');
    expect(ask(12, start: 4), isNotNull, reason: 'the row stands at 12');
    expect(await pollUntil(() => landings == 3), isTrue);
  });

  test('a second zoom after one that came back stops as any other', () async {
    if (skipped()) {
      return;
    }
    store.debugZoomSettles = const Duration(seconds: 2);
    final old = await baked(24);
    ask(16);
    expect(ask(24), same(old));
    await Future<void>.delayed(const Duration(seconds: 3));

    ask(16);
    expect(await pollUntil(() => landings == 2), isTrue);
    expect(ask(16)!.width, 4 * 16 * 2);
  });

  test('another row\'s warm-up is not let go at this row\'s stop', () async {
    if (skipped()) {
      return;
    }
    store.debugZoomSettles = const Duration(seconds: 2);
    await baked(24);

    ask(16);
    store.warmAhead(
      painter: at(
        24,
        of: Layer(
          id: const LayerId('layer-b'),
          name: 'B',
          frames: layer.frames,
          timeline: layer.timeline,
        ),
      ),
      spanStartIndex: 0,
      spanEndIndexExclusive: 4,
      devicePixelRatio: 2.0,
    );
    expect(await pollUntil(() => landings == 3), isTrue);
  });
}
