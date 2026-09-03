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
import '../../helpers/library_source.dart';

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
  /// ⛔A RATCHET, and the rule is not "no saveLayers" — it is that a
  /// saveLayer may not contain a WALK OF THE TREE. Every one of these
  /// contains a blit of an image that already exists, so there is nothing in
  /// it a folder effect could have needed to sample. A new one has to argue
  /// itself into this table in the same commit, and the argument has to be
  /// that the children are not painted inside it.
  ///
  /// 🧪An adjustment's passes still open layers — restoring a layer into the
  /// pass's paint and blitting with that paint round differently, and a
  /// crossfade ADDS two passes (measured at 2/255 over 488 pixels) — but
  /// those layers live in `composeAdjustmentScope`, in ONE copy. A walk
  /// holding its own copy is how a mutation that fed the FILTERED paint to
  /// the unfiltered pass survived every test in the repo.
  const allowedSaveLayers = <String, int>{
    // The ACTIVE SURFACE's own buffer, and it STAYS a saveLayer. ⛔Not a
    // to-do — 🧪the numbers, on a 2340x1654 page whose pasteboard hint is
    // 7020x4962, output 1200x800, 20 runs after warm-up:
    //
    //   saveLayer(pasteboard)                    1245us
    //   saveLayer(content∩view 1200x800)         1321us   <- same, noise
    //   toImageSync(content∩view 1200x800)+blit  4268us   <- 3.2x
    //   toImageSync(pasteboard)+blit            40478us   <- 32.5x
    //
    // Two things fall out. A saveLayer's bounds are a HINT Skia takes the
    // intersection of with the current clip, so the alarming-looking
    // pasteboard rect costs the same as a tight one — measured, not
    // reasoned. And `toImageSync` allocates exactly what it is asked for,
    // so converting costs 3.2x even AFTER fixing the bound.
    //
    // A group was worth that; this is not. A group's pixels are what a
    // folder effect has to sample, and converting it put four routes on one
    // code path. The live layer is a LEAF: there is no sub-tree inside it,
    // and its own colour key runs on the CPU over its source bytes anyway
    // (EffectKind.runsOnSourcePixels), so the conversion would buy
    // uniformity alone — on the path a stroke redraws every step.
    //
    // ⚠️Software rasteriser (flutter_tester). The RATIO is what travels; the
    // absolute numbers do not.
    'lib/src/ui/canvas/canvas_layer_stack_view.dart': 1,
    'lib/src/ui/camera/camera_frame_render_service.dart': 0,
    'lib/src/ui/playback/cut_frame_composite_cache.dart': 0,
  };

  List<String> codeLines(String path) {
    // The library, host and parts: the stack view keeps its paint in a
    // part since the Round 6 cut.
    final lines = librarySource(path).split('\n');
    return [
      for (final line in lines)
        if (!line.trimLeft().startsWith('//') &&
            !line.trimLeft().startsWith('///'))
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
        source.contains('maxPixelSide'),
        isFalse,
        reason:
            '$path must not ARGUE about the cap. It is the parameter '
            'DEFAULT now, which holds tighter than three routes spelling '
            'one constant correctly: a route that wanted a different cap '
            'would have to write an argument, and none of them may.',
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
        reason:
            'saveLayer count changed in $path. A saveLayer offscreen '
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
