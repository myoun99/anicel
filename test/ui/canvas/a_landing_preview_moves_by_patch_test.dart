// A PREVIEW THAT MOVES PATCHES THE PICTURE — THE OLD RECT AND THE NEW —
// INSTEAD OF COMPOSITING THE WHOLE FRAME AGAIN.
//
// 🚨★★★F-130 measured it on the stamp's ghost (2026-09-15,
// `cursor_at_os_speed_benchmark_test`, the stamp arm): 25 moves of the held
// piece, 25 FULL composes of the display buffer, 0 patches — 23ms a frame
// on the debug bar where the brush's own hover cost 8. The ghost was in the
// buffer's KEY (F-33: it rode the surface painter, so the buffer held it)
// but not in its TOKENS, so a hover was a miss that could not say where it
// changed and fell through to the full raster. The tokens carry the
// painter's preview, and a move is the union of where it was and where it
// is. The pixels are pinned equal to the frame drawn as it stands.
//
// ↩️The ghost was the preview these tests moved — F-33 untouched on
// purpose: it rode the surface painter and composited as the layer — until
// brush-fidelity-Q9 (유저 2026-10-18 「통일하면 좋음」) made it the overlay's
// tiles, the click's own bytes. What the text tool floats over its hole
// (F-344) is the painter's preview now. ↩️The patches went into the
// canvas's display buffer, until a canvas that stands patched them into
// the frame's one picture (one-picture-per-frame ②-5a).
//
// 🪦The two routes that once replaced the walk — the flat projection below
// the knee, and the first-activation stand-in — never drew the ghost at
// all (the walk's `_paintStampPreview` was its only draw), and for a week
// each drew it over its own image. Both routes are gone (the projection
// with the render round, the stand-in on 2026-09-17): the tiles are the
// one draw the active slot has, so the last test pins the frame the
// stand-in existed for — activation (↩️with the ghost over the tiles, until
// brush-fidelity-Q9).
//
// The patches are Flutter GPU's writes: the picture holds them only where
// the GPU wrote them, so this runs in the `gpu` tag's batch.
@Tags(['gpu'])
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/dirty_region.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/brush_live_stroke_rasterizer.dart';
import 'package:anicel/src/ui/canvas/active_stroke_overlay.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/bitmap_tile_image_cache.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/canvas/landing_preview.dart';
import 'package:anicel/src/ui/canvas/selection_float_overlay.dart';
import 'package:anicel/src/ui/playback/frame_picture_store.dart';
import 'package:anicel/src/ui/playback/frame_picture_view.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';
import 'package:anicel/src/ui/playback/stacked_frame_picture.dart';
import '../../helpers/a_canvas_standing_on_a_frame.dart';
import '../../helpers/cels_kept_in_a_file.dart';
import '../../helpers/settle_async.dart';
import '../../helpers/the_frame_as_it_stands.dart';

void main() {
  const side = 32;
  const canvasSize = CanvasSize(width: side, height: side);
  const viewSize = Size(side * 1.0, side * 1.0);
  final screen = GlobalKey();

  BrushFrameKey keyOf(String layer) => BrushFrameKey(
    projectId: const ProjectId('p'),
    trackId: const TrackId('t'),
    cutId: const CutId('c'),
    layerId: LayerId(layer),
    frameId: const FrameId('f'),
  );
  final picture = (
    cut: Cut(
      id: const CutId('c'),
      name: 'c',
      duration: 1,
      canvasSize: canvasSize,
      layers: const [],
    ),
    frameIndex: 0,
    paintPaper: true,
  );

  /// One tile of [colour] at the pixels [inked] says, clear elsewhere.
  BitmapTile tileOf(List<int> colour, bool Function(int x, int y) inked) {
    final pixels = Uint8List(16 * 16 * 4);
    for (var y = 0; y < 16; y += 1) {
      for (var x = 0; x < 16; x += 1) {
        if (inked(x, y)) {
          pixels.setRange((y * 16 + x) * 4, (y * 16 + x) * 4 + 4, colour);
        }
      }
    }
    return BitmapTile(size: 16, pixels: pixels);
  }

  BitmapSurface surfaceOf(Map<TileCoord, BitmapTile> tiles) =>
      BitmapSurface(canvasSize: canvasSize, tileSize: 16, tiles: tiles);

  /// What the text tool floats over a text's hole, as it carries the text:
  /// a 4×4 square of red ink at the far corner of a tile of its own, moved
  /// by whole pixels (`CelTextFloat` — a lifted selection's pure move).
  final carried = BitmapSurfacePainter(
    surface: surfaceOf({
      TileCoord(x: 0, y: 0): tileOf(
        [0xFF, 0, 0, 0xFF],
        (x, y) => x >= 12 && y >= 12,
      ),
    }),
    showTransparentBackground: false,
    lineage: 'f344-float-under-test',
  );
  SelectionFloatPaint floatAt(double x, double y) => SelectionFloatPaint(
    surface: carried,
    surfaceOffset: CanvasPoint(x: x, y: y),
  );

  /// A canvas standing on the frame [nodes] stack, its pictures kept by
  /// [store], once its picture is made.
  Future<StackRun> standOn(
    WidgetTester tester,
    LayerFrameImageCache images,
    FramePictureStore<FramePictureKey> store, {
    required List<CompositeNode<CanvasStackRow>> nodes,
    required BitmapSurfacePainter live,
    required Key view,
  }) async {
    final run = runOver(
      images,
      store,
      canvasSize: canvasSize,
      stackOf: (_) => nodes,
    );
    await tester.pumpWidget(
      onAScreen(
        screen,
        size: viewSize,
        under: const Color(0xFF808080),
        view: standingOn(
          run,
          key: view,
          picture: picture,
          nodes: nodes,
          viewport: CanvasViewport(),
          live: (
            activeSurfacePainter: live,
            floatOverlay: null,
            liftedRows: const {},
          ),
        ),
      ),
    );
    final shown = run.pictures.keyOfStack(nodes, picture);
    expect(
      await settleAsync(tester, () => store.bytesOf(shown) != null),
      isTrue,
      reason: 'LIVENESS: the frame\'s picture is made',
    );
    await lendBothClocks(tester, rounds: 2);
    return run;
  }

  /// [change] made, then the paint after it: what moved is patched into
  /// [shown]'s picture — held on its way until that is seen — and lands.
  Future<void> patchedIn(
    WidgetTester tester,
    WritesLand gpu,
    FramePictureStore<FramePictureKey> store,
    FramePictureKey shown,
    Future<void> Function() change, {
    required String what,
  }) async {
    gpu.holdsRenders = true;
    await change();
    await tester.pump();
    final landing = store.landingOf(keptByTheCanvas(tester, shown));
    expect(
      landing,
      isNotNull,
      reason: 'LIVENESS: $what is patched into the picture — not the frame '
          'drawn as it stands',
    );
    gpu.letAllThrough();
    await inThePicture(tester, landing);
  }

  testWidgets('🚨F-344: a LANDING PREVIEW that moves is where it was and '
      'where it is, one pixel of hairline', (tester) async {
    final preview = ValueNotifier<LandingPreview?>(floatAt(2, 2));
    addTearDown(preview.dispose);
    final frame = stackedFrameOf(
      const [CompositeLeaf<CanvasStackRow>(CanvasActiveLayerRow(opacity: 1))],
      page: (
        canvasSize: canvasSize,
        pasteboardReach: PasteboardReach.whole,
        paintPaper: false,
        paperBackground: ProjectBackground.defaultBackground,
      ),
      surfaceOf: (_) => null,
      live: (
        rows: (
          activeSurfacePainter: BitmapSurfacePainter(
            surface: surfaceOf({
              TileCoord(x: 0, y: 0): BitmapTile.blank(size: 16),
            }),
            showTransparentBackground: false,
            landingPreview: preview,
          ),
          floatOverlay: null,
          liftedRows: const {},
        ),
        painters: LiftedRowPainters(),
      ),
    );
    final before = frame.tokens!;
    final was = preview.value!.drawnWorldRect;

    // THE CARRY: the float moves, nothing else does — out past the live
    // row's one tile.
    preview.value = floatAt(10, 8);
    final moved = frame.movedSince(before);

    expect(moved.located, isTrue, reason: 'it is a patch');
    expect(
      moved.dirty,
      was.expandToInclude(preview.value!.drawnWorldRect).inflate(1),
      reason: 'where it was and where it is, one pixel of hairline',
    );
  });

  testWidgets('🚨F-344: a landing preview patched into the picture as it '
      'comes and as it moves shows what the frame drawn as it stands shows', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    final cel = keyOf('l');
    // A blue pixel in the far corner: a cel with nothing on it is no part
    // of its frame's picture.
    BitmapSurface theCel() => surfaceOf({
      TileCoord(x: 1, y: 1): tileOf(
        [0, 0, 0xFF, 0xFF],
        (x, y) => x == 15 && y == 15,
      ),
    });
    final cels = BrushFrameStore();
    keepInAFile(cels, {cel: theCel()});
    final images = LayerFrameImageCache(frameStore: cels);
    addTearDown(images.dispose);
    final preview = ValueNotifier<LandingPreview?>(null);
    addTearDown(preview.dispose);
    final live = BitmapSurfacePainter(
      surface: theCel(),
      showTransparentBackground: false,
      landingPreview: preview,
    );
    final nodes = [
      CompositeLeaf<CanvasStackRow>(
        CanvasActiveLayerRow(opacity: 1, frameKey: cel),
      ),
    ];
    final gpu = WritesLand();
    addTearDown(gpu.letAllThrough);
    final store = FramePictureStore<FramePictureKey>(gpu: gpu);
    addTearDown(store.dispose);
    final run = await standOn(
      tester,
      images,
      store,
      nodes: nodes,
      live: live,
      view: const ValueKey(0),
    );
    final shown = run.pictures.keyOfStack(nodes, picture);
    bool isRed(Shot shot, int x, int y) =>
        shot.rgba[(y * shot.width + x) * 4] > 200 &&
        shot.rgba[(y * shot.width + x) * 4 + 1] < 60;

    await patchedIn(tester, gpu, store, shown, () async {
      preview.value = floatAt(2, 2);
    }, what: 'the preview as it comes');
    expect(
      isRed(await shotOf(tester, screen), 15, 15),
      isTrue,
      reason: 'it is drawn where it is',
    );
    await patchedIn(tester, gpu, store, shown, () async {
      preview.value = floatAt(10, 8);
    }, what: 'the preview as it moves');
    final patched = await shotOf(tester, screen);
    expect(isRed(patched, 15, 15), isFalse, reason: 'the old place is cleared');
    expect(isRed(patched, 23, 21), isTrue, reason: 'the new place is inked');

    // A view of its own, the preview in hand: the frame as it stands.
    final standing = FramePictureStore<FramePictureKey>(gpu: WritesNeverLand());
    addTearDown(standing.dispose);
    await standOn(
      tester,
      images,
      standing,
      nodes: nodes,
      live: live,
      view: const ValueKey(1),
    );
    expect(
      differences(await shotOf(tester, screen), patched),
      isEmpty,
      reason: 'the patched picture is the frame as it stands',
    );
  }, skip: noFlutterGpu != null);

  // ↩️A preview that crossed the edge of the live row's extent moved the
  // display buffer's rect, and the carry had to repaint both its places
  // (F-85, adversarial review 2026-09-15), until nothing kept a buffer
  // (one-picture-per-frame ②-5a). A picture does not grow: what goes past
  // it draws the frame as it stands
  // (`a_stroke_is_written_into_the_picture_shown_test`).

  testWidgets('an EMPTY cel: the second step of a stroke patches — an empty '
      'snapshot is a base, not 「nothing kept」', (tester) async {
    // The stamp's usual target is an empty cel, and so is every drawing's
    // first stroke. The snapshot of an empty surface has no tiles; reading
    // that as a cold start (the old `kept.tiles.isEmpty`) refused the patch
    // on every step until the first commit put tiles there.
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    // The frame's picture is of the row under it: the empty cel is no part
    // of it.
    final under = keyOf('under');
    final cels = BrushFrameStore();
    keepInAFile(cels, {
      under: surfaceOf({
        TileCoord(x: 1, y: 1): tileOf(
          [0, 0, 0xFF, 0xFF],
          (x, y) => x == 15 && y == 15,
        ),
      }),
    });
    final images = LayerFrameImageCache(frameStore: cels);
    addTearDown(images.dispose);
    final overlay = ActiveStrokeOverlayModel(tileSize: 16);
    addTearDown(overlay.dispose);
    final rasterizer = BrushLiveStrokeRasterizer(
      pasteboard: canvasSize.pasteboardAt(PasteboardReach.whole),
    );
    final nodes = [
      CompositeLeaf<CanvasStackRow>(
        CanvasLayerImageRequest(frameKey: under, opacity: 1),
      ),
      CompositeLeaf<CanvasStackRow>(
        CanvasActiveLayerRow(opacity: 1, frameKey: keyOf('empty')),
      ),
    ];
    BrushDab dabAt(double x, {int sequence = 0}) => BrushDab(
      center: CanvasPoint(x: x, y: 6),
      color: 0xFF000000,
      size: 3,
      opacity: 1,
      flow: 1,
      hardness: 1,
      tipShape: BrushTipShape.round,
      pressure: 1,
      sequence: sequence,
    );
    final gpu = WritesLand();
    addTearDown(gpu.letAllThrough);
    final store = FramePictureStore<FramePictureKey>(gpu: gpu);
    addTearDown(store.dispose);
    final run = await standOn(
      tester,
      images,
      store,
      nodes: nodes,
      live: BitmapSurfacePainter(
        surface: surfaceOf(const {}),
        overlayModel: overlay,
        showTransparentBackground: false,
      ),
      view: const ValueKey(0),
    );
    final shown = run.pictures.keyOfStack(nodes, picture);

    await patchedIn(tester, gpu, store, shown, () async {
      await tester.runAsync(() async {
        rasterizer.blendFrom([dabAt(4)], from: 0);
        overlay.updateRegion(
          source: rasterizer,
          region: DirtyRegion.fromXYWH(x: 2, y: 4, width: 5, height: 5),
        );
      });
    }, what: 'the first step');
    await patchedIn(tester, gpu, store, shown, () async {
      await tester.runAsync(() async {
        rasterizer.blendFrom([dabAt(4), dabAt(8, sequence: 1)], from: 1);
        overlay.updateRegion(
          source: rasterizer,
          region: DirtyRegion.fromXYWH(x: 6, y: 4, width: 5, height: 5),
        );
      });
    }, what: 'the second step');
  }, skip: noFlutterGpu != null);

  testWidgets('on the activation frame the tiles draw themselves', (
    tester,
  ) async {
    // A file-backed cel shown as it is stored, then promoted with a tile
    // cache that knows none of its fresh tile objects — the frame the
    // first-activation stand-in used to exist for; every tile pictures
    // itself inside this paint now (2026-09-17).
    const tileSize = 16;
    const tileCount = 4;
    final key = keyOf('l');
    const celSize = CanvasSize(width: tileCount * tileSize, height: tileSize);
    final celBox = Size(celSize.width.toDouble(), celSize.height.toDouble());
    final tiles = <TileCoord, BitmapTile>{};
    for (var x = 0; x < tileCount; x += 1) {
      final pixels = Uint8List(tileSize * tileSize * 4);
      for (var i = 0; i < pixels.length; i += 4) {
        pixels[i + 2] = 0xFF;
        pixels[i + 3] = 0xFF;
      }
      tiles[TileCoord(x: x, y: 0)] = BitmapTile(size: tileSize, pixels: pixels);
    }
    final store = BrushFrameStore();
    keepInAFile(store, {
      key: BitmapSurface(canvasSize: celSize, tileSize: tileSize, tiles: tiles),
    });
    final imageCache = LayerFrameImageCache(frameStore: store);
    expect(
      imageCache.storedSurfaceOrNull(key, canvasSize: celSize),
      isNotNull,
      reason: 'fixture: the inactive route has the cel',
    );

    Future<void> pumpStack({
      required List<CompositeNode<CanvasStackRow>> nodes,
      BitmapSurfacePainter? activeSurfacePainter,
    }) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: celBox.width,
              height: celBox.height,
              child: TheFrameAsItStands(
                nodes: nodes,
                imageCache: imageCache,
                canvasSize: celSize,
                viewport: CanvasViewport(),
                activeSurfacePainter: activeSurfacePainter,
              ),
            ),
          ),
        ),
      ),
    );

    Future<Uint8List> paintStack() async {
      final painter = tester
          .widgetList<CustomPaint>(
            find.descendant(
              of: find.byType(TheFrameAsItStands),
              matching: find.byType(CustomPaint),
            ),
          )
          .where((paint) => paint.painter != null)
          .first
          .painter!;
      final recorder = ui.PictureRecorder();
      painter.paint(Canvas(recorder, Offset.zero & celBox), celBox);
      final picture = recorder.endRecording();
      try {
        return (await tester.runAsync(() async {
          final image = await picture.toImage(celSize.width, celSize.height);
          try {
            final data = await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            );
            return data!.buffer.asUint8List();
          } finally {
            image.dispose();
          }
        }))!;
      } finally {
        picture.dispose();
      }
    }

    List<int> rgbaAt(Uint8List px, int x, int y) {
      final o = (y * celSize.width + x) * 4;
      return [px[o], px[o + 1], px[o + 2], px[o + 3]];
    }

    await pumpStack(
      nodes: [
        CompositeLeaf<CanvasStackRow>(
          CanvasLayerImageRequest(frameKey: key, opacity: 1),
        ),
      ],
    );
    await paintStack();

    // ACTIVATION. ↩️It was made with a ghost already in hand — the stamp
    // tool picked before the layer — and pinned the ghost drawn over the
    // tiles, until brush-fidelity-Q9 made the ghost the overlay's tiles
    // rather than this painter's draw.
    final painter = BitmapSurfacePainter(
      surface: store.bakedSurfaceOrNull(key)!,
      showTransparentBackground: false,
      lineage: 'ghost-stand-in-under-test',
      tileImageCache: BitmapTileImageCache(),
    );
    await pumpStack(
      nodes: const [
        CompositeLeaf<CanvasStackRow>(CanvasActiveLayerRow(opacity: 1)),
      ],
      activeSurfacePainter: painter,
    );
    final swapFrame = await paintStack();
    expect(
      rgbaAt(swapFrame, 8, 8),
      [0, 0, 255, 255],
      reason: 'the tiles draw the artwork on the activation frame',
    );
  });
}
