import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderCustomPaint;
import 'package:flutter_test/flutter_test.dart';
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
import 'package:anicel/src/services/brush_frame_display_cache_service.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/brush_live_stroke_rasterizer.dart'
    show PromotedStrokeTile;
import 'package:anicel/src/ui/canvas/active_stroke_overlay.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/playback/frame_picture_store.dart';
import 'package:anicel/src/ui/playback/frame_picture_view.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';
import 'package:anicel/src/ui/playback/stacked_frame_picture.dart';
import '../../helpers/a_canvas_standing_on_a_frame.dart';
import '../../helpers/cels_kept_in_a_file.dart';
import '../../helpers/settle_async.dart';

/// 🚨A STROKE'S STEP IS WRITTEN INTO THE PICTURE THE CANVAS SHOWS
/// (one-picture-per-frame ②-4): where it lands is patched into the frame's
/// one picture, and until the patch's texels are in, that rect is drawn as
/// it stands — by the walk ALONE. What the screen shows while the step lands,
/// once it has landed, and drawn as it stands whole is one picture, pixel for
/// pixel, through a pan, a zoom and a device's ratio.
///
/// The ink is translucent and no paper lies under it, so a rect drawn as it
/// stands OVER the picture shows its ink twice.
///
/// A step shows at the paint after it, with no build between: the rect it
/// lands in, and the whole frame as it stands where the step goes past the
/// picture (a picture does not grow).
///
/// A stroke that lands moves the picture to the frame's next key where it
/// stands, and the next stroke is written into it there — its steps shown
/// while the picture is still on its way. Another screen showing the frame
/// sees nothing change as the stroke lands.
void main() {
  const tileSize = 16;
  const canvasSize = CanvasSize(width: 32, height: 32);
  const viewSize = Size(48, 40);
  const ink = [0x00, 0x40, 0x00, 0x80];
  const stroke = [0x40, 0x00, 0x00, 0x80];
  const strokeAt = Rect.fromLTRB(4, 4, 12, 12);
  const under = Color(0xFF203040);

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
  final nodes = [
    const CompositeLeaf<CanvasStackRow>(
      CanvasActiveLayerRow(opacity: 1, frameKey: key),
    ),
  ];
  // No paper: what lies under the ink is the screen's own.
  final frame = (cut: cut, frameIndex: 0, paintPaper: false);
  final screen = GlobalKey();

  /// A tile of [colour] wherever [inside] holds, and clear elsewhere.
  BitmapTile tileOf(
    TileCoord coord,
    List<int> colour,
    bool Function(Offset at) inside,
  ) {
    final pixels = Uint8List(tileSize * tileSize * 4);
    for (var y = 0; y < tileSize; y += 1) {
      for (var x = 0; x < tileSize; x += 1) {
        final at = Offset(
          coord.x * tileSize + x + 0.5,
          coord.y * tileSize + y + 0.5,
        );
        if (inside(at)) {
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

  BrushFrameStore storeWithTheCel() {
    final store = BrushFrameStore();
    keepInAFile(store, {
      key: BitmapSurface(
        canvasSize: canvasSize,
        tileSize: tileSize,
        tiles: {
          for (var ty = 0; ty < 2; ty += 1)
            for (var tx = 0; tx < 2; tx += 1)
              TileCoord(x: tx, y: ty): tileOf(
                TileCoord(x: tx, y: ty),
                ink,
                (_) => true,
              ),
        },
      ),
    });
    return store;
  }

  /// The frame's pictures, of their own, kept by [store].
  StackRun runOf(
    LayerFrameImageCache images,
    FramePictureStore<FramePictureKey> store,
  ) => runOver(images, store, canvasSize: canvasSize, stackOf: (_) => nodes);

  Future<void> pump(
    WidgetTester tester,
    StackRun run, {
    required Key key,
    required CanvasViewport view,
    required BitmapSurfacePainter live,
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
          floatOverlay: null,
          liftedRows: const {},
        ),
      ),
    ),
  );

  /// What [boundary] shows — [screen] where none is named.
  Future<Shot> onScreen(WidgetTester tester, [GlobalKey? boundary]) =>
      shotOf(tester, boundary ?? screen);

  final views = {
    'panned': CanvasViewport(panX: 8, panY: 4),
    'at 200%': CanvasViewport(zoom: 2, panX: -6, panY: -10),
  };
  const ratios = [1.0, 1.5];

  for (final MapEntry(key: name, value: view) in views.entries) {
    for (final ratio in ratios) {
      testWidgets('🚨$name (ratio $ratio): the screen shows one picture while '
          'a step lands, once it has, and drawn as it stands', (tester) async {
        tester.view.devicePixelRatio = ratio;
        addTearDown(tester.view.resetDevicePixelRatio);
        final lineage = 'a-stroke-step-$name-$ratio';
        final cels = storeWithTheCel();
        final images = LayerFrameImageCache(frameStore: cels);
        addTearDown(images.dispose);
        final overlay = ActiveStrokeOverlayModel(tileSize: tileSize);
        final live = BitmapSurfacePainter(
          surface: BrushFrameDisplayCacheService(
            frameStore: cels,
            canvasSize: canvasSize,
          ).prepareFramePreview(key).previewSurface,
          overlayModel: overlay,
          showTransparentBackground: false,
          lineage: lineage,
        );
        final gpu = WritesNeverLand();
        final store = FramePictureStore<FramePictureKey>(gpu: gpu);
        addTearDown(store.dispose);
        final run = runOf(images, store);
        final picture = run.pictures.keyOfStack(nodes, frame);

        await pump(tester, run, key: const ValueKey(0), view: view, live: live);
        expect(
          await settleAsync(tester, () => store.bytesOf(picture) != null),
          isTrue,
          reason: 'LIVENESS: the frame\'s picture is made',
        );
        await lendBothClocks(tester, rounds: 2);
        final before = await onScreen(tester);

        gpu.holdsRenders = true;
        addTearDown(gpu.letAllThrough);
        overlay.showResultTiles([
          PromotedStrokeTile(
            TileCoord(x: 0, y: 0),
            tileOf(TileCoord(x: 0, y: 0), stroke, strokeAt.contains),
            1,
          ),
        ]);
        await tester.pump();
        final step = store.landingOf(picture);
        expect(
          step,
          isNotNull,
          reason: 'LIVENESS: the step is on its way into the picture, not '
              'the frame drawn as it stands',
        );
        final landing = await onScreen(tester);
        expect(
          store.peek(picture)!.landing,
          isEmpty,
          reason: 'LIVENESS: none of the step\'s texels are there yet',
        );
        expect(
          differences(before, landing),
          isNotEmpty,
          reason: 'the step shows at the paint after it — not once its '
              'texels are in',
        );

        gpu.letAllThrough();
        await tester.runAsync(() => step!);
        await tester.pump();
        expect(
          store.peek(picture)!.landing,
          isNotEmpty,
          reason: 'LIVENESS: the step\'s own texels are drawn over the picture',
        );
        final landed = await onScreen(tester);

        // A view of its own, the step in hand before it takes a picture:
        // the frame drawn as it stands.
        final standing = FramePictureStore<FramePictureKey>(
          gpu: WritesNeverLand(),
        );
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
        final asItStands = await onScreen(tester);

        expect(
          differences(asItStands, landing),
          isEmpty,
          reason: 'while the step lands its rect is drawn as it stands, '
              'once',
        );
        expect(
          differences(asItStands, landed),
          isEmpty,
          reason: 'once it has, the picture holds what the rows show',
        );

        await tester.pumpWidget(const SizedBox());
        overlay.dispose();
      });
    }
  }

  testWidgets('🚨a step past the picture draws the frame as it stands at the '
      'paint after it — not the picture without the step until a build', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    const lineage = 'a-step-past-the-picture';
    final cels = storeWithTheCel();
    final images = LayerFrameImageCache(frameStore: cels);
    addTearDown(images.dispose);
    final overlay = ActiveStrokeOverlayModel(tileSize: tileSize);
    final live = BitmapSurfacePainter(
      surface: BrushFrameDisplayCacheService(
        frameStore: cels,
        canvasSize: canvasSize,
      ).prepareFramePreview(key).previewSurface,
      overlayModel: overlay,
      showTransparentBackground: false,
      lineage: lineage,
    );
    final store = FramePictureStore<FramePictureKey>(gpu: WritesNeverLand());
    addTearDown(store.dispose);
    final run = runOf(images, store);
    final picture = run.pictures.keyOfStack(nodes, frame);
    final view = CanvasViewport(panX: 8, panY: 4);

    await pump(tester, run, key: const ValueKey(0), view: view, live: live);
    expect(
      await settleAsync(tester, () => store.bytesOf(picture) != null),
      isTrue,
      reason: 'LIVENESS: the frame\'s picture is made',
    );
    await lendBothClocks(tester, rounds: 2);
    final before = await onScreen(tester);

    // Right of the page, on the pasteboard the screen shows.
    final past = TileCoord(x: 2, y: 0);
    overlay.showResultTiles([
      PromotedStrokeTile(past, tileOf(past, stroke, (_) => true), 1),
    ]);
    await tester.pump();
    expect(
      store.landingOf(picture),
      isNull,
      reason: '⛔premise: a picture does not grow — no patch goes past it',
    );
    final stepped = await onScreen(tester);
    expect(
      differences(before, stepped),
      isNotEmpty,
      reason: 'the step shows at the paint after it',
    );

    // A view of its own, the step in hand: the frame as it stands.
    final standing = FramePictureStore<FramePictureKey>(
      gpu: WritesNeverLand(),
    );
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
    expect(
      differences(await onScreen(tester), stepped),
      isEmpty,
      reason: 'drawn as it stands, at once',
    );

    await tester.pumpWidget(const SizedBox());
    overlay.dispose();
  });

  testWidgets('🚨the next stroke\'s step while the picture moves to the '
      'frame\'s next key shows at the paint after it, and still as the move '
      'lands — not once its texels are in', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    const lineage = 'a-step-while-it-moves';
    final cels = storeWithTheCel();
    final images = LayerFrameImageCache(frameStore: cels);
    addTearDown(images.dispose);
    final overlay = ActiveStrokeOverlayModel(tileSize: tileSize);
    BitmapSurfacePainter painterOfTheCel() => BitmapSurfacePainter(
      surface: BrushFrameDisplayCacheService(
        frameStore: cels,
        canvasSize: canvasSize,
      ).prepareFramePreview(key).previewSurface,
      overlayModel: overlay,
      showTransparentBackground: false,
      lineage: lineage,
    );
    final gpu = WritesNeverLand();
    final store = FramePictureStore<FramePictureKey>(gpu: gpu);
    addTearDown(store.dispose);
    final run = runOf(images, store);
    final view = CanvasViewport(panX: 8, panY: 4);
    final before = run.pictures.keyOfStack(nodes, frame);

    await pump(
      tester,
      run,
      key: const ValueKey(0),
      view: view,
      live: painterOfTheCel(),
    );
    expect(
      await settleAsync(tester, () => store.bytesOf(before) != null),
      isTrue,
      reason: 'LIVENESS: the frame\'s picture is made',
    );
    await lendBothClocks(tester, rounds: 2);
    final first = TileCoord(x: 0, y: 0);
    overlay.showResultTiles([
      PromotedStrokeTile(first, tileOf(first, stroke, strokeAt.contains), 1),
    ]);
    await tester.pump();
    expect(
      await settleAsync(
        tester,
        () => store.peek(before)!.landing.isNotEmpty,
      ),
      isTrue,
      reason: '⛔premise: the stroke is written into the picture',
    );
    await tester.pump();

    // The pen lifts while the stroke's last step is on its way: the
    // picture's move to the frame's next key waits behind it, and what the
    // lift hands on is patched in under the key it moves to.
    gpu.holdsRenders = true;
    addTearDown(gpu.letAllThrough);
    final last = TileCoord(x: 1, y: 0);
    final lastStep = tileOf(last, stroke, (at) => at.dx < 24 && at.dy < 8);
    overlay.showResultTiles([PromotedStrokeTile(last, lastStep, 1)]);
    await tester.pump();
    expect(
      await settleAsync(tester, () => gpu.rendersWaiting == 1),
      isTrue,
      reason: '⛔premise: the last step is on its way into the picture',
    );
    final drawn = BrushFrameDisplayCacheService(
      frameStore: cels,
      canvasSize: canvasSize,
    ).prepareFramePreview(key).previewSurface;
    cels.storeBakedSurface(
      key,
      BitmapSurface(
        canvasSize: canvasSize,
        tileSize: tileSize,
        tiles: {
          ...drawn.tiles,
          first: tileOf(first, stroke, (_) => true),
          last: lastStep,
        },
      ),
    );
    cels.markCelEdited(key);
    overlay.reset();
    final after = run.pictures.keyOfStack(nodes, frame);
    expect(after, isNot(before), reason: '⛔premise: the frame\'s key moved');
    await pump(
      tester,
      run,
      key: const ValueKey(0),
      view: view,
      live: painterOfTheCel(),
    );
    expect(
      store.peek(after),
      isNull,
      reason: 'LIVENESS: the picture is still on its way to its next key',
    );

    final second = TileCoord(x: 1, y: 1);
    overlay.showResultTiles([
      PromotedStrokeTile(
        second,
        tileOf(second, stroke, (at) => at.dx < 24 && at.dy < 24),
        2,
      ),
    ]);
    await tester.pump();
    final whileItMoves = await onScreen(tester);

    // The move lands — what waits before it let through a render at a
    // time — and the patches behind it, the next stroke's last, still wait.
    while (store.peek(after) == null) {
      expect(
        await settleAsync(
          tester,
          () => gpu.rendersWaiting > 0 || store.peek(after) != null,
        ),
        isTrue,
        reason: 'LIVENESS: the picture answers to the frame\'s next key',
      );
      if (store.peek(after) == null) {
        gpu.letOneThrough();
      }
    }
    expect(
      await settleAsync(tester, () => gpu.rendersWaiting == 1),
      isTrue,
      reason: '⛔premise: the patches behind the move — the next stroke\'s '
          'last — are still on their way, a render at a time',
    );
    await tester.pump();
    final onceMoved = await onScreen(tester);

    // A view of its own, the stroke in hand: the frame as it stands.
    final standing = FramePictureStore<FramePictureKey>(
      gpu: WritesNeverLand(),
    );
    addTearDown(standing.dispose);
    await pump(
      tester,
      runOf(images, standing),
      key: const ValueKey(1),
      view: view,
      live: painterOfTheCel(),
    );
    expect(
      await settleAsync(tester, () => standing.bytesOf(after) != null),
      isTrue,
      reason: 'LIVENESS: its picture is made too',
    );
    await lendBothClocks(tester, rounds: 2);
    final asItStands = await onScreen(tester);
    expect(
      differences(asItStands, whileItMoves),
      isEmpty,
      reason: 'the step shows while the picture moves',
    );
    expect(
      differences(asItStands, onceMoved),
      isEmpty,
      reason: 'and still once it has moved, its texels not yet in',
    );

    gpu.letAllThrough();
    await tester.pumpWidget(const SizedBox());
    overlay.dispose();
  });

  testWidgets('🚨a stroke that lands changes nothing on another screen '
      'showing its frame — not the frame without the stroke for a moment', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    const lineage = 'a-stroke-lands-under-another-screen';
    final cels = storeWithTheCel();
    final images = LayerFrameImageCache(frameStore: cels);
    addTearDown(images.dispose);
    final overlay = ActiveStrokeOverlayModel(tileSize: tileSize);
    BitmapSurfacePainter painterOfTheCel() => BitmapSurfacePainter(
      surface: BrushFrameDisplayCacheService(
        frameStore: cels,
        canvasSize: canvasSize,
      ).prepareFramePreview(key).previewSurface,
      overlayModel: overlay,
      showTransparentBackground: false,
      lineage: lineage,
    );
    final gpu = WritesNeverLand();
    final store = FramePictureStore<FramePictureKey>(gpu: gpu);
    addTearDown(store.dispose);
    final run = runOf(images, store);
    final view = CanvasViewport(panX: 8, panY: 4);
    final before = run.pictures.keyOfStack(nodes, frame);
    final other = GlobalKey();

    // The canvas, and beside it another screen showing the frame's one
    // picture as it stands in the store — a conte's, a parked cut's.
    Future<void> pumpBoth(BitmapSurfacePainter live) => tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox.fromSize(
                size: viewSize,
                child: standingOn(
                  run,
                  picture: frame,
                  nodes: nodes,
                  viewport: view,
                  live: (
                    activeSurfacePainter: live,
                    floatOverlay: null,
                    liftedRows: const {},
                  ),
                ),
              ),
              RepaintBoundary(
                key: other,
                child: Container(
                  width: viewSize.width,
                  height: viewSize.height,
                  color: under,
                  child: FramePictureView(
                    key: const ValueKey('other'),
                    run: run,
                    picture: frame,
                    nodes: nodes,
                    viewport: view,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    /// The other screen as it paints next — for its own reasons, a tick of
    /// its own.
    Future<Shot> otherPaints() async {
      tester
          .renderObject<RenderCustomPaint>(
            find.descendant(
              of: find.byKey(const ValueKey('other')),
              matching: find.byType(CustomPaint),
            ),
          )
          .markNeedsPaint();
      await tester.pump();
      return onScreen(tester, other);
    }

    await pumpBoth(painterOfTheCel());
    expect(
      await settleAsync(tester, () => store.bytesOf(before) != null),
      isTrue,
      reason: 'LIVENESS: the frame\'s picture is made',
    );
    await lendBothClocks(tester, rounds: 2);
    final blank = await otherPaints();
    // The picture landed, as a maker would say — the other screen takes it.
    (run.landings as ValueNotifier<int>).value += 1;
    await tester.pump();
    final shown = await otherPaints();
    expect(
      differences(blank, shown),
      isNotEmpty,
      reason: 'LIVENESS: the other screen shows the frame\'s picture',
    );
    final first = TileCoord(x: 0, y: 0);
    final drawnTile = tileOf(first, stroke, strokeAt.contains);
    overlay.showResultTiles([PromotedStrokeTile(first, drawnTile, 1)]);
    await tester.pump();
    expect(
      await settleAsync(
        tester,
        () => store.peek(before)!.landing.isNotEmpty,
      ),
      isTrue,
      reason: '⛔premise: the stroke is written into the picture',
    );
    final drawn = await otherPaints();
    expect(
      differences(shown, drawn),
      isNotEmpty,
      reason: 'LIVENESS: the stroke is in the picture the other screen shows',
    );

    // The pen lifts: the cel takes the very tile the overlay showed, and
    // lets the overlay go in the same call; the painter of the cel as it
    // is now comes with the next build.
    final committed = BrushFrameDisplayCacheService(
      frameStore: cels,
      canvasSize: canvasSize,
    ).prepareFramePreview(key).previewSurface;
    cels.storeBakedSurface(
      key,
      BitmapSurface(
        canvasSize: canvasSize,
        tileSize: tileSize,
        tiles: {...committed.tiles, first: drawnTile},
      ),
    );
    cels.markCelEdited(key);
    overlay.reset();
    final letGo = store.landingOf(before);
    if (letGo != null) {
      await tester.runAsync(() => letGo);
    }
    gpu.holdsRenders = true;
    addTearDown(gpu.letAllThrough);
    await pumpBoth(painterOfTheCel());

    expect(
      differences(drawn, await otherPaints()),
      isEmpty,
      reason: 'the frame did not change, so the other screen does not',
    );

    gpu.letAllThrough();
    await tester.pumpWidget(const SizedBox());
    overlay.dispose();
  });

  testWidgets('🚨a stroke that lands moves the picture it was written into to '
      'the frame\'s next key — not laid anew — and the next stroke is written '
      'into it there', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    const lineage = 'a-stroke-lands';
    final cels = storeWithTheCel();
    final images = LayerFrameImageCache(frameStore: cels);
    addTearDown(images.dispose);
    final overlay = ActiveStrokeOverlayModel(tileSize: tileSize);
    BitmapSurfacePainter painterOfTheCel() => BitmapSurfacePainter(
      surface: BrushFrameDisplayCacheService(
        frameStore: cels,
        canvasSize: canvasSize,
      ).prepareFramePreview(key).previewSurface,
      overlayModel: overlay,
      showTransparentBackground: false,
      lineage: lineage,
    );
    final gpu = WritesNeverLand();
    final store = _LaysCounted(gpu: gpu);
    addTearDown(store.dispose);
    final run = runOf(images, store);
    final view = CanvasViewport(panX: 8, panY: 4);
    final before = run.pictures.keyOfStack(nodes, frame);

    await pump(
      tester,
      run,
      key: const ValueKey(0),
      view: view,
      live: painterOfTheCel(),
    );
    expect(
      await settleAsync(tester, () => store.bytesOf(before) != null),
      isTrue,
      reason: 'LIVENESS: the frame\'s picture is made',
    );
    await lendBothClocks(tester, rounds: 2);
    final first = TileCoord(x: 0, y: 0);
    overlay.showResultTiles([
      PromotedStrokeTile(first, tileOf(first, stroke, strokeAt.contains), 1),
    ]);
    await tester.pump();
    expect(
      await settleAsync(
        tester,
        () => store.peek(before)!.landing.isNotEmpty,
      ),
      isTrue,
      reason: '⛔premise: the stroke is written into the picture',
    );
    await tester.pump();

    // The pen lifts: the stroke is the cel's, and the pen's row is drawn
    // by a painter of what it holds now.
    final drawn = BrushFrameDisplayCacheService(
      frameStore: cels,
      canvasSize: canvasSize,
    ).prepareFramePreview(key).previewSurface;
    cels.storeBakedSurface(
      key,
      BitmapSurface(
        canvasSize: canvasSize,
        tileSize: tileSize,
        tiles: {
          ...drawn.tiles,
          first: tileOf(first, stroke, (_) => true),
        },
      ),
    );
    cels.markCelEdited(key);
    overlay.reset();
    final after = run.pictures.keyOfStack(nodes, frame);
    expect(after, isNot(before), reason: '⛔premise: the frame\'s key moved');
    await pump(
      tester,
      run,
      key: const ValueKey(0),
      view: view,
      live: painterOfTheCel(),
    );
    expect(
      await settleAsync(tester, () => store.peek(after) != null),
      isTrue,
      reason: 'the picture answers to the frame\'s next key',
    );
    expect(
      store.laid,
      isNot(contains(after)),
      reason: 'moved where it stands, not laid anew',
    );

    // Its patch stays on its way, to be seen going in.
    gpu.holdsRenders = true;
    addTearDown(gpu.letAllThrough);
    final second = TileCoord(x: 1, y: 1);
    overlay.showResultTiles([
      PromotedStrokeTile(
        second,
        tileOf(second, stroke, (at) => at.dx < 24 && at.dy < 24),
        2,
      ),
    ]);
    await tester.pump();
    expect(
      store.landingOf(after),
      isNotNull,
      reason: 'the next stroke is written into the picture under its new '
          'key — not the frame drawn as it stands a step at a time',
    );

    await tester.pumpWidget(const SizedBox());
    overlay.dispose();
  });
}

/// A store that says which keys were laid.
class _LaysCounted extends FramePictureStore<FramePictureKey> {
  _LaysCounted({super.gpu});

  final List<FramePictureKey> laid = [];

  @override
  Future<FramePicture?> lay(
    FramePictureKey key,
    FrameDrawing frame, {
    bool shownNow = false,
  }) {
    laid.add(key);
    return super.lay(key, frame, shownNow: shownNow);
  }
}
