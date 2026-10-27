import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/transform_pose.dart';
import 'package:anicel/src/services/camera_frame_corners.dart';
import 'package:anicel/src/services/cut_frame_composite_plan.dart';
import 'package:anicel/src/services/layer_pose_matrix.dart';
import 'package:anicel/src/ui/camera/camera_frame_render_service.dart';
import 'package:anicel/src/ui/canvas/subtree_image_composite.dart';

import '../../helpers/placement_reading.dart';

/// 🎯A FOLDER THE CAMERA SHOWS IS BUFFERED AT WHAT OF IT IS IN SHOT (card
/// export-folders-and-rows-at-their-extent) — the editing stack's law
/// ([subtreeBufferBounds]), where the camera used to buffer the square
/// that covers its frame at any turn: 2.1× a 2340×1654 canvas, a folder.
/// And a folder inside a folder is buffered at what the outer one reads,
/// which its blur reads past the shot.
void main() {
  const canvasSize = CanvasSize(width: 64, height: 48);

  /// Ink filling the tile at ([x], [y]) of the canvas's 16-pixel grid.
  BitmapSurface inkAt(int x, int y) {
    final pixels = Uint8List(16 * 16 * 4);
    for (var i = 0; i < pixels.length; i += 4) {
      pixels[i] = 40;
      pixels[i + 1] = 90;
      pixels[i + 2] = 200;
      pixels[i + 3] = 255;
    }
    return BitmapSurface(
      canvasSize: canvasSize,
      tileSize: 16,
      tiles: {TileCoord(x: x, y: y): BitmapTile(size: 16, pixels: pixels)},
    );
  }

  CompositeNode<CutFrameCompositeLayer> row(
    BitmapSurface surface, {
    LayerPlacement? placement,
  }) => CompositeLeaf(
    CutFrameCompositeLayer(surface: surface, opacity: 1, placement: placement),
  );

  CompositeNode<CutFrameCompositeLayer> folder(
    List<CompositeNode<CutFrameCompositeLayer>> children, {
    List<ResolvedLayerEffect> effects = const [],
  }) => CompositeGroup(
    children: children,
    opacity: 1,
    blendMode: LayerBlendMode.normal,
    effects: effects,
  );

  final blur = [ResolvedLayerEffect(kind: EffectKind.blur, values: [4, 0])];

  const service = CameraFrameRenderService();

  Future<Uint8List> render(
    List<CompositeNode<CutFrameCompositeLayer>> nodes,
    CameraView view,
  ) async {
    final image = await service.renderThroughCamera(
      nodes: nodes,
      pose: view.pose,
      cameraFrameSize: view.frameSize,
    );
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    return data!.buffer.asUint8List();
  }

  /// The rect the last folder's buffer was asked to cover.
  Future<Rect> bufferOf(
    List<CompositeNode<CutFrameCompositeLayer>> nodes,
    CameraView view,
  ) async {
    debugLastSubtreeRaster = null;
    await render(nodes, view);
    return debugLastSubtreeRaster!.bounds;
  }

  Matcher near(Rect rect) => isA<Rect>()
      .having((r) => r.left, 'left', closeTo(rect.left, 1e-3))
      .having((r) => r.top, 'top', closeTo(rect.top, 1e-3))
      .having((r) => r.right, 'right', closeTo(rect.right, 1e-3))
      .having((r) => r.bottom, 'bottom', closeTo(rect.bottom, 1e-3));

  final inFolder = folder([row(inkAt(1, 1))]);
  final whole = cameraViewOver(canvasSize.canvasRect);
  final part = cameraViewOver(const Rect.fromLTWH(10, 7, 40, 30));
  for (final (says, node, view, bounds) in <(
    String,
    CompositeNode<CutFrameCompositeLayer>,
    CameraView,
    Rect,
  )>[
    (
      'a camera square over a part of the canvas: that part',
      inFolder,
      part,
      const Rect.fromLTRB(10, 7, 50, 37),
    ),
    (
      'a camera reaching past the canvas: the canvas part of its shot',
      inFolder,
      cameraViewOver(const Rect.fromLTWH(40, 30, 40, 30)),
      const Rect.fromLTRB(40, 30, 64, 48),
    ),
    (
      'a turned camera: the box around its turned frame',
      inFolder,
      (
        pose: CameraPose(
          center: CanvasPoint(x: 32, y: 24),
          rotationDegrees: 30,
        ),
        frameSize: const CanvasSize(width: 40, height: 30),
      ),
      // 20·cos 30° + 15·sin 30° across, 20·sin 30° + 15·cos 30° down.
      const Rect.fromLTRB(7.1795, 1.0096, 56.8205, 46.9904),
    ),
    (
      'a camera over the whole canvas: the rect its row stands for, not '
          'the ink in it',
      inFolder,
      whole,
      const Rect.fromLTRB(0, 0, 64, 48),
    ),
    (
      'a row moved half the canvas across: where its placement puts it',
      folder([
        row(
          inkAt(1, 1),
          placement: placedBy(
            TransformPose(center: CanvasPoint(x: 64, y: 24)),
            canvasSize,
          ),
        ),
      ]),
      whole,
      const Rect.fromLTRB(32, 0, 64, 48),
    ),
    (
      // Neither the shot (10, 7, 50, 37) nor the row (32, 0, 96, 48) alone.
      'an adjustment over a moved row through a camera over a part: what '
          'of the row is in shot',
      CompositeAdjustment(
        children: [
          row(
            inkAt(1, 1),
            placement: placedBy(
              TransformPose(center: CanvasPoint(x: 64, y: 24)),
              canvasSize,
            ),
          ),
        ],
        effects: [
          ResolvedLayerEffect(
            kind: EffectKind.brightnessContrast,
            values: [20, 0],
          ),
        ],
        mix: 1,
      ),
      part,
      const Rect.fromLTRB(32, 7, 50, 37),
    ),
  ]) {
    testWidgets('🎯$says', (tester) async {
      await tester.runAsync(() async {
        expect(await bufferOf([node], view), near(bounds));
      });
    });
  }

  group('🎯a folder inside one whose blur reads past the shot is buffered '
      'at what the outer one reads — the same bytes as its rows drawn '
      'straight into it', () {
    // The ink lies left of the shot, as near as the blur reaches.
    final view = cameraViewOver(const Rect.fromLTWH(16, 16, 32, 16));
    final ink = inkAt(0, 1);

    testWidgets('a folder', (tester) async {
      await tester.runAsync(() async {
        final straight = await render([
          folder([row(ink)], effects: blur),
        ], view);
        final nested = await render([
          folder([
            folder([row(ink)]),
          ], effects: blur),
        ], view);

        expect(
          straight.any((byte) => byte != 255),
          isTrue,
          reason: 'LIVENESS: the blur reaches into the shot',
        );
        expect(nested, straight);
      });
    });

    testWidgets('an adjustment', (tester) async {
      await tester.runAsync(() async {
        final straight = await render([
          CompositeAdjustment(children: [row(ink)], effects: blur, mix: 1),
        ], view);
        final nested = await render([
          CompositeAdjustment(
            children: [
              folder([row(ink)]),
            ],
            effects: blur,
            mix: 1,
          ),
        ], view);

        expect(
          straight.any((byte) => byte != 255),
          isTrue,
          reason: 'LIVENESS: the blur reaches into the shot',
        );
        expect(nested, straight);
      });
    });
  });
}
