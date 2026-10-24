import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
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
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/project_background.dart';
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
import 'package:anicel/src/ui/canvas/tile_pyramid.dart';
import 'package:anicel/src/ui/playback/frame_picture_gpu.dart';
import 'package:anicel/src/ui/playback/frame_picture_store.dart';
import 'package:anicel/src/ui/playback/frame_picture_view.dart';
import 'package:anicel/src/ui/playback/frame_pictures.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';
import 'package:anicel/src/ui/playback/stacked_frame_picture.dart';
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
/// A stroke that lands moves the picture to the frame's next key where it
/// stands, and the next stroke is written into it there.
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
  ) {
    final landings = ValueNotifier<int>(0);
    addTearDown(landings.dispose);
    return (
      landings: landings,
      pictures: FramePictures(
        store: store,
        layerImages: images,
        stackOf: (_) => nodes,
        pageOf: (picture) => (
          canvasSize: canvasSize,
          pasteboardReach: PasteboardReach.whole,
          paintPaper: picture.paintPaper,
          paperBackground: ProjectBackground.defaultBackground,
        ),
      ),
    );
  }

  Future<void> pump(
    WidgetTester tester,
    StackRun run, {
    required Key key,
    required CanvasViewport view,
    required BitmapSurfacePainter live,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: RepaintBoundary(
          key: screen,
          child: ClipRect(
            child: Container(
              width: viewSize.width,
              height: viewSize.height,
              color: under,
              child: FramePictureView(
                key: key,
                run: run,
                picture: frame,
                nodes: nodes,
                viewport: view,
                live: (
                  activeSurfacePainter: live,
                  floatOverlay: null,
                  liftedRows: const {},
                ),
                laysWhatItMisses: true,
                wholeFrames: false,
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Future<({Uint8List rgba, int width})> onScreen(WidgetTester tester) async {
    final render =
        screen.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final shot = await tester.runAsync(() async {
      final image = await render.toImage(
        pixelRatio: tester.view.devicePixelRatio,
      );
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final width = image.width;
      image.dispose();
      return (rgba: data!.buffer.asUint8List(), width: width);
    });
    return shot!;
  }

  List<String> differences(
    ({Uint8List rgba, int width}) a,
    ({Uint8List rgba, int width}) b,
  ) => [
    for (var at = 0; at < a.rgba.length; at += 4)
      if (!listEquals(a.rgba.sublist(at, at + 4), b.rgba.sublist(at, at + 4)))
        '(${at ~/ 4 % a.width}, ${at ~/ 4 ~/ a.width}): '
            '${a.rgba.sublist(at, at + 4)} → ${b.rgba.sublist(at, at + 4)}',
  ];

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
        addTearDown(() => TilePyramid.instance.drop(lineage));
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
        final store = FramePictureStore<FramePictureKey>(
          gpu: _WritesNeverLand(),
        );
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

        overlay.showResultTiles([
          PromotedStrokeTile(
            TileCoord(x: 0, y: 0),
            tileOf(TileCoord(x: 0, y: 0), stroke, strokeAt.contains),
            1,
          ),
        ]);
        final step = store.landingOf(picture);
        expect(
          step,
          isNotNull,
          reason: 'LIVENESS: the step is on its way into the picture, not '
              'the frame drawn as it stands',
        );
        await tester.pump();
        final landing = await onScreen(tester);
        expect(
          differences(before, landing),
          isNotEmpty,
          reason: 'LIVENESS: the step shows while it lands',
        );

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
          gpu: _WritesNeverLand(),
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

  testWidgets('🚨a stroke that lands moves the picture it was written into to '
      'the frame\'s next key — not laid anew — and the next stroke is written '
      'into it there', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    const lineage = 'a-stroke-lands';
    addTearDown(() => TilePyramid.instance.drop(lineage));
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
    final store = _LaysCounted(gpu: _WritesNeverLand());
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
    final step = store.landingOf(before);
    expect(
      step,
      isNotNull,
      reason: '⛔premise: the stroke is written into the picture',
    );
    await tester.runAsync(() => step!);
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

    final second = TileCoord(x: 1, y: 1);
    overlay.showResultTiles([
      PromotedStrokeTile(
        second,
        tileOf(second, stroke, (at) => at.dx < 24 && at.dy < 24),
        2,
      ),
    ]);
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

/// A GPU whose writes never come back: every patch stays drawn over its
/// picture ([FramePicture.landing]), so what shows once it lands is the
/// patch's own texels.
class _WritesNeverLand implements FramePictureGpu {
  @override
  Future<ui.Image> render(ui.Picture picture, int width, int height) =>
      picture.toImage(width, height);

  @override
  Object? hold(ui.Image image) => image;

  @override
  int levelsOf(Object held) {
    final image = held as ui.Image;
    return math.max(image.width, image.height).bitLength;
  }

  @override
  Future<bool> writeBase(Object held, List<BaseWrite> writes) =>
      Completer<bool>().future;

  @override
  Future<bool> writeLevels(Object held, ui.Image run, List<RunSpan> spans) =>
      Completer<bool>().future;
}
