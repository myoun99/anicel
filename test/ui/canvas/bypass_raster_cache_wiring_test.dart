import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/debug/measurement_mode.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';

/// The transition-pixel-jump A/B must actually reach the engine: the
/// switch rides [CustomPaint.willChange], which is the only hint Dart
/// has over the Skia raster cache. A switch that flips a notifier
/// nobody reads is the "debug affordance nobody has" this popover has
/// already shipped once.
void main() {
  tearDown(MeasurementMode.reset);

  testWidgets('the bypass switch drives the canvas stack\'s willChange, '
      'live', (tester) async {
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

    CustomPaint stackPaint() => tester
        .widgetList<CustomPaint>(
          find.descendant(
            of: find.byType(CanvasLayerStackView),
            matching: find.byType(CustomPaint),
          ),
        )
        .firstWhere((paint) => paint.painter != null);

    expect(stackPaint().willChange, isFalse, reason: 'default = cache on');

    MeasurementMode.bypassCanvasRasterCache.value = true;
    await tester.pump();
    expect(
      stackPaint().willChange,
      isTrue,
      reason: 'flipping the switch must not need a rebuild from elsewhere',
    );

    MeasurementMode.bypassCanvasRasterCache.value = false;
    await tester.pump();
    expect(stackPaint().willChange, isFalse);
  });
}
