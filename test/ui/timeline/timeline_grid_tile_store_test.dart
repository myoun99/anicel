/// 🚨THE 30-SECOND DEFAULT IS NOT THIS FILE'S BOUND (2026-09-16).
///
/// These cases raster tiles for real and wait for the landing off-frame.
/// Alone they are slow but green; under load — another lane gating on the
/// same machine — they cross the test package's DEFAULT 30s and die with a
/// bare `TimeoutException` that says nothing about what was being waited
/// for. Three landings lost a cycle to that in one evening (i22a, f95,
/// f101), each time with the product perfectly green on the re-run.
///
/// ⛔This is not 「상한을 올려 숨긴다」. The default was never chosen for a
/// rasterising test; the real bound is stated here, and the COST itself —
/// 4m27s for three cases, measured — stays open as its own round
/// (`tile-count-timeout-under-load`).
@Timeout(Duration(minutes: 3))
library;

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

import '../../helpers/native_engine_path.dart';
import 'timeline_frame_geometry_probe.dart';

/// UI-R18 O7 T2: the substrate tile store — engine-gated stand-down,
/// probe-driven op emission, tile landing + look-identity invalidation.
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
    Color? paperGround,
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
      baseTextStyle: baseTextStyle,
      tileStore: store,
      paperGround: paperGround,
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

  // ⚠️CONTRACT CHANGED TWICE. D32/D38 (2026-08-18) took the per-cell border
  // stroke out of the substrate and put the painter's seams in as plain
  // rect fills; I-44 (2026-09-24, 「합친다 — 그리드 한 장」) took the seams
  // out too — every line is the grid sheet's, under the row — so the
  // stream is the paper and nothing else.
  test('the emitter probes the painter: every papered cell is ONE fill at '
      'its paper box, and an EMPTY span emits nothing', () {
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
    // No border strokes anywhere in the stream — every op is a fill, so
    // the stream walks in rrectFill strides of 8.
    for (var i = 0; i < covered.length; i += 8) {
      expect(
        covered[i],
        TimelineGridTileOp.rrectFill,
        reason: 'no border strokes in the substrate any more',
      );
    }
    // 🚨AND EVERY CELL GETS ITS OWN BOX. Emitting the SPAN-START cell's
    // rect for all four frames left this test green (a mutation,
    // 2026-09-07): the assertions above read the op KIND and the first
    // cell's corners, so a tile that stacked four fills on cell 0 and left
    // three cells blank passed. The probe-the-painter rule is about the
    // geometry, so the geometry is what gets named — the PAPER box, short
    // of the row seam the sheet draws under the row (I-44).
    final origin = painter.cellRectFor(0);
    final originMainCovered = painter.axis == Axis.horizontal
        ? origin.left
        : origin.top;
    bool streamHasFillAt(Int32List ops, Rect local) {
      for (var i = 0; i < ops.length; i += 8) {
        if (ops[i] == TimelineGridTileOp.rrectFill &&
            ops[i + 1] == timelineGridQ8(local.left) &&
            ops[i + 2] == timelineGridQ8(local.top) &&
            ops[i + 3] == timelineGridQ8(local.width) &&
            ops[i + 4] == timelineGridQ8(local.height)) {
          return true;
        }
      }
      return false;
    }

    var papered = 0;
    for (var frame = 0; frame < 4; frame += 1) {
      final paper = painter.paperRectFor(frame);
      final local = painter.axis == Axis.horizontal
          ? paper.shift(Offset(-originMainCovered, 0))
          : paper.shift(Offset(0, -originMainCovered));
      final hasPaper = painter.resolvedCellStyleFor(frame).background.a > 0;
      if (hasPaper) {
        papered += 1;
      }
      expect(
        streamHasFillAt(covered, local),
        hasPaper,
        reason:
            'frame $frame: a cell with paper owes the stream a fill at ITS '
            'own paper box, and one without owes none',
      );
    }
    expect(papered, greaterThan(0), reason: 'fixture premise: a block');
    expect(
      covered.length,
      papered * 8,
      reason: 'one fill per papered cell and NOTHING more — a line on the '
          'paper would be an op of its own (「블록에 존재하는 그리드선만 싹 '
          '삭제」)',
    );

    // 🚨D43-2 재개 (유저 2026-08-22): 「아직도 레이어행에만 그리드 없거든?」.
    // This assertion once read `isEmpty` and that WAS the bug: the painter
    // drew the empty cells' lines and the emitter dropped them, so the
    // tiled rows went blank. It reads `isEmpty` again for the opposite
    // reason — no row draws a line at all now, the sheet under the rows
    // does (I-44), so an empty cell has nothing left to bake.
    const emptyStart = 8;
    const emptyEndExclusive = 12;
    for (var frame = emptyStart; frame < emptyEndExclusive; frame += 1) {
      expect(
        painter.resolvedCellStyleFor(frame).background.a,
        0,
        reason: 'fixture premise: frame $frame really is empty paper',
      );
    }
    final empty = timelineGridSubstrateOps(
      painter: painter,
      spanStartIndex: emptyStart,
      spanEndIndexExclusive: emptyEndExclusive,
      devicePixelRatio: 1.0,
    );
    expect(empty, isEmpty);
  });

  test('T3: tiles carry the FOREGROUND ink too — the drawing cell\'s mark '
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
    // flag is no such lever anymore: it left the raster entirely (UI-R21
    // #2; the grid sheet paints the wash since I-44), so activation is a
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

  // I-44: what the unworked paper is pre-blended onto is baked into the
  // tile, so a changed paper ground is a changed LOOK — it re-rasters,
  // showing the stale tile while it does.
  test('I-44: the paper\'s ground is part of the look — a new one '
      're-rasters the tile', () async {
    if (!available) {
      markTestSkipped('qa_engine.dll not built');
      return;
    }
    final store = TimelineGridTileStore.instance;
    final layer = blockLayer();
    ui.Image? tile(TimelineRowCellsPainter painter) => store.tileFor(
      painter: painter,
      spanStartIndex: 0,
      spanEndIndexExclusive: 4,
      devicePixelRatio: 2.0,
    );

    // Waited for by what lands, not by a landing count: a raster the last
    // test left in flight can bump the revision first.
    final plain = painterFor(layer, store: store);
    expect(tile(plain), isNull, reason: 'cold');
    var first = tile(plain);
    while (first == null) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      first = tile(plain);
    }

    final grounded = painterFor(
      layer,
      store: store,
      paperGround: const Color(0xFF202020),
    );
    expect(
      tile(grounded),
      same(first),
      reason: 'stale-while-revalidate for a new paper ground too',
    );
    while (identical(tile(grounded), first)) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(
      tile(grounded),
      isNotNull,
      reason: 'the paper\'s ground is part of the look the tile keys on — '
          'a fresh raster landed for it',
    );
  });
}
