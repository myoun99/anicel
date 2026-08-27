import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/cut_frame_composite_plan.dart';
import 'package:anicel/src/ui/camera/camera_frame_render_service.dart';
import 'package:anicel/src/ui/canvas/subtree_image_composite.dart';

/// 🚨★★★EVERY ROUTE COMPOSITES A GROUP THE SAME WAY.
///
/// Three walks composite the same tree — the editing stack, the camera (which
/// the export renders through) and the playback cache. Moving only one of
/// them to a `ui.Image` would not have been a smaller version of the change;
/// it would have BEEN the asymmetry, because a folder that is samplable on
/// screen and a `saveLayer` in the file is how the screen starts lying.
///
/// ⚠️Nothing about "they all call the same function" shows up in a pixel
/// comparison — three identical implementations pass every parity test and
/// then drift one commit at a time. This reads the source.
void main() {
  const canvasSize = CanvasSize(width: 8, height: 8);

  BitmapSurface inkedSurface() {
    final pixels = Uint8List(8 * 8 * 4);
    const offset = (2 * 8 + 2) * 4;
    pixels[offset] = 255;
    pixels[offset + 3] = 255;
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

  /// The three files that walk a composite tree and buffer a sub-tree.
  const walks = <String>[
    'lib/src/ui/canvas/canvas_layer_stack_view.dart',
    'lib/src/ui/camera/camera_frame_render_service.dart',
    'lib/src/ui/playback/cut_frame_composite_cache.dart',
  ];

  /// What each walk is still allowed to open a `saveLayer` for, and why.
  ///
  /// ⛔A RATCHET. Every one of these is an alpha group over draws of an image
  /// that ALREADY EXISTS — nothing downstream needs to sample it — which is
  /// the only reason a layer is still the right tool there. A new saveLayer
  /// that buffers a SUB-TREE has to argue itself into this table in the same
  /// commit, and the argument has to be that nothing will ever want to read
  /// its pixels.
  const allowedSaveLayers = <String, int>{
    // 1: the adjustment crossfade's alpha group.
    // 2: the ACTIVE SURFACE's own buffer — a leaf, not a sub-tree, and its
    //    bounds are the pasteboard (9x the canvas), so converting it wants
    //    the "content ∩ view" bound applied there first.
    'lib/src/ui/canvas/canvas_layer_stack_view.dart': 2,
    // The adjustment crossfade's alpha group.
    'lib/src/ui/camera/camera_frame_render_service.dart': 1,
    'lib/src/ui/playback/cut_frame_composite_cache.dart': 1,
  };

  List<String> codeLines(String path) {
    final lines = File(path).readAsLinesSync();
    return [
      for (final line in lines)
        if (!line.trimLeft().startsWith('//') && !line.trimLeft().startsWith('///'))
          line,
    ];
  }

  test('all three walks buffer a sub-tree through the one shared function', () {
    for (final path in walks) {
      final source = codeLines(path).join('\n');
      expect(
        source.contains('drawSubtreeAsImage'),
        isTrue,
        reason: '$path composites a tree but does not use the shared raster',
      );
      expect(
        source.contains('maxSubtreeRasterSide'),
        isTrue,
        reason: '$path must not invent its own cap — the three walks '
            'disagreeing about how big a folder may get is the same bug in '
            'a different coat',
      );
    }
  });

  test('no walk has grown a new sub-tree saveLayer', () {
    for (final path in walks) {
      final count = codeLines(
        path,
      ).where((line) => line.contains('saveLayer(')).length;
      expect(
        count,
        allowedSaveLayers[path],
        reason: 'saveLayer count changed in $path. A saveLayer offscreen '
            'cannot be sampled, so buffering a sub-tree in one is what makes '
            'a folder effect impossible. If this new one is an alpha group '
            'over an existing image, say so in allowedSaveLayers in the same '
            'commit; otherwise route it through drawSubtreeAsImage.',
      );
    }
  });

  testWidgets('the camera rasterises a folder at its projection scale', (
    tester,
  ) async {
    await tester.runAsync(() async {
      // 🚨THE WIRE, READ AT THE ROUTE. The camera's CTM is
      // `previewScale * zoom`, and a `Canvas` will not say so — the walk
      // carries the number. Cut that wire and the folder still draws, at a
      // resolution nobody chose, next to siblings drawn at the right one.
      debugLastSubtreeRaster = null;
      const service = CameraFrameRenderService(
        filterQuality: FilterQuality.none,
      );
      final image = await service.renderThroughCamera(
        nodes: [
          CutFrameCompositeSurfaceGroup(
            children: [
              CutFrameCompositeSurfaceLeaf(
                CutFrameCompositeLayer(surface: inkedSurface(), opacity: 1),
              ),
            ],
            opacity: 1,
            // A folder only becomes a group node when it NEEDS the buffer.
            blendMode: LayerBlendMode.multiply,
          ),
        ],
        pose: CameraPose(center: CanvasPoint(x: 4, y: 4), zoom: 2),
        cameraFrameSize: canvasSize,
        // 32 / 8 = a preview scale of 4, times a camera zoom of 2.
        outputSize: const CanvasSize(width: 32, height: 32),
      );
      expect(
        debugLastSubtreeRaster,
        isNotNull,
        reason: 'the folder never rasterised at all',
      );
      expect(debugLastSubtreeRaster!.scale, 8);
      image.dispose();
    });
  });
}
