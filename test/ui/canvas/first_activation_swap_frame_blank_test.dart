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
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/persistence/brush_drawing_binary_codec.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/bitmap_tile_image_cache.dart';
import 'package:anicel/src/ui/debug/measurement_mode.dart';

/// 🔴 repro — the FIRST-ACTIVATION swap-frame blank (device report
/// 2026-08-17: old file opened, layers with existing art; the FIRST time
/// each layer is made active its picture disappears for one frame, then
/// returns; never again for that layer).
///
/// The frame sequence this pins:
///  1. While INACTIVE the layer paints as a cached image
///     (CanvasLayerImageNode — editor_session_manager.dart:2656).
///  2. Activation swaps its leaf to CanvasActiveLayerNode
///     (editor_session_manager.dart:2639-2654); the editing seed promotes
///     the FILE-BACKED cel synchronously
///     (brush_frame_editing_coordinator.dart:118-130 →
///     BrushFrameStore.bakedSurfaceOrNull, brush_frame_store.dart:223-250).
///  3. The swap frame paints the live surface through
///     BitmapSurfacePainter.paintContentInto. Every tile of the promoted
///     surface is a FRESH object — BitmapTileImageCache keys images by
///     tile identity — so `displayImageFor` is null for all of them, the
///     stale-borrow scope has never decoded anything, the flat projection
///     refuses (active_layer_flat_projection.dart:198-203 — it needs a
///     truth image for EVERY committed tile), and the only same-frame
///     answers are `adoptSyncUpload` (Impeller only, budget 32/paint —
///     bitmap_surface_painter.dart:218,369-380) and the per-pixel fallback
///     (budget 4 — line 200). Everything past the budgets is SILENT
///     (line 410-416) — the blank.
///  4. Decodes land within a few frames (`ensureDecoded`, coalesced
///     notify) and the picture returns. A second activation reuses the
///     SAME hot surface instance, whose tile objects still hold their
///     decoded images — clean by construction.
///
/// The magenta predicate (MeasurementMode.showUnpaintedTiles) is the
/// oracle: it fills exactly the coordinates the painter could not draw.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  /// A one-row surface of [tileCount] fully-drawn tiles (opaque blue).
  BitmapSurface drawnSurface(int tileCount) {
    final tiles = <TileCoord, BitmapTile>{};
    for (var x = 0; x < tileCount; x += 1) {
      final pixels = Uint8List(tileSize * tileSize * 4);
      for (var i = 0; i < pixels.length; i += 4) {
        pixels[i + 2] = 0xFF; // blue
        pixels[i + 3] = 0xFF; // opaque
      }
      final tile = BitmapTile(
        coord: TileCoord(x: x, y: 0),
        size: tileSize,
        pixels: pixels,
      );
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
  /// open (BrushFrameStore.restoreFromFile, brush_frame_store.dart:371).
  BrushFrameStore openShapedStore(BitmapSurface surface) {
    final blob = AnicelCelBlob.encode(AnicelCelEntry.fromSurface(key, surface));
    final file = File('${tempDir.path}\\cel.bin')
      ..writeAsBytesSync(blob.bytes);
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

  Future<Uint8List> paintOnce(BitmapSurfacePainter painter, Size size) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    painter.paint(canvas, size);
    final picture = recorder.endRecording();
    final image = picture.toImageSync(size.width.toInt(), size.height.toInt());
    picture.dispose();
    final bytes = (await image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!.buffer.asUint8List();
    image.dispose();
    return bytes;
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

  int unpaintedTileCount(Uint8List rgba, int width, int tileCount) {
    var unpainted = 0;
    for (var tile = 0; tile < tileCount; tile += 1) {
      if (magentaAt(rgba, width, tile * tileSize + tileSize ~/ 2, 8)) {
        unpainted += 1;
      }
    }
    return unpainted;
  }

  test(
    'Skia shape (no sync upload): the first paint after promoting a '
    'file-backed cel draws only the per-pixel budget — the rest of a cel '
    'with renderable content is BLANK for that frame; the second paint is '
    'whole, and a re-promotion reuses the same decoded tiles',
    () async {
      const tileCount = 6;
      final store = openShapedStore(drawnSurface(tileCount));
      expect(store.celHasRenderableContent(key), isTrue);
      expect(store.isCelFileBacked(key), isTrue);

      // The activation promotion — what _seedSession does when the layer
      // is first made active.
      final promoted = store.bakedSurfaceOrNull(key)!;
      expect(promoted.tiles.length, tileCount);

      // The promotion also "reseeds the display cache" — with the SAME
      // undecoded surface object. There is no paintable stand-in in it:
      // seeding the display cache is NOT a fix for the swap frame.
      expect(
        identical(store.validPreviewSurfaceOrNull(key), promoted),
        isTrue,
        reason:
            'brush_frame_store.dart:246-247 — the display-cache preview is '
            'the same tile objects the painter cannot draw yet',
      );

      final cache = BitmapTileImageCache();
      final painter = BitmapSurfacePainter(
        surface: promoted,
        showTransparentBackground: false,
        staleScope: 'cel-under-test',
        tileImageCache: cache,
      );
      const size = Size(tileCount * tileSize * 1.0, tileSize * 1.0);

      // ---- the SWAP FRAME ------------------------------------------------
      final first = await paintOnce(painter, size);
      final unpaintedOnSwapFrame = unpaintedTileCount(
        first,
        size.width.toInt(),
        tileCount,
      );
      // 🔴 repro: BROKEN value documented. The cel HAS renderable content
      // (asserted above), yet the swap frame paints only the per-pixel
      // budget (4 tiles) and leaves the rest silent — this is the
      // one-frame disappearance. CORRECT behavior under the project law
      // ("no UI that pops into existence / no one-frame flashes") is 0
      // unpainted coordinates — the previous route's picture (the layer's
      // CanvasLayerImageNode image, still held at the swap frame) must
      // stand in until the decodes land. Flip this to `equals(0)` when a
      // stand-in ships.
      expect(unpaintedOnSwapFrame, isNot(0));
      expect(unpaintedOnSwapFrame, tileCount - 4);
      expect(
        blueAt(first, size.width.toInt(), 8, 8),
        isTrue,
        reason: 'the per-pixel budget covered the first four tiles',
      );

      // ---- decodes land (started by the swap-frame paint) ----------------
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (!cache.allDecoded(promoted.tiles.values)) {
        if (DateTime.now().isAfter(deadline)) {
          fail('timed out waiting for tile decodes');
        }
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      final second = await paintOnce(painter, size);
      expect(
        unpaintedTileCount(second, size.width.toInt(), tileCount),
        0,
        reason: 'the picture returns once the decodes land',
      );
      expect(
        blueAt(second, size.width.toInt(), (tileCount - 1) * tileSize + 8, 8),
        isTrue,
      );

      // ---- why it never happens again for this layer ----------------------
      final repromoted = store.bakedSurfaceOrNull(key)!;
      expect(
        identical(repromoted, promoted),
        isTrue,
        reason:
            'the second activation reuses the same hot surface instance...',
      );
      expect(
        cache.allDecoded(repromoted.tiles.values),
        isTrue,
        reason:
            '...whose tile objects still hold their decoded images — the '
            'first paint after a re-activation is whole',
      );
    },
  );

  test(
    'Impeller shape (sync upload available): the swap frame still blanks '
    'whatever exceeds syncUploadBudget (32) + pixel budget (4) — big cels '
    'blank partially even on device renderers with the sync path',
    () async {
      // Stand in for ui.decodeImageFromPixelsSync (Impeller-only; the
      // probe throws on Skia hosts). Fidelity is irrelevant here — the
      // assertion is about the BUDGET, not the pixels — so a solid tile
      // of the right size is enough.
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
      final store = openShapedStore(drawnSurface(tileCount));
      final promoted = store.bakedSurfaceOrNull(key)!;
      final cache = BitmapTileImageCache();
      final painter = BitmapSurfacePainter(
        surface: promoted,
        showTransparentBackground: false,
        staleScope: 'cel-under-test',
        tileImageCache: cache,
      );
      const size = Size(tileCount * tileSize * 1.0, tileSize * 1.0);

      final first = await paintOnce(painter, size);
      final unpaintedOnSwapFrame = unpaintedTileCount(
        first,
        size.width.toInt(),
        tileCount,
      );
      // 🔴 repro: BROKEN value documented. Even with the synchronous
      // upload path (the device renderers), a cel bigger than the two
      // budgets combined shows holes on its first active frame:
      // 40 - 32 (sync uploads) - 4 (per-pixel) = 4 silent tiles. CORRECT
      // is 0 (stand-in until decodes land). Flip to `equals(0)` when the
      // fix ships.
      expect(unpaintedOnSwapFrame, isNot(0));
      expect(unpaintedOnSwapFrame, tileCount - 32 - 4);
    },
  );
}
