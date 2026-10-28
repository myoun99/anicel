@Tags(['impeller'])
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/canvas/layer_blend_shader.dart';
import 'package:anicel/src/ui/canvas/subtree_image_composite.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';
import '../../helpers/the_frame_as_it_stands.dart';

/// 🚨The canvas hands the one walk (`paintCompositeTree`) the rect its
/// recording is shown within, so a row composed over its backdrop is read
/// in the frame there ([drawBlendOverBackdrop]'s `shownWithin`) — not
/// rasterised off the screen three times a step (🔬21.3ms against 30.0
/// from a stroke's input to the screen under a multiply row, 10-22). The
/// camera's route hands none: its recording may be cut again.
///
/// ⚠️IMPELLER ONLY: Skia has no shader filter, so on the default runner
/// nothing is read in the frame and this skips.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(LayerBlendShader.load);

  const canvasSize = CanvasSize(width: 4, height: 4);
  const subtractedFromThePaper = [0, 68, 0, 255];

  testWidgets(
    'a blend at the root is read in the frame the canvas shows',
    (tester) async {
      final pixels = Uint8List(4 * 4 * 4)
        ..[0] = 200
        ..[1] = 60
        ..[2] = 128
        ..[3] = 255;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 4,
                height: 4,
                child: TheFrameAsItStands(
                  nodes: [
                    const CompositeBackdropBlend<CanvasStackRow>(
                      backdrop: [],
                      source: CompositeLeaf<CanvasStackRow>(
                        CanvasActiveLayerRow(
                          opacity: 1,
                          blendMode: LayerBlendMode.normal,
                        ),
                      ),
                      blendMode: LayerBlendMode.subtract,
                    ),
                  ],
                  imageCache: LayerFrameImageCache(
                    frameStore: BrushFrameStore(),
                  ),
                  canvasSize: canvasSize,
                  viewport: CanvasViewport(),
                  activeSurfacePainter: BitmapSurfacePainter(
                    surface: BitmapSurface(
                      canvasSize: canvasSize,
                      tileSize: 4,
                      tiles: {
                        TileCoord(x: 0, y: 0): BitmapTile(
                          size: 4,
                          pixels: pixels,
                        ),
                      },
                    ),
                    showTransparentBackground: false,
                  ),
                  paintPaper: true,
                  paperBackground: const ProjectBackground.color(0xFF808080),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final painter = tester
          .widgetList<CustomPaint>(
            find.descendant(
              of: find.byType(TheFrameAsItStands),
              matching: find.byType(CustomPaint),
            ),
          )
          .map((paint) => paint.painter)
          .whereType<CustomPainter>()
          .first;
      debugBlendsReadInTheFrame = 0;
      final bytes = (await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        const size = Size(4, 4);
        painter.paint(Canvas(recorder, Offset.zero & size), size);
        final image = await recorder.endRecording().toImage(4, 4);
        final data = await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        image.dispose();
        return data!.buffer.asUint8List();
      }))!;

      expect(
        debugBlendsReadInTheFrame,
        1,
        reason: 'with no rect handed over, the backdrop is rasterised',
      );
      expect(bytes.sublist(0, 4), subtractedFromThePaper, reason: 'control');
    },
    skip: !ui.ImageFilter.isShaderFilterSupported,
  );
}
