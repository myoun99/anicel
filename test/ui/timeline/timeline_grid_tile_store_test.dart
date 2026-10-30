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

import 'package:flutter/foundation.dart' show ValueListenable;
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
import 'package:anicel/src/ui/timeline/timeline_frame_window.dart'
    show timelineFrameWindowSpanFor;
import 'package:anicel/src/ui/timeline/timeline_row_cells_painter.dart';

import '../../helpers/census_where_textures_are_ram.dart';
import '../../helpers/native_engine_path.dart';
import '../../helpers/poll_until.dart';
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
    bool blockFrameLines = false,
    InbetweenMark unnamedMark = defaultUnnamedDrawingMark,
    int framesPerSecond = 0,
    bool shown = true,
    ValueListenable<int>? windowBucket,
    double viewportMainExtent = 0,
    int? Function(int frame)? stepsUntilShown,
  }) {
    return TimelineRowCellsPainter(
      layer: layer,
      geometry: testFrameGeometry(
        frameCellExtent: 24,
        frameEndIndexExclusive: 40,
        viewExtentPx: viewportMainExtent,
      ),
      crossAxisExtent: 28,
      exposureStateForLayer: stateFor,
      colorScheme: const ColorScheme.dark(),
      baseTextStyle: baseTextStyle,
      windowBucket: windowBucket,
      stepsUntilShown: stepsUntilShown,
      tileStore: store,
      paperGround: paperGround,
      blockFrameLines: blockFrameLines,
      unnamedMark: unnamedMark,
      framesPerSecond: framesPerSecond,
      shown: shown,
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

  // ⚠️CONTRACT CHANGED THREE TIMES. D32/D38 (2026-08-18) took the per-cell
  // border stroke out of the substrate and put the painter's seams in as
  // plain rect fills; I-44 (2026-09-24, 「합친다 — 그리드 한 장」) took the
  // seams out too; and the block-frame-lines switch (유저 2026-09-24) made
  // the lines the user's choice again and the paper ONE piece per block.
  // What stays is the rule: the emitter decides nothing — it bakes what the
  // painter answers ([TimelineRowCellsPainter.substrateIn]).
  test('the emitter bakes what the painter answers: a block is ONE piece, '
      'and an EMPTY span emits nothing', () {
    final painter = painterFor(blockLayer());
    final substrate = painter.substrateIn(0, 4);
    expect(
      substrate.paper,
      hasLength(1),
      reason: 'a two-frame block is one piece of paper, not a fill per cell',
    );
    expect(
      substrate.paper.single.rect,
      painter.paperRectFor(0).expandToInclude(painter.paperRectFor(1)),
    );
    final covered = timelineGridSubstrateOps(
      painter: painter,
      spanStartIndex: 0,
      spanEndIndexExclusive: 4,
      devicePixelRatio: 1.0,
    );
    // Rastered, the stream is that piece and nothing more: the field's own
    // fill of the piece gives the same pixels.
    final radius = substrate.paper.single.radius!;
    final field = TimelineGridTileOpWriter()
      ..rrectFill(
        substrate.paper.single.rect.left,
        substrate.paper.single.rect.top,
        substrate.paper.single.rect.width,
        substrate.paper.single.rect.height,
        radius.topLeft.x,
        TimelineGridTileOp.cornerTopLeft |
            TimelineGridTileOp.cornerTopRight |
            TimelineGridTileOp.cornerBottomLeft |
            TimelineGridTileOp.cornerBottomRight,
        timelineGridPackRgba(substrate.paper.single.color),
      );
    Uint8List raster(Int32List ops) {
      final pixels = Uint8List(4 * 24 * 28 * 4);
      expect(
        timelineGridRasterTileReference(
          pixels: pixels,
          tileWidth: 4 * 24,
          tileHeight: 28,
          backgroundRgba: 0,
          ops: ops,
        ),
        0,
      );
      return pixels;
    }

    expect(raster(covered), equals(raster(field.build())));

    // 🚨D43-2 재개 (유저 2026-08-22): 「아직도 레이어행에만 그리드 없거든?」.
    // This assertion once read `isEmpty` and that WAS the bug: the painter
    // drew the empty cells' lines and the emitter dropped them, so the
    // tiled rows went blank. It reads `isEmpty` again for the opposite
    // reason — no row draws a line on its ground, the sheet under the rows
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

  // 🗣️F-208 (유저 2026-09-29, Android): 「블록 선 표시 제거 활성화했는데
  // 6콤마에 한번 세로선 존재. 줌 할때마다 위치바뀜」. A tile is as many
  // pixels as its span's length rounds UP to, so at a fractional device
  // pixel ratio the span ends inside the tile's last pixel — and paper that
  // stopped there left that pixel part-covered: a line of ground at every
  // tile's end, wherever the zoom put the tile edges.
  test('a block running on past its tile covers the tile to its last '
      'pixel — and stops at the row\'s last frame', () {
    const cell = 17.0;
    const span = 6;
    final layer = Layer(
      id: const LayerId('layer-long'),
      name: 'L',
      frames: [Frame(id: const FrameId('f1'), duration: 1, strokes: const [])],
      timeline: {0: const TimelineExposure.drawing(FrameId('f1'), length: 12)},
    );
    for (final axis in Axis.values) {
      for (final dpr in [1.25, 2.625, 2.75]) {
        final what = '$axis at ×$dpr';
        expect(
          span * cell * dpr % 1,
          isNot(0),
          reason: 'fixture ($what): the span ends inside its last pixel',
        );
        final painter = TimelineRowCellsPainter(
          layer: layer,
          axis: axis,
          geometry: testFrameGeometry(
            frameCellExtent: cell,
            frameEndIndexExclusive: 40,
          ),
          crossAxisExtent: 28,
          exposureStateForLayer: stateFor,
          colorScheme: const ColorScheme.dark(),
          baseTextStyle: const TextStyle(fontSize: 11),
        );
        final along = (span * cell * dpr).ceil();
        final across = (28 * dpr).ceil();
        final horizontal = axis == Axis.horizontal;
        final width = horizontal ? along : across;
        final pixels = Uint8List(along * across * 4);
        expect(
          timelineGridRasterTileReference(
            pixels: pixels,
            tileWidth: width,
            tileHeight: horizontal ? across : along,
            backgroundRgba: 0,
            ops: timelineGridSubstrateOps(
              painter: painter,
              spanStartIndex: 0,
              spanEndIndexExclusive: span,
              devicePixelRatio: dpr,
            ),
          ),
          0,
        );
        int alphaAt(int main) {
          final middle = across ~/ 2;
          final (x, y) = horizontal ? (main, middle) : (middle, main);
          return pixels[(y * width + x) * 4 + 3];
        }

        expect(alphaAt(along - 2), greaterThan(0), reason: 'fixture: paper');
        expect(
          alphaAt(along - 1),
          alphaAt(along - 2),
          reason: '$what: the last pixel is paper like the one before it',
        );
      }
    }

    // A block that goes on past the frames the row renders stops at them:
    // no tile follows there, and the window's paint would lay a cell of
    // paper past the row.
    final lastSpan = TimelineRowCellsPainter(
      layer: layer,
      geometry: testFrameGeometry(
        frameCellExtent: cell,
        frameEndIndexExclusive: span,
      ),
      crossAxisExtent: 28,
      exposureStateForLayer: stateFor,
      colorScheme: const ColorScheme.dark(),
      baseTextStyle: const TextStyle(fontSize: 11),
    );
    expect(
      lastSpan.substrateIn(0, span).paper.single.rect.right,
      lastSpan.cellRectFor(span - 1).right,
    );
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
    await pollUntil(() => landings > 0);
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
    await pollUntil(() => landings > 0);

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
    // classic-pass flicker) — a new type is a new word, every one of them
    // (the X that opens the empty run too), and a word's first bake is the
    // one wait an ask cannot make (F-314). The ACTIVE flag is no such
    // lever anymore: it left the raster entirely (UI-R21 #2; the grid
    // sheet paints the wash since I-44), so activation is a guaranteed
    // tile HIT by construction.
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
      reason: 'stale-while-revalidate while its words bake',
    );
    await pollUntil(() => landings != hits);
    final fresh = store.tileFor(
      painter: stylePainter,
      spanStartIndex: 0,
      spanEndIndexExclusive: 4,
      devicePixelRatio: 2.0,
    );
    expect(fresh, isNotNull);
    expect(identical(fresh, image), isFalse, reason: 'the re-raster landed');

    // A CONTENT change (new layer instance) over words already baked is
    // baked in the ask (F-314): the row's chrome follows the edit in this
    // frame, and so must its tile.
    final beforeEdit = landings;
    final editedPainter = painterFor(
      Layer(
        id: const LayerId('layer-a'),
        name: 'A',
        frames: [
          Frame(id: const FrameId('f1'), duration: 1, strokes: const []),
        ],
        timeline: {
          0: const TimelineExposure.drawing(FrameId('f1'), length: 3),
        },
      ),
      store: store,
      baseTextStyle: const TextStyle(fontSize: 12),
    );
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
      reason: 'F-314: the content is baked in the ask, not served stale',
    );
    expect(landings, beforeEdit + 1);
    expect(store.debugBusy, isFalse, reason: 'nothing left for off-frame');

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
  // tile, so a changed paper ground is a changed LOOK — it re-rasters, in
  // the ask that brings it (F-314).
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
    expect(await pollUntil(() => tile(plain) != null), isTrue);
    final first = tile(plain)!;

    final grounded = painterFor(
      layer,
      store: store,
      paperGround: const Color(0xFF202020),
    );
    final fresh = tile(grounded);
    expect(
      fresh,
      isNotNull,
      reason: 'the paper\'s ground is part of the look the tile keys on — '
          'a fresh raster is baked for it',
    );
    expect(identical(fresh, first), isFalse);
    expect(first.debugDisposed, isTrue, reason: 'the tile it replaced went');
  });

  // 🗣️I-129: a folder's flip hides its rows without making a new layer of
  // any of them — the eye is no fact of the layer's, so the tile has to key
  // on it of its own.
  test('I-129: the row\'s eye is part of the look — hiding the row '
      're-rasters the tile, and showing it as before keeps it', () async {
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

    final shown = painterFor(layer, store: store);
    expect(tile(shown), isNull, reason: 'cold');
    expect(await pollUntil(() => tile(shown) != null), isTrue);
    final first = tile(shown)!;
    expect(
      tile(painterFor(layer, store: store, shown: true)),
      same(first),
      reason: 'the same eye is the same look',
    );

    final hidden = painterFor(layer, store: store, shown: false);
    await pollUntil(() => !identical(tile(hidden), first));
    expect(tile(hidden), isNotNull, reason: 'a fresh raster landed for it');
    expect(first.debugDisposed, isTrue, reason: 'the tile it replaced went');
  });

  test('🚨past its capacity the tile asked for longest ago goes, its picture '
      'disposed — not one a paint asked for again since', () async {
    if (!available) {
      markTestSkipped('qa_engine.dll not built');
      return;
    }
    final store = TimelineGridTileStore.instance..debugCapacity = 2;
    addTearDown(() => store.debugCapacity = TimelineGridTileStore.capacity);
    final painter = painterFor(blockLayer(), store: store);
    ui.Image? tile(int span) => store.tileFor(
      painter: painter,
      spanStartIndex: span * 4,
      spanEndIndexExclusive: span * 4 + 4,
      devicePixelRatio: 2.0,
    );
    Future<ui.Image> landed(int span) async {
      expect(
        await pollUntil(() => tile(span) != null),
        isTrue,
        reason: 'span $span never landed',
      );
      return tile(span)!;
    }

    final first = await landed(0);
    final second = await landed(1);
    expect(tile(0), same(first), reason: 'asked for again: the newest');
    final third = await landed(2);

    expect(second.debugDisposed, isTrue, reason: 'asked for longest ago');
    expect(first.debugDisposed, isFalse);
    expect(third.debugDisposed, isFalse);
    expect(tile(0), same(first));
    // 🧮What the memory census reads of it is what the two kept weigh — the
    // one that went no longer (card census-misses-bake-once-images).
    expect(
      store.tileImageBytes,
      [first, third].fold(0, (sum, image) => sum + image.width * image.height * 4),
    );
    expect(
      collectMemoryCensusWhereTexturesAreRam(
        const [],
      ).items.singleWhere((item) => item.id == 'timelineTiles').bytes,
      store.tileImageBytes,
    );
  });

  // 🚨playback-draws-frames-the-film-did-not-change-in (2026-10-24): a run
  // shows its pages in its own order and round again, so the tile asked for
  // longest ago is the next one it shows — what an LRU lets go of first.
  group('past its capacity, a row on screen lets its tiles go by the run', () {
    /// A row on screen ([TimelineGridTileStore.noticesFor] heard), windowed
    /// so its first spans are shown and the three after them are not:
    /// those three's starts, the painter, and the tile of a span.
    ({
      List<int> past,
      TimelineRowCellsPainter painter,
      ui.Image? Function(int start) tile,
    })
    rowOnScreen(int? Function(int frame) stepsUntilShown) {
      final store = TimelineGridTileStore.instance..debugCapacity = 2;
      addTearDown(() => store.debugCapacity = TimelineGridTileStore.capacity);
      final bucket = ValueNotifier<int>(0);
      addTearDown(bucket.dispose);
      final painter = painterFor(
        blockLayer(),
        store: store,
        windowBucket: bucket,
        viewportMainExtent: 48,
        stepsUntilShown: stepsUntilShown,
      );
      void heard() {}
      painter.addListener(heard);
      addTearDown(() => painter.removeListener(heard));
      final span = timelineFrameWindowSpanFor(24);
      final shownEnd = painter.tileSpans.shown.last.$2;
      final past = [for (var i = 0; i < 3; i += 1) shownEnd + i * span];
      expect(
        past.last + span,
        lessThanOrEqualTo(40),
        reason: 'the window showed too much of the row to leave three spans',
      );
      return (
        past: past,
        painter: painter,
        tile: (start) => store.tileFor(
          painter: painter,
          spanStartIndex: start,
          spanEndIndexExclusive: start + span,
          devicePixelRatio: 2.0,
        ),
      );
    }

    Future<ui.Image> landed(ui.Image? Function() tile) async {
      expect(await pollUntil(() => tile() != null), isTrue);
      return tile()!;
    }

    test('🚨while a run plays, the tile it shows LATEST goes — though a '
        'paint asked for it since', () async {
      if (!available) {
        markTestSkipped('qa_engine.dll not built');
        return;
      }
      final steps = <int, int>{};
      final row = rowOnScreen((frame) => steps[frame]);
      final past = row.past;
      steps.addAll({past[0]: 30, past[1]: 1, past[2]: 2});

      final latest = await landed(() => row.tile(past[0]));
      final soon = await landed(() => row.tile(past[1]));
      expect(row.tile(past[0]), same(latest), reason: 'asked for again');
      final next = await landed(() => row.tile(past[2]));

      expect(latest.debugDisposed, isTrue, reason: 'shown 30 steps on');
      expect(soon.debugDisposed, isFalse, reason: 'shown next');
      expect(next.debugDisposed, isFalse);
    });

    test('wherever nothing plays, the tile asked for longest ago goes, as '
        'before', () async {
      if (!available) {
        markTestSkipped('qa_engine.dll not built');
        return;
      }
      final row = rowOnScreen((_) => null);
      final past = row.past;

      final first = await landed(() => row.tile(past[0]));
      final second = await landed(() => row.tile(past[1]));
      expect(row.tile(past[0]), same(first));
      final third = await landed(() => row.tile(past[2]));

      expect(second.debugDisposed, isTrue, reason: 'asked for longest ago');
      expect(first.debugDisposed, isFalse);
      expect(third.debugDisposed, isFalse);
    });

    test('a tile of a row nothing shows goes first, though its own window '
        'holds it and the run shows it soonest', () async {
      if (!available) {
        markTestSkipped('qa_engine.dll not built');
        return;
      }
      final steps = <int, int>{};
      final row = rowOnScreen((frame) => steps[frame]);
      final past = row.past;
      steps.addAll({past[0]: 1, past[1]: 2});
      final store = TimelineGridTileStore.instance;
      // Windowed off no bucket: every span is in its window — and no
      // painter of it is attached, so no screen shows the row.
      final unshown = painterFor(
        Layer(
          id: const LayerId('layer-b'),
          name: 'B',
          frames: [
            Frame(id: const FrameId('f1'), duration: 1, strokes: const []),
          ],
          timeline: {
            0: const TimelineExposure.drawing(FrameId('f1'), length: 2),
          },
        ),
        store: store,
        stepsUntilShown: (_) => 0,
      );
      final span = timelineFrameWindowSpanFor(24);

      final hidden = await landed(
        () => store.tileFor(
          painter: unshown,
          spanStartIndex: 0,
          spanEndIndexExclusive: span,
          devicePixelRatio: 2.0,
        ),
      );
      final sooner = await landed(() => row.tile(past[0]));
      final later = await landed(() => row.tile(past[1]));

      expect(hidden.debugDisposed, isTrue, reason: 'no row on screen');
      expect(sooner.debugDisposed, isFalse);
      expect(later.debugDisposed, isFalse);
    });

    test('a span the row shows NOW stays, however late the run shows it '
        'again', () async {
      if (!available) {
        markTestSkipped('qa_engine.dll not built');
        return;
      }
      final row = rowOnScreen((frame) => 1000 - frame);
      final shown = row.painter.tileSpans.shown.first.$1;
      final past = row.past;

      final onScreen = await landed(() => row.tile(shown));
      final farther = await landed(() => row.tile(past[0]));
      final nearer = await landed(() => row.tile(past[1]));

      expect(onScreen.debugDisposed, isFalse, reason: 'it is on screen');
      expect(farther.debugDisposed, isTrue, reason: 'off screen, shown '
          '${1000 - past[0]} steps on — after the other');
      expect(nearer.debugDisposed, isFalse);
    });
  });

  // The block-frame-lines switch (유저 2026-09-24) bakes into the tile, and
  // so does the fps that makes a second boundary's line the strongest — a
  // flip of either is a changed LOOK, and a stale tile must not keep
  // serving the other one. So does the unnamed head's mark the user picks
  // (F-489) — the block here has no name, so its head wears it.
  test('the lines and the unnamed mark are part of the look — flipping the '
      'switch, the fps while they show, or the mark re-rasters the tile',
      () async {
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
    // Bounded: a key that forgot the fact never lands a fresh tile, and
    // that has to fail here rather than hang the file.
    Future<ui.Image> landed(
      TimelineRowCellsPainter painter,
      ui.Image? stale,
    ) async {
      bool fresh() {
        final image = tile(painter);
        return image != null && !identical(image, stale);
      }

      if (!await pollUntil(fresh)) {
        fail('no fresh tile landed — the key does not see the change');
      }
      return tile(painter)!;
    }

    // ONE fact moves per step: the switch alone, then the fps alone, then
    // the mark alone — a key that saw only one of them would pass a step
    // that moved both.
    final off = painterFor(layer, store: store, framesPerSecond: 24);
    final first = await landed(off, null);

    final on = painterFor(
      layer,
      store: store,
      blockFrameLines: true,
      framesPerSecond: 24,
    );
    final second = await landed(on, first);

    final otherFps = painterFor(
      layer,
      store: store,
      blockFrameLines: true,
      framesPerSecond: 30,
    );
    final third = await landed(otherFps, second);

    final otherMark = painterFor(
      layer,
      store: store,
      blockFrameLines: true,
      framesPerSecond: 30,
      unnamedMark: InbetweenMark.one,
    );
    expect(otherMark.unnamedMark, isNot(otherFps.unnamedMark));
    final fourth = await landed(otherMark, third);
    expect(
      identical(tile(otherMark), fourth),
      isTrue,
      reason: 'kept for the mark it was baked with, not baked again',
    );
  });
}
