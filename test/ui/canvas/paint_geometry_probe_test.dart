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
/// on every drag frame — the inspector's 5-line ring would be all geometry
/// and the pen diagnostics it exists for would scroll away. So the tests
/// pin BOTH sides: a repaint with the same geometry emits nothing, and the
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

    final geometry = InputInspector.notes
        .where((line) => line.startsWith('geom '))
        .toList();
    expect(geometry, hasLength(1), reason: 'the first paint reports');
    expect(geometry.single, contains('view=8x8'));
    expect(geometry.single, contains('dpr='));
    expect(geometry.single, contains('zoom~100%'));
    expect(geometry.single, contains('buf='));
    expect(geometry.single, contains('capped=false'));
    expect(
      geometry.single,
      contains('hist 100%:'),
      reason: 'the histogram rides along, bucketed',
    );

    paintOnce(tester);
    paintOnce(tester);
    expect(
      InputInspector.notes.where((line) => line.startsWith('geom ')).length,
      1,
      reason: 'unchanged geometry must not emit again — the 5-line ring is '
          'shared with the pen diagnostics this inspector exists for',
    );
  });

  testWidgets('crossing a zoom bucket re-arms the emitter; moving inside '
      'one does not', (tester) async {
    await pumpStack(tester, zoom: 1);
    paintOnce(tester);
    expect(
      InputInspector.notes.where((line) => line.startsWith('geom ')).length,
      1,
    );

    // 1.00 → 1.02: same 10% bucket, no new line even though the double
    // changed. This is the assertion that dies if the raw zoom ever gets
    // into the key.
    await pumpStack(tester, zoom: 1.02);
    paintOnce(tester);
    expect(
      InputInspector.notes.where((line) => line.startsWith('geom ')).length,
      1,
      reason: 'a continuous zoom change inside one bucket stays quiet',
    );

    await pumpStack(tester, zoom: 0.5);
    paintOnce(tester);
    final geometry = InputInspector.notes
        .where((line) => line.startsWith('geom '))
        .toList();
    expect(geometry, hasLength(2), reason: 'a new bucket reports once');
    expect(geometry.last, contains('zoom~50%'));
  });

  /// 🚨THE BUFFER COUNTERS LINE MOVES ON A BUCKET, NOT ON EVERY COMPOSE.
  /// Keyed raw it emitted a line per full compose and per carry — a pan
  /// is one of those per paint — and the inspector keeps FIVE notes, so
  /// the line built to sit beside the geometry line evicted it (this
  /// file's own bucket test went red on master, 2026-09-13). The counts
  /// are read off the injected cache so the assertion sits exactly on the
  /// bucket edge instead of guessing how many composes a pump costs.
  ///
  /// ⚠️PINNED ON THE CADENCE KEY FIRST, AND ON THE RING SECOND. The key is
  /// what the emitter dedupes on, and a raw count in it changes on the very
  /// next compose. The ring is the thing the user reads, and it is shared:
  /// every `pumpStack` here builds a fresh painter, and the T12 `stack
  /// paint` probe used to key on the painter's identity (an interpolation
  /// without braces — it printed the painter, not the flag), so seven pans
  /// were seven of those and the ring held nothing else. With that fixed,
  /// eight pans leave one geometry line, one T12 line and two counter
  /// lines: four of five, and the geometry line is still there to read.
  testWidgets('the buffer counters line moves once per bucket of eight full '
      'composes — a pan does not flood the five-line ring', (tester) async {
    final buffers = DisplayBufferCache();
    addTearDown(buffers.dispose);

    await pumpStack(tester, buffers: buffers);
    paintOnce(tester);
    expect(
      InputInspector.notes.where((line) => line.startsWith('buf ')),
      hasLength(1),
      reason: 'the first compose reports',
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

    // And the ring the user reads: eight rebuilds later the geometry line
    // is still in it, beside the two counter lines and ONE T12 line that
    // says what it was built to say.
    final ring = InputInspector.notes;
    expect(
      ring.where((line) => line.startsWith('geom ')),
      hasLength(1),
      reason: 'a pan must not evict the geometry line: $ring',
    );
    expect(
      ring.where((line) => line.startsWith('buf ')),
      hasLength(2),
      reason: 'the first compose and the bucket crossing: $ring',
    );
    expect(
      ring.where((line) => line.startsWith('stack paint ')),
      hasLength(1),
      reason: 'the T12 line is keyed on what it prints, not on the painter '
          'object — one line for eight rebuilds: $ring',
    );
    expect(
      ring.singleWhere((line) => line.startsWith('stack paint ')),
      contains('paper=true'),
      reason: 'it prints the flag, not the painter',
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
