// A NEW PICTURE FOR A KEY THE STACK ALREADY HOLDS REPLACES IT — AND THE
// VIEW REPAINTS WITH IT.
//
// Two survivors of the mutation campaign (2026-09-04, the image-adoption
// unification): an adopt that kept whatever it held for a key, and an
// async pass whose changes never asked for a repaint. Every existing test
// watched a picture ARRIVE cold; none watched one CHANGE. These put a
// blue cel behind the key, let the stack adopt it, then put a RED cel
// behind the same key — once with the cache warmed (the sync sweep
// adopts) and once cold (the async pass adopts, so its repaint request is
// on the line).
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
import 'package:anicel/src/models/composite_tree.dart';

void main() {
  const tileSize = 16;
  const key = BrushFrameKey(
    projectId: ProjectId('p'),
    trackId: TrackId('t'),
    cutId: CutId('c'),
    layerId: LayerId('l'),
    frameId: FrameId('f'),
  );
  const canvasSize = CanvasSize(width: tileSize, height: tileSize);
  const size = Size(tileSize * 1.0, tileSize * 1.0);

  /// A cel blob the store can hold for [key].
  AnicelCelBlob blobOf(BitmapSurface surface) =>
      AnicelCelBlob.encode(AnicelCelEntry.fromSurface(key, surface));

  /// One solid tile: [red] or blue.
  BitmapSurface solid({required bool red}) {
    final pixels = Uint8List(tileSize * tileSize * 4);
    for (var i = 0; i < pixels.length; i += 4) {
      pixels[i + (red ? 0 : 2)] = 0xFF;
      pixels[i + 3] = 0xFF;
    }
    final coord = TileCoord(x: 0, y: 0);
    return BitmapSurface(
      canvasSize: canvasSize,
      tileSize: tileSize,
      tiles: {coord: BitmapTile(size: tileSize, pixels: pixels)},
    );
  }

  Future<void> pumpStack(WidgetTester tester, LayerFrameImageCache cache) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: CanvasLayerStackView(
                nodes: const [
                  CompositeLeaf<CanvasStackRow>(
                    CanvasLayerImageRequest(frameKey: key, opacity: 1),
                  ),
                ],
                imageCache: cache,
                canvasSize: canvasSize,
                viewport: CanvasViewport(),
                paintPaper: false,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Decodes the cel into the cache, so the stack's SYNC sweep finds it.
  Future<void> warm(WidgetTester tester, LayerFrameImageCache cache) {
    return tester.runAsync(
      () => cache.prepare(
        key: key,
        canvasSize: canvasSize,
        quality: PlaybackQuality.full,
        sourceEffects: const [],
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

  /// The centre pixel the stack paints right now, as (r, g, b, a).
  Future<List<int>> centrePixel(WidgetTester tester) {
    return tester
        .runAsync(() async {
          final recorder = ui.PictureRecorder();
          stackPainter(
            tester,
          ).paint(Canvas(recorder, Offset.zero & size), size);
          final picture = recorder.endRecording();
          final image = picture.toImageSync(tileSize, tileSize);
          picture.dispose();
          final data = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          image.dispose();
          final bytes = data!.buffer.asUint8List();
          const i = (tileSize ~/ 2 * tileSize + tileSize ~/ 2) * 4;
          return [bytes[i], bytes[i + 1], bytes[i + 2], bytes[i + 3]];
        })
        .then((pixel) => pixel!);
  }

  /// A store holding a BLUE cel for [key], its cache, and the stack
  /// pumped with that blue picture already on screen.
  Future<(BrushFrameStore, LayerFrameImageCache)> blueOnScreen(
    WidgetTester tester,
  ) async {
    final store = BrushFrameStore()
      ..restoreBaked({key: blobOf(solid(red: false))});
    final cache = LayerFrameImageCache(frameStore: store);
    await warm(tester, cache);
    await pumpStack(tester, cache);
    await tester.pump();
    final blue = await centrePixel(tester);
    expect(
      blue[2],
      greaterThan(128),
      reason:
          'the first picture is on screen — without it the red '
          'expectation below would pass on a stack that simply never held '
          'anything',
    );
    expect(blue[0], lessThan(128));
    return (store, cache);
  }

  testWidgets('the sync sweep: a warm new picture for a HELD key replaces '
      'the one held', (tester) async {
    final (store, cache) = await blueOnScreen(tester);
    store.restoreBaked({key: blobOf(solid(red: true))});
    cache.invalidateFrame(key);
    await warm(tester, cache);
    await pumpStack(tester, cache);
    await tester.pump();
    final red = await centrePixel(tester);
    expect(
      red[0],
      greaterThan(128),
      reason:
          'the new picture replaces the held one — a hold that keeps '
          'whatever it has shows the previous cel for ever',
    );
    expect(red[2], lessThan(128));
  });

  testWidgets('the async pass: a COLD new picture for a HELD key replaces '
      'it and asks the view to repaint', (tester) async {
    final (store, cache) = await blueOnScreen(tester);
    store.restoreBaked({key: blobOf(solid(red: true))});
    cache.invalidateFrame(key);
    // Nothing warmed: the sync sweep misses and the ASYNC pass adopts, so
    // the repaint it asks for is what puts the new cel on screen.
    await pumpStack(tester, cache);
    var pixel = await centrePixel(tester);
    for (var i = 0; i < 30 && pixel[0] < 128; i += 1) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      pixel = await centrePixel(tester);
    }
    expect(
      pixel[0],
      greaterThan(128),
      reason: 'the async pass adopted the new picture AND asked to repaint',
    );
    expect(pixel[2], lessThan(128));
  });
}
