@Tags(['gpu'])
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/playback/frame_demand.dart'
    show DemandedPicture, FrameGhosts;
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/canvas/subtree_image_composite.dart';
import 'package:anicel/src/ui/playback/frame_picture_store.dart';
import 'package:anicel/src/ui/playback/frame_pictures.dart'
    show debugKeptFrameDraws;
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';
import 'package:anicel/src/ui/playback/stacked_frame_picture.dart';

import '../../helpers/a_canvas_standing_on_a_frame.dart';
import '../../helpers/cels_kept_in_a_file.dart';

/// 🚨A FRAME LAID A PIECE AT A TIME FOR THE CANVAS THAT STANDS ON IT HOLDS
/// ITS FOLDER, DRAWN WHOLE ONCE (card a-picture-lay-holds-the-raster-thread):
/// held at every piece, each piece let go of what the pieces before it held
/// and did not meet — a folder in a corner was let go of by the next piece,
/// and the canvas's strokes found nothing held. Laid at once, the frame is
/// drawn once, holding as it draws — as before pieces.
void main() {
  const tileSize = 16;
  // Three pieces across, the folder's ink in the first alone.
  const canvasSize = CanvasSize(width: 1100, height: 300);

  BrushFrameKey celOf(String layer) => BrushFrameKey(
    projectId: const ProjectId('p'),
    trackId: const TrackId('t'),
    cutId: const CutId('c'),
    layerId: LayerId(layer),
    frameId: const FrameId('f'),
  );
  final a = celOf('a');
  final b = celOf('b');
  final pen = celOf('pen');
  DemandedPicture frameOf(CanvasSize size) => (
    cut: Cut(
      id: a.cutId,
      name: 'Cut',
      duration: 1,
      canvasSize: size,
      layers: [
        for (final cel in [a, b, pen])
          Layer(
            id: cel.layerId,
            name: 'Layer',
            frames: [Frame(id: cel.frameId, duration: 1, strokes: const [])],
            timeline: {0: TimelineExposure.drawing(cel.frameId, length: 1)},
          ),
      ],
    ),
    frameIndex: 0,
    paintPaper: false,
    ghosts: FrameGhosts.none,
  );

  BitmapSurface filled(List<int> colour, CanvasSize size) => BitmapSurface(
    canvasSize: size,
    tileSize: tileSize,
    tiles: {
      TileCoord(x: 1, y: 1): BitmapTile(
        size: tileSize,
        pixels: Uint8List.fromList([
          for (var at = 0; at < tileSize * tileSize; at += 1) ...colour,
        ]),
      ),
    },
  );

  /// Two rows in a folder at half strength — one picture of its own — over
  /// the row a pen is on.
  List<CompositeNode<CanvasStackRow>> treeOf() => [
    CompositeLeaf<CanvasStackRow>(
      CanvasActiveLayerRow(opacity: 1, frameKey: pen),
    ),
    CompositeGroup<CanvasStackRow>(
      children: [
        CompositeLeaf(CanvasLayerImageRequest(frameKey: a, opacity: 1)),
        CompositeLeaf(CanvasLayerImageRequest(frameKey: b, opacity: 0.6)),
      ],
      opacity: 0.5,
      blendMode: LayerBlendMode.normal,
      effects: const [],
    ),
  ];

  /// The canvas standing on [frame] of [size], laid for it; what the store
  /// laid.
  Future<({FramePicture? laid, HeldSubtreeRasters held})> standOn(
    CanvasSize size,
  ) async {
    final cels = BrushFrameStore();
    keepInAFile(cels, {
      a: filled(const [0x30, 0x60, 0x90, 0xFF], size),
      b: filled(const [0x90, 0x30, 0x10, 0xFF], size),
    });
    final images = LayerFrameImageCache(frameStore: cels);
    addTearDown(images.dispose);
    final store = FramePictureStore<FramePictureKey>();
    addTearDown(store.dispose);
    final run = runOver(
      images,
      store,
      canvasSize: size,
      stackOf: (_) => treeOf(),
    );
    final shown = frameOf(size);
    debugSubtreeRasterCount = 0;
    debugKeptFrameDraws = 0;
    await run.pictures.makeShown(
      treeOf(),
      shown,
      shouldAbort: () => false,
      keepsNodes: true,
    );
    return (
      laid: store.peek(run.pictures.keyOfStack(treeOf(), shown)),
      held: run.pictures.heldNodes,
    );
  }

  testWidgets('laid a piece at a time for the canvas that stands on it, the '
      'frame holds its folder — drawn whole once, each piece cut from it', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final (:laid, :held) = await standOn(canvasSize);

      expect(
        laid?.extent.width,
        greaterThan(512),
        reason: '⛔premise: laid in more than one piece',
      );
      expect(held, hasLength(1), reason: 'the folder');
      expect(debugSubtreeRasterCount, 1, reason: 'drawn whole once');
      // The store's pieces are 512 a side.
      final pieces =
          (laid!.extent.width / 512).ceil() * (laid.extent.height / 512).ceil();
      expect(
        debugKeptFrameDraws,
        1 + pieces,
        reason: 'whole into nothing once, then each piece',
      );
    });
  }, skip: noFlutterGpu != null);

  testWidgets('laid at once for the canvas that stands on it, the frame is '
      'drawn once, holding its folder as it draws it', (tester) async {
    await tester.runAsync(() async {
      final (:laid, :held) = await standOn(
        const CanvasSize(width: 300, height: 200),
      );

      expect(
        laid?.extent.width,
        lessThanOrEqualTo(512),
        reason: '⛔premise: laid in one piece',
      );
      expect(held, hasLength(1), reason: 'the folder');
      expect(debugSubtreeRasterCount, 1);
      expect(
        debugKeptFrameDraws,
        1,
        reason: '🚨drawn twice, the frame on screen was recorded twice a lay',
      );
    });
  }, skip: noFlutterGpu != null);
}
