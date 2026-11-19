import 'dart:typed_data';

import 'package:flutter/material.dart';
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
import 'package:anicel/src/services/brush_live_stroke_rasterizer.dart'
    show PromotedStrokeTile;
import 'package:anicel/src/ui/canvas/active_stroke_overlay.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/playback/frame_picture_view.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';
import 'package:anicel/src/ui/playback/stacked_frame_picture.dart'
    show FramePictureKey;
import '../../helpers/a_canvas_standing_on_a_frame.dart';
import '../../helpers/cels_kept_in_a_file.dart';
import '../../helpers/settle_async.dart';

/// 🔬F-620 (S5_BA cut 352, 2026-11-19): a value dragged on the canvas — a
/// cel number's box, a lane's colour wheel — moved the frame's key at each
/// value, and the canvas composed the frame twice a value: drawn as it
/// stands, and again as its key's picture. The frame drawn as it stands is
/// kept as that picture where it is the one the store would lay — every
/// cel in hand, the live rows showing nothing no cel stores — and the
/// store lays it where it is not, as ever.
void main() {
  opensTheEnginesScreens();
  const tileSize = defaultCelTileSize;
  const canvasSize = CanvasSize(width: 2 * tileSize, height: 2 * tileSize);
  const viewSize = Size(3.0 * tileSize, 2.5 * tileSize);
  const fill = [0x30, 0x60, 0x90, 0xFF];
  const under = Color(0xFF203040);
  final view = CanvasViewport(panX: tileSize / 2, panY: tileSize / 4);
  const world = Rect.fromLTWH(0, 0, 2.0 * tileSize, 2.0 * tileSize);

  BrushFrameKey celOf(String layer) => BrushFrameKey(
    projectId: const ProjectId('p'),
    trackId: const TrackId('t'),
    cutId: const CutId('c'),
    layerId: LayerId(layer),
    frameId: const FrameId('f'),
  );
  final inked = celOf('inked');
  final empty = celOf('empty');
  // Kept in the file, and read by no one.
  final unread = celOf('unread');
  final cut = Cut(
    id: inked.cutId,
    name: 'Cut',
    duration: 1,
    canvasSize: canvasSize,
    layers: [
      for (final cel in [inked, empty, unread])
        Layer(
          id: cel.layerId,
          name: 'Layer',
          frames: [Frame(id: cel.frameId, duration: 1, strokes: const [])],
          timeline: {0: TimelineExposure.drawing(cel.frameId, length: 1)},
        ),
    ],
  );
  final frame = (
    cut: cut,
    frameIndex: 0,
    paintPaper: false,
    ghosts: FrameGhosts.none,
  );
  final screen = GlobalKey();

  BitmapTile tileOf(List<int> colour) => BitmapTile(
    size: tileSize,
    pixels: Uint8List.fromList([
      for (var at = 0; at < tileSize * tileSize; at += 1) ...colour,
    ]),
  );

  /// The tree a canvas stands: [drawn] as stored at [opacity] — the value
  /// a hand drags — and the row a pen is on over [empty].
  List<CompositeNode<CanvasStackRow>> treeOf({
    double opacity = 1,
    BrushFrameKey? drawn,
  }) => [
    CompositeLeaf<CanvasStackRow>(
      CanvasLayerImageRequest(frameKey: drawn ?? inked, opacity: opacity),
    ),
    CompositeLeaf<CanvasStackRow>(
      CanvasActiveLayerRow(opacity: 1, frameKey: empty),
    ),
  ];

  BitmapSurface aCelOf(List<int> colour) => BitmapSurface(
    canvasSize: canvasSize,
    tileSize: tileSize,
    tiles: {
      for (var ty = 0; ty < 2; ty += 1)
        for (var tx = 0; tx < 2; tx += 1)
          TileCoord(x: tx, y: ty): tileOf(colour),
    },
  );

  /// A canvas's run over the cels kept in a file, its store saying what it
  /// laid, on a file put on screen already; the row a pen is on drawn by a
  /// painter whose stroke on its way is [overlay].
  ({StackRun run, StoreTellingItsWrites store, LiveRows live}) standing(
    ActiveStrokeOverlayModel overlay,
  ) {
    final cels = BrushFrameStore();
    keepInAFile(cels, {
      inked: aCelOf(fill),
      unread: aCelOf(const [0x90, 0x30, 0x60, 0xFF]),
    });
    final images = LayerFrameImageCache(frameStore: cels);
    addTearDown(images.dispose);
    final store = StoreTellingItsWrites();
    addTearDown(store.dispose);
    final run = runOver(
      images,
      store,
      canvasSize: canvasSize,
      stackOf: (_) => treeOf(),
    );
    run.pictures.putOnScreen();
    return (
      run: run,
      store: store,
      live: (
        activeSurfacePainter: BitmapSurfacePainter(
          surface: BitmapSurface(canvasSize: canvasSize, tileSize: tileSize),
          overlayModel: overlay,
          showTransparentBackground: false,
          lineage: 'a-frame-drawn-as-it-stands-is-kept',
        ),
        floatOverlay: null,
        liftedRows: const {},
      ),
    );
  }

  ActiveStrokeOverlayModel anOverlay() {
    final overlay = ActiveStrokeOverlayModel(tileSize: tileSize)
      ..preBlendBase = BitmapSurface(
        canvasSize: canvasSize,
        tileSize: tileSize,
      );
    addTearDown(overlay.dispose);
    return overlay;
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

  /// The cel read into hand, and the engine's tools open: a paint lays the
  /// frame from the first.
  Future<void> theCelsRead(WidgetTester tester, StackRun run) async {
    await itsToolsOpen(tester, run.pictures.store);
    await tester.runAsync(() => run.pictures.readInStack(treeOf(), frame));
    expect(
      run.pictures.allInHand(treeOf(), frame),
      isTrue,
      reason: '⛔premise: the cel is in hand',
    );
  }

  /// [tree] handed to the canvas, and its key once its picture is there.
  Future<FramePictureKey> handed(
    WidgetTester tester,
    ({StackRun run, StoreTellingItsWrites store, LiveRows live}) standing,
    List<CompositeNode<CanvasStackRow>> tree,
  ) async {
    await tester.pumpWidget(shown(standing.run, standing.live, tree));
    final key = standing.run.pictures.keyOfStack(tree, frame);
    expect(
      await settleAsync(tester, () => standing.store.holds(key)),
      isTrue,
      reason: 'LIVENESS: the frame has its picture',
    );
    await tester.pump();
    return key;
  }

  testWidgets('🚨a value dragged on a drawn row: each frame drawn as it '
      'stands is kept as its key\'s picture, and the store lays none of '
      'them again — the first, painted before its screen had a texture to '
      'lay it on, it lays as ever', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    final canvas = standing(anOverlay());
    await theCelsRead(tester, canvas.run);
    final first = await handed(tester, canvas, treeOf());
    expect(canvas.store.laid, [first], reason: 'made once it was painted');

    for (final opacity in [0.75, 0.5, 0.25]) {
      final tree = treeOf(opacity: opacity);
      final key = await handed(tester, canvas, tree);
      expect(
        pixelsOfPicture(canvas.store.peek(key)!, world),
        pixelsOfFrame(canvas.run.pictures.drawingNow(tree, frame).frame, world),
        reason: 'what is kept is the frame the store would lay ($opacity)',
      );
    }

    expect(canvas.store.laid, [first], reason: 'each value kept as it stood');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a frame whose cels are still in their file is laid by the '
      'store — it stands without them meanwhile', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    final canvas = standing(anOverlay());
    await theCelsRead(tester, canvas.run);
    final first = await handed(tester, canvas, treeOf());
    canvas.store.laid.clear();
    // The row shows a cel no one read yet.
    final tree = treeOf(drawn: unread);
    expect(
      canvas.run.pictures.allInHand(tree, frame),
      isFalse,
      reason: '⛔premise: the cel is in its file',
    );

    final key = await handed(tester, canvas, tree);

    expect(key, isNot(first), reason: '⛔premise');
    expect(canvas.store.laid, [key]);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('🚨a step come on its way before the frame was painted is no '
      'part of the key\'s picture: the store lays it as the cels store it',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    final overlay = anOverlay();
    final canvas = standing(overlay);
    await theCelsRead(tester, canvas.run);
    await handed(tester, canvas, treeOf());
    canvas.store.laid.clear();
    final tree = treeOf(opacity: 0.5);

    // Handed, and stood on, with nothing on its way ...
    await tester.pumpWidget(
      shown(canvas.run, canvas.live, tree),
      phase: EnginePhase.layout,
    );
    // ... and a step shown before the paint lays the frame.
    overlay.showResultTiles([
      PromotedStrokeTile(
        TileCoord(x: 0, y: 0),
        tileOf(const [0xFF, 0x00, 0x00, 0xFF]),
        1,
      ),
    ]);
    await tester.pump();
    final key = canvas.run.pictures.keyOfStack(tree, frame);
    expect(
      await settleAsync(tester, () => canvas.store.laid.contains(key)),
      isTrue,
      reason: 'the frame as it stands holds the step: the store lays the '
          'frame instead',
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the store keeps no screen under a key it has a picture of, or '
      'lays one of: one picture a key', (tester) async {
    final (:run, :store, live: _) = standing(anOverlay());
    await theCelsRead(tester, run);
    final (:composite, :letters) = store.toolsOpen!;
    final key = run.pictures.keyOfStack(treeOf(), frame);
    final drawn = run.pictures.drawingNow(treeOf(), frame).frame;
    final screen = EngineStackScreen(composite, letters);

    final onItsWay = store.lay(key, drawn);
    expect(store.keepLaid(key, screen), isNull, reason: 'one on its way');
    await tester.runAsync(() => onItsWay);
    expect(store.holds(key), isTrue, reason: '⛔premise: laid');
    expect(store.keepLaid(key, screen), isNull, reason: 'one there');

    final another = run.pictures.keyOfStack(treeOf(opacity: 0.5), frame);
    expect(
      store.keepLaid(another, screen),
      isNotNull,
      reason: '⛔CONTROL: a key with none is kept',
    );
    expect(store.holds(another), isTrue);
  });
}
