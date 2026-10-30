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
import 'a_canvas_standing_on_a_frame.dart';
import 'cels_kept_in_a_file.dart';
import 'settle_async.dart';

/// 🚨A STROKE'S STEP IS WRITTEN INTO THE PICTURE THE CANVAS SHOWS
/// (one-picture-per-frame ②-4): where it lands is patched into the frame's
/// one picture, and the screen shows that picture ALONE — as it was while
/// the step is on its way into it, and with the step once its texels are
/// in every level of it, pixel for pixel what the frame drawn as it stands
/// shows, through a pan, a zoom in and out and a device's ratio (F-465, 유저
/// 채팅 2026-10-26: 「그럼 그냥 바로 바로쓰기로 바꾸고, 잔재들 없애고」).
///
/// The ink is translucent and no paper lies under it, so anything drawn
/// OVER the picture shows its ink twice.
///
/// A step shows at the paint after its texels are in, with no build
/// between; where it goes past the picture (a picture does not grow), the
/// whole frame as it stands shows at the paint after it.
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
///
/// The writes are Flutter GPU's ([WritesLand]): the files that call this
/// carry the `gpu` tag, and on a runner with none every pin skips.
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
  final skipped = skip || noFlutterGpu != null;
  const tileSize = 16;
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
  final frame = (cut: cut, frameIndex: 0, paintPaper: false, ghosts: FrameGhosts.none);
  final screen = GlobalKey();

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

  /// A tile of [colour] wherever [inside] holds, and clear elsewhere.
  BitmapTile tileOf(
    TileCoord coord,
    List<int> colour,
    bool Function(Offset at) inside,
  ) => tileAt(coord, (at) => inside(at) ? colour : null);

  BrushFrameStore storeWithTheCel() {
    final store = BrushFrameStore();
    keepInAFile(store, {
      key: BitmapSurface(
        canvasSize: canvasSize,
        tileSize: tileSize,
        tiles: {
          for (var ty = 0; ty < (page.height / tileSize).ceil(); ty += 1)
            for (var tx = 0; tx < (page.width / tileSize).ceil(); tx += 1)
              TileCoord(x: tx, y: ty): tileAt(TileCoord(x: tx, y: ty), inkOf),
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

  /// What a view of its own shows of the frame, the rows [live] draws in
  /// hand before it takes a picture: the frame drawn as it stands.
  Future<Shot> asItStands(
    WidgetTester tester,
    LayerFrameImageCache images, {
    required FramePictureKey picture,
    required CanvasViewport view,
    required BitmapSurfacePainter live,
  }) async {
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
    return onScreen(tester);
  }

  for (final MapEntry(key: name, value: view) in views.entries) {
    for (final ratio in ratios) {
      testWidgets('🚨$name (ratio $ratio): the screen shows the frame\'s one '
          'picture — as it was while a step is on its way into it, and with '
          'it once it is in, as the frame drawn as it stands shows', (
        tester,
      ) async {
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
        final gpu = WritesLand();
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
        final stroked = TileCoord(
          x: strokeAt.left ~/ tileSize,
          y: strokeAt.top ~/ tileSize,
        );
        overlay.showResultTiles([
          PromotedStrokeTile(
            stroked,
            tileAt(
              stroked,
              (at) => strokeAt.contains(at) ? stroke : inkOf(at),
            ),
            1,
          ),
        ]);
        await tester.pump();
        final step = store.landingOf(keptByTheCanvas(tester, picture));
        expect(
          step,
          isNotNull,
          reason: 'LIVENESS: the step is on its way into the picture, not '
              'the frame drawn as it stands',
        );
        expect(
          differences(before, await onScreen(tester)),
          isEmpty,
          reason: 'while the step is on its way, the screen shows the '
              'picture as it was — nothing drawn over it',
        );

        gpu.letAllThrough();
        await inThePicture(tester, step);
        final shown = await onScreen(tester);
        expect(
          differences(before, shown),
          isNotEmpty,
          reason: 'LIVENESS: the step shows at the paint after it is in',
        );

        expect(
          differences(
            await asItStands(
              tester,
              images,
              picture: picture,
              view: view,
              live: live,
            ),
            shown,
            by: apartBy,
          ),
          isEmpty,
          reason: 'once it is in, the picture shows what the frame drawn as '
              'it stands shows — at every level the view reads',
        );

        await tester.pumpWidget(const SizedBox());
        overlay.dispose();
      }, skip: skipped);
    }
  }

  if (!withThePinsOfNoView) {
    return;
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
    final store = FramePictureStore<FramePictureKey>(gpu: WritesLand());
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

    // Left of the page, on the pasteboard the screen shows — past the
    // grid its picture lies on, which reaches right of the page.
    final past = TileCoord(x: -1, y: 0);
    overlay.showResultTiles([
      PromotedStrokeTile(past, tileOf(past, stroke, (_) => true), 1),
    ]);
    await tester.pump();
    expect(
      store.landingOf(keptByTheCanvas(tester, picture)),
      isNull,
      reason: '⛔premise: a picture does not grow — no patch goes past it',
    );
    final stepped = await onScreen(tester);
    expect(
      differences(before, stepped),
      isNotEmpty,
      reason: 'the step shows at the paint after it',
    );
    expect(
      differences(
        await asItStands(
          tester,
          images,
          picture: picture,
          view: view,
          live: live,
        ),
        stepped,
      ),
      isEmpty,
      reason: 'drawn as it stands, at once',
    );

    await tester.pumpWidget(const SizedBox());
    overlay.dispose();
  }, skip: skipped);

  testWidgets('🚨the steps a pen takes while one is on its way wait for it and '
      'go in as ONE patch — no queue grows behind the pen (F-512)', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    const lineage = 'steps-wait-for-the-one-on-its-way';
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
    final gpu = WritesLand();
    final store = FramePictureStore<FramePictureKey>(gpu: gpu);
    addTearDown(store.dispose);
    final run = runOf(images, store);
    final picture = run.pictures.keyOfStack(nodes, frame);
    final view = CanvasViewport();

    await pump(tester, run, key: const ValueKey(0), view: view, live: live);
    expect(
      await settleAsync(tester, () => store.bytesOf(picture) != null),
      isTrue,
      reason: 'LIVENESS: the frame\'s picture is made',
    );
    await lendBothClocks(tester, rounds: 2);

    void step(TileCoord at) => overlay.showResultTiles([
      PromotedStrokeTile(at, tileOf(at, stroke, (_) => true), 1),
    ]);

    gpu.holdsRenders = true;
    addTearDown(gpu.letAllThrough);
    step(TileCoord(x: 0, y: 0));
    await tester.pump();
    final first = store.landingOf(keptByTheCanvas(tester, picture));
    expect(first, isNotNull, reason: 'LIVENESS: the first is on its way');

    step(TileCoord(x: 1, y: 0));
    await tester.pump();
    step(TileCoord(x: 0, y: 1));
    await tester.pump();

    gpu.letAllThrough();
    await inThePicture(tester, first);
    await inThePicture(
      tester,
      store.landingOf(keptByTheCanvas(tester, picture)),
    );
    expect(
      gpu.patchesWritten,
      2,
      reason: 'the first step, and the two behind it as one',
    );
    expect(
      differences(
        await asItStands(
          tester,
          images,
          picture: picture,
          view: view,
          live: live,
        ),
        await onScreen(tester),
      ),
      isEmpty,
      reason: 'and all three are in the picture',
    );

    await tester.pumpWidget(const SizedBox());
    overlay.dispose();
  }, skip: skipped);

  testWidgets('🚨a step whose write throws shows at the paint after it is '
      'answered — the frame drawn as it stands, not the picture without it '
      '(F-509)', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    const lineage = 'a-step-whose-write-throws';
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
    final gpu = WritesThrow();
    final store = FramePictureStore<FramePictureKey>(gpu: gpu);
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

    gpu.holdsRenders = true;
    addTearDown(gpu.letAllThrough);
    final stroked = TileCoord(
      x: strokeAt.left ~/ tileSize,
      y: strokeAt.top ~/ tileSize,
    );
    overlay.showResultTiles([
      PromotedStrokeTile(
        stroked,
        tileAt(stroked, (at) => strokeAt.contains(at) ? stroke : inkOf(at)),
        1,
      ),
    ]);
    await tester.pump();
    final step = store.landingOf(keptByTheCanvas(tester, picture));
    expect(step, isNotNull, reason: '⛔premise: on its way into the picture');
    bool? landed;
    step!.then((now) => landed = now).ignore();
    gpu.letAllThrough();
    expect(
      await settleAsync(tester, () => landed != null),
      isTrue,
      reason: 'LIVENESS: a step whose write threw is answered',
    );
    expect(landed, isFalse, reason: '⛔premise: it never went in');
    expect(
      tester.takeException(),
      isA<StateError>(),
      reason: 'the throw is reported, not swallowed',
    );
    await tester.pump();
    final stepped = await onScreen(tester);
    expect(
      differences(before, stepped),
      isNotEmpty,
      reason: 'the step shows at the paint after it is answered',
    );
    expect(
      differences(
        await asItStands(
          tester,
          images,
          picture: picture,
          view: view,
          live: live,
        ),
        stepped,
      ),
      isEmpty,
      reason: 'drawn as it stands',
    );

    await tester.pumpWidget(const SizedBox());
    overlay.dispose();
  }, skip: skipped);

  for (final painted in [true, false]) {
    testWidgets('🚨the next stroke\'s step while the picture moves to the '
        'frame\'s next key is written into it there, and shows once it is in '
        '— not left out until the move lands'
        '${painted ? '' : ', nor the frame drawn as it stands where the step '
                  'came before the move did'}', (tester) async {
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
      final gpu = WritesLand();
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
      await inThePicture(
        tester,
        store.landingOf(keptByTheCanvas(tester, before)),
      );

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
      expect(
        after,
        isNot(before),
        reason: '⛔premise: the frame\'s key moved',
      );
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

      final moving = store.landingOf(after);
      expect(
        moving,
        isNotNull,
        reason: 'the stroke is stored and nothing no cel stores is shown: '
            'the picture moves to the frame\'s own key',
      );
      final second = TileCoord(x: 1, y: 1);
      void showTheSecondStep() => overlay.showResultTiles([
        PromotedStrokeTile(
          second,
          tileOf(second, stroke, (at) => at.dx < 24 && at.dy < 24),
          2,
        ),
      ]);
      if (painted) {
        showTheSecondStep();
        await tester.pump();
      } else {
        // The pen put down again at once: the step is on screen as the last
        // one's write is in — before the move comes in, painted only after.
        gpu.beforeTheNextLands = showTheSecondStep;
        gpu.letAllThrough();
        await inThePicture(tester, moving);
      }
      final secondStep = store.landingOf(keptByTheCanvas(tester, after));
      expect(
        secondStep,
        allOf(isNotNull, isNot(same(moving))),
        reason: 'the next stroke\'s step is on its way into the picture under '
            'the key it moves to, behind the move — ⛔not the frame drawn as '
            'it stands from here, a step at a time',
      );

      gpu.letAllThrough();
      await inThePicture(tester, secondStep);
      expect(
        differences(
          await asItStands(
            tester,
            images,
            picture: after,
            view: view,
            live: painterOfTheCel(),
          ),
          await onScreen(tester),
        ),
        isEmpty,
        reason: 'the step shows once it is in the picture it moved',
      );

      await tester.pumpWidget(const SizedBox());
      overlay.dispose();
    }, skip: skipped);
  }

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
    final gpu = WritesLand();
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
    await inThePicture(
      tester,
      store.landingOf(keptByTheCanvas(tester, before)),
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
      await inThePicture(tester, letGo);
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
  }, skip: skipped);

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
    final gpu = WritesLand();
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
    await inThePicture(
      tester,
      store.landingOf(keptByTheCanvas(tester, before)),
    );

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
    // What the lift changed goes in behind the move, and a step waits for
    // the one before it.
    expect(
      await settleAsync(
        tester,
        () =>
            store.landingOf(after) == null &&
            store.landingOf(keptByTheCanvas(tester, after)) == null,
      ),
      isTrue,
      reason: 'LIVENESS: what the lift changed is in',
    );
    await tester.pump();

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
    final secondStep = store.landingOf(keptByTheCanvas(tester, after));
    expect(
      secondStep,
      isNotNull,
      reason: 'the next stroke is written into the picture under its new '
          'key — not the frame drawn as it stands a step at a time',
    );

    // The next stroke lands as the first did.
    gpu.letAllThrough();
    await inThePicture(tester, secondStep);
    final drawnNow = BrushFrameDisplayCacheService(
      frameStore: cels,
      canvasSize: canvasSize,
    ).prepareFramePreview(key).previewSurface;
    cels.storeBakedSurface(
      key,
      BitmapSurface(
        canvasSize: canvasSize,
        tileSize: tileSize,
        tiles: {
          ...drawnNow.tiles,
          second: tileOf(second, stroke, (at) => at.dx < 24 && at.dy < 24),
        },
      ),
    );
    cels.markCelEdited(key);
    overlay.reset();
    final next = run.pictures.keyOfStack(nodes, frame);
    expect(next, isNot(after), reason: '⛔premise: the frame\'s key moved');
    await pump(
      tester,
      run,
      key: const ValueKey(0),
      view: view,
      live: painterOfTheCel(),
    );
    expect(
      await settleAsync(tester, () => store.peek(next) != null),
      isTrue,
      reason: 'the picture answers to the frame\'s key after the next stroke',
    );
    expect(
      store.laid,
      isNot(contains(next)),
      reason: 'the next stroke\'s landing moves it again, not laid anew',
    );

    await tester.pumpWidget(const SizedBox());
    overlay.dispose();
  }, skip: skipped);
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
