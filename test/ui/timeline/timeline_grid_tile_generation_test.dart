import 'dart:io';

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

import 'timeline_frame_geometry_probe.dart';

/// 🚨#29 프레임 블록 회색 깜빡임 — THE SUBSTRATE GENERATION.
///
/// A tile request captures the painter, but the painter's resolvers answer
/// from the LIVE session at drain time. The drain is serial, up to 32 deep,
/// with real async hops between rasters — so a cut switch mid-queue baked
/// the old cut's rows against the new cut's answers: a drawing shown grey,
/// stored, and served again later as a perfectly valid cache hit. And the
/// tile key carried no cut at all, so a same-id row in another cut (old
/// files written before PR #1070 carry those) could be handed this cut's
/// pixels whenever the geometry happened to match.
///
/// The generation token closes both: dead-generation requests are
/// discarded un-rastered, the generation joins the key, and — the belt —
/// the entry itself refuses to answer across generations even if the key
/// ever loses its generation segment.
///
/// ⛔The belt is load-bearing on purpose: the third test pins that
/// stale-while-revalidate WITHIN a generation still serves the old tile
/// (R26 #27 — a content edit is a new Layer instance that must find its
/// old tile), which is exactly why "different instance" alone can never
/// be the cross-generation guard.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final dllPath =
      '${Directory.current.path}\\build\\native_standalone\\Release\\qa_engine.dll';
  final available = File(dllPath).existsSync();

  TimelineCellExposureState stateFor(Layer layer, int frameIndex) {
    if (layer.timeline[frameIndex]?.isDrawing ?? false) {
      return TimelineCellExposureState.drawingStart;
    }
    if (coveringDrawingBlockAt(layer.timeline, frameIndex) != null) {
      return TimelineCellExposureState.held;
    }
    return TimelineCellExposureState.uncovered;
  }

  Layer blockLayer({String id = 'layer-a'}) => Layer(
    id: LayerId(id),
    name: 'A',
    frames: [Frame(id: const FrameId('f1'), duration: 1, strokes: const [])],
    timeline: {0: const TimelineExposure.drawing(FrameId('f1'), length: 2)},
  );

  TimelineRowCellsPainter painterFor(
    Layer layer, {
    required String generation,
    TimelineGridTileStore? store,
  }) {
    return TimelineRowCellsPainter(
      layer: layer,
      geometry: testFrameGeometry(
        frameCellExtent: 24,
        frameEndIndexExclusive: 40,
      ),
      crossAxisExtent: 28,
      exposureStateForLayer: stateFor,
      colorScheme: const ColorScheme.dark(),
      baseTextStyle: const TextStyle(fontSize: 11),
      tileStore: store,
      substrateGeneration: generation,
    );
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

  test('a request whose generation died before the drain is discarded — '
      'rastering it would consult resolvers that no longer describe its '
      'rows', () async {
    if (!available) {
      markTestSkipped('qa_engine.dll not built');
      return;
    }
    final store = TimelineGridTileStore.instance;
    var landings = 0;
    store.revision.addListener(() => landings += 1);

    // The gesture: cut A's row asks for a tile...
    expect(
      store.tileFor(
        painter: painterFor(
          blockLayer(),
          generation: 'p:cut-a',
          store: store,
        ),
        spanStartIndex: 0,
        spanEndIndexExclusive: 4,
        devicePixelRatio: 1.0,
      ),
      isNull,
    );
    // ...and the user switches cuts before the drain reaches it. The next
    // paint carries the new generation — that IS the liveness signal.
    final painterB = painterFor(
      blockLayer(id: 'layer-b'),
      generation: 'p:cut-b',
      store: store,
    );
    expect(
      store.tileFor(
        painter: painterB,
        spanStartIndex: 0,
        spanEndIndexExclusive: 4,
        devicePixelRatio: 1.0,
      ),
      isNull,
    );

    while (landings == 0) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    // Let the drain finish whatever else it would do.
    await Future<void>.delayed(const Duration(milliseconds: 25));

    expect(
      landings,
      1,
      reason: 'exactly one tile landed — the dead-generation request was '
          'discarded, not rastered',
    );
    expect(
      store.tileFor(
        painter: painterB,
        spanStartIndex: 0,
        spanEndIndexExclusive: 4,
        devicePixelRatio: 1.0,
      ),
      isNotNull,
      reason: 'the live generation landed normally',
    );
    expect(
      store.tileFor(
        painter: painterFor(
          blockLayer(),
          generation: 'p:cut-a',
          store: store,
        ),
        spanStartIndex: 0,
        spanEndIndexExclusive: 4,
        devicePixelRatio: 1.0,
      ),
      isNull,
      reason: 'nothing was stored for the dead generation',
    );
  });

  test('a same-id row in another generation is never served this '
      'generation\'s pixels — old files carry duplicate ids across cuts', () async {
    if (!available) {
      markTestSkipped('qa_engine.dll not built');
      return;
    }
    final store = TimelineGridTileStore.instance;
    var landings = 0;
    store.revision.addListener(() => landings += 1);

    final cutA = painterFor(
      blockLayer(),
      generation: 'p:cut-a',
      store: store,
    );
    store.tileFor(
      painter: cutA,
      spanStartIndex: 0,
      spanEndIndexExclusive: 4,
      devicePixelRatio: 1.0,
    );
    while (landings == 0) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(
      store.tileFor(
        painter: cutA,
        spanStartIndex: 0,
        spanEndIndexExclusive: 4,
        devicePixelRatio: 1.0,
      ),
      isNotNull,
      reason: 'sanity: cut A owns its tile',
    );

    // Same LayerId, DIFFERENT Layer instance, different content, same
    // geometry and DPR — cut B's row in a pre-PR-#1070 file. Every
    // geometry term the stale arms compare matches; only the generation
    // says these are different worlds.
    final cutB = painterFor(
      Layer(
        id: const LayerId('layer-a'),
        name: 'A in cut B',
        frames: const [],
        timeline: const {},
      ),
      generation: 'p:cut-b',
      store: store,
    );
    expect(
      store.tileFor(
        painter: cutB,
        spanStartIndex: 0,
        spanEndIndexExclusive: 4,
        devicePixelRatio: 1.0,
      ),
      isNull,
      reason: 'cut B must go cold rather than wear cut A\'s pixels — '
          'this is the arm that turned a mid-drain grey into a resident',
    );
  });

  test('stale-while-revalidate WITHIN a generation still serves the old '
      'tile — a content edit is a new instance that must find it (R26 #27)',
      () async {
    if (!available) {
      markTestSkipped('qa_engine.dll not built');
      return;
    }
    final store = TimelineGridTileStore.instance;
    var landings = 0;
    store.revision.addListener(() => landings += 1);

    store.tileFor(
      painter: painterFor(
        blockLayer(),
        generation: 'p:cut-a',
        store: store,
      ),
      spanStartIndex: 0,
      spanEndIndexExclusive: 4,
      devicePixelRatio: 1.0,
    );
    while (landings == 0) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }

    // The same row after an edit: new instance, same id, same generation,
    // same geometry. The stale arm exists exactly for this frame.
    final edited = painterFor(
      blockLayer(),
      generation: 'p:cut-a',
      store: store,
    );
    expect(
      store.tileFor(
        painter: edited,
        spanStartIndex: 0,
        spanEndIndexExclusive: 4,
        devicePixelRatio: 1.0,
      ),
      isNotNull,
      reason: 'the generation guard must not break stale-while-revalidate '
          'inside one world — dropping to the classic pass here swaps '
          'glyph technologies for a frame',
    );
  });
}
