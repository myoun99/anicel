import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
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

  Future<void> pumpStack(WidgetTester tester, {double zoom = 1}) async {
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
                viewport: CanvasViewport(zoom: zoom),
                paintPaper: true,
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
