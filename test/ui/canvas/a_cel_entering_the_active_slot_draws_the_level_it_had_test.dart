import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/playback_quality.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_display_cache_service.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/persistence/brush_drawing_binary_codec.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/canvas/tile_pyramid.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';
import '../../helpers/temp_dir.dart';

/// 🚨★★★A CEL THAT BECOMES THE ACTIVE ROW BELOW 100% SHOWS WHAT IT SHOWED A
/// FRAME AGO, AND MAKES NOTHING IN THAT FRAME (2026-09-24, board
/// `a-layer-switch-below-100-composes-the-full-cel`).
///
/// Every other row is one image of its cel at the display's level; the
/// active row is drawn in level blocks, and every block it had no level
/// tile for was made in the switch frame — a `toImageSync` each, a fresh
/// MSAA target and a mip chain. 🔬On the real Windows app at 50% (the
/// user's work file, a 2540×1654 cel): 29–52 level tiles made in the frame
/// of a switch to a layer not stood on before, and the raster thread busy
/// 55–66 ms before it could draw it; the same switch a second time, with
/// the tiles kept, 7–20 ms.
///
/// The stack hands the image the row was drawn with to the pyramid
/// ([TilePyramid.seed]); a block whose tiles are still the ones that image
/// was composed from is drawn from it, 1:1, and only a block whose tiles
/// changed is made.
void main() {
  const tileSize = 16;
  // 4 × 2 tiles: two level-1 blocks of 2 × 2 tiles each.
  const canvasSize = CanvasSize(width: tileSize * 4, height: tileSize * 2);
  // At 50% the whole cel, one device pixel per 2 × 2 canvas pixels.
  const viewSize = Size(tileSize * 2.0, tileSize * 1.0);

  const key = BrushFrameKey(
    projectId: ProjectId('p'),
    trackId: TrackId('t'),
    cutId: CutId('c'),
    layerId: LayerId('entering'),
    frameId: FrameId('f'),
  );

  final screen = GlobalKey();

  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('anicel-entering-the-slot');
  });

  tearDown(() => deleteTempQuietly(tempDir));

  /// A tile whose pixels are opaque gradients on the left three quarters of
  /// the cel and nothing on the rest — so every level texel is a real mean
  /// of four different pixels, and some blocks are part ink, part empty.
  BitmapTile tileAt(int tx, int ty, {int shift = 0}) {
    final pixels = Uint8List(tileSize * tileSize * 4);
    for (var y = 0; y < tileSize; y += 1) {
      for (var x = 0; x < tileSize; x += 1) {
        final cx = tx * tileSize + x;
        final cy = ty * tileSize + y;
        if (cx >= tileSize * 3) {
          continue;
        }
        final o = (y * tileSize + x) * 4;
        pixels[o] = (cx * 5 + shift) & 0xFF;
        pixels[o + 1] = (cy * 7 + shift * 3) & 0xFF;
        pixels[o + 2] = (0x40 + ((cx + cy) & 0x3F)) & 0xFF;
        pixels[o + 3] = 0xFF;
      }
    }
    return BitmapTile(size: tileSize, pixels: pixels);
  }

  /// A store holding [key]'s cel as a FILE-BACKED entry — the image cache
  /// refuses a cel without a drawing state at its first gate.
  BrushFrameStore storeWithTheCel() {
    final blob = AnicelCelBlob.encode(
      AnicelCelEntry.fromSurface(
        key,
        BitmapSurface(
          canvasSize: canvasSize,
          tileSize: tileSize,
          tiles: {
            for (var ty = 0; ty < 2; ty += 1)
              for (var tx = 0; tx < 4; tx += 1)
                TileCoord(x: tx, y: ty): tileAt(tx, ty),
          },
        ),
      ),
    );
    final file = File('${tempDir.path}/cel.bin')..writeAsBytesSync(blob.bytes);
    return BrushFrameStore()
      ..restoreFromFile({
        key: AnicelCelFileRef(
          filePath: file.path,
          dataOffset: 0,
          length: blob.bytes.length,
          canvasSize: canvasSize,
          tileSize: tileSize,
        ),
      });
  }

  /// The surface a canvas paints the cel from — the same tile objects the
  /// image cache composes.
  BitmapSurface surfaceOf(BrushFrameStore store) => BrushFrameDisplayCacheService(
    frameStore: store,
    canvasSize: canvasSize,
  ).prepareFramePreview(key).previewSurface;

  Future<void> pumpStack(
    WidgetTester tester,
    LayerFrameImageCache images, {
    required bool active,
    BitmapSurfacePainter? painter,
    Key? stackKey,
    double zoom = 0.5,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: RepaintBoundary(
            key: screen,
            child: ClipRect(
              child: SizedBox(
                width: viewSize.width,
                height: viewSize.height,
                child: CanvasLayerStackView(
                  key: stackKey,
                  nodes: [
                    CompositeLeaf<CanvasStackRow>(
                      active
                          ? const CanvasActiveLayerRow(opacity: 1, frameKey: key)
                          : const CanvasLayerImageRequest(
                              frameKey: key,
                              opacity: 1,
                            ),
                    ),
                  ],
                  imageCache: images,
                  canvasSize: canvasSize,
                  viewport: CanvasViewport(zoom: zoom),
                  activeSurfacePainter: active ? painter : null,
                  debugDisableBake: true,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  /// What the last pump put on screen, read off the layer tree.
  Future<Uint8List> onScreen(WidgetTester tester) async {
    final render =
        screen.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final bytes = await tester.runAsync(() async {
      final image = await render.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return data!.buffer.asUint8List();
    });
    return bytes!;
  }

  /// Whether every pixel of [rgba] is the same — nothing drawn over the
  /// background.
  bool blank(Uint8List rgba) {
    for (var i = 4; i < rgba.length; i += 1) {
      if (rgba[i] != rgba[i % 4]) {
        return false;
      }
    }
    return true;
  }

  /// Lets the asynchronous pass land the row's image.
  Future<void> landEverything(WidgetTester tester) async {
    for (var i = 0; i < 6; i += 1) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump();
    }
  }

  BitmapSurfacePainter painterOf(BitmapSurface surface, Object lineage) =>
      BitmapSurfacePainter(
        surface: surface,
        showTransparentBackground: false,
        lineage: lineage,
      );

  /// The bytes of the device pixels over canvas block [blockX] (a level-1
  /// block is 32 canvas px = 16 device px wide at 50%).
  List<int> block(Uint8List rgba, int blockX) => [
    for (var y = 0; y < viewSize.height.toInt(); y += 1)
      for (var x = blockX * 16; x < blockX * 16 + 16; x += 1)
        ...rgba.sublist(
          (y * viewSize.width.toInt() + x) * 4,
          (y * viewSize.width.toInt() + x) * 4 + 4,
        ),
  ];

  /// The cel as a stack row, its level image already in the cache (as every
  /// row's is once the editor has sat idle), then as the ACTIVE row for one
  /// frame.
  Future<({Uint8List bytes, BitmapSurface surface})> enterTheSlot(
    WidgetTester tester,
    LayerFrameImageCache images,
    BrushFrameStore store,
    Object lineage,
  ) async {
    await tester.runAsync(
      () => images.prepare(
        key: key,
        canvasSize: canvasSize,
        quality: PlaybackQuality.forLevel(1),
        sourceEffects: const [],
      ),
    );
    await pumpStack(tester, images, active: false);
    await landEverything(tester);
    expect(
      blank(await onScreen(tester)),
      isFalse,
      reason: 'fixture: the row is on screen from its image',
    );
    final surface = surfaceOf(store);
    // THE SWITCH — one frame, ⛔not pumpAndSettle.
    await pumpStack(
      tester,
      images,
      active: true,
      painter: painterOf(surface, lineage),
    );
    return (bytes: await onScreen(tester), surface: surface);
  }

  // The pyramid is one for the whole run: each test names a scope of its
  // own and lets it go ([TilePyramid.drop] takes the seed with it).

  testWidgets('🚨at 50% the frame a cel becomes the active row makes no level '
      'tile — its blocks are drawn from the image it was drawn with', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = storeWithTheCel();
    final images = LayerFrameImageCache(frameStore: store);
    addTearDown(images.dispose);
    const lineage = 'entering-no-tile';
    addTearDown(() => TilePyramid.instance.drop(lineage));

    await enterTheSlot(tester, images, store, lineage);

    expect(
      TilePyramid.instance.debugHasSeed(lineage),
      isTrue,
      reason: 'fixture: the stack handed the row\'s image over as it left',
    );
    expect(
      TilePyramid.instance.debugTileCountOf(lineage),
      0,
      reason: 'every block still shows what the image was composed from, so '
          'nothing is made — each block made here is a snapshot in the '
          'switch frame, 29–52 of them on the user\'s work file',
    );
  });

  testWidgets('🚨and what it draws is the very picture the pyramid makes — '
      'byte for byte', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = storeWithTheCel();
    final images = LayerFrameImageCache(frameStore: store);
    addTearDown(images.dispose);
    const seeded = 'entering-seeded';
    const made = 'entering-made';
    addTearDown(() => TilePyramid.instance.drop(seeded));
    addTearDown(() => TilePyramid.instance.drop(made));

    final entered = await enterTheSlot(tester, images, store, seeded);
    expect(TilePyramid.instance.debugTileCountOf(seeded), 0);

    // The same cel as the active row in a stack that held no image of it:
    // no seed, so the pyramid makes every block.
    await pumpStack(
      tester,
      images,
      active: true,
      painter: painterOf(entered.surface, made),
      stackKey: UniqueKey(),
    );
    expect(
      TilePyramid.instance.debugTileCountOf(made),
      2,
      reason: 'fixture: the pyramid made both blocks this time',
    );
    expect(
      await onScreen(tester),
      entered.bytes,
      reason: 'a level of the whole image and the halving of its blocks are '
          'the same means — the seed may change how the frame is made, never '
          'what it shows',
    );
  });

  testWidgets('a block whose tile changed is made; the block beside it is '
      'still drawn from the image', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = storeWithTheCel();
    final images = LayerFrameImageCache(frameStore: store);
    addTearDown(images.dispose);
    const lineage = 'entering-edited';
    addTearDown(() => TilePyramid.instance.drop(lineage));

    final entered = await enterTheSlot(tester, images, store, lineage);

    // A stroke lands in block 0: one tile there is a new object.
    final edited = entered.surface.putTiles([
      (coord: TileCoord(x: 1, y: 1), tile: tileAt(1, 1, shift: 90)),
    ]);
    await pumpStack(
      tester,
      images,
      active: true,
      painter: painterOf(edited, lineage),
    );
    final after = await onScreen(tester);

    expect(
      TilePyramid.instance.debugTileCountOf(lineage),
      1,
      reason: 'the edited block alone is made — its tiles are no longer what '
          'the image was composed from',
    );
    expect(
      block(after, 0),
      isNot(block(entered.bytes, 0)),
      reason: 'the edit shows: the image\'s stale part is never drawn',
    );
    expect(
      block(after, 1),
      block(entered.bytes, 1),
      reason: 'the untouched block is the image\'s, as it was',
    );
  });

  testWidgets('a zoom to another level does not draw from an image of the '
      'last one', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = storeWithTheCel();
    final images = LayerFrameImageCache(frameStore: store);
    addTearDown(images.dispose);
    const lineage = 'entering-then-zooming';
    const fresh = 'zoomed-fresh';
    addTearDown(() => TilePyramid.instance.drop(lineage));
    addTearDown(() => TilePyramid.instance.drop(fresh));

    final entered = await enterTheSlot(tester, images, store, lineage);
    expect(TilePyramid.instance.debugHasSeed(lineage), isTrue);

    // 25%: level 2. The seed is a level-1 image and must not be read as one.
    await pumpStack(
      tester,
      images,
      active: true,
      painter: painterOf(entered.surface, lineage),
      zoom: 0.25,
    );
    final zoomed = await onScreen(tester);
    await pumpStack(
      tester,
      images,
      active: true,
      painter: painterOf(entered.surface, fresh),
      zoom: 0.25,
      stackKey: UniqueKey(),
    );
    expect(
      zoomed,
      await onScreen(tester),
      reason: 'at a level the seed was not made at, the blocks come from the '
          'pyramid, as they do for a cel nothing was handed over for',
    );
  });

  testWidgets('the image goes when the cel leaves the active slot', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = storeWithTheCel();
    final images = LayerFrameImageCache(frameStore: store);
    addTearDown(images.dispose);
    const lineage = 'entering-and-leaving';
    addTearDown(() => TilePyramid.instance.drop(lineage));

    await enterTheSlot(tester, images, store, lineage);
    expect(TilePyramid.instance.debugHasSeed(lineage), isTrue);

    await pumpStack(tester, images, active: false);
    expect(
      TilePyramid.instance.debugHasSeed(lineage),
      isFalse,
      reason: 'a row back in the stack is drawn from its own image again — '
          'the handed-over copy would only hold its pixels',
    );
  });
}
