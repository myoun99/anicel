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
import 'package:anicel/src/native/engine_chain_holds.dart';
import 'package:anicel/src/native/engine_frame_tools.dart';
import 'package:anicel/src/services/brush_frame_display_cache_service.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/brush_live_stroke_rasterizer.dart'
    show PromotedStrokeTile;
import 'package:anicel/src/ui/canvas/active_stroke_overlay.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/canvas/selection_float_overlay.dart';
import 'package:anicel/src/ui/playback/engine_frame_picture_store.dart';
import 'package:anicel/src/ui/playback/frame_picture_view.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';
import 'package:anicel/src/ui/playback/stacked_frame_picture.dart';
import 'a_canvas_standing_on_a_frame.dart';
import 'cels_kept_in_a_file.dart';
import 'settle_async.dart';

/// 🚨A STROKE'S STEP IS WRITTEN INTO THE PICTURE THE CANVAS SHOWS
/// (one-picture-per-frame ②-4): where it lands is composed into the frame's
/// one picture, and the screen shows that picture at the paint that wrote
/// it — pixel for pixel what the frame drawn as it stands shows, through a
/// pan, a zoom in and out and a device's ratio (F-465, 유저 채팅 2026-10-26:
/// 「그럼 그냥 바로 바로쓰기로 바꾸고, 잔재들 없애고」; F-509, 유저 2026-10-30
/// 「홍보 한참인데 진짜 비상사태」: a stroke must not leave the frame).
///
/// A stroke that lands moves the picture to the frame's next key where it
/// stands, and the next stroke is written into it there. Another screen
/// showing the frame sees nothing change as the stroke lands.
///
/// The step is seen at each of [views] on a screen of each of [ratios]: a
/// cel of [inkAt] (one ink where it is null) under a stroke at [strokeAt],
/// each pixel shown as it stands to within [apartBy] of a channel, on a page
/// of [page], its row standing in the tree [stack] lays it in (alone where
/// none is named). The pins of no view come [withThePinsOfNoView].
void aStrokeIsWrittenIntoThePictureShown({
  required Map<String, CanvasViewport> views,
  required List<double> ratios,
  List<int> Function(int x, int y)? inkAt,
  Rect strokeAt = const Rect.fromLTRB(4, 4, 12, 12),
  CanvasSize page = const CanvasSize(width: 32, height: 32),
  int apartBy = 0,
  List<CompositeNode<CanvasStackRow>> Function(BrushFrameKey cel)? stack,
  bool withThePinsOfNoView = true,
  bool skip = false,
}) {
  opensTheEnginesScreens();
  const tileSize = 128;
  final canvasSize = page;
  const viewSize = Size(48, 40);
  const ink = [0x00, 0x40, 0x00, 0x80];
  const stroke = [0x40, 0x00, 0x00, 0x80];
  const under = Color(0xFF203040);
  List<int> inkOf(Offset at) =>
      inkAt?.call(at.dx.floor(), at.dy.floor()) ?? ink;

  const key = BrushFrameKey(
    projectId: ProjectId('p'),
    trackId: TrackId('t'),
    cutId: CutId('c'),
    layerId: LayerId('inked'),
    frameId: FrameId('f'),
  );
  final cut = Cut(
    id: key.cutId,
    name: 'Cut',
    duration: 1,
    canvasSize: canvasSize,
    layers: [
      Layer(
        id: key.layerId,
        name: 'Inked',
        frames: [Frame(id: key.frameId, duration: 1, strokes: const [])],
        timeline: {0: TimelineExposure.drawing(key.frameId, length: 1)},
      ),
    ],
  );
  final nodes =
      stack?.call(key) ??
      [
        const CompositeLeaf<CanvasStackRow>(
          CanvasActiveLayerRow(opacity: 1, frameKey: key),
        ),
      ];
  // No paper: what lies under the ink is the screen's own.
  final frame = (
    cut: cut,
    frameIndex: 0,
    paintPaper: false,
    ghosts: FrameGhosts.none,
  );
  final screen = GlobalKey();
  final onThePage = Offset.zero & Size(page.width + 0.0, page.height + 0.0);

  /// A tile of what [colourAt] says at each pixel's centre — clear where
  /// it says nothing.
  BitmapTile tileAt(TileCoord coord, List<int>? Function(Offset at) colourAt) {
    final pixels = Uint8List(tileSize * tileSize * 4);
    for (var y = 0; y < tileSize; y += 1) {
      for (var x = 0; x < tileSize; x += 1) {
        final colour = colourAt(
          Offset(coord.x * tileSize + x + 0.5, coord.y * tileSize + y + 0.5),
        );
        if (colour != null) {
          pixels.setRange(
            (y * tileSize + x) * 4,
            (y * tileSize + x) * 4 + 4,
            colour,
          );
        }
      }
    }
    return BitmapTile(size: tileSize, pixels: pixels);
  }

  List<int>? inkOnThePage(Offset at) =>
      onThePage.contains(at) ? inkOf(at) : null;

  BrushFrameStore storeWithTheCel() {
    final store = BrushFrameStore();
    keepInAFile(store, {
      key: BitmapSurface(
        canvasSize: canvasSize,
        tileSize: tileSize,
        tiles: {
          for (var ty = 0; ty < (page.height / tileSize).ceil(); ty += 1)
            for (var tx = 0; tx < (page.width / tileSize).ceil(); tx += 1)
              TileCoord(x: tx, y: ty): tileAt(
                TileCoord(x: tx, y: ty),
                inkOnThePage,
              ),
        },
      ),
    });
    return store;
  }

  /// The frame's pictures, of their own, kept by [store].
  StackRun runOf(
    LayerFrameImageCache images,
    EngineFramePictureStore<FramePictureKey> store,
  ) => runOver(images, store, canvasSize: canvasSize, stackOf: (_) => nodes);

  BitmapSurface surfaceOfTheCel(BrushFrameStore cels) =>
      BrushFrameDisplayCacheService(
        frameStore: cels,
        canvasSize: canvasSize,
      ).prepareFramePreview(key).previewSurface;

  Future<void> pump(
    WidgetTester tester,
    StackRun run, {
    required Key key,
    required CanvasViewport view,
    required BitmapSurfacePainter live,
    SelectionFloatOverlay? float,
  }) => tester.pumpWidget(
    onAScreen(
      screen,
      size: viewSize,
      under: under,
      view: standingOn(
        run,
        key: key,
        picture: frame,
        nodes: nodes,
        viewport: view,
        live: (
          activeSurfacePainter: live,
          floatOverlay: float,
          liftedRows: const {},
        ),
      ),
    ),
  );

  Future<Shot> onScreen(WidgetTester tester) => shotOf(tester, screen);

  /// What a view of its own shows of the frame, the rows [live] draws in
  /// hand before it takes a picture: the frame drawn as it stands.
  Future<Shot> asItStands(
    WidgetTester tester,
    LayerFrameImageCache images, {
    required FramePictureKey picture,
    required CanvasViewport view,
    required BitmapSurfacePainter live,
  }) async {
    final standing = aStoreOfPictures();
    addTearDown(standing.dispose);
    await pump(
      tester,
      runOf(images, standing),
      key: const ValueKey(1),
      view: view,
      live: live,
    );
    expect(
      await settleAsync(tester, () => standing.bytesOf(picture) != null),
      isTrue,
      reason: 'LIVENESS: its picture is made too',
    );
    await lendBothClocks(tester, rounds: 2);
    return onScreen(tester);
  }

  /// [cels]' cel with [tiles] stored over what it held.
  void land(
    BrushFrameStore cels,
    Map<TileCoord, BitmapTile> tiles,
  ) {
    cels.storeBakedSurface(
      key,
      BitmapSurface(
        canvasSize: canvasSize,
        tileSize: tileSize,
        tiles: {...surfaceOfTheCel(cels).tiles, ...tiles},
      ),
    );
    cels.markCelEdited(key);
  }

  final origin = TileCoord(x: 0, y: 0);
  BitmapTile stroked(Rect where) =>
      tileAt(origin, (at) => where.contains(at) ? stroke : inkOnThePage(at));

  /// A frame standing on its picture, and a stroke on its way in it.
  Future<
    ({
      BrushFrameStore cels,
      LayerFrameImageCache images,
      ActiveStrokeOverlayModel overlay,
      BitmapSurfacePainter Function() painter,
      StackRun run,
      FramePictureKey picture,
    })
  >
  standOnIt(
    WidgetTester tester,
    EngineFramePictureStore<FramePictureKey> store, {
    required CanvasViewport view,
    required String lineage,
  }) async {
    final cels = storeWithTheCel();
    final images = LayerFrameImageCache(frameStore: cels);
    addTearDown(images.dispose);
    final overlay = ActiveStrokeOverlayModel(tileSize: tileSize)
      ..preBlendBase = surfaceOfTheCel(cels);
    addTearDown(overlay.dispose);
    BitmapSurfacePainter painter() => BitmapSurfacePainter(
      surface: surfaceOfTheCel(cels),
      overlayModel: overlay,
      showTransparentBackground: false,
      lineage: lineage,
    );
    final run = runOf(images, store);
    final picture = run.pictures.keyOfStack(nodes, frame);
    await pump(tester, run, key: const ValueKey(0), view: view, live: painter());
    expect(
      await settleAsync(tester, () => store.bytesOf(picture) != null),
      isTrue,
      reason: 'LIVENESS: the frame\'s picture is made',
    );
    await lendBothClocks(tester, rounds: 2);
    await tester.pump();
    return (
      cels: cels,
      images: images,
      overlay: overlay,
      painter: painter,
      run: run,
      picture: picture,
    );
  }

  for (final MapEntry(key: name, value: view) in views.entries) {
    for (final ratio in ratios) {
      testWidgets('🚨$name (ratio $ratio): a step shows at the paint that '
          'writes it, as the frame drawn as it stands shows', (tester) async {
        tester.view.devicePixelRatio = ratio;
        addTearDown(tester.view.resetDevicePixelRatio);
        final store = aStoreOfPictures();
        addTearDown(store.dispose);
        final standing = await standOnIt(
          tester,
          store,
          view: view,
          lineage: 'a-stroke-step-$name-$ratio',
        );
        final before = await onScreen(tester);

        standing.overlay.showResultTiles([
          PromotedStrokeTile(origin, stroked(strokeAt), 1),
        ]);
        await tester.pump();
        final shown = await onScreen(tester);
        expect(
          differences(before, shown),
          isNotEmpty,
          reason: 'LIVENESS: the step shows at the paint after it',
        );
        expect(
          differences(
            await asItStands(
              tester,
              standing.images,
              picture: standing.picture,
              view: view,
              live: standing.painter(),
            ),
            shown,
            by: apartBy,
          ),
          isEmpty,
          reason: 'the picture shows what the frame drawn as it stands shows',
        );
        await tester.pumpWidget(const SizedBox());
      }, skip: skip);
    }
  }

  if (!withThePinsOfNoView) {
    return;
  }

  final pannedView = CanvasViewport(panX: 8, panY: 4);

  testWidgets('🚨a step past the picture grows it where it stands, and shows '
      'as the frame drawn as it stands shows (F-533)', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = aStoreOfPictures();
    addTearDown(store.dispose);
    final standing = await standOnIt(
      tester,
      store,
      view: pannedView,
      lineage: 'a-step-past-the-picture',
    );
    final before = store.bytesOf(keptByTheCanvas(tester, standing.picture)) ??
        store.bytesOf(standing.picture)!;
    // Before the page: past it is past the pasteboard, on a page this small.
    final past = TileCoord(x: -1, y: 0);
    standing.overlay.showResultTiles([
      PromotedStrokeTile(past, tileAt(past, (_) => stroke), 1),
    ]);
    await tester.pump();
    final kept = keptByTheCanvas(tester, standing.picture);
    expect(
      store.bytesOf(kept) ?? store.bytesOf(standing.picture),
      greaterThan(before),
      reason: 'the picture keeps the world the stroke reached',
    );
    final shown = await onScreen(tester);
    expect(
      differences(
        await asItStands(
          tester,
          standing.images,
          picture: standing.picture,
          view: pannedView,
          live: standing.painter(),
        ),
        shown,
      ),
      isEmpty,
      reason: 'grown, it shows what the frame as it stands shows',
    );
    await tester.pumpWidget(const SizedBox());
  }, skip: skip);

  testWidgets('🚨a step whose write throws shows at that paint as the frame '
      'stands, not the picture without it, and stays so (F-509)', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = _WritesThrow();
    addTearDown(store.dispose);
    final standing = await standOnIt(
      tester,
      store,
      view: pannedView,
      lineage: 'a-step-that-throws',
    );
    final before = await onScreen(tester);
    store.refuses = true;
    standing.overlay.showResultTiles([
      PromotedStrokeTile(origin, stroked(strokeAt), 1),
    ]);
    await tester.pump();
    expect(
      tester.takeException(),
      isStateError,
      reason: 'the refusal is told, by name',
    );
    final shown = await onScreen(tester);
    expect(
      differences(before, shown),
      isNotEmpty,
      reason: 'the step shows all the same',
    );
    store.refuses = false;
    expect(
      differences(
        await asItStands(
          tester,
          standing.images,
          picture: standing.picture,
          view: pannedView,
          live: standing.painter(),
        ),
        shown,
      ),
      isEmpty,
      reason: 'what shows is the frame as it stands',
    );
    await tester.pumpWidget(const SizedBox());
  }, skip: skip);

  testWidgets('🚨a stroke that lands moves the picture it was written into to '
      'the frame\'s next key — not laid anew — and the next stroke is written '
      'into it there', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = StoreTellingItsWrites();
    addTearDown(store.dispose);
    final standing = await standOnIt(
      tester,
      store,
      view: pannedView,
      lineage: 'a-stroke-lands',
    );
    final (:cels, :overlay, :painter, :run) = (
      cels: standing.cels,
      overlay: standing.overlay,
      painter: standing.painter,
      run: standing.run,
    );
    overlay.showResultTiles([
      PromotedStrokeTile(origin, stroked(strokeAt), 1),
    ]);
    await tester.pump();

    // The pen lifts: the stroke is the cel's, and the pen's row is drawn
    // by a painter of what it holds now.
    land(cels, {origin: stroked(strokeAt)});
    overlay.reset();
    final after = run.pictures.keyOfStack(nodes, frame);
    expect(
      after,
      isNot(standing.picture),
      reason: '⛔premise: the frame\'s key moved',
    );
    await pump(
      tester,
      run,
      key: const ValueKey(0),
      view: pannedView,
      live: painter(),
    );
    await tester.pump();
    expect(
      store.peek(after),
      isNotNull,
      reason: 'the picture answers to the frame\'s next key',
    );
    expect(
      store.laid,
      isNot(contains(after)),
      reason: 'moved where it stands, not laid anew',
    );

    const second = Rect.fromLTRB(16, 16, 24, 24);
    overlay.showResultTiles([
      PromotedStrokeTile(origin, stroked(second), 2),
    ]);
    await tester.pump();
    expect(
      store.patched,
      isNotEmpty,
      reason: 'the next stroke is written into the picture under its new '
          'key — not the frame drawn as it stands a step at a time',
    );
    land(cels, {origin: stroked(second)});
    overlay.reset();
    final next = run.pictures.keyOfStack(nodes, frame);
    expect(next, isNot(after), reason: '⛔premise: the frame\'s key moved');
    await pump(
      tester,
      run,
      key: const ValueKey(0),
      view: pannedView,
      live: painter(),
    );
    await tester.pump();
    expect(
      store.peek(next),
      isNotNull,
      reason: 'the picture answers to the frame\'s key after the next stroke',
    );
    expect(
      store.laid,
      isNot(contains(next)),
      reason: 'the next stroke\'s landing moves it again, not laid anew',
    );
    await tester.pumpWidget(const SizedBox());
  }, skip: skip);

  testWidgets('🚨a landing that comes with a float in hand is no move: where '
      'it lands cannot be told, and the picture it would leave under the '
      'frame\'s key never gets it (F-525)', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = StoreTellingItsWrites();
    addTearDown(store.dispose);
    final standing = await standOnIt(
      tester,
      store,
      view: pannedView,
      lineage: 'a-landing-with-a-float',
    );
    land(standing.cels, {origin: stroked(strokeAt)});
    final after = standing.run.pictures.keyOfStack(nodes, frame);
    expect(
      after,
      isNot(standing.picture),
      reason: '⛔premise: the frame\'s key moved',
    );
    final float = SelectionFloatOverlay(
      SelectionFloatPaint(surface: standing.painter()),
    );
    addTearDown(float.dispose);
    await pump(
      tester,
      standing.run,
      key: const ValueKey(0),
      view: pannedView,
      live: standing.painter(),
      float: float,
    );
    expect(
      await settleAsync(tester, () => store.peek(after) != null),
      isTrue,
      reason: 'LIVENESS: the frame\'s next key has its picture',
    );
    expect(
      store.laid,
      contains(after),
      reason: 'laid anew: ↩️moved, it was the picture before the landing',
    );
    await tester.pumpWidget(const SizedBox());
  }, skip: skip);
}

/// A store whose write into a picture is refused where it [refuses].
class _WritesThrow extends EngineFramePictureStore<FramePictureKey> {
  _WritesThrow() : super(tools: () => appEngineFrameTools);

  bool refuses = false;

  @override
  bool patch({
    required FramePictureKey from,
    required FramePictureKey to,
    required Rect rect,
    required StackedFrame frame,
    EngineChainHolds? holds,
  }) {
    if (refuses) {
      throw StateError('the engine refused the write');
    }
    return super.patch(
      from: from,
      to: to,
      rect: rect,
      frame: frame,
      holds: holds,
    );
  }
}
