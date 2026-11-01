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
import 'package:anicel/src/ui/playback/frame_picture_view.dart' show StackRun;
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';
import 'package:anicel/src/ui/playback/stacked_frame_picture.dart';

import '../../helpers/a_canvas_standing_on_a_frame.dart';
import '../../helpers/cels_kept_in_a_file.dart';

/// 🚨A FRAME MADE AHEAD FINDS THE FOLDER THE ONE BEFORE IT DREW (유저
/// 2026-11-01, F-529-Q1: 「거기서 굽는시간 최대한 단축하고싶음」): a walk went
/// through 47 frames of a cut whose lens-blurred folder changes at two of
/// them, and ran the blur at every one — two thirds of the bar.
void main() {
  const tileSize = 16;
  const canvasSize = CanvasSize(width: 300, height: 200);

  BrushFrameKey celOf(String layer, String frame) => BrushFrameKey(
    projectId: const ProjectId('p'),
    trackId: const TrackId('t'),
    cutId: const CutId('c'),
    layerId: LayerId(layer),
    frameId: FrameId(frame),
  );
  final inFolder = celOf('in-folder', 'first');
  final inFolderLater = celOf('in-folder', 'later');
  final moving = [celOf('moving', 'first'), celOf('moving', 'later')];

  /// A frame of the cut, on the row that changes at each.
  DemandedPicture frameAt(int index) => (
    cut: Cut(
      id: inFolder.cutId,
      name: 'Cut',
      duration: 2,
      canvasSize: canvasSize,
      layers: [
        for (final cels in [
          [inFolder, inFolderLater],
          moving,
        ])
          Layer(
            id: cels.first.layerId,
            name: 'Layer',
            frames: [
              for (final cel in cels)
                Frame(id: cel.frameId, duration: 1, strokes: const []),
            ],
            timeline: {
              for (final (at, cel) in cels.indexed)
                at: TimelineExposure.drawing(cel.frameId, length: 1),
            },
          ),
      ],
    ),
    frameIndex: index,
    paintPaper: false,
    ghosts: FrameGhosts.none,
  );

  BitmapSurface filled(int shade) => BitmapSurface(
    canvasSize: canvasSize,
    tileSize: tileSize,
    tiles: {
      TileCoord(x: 1, y: 1): BitmapTile(
        size: tileSize,
        pixels: Uint8List.fromList([
          for (var at = 0; at < tileSize * tileSize; at += 1) ...[
            shade,
            0x60,
            0x90,
            0xFF,
          ],
        ]),
      ),
    },
  );

  /// The row that changes at each frame, over a folder at half strength —
  /// one picture of its own — holding [folderCel] of that frame.
  List<CompositeNode<CanvasStackRow>> treeOf(
    DemandedPicture picture,
    BrushFrameKey Function(int frame) folderCel,
  ) => [
    CompositeLeaf(
      CanvasLayerImageRequest(frameKey: moving[picture.frameIndex], opacity: 1),
    ),
    CompositeGroup<CanvasStackRow>(
      children: [
        CompositeLeaf(
          CanvasLayerImageRequest(
            frameKey: folderCel(picture.frameIndex),
            opacity: 1,
          ),
        ),
      ],
      opacity: 0.5,
      blendMode: LayerBlendMode.normal,
      effects: const [],
    ),
  ];

  /// The frames' pictures, their folder holding [folderCel] of each frame.
  StackRun walkOver(BrushFrameKey Function(int frame) folderCel) {
    final cels = BrushFrameStore();
    keepInAFile(cels, {
      inFolder: filled(0x30),
      inFolderLater: filled(0xC0),
      moving.first: filled(0x10),
      moving.last: filled(0xE0),
    });
    final images = LayerFrameImageCache(frameStore: cels);
    addTearDown(images.dispose);
    final store = FramePictureStore<FramePictureKey>();
    addTearDown(store.dispose);
    final run = runOver(
      images,
      store,
      canvasSize: canvasSize,
      stackOf: (picture) => treeOf(picture, folderCel),
    );
    addTearDown(run.pictures.dispose);
    return run;
  }

  Future<void> madeAhead(StackRun run, int frame) async {
    expect(
      await run.pictures.make(frameAt(frame), shouldAbort: () => false),
      isTrue,
      reason: '⛔premise: made',
    );
  }

  testWidgets('a folder the next frame made ahead draws the same is not drawn '
      'again', (tester) async {
    await tester.runAsync(() async {
      final run = walkOver((_) => inFolder);
      debugSubtreeRasterCount = 0;

      await madeAhead(run, 0);
      expect(debugSubtreeRasterCount, 1, reason: '⛔premise: drawn');
      await madeAhead(run, 1);

      expect(debugSubtreeRasterCount, 1, reason: 'found');
    });
  });

  testWidgets('a folder the next frame draws another way is drawn, and only '
      'that frame\'s is held', (tester) async {
    await tester.runAsync(() async {
      final run = walkOver((frame) => frame == 0 ? inFolder : inFolderLater);
      debugSubtreeRasterCount = 0;

      await madeAhead(run, 0);
      await madeAhead(run, 1);

      expect(debugSubtreeRasterCount, 2);
      expect(run.pictures.aheadNodes, hasLength(1));
    });
  });

  testWidgets('a walk goes through what a canvas stands on: what it holds '
      'stays held, and nothing of the walk\'s is kept with it', (tester) async {
    await tester.runAsync(() async {
      final run = walkOver((frame) => frame == 0 ? inFolder : inFolderLater);
      final pictures = run.pictures;
      final stood = frameAt(0);
      await pictures.makeShown(
        pictures.stackOf(stood),
        stood,
        shouldAbort: () => false,
        keepsNodes: true,
      );
      final key = pictures.keyOfStack(pictures.stackOf(stood), stood);
      expect(pictures.heldNodes, hasLength(1), reason: '⛔premise');
      expect(pictures.aheadNodes, hasLength(0), reason: '⛔premise');

      await madeAhead(run, 1);

      expect(pictures.heldNodes, hasLength(1));
      expect(pictures.heldNodes.holdsAllOf(key), isTrue);
      expect(pictures.aheadNodes, hasLength(1));
    });
  });
}
