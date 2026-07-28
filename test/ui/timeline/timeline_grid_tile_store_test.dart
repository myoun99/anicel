import 'dart:io';
import 'dart:typed_data';
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
import 'package:anicel/src/ui/timeline/timeline_grid_tile_ops.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_tile_store.dart';
import 'package:anicel/src/ui/timeline/timeline_row_cells_painter.dart';

import 'timeline_frame_geometry_probe.dart';

/// UI-R18 O7 T2: the substrate tile store — engine-gated stand-down,
/// probe-driven op emission, tile landing + look-identity invalidation.
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

  Layer blockLayer() => Layer(
    id: const LayerId('layer-a'),
    name: 'A',
    frames: [Frame(id: const FrameId('f1'), duration: 1, strokes: const [])],
    timeline: {0: const TimelineExposure.drawing(FrameId('f1'), length: 2)},
  );

  TimelineRowCellsPainter painterFor(
    Layer layer, {
    TimelineGridTileStore? store,
    TextStyle baseTextStyle = const TextStyle(fontSize: 11),
  }) {
    return TimelineRowCellsPainter(
      layer: layer,
      playbackFrameCount: 24,
      geometry: testFrameGeometry(
        frameCellExtent: 24,
        frameEndIndexExclusive: 40,
      ),
      crossAxisExtent: 28,
      exposureStateForLayer: stateFor,
      colorScheme: const ColorScheme.dark(),
      baseTextStyle: baseTextStyle,
      tileStore: store,
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

  test('WITHOUT the native engine the store stands down entirely — the '
      'classic paint path stays byte-for-byte (the suite-wide default)', () {
    QaNativeEngine.debugForceDartFallback = true;
    final store = TimelineGridTileStore.instance;
    final revisionBefore = store.revision.value;

    final image = store.tileFor(
      painter: painterFor(blockLayer()),
      spanStartIndex: 0,
      spanEndIndexExclusive: 4,
      devicePixelRatio: 1.0,
    );

    expect(image, isNull);
    expect(store.revision.value, revisionBefore);
  });

  test('the emitter probes the painter: the covered span opens with the '
      'block fill and its border, the empty span emits nothing', () {
    final painter = painterFor(blockLayer());
    final covered = timelineGridSubstrateOps(
      painter: painter,
      spanStartIndex: 0,
      spanEndIndexExclusive: 4,
      devicePixelRatio: 1.0,
    );
    expect(covered, isNotEmpty);
    expect(covered[0], TimelineGridTileOp.rrectFill);
    // The block START cell rounds its LEFT corners only (the painter's
    // radius map, mask TL|BL = 5).
    expect(covered[6], 5, reason: 'corner mask');
    expect(covered[5], timelineGridQ8(6), reason: 'radius 6 in q8');

    // Uncovered cells emit NOTHING (UI-R21 #2): empties are transparent
    // — the row underlay owns the paper, so an empty span is zero ops
    // and the tile stays fully transparent there.
    final empty = timelineGridSubstrateOps(
      painter: painter,
      spanStartIndex: 8,
      spanEndIndexExclusive: 12,
      devicePixelRatio: 1.0,
    );
    expect(empty, isEmpty);
  });

  test('T3: tiles carry the FOREGROUND ink too — the drawing cell\'s ○ '
      'glyph shows up as a strong delta over the substrate alone', () async {
    if (!available) {
      markTestSkipped('qa_engine.dll not built');
      return;
    }
    final store = TimelineGridTileStore.instance;
    final layer = blockLayer();
    final painter = painterFor(layer, store: store);

    var landings = 0;
    store.revision.addListener(() => landings += 1);
    expect(
      store.tileFor(
        painter: painter,
        spanStartIndex: 0,
        spanEndIndexExclusive: 4,
        devicePixelRatio: 1.0,
      ),
      isNull,
    );
    while (landings == 0) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    final image = store.tileFor(
      painter: painter,
      spanStartIndex: 0,
      spanEndIndexExclusive: 4,
      devicePixelRatio: 1.0,
    );
    expect(image, isNotNull);
    final tileData = await image!.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    final tileBytes = tileData!.buffer.asUint8List();

    final substrate = Uint8List(image.width * image.height * 4);
    expect(
      QaNativeEngine.instance!.gridRasterTileBytes(
        pixels: substrate,
        tileWidth: image.width,
        tileHeight: image.height,
        backgroundRgba: 0,
        ops: timelineGridSubstrateOps(
          painter: painter,
          spanStartIndex: 0,
          spanEndIndexExclusive: 4,
          devicePixelRatio: 1.0,
        ),
      ),
      0,
    );

    // Cell 0 holds the drawing's ○ glyph: dark ink on the paper block —
    // somewhere in that cell the delta must be strong (conversion noise
    // is ±1 per channel; ink is tens of levels).
    var maxDelta = 0;
    for (var y = 0; y < image.height; y += 1) {
      for (var x = 0; x < 24; x += 1) {
        final base = (y * image.width + x) * 4;
        for (var channel = 0; channel < 3; channel += 1) {
          final delta = (tileBytes[base + channel] - substrate[base + channel])
              .abs();
          if (delta > maxDelta) {
            maxDelta = delta;
          }
        }
      }
    }
    expect(
      maxDelta,
      greaterThan(64),
      reason: 'the glyph must be baked into the tile',
    );
  });

  test('a cold span rasters off-frame, lands as a physical-resolution '
      'image, and a changed LOOK invalidates it', () async {
    if (!available) {
      markTestSkipped('qa_engine.dll not built');
      return;
    }
    final store = TimelineGridTileStore.instance;
    final layer = blockLayer();
    final painter = painterFor(layer, store: store);

    var landings = 0;
    store.revision.addListener(() => landings += 1);

    // Cold: null now, raster scheduled.
    expect(
      store.tileFor(
        painter: painter,
        spanStartIndex: 0,
        spanEndIndexExclusive: 4,
        devicePixelRatio: 2.0,
      ),
      isNull,
    );
    while (landings == 0) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }

    final image = store.tileFor(
      painter: painter,
      spanStartIndex: 0,
      spanEndIndexExclusive: 4,
      devicePixelRatio: 2.0,
    );
    expect(image, isNotNull);
    expect(image!.width, 4 * 24 * 2, reason: 'span cells × extent × DPR');
    expect(image.height, 28 * 2);

    // The SAME look stays a hit (no new landing).
    final hits = landings;
    store.tileFor(
      painter: painter,
      spanStartIndex: 0,
      spanEndIndexExclusive: 4,
      devicePixelRatio: 2.0,
    );
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(landings, hits);

    // A LOOK-only change (the base text style here) keeps showing the
    // STALE tile while the fresh raster lands (UI-R20 #6: no
    // classic-pass flicker) — same content, different look. The ACTIVE
    // flag is no such lever anymore: it left the raster entirely
    // (UI-R21 #2, the row underlay owns the wash), so activation is a
    // guaranteed tile HIT by construction.
    final stylePainter = painterFor(
      layer,
      store: store,
      baseTextStyle: const TextStyle(fontSize: 12),
    );
    expect(
      store.tileFor(
        painter: stylePainter,
        spanStartIndex: 0,
        spanEndIndexExclusive: 4,
        devicePixelRatio: 2.0,
      ),
      same(image),
      reason: 'stale-while-revalidate for look-only changes',
    );
    while (landings == hits) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    final fresh = store.tileFor(
      painter: stylePainter,
      spanStartIndex: 0,
      spanEndIndexExclusive: 4,
      devicePixelRatio: 2.0,
    );
    expect(fresh, isNotNull);
    expect(identical(fresh, image), isFalse, reason: 'the re-raster landed');

    // A CONTENT change (new layer instance) ALSO holds the stale tile
    // while the fresh raster lands (R26 #27): dropping to the classic
    // pass swapped text rendering for a frame and read as every glyph
    // thinning/thickening. The re-raster still happens — the fresh
    // image must land and replace the held one.
    final beforeEdit = landings;
    final editedPainter = painterFor(blockLayer(), store: store);
    expect(
      store.tileFor(
        painter: editedPainter,
        spanStartIndex: 0,
        spanEndIndexExclusive: 4,
        devicePixelRatio: 2.0,
      ),
      same(fresh),
      reason: 'R26 #27: stale-while-revalidate covers content edits too',
    );
    while (landings == beforeEdit) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    final reRastered = store.tileFor(
      painter: editedPainter,
      spanStartIndex: 0,
      spanEndIndexExclusive: 4,
      devicePixelRatio: 2.0,
    );
    expect(reRastered, isNotNull);
    expect(
      identical(reRastered, fresh),
      isFalse,
      reason: 'the content re-raster landed',
    );

    // R27 #10: a ZOOM step re-geometries every visible tile at once, and
    // dropping them all to the classic pass is what made zooming crawl.
    // The tile covers the SAME frames and the painter draws it into a
    // dst rect built from the CURRENT geometry, so the stale raster
    // simply scales while the fresh one lands.
    TimelineRowCellsPainter zoomedTo(double extent) => TimelineRowCellsPainter(
      layer: editedPainter.layer,
      playbackFrameCount: 24,
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

    expect(
      store.tileFor(
        painter: zoomedTo(12),
        spanStartIndex: 0,
        spanEndIndexExclusive: 4,
        devicePixelRatio: 2.0,
      ),
      isNotNull,
      reason: 'a 2× zoom step keeps showing the stale tile, scaled',
    );

    // Bounded, though: an extreme jump would show mush, so that still
    // takes the crisp classic path.
    expect(
      store.tileFor(
        painter: zoomedTo(4),
        spanStartIndex: 0,
        spanEndIndexExclusive: 4,
        devicePixelRatio: 2.0,
      ),
      isNull,
      reason: 'past the rescale band the classic paint takes over',
    );
  });
}
