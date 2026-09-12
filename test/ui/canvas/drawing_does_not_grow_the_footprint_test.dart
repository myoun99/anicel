import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/models/rgba_color.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/native/native_scratch.dart';
import 'package:anicel/src/native/qa_native_engine.dart';
import 'package:anicel/src/services/bitmap_tile_rgba.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/bitmap_tile_image_cache.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/canvas/display_buffer_cache.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';

import '../../helpers/collect_garbage.dart';
import '../../helpers/native_engine_path.dart';

/// 🚨★★★**DRAWING MUST NOT GROW THE PROCESS WITHOUT BOUND.**
///
/// 유저 실기 2026-09-12: a minute of ordinary drawing took the app from
/// 544MB to 17GB and it began to lag and was killed. Every counter the
/// memory census reads stayed flat (330 → 400MB) — the growth was ALL in
/// `untrackedBytes`, the row the panel labels 「엔진·폰트·프레임워크」 —
/// and switching the active layer gave it all back at once.
///
/// 🔢The shape the user measured: one dot +100MB, a half-canvas stroke
/// +700MB, a stroke across every tile +7.7GB, and WORSE once it has
/// accumulated. It scales with the dirty tile count and it is per PAINT,
/// not per dab: the lag it causes puts more frames under one stroke.
///
/// ⛔THIS FILE MEASURES, IT DOES NOT GUESS. Six candidates were read out
/// of the code first and every one was either counted or disposed. What
/// was left was invisible to every counter the app had — and that turned
/// out to BE the finding: [DisplayBufferCache] pinned a chain of whole
/// canvases while reporting the size of one.
///
/// 🎯**WHAT IT PINS DOWN**: the display buffer derives each image from the
/// last one, `toImageSync` hands back an image the engine has not
/// rasterized, and the display list that would draw it holds the image
/// BEFORE it. So the buffer holds a chain, one canvas per link, and until
/// 2026-09-12 the only budget on that chain was a LINK count sized against
/// the raster thread's stack.
///
/// 🧪**THE AXIS IS THE BUDGET, and it is held still by mutation, not by a
/// second arm** — see the note at the end of the test for the two ways a
/// "without the buffer" arm lied. Change the budget and the peak moves
/// with it, linearly; that is a controlled comparison
/// ([[symptom-attribution-is-a-clue-not-a-cause]]: two states on one axis,
/// never a number against a memory).
///
/// ⚠️A process footprint at this scale is noisy — `collectGarbage` itself
/// churns lists to force the collections, and Windows keeps freed pages in
/// the working set — so the exact assertion is on the chain's own byte
/// count and the footprint carries only a loose bound.
void main() {
  const canvasSize = CanvasSize(width: 1024, height: 1024);
  const tileSize = 128;
  /// 🚨★★★BIG ON PURPOSE — THE VIEW SIDE IS THE SIGNAL-TO-NOISE RATIO.
  ///
  /// The chain pins one image PER LINK, so the defect's size is the view's
  /// area and the instrument's noise is not. At 600px a buffer is 1.44MB:
  /// the runaway chain peaked at 184MB, the fix brings it to 64MB, and a
  /// process footprint at this scale swings ±70MB between arms for
  /// identical work (the control below read 0, +70 and +55MB on three
  /// runs) — so the two states OVERLAP and the footprint arm decides
  /// nothing. At 1200px a buffer is 5.76MB, the unbounded chain is ~737MB
  /// against a bounded 64MB, and the same noise is a tenth of the gap.
  ///
  /// ⚠️Needs [WidgetTester.view] widened to match: the default 800×600
  /// test surface would CLIP the view, and the buffer is sized to what is
  /// visible — a clipped arm would quietly measure a smaller defect.
  const defaultViewSide = 1200.0;

  /// `DisplayBufferCache._maxChainBytes`, in MB. ⚠️Written out rather than
  /// read from the class: the budget is the thing under test, and a test
  /// that asks the code what the answer is cannot fail when the answer
  /// changes.
  const maxChainMb = 64;

  const warmUpPaints = 5;
  const measuredPaints = 200;

  /// 🚨★★★**THE FIXTURE ALLOCATES NOTHING INSIDE THE LOOP**, and that is
  /// not tidiness — it is the measurement.
  ///
  /// ⛔The first version built its tiles per step. `BitmapTile` is
  /// immutable, so `writeRgbaColorToBitmapTile` returns a NEW one every
  /// call: eight calls a step, 64KB a tile, 0.5MB a paint — which is
  /// almost exactly the per-paint growth that version then reported. The
  /// instrument was measuring its own garbage, and the tile blocks it
  /// freed went past the C pool's cap to `free()`, which Windows does not
  /// hand straight back to the OS. 🧪[[symptom-attribution-is-a-clue-not-a-cause]]:
  /// what I was counting was the SHADOW of the thing I meant to count.
  ///
  /// Built once, cycled forever: every allocation the loop then makes
  /// belongs to the paint path.
  final surfaces = <BitmapSurfacePainter>[
    for (var step = 0; step < 16; step += 1)
      () {
        final tiles = canvasSize.width ~/ tileSize;
        var tile = BitmapTile.blank(size: tileSize);
        for (var i = 0; i < 8; i += 1) {
          tile = writeRgbaColorToBitmapTile(
            tile: tile,
            x: i,
            y: (step + i) % tileSize,
            color: RgbaColor(r: 255, g: 0, b: 0, a: 255),
          );
        }
        return BitmapSurfacePainter(
          surface: BitmapSurface(
            canvasSize: canvasSize,
            tileSize: tileSize,
            tiles: {
              TileCoord(x: step % tiles, y: (step ~/ tiles) % tiles): tile,
            },
          ),
          showTransparentBackground: false,
        );
      }(),
  ];

  BitmapSurfacePainter liveAt(int step) => surfaces[step % surfaces.length];

  /// Paints [measuredPaints] frames and answers what the process kept,
  /// and what [buffers] pinned at its worst moment while doing it.
  ///
  /// ⚠️[buffers] must be INJECTED, never left to the view to invent: the
  /// view's own cache is unreachable from here, so a run that used one
  /// would report `patched=0` and a peak of zero while painting exactly
  /// as hard. See the note at the end of the test.
  Future<({int keptMb, int chainPeakMb, String reading})> measure(
    WidgetTester tester,
    QaNativeEngine engine, {
    required DisplayBufferCache buffers,
    required String arm,
  }) async {
    final imageCache = LayerFrameImageCache(frameStore: BrushFrameStore());
    const nodes = <CompositeNode<CanvasStackRow>>[
      CompositeLeaf<CanvasStackRow>(CanvasActiveLayerRow(opacity: 1)),
    ];

    Future<void> paintStep(int step) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: defaultViewSide,
                height: defaultViewSide,
                child: CanvasLayerStackView(
                  nodes: nodes,
                  imageCache: imageCache,
                  debugBufferCache: buffers,
                  canvasSize: canvasSize,
                  viewport: CanvasViewport(),
                  activeSurfacePainter: liveAt(step),
                  paintPaper: true,
                  paperBackground: ProjectBackground.defaultBackground,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    int footprintMb() => (engine.processFootprintBytes ?? 0) >> 20;

    /// Every counter that could name a share of the growth, read at the
    /// same instant as the footprint. `untrackedBytes` is footprint MINUS
    /// these, so a holder that moves NAMES itself and one that does not
    /// proves the growth is outside every counter the app has.
    Map<String, int> counters() => <String, int>{
      'tileImages': BitmapTileImageCache.liveImageBytes,
      'displayBuffer': buffers.heldBytes,
      'tilePoolParked': engine.tilePoolParkedBytes,
      'nativeScratch': NativeScratch.liveBytes,
      'layerImages': imageCache.estimatedBytes,
      'flutterImageCache':
          PaintingBinding.instance.imageCache.currentSizeBytes,
    };

    for (var step = 0; step < warmUpPaints; step += 1) {
      await paintStep(step);
    }
    await tester.runAsync(collectGarbage);
    final baseline = footprintMb();
    final before = counters();

    // 🚨★★★THE SHAPE OF THE GROWTH IS THE DIAGNOSIS, not its size.
    // Everything on this path that holds images holds a BOUNDED number of
    // them — one display buffer, a derivation chain the budget caps at
    // 128. A bounded holder makes a curve that FLATTENS; only something
    // that never lets go makes a straight line. Two endpoints cannot tell
    // those apart, and the whole question is which one the user is living
    // in.
    final curve = <int>[];
    var chainPeak = 0;
    for (var step = warmUpPaints; step < measuredPaints; step += 1) {
      await paintStep(step);
      // Read AFTER every paint, not at the end: the chain collapses when
      // the budget forces a full compose, so a final reading would report
      // the trough of a sawtooth and call the peak zero.
      chainPeak = max(chainPeak, buffers.heldBytes);
      if ((step - warmUpPaints + 1) % 25 == 0) {
        curve.add(footprintMb() - baseline);
      }
    }
    await tester.runAsync(collectGarbage);
    final afterGc = footprintMb();
    final after = counters();

    final named = [
      for (final entry in after.entries)
        '${entry.key} ${(entry.value - before[entry.key]!) >> 10}KB',
    ].join(' · ');
    return (
      keptMb: afterGc - baseline,
      chainPeakMb: chainPeak >> 20,
      reading:
          '$arm: kept ${afterGc - baseline}MB '
          '(baseline=${baseline}MB after=${afterGc}MB) '
          'over ${measuredPaints - warmUpPaints} paints; named: $named'
          '\n    curve(+MB every 25 paints): ${curve.join(' ')}'
          '\n    buffer: patched=${buffers.patchedCount} '
          'full=${buffers.fullCount} '
          'depth=${buffers.derivedDepth} '
          'chainPeak=${chainPeak >> 20}MB',
    );
  }

  testWidgets('🚨the display buffer may pin a chain of canvases, so the '
      'chain has a byte budget and painting does not grow the process',
      (tester) async {
    final engine = QaNativeEngine.instance;
    if (nativeEngineLibraryPathOrNull() == null || engine == null) {
      markTestSkipped(nativeEngineMissingSkipReason);
      return;
    }

    tester.view.physicalSize = const Size(
      defaultViewSide + 80,
      defaultViewSide + 80,
    );
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final buffers = DisplayBufferCache();
    addTearDown(buffers.dispose);
    final withBuffer = await measure(
      tester,
      engine,
      buffers: buffers,
      arm: 'WITH buffer',
    );
    // 🚨★★★THE CONTROL VALIDATES THE INSTRUMENT, AND IT TOUCHES NO PRODUCT
    // CODE: record a picture, `toImageSync` it at the buffer's size, DRAW
    // it into another recording, dispose both — the bare pattern the
    // buffer path runs once a frame. The DRAW is the half that matters,
    // and the code at that draw says why: 「the draw put the image into
    // this frame's display list, and the engine holds its own reference to
    // it from that moment」. A widget test has no raster thread to consume
    // those lists, so if the bare pattern grew here, this file would be
    // measuring the harness and no product code could be changed on its
    // word. It reads ~0 — the pattern is clean and the app holds.
    await tester.runAsync(collectGarbage);
    final drawnBefore = (engine.processFootprintBytes ?? 0) >> 20;
    for (var step = 0; step < measuredPaints - warmUpPaints; step += 1) {
      final source = ui.PictureRecorder();
      ui.Canvas(source, const Rect.fromLTWH(0, 0, defaultViewSide, defaultViewSide))
          .drawRect(
            const Rect.fromLTWH(0, 0, defaultViewSide, defaultViewSide),
            Paint()..color = const Color(0xFF3366FF),
          );
      final sourcePicture = source.endRecording();
      final image = sourcePicture.toImageSync(
        defaultViewSide.toInt(),
        defaultViewSide.toInt(),
      );
      sourcePicture.dispose();
      final into = ui.PictureRecorder();
      ui.Canvas(into, const Rect.fromLTWH(0, 0, defaultViewSide, defaultViewSide))
          .drawImage(image, Offset.zero, Paint());
      into.endRecording().dispose();
      image.dispose();
    }
    await tester.runAsync(collectGarbage);
    final drawnAfter = (engine.processFootprintBytes ?? 0) >> 20;
    final control =
        'CONTROL toImageSync+DRAW+dispose: kept '
        '${drawnAfter - drawnBefore}MB '
        '(before=${drawnBefore}MB after=${drawnAfter}MB)';

    final reading =
        '${withBuffer.reading}\n$control';
    printOnFailure(reading);

    // 🚨★★★①THE BUDGET HOLDS — exact, and free of footprint noise. The
    // cache now reports what the CHAIN pins rather than what its head
    // image costs, so this reading IS the defect. Before the byte budget
    // it peaked at 184MB on this 600×600 view (128 links × 1.44MB) and at
    // 1.06GB on a 1920×1080 canvas, which is the user's own "half a stroke
    // adds 1000~1600MB".
    expect(
      withBuffer.chainPeakMb,
      lessThanOrEqualTo(maxChainMb),
      reason: 'the display buffer chain outgrew its byte budget:\n$reading',
    );
    // ②AND THE PROCESS AGREES — the independent half, and the one that
    // would have caught this without trusting a counter this same commit
    // wrote ([[adversarial-verify-is-not-optional]]: suspect the
    // instrument first). Loose because the footprint carries ±70MB of
    // allocator noise; the view side is what puts the defect an order of
    // magnitude above that. The curve in the reading is the honest
    // picture — unbounded it climbs, bounded it saws.
    expect(
      withBuffer.keptMb,
      lessThan(320),
      reason: 'painting kept memory no counter can name:\n$reading',
    );
    // ⛔THERE IS DELIBERATELY NO "WITHOUT THE BUFFER" ARM, AND THAT COST
    // A WHOLE ROUND TO LEARN (2026-09-12).
    //
    // This file began as an A/B — the same frames with and without the
    // display buffer — and NEITHER HALF OF THAT AXIS WAS REAL:
    // · `debugBufferCache: null` does not turn the buffer OFF. The view
    //   reads `widget.debugBufferCache ?? DisplayBufferCache()`, so null
    //   means "make your own", and the arm labelled "direct walk" was
    //   painting through a buffer nothing was counting.
    // · That field is `late final` on the STATE, and two `pumpWidget`s of
    //   the same widget in one test REUSE the state. So the second arm
    //   silently inherited the first arm's cache whichever order they ran
    //   in — the giveaway was `patched=0 full=0` on a cache that had just
    //   been handed to a painting view.
    // 🧪Both arms read plausible numbers throughout. An arm that measures
    // something other than its label is the "빈 것을 쟀다" trap
    // ([[adversarial-verify-is-not-optional]]), and a plausible number is
    // how it hides. THE AXIS OF THIS TEST IS THE BUDGET ITSELF, proven
    // where an axis can actually be held still: mutate the budget and the
    // peak moves with it, linearly.
  });
}
