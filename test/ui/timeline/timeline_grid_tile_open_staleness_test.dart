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

/// The OPEN-STALENESS residency law (device report 2026-08-17: old-format
/// file opened, some rows' block bodies dark/short from the first frame; a
/// cut switch away and back did NOT repair; activating the layer did).
///
/// #1076 closed the CROSS-GENERATION TOCTOU: a request whose (project,
/// cut) generation died before the drain is discarded un-rastered. That
/// discard is airtight for the CHECK — and it was not, until this round,
/// for the revision STAMP. `_drain` used to store the entry with a LIVE
/// read of `painter.celContentRevision` AFTER `await _raster(...)`, while
/// the content answers were sampled synchronously at raster START (the
/// substrate emit). The raster suspends between the two — the glyph A8
/// bake's `toByteData` and the `ImmutableBuffer` upload are real awaits —
/// so a `celHasContentForLayer` crossing whose bump landed inside that
/// window produced a tile whose PIXELS describe revision N under a STAMP
/// of N+1. `_TileEntry.matches` compares the NUMBER, so the poisoned tile
/// was served as fresh forever: the LRU survives cut trips (capacity 768,
/// `clear()` is test-only) and the generation token is the pure string
/// 'projectId:cutId', reproduced exactly on return. Only the NEXT bump
/// (first pen-down, any later crossing) healed it — the device's
/// "activating the layer fixes it".
///
/// THE LAW THIS PINS: the entry is stamped with the revision `_raster`
/// SAMPLED in the same synchronous block as its content reads — pixels
/// and stamp can never disagree. A crossing that straddles the raster
/// costs exactly one stale-while-revalidate beat (the old tile shows, no
/// flash, while the re-raster against live answers lands) and then the
/// resident tile is honest: no revalidation storm, and a cut trip serves
/// it back with no repair needed.
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

  test('a crossing that lands inside the raster window stamps the SAMPLED '
      'revision: the straddled tile is served stale-while-revalidate, '
      're-rastered once against live answers, and never resident-poisoned '
      '(a cut trip needs no repair)', () async {
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

    final stale = store.tileFor(
      painter: painterA,
      spanStartIndex: 0,
      spanEndIndexExclusive: 4,
      devicePixelRatio: 1.0,
    );
    // The tile's pixels describe revision 0 (cells 0..2 baked with the
    // empty-cel tint) and — the fix — its stamp says so too: `_raster`
    // returned the revision it sampled beside its content reads and
    // `_drain` stamped that. `matches()` now fails against the live
    // revision 1, so this serve is STALE-WHILE-REVALIDATE: the resident
    // tile shows (no flash) and a re-raster against live answers is
    // scheduled. Pre-fix this was the poisoning: a live stamp read after
    // the raster's awaits said revision 1 over revision-0 pixels, the
    // serve was a perfectly FRESH hit, and the landing waited on below
    // never came (this test's red state).
    expect(
      stale,
      isNotNull,
      reason:
          'stale-while-revalidate (by design): the straddled tile keeps '
          'showing while the honest re-raster lands',
    );
    final staleImage = stale!;
    final staleBytes = (await staleImage.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!.buffer.asUint8List();

    // The revalidation the sampled stamp makes possible — and the exact
    // landing the live-read stamp made impossible forever.
    await waitForLandings(2);
    final healed = store.tileFor(
      painter: painterA,
      spanStartIndex: 0,
      spanEndIndexExclusive: 4,
      devicePixelRatio: 1.0,
    );
    expect(healed, isNotNull);
    expect(identical(healed, staleImage), isFalse);
    final healedBytes = (await healed!.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!.buffer.asUint8List();
    // The pixels really were different worlds: the straddled tile
    // carried the empty-cel tint (timelineEmptyCelPaperColor) over cells
    // 0..2, the healed one carries the full paper. This is the assertion
    // that pins "the resident tile was WRONG", not merely "old".
    expect(
      listEquals(staleBytes, healedBytes),
      isFalse,
      reason:
          'the straddled tile\'s pixels described the pre-crossing world '
          '(empty-cel tint), the healed tile the post-crossing one',
    );

    // And the honest stamp is QUIESCENT: the healed entry carries the
    // revision its raster sampled (1, unchanged since), so serving it is
    // a fresh hit — no revalidation storm.
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(
      landings,
      2,
      reason:
          'exactly one repair: the sampled stamp matches the live '
          'revision, so nothing keeps re-rastering',
    );

    // ---- the cut trip (device observation was "navigating to another
    // cut and back does NOT repair" — with the honest stamp there is
    // nothing left TO repair, and the trip schedules nothing) ------------
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
    await waitForLandings(3);

    final backHome = store.tileFor(
      painter: painterA,
      spanStartIndex: 0,
      spanEndIndexExclusive: 4,
      devicePixelRatio: 1.0,
    );
    expect(
      identical(backHome, healed),
      isTrue,
      reason:
          'returning serves the honest resident tile as a valid hit — '
          'the LRU survived the trip and the pure-string generation is '
          'reproduced exactly, which is only safe now that pixels and '
          'stamp cannot disagree',
    );
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(landings, 3, reason: 'the trip needed no repair');
  });
}
