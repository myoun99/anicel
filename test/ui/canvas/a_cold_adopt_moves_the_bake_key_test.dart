import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/playback_quality.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/persistence/brush_drawing_binary_codec.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';

/// 유저 2026-08-27, iPhone (H27 잔여): 「**변형툴의 외곽에만** 그림이 남음 …
/// 변형중에는 해당 그림 사라지고 … 이전에 확정했던게 존재하고 변형중이 아닌
/// 상황에서만 외곽에 지금까지 확정했던 그림들이 남아있음. **보기에만** 그[렇다]」.
///
/// The active layer paints live and everything around it is replayed from the
/// kept composite, so a stale bake shows up as exactly that: a ring of old
/// drawing around a correct one, with the pixels themselves fine.
///
/// The bake's key carries `_imagesRevision`, whose own note says it moves at
/// EVERY `_images` mutation. It did not: a DROP bumped it and a cold ADOPT —
/// nothing held yet, so the assignment took the empty branch — did not. The
/// key therefore did not move when a layer's picture arrived, and `keepFor`
/// kept the composite recorded without it.
void main() {
  const tileSize = 16;
  const key = BrushFrameKey(
    projectId: ProjectId('p'),
    trackId: TrackId('t'),
    cutId: CutId('c'),
    layerId: LayerId('l'),
    frameId: FrameId('f'),
  );
  const settled = BrushFrameKey(
    projectId: ProjectId('p'),
    trackId: TrackId('t'),
    cutId: CutId('c'),
    layerId: LayerId('settled'),
    frameId: FrameId('f'),
  );
  const canvasSize = CanvasSize(width: tileSize * 4, height: tileSize);
  const size = Size(tileSize * 4.0, tileSize * 1.0);

  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('anicel-bake-key');
  });

  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  BrushFrameStore drawnStore() {
    final tiles = <TileCoord, BitmapTile>{};
    for (var x = 0; x < 4; x += 1) {
      final pixels = Uint8List(tileSize * tileSize * 4);
      for (var i = 0; i < pixels.length; i += 4) {
        pixels[i + 2] = 0xFF;
        pixels[i + 3] = 0xFF;
      }
      tiles[TileCoord(x: x, y: 0)] = BitmapTile(
        coord: TileCoord(x: x, y: 0),
        size: tileSize,
        pixels: pixels,
      );
    }
    final surface = BitmapSurface(
      canvasSize: canvasSize,
      tileSize: tileSize,
      tiles: tiles,
    );
    final blob = AnicelCelBlob.encode(AnicelCelEntry.fromSurface(key, surface));
    final file = File('${dir.path}/cel.bin')..writeAsBytesSync(blob.bytes);
    final store = BrushFrameStore();
    final ref = AnicelCelFileRef(
      filePath: file.path,
      dataOffset: 0,
      length: blob.bytes.length,
      canvasSize: canvasSize,
      tileSize: tileSize,
    );
    store.restoreFromFile({key: ref, settled: ref});
    return store;
  }

  Future<void> pumpStack(
    WidgetTester tester,
    LayerFrameImageCache imageCache,
  ) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: CanvasLayerStackView(
                nodes: const [
                  // The one that is ALREADY there — the bake records this,
                  // and it is the ring the user sees around the live layer.
                  CanvasLayerImageNode(
                    CanvasLayerImageRequest(frameKey: settled, opacity: 1),
                  ),
                  // The one whose picture arrives later, cold.
                  CanvasLayerImageNode(
                    CanvasLayerImageRequest(frameKey: key, opacity: 1),
                  ),
                ],
                imageCache: imageCache,
                canvasSize: canvasSize,
                viewport: CanvasViewport(),
                // ⚠️The bake stays ON — it IS the thing under test. Every
                // other file in this folder disables it to see the paint body.
                //
                // The PAPER gives the bake something to hold before any
                // picture arrives: an empty stack records no slots at all,
                // and then "invalidated" and "never had anything" look the
                // same, which is the reading mistake this whole round is
                // about one level up.
                paintPaper: true,
              ),
            ),
          ),
        ),
      ),
    );
  }

  CustomPainter stackPainter(WidgetTester tester) => tester
      .widgetList<CustomPaint>(
        find.descendant(
          of: find.byType(CanvasLayerStackView),
          matching: find.byType(CustomPaint),
        ),
      )
      .where((paint) => paint.painter != null)
      .first
      .painter!;

  /// Paints once, which is what fills the bake's slots.
  void paintOnce(WidgetTester tester) {
    final recorder = ui.PictureRecorder();
    stackPainter(tester).paint(Canvas(recorder, Offset.zero & size), size);
    recorder.endRecording().dispose();
  }

  /// ⚠️`as dynamic`, the way the other bake tests in this folder reach in:
  /// the State class is private and these getters are its hatches.
  int revisionOf(WidgetTester tester) =>
      // ignore: avoid_dynamic_calls
      (tester.state(find.byType(CanvasLayerStackView)) as dynamic)
              .debugImagesRevision
          as int;

  testWidgets('a picture ARRIVING moves the bake key, so the kept composite '
      'cannot replay without it', (tester) async {
    final store = drawnStore();
    // Nothing ready for the second layer: the stack mounts holding no image
    // for it, which is the state a COLD adopt starts from.
    final cache = _ColdThenWarm(frameStore: store);
    await pumpStack(tester, cache);
    paintOnce(tester);
    final before = revisionOf(tester);

    // The picture becomes available and the sweep adopts it — cold, because
    // nothing was held for that key.
    cache.warm = true;
    await tester.runAsync(
      () => cache.prepare(
        key: key,
        canvasSize: canvasSize,
        quality: PlaybackQuality.full,
      ),
    );
    await pumpStack(tester, cache);

    expect(
      revisionOf(tester),
      greaterThan(before),
      reason: 'the bake key reads this, so a picture that arrives without '
          'moving it leaves the kept composite replaying the frame before — '
          '유저: 「변형툴의 외곽에만 그림이 남음 … 보기에만 그[렇다]」',
    );
  });
}

/// A cache that answers nothing until [warm] is set.
class _ColdThenWarm extends LayerFrameImageCache {
  _ColdThenWarm({required super.frameStore});

  bool warm = false;

  @override
  LayerFrameImage? prepareSyncOrNull({
    required BrushFrameKey key,
    required CanvasSize canvasSize,
    required PlaybackQuality quality,
  }) => (warm || key.layerId.value == 'settled')
      ? super.prepareSyncOrNull(
          key: key,
          canvasSize: canvasSize,
          quality: quality,
        )
      : null;

  @override
  Future<LayerFrameImage?> prepare({
    required BrushFrameKey key,
    required CanvasSize canvasSize,
    required PlaybackQuality quality,
    bool Function()? shouldAbort,
  }) => (warm || key.layerId.value == 'settled')
      ? super.prepare(
          key: key,
          canvasSize: canvasSize,
          quality: quality,
          shouldAbort: shouldAbort,
        )
      : Future<LayerFrameImage?>.value(null);
}

