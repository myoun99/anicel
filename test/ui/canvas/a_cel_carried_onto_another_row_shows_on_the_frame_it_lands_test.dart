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
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';
import '../../helpers/cels_kept_in_a_file.dart';
import '../../helpers/settle_async.dart';

/// F-313 (유저 2026-10-08): 「다른행이동하면 일시적으로 빈 블록으로 만드는
/// 로직 있는거같은데 싹 삭제하고 법 통일. 항상 보여야함」.
///
/// A move that carries a cel onto another row shows it, until the release,
/// under the row it came from (`celPixelsOf`); the release re-keys its
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

  /// One opaque cel of eight tiles, full in colour [channel] (0 red, 2 blue).
  BitmapSurface opaque(int channel) {
    final tiles = <TileCoord, BitmapTile>{};
    for (var x = 0; x < tileCount; x += 1) {
      final pixels = Uint8List(tileSize * tileSize * 4);
      for (var i = 0; i < pixels.length; i += 4) {
        pixels[i + channel] = 0xFF;
        pixels[i + 3] = 0xFF;
      }
      tiles[TileCoord(x: x, y: 0)] = BitmapTile(size: tileSize, pixels: pixels);
    }
    return BitmapSurface(
      canvasSize: canvasSize,
      tileSize: tileSize,
      tiles: tiles,
    );
  }

  /// A store whose cels are each [opaque] in the channel [channelOf] names,
  /// FILE-BACKED — because the image cache refuses a cel without a drawing
  /// state at its first gate.
  BrushFrameStore celStore(Map<BrushFrameKey, int> channelOf) {
    final store = BrushFrameStore();
    keepInAFile(store, {
      for (final MapEntry(:key, value: channel) in channelOf.entries)
        key: opaque(channel),
    });
    return store;
  }

  /// [key]'s cel as an image row — as the stack draws an onion ghost — over
  /// [under]'s, an image row too.
  Future<void> pumpRow(
    WidgetTester tester,
    LayerFrameImageCache images,
    BrushFrameKey key, {
    required double zoom,
    BrushFrameKey? under,
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
                    if (under != null)
                      CompositeLeaf<CanvasStackRow>(
                        CanvasLayerImageRequest(frameKey: under, opacity: 1),
                      ),
                    CompositeLeaf<CanvasStackRow>(
                      CanvasLayerImageRequest(frameKey: key, opacity: 1),
                    ),
                  ],
                  imageCache: images,
                  canvasSize: canvasSize,
                  viewport: CanvasViewport(zoom: zoom),
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

  /// Lets the asynchronous pass land the rows' images.
  Future<void> landEverything(WidgetTester tester) => lendBothClocks(
    tester,
    rounds: 6,
    beat: const Duration(milliseconds: 30),
  );

  /// The cel on screen under the row it came from, as the drag shows it,
  /// then the release's rekey.
  Future<(BrushFrameStore, LayerFrameImageCache)> carryAndRelease(
    WidgetTester tester, {
    required double zoom,
  }) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = celStore({from: 2});
    final images = LayerFrameImageCache(frameStore: store);
    addTearDown(images.dispose);

    await pumpRow(tester, images, from, zoom: zoom);
    expect(
      await settleAsync(
        tester,
        () async =>
            await blueColumns(tester, zoom) == viewSize.width.toInt(),
      ),
      isTrue,
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

  // ↩️A cel that landed as the row the brush is on drew its blocks from the
  // picture it was shown with (`TilePyramid.seed`), until the canvas that
  // stands showed the frame's one picture, which a rekey does not change
  // (one-picture-per-frame ②-5a).

  testWidgets('a picture the view held under the key the cel lands on is let '
      'go — its pin with it — and the cel is what that key shows', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);
    // A red cel under the key the blue one is carried to.
    final store = celStore({from: 2, to: 0});
    final images = LayerFrameImageCache(frameStore: store);
    addTearDown(images.dispose);
    await pumpRow(tester, images, from, zoom: 1, under: to);
    await landEverything(tester);

    store.rekeyFrames([(from, to)]);
    await pumpRow(tester, images, to, zoom: 1);
    expect(await blueColumns(tester, 1), viewSize.width.toInt());

    await tester.pumpWidget(const SizedBox());
    expect(
      images.pinnedBytes,
      0,
      reason: 'every picture the view held is let go with the view — the one '
          'the carried cel took the key of as well',
    );
  });
}
