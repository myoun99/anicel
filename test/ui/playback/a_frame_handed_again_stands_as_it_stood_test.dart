import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderCustomPaint;
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/playback/frame_demand.dart' show FrameGhosts;
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/playback/frame_picture_store.dart';
import 'package:anicel/src/ui/playback/frame_picture_view.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';
import 'package:anicel/src/ui/playback/stacked_frame_picture.dart';
import '../../helpers/a_canvas_standing_on_a_frame.dart';
import '../../helpers/cels_kept_in_a_file.dart';
import '../../helpers/no_worker_free.dart';
import '../../helpers/settle_async.dart';

/// 🚨A TREE HANDED AGAIN IS THE FRAME HANDED AGAIN (F-244): a canvas asks
/// its tree afresh at every build — a block's drag in the timeline builds
/// it at each step with every row as it was — and the frame stood again
/// at each repainted the whole canvas. A tree that stands as the frame was
/// stood ([FramePictures.keyAsItStands]) repaints nothing; one that
/// changes a row stands the frame again — a row a pen is on with nothing
/// in its cel among them, which the picture is made without but which
/// draws the stroke in hand. A frame handed again while its cels are read
/// shows them once they are. Handed with another run, or to be drawn as it
/// stands while a view of whole frames waited, it stands again too — by
/// the same key.
void main() {
  const tileSize = 16;
  const canvasSize = CanvasSize(width: 32, height: 32);
  const viewSize = Size(48, 40);
  const fill = [0x30, 0x60, 0x90, 0xFF];
  const under = Color(0xFF203040);
  final view = CanvasViewport(panX: 8, panY: 4);

  BrushFrameKey celOf(String layer) => BrushFrameKey(
    projectId: const ProjectId('p'),
    trackId: const TrackId('t'),
    cutId: const CutId('c'),
    layerId: LayerId(layer),
    frameId: const FrameId('f'),
  );
  final inked = celOf('inked');
  final empty = celOf('empty');
  final cut = Cut(
    id: inked.cutId,
    name: 'Cut',
    duration: 1,
    canvasSize: canvasSize,
    layers: [
      for (final cel in [inked, empty])
        Layer(
          id: cel.layerId,
          name: 'Layer',
          frames: [Frame(id: cel.frameId, duration: 1, strokes: const [])],
          timeline: {0: TimelineExposure.drawing(cel.frameId, length: 1)},
        ),
    ],
  );
  // No paper: what lies under the ink is the screen's own.
  final frame = (cut: cut, frameIndex: 0, paintPaper: false, ghosts: FrameGhosts.none);
  final screen = GlobalKey();

  BitmapSurface filled(List<int> colour) => BitmapSurface(
    canvasSize: canvasSize,
    tileSize: tileSize,
    tiles: {
      for (var ty = 0; ty < 2; ty += 1)
        for (var tx = 0; tx < 2; tx += 1)
          TileCoord(x: tx, y: ty): BitmapTile(
            size: tileSize,
            pixels: Uint8List.fromList([
              for (var at = 0; at < tileSize * tileSize; at += 1) ...colour,
            ]),
          ),
    },
  );

  /// The tree a canvas stands: [inked] as stored, and the row a pen is on
  /// over [empty] at [opacity] — every row a new object at each call, as a
  /// build makes them.
  List<CompositeNode<CanvasStackRow>> treeOf({double opacity = 1}) => [
    CompositeLeaf<CanvasStackRow>(
      CanvasLayerImageRequest(frameKey: inked, opacity: 1),
    ),
    CompositeLeaf<CanvasStackRow>(
      CanvasActiveLayerRow(opacity: opacity, frameKey: empty),
    ),
  ];

  ({StackRun run, LiveRows live}) standing(
    WritesNeverLand gpu, {
    List<int> colour = fill,
  }) {
    final cels = BrushFrameStore();
    keepInAFile(cels, {inked: filled(colour)});
    final images = LayerFrameImageCache(frameStore: cels);
    addTearDown(images.dispose);
    final store = FramePictureStore<FramePictureKey>(gpu: gpu);
    addTearDown(store.dispose);
    return (
      run: runOver(
        images,
        store,
        canvasSize: canvasSize,
        stackOf: (_) => treeOf(),
      ),
      live: (
        activeSurfacePainter: BitmapSurfacePainter(
          surface: BitmapSurface(canvasSize: canvasSize, tileSize: tileSize),
          showTransparentBackground: false,
          lineage: 'a-frame-handed-again',
        ),
        floatOverlay: null,
        liftedRows: const {},
      ),
    );
  }

  Widget shown(
    StackRun run,
    LiveRows live,
    List<CompositeNode<CanvasStackRow>> nodes,
  ) => onAScreen(
    screen,
    size: viewSize,
    under: under,
    view: standingOn(
      run,
      picture: frame,
      nodes: nodes,
      viewport: view,
      live: live,
    ),
  );

  RenderCustomPaint theView(WidgetTester tester) =>
      tester.renderObject<RenderCustomPaint>(
        find.descendant(
          of: find.byType(FramePictureView),
          matching: find.byType(CustomPaint),
        ),
      );

  /// What [shot] shows inside the page, where the cel is ink.
  List<int> onThePage(Shot shot) {
    final at = (12 * shot.width + 20) * 4;
    return shot.rgba.sublist(at, at + 4);
  }

  testWidgets('🚨a tree handed again with every row as it was repaints '
      'nothing; a row changed stands the frame again — the pen\'s row over '
      'an empty cel too', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    final (:run, :live) = standing(WritesNeverLand());
    await tester.pumpWidget(shown(run, live, treeOf()));
    final picture = run.pictures.keyOfStack(treeOf(), frame);
    expect(
      await settleAsync(tester, () => run.pictures.store.bytesOf(picture) != null),
      isTrue,
      reason: 'LIVENESS: the frame\'s picture is made',
    );
    await lendBothClocks(tester, rounds: 2);
    expect(theView(tester).debugNeedsPaint, isFalse, reason: 'the premise');

    await tester.pumpWidget(
      shown(run, live, treeOf()),
      phase: EnginePhase.layout,
    );
    expect(
      theView(tester).debugNeedsPaint,
      isFalse,
      reason: 'the same frame, handed again, is not stood again',
    );
    await tester.pump();

    await tester.pumpWidget(
      shown(run, live, treeOf(opacity: 0.5)),
      phase: EnginePhase.layout,
    );
    expect(
      theView(tester).debugNeedsPaint,
      isTrue,
      reason: 'the pen\'s row at another opacity draws its stroke so — the '
          'frame as it stands is another, though its picture is not',
    );
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('🚨a frame handed again while its cels are read shows them once '
      'they are', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    final gpu = WritesNeverLand()..holdsRenders = true;
    addTearDown(gpu.letAllThrough);
    final (:run, :live) = standing(gpu);
    final tree = treeOf();
    // ⚠️Held: in this runner a read lands in the microtasks after the
    // frame that asked it.
    await whileNoWorkerIsFree(() async {
      await tester.pumpWidget(shown(run, live, tree));
      expect(
        run.pictures.allInHand(tree, frame),
        isFalse,
        reason: '⛔premise: the cel is still in its file',
      );
      // Handed again before the cel is read.
      await tester.pumpWidget(shown(run, live, treeOf()));
    });
    expect(
      await settleAsync(tester, () => run.pictures.allInHand(tree, frame)),
      isTrue,
      reason: 'LIVENESS: the cel is read',
    );
    await tester.pump();

    expect(
      onThePage(await shotOf(tester, screen)),
      fill,
      reason: 'the frame as it stands draws the cel once it is read — its '
          'picture is held, so nothing else shows it',
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('🚨the tree handed again with another run stands the frame '
      'again — its key the same, its cels another store\'s', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    final first = standing(WritesNeverLand());
    await tester.pumpWidget(shown(first.run, first.live, treeOf()));
    expect(
      await settleAsync(
        tester,
        () => first.run.pictures.allInHand(treeOf(), frame),
      ),
      isTrue,
      reason: 'LIVENESS: the first run\'s cel is read',
    );
    await tester.pump();

    const other = [0x90, 0x30, 0x60, 0xFF];
    // Its picture held: what shows is the frame as it stands.
    final gpu = WritesNeverLand()..holdsRenders = true;
    addTearDown(gpu.letAllThrough);
    final (:run, live: _) = standing(gpu, colour: other);
    expect(
      run.pictures.keyAsItStands(treeOf(), frame),
      first.run.pictures.keyAsItStands(treeOf(), frame),
      reason: '⛔premise: the frame stands by the same key in both',
    );
    await tester.pumpWidget(shown(run, first.live, treeOf()));
    expect(
      await settleAsync(tester, () => run.pictures.allInHand(treeOf(), frame)),
      isTrue,
      reason: 'LIVENESS: the other run\'s cel is read',
    );
    await tester.pump();
    expect(
      onThePage(await shotOf(tester, screen)),
      other,
      reason: 'the frame stands on the cels of the run it is handed with — '
          'not the first run\'s, by a key both answer',
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('🚨a frame handed again to be drawn as it stands meanwhile '
      'stands — not left waiting for its picture', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    final gpu = WritesNeverLand()..holdsRenders = true;
    addTearDown(gpu.letAllThrough);
    final (:run, live: _) = standing(gpu);
    Widget wholeFramesOnly(bool wholeFrames) => onAScreen(
      screen,
      size: viewSize,
      under: under,
      view: FramePictureView(
        run: run,
        picture: frame,
        nodes: treeOf(),
        viewport: view,
        laysWhatItMisses: true,
        wholeFrames: wholeFrames,
      ),
    );
    await tester.pumpWidget(wholeFramesOnly(true));
    await lendBothClocks(tester, rounds: 2);
    expect(
      onThePage(await shotOf(tester, screen)),
      isNot(fill),
      reason: '⛔premise: a view of whole frames waits for the picture, held',
    );

    await tester.pumpWidget(wholeFramesOnly(false));
    expect(
      await settleAsync(tester, () => run.pictures.allInHand(treeOf(), frame)),
      isTrue,
      reason: 'LIVENESS: the cel is read',
    );
    await tester.pump();
    expect(
      onThePage(await shotOf(tester, screen)),
      fill,
      reason: 'handed again to be drawn as it stands meanwhile, it is',
    );
    await tester.pumpWidget(const SizedBox());
  });
}
