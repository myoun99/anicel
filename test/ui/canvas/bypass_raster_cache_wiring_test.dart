import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';

/// The canvas stack's picture is NEVER engine-raster-cached: Skia's cache
/// snaps a stable picture to integral device translation while live
/// repaints render fractional, and the flip between the two hopped
/// axis-aligned edges by 1px at every engage/disengage moment (pen-down,
/// pen-up, layer switch, tool buttons — device-confirmed 2026-08-17,
/// including that the in-picture snap of #1101 could not close it: the
/// cache snaps the picture LAYER's device offset, which panel layout
/// owns). willChange stays true — the display buffer already reduces the
/// picture to a couple of image blits, so the engine cache saved nothing
/// here worth a visible pixel.
void main() {
  testWidgets('the canvas stack picture opts out of the raster cache, '
      'unconditionally', (tester) async {
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
      isTrue,
      reason: 'a cached canvas picture snaps to integral device offsets '
          'and hops 1px against its own live frames — the hint is the law '
          'now, not a diagnosis switch',
    );
  });
}
