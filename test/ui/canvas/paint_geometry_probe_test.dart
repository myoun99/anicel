import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/canvas/display_buffer_cache.dart';
import 'package:anicel/src/ui/debug/input_inspector.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';

/// A1 — THE GEOMETRY FIELD PROBE.
///
/// Every byte figure in the composite plan is a function of the logical
/// view size, the device pixel ratio and the zoom actually worked at — and
/// none of the three has ever been measured on a device. The 1928×1200
/// that circulates is a comment in the bake, not a measurement. This probe
/// is how the numbers finally arrive: one Input Inspector line per
/// geometry change, plus a zoom histogram.
///
/// ⛔The dedupe is the part a regression would silently destroy: the zoom
/// is a continuous double, and putting it raw in the key would emit a note
/// on every drag frame — a geometry line that moves on every frame cannot
/// be read (and until 2026-09-13 the inspector was a five-line ring, so it
/// would also have scrolled the pen diagnostics away). So the tests pin
/// BOTH sides: a repaint with the same geometry emits nothing, and the
/// bucket boundary is what re-arms the emitter.
void main() {
  const canvasSize = CanvasSize(width: 8, height: 8);

  Future<void> pumpStack(
    WidgetTester tester, {
    double zoom = 1,
    double panX = 0,
    DisplayBufferCache? buffers,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 8,
              height: 8,
              child: CanvasLayerStackView(
                nodes: const [],
                imageCache: LayerFrameImageCache(frameStore: BrushFrameStore()),
                canvasSize: canvasSize,
                viewport: CanvasViewport(zoom: zoom, panX: panX),
                paintPaper: true,
                debugBufferCache: buffers,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Drives the painter directly: paints happen on the raster thread's
  /// schedule, so pumping alone cannot deterministically repaint an
  /// unchanged tree — this can.
  void paintOnce(WidgetTester tester) {
    final painter = tester
        .widgetList<CustomPaint>(
          find.descendant(
            of: find.byType(CanvasLayerStackView),
            matching: find.byType(CustomPaint),
          ),
        )
        .map((paint) => paint.painter)
        .whereType<CustomPainter>()
        .first;
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder), const Size(8, 8));
    recorder.endRecording().dispose();
  }

  setUp(() {
    InputInspector.reset();
    CanvasPaintGeometryProbe.reset();
    InputInspector.visible.value = true;
  });

  tearDown(() {
    InputInspector.reset();
    CanvasPaintGeometryProbe.reset();
  });

  testWidgets('one geometry, one line — with the numbers the plan needs',
      (tester) async {
    await pumpStack(tester);
    paintOnce(tester);

    final geometry = InputInspector.notes['geom'];
    expect(geometry, isNotNull, reason: 'the first paint reports');
    expect(geometry, contains('view=8x8'));
    expect(geometry, contains('dpr='));
    expect(geometry, contains('zoom~100%'));
    expect(geometry, contains('buf='));
    expect(geometry, contains('capped=false'));
    expect(
      geometry,
      contains('hist 100%:'),
      reason: 'the histogram rides along, bucketed',
    );

    // `paintOnce` paints outside a frame, so a note would bump the card's
    // revision on the spot: two more paints of the same geometry must
    // leave it where it is.
    final revision = InputInspector.revision.value;
    paintOnce(tester);
    paintOnce(tester);
    expect(
      InputInspector.revision.value,
      revision,
      reason: 'unchanged geometry must not emit again — a line that moves '
          'on every paint cannot be read',
    );
  });

  testWidgets('crossing a zoom bucket re-arms the emitter; moving inside '
      'one does not', (tester) async {
    await pumpStack(tester, zoom: 1);
    paintOnce(tester);
    final armed = CanvasPaintGeometryProbe.lastLine;
    expect(armed, contains('zoom~100%'));

    // 1.00 → 1.02: same 10% bucket, no new line even though the double
    // changed. This is the assertion that dies if the raw zoom ever gets
    // into the key.
    await pumpStack(tester, zoom: 1.02);
    paintOnce(tester);
    expect(
      CanvasPaintGeometryProbe.lastLine,
      armed,
      reason: 'a continuous zoom change inside one bucket stays quiet',
    );
    expect(InputInspector.notes['geom'], contains('zoom~100%'));

    await pumpStack(tester, zoom: 0.5);
    paintOnce(tester);
    expect(
      CanvasPaintGeometryProbe.lastLine,
      isNot(armed),
      reason: 'a new bucket re-arms the emitter',
    );
    expect(
      InputInspector.notes['geom'],
      contains('zoom~50%'),
      reason: 'and the slot shows the new bucket',
    );
  });

  /// 🚨THE BUFFER COUNTERS LINE MOVES ON A BUCKET, NOT ON EVERY COMPOSE.
  /// Keyed raw it emitted a line per full compose and per carry — a pan
  /// is one of those per paint — and a line that moves on every paint
  /// cannot be read mid-stroke. (It also evicted the geometry line while
  /// the inspector was a five-line ring: this file's own bucket test went
  /// red on master, 2026-09-13. The ring holds one slot per emitter since
  /// that day.) The counts are read off the injected cache so the
  /// assertion sits exactly on the bucket edge instead of guessing how
  /// many composes a pump costs.
  ///
  /// ⚠️PINNED ON THE CADENCE KEY FIRST, AND ON THE SLOTS SECOND. The key is
  /// what the emitter dedupes on, and a raw count in it changes on the very
  /// next compose. The slots are what the user reads: every `pumpStack`
  /// here builds a fresh painter, and the T12 `stack paint` probe used to
  /// key on the painter's identity (an interpolation without braces — it
  /// printed the painter, not the flag), so it said nothing a reader could
  /// use. With that fixed, eight pans leave a geometry slot, a T12 slot
  /// that names the flag, and a counter slot that reads the eighth
  /// compose.
  testWidgets('the buffer counters line moves once per bucket of eight full '
      'composes — a pan does not move it per paint', (tester) async {
    final buffers = DisplayBufferCache();
    addTearDown(buffers.dispose);

    await pumpStack(tester, buffers: buffers);
    paintOnce(tester);
    expect(
      InputInspector.notes['buf'],
      contains('full=0'),
      reason: 'the first paint reports, counters read before it composes',
    );
    final armed = CanvasPaintGeometryProbe.lastCounters;
    expect(armed, isNotNull);

    // No live surface here, so every moved rect composes whole: one full
    // compose per pan, and the count climbs by exactly one each time.
    var pan = 0.0;
    while (buffers.fullCount < 7) {
      pan += 1;
      await pumpStack(tester, panX: pan, buffers: buffers);
      paintOnce(tester);
    }
    expect(
      CanvasPaintGeometryProbe.lastCounters,
      armed,
      reason: 'seven full composes are inside one bucket of eight — the key '
          'must not have moved, or a pan is a line per paint',
    );

    while (buffers.fullCount < 8) {
      pan += 1;
      await pumpStack(tester, panX: pan, buffers: buffers);
      paintOnce(tester);
    }
    expect(
      CanvasPaintGeometryProbe.lastCounters,
      isNot(armed),
      reason: 'the eighth crosses the bucket',
    );

    // And the slots the user reads: eight rebuilds later the geometry
    // slot is still there, the counter slot reads the crossing, and the
    // T12 slot says what it was built to say.
    final slots = InputInspector.notes;
    expect(
      slots['geom'],
      contains('view=8x8'),
      reason: 'the geometry slot outlives a pan: $slots',
    );
    expect(
      slots['buf'],
      contains('full=8'),
      reason: 'the bucket crossing wrote the counter slot: $slots',
    );
    expect(
      slots['stack'],
      contains('paper=true'),
      reason: 'the T12 slot prints the flag, not the painter: $slots',
    );
  });

  testWidgets('the histogram counts paints per bucket', (tester) async {
    await pumpStack(tester, zoom: 1);
    paintOnce(tester);
    paintOnce(tester);
    await pumpStack(tester, zoom: 0.5);
    paintOnce(tester);

    expect(
      CanvasPaintGeometryProbe.zoomHistogram[100],
      greaterThanOrEqualTo(2),
    );
    expect(
      CanvasPaintGeometryProbe.zoomHistogram[50],
      greaterThanOrEqualTo(1),
    );
  });

  testWidgets('hidden inspector: no lines, no histogram, no work',
      (tester) async {
    InputInspector.visible.value = false;
    await pumpStack(tester);
    paintOnce(tester);

    expect(InputInspector.notes, isEmpty);
    expect(
      CanvasPaintGeometryProbe.zoomHistogram,
      isEmpty,
      reason: 'the probe may cost nothing while the inspector is off',
    );
  });
}
