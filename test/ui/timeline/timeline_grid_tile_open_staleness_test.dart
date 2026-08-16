import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show ValueNotifier, listEquals;
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

import 'timeline_frame_geometry_probe.dart';

/// 🔴 repro — the OPEN-STALENESS residency law (device report 2026-08-17:
/// old-format file opened, some rows' block bodies dark/short from the
/// first frame; a cut switch away and back does NOT repair; activating the
/// layer does).
///
/// #1076 closed the CROSS-GENERATION TOCTOU: a request whose (project,
/// cut) generation died before the drain is discarded un-rastered, and its
/// commit message says the discard is airtight because "every resolver
/// read in a raster happens in one synchronous block with the check".
///
/// That is true of the DEAD-GENERATION CHECK — and NOT of the revision
/// stamp. `_drain` stores the entry with
/// `celContentRevision: request.painter.celContentRevision`
/// (timeline_grid_tile_store.dart:241), a LIVE read that happens AFTER
/// `await _raster(...)` (line 226), while the content answers were sampled
/// synchronously at raster START (the substrate emit, line 344-350). The
/// raster suspends between the two — the glyph A8 bake's `toByteData` and
/// the `ImmutableBuffer` upload are real awaits — so any
/// `celHasContentForLayer` transition whose revision bump lands inside
/// that window produces a tile whose PIXELS describe revision N while its
/// STAMP says N+1.
///
/// Such a tile is indistinguishable from fresh forever after:
/// `_TileEntry.matches` (lines 605-636) compares identities only — layer
/// instance, resolver tear-offs, the revision NUMBER — never the answers
/// baked into the pixels. Nothing re-rasters it:
///  - repaints serve it as a valid hit,
///  - a cut switch away and back serves it too, because the entry LRU is
///    app-global and never cleared (capacity 768, `clear()` is
///    @visibleForTesting), and the generation token is the pure string
///    'projectId:cutId' (timeline_tab_host.dart:706-708) — leaving and
///    returning reproduces it exactly,
///  - only the NEXT revision bump (first pen-down flips
///    `brushInputActive`, any empty↔drawn crossing) makes it stale.
///
/// At open this window is exactly "tiles baked from incomplete state and
/// never invalidated": the first frame's paint queues up to 32 requests,
/// the drain rasters them serially across many event-loop turns, and a
/// crossing that lands mid-queue (e.g. the post-open text-cel projection
/// sweep storing its first surfaces, or any store registration finishing
/// after the first paint) splits every straddled row at a span boundary —
/// blocks correct up to one tile edge, empty-tinted after it, which is the
/// screenshot's shape.
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

  // One drawing block covering cells 0..7 — both probed spans sit inside
  // one hold, so every cell asks the content question.
  Layer blockLayer({String id = 'layer-a'}) => Layer(
    id: LayerId(id),
    name: 'A',
    frames: [Frame(id: const FrameId('f1'), duration: 1, strokes: const [])],
    timeline: {0: const TimelineExposure.drawing(FrameId('f1'), length: 8)},
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

  test(
    'a tile whose pixels answered "cel empty" but whose revision stamp was '
    'read after the mid-raster crossing is served as FRESH forever — '
    'including after a cut switch away and back; only the next revision '
    'bump heals it',
    () async {
      if (!available) {
        markTestSkipped('qa_engine.dll not built');
        return;
      }
      final store = TimelineGridTileStore.instance;
      var landings = 0;
      store.revision.addListener(() => landings += 1);
      Future<void> waitForLandings(int n) async {
        final deadline = DateTime.now().add(const Duration(seconds: 10));
        while (landings < n) {
          if (DateTime.now().isAfter(deadline)) {
            fail('timed out waiting for tile landing #$n (have $landings)');
          }
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
      }

      // The content source, wired the way timeline_tab_host wires the
      // session's: a fact resolver plus the revision that bumps whenever
      // the fact can have changed. `hasContent` starts FALSE — the state a
      // file-backed cel shows any consumer that asks before its
      // registration/crossing lands.
      var hasContent = false;
      var flipAtFrame = -1;
      final revision = ValueNotifier<int>(0);
      final celContent = TimelineCelContentSource(
        hasContent: (layer, frameIndex) {
          if (frameIndex == flipAtFrame && !hasContent) {
            // The crossing lands while the drain is INSIDE `_raster`:
            // cells 0..2 of the span already answered "empty" into the op
            // stream, and the store bumps its revision exactly as
            // BrushFrameStore._noteCelContent does. The entry stamp is
            // read only after the raster's awaits, so it will carry the
            // POST-crossing value over the PRE-crossing pixels.
            hasContent = true;
            revision.value += 1;
          }
          return hasContent;
        },
        revision: revision,
      );

      final layerA = blockLayer();
      final painterA = TimelineRowCellsPainter(
        layer: layerA,
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
        substrateGeneration: 'p:cut-a',
      );

      flipAtFrame = 3; // the LAST cell of the probed span [0, 4)
      expect(
        store.tileFor(
          painter: painterA,
          spanStartIndex: 0,
          spanEndIndexExclusive: 4,
          devicePixelRatio: 1.0,
        ),
        isNull,
        reason: 'cold span: the classic paint covers this frame',
      );
      await waitForLandings(1);
      expect(
        revision.value,
        1,
        reason: 'sanity: the crossing really landed inside the raster',
      );

      final poisoned = store.tileFor(
        painter: painterA,
        spanStartIndex: 0,
        spanEndIndexExclusive: 4,
        devicePixelRatio: 1.0,
      );
      // 🔴 repro: BROKEN value documented. The tile's pixels describe
      // revision 0 (cells 0..2 baked with the empty-cel tint), but the
      // entry was stamped `request.painter.celContentRevision` AFTER the
      // raster's awaits (timeline_grid_tile_store.dart:241) — revision 1 —
      // so `matches()` passes and the poisoned tile is served as a
      // perfectly FRESH hit. CORRECT behavior: the stamp must be the
      // revision sampled at raster start (the fix is `_raster` returning
      // the sampled revision and `_drain` stamping that), which would make
      // this call return the tile as STALE and schedule a re-raster.
      // When that fix lands, flip this to expect a third landing below.
      expect(poisoned, isNotNull);
      final poisonedImage = poisoned!;
      final poisonedBytes = (await poisonedImage.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List();

      // No revalidation is ever scheduled for it: the store believes the
      // tile is current.
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(
        landings,
        1,
        reason:
            '🔴 repro: no re-raster is scheduled for the poisoned tile — '
            'the stamp says it already describes revision 1',
      );

      // ---- the cut trip (device observation: "navigating to another cut
      // and back does NOT repair") -----------------------------------------
      final painterB = TimelineRowCellsPainter(
        layer: blockLayer(id: 'layer-b'),
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
        substrateGeneration: 'p:cut-b',
      );
      store.tileFor(
        painter: painterB,
        spanStartIndex: 0,
        spanEndIndexExclusive: 4,
        devicePixelRatio: 1.0,
      );
      await waitForLandings(2);

      final backHome = store.tileFor(
        painter: painterA,
        spanStartIndex: 0,
        spanEndIndexExclusive: 4,
        devicePixelRatio: 1.0,
      );
      // 🔴 repro: BROKEN value documented. Returning to the cut serves the
      // SAME poisoned image as a valid hit: the LRU survived the trip
      // (nothing clears it on a cut switch), the generation token is the
      // pure string 'projectId:cutId' so it is reproduced exactly on
      // return, and every identity `matches()` compares — layer instance,
      // resolver tear-offs, revision NUMBER — is unchanged. CORRECT
      // behavior (with the stamp fixed): the entry would still carry
      // revision 0 and this call would re-raster instead of serving it.
      expect(identical(backHome, poisonedImage), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(landings, 2, reason: '🔴 repro: the trip scheduled no repair');

      // ---- the healing law (green): the NEXT crossing bump makes the
      // stamp stale, and the re-raster against live answers replaces the
      // tile. On device this is why the first pen-down (brushInputActive
      // → celTintRevision) or any later empty↔drawn crossing repairs every
      // resident tile at once.
      revision.value += 1;
      final staleServed = store.tileFor(
        painter: painterA,
        spanStartIndex: 0,
        spanEndIndexExclusive: 4,
        devicePixelRatio: 1.0,
      );
      expect(
        identical(staleServed, poisonedImage),
        isTrue,
        reason:
            'stale-while-revalidate (by design): the old tile shows while '
            'the fresh raster lands',
      );
      await waitForLandings(3);
      final healed = store.tileFor(
        painter: painterA,
        spanStartIndex: 0,
        spanEndIndexExclusive: 4,
        devicePixelRatio: 1.0,
      );
      expect(healed, isNotNull);
      expect(identical(healed, poisonedImage), isFalse);
      final healedBytes = (await healed!.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List();
      // The pixels really were different worlds: the poisoned tile carried
      // the empty-cel tint (timelineEmptyCelPaperColor) over cells 0..2,
      // the healed one carries the full paper. This is the assertion that
      // pins "the resident tile was WRONG", not merely "old".
      expect(
        listEquals(poisonedBytes, healedBytes),
        isFalse,
        reason:
            'the resident tile\'s pixels described the pre-crossing world '
            '(empty-cel tint), the healed tile the post-crossing one',
      );
    },
  );
}
