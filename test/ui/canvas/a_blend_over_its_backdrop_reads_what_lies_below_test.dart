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
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/camera_frame_corners.dart';
import 'package:anicel/src/services/cut_frame_composite_plan.dart';
import 'package:anicel/src/ui/camera/camera_frame_render_service.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/canvas/layer_blend_shader.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';
import '../../helpers/the_frame_as_it_stands.dart';

/// 🗣️brush-fidelity-Q4 (유저 2026-10-17 「레이어까지 같이」): a layer in a
/// blend the GPU lacks — ↩️and since a-blurred-folder-cut-by-the-view-moves-
/// on-vulkan, in any advanced blend — is composed over a picture of what
/// lies below it, and what lies below it is what a GPU blend would have
/// read off its target: at the root, the PAPER; inside a folder's buffer,
/// only what the folder holds.
///
/// 📐THE CONTROL IS DIFFERENCE. Over a grey paper, ink brighter than it in
/// red and darker in green: subtract floors red at nothing and keeps
/// green's distance, where difference turns red round — so the two say
/// apart which one read the paper, and agree where both must. Both bytes
/// are worked out by hand ([subtractedFromThePaper],
/// [differenceWithThePaper]); over nothing either would be the ink itself.
/// ↩️Difference had a GPU blend, which read the paper off its target, and
/// so stood in as the route known to read it — until every advanced blend
/// went over its backdrop in the shader
/// (a-blurred-folder-cut-by-the-view-moves-on-vulkan). The paper laid once
/// is held against a normal row, which lays it under itself.
///
/// Both walks, the editing stack (playback's too) and the camera (the
/// export's), each against its own control.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(LayerBlendShader.load);

  const canvasSize = CanvasSize(width: 4, height: 4);
  const grey = ProjectBackground.color(0xFF808080);

  /// The ink (200, 60, 128), opaque, on the top-left pixel alone.
  BitmapSurface inked() {
    final pixels = Uint8List(4 * 4 * 4);
    pixels
      ..[0] = 200
      ..[1] = 60
      ..[2] = 128
      ..[3] = 255;
    return BitmapSurface(
      canvasSize: canvasSize,
      tileSize: 4,
      tiles: {TileCoord(x: 0, y: 0): BitmapTile(size: 4, pixels: pixels)},
    );
  }

  const subtractedFromThePaper = [0, 68, 0, 255];
  const differenceWithThePaper = [72, 68, 0, 255];
  const inkOverThePaper = [200, 60, 128, 255];
  const thePaper = [128, 128, 128, 255];

  List<int> at(Uint8List bytes, int x, int y) {
    final i = (y * canvasSize.width + x) * 4;
    return bytes.sublist(i, i + 4);
  }

  group('the camera', () {
    Future<Uint8List> render(
      List<CompositeNode<CutFrameCompositeLayer>> nodes, {
      ProjectBackground paper = grey,
    }) async {
      final view = cameraViewOver(canvasSize.canvasRect);
      final image = await const CameraFrameRenderService().renderThroughCamera(
        nodes: nodes,
        pose: view.pose,
        cameraFrameSize: view.frameSize,
        canvasSize: canvasSize,
        cutsToTheCanvas: true,
        paper: paper,
      );
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return data!.buffer.asUint8List();
    }

    CutFrameCompositeLayer row(LayerBlendMode blendMode) =>
        CutFrameCompositeLayer(
          surface: inked(),
          opacity: 1,
          blendMode: blendMode,
        );

    /// [nodes] as the plan hands them over.
    List<CompositeNode<CutFrameCompositeLayer>> planned(
      List<CompositeNode<CutFrameCompositeLayer>> nodes,
    ) => composeOverTheirBackdrops(
      nodes,
      blendOf: (layer) => layer.blendMode,
      paintedNormal: (layer) => layer.paintedNormal(),
    );

    test('at the root a blend reads the paper', () async {
      final control = await render(
        planned([CompositeLeaf(row(LayerBlendMode.difference))]),
      );
      expect(at(control, 0, 0), differenceWithThePaper, reason: 'control');

      final bytes = await render(
        planned([CompositeLeaf(row(LayerBlendMode.subtract))]),
      );
      expect(at(bytes, 0, 0), subtractedFromThePaper);
      expect(at(bytes, 3, 3), thePaper);
    });

    test('inside a folder\'s buffer it reads only what the folder holds',
        () async {
      final bytes = await render(
        planned([
          CompositeGroup(
            children: [CompositeLeaf(row(LayerBlendMode.subtract))],
            opacity: 1,
            blendMode: LayerBlendMode.normal,
          ),
        ]),
      );
      expect(
        at(bytes, 0, 0),
        inkOverThePaper,
        reason: 'over nothing, subtract keeps the ink — and the folder lays '
            'it on the paper plain',
      );
    });

    test('the paper is laid once: a thin one stays as thin', () async {
      const thin = ProjectBackground.color(0x80808080);
      final control = await render([
        CompositeLeaf(row(LayerBlendMode.normal)),
      ], paper: thin);
      final bytes = await render(
        planned([CompositeLeaf(row(LayerBlendMode.subtract))]),
        paper: thin,
      );
      expect(
        at(bytes, 3, 3),
        at(control, 3, 3),
        reason: 'laid under the rows AND in the blend\'s backdrop it would '
            'show through itself',
      );
    });
  });

  group('the editing stack', () {
    Future<Uint8List> render(
      WidgetTester tester,
      List<CompositeNode<CanvasStackRow>> nodes, {
      ProjectBackground paper = grey,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          // A fresh state per render: nothing of the last one carried.
          key: UniqueKey(),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 4,
                height: 4,
                child: TheFrameAsItStands(
                  nodes: nodes,
                  imageCache: LayerFrameImageCache(
                    frameStore: BrushFrameStore(),
                  ),
                  canvasSize: canvasSize,
                  viewport: CanvasViewport(),
                  activeSurfacePainter: BitmapSurfacePainter(
                    surface: inked(),
                    showTransparentBackground: false,
                  ),
                  paintPaper: true,
                  paperBackground: paper,
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
      return (await tester.runAsync(() async {
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
    }

    CompositeNode<CanvasStackRow> live(LayerBlendMode blendMode) =>
        CompositeLeaf<CanvasStackRow>(
          CanvasActiveLayerRow(opacity: 1, blendMode: blendMode),
        );

    /// The live row in [blendMode] as the plan hands it over: composed over
    /// everything below it in its list, here nothing.
    CompositeNode<CanvasStackRow> blended(LayerBlendMode blendMode) =>
        CompositeBackdropBlend<CanvasStackRow>(
          backdrop: const [],
          source: live(LayerBlendMode.normal),
          blendMode: blendMode,
        );

    testWidgets('at the root a blend reads the paper', (tester) async {
      final control = await render(tester, [
        blended(LayerBlendMode.difference),
      ]);
      expect(at(control, 0, 0), differenceWithThePaper, reason: 'control');

      final bytes = await render(tester, [blended(LayerBlendMode.subtract)]);
      expect(at(bytes, 0, 0), subtractedFromThePaper);
      expect(at(bytes, 3, 3), thePaper);
    });

    testWidgets('inside a folder\'s buffer it reads only what the folder '
        'holds', (tester) async {
      final bytes = await render(tester, [
        CompositeGroup<CanvasStackRow>(
          children: [blended(LayerBlendMode.subtract)],
          opacity: 1,
          blendMode: LayerBlendMode.normal,
        ),
      ]);
      expect(at(bytes, 0, 0), inkOverThePaper);
    });

    testWidgets('the paper is laid once: a thin one stays as thin', (
      tester,
    ) async {
      const thin = ProjectBackground.color(0x80808080);
      final control = await render(tester, [
        live(LayerBlendMode.normal),
      ], paper: thin);
      final bytes = await render(tester, [
        blended(LayerBlendMode.subtract),
      ], paper: thin);
      expect(at(bytes, 3, 3), at(control, 3, 3));
    });
  });
}
