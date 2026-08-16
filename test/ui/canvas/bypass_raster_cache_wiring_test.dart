import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';

/// The canvas stack's picture is engine-raster-cacheable AGAIN — the
/// integral layer offset law replaced the bypass.
///
/// History: Skia's cache snaps a stable picture's LAYER to integral
/// device translation while live repaints render fractional, and the flip
/// hopped axis-aligned edges by 1px at every engage/disengage moment
/// (pen-down, pen-up, layer switch, tool buttons — device-confirmed
/// 2026-08-17; #1101's in-picture snap could not close it because the
/// snapped offset belongs to panel layout, not to the picture). #1103
/// answered by refusing the cache with `willChange: true`. The
/// fundamental fix is `IntegralLayerOffset` (mounted above the canvas
/// content boundary in `brush_canvas_panel.dart`): it holds the layer's
/// device offset integral, so the snap is a no-op and cached and live
/// renders are the same pixels — see
/// `test/ui/canvas/integral_layer_offset_test.dart` for that law's own
/// pins. With the disagreement gone, keeping the bypass would only pay
/// re-raster cost for no pixel; this file pins that it stays gone.
void main() {
  testWidgets('the canvas stack picture does NOT opt out of the raster '
      'cache — the integral layer offset law replaced the bypass', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 100,
            height: 100,
            child: CanvasLayerStackView(
              nodes: const [CanvasActiveLayerNode(opacity: 1)],
              imageCache: LayerFrameImageCache(frameStore: BrushFrameStore()),
              canvasSize: const CanvasSize(width: 16, height: 16),
              viewport: CanvasViewport(zoom: 1),
              paintPaper: true,
              paperBackground: const ProjectBackground.color(0xFFFFFFFF),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final stackPaint = tester
        .widgetList<CustomPaint>(
          find.descendant(
            of: find.byType(CanvasLayerStackView),
            matching: find.byType(CustomPaint),
          ),
        )
        .firstWhere((paint) => paint.painter != null);

    expect(
      stackPaint.willChange,
      isFalse,
      reason: 'the layer offset law (IntegralLayerOffset above the content '
          'boundary) makes the raster cache agree with live renders, so '
          'the willChange bypass would only refuse a cache that is now '
          'harmless — and pay re-raster for it',
    );
  });
}
