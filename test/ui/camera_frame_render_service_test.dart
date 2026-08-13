import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/services/cut_frame_composite_plan.dart';
import 'package:anicel/src/ui/camera/camera_frame_render_service.dart';

void main() {
  const canvasSize = CanvasSize(width: 8, height: 8);

  /// An 8×8 surface with one opaque red pixel at (x, y).
  BitmapSurface surfaceWithRedPixelAt(int x, int y, {int alpha = 255}) {
    final pixels = Uint8List(8 * 8 * 4);
    final offset = (y * 8 + x) * 4;
    pixels[offset] = 255;
    pixels[offset + 3] = alpha;
    return BitmapSurface(
      canvasSize: canvasSize,
      tileSize: 8,
      tiles: {
        TileCoord(x: 0, y: 0): BitmapTile(
          coord: TileCoord(x: 0, y: 0),
          size: 8,
          pixels: pixels,
        ),
      },
    );
  }

  Future<Color> pixelAt(ui.Image image, int x, int y) async {
    final data = await image.toByteData();
    final offset = (y * image.width + x) * 4;
    return Color.fromARGB(
      data!.getUint8(offset + 3),
      data.getUint8(offset),
      data.getUint8(offset + 1),
      data.getUint8(offset + 2),
    );
  }

  const service = CameraFrameRenderService(filterQuality: FilterQuality.none);

  test('file names are 1-based and zero padded', () {
    expect(cameraSequenceFileName(0), 'frame_0001.png');
    expect(cameraSequenceFileName(11), 'frame_0012.png');
  });

  /// One red pixel in the tile to the LEFT of the canvas: local (7,2) of the
  /// tile at x = -1 is world (-1, 2).
  BitmapSurface surfaceWithParkedRedPixel() {
    final pixels = Uint8List(8 * 8 * 4);
    const offset = (2 * 8 + 7) * 4;
    pixels[offset] = 255;
    pixels[offset + 3] = 255;
    return BitmapSurface(
      canvasSize: canvasSize,
      tileSize: 8,
      tiles: {
        TileCoord(x: -1, y: 0): BitmapTile(
          coord: TileCoord(x: -1, y: 0),
          size: 8,
          pixels: pixels,
        ),
      },
    );
  }

  testWidgets('artwork parked OFF canvas and posed INTO frame reaches the '
      'render — the crop is after the pose, as it already is in playback', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final image = await service.renderThroughCamera(
        layers: [
          CutFrameCompositeLayer(
            surface: surfaceWithParkedRedPixel(),
            opacity: 1,
            // The anchor is the canvas centre (4,4), so this translates the
            // layer +2 in x: world (-1,2) lands on (1,2).
            pose: TransformPose(center: CanvasPoint(x: 6, y: 4)),
          ),
        ],
        pose: CameraPose(center: CanvasPoint(x: 4, y: 4)),
        cameraFrameSize: canvasSize,
      );

      expect(
        await pixelAt(image, 1, 2),
        const Color(0xFFFF0000),
        reason:
            'This route composed each layer at the CANVAS extent, so the '
            'pasteboard tile was thrown away BEFORE the pose ran and the '
            'artwork the pose brought into frame was on screen but missing '
            'from the file. Playback has always cropped after the pose; that '
            'is what made the two disagree about the same frame.',
      );
      expect(
        await pixelAt(image, 5, 5),
        const Color(0xFFFFFFFF),
        reason: 'and nothing else moved',
      );
    });
  });

  testWidgets('artwork the pose does NOT bring in is still cropped', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final image = await service.renderThroughCamera(
        layers: [
          CutFrameCompositeLayer(
            surface: surfaceWithParkedRedPixel(),
            opacity: 1,
          ),
        ],
        pose: CameraPose(center: CanvasPoint(x: 4, y: 4)),
        cameraFrameSize: canvasSize,
      );

      for (var y = 0; y < 8; y += 1) {
        for (var x = 0; x < 8; x += 1) {
          expect(
            await pixelAt(image, x, y),
            const Color(0xFFFFFFFF),
            reason:
                'The output is still canvas-sized: what changed is WHEN the '
                'crop happens, not whether. 유저 확정: 「페이스트보드는 포함 '
                '안 시킴」 — off-canvas artwork no pose brings in stays out '
                'of the file. ($x,$y)',
          );
        }
      }
    });
  });

  testWidgets('identity pose maps canvas pixels 1:1 onto the output', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final image = await service.renderThroughCamera(
        layers: [
          CutFrameCompositeLayer(
            surface: surfaceWithRedPixelAt(1, 2),
            opacity: 1,
          ),
        ],
        pose: CameraPose(center: CanvasPoint(x: 4, y: 4)),
        cameraFrameSize: canvasSize,
      );

      expect(image.width, 8);
      expect(image.height, 8);
      expect(await pixelAt(image, 1, 2), const Color(0xFFFF0000));
      expect(await pixelAt(image, 5, 5), const Color(0xFFFFFFFF));
      image.dispose();
    });
  });

  testWidgets('background fills the area beyond the canvas edges', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final image = await service.renderThroughCamera(
        layers: const [],
        // Camera centered at the canvas corner: most of the view is outside.
        pose: CameraPose(center: CanvasPoint(x: 0, y: 0)),
        cameraFrameSize: canvasSize,
      );

      expect(await pixelAt(image, 0, 0), const Color(0xFFFFFFFF));
      expect(await pixelAt(image, 7, 7), const Color(0xFFFFFFFF));
      image.dispose();
    });
  });

  testWidgets('a layer transform pose shifts the layer under the identity '
      'camera (composite-time apply)', (tester) async {
    await tester.runAsync(() async {
      final image = await service.renderThroughCamera(
        layers: [
          CutFrameCompositeLayer(
            surface: surfaceWithRedPixelAt(1, 2),
            opacity: 1,
            // The layer's anchor (canvas center 4,4) lands at (6,5):
            // content translates by (+2, +1).
            pose: CameraPose(center: CanvasPoint(x: 6, y: 5)),
          ),
        ],
        pose: CameraPose(center: CanvasPoint(x: 4, y: 4)),
        cameraFrameSize: canvasSize,
      );

      expect(await pixelAt(image, 3, 3), const Color(0xFFFF0000));
      expect(await pixelAt(image, 1, 2), const Color(0xFFFFFFFF));
      image.dispose();
    });
  });

  testWidgets('camera zoom 2 magnifies around the pose center', (tester) async {
    await tester.runAsync(() async {
      final image = await service.renderThroughCamera(
        layers: [
          CutFrameCompositeLayer(
            surface: surfaceWithRedPixelAt(3, 3),
            opacity: 1,
          ),
        ],
        pose: CameraPose(center: CanvasPoint(x: 4, y: 4), zoom: 2),
        cameraFrameSize: canvasSize,
      );

      // Canvas pixel (3,3)..(4,4) maps to output (4 + 2*(3-4)) = 2..4:
      // the red canvas pixel covers the 2×2 output block at (2,2).
      expect(await pixelAt(image, 2, 2), const Color(0xFFFF0000));
      expect(await pixelAt(image, 3, 3), const Color(0xFFFF0000));
      expect(await pixelAt(image, 4, 4), isNot(const Color(0xFFFF0000)));
      image.dispose();
    });
  });

  testWidgets('clockwise camera rotation rotates the world the opposite way', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final image = await service.renderThroughCamera(
        layers: [
          CutFrameCompositeLayer(
            // One pixel right of center: canvas (5..6, 4..5).
            surface: surfaceWithRedPixelAt(5, 4),
            opacity: 1,
          ),
        ],
        pose: CameraPose(center: CanvasPoint(x: 4, y: 4), rotationDegrees: 90),
        cameraFrameSize: canvasSize,
      );

      // Camera rotated 90° clockwise: what was to the canvas-right of center
      // appears above the output center. Canvas rect (5,4)-(6,5) maps through
      // R(-90): corners (1,0)&(2,1) → output rect (0,-2)-(1,-1) + center
      // = (4,2)-(5,3), so output pixel (4,2) is red.
      expect(await pixelAt(image, 4, 2), const Color(0xFFFF0000));
      expect(await pixelAt(image, 5, 4), const Color(0xFFFFFFFF));
      image.dispose();
    });
  });

  testWidgets('R6: a layer effect filters its own picture on this route', (
    tester,
  ) async {
    await tester.runAsync(() async {
      // Mid-grey pixel, brightened +20 (= +51 of full scale). This is the
      // camera/export/thumbnail route, so it proves the chain travels the
      // whole way — plan field to painted pixel.
      final pixels = Uint8List(8 * 8 * 4);
      const offset = (2 * 8 + 2) * 4;
      pixels[offset] = 0x80;
      pixels[offset + 1] = 0x80;
      pixels[offset + 2] = 0x80;
      pixels[offset + 3] = 255;
      final image = await service.renderThroughCamera(
        layers: [
          CutFrameCompositeLayer(
            surface: BitmapSurface(
              canvasSize: canvasSize,
              tileSize: 8,
              tiles: {
                TileCoord(x: 0, y: 0): BitmapTile(
                  coord: TileCoord(x: 0, y: 0),
                  size: 8,
                  pixels: pixels,
                ),
              },
            ),
            opacity: 1,
            effects: resolveLayerEffectsAt(
              effects: [
                LayerEffect(
                  id: const EffectId('fx'),
                  kind: EffectKind.brightnessContrast,
                  parameters: {'brightness': EffectParameter(value: 20)},
                ),
              ],
              frameIndex: 0,
            ),
          ),
        ],
        pose: CameraPose(center: CanvasPoint(x: 4, y: 4)),
        cameraFrameSize: canvasSize,
      );

      final filtered = await pixelAt(image, 2, 2);
      expect(
        (filtered.r * 255).round(),
        inInclusiveRange(0x80 + 49, 0x80 + 53),
      );
      expect(filtered.a, 1.0);
      image.dispose();
    });
  });

  testWidgets('R6: a GROUP effect lands once on the buffer, and a panned '
      'camera does not clip the group', (tester) async {
    await tester.runAsync(() async {
      // The old group bounds were the camera frame at the canvas ORIGIN, so
      // a camera panned away from it clipped members the view plainly
      // showed. Camera centered at (6,6) with a member at (6,6): visible.
      final image = await service.renderThroughCamera(
        nodes: [
          CutFrameCompositeSurfaceGroup(
            children: [
              CutFrameCompositeSurfaceLeaf(
                CutFrameCompositeLayer(
                  surface: surfaceWithRedPixelAt(6, 6),
                  opacity: 1,
                ),
              ),
            ],
            opacity: 1,
            blendMode: LayerBlendMode.normal,
            effects: resolveLayerEffectsAt(
              effects: [
                LayerEffect(
                  id: const EffectId('fx'),
                  kind: EffectKind.hueSaturation,
                  // Fully desaturated: the red member must come out grey.
                  parameters: {'saturation': EffectParameter(value: -100)},
                ),
              ],
              frameIndex: 0,
            ),
          ),
        ],
        pose: CameraPose(center: CanvasPoint(x: 6, y: 6)),
        cameraFrameSize: canvasSize,
      );

      // The member sits at the output center under this pose.
      final greyed = await pixelAt(image, 4, 4);
      expect(
        greyed.a,
        1.0,
        reason: 'the group must not be clipped away by its buffer bounds',
      );
      expect(
        (greyed.r * 255).round(),
        (greyed.g * 255).round(),
        reason: 'desaturated: every channel equal',
      );
      expect((greyed.r * 255).round(), lessThan(200));
      image.dispose();
    });
  });

  testWidgets('layer opacity blends into the background', (tester) async {
    await tester.runAsync(() async {
      final image = await service.renderThroughCamera(
        layers: [
          CutFrameCompositeLayer(
            surface: surfaceWithRedPixelAt(1, 1),
            opacity: 0.5,
          ),
        ],
        pose: CameraPose(center: CanvasPoint(x: 4, y: 4)),
        cameraFrameSize: canvasSize,
      );

      final blended = await pixelAt(image, 1, 1);
      // 50% red over white: red stays near 255, green/blue drop to ~127.
      expect((blended.r * 255).round(), inInclusiveRange(250, 255));
      expect((blended.g * 255).round(), inInclusiveRange(120, 135));
      expect((blended.b * 255).round(), inInclusiveRange(120, 135));
      image.dispose();
    });
  });

  testWidgets('smaller output renders the same view scaled down', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final image = await service.renderThroughCamera(
        layers: [
          CutFrameCompositeLayer(
            // Left half red? Just one pixel; use scale factor 0.5:
            surface: surfaceWithRedPixelAt(2, 2),
            opacity: 1,
          ),
        ],
        pose: CameraPose(center: CanvasPoint(x: 4, y: 4)),
        cameraFrameSize: canvasSize,
        outputSize: const CanvasSize(width: 4, height: 4),
      );

      expect(image.width, 4);
      expect(image.height, 4);
      // Canvas pixel (2..3) maps to output (1..1.5): probe (1,1).
      expect(await pixelAt(image, 1, 1), isNot(const Color(0xFFFFFFFF)));
      image.dispose();
    });
  });
}
