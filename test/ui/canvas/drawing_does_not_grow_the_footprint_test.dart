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
/// second arm** — see the note at the end of the reading test for the two
/// ways a "without the buffer" arm lied. Change the budget and the peak
/// moves with it, linearly; that is a controlled comparison
/// ([[symptom-attribution-is-a-clue-not-a-cause]]: two states on one axis,
/// never a number against a memory).
///
/// ⚠️A process footprint at this scale is noisy — `collectGarbage` itself
/// churns lists to force the collections, and Windows keeps freed pages in
/// the working set — so the exact assertion is on the chain's own byte
/// count and the footprint carries only a loose bound.
/// ✏️2026-09-13 the footprint stopped being a bound at all (see the reading
/// test), and 2026-09-15 it left the gate: the footprint reading and its
/// control now live in their OWN test under the `benchmark` tag. Inside an
/// affected batch they held the gate for minutes (09-13 it hit the ten-minute
/// timeout — record `mem-footprint-test-times-out-in-a-batch` — and 09-15 it
/// sat three minutes in a 460-file batch), while the two assertions that ARE
/// the gate need neither a collection nor a footprint.
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

  /// The most the buffer may pin while painting: the head and the real
  /// base (two canvases of 5.76MB at this view side), plus room for one
  /// deferred ancestor in the paints before a snapshot lands. Far under
  /// `DisplayBufferCache._maxChainBytes` (64MB) on purpose — that budget
  /// is the net, and a test bounded at the net cannot tell the net from
  /// the floor. ⚠️Written out rather than read from the class: a test that
  /// asks the code what the answer is cannot fail when the answer changes.
  const residentBufferMb = 24;

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

  const nodes = <CompositeNode<CanvasStackRow>>[
    CompositeLeaf<CanvasStackRow>(CanvasActiveLayerRow(opacity: 1)),
  ];

  void widenTheView(WidgetTester tester) {
    tester.view.physicalSize = const Size(
      defaultViewSide + 80,
      defaultViewSide + 80,
    );
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  /// ⚠️[buffers] must be INJECTED, never left to the view to invent: the
  /// view's own cache is unreachable from here, so a run that used one
  /// would report `patched=0` and a peak of zero while painting exactly
  /// as hard. See the note at the end of the reading test.
  Future<void> paintStep(
    WidgetTester tester,
    DisplayBufferCache buffers,
    LayerFrameImageCache imageCache,
    int step,
  ) async {
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

  /// Paints the warm-up and then the measured frames, and answers the most
  /// [buffers] pinned at any moment of the measured ones. [afterPaint] is
  /// told the count of measured paints so far.
  Future<int> paintWatchingTheChain(
    WidgetTester tester, {
    required DisplayBufferCache buffers,
    required LayerFrameImageCache imageCache,
    void Function(int paints)? afterPaint,
  }) async {
    var chainPeak = 0;
    // 🎯UNDER `runAsync`, WITH A TURN OF THE EVENT QUEUE AFTER EACH PAINT.
    // The real base arrives through `Picture.toImage`, whose completion is
    // a real engine callback; the fake async zone a plain `pump` runs in
    // never delivers it, so the snapshots would all still be "in flight",
    // `promotionSlotFree` would stay false, and every paint would derive
    // from the head under budget — the old shape, measured as the new one.
    // The `promotedCount` assertion is what says this actually ran.
    await tester.runAsync(() async {
      for (var step = warmUpPaints; step < measuredPaints; step += 1) {
        await paintStep(tester, buffers, imageCache, step);
        await Future<void>.delayed(Duration.zero);
        // Read AFTER every paint, not at the end: a chain collapses when a
        // budget forces a full compose, so a final reading would report
        // the trough of a sawtooth and call the peak zero.
        chainPeak = max(chainPeak, buffers.heldBytes);
        afterPaint?.call(step - warmUpPaints + 1);
      }
    });
    return chainPeak;
  }

  String bufferLine(DisplayBufferCache buffers, int chainPeak) =>
      'buffer: patched=${buffers.patchedCount} '
      'full=${buffers.fullCount} '
      'depth=${buffers.derivedDepth} '
      'real=${buffers.promotedCount} '
      'chainPeak=${chainPeak >> 20}MB';

  testWidgets('🚨the display buffer may pin a chain of canvases, so the '
      'chain has a byte budget — and a paint pins no more than head and base',
      (tester) async {
    widenTheView(tester);
    final buffers = DisplayBufferCache();
    addTearDown(buffers.dispose);
    final imageCache = LayerFrameImageCache(frameStore: BrushFrameStore());
    for (var step = 0; step < warmUpPaints; step += 1) {
      await paintStep(tester, buffers, imageCache, step);
    }

    final chainPeak = await paintWatchingTheChain(
      tester,
      buffers: buffers,
      imageCache: imageCache,
    );
    final reading = bufferLine(buffers, chainPeak);
    printOnFailure(reading);

    // 🚨★★★①NO CHAIN — exact, and free of footprint noise. The cache
    // reports what it pins: the head, the real base, and any deferred
    // ancestors the head still holds. With the real base landing, that is
    // TWO canvases (11.5MB here) and the deferred depth saws between 0
    // and 1; the bound leaves room for one more. Before the real base it
    // read 64MB — the budget's edge — and before the byte budget 516MB on
    // this view, 1.06GB on a 1920×1080 canvas.
    expect(
      chainPeak >> 20,
      lessThanOrEqualTo(residentBufferMb),
      reason: 'the display buffer pinned more than head + real base:\n'
          '$reading',
    );
    // ②AND THE SNAPSHOTS ACTUALLY LANDED. Without this, a promotion that
    // never completes would leave every paint deriving from the head under
    // budget — 64MB pinned, ① red, and this line is what names the cause.
    expect(
      buffers.promotedCount,
      greaterThan(measuredPaints ~/ 8),
      reason: 'real bases stopped landing — the head is being derived from '
          'under budget instead:\n$reading',
    );
  });

  testWidgets('READING: what the process kept over the same paints, beside '
      'the bare toImageSync+DRAW+dispose control — run this file alone',
      (tester) async {
    final engine = QaNativeEngine.instance;
    if (nativeEngineLibraryPathOrNull() == null || engine == null) {
      markTestSkipped(nativeEngineMissingSkipReason);
      return;
    }
    widenTheView(tester);
    final buffers = DisplayBufferCache();
    addTearDown(buffers.dispose);
    final imageCache = LayerFrameImageCache(frameStore: BrushFrameStore());

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
      await paintStep(tester, buffers, imageCache, step);
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
    final chainPeak = await paintWatchingTheChain(
      tester,
      buffers: buffers,
      imageCache: imageCache,
      afterPaint: (paints) {
        if (paints % 25 == 0) {
          curve.add(footprintMb() - baseline);
        }
      },
    );
    await tester.runAsync(collectGarbage);
    final afterGc = footprintMb();
    final after = counters();
    final named = [
      for (final entry in after.entries)
        '${entry.key} ${(entry.value - before[entry.key]!) >> 10}KB',
    ].join(' · ');

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
    final drawnBefore = footprintMb();
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
    final drawnAfter = footprintMb();

    // ignore: avoid_print
    print(
      'WITH buffer: kept ${afterGc - baseline}MB '
      '(baseline=${baseline}MB after=${afterGc}MB) '
      'over ${measuredPaints - warmUpPaints} paints; named: $named'
      '\n    curve(+MB every 25 paints): ${curve.join(' ')}'
      '\n    ${bufferLine(buffers, chainPeak)}'
      '\nCONTROL toImageSync+DRAW+dispose: kept '
      '${drawnAfter - drawnBefore}MB '
      '(before=${drawnBefore}MB after=${drawnAfter}MB)',
    );
    // ⛔THE PROCESS FOOTPRINT IS A READING HERE, NOT A GATE. It was the
    // independent instrument that found the chain — the one that did not
    // trust the counter the fix wrote — and it is still printed above for
    // whoever runs this file ALONE. But `flutter test` runs files in
    // parallel isolates of ONE process, and a process footprint counts the
    // neighbours: the same run that read +151MB alone read +760MB in a
    // batch of 800 tests (2026-09-13) and went red on nothing — and the
    // CONTROL beside it, which allocates nothing of its own, read +6.7GB
    // (1,279 → 8,041MB) in that batch while its curve stayed a healthy
    // saw. A gate that
    // measures whoever happens to be running beside it is the "빈 것을
    // 쟀다" trap with the sign flipped. To re-check the engine against the
    // counter, run this file by itself and read the curve: unbounded it
    // climbs, bounded it saws, and with the real base it stays flat.
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
  }, tags: const ['benchmark']);
}
