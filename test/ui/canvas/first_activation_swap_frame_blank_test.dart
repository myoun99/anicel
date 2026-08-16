import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/core/sync_image_upload.dart';
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
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/bitmap_tile_image_cache.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/debug/measurement_mode.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';

/// The FIRST-ACTIVATION swap-frame law (device report 2026-08-17: old file
/// opened, layers with existing art; the FIRST time each layer was made
/// active its picture disappeared for one frame, then returned; never
/// again for that layer).
///
/// The broken frame sequence this closes:
///  1. While INACTIVE the layer paints as a cached image
///     (CanvasLayerImageNode) — the stack state holds a clone of it.
///  2. Activation swaps its leaf to CanvasActiveLayerNode; the editing
///     seed promotes the FILE-BACKED cel synchronously
///     (BrushFrameStore.bakedSurfaceOrNull) — every tile of the promoted
///     surface is a FRESH object.
///  3. BitmapTileImageCache keys images by tile identity, so it has none
///     of them; the flat projection refuses; the only same-frame answers
///     are the sync-upload budget (Impeller, 32/paint) and the per-pixel
///     budget (4). Everything past them was SILENT — the blank.
///  4. Decodes land within a few frames and the picture returns. A second
///     activation reuses the SAME hot surface instance, whose tile objects
///     still hold their decoded images — clean by construction.
///
/// THE LAW: the active slot draws the held image of step 1 — truth pixels
/// for exactly this cel, drawn at the same rect with the same sampling as
/// the frame before, so the handoff has no seam — while ZERO decoded tile
/// images exist for the promoted surface. That predicate is precisely the
/// first-activation frame, and it is checked at PAINT time: the moment ANY
/// picture exists the walk takes over, so the stand-in can never outrank
/// truth (the third test pins that with an edit).
///
/// The magenta oracle (MeasurementMode.showUnpaintedTiles) fills exactly
/// the coordinates the painter could not draw.
void main() {
  const tileSize = 16;
  const key = BrushFrameKey(
    projectId: ProjectId('p'),
    trackId: TrackId('t'),
    cutId: CutId('c'),
    layerId: LayerId('l'),
    frameId: FrameId('f'),
  );

  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('anicel-swap-frame-test');
    MeasurementMode.showUnpaintedTiles.value = true;
  });

  tearDown(() {
    MeasurementMode.showUnpaintedTiles.value = false;
    debugSyncImageUploadOverride = null;
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  BitmapTile filledTile(
    int x, {
    required int r,
    required int g,
    required int b,
  }) {
    final pixels = Uint8List(tileSize * tileSize * 4);
    for (var i = 0; i < pixels.length; i += 4) {
      pixels[i] = r;
      pixels[i + 1] = g;
      pixels[i + 2] = b;
      pixels[i + 3] = 0xFF;
    }
    return BitmapTile(
      coord: TileCoord(x: x, y: 0),
      size: tileSize,
      pixels: pixels,
    );
  }

  /// A one-row surface of [tileCount] fully-drawn tiles (opaque blue).
  BitmapSurface drawnSurface(int tileCount) {
    final tiles = <TileCoord, BitmapTile>{};
    for (var x = 0; x < tileCount; x += 1) {
      final tile = filledTile(x, r: 0, g: 0, b: 0xFF);
      tiles[tile.coord] = tile;
    }
    return BitmapSurface(
      canvasSize: CanvasSize(width: tileCount * tileSize, height: tileSize),
      tileSize: tileSize,
      tiles: tiles,
    );
  }

  /// Round-trips [surface] through the saved-file shape and registers it
  /// FILE-BACKED — the exact state every cel is in right after a project
  /// open (BrushFrameStore.restoreFromFile).
  BrushFrameStore openShapedStore(BitmapSurface surface) {
    final blob = AnicelCelBlob.encode(AnicelCelEntry.fromSurface(key, surface));
    final file = File('${tempDir.path}/cel.bin')..writeAsBytesSync(blob.bytes);
    final store = BrushFrameStore();
    store.restoreFromFile({
      key: AnicelCelFileRef(
        filePath: file.path,
        dataOffset: 0,
        length: blob.bytes.length,
        canvasSize: surface.canvasSize,
        tileSize: tileSize,
      ),
    });
    return store;
  }

  /// Mounts the stack view in [phaseNodes] shape, keeping ONE State alive
  /// across calls — the activation swap is a didUpdateWidget, exactly as
  /// on device.
  Future<void> pumpStack(
    WidgetTester tester, {
    required List<CanvasLayerStackNode> nodes,
    required LayerFrameImageCache imageCache,
    required CanvasSize canvasSize,
    BitmapSurfacePainter? activeSurfacePainter,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: canvasSize.width.toDouble(),
              height: canvasSize.height.toDouble(),
              child: CanvasLayerStackView(
                nodes: nodes,
                imageCache: imageCache,
                canvasSize: canvasSize,
                viewport: CanvasViewport(),
                activeSurfacePainter: activeSurfacePainter,
              ),
            ),
          ),
        ),
      ),
    );
  }

  CustomPainter stackPainter(WidgetTester tester) {
    final painted = tester
        .widgetList<CustomPaint>(
          find.descendant(
            of: find.byType(CanvasLayerStackView),
            matching: find.byType(CustomPaint),
          ),
        )
        .where((paint) => paint.painter != null)
        .toList();
    expect(painted, isNotEmpty, reason: 'the stack view paints through one');
    return painted.first.painter!;
  }

  /// One frame's pixels through the stack painter. The picture is recorded
  /// SYNCHRONOUSLY (no decode can land mid-record); only the readback runs
  /// under runAsync.
  Future<Uint8List> paintStack(WidgetTester tester, Size size) async {
    final painter = stackPainter(tester);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Offset.zero & size);
    painter.paint(canvas, size);
    final picture = recorder.endRecording();
    final bytes = await tester.runAsync(() async {
      final image = await picture.toImage(
        size.width.toInt(),
        size.height.toInt(),
      );
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return data!.buffer.asUint8List();
    });
    picture.dispose();
    return bytes!;
  }

  bool magentaAt(Uint8List rgba, int width, int x, int y) {
    final offset = (y * width + x) * 4;
    // The unpainted marker is 0x99FF00FF over a transparent ground.
    // Measured readback on the tester is the PREMULTIPLIED form
    // (153,0,153,153); accept the unpremultiplied form too so the oracle
    // survives an engine that unpremultiplies rawRgba.
    return rgba[offset] > 0x60 &&
        rgba[offset + 1] < 0x30 &&
        rgba[offset + 2] > 0x60 &&
        rgba[offset + 3] > 0x60 &&
        rgba[offset + 3] < 0xC8;
  }

  bool blueAt(Uint8List rgba, int width, int x, int y) {
    final offset = (y * width + x) * 4;
    return rgba[offset] < 0x30 &&
        rgba[offset + 1] < 0x30 &&
        rgba[offset + 2] > 0xC8 &&
        rgba[offset + 3] == 0xFF;
  }

  bool redAt(Uint8List rgba, int width, int x, int y) {
    final offset = (y * width + x) * 4;
    return rgba[offset] > 0xC8 &&
        rgba[offset + 1] < 0x30 &&
        rgba[offset + 2] < 0x30 &&
        rgba[offset + 3] == 0xFF;
  }

  int unpaintedTileCount(Uint8List rgba, int width, int tileCount) {
    var unpainted = 0;
    for (var tile = 0; tile < tileCount; tile += 1) {
      if (magentaAt(rgba, width, tile * tileSize + tileSize ~/ 2, 8)) {
        unpainted += 1;
      }
    }
    return unpainted;
  }

  testWidgets('Skia shape (no sync upload): the swap frame after promoting a '
      'file-backed cel is WHOLE — the previous route\'s held image stands in '
      'while zero tile images are decoded, and hands off seamlessly once the '
      'decodes land', (tester) async {
    const tileCount = 6;
    final canvasSize = CanvasSize(
      width: tileCount * tileSize,
      height: tileSize,
    );
    final size = Size(
      canvasSize.width.toDouble(),
      canvasSize.height.toDouble(),
    );
    final store = openShapedStore(drawnSurface(tileCount));
    expect(store.celHasRenderableContent(key), isTrue);
    expect(store.isCelFileBacked(key), isTrue);

    // The PREVIOUS route: while inactive the layer is a cached image.
    // prepare() builds it exactly the way the app does.
    final imageCache = LayerFrameImageCache(frameStore: store);
    final prepared = await tester.runAsync(
      () => imageCache.prepare(
        key: key,
        canvasSize: canvasSize,
        quality: PlaybackQuality.full,
      ),
    );
    expect(prepared, isNotNull);

    await pumpStack(
      tester,
      nodes: const [
        CanvasLayerImageNode(
          CanvasLayerImageRequest(frameKey: key, opacity: 1),
        ),
      ],
      imageCache: imageCache,
      canvasSize: canvasSize,
    );
    final before = await paintStack(tester, size);
    expect(
      blueAt(before, size.width.toInt(), 8, 8),
      isTrue,
      reason: 'the inactive route shows the artwork',
    );

    // ---- ACTIVATION: the editing seed's promotion, a fresh tile cache
    // standing for "no images exist for these tile objects" (on device:
    // the promotion after a cooling drop makes all-fresh objects).
    final promoted = store.bakedSurfaceOrNull(key)!;
    expect(promoted.tiles.length, tileCount);
    final tileCache = BitmapTileImageCache();
    final painter = BitmapSurfacePainter(
      surface: promoted,
      showTransparentBackground: false,
      staleScope: 'cel-under-test',
      tileImageCache: tileCache,
    );
    await pumpStack(
      tester,
      nodes: const [CanvasActiveLayerNode(opacity: 1, frameKey: key)],
      imageCache: imageCache,
      canvasSize: canvasSize,
      activeSurfacePainter: painter,
    );

    // ---- the SWAP FRAME ------------------------------------------------
    final first = await paintStack(tester, size);
    expect(
      unpaintedTileCount(first, size.width.toInt(), tileCount),
      0,
      reason:
          'the cel HAS renderable content and the stack held its truth '
          'image one frame ago — the swap frame must be whole (this was '
          'the one-frame disappearance: only the per-pixel budget of 4 '
          'drew, the rest was silent)',
    );
    for (var tile = 0; tile < tileCount; tile += 1) {
      expect(
        blueAt(first, size.width.toInt(), tile * tileSize + 8, 8),
        isTrue,
        reason: 'tile $tile shows the held truth pixels on the swap frame',
      );
    }

    // ---- decodes land (they MUST have been started by the stand-in
    // frame — the walk that normally starts them was covered) ------------
    await tester.runAsync(() async {
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (!tileCache.allDecoded(promoted.tiles.values)) {
        if (DateTime.now().isAfter(deadline)) {
          fail(
            'timed out waiting for tile decodes — the stand-in frame did '
            'not start them, so it could never hand off',
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    });

    // ---- the handoff: same pixels from the surface\'s own tiles --------
    final second = await paintStack(tester, size);
    expect(unpaintedTileCount(second, size.width.toInt(), tileCount), 0);
    for (var tile = 0; tile < tileCount; tile += 1) {
      expect(
        blueAt(second, size.width.toInt(), tile * tileSize + 8, 8),
        isTrue,
        reason: 'tile $tile after handoff — no seam, same pixel source',
      );
    }

    // ---- why it never happens again for this layer ----------------------
    final repromoted = store.bakedSurfaceOrNull(key)!;
    expect(
      identical(repromoted, promoted),
      isTrue,
      reason: 'the second activation reuses the same hot surface instance...',
    );
    expect(
      tileCache.allDecoded(repromoted.tiles.values),
      isTrue,
      reason:
          '...whose tile objects still hold their decoded images — the '
          'first paint after a re-activation is whole',
    );
  });

  testWidgets('the stand-in never outranks truth: with ANY decoded tile image '
      'present (an edited coordinate, decoded), the walk draws — the edit '
      'shows and the stand-in does not', (tester) async {
    const tileCount = 6;
    final canvasSize = CanvasSize(
      width: tileCount * tileSize,
      height: tileSize,
    );
    final size = Size(
      canvasSize.width.toDouble(),
      canvasSize.height.toDouble(),
    );
    final store = openShapedStore(drawnSurface(tileCount));

    final imageCache = LayerFrameImageCache(frameStore: store);
    final prepared = await tester.runAsync(
      () => imageCache.prepare(
        key: key,
        canvasSize: canvasSize,
        quality: PlaybackQuality.full,
      ),
    );
    expect(prepared, isNotNull, reason: 'the held image is all-blue');

    await pumpStack(
      tester,
      nodes: const [
        CanvasLayerImageNode(
          CanvasLayerImageRequest(frameKey: key, opacity: 1),
        ),
      ],
      imageCache: imageCache,
      canvasSize: canvasSize,
    );

    // The activation surface differs from the held image: tile 0 was
    // EDITED to red, and its picture is already decoded — the partial-
    // decode state the stand-in must stand aside for.
    final redTile = filledTile(0, r: 0xFF, g: 0, b: 0);
    final edited = drawnSurface(tileCount).putTile(redTile);
    final tileCache = BitmapTileImageCache();
    await tester.runAsync(() async {
      tileCache.ensureDecoded(redTile);
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (tileCache.imageFor(redTile) == null) {
        if (DateTime.now().isAfter(deadline)) {
          fail('timed out decoding the edited tile');
        }
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    });
    final painter = BitmapSurfacePainter(
      surface: edited,
      showTransparentBackground: false,
      staleScope: 'cel-under-test',
      tileImageCache: tileCache,
    );
    await pumpStack(
      tester,
      nodes: const [CanvasActiveLayerNode(opacity: 1, frameKey: key)],
      imageCache: imageCache,
      canvasSize: canvasSize,
      activeSurfacePainter: painter,
    );

    final first = await paintStack(tester, size);
    expect(
      redAt(first, size.width.toInt(), 8, 8),
      isTrue,
      reason:
          'a decoded image EXISTS, so the walk must draw: the edited '
          'coordinate shows its own truth. A stand-in here would paint '
          'the pre-edit blue over it — stale pixels presented as fresh',
    );
    expect(blueAt(first, size.width.toInt(), 8, 8), isFalse);
    expect(
      unpaintedTileCount(first, size.width.toInt(), tileCount),
      tileCount - 1 - 4,
      reason:
          'and it really was the walk: one decoded tile + the per-pixel '
          'budget of 4 drew, the last tile is silent this frame (today\'s '
          'convergence, not a stand-in)',
    );
  });

  testWidgets('Impeller shape (sync upload available): a cel bigger than both '
      'budgets combined (40 > 32 + 4) is still WHOLE on the swap frame — '
      'the stand-in owes nothing to the budgets', (tester) async {
    // Stand in for ui.decodeImageFromPixelsSync (Impeller-only; the
    // probe throws on Skia hosts). Fidelity is irrelevant here — the
    // assertion is about wholeness, not the upload's pixels.
    debugSyncImageUploadOverride = (pixels, width, height) {
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder).drawRect(
        Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
        Paint()..color = const Color(0xFF0000FF),
      );
      final picture = recorder.endRecording();
      final image = picture.toImageSync(width, height);
      picture.dispose();
      return image;
    };
    expect(syncImageUploadSupported, isTrue);

    const tileCount = 40; // > 32 + 4: an 8K-era cel at fit zoom
    final canvasSize = CanvasSize(
      width: tileCount * tileSize,
      height: tileSize,
    );
    final size = Size(
      canvasSize.width.toDouble(),
      canvasSize.height.toDouble(),
    );
    final store = openShapedStore(drawnSurface(tileCount));

    final imageCache = LayerFrameImageCache(frameStore: store);
    final prepared = await tester.runAsync(
      () => imageCache.prepare(
        key: key,
        canvasSize: canvasSize,
        quality: PlaybackQuality.full,
      ),
    );
    expect(prepared, isNotNull);

    await pumpStack(
      tester,
      nodes: const [
        CanvasLayerImageNode(
          CanvasLayerImageRequest(frameKey: key, opacity: 1),
        ),
      ],
      imageCache: imageCache,
      canvasSize: canvasSize,
    );

    final promoted = store.bakedSurfaceOrNull(key)!;
    final tileCache = BitmapTileImageCache();
    final painter = BitmapSurfacePainter(
      surface: promoted,
      showTransparentBackground: false,
      staleScope: 'cel-under-test',
      tileImageCache: tileCache,
    );
    await pumpStack(
      tester,
      nodes: const [CanvasActiveLayerNode(opacity: 1, frameKey: key)],
      imageCache: imageCache,
      canvasSize: canvasSize,
      activeSurfacePainter: painter,
    );

    final first = await paintStack(tester, size);
    expect(
      unpaintedTileCount(first, size.width.toInt(), tileCount),
      0,
      reason:
          'pre-fix this was 40 - 32 (sync uploads) - 4 (per-pixel) = 4 '
          'silent tiles even on the device renderers — the stand-in '
          'covers the whole cel regardless of budget arithmetic',
    );
    expect(blueAt(first, size.width.toInt(), 8, 8), isTrue);
    expect(
      blueAt(first, size.width.toInt(), (tileCount - 1) * tileSize + 8, 8),
      isTrue,
    );
  });
}
