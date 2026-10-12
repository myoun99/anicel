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

/// F-313 (유저 2026-10-08): 「다른행이동하면 일시적으로 빈 블록으로 만드는
/// 로직 있는거같은데 싹 삭제하고 법 통일. 항상 보여야함」.
///
/// A move that carries a cel onto another row shows it, until the release,
/// under the row it came from (`celPixelsRowOf`); the release re-keys its
/// pixels onto the row it lands on. The picture does not change — only the
/// key the canvas asks with does — so the frame it lands on shows it as the
/// frame before did, whichever way it arrives there.
///
/// 🔬Measured before the pictures travelled with their cel (2026-10-12):
/// **0 of 32** columns on the first frame after the release, at 50% and at
/// 100%, for a cel that lands as an image row (an onion ghost, a row of a
/// multi-row move the brush is not on).
void main() {
  const tileSize = 16;
  const tileCount = 8;
  const canvasSize = CanvasSize(width: tileSize * tileCount, height: tileSize);
  const viewSize = Size(tileSize * 2.0, tileSize * 1.0);

  BrushFrameKey keyOf(String layer) => BrushFrameKey(
    projectId: const ProjectId('p'),
    trackId: const TrackId('t'),
    cutId: const CutId('c'),
    layerId: LayerId(layer),
    frameId: const FrameId('f'),
  );

  final from = keyOf('from');
  final to = keyOf('to');

  final screen = GlobalKey();

  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('anicel-carried-cel');
  });

  tearDown(() => deleteTempQuietly(tempDir));

  /// A store whose [from] row holds one blue, FILE-BACKED cel of eight tiles
  /// — file-backed because the image cache refuses a cel without a drawing
  /// state at its first gate.
  BrushFrameStore blueStore() {
    final tiles = <TileCoord, BitmapTile>{};
    for (var x = 0; x < tileCount; x += 1) {
      final pixels = Uint8List(tileSize * tileSize * 4);
      for (var i = 0; i < pixels.length; i += 4) {
        pixels[i + 2] = 0xFF;
        pixels[i + 3] = 0xFF;
      }
      tiles[TileCoord(x: x, y: 0)] = BitmapTile(size: tileSize, pixels: pixels);
    }
    final blob = AnicelCelBlob.encode(
      AnicelCelEntry.fromSurface(
        from,
        BitmapSurface(canvasSize: canvasSize, tileSize: tileSize, tiles: tiles),
      ),
    );
    final file = File('${tempDir.path}/cel.bin')..writeAsBytesSync(blob.bytes);
    return BrushFrameStore()..restoreFromFile({
      from: AnicelCelFileRef(
        filePath: file.path,
        dataOffset: 0,
        length: blob.bytes.length,
        canvasSize: canvasSize,
        tileSize: tileSize,
      ),
    });
  }

  /// [key]'s cel as an image row — or, with [active], as the row the brush
  /// is on, painted from its tiles.
  Future<void> pumpRow(
    WidgetTester tester,
    LayerFrameImageCache images,
    BrushFrameKey key, {
    required double zoom,
    BitmapSurfacePainter? active,
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
                  nodes: [
                    CompositeLeaf<CanvasStackRow>(
                      active == null
                          ? CanvasLayerImageRequest(frameKey: key, opacity: 1)
                          : CanvasActiveLayerRow(opacity: 1, frameKey: key),
                    ),
                  ],
                  imageCache: images,
                  canvasSize: canvasSize,
                  viewport: CanvasViewport(zoom: zoom),
                  activeSurfacePainter: active,
                  debugDisableBake: true,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Future<int> blueColumns(WidgetTester tester, double zoom) async {
    final render =
        screen.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final rgba = (await tester.runAsync(() async {
      final image = await render.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return data!.buffer.asUint8List();
    }))!;
    var n = 0;
    final row = (tileSize * zoom / 2).floor();
    for (var x = 0; x < viewSize.width.toInt(); x += 1) {
      final o = (row * viewSize.width.toInt() + x) * 4;
      if (rgba[o + 2] > 0xC8 && rgba[o + 3] == 0xFF) n += 1;
    }
    return n;
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

  /// The cel on screen under the row it came from, as the drag shows it,
  /// then the release's rekey.
  Future<(BrushFrameStore, LayerFrameImageCache)> carryAndRelease(
    WidgetTester tester, {
    required double zoom,
  }) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = blueStore();
    final images = LayerFrameImageCache(frameStore: store);
    addTearDown(images.dispose);

    await pumpRow(tester, images, from, zoom: zoom);
    await landEverything(tester);
    expect(
      await blueColumns(tester, zoom),
      viewSize.width.toInt(),
      reason: 'fixture: the drag shows the cel under the row it came from',
    );
    store.rekeyFrames([(from, to)]);
    return (store, images);
  }

  for (final zoom in [0.5, 1.0]) {
    testWidgets('🚨at ${(zoom * 100).round()}%: a cel that lands as an image '
        'row is whole on the first frame after the release', (tester) async {
      final (_, images) = await carryAndRelease(tester, zoom: zoom);

      // ONE frame — ⛔not pumpAndSettle, which lets the asynchronous pass
      // land.
      await pumpRow(tester, images, to, zoom: zoom);
      expect(await blueColumns(tester, zoom), viewSize.width.toInt());
    });
  }

  testWidgets('🚨at 50%: a cel that lands as the row the brush is on draws its '
      'blocks from the picture it was shown with, making none', (tester) async {
    final (store, images) = await carryAndRelease(tester, zoom: 0.5);
    const lineage = 'carried-into-the-slot';
    addTearDown(() => TilePyramid.instance.drop(lineage));

    await pumpRow(
      tester,
      images,
      to,
      zoom: 0.5,
      active: BitmapSurfacePainter(
        surface: BrushFrameDisplayCacheService(
          frameStore: store,
          canvasSize: canvasSize,
        ).prepareFramePreview(to).previewSurface,
        showTransparentBackground: false,
        lineage: lineage,
      ),
    );

    expect(await blueColumns(tester, 0.5), viewSize.width.toInt());
    expect(
      TilePyramid.instance.debugHasSeed(lineage),
      isTrue,
      reason: 'the picture the row was shown with is handed over as it '
          'becomes the brush\'s, as it is when a row is stood on '
          '(a_cel_entering_the_active_slot_draws_the_level_it_had_test)',
    );
    expect(TilePyramid.instance.debugTileCountOf(lineage), 0);
  });
}
