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
import 'package:anicel/src/ui/playback/frame_pictures.dart'
    show debugKeptFrameDraws;
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';
import 'package:anicel/src/ui/playback/stacked_frame_picture.dart';

import '../../helpers/a_canvas_standing_on_a_frame.dart';
import '../../helpers/cels_kept_in_a_file.dart';

/// 🚨A FRAME MADE AHEAD FINDS THE FOLDER THE ONE BEFORE IT DREW (유저
/// 2026-11-01, F-529-Q1: 「거기서 굽는시간 최대한 단축하고싶음」): a walk went
/// through 47 frames of a cut whose lens-blurred folder changes at two of
/// them, and ran the blur at every one — two thirds of the bar. A frame
/// draws a folder whole only for the picture after it: drawn whole it holds
/// the raster thread through its chain, and one nothing finds was that for
/// nothing.
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
  final still = celOf('still', 'first');
  final inFolder = celOf('in-folder', 'first');
  final inFolderLater = celOf('in-folder', 'later');
  final moving = [
    for (final frame in ['a', 'b', 'c', 'd']) celOf('moving', frame),
  ];

  /// A frame of the cut, on the row that changes at each.
  DemandedPicture frameAt(int index) => (
    cut: Cut(
      id: inFolder.cutId,
      name: 'Cut',
      duration: moving.length,
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

  CompositeNode<CanvasStackRow> rowOf(BrushFrameKey cel) =>
      CompositeLeaf(CanvasLayerImageRequest(frameKey: cel, opacity: 1));

  /// [children] below full strength: one picture of their own.
  CompositeNode<CanvasStackRow> folderOf(
    List<CompositeNode<CanvasStackRow>> children, {
    double strength = 0.5,
  }) => CompositeGroup<CanvasStackRow>(
    children: children,
    opacity: strength,
    blendMode: LayerBlendMode.normal,
    effects: const [],
  );

  /// A row no frame changes and the row that changes at each, over a folder
  /// holding [folderCel] of that frame.
  List<CompositeNode<CanvasStackRow>> treeOf(
    DemandedPicture picture,
    BrushFrameKey Function(int frame) folderCel,
  ) => [
    rowOf(still),
    rowOf(moving[picture.frameIndex]),
    folderOf([rowOf(folderCel(picture.frameIndex))]),
  ];

  /// The frames' pictures, stacked as [stackOf] stacks them.
  StackRun walkOf(
    List<CompositeNode<CanvasStackRow>> Function(DemandedPicture) stackOf,
  ) {
    final cels = BrushFrameStore();
    keepInAFile(cels, {
      still: filled(0x70),
      inFolder: filled(0x30),
      inFolderLater: filled(0xC0),
      for (final (at, cel) in moving.indexed) cel: filled(0x10 + 0x40 * at),
    });
    final images = LayerFrameImageCache(frameStore: cels);
    addTearDown(images.dispose);
    final store = FramePictureStore<FramePictureKey>();
    addTearDown(store.dispose);
    final run = runOver(
      images,
      store,
      canvasSize: canvasSize,
      stackOf: stackOf,
    );
    addTearDown(run.pictures.dispose);
    debugSubtreeRasterCount = 0;
    debugKeptFrameDraws = 0;
    return run;
  }

  /// The frames' pictures, their folder holding [folderCel] of each frame.
  StackRun walkOver(BrushFrameKey Function(int frame) folderCel) =>
      walkOf((picture) => treeOf(picture, folderCel));

  Future<void> madeAhead(StackRun run, int frame) async {
    expect(
      await run.pictures.make(frameAt(frame), shouldAbort: () => false),
      isTrue,
      reason: '⛔premise: made',
    );
  }

  testWidgets('a folder the next picture draws the same is drawn once, and '
      'the frames after it draw nothing whole', (tester) async {
    await tester.runAsync(() async {
      final run = walkOver((_) => inFolder);

      await madeAhead(run, 0);
      expect(debugSubtreeRasterCount, 1, reason: '⛔premise: drawn');
      expect(debugKeptFrameDraws, 1, reason: '⛔premise: to be held');
      await madeAhead(run, 1);
      await madeAhead(run, 2);

      expect(debugSubtreeRasterCount, 1, reason: 'found');
      expect(debugKeptFrameDraws, 1, reason: 'held already');
    });
  });

  testWidgets('🚨a folder the next picture lays at another strength is the '
      'same picture: drawn once, and the frames after it draw nothing whole', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final run = walkOf(
        (picture) => [
          rowOf(still),
          rowOf(moving[picture.frameIndex]),
          folderOf([
            rowOf(inFolder),
          ], strength: 0.2 + 0.2 * picture.frameIndex),
        ],
      );

      await madeAhead(run, 0);
      expect(debugKeptFrameDraws, 1, reason: '⛔premise: to be held');
      await madeAhead(run, 1);
      await madeAhead(run, 2);

      expect(debugSubtreeRasterCount, 1, reason: 'found');
      expect(debugKeptFrameDraws, 1, reason: 'held already');
    });
  });

  testWidgets('🚨a folder the next picture draws another way is not drawn '
      'whole to be held: nothing would find it', (tester) async {
    await tester.runAsync(() async {
      final run = walkOver((frame) => frame < 2 ? inFolder : inFolderLater);

      await madeAhead(run, 1);

      expect(debugSubtreeRasterCount, 1, reason: '⛔premise: drawn');
      expect(debugKeptFrameDraws, 0);
      expect(run.pictures.aheadNodes, hasLength(0));
    });
  });

  testWidgets('the last picture of its cut holds nothing for a next', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final run = walkOver((_) => inFolder);

      await madeAhead(run, moving.length - 1);

      expect(debugKeptFrameDraws, 0);
      expect(run.pictures.aheadNodes, hasLength(0));
    });
  });

  testWidgets('a folder that changes is held anew for the pictures after it, '
      'and the one before is let go of', (tester) async {
    await tester.runAsync(() async {
      final run = walkOver((frame) => frame < 2 ? inFolder : inFolderLater);

      for (var frame = 0; frame < moving.length; frame += 1) {
        await madeAhead(run, frame);
      }

      expect(debugSubtreeRasterCount, 2);
      expect(debugKeptFrameDraws, 2);
      expect(run.pictures.aheadNodes, hasLength(1));
    });
  });

  testWidgets('a folder that stays inside one that changes is held all the '
      'same', (tester) async {
    await tester.runAsync(() async {
      final run = walkOf(
        (picture) => [
          folderOf([
            rowOf(moving[picture.frameIndex]),
            folderOf([rowOf(inFolder)]),
          ]),
        ],
      );

      await madeAhead(run, 0);
      expect(debugSubtreeRasterCount, 2, reason: '⛔premise: both drawn');
      await madeAhead(run, 1);

      expect(debugSubtreeRasterCount, 3, reason: 'the inner one found');
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
