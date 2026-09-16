import 'dart:ffi';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/placed_tile.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/native/native_scratch.dart';
import 'package:anicel/src/native/qa_native_engine.dart';
import 'package:anicel/src/ui/canvas/bitmap_tile_image_cache.dart';
import 'package:anicel/src/ui/diagnostics/memory_census.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

import '../../helpers/collect_garbage.dart';

/// 🚨C-ipad-crash (2026-09-11): on a phone every decoded tile is a GPU
/// texture, alive as long as its tile — the picture on screen and, through
/// the tiles it keeps, the undo history's. The census had no row for them,
/// so the share read as engine overhead; the drawing engine's own parked
/// tile blocks and grow-only scratch had none either.
void main() {
  PlacedTile tileAt(int x, int y) => (
    coord: TileCoord(x: x, y: y),
    tile: BitmapTile.blank(size: 4),
  );

  Future<ui.Image> anImage() {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawRect(
      const ui.Rect.fromLTWH(0, 0, 4, 4),
      ui.Paint()..color = const ui.Color(0xFF00FF00),
    );
    final picture = recorder.endRecording();
    final image = picture.toImageSync(4, 4);
    picture.dispose();
    return Future<ui.Image>.value(image);
  }

  const oneImage = 4 * 4 * 4;

  testWidgets('🚨a tile image is on the books while its tile lives — truths '
      'and stand-ins — and comes off with it', (tester) async {
    await tester.runAsync(() async {
      final cache = BitmapTileImageCache();
      // Settle what earlier tests let go of, so the baseline holds still.
      await collectGarbage();
      final before = BitmapTileImageCache.liveImageBytes;

      PlacedTile? truth = tileAt(0, 0);
      PlacedTile? standIn = tileAt(1, 0);
      cache.adoptDecoded(
        truth,
        await anImage(),
        staleScope: BitmapTileImageCache.unfiled,
      );
      cache.putProvisional(standIn, await anImage());
      expect(BitmapTileImageCache.liveImageBytes - before, 2 * oneImage);

      // Its truth landing retires the stand-in: one off, one on.
      cache.adoptDecoded(
        standIn,
        await anImage(),
        staleScope: BitmapTileImageCache.unfiled,
      );
      expect(BitmapTileImageCache.liveImageBytes - before, 2 * oneImage);

      truth = null;
      standIn = null;
      await collectGarbageUntil(
        () => BitmapTileImageCache.liveImageBytes == before,
      );

      expect(
        BitmapTileImageCache.liveImageBytes,
        before,
        reason:
            'a collected tile takes its picture off the books — and an '
            'unfiled one is pinned by no bucket',
      );
    });
  });

  testWidgets('the census has a row for the tile images and one for the '
      "drawing engine's own buffers, each reading its counter", (
    tester,
  ) async {
    await tester.runAsync(() async {
      final session = EditorSessionManager(
        initialProject: createDefaultProject(),
      );
      addTearDown(session.dispose);
      PlacedTile? held = tileAt(0, 0);
      BitmapTileImageCache.instance.adoptDecoded(
        held,
        await anImage(),
        staleScope: BitmapTileImageCache.unfiled,
      );
      final scratch = NativeScratch<Uint8>((n) => calloc<Uint8>(n));
      addTearDown(scratch.release);
      scratch.ensure(1000);

      final rows = {
        for (final item in collectMemoryCensus(session).items)
          item.id: item.bytes,
      };

      expect(rows['tileImages'], BitmapTileImageCache.liveImageBytes);
      expect(
        rows['tileImages'],
        greaterThanOrEqualTo(oneImage),
        reason: 'fixture: a held picture is on the books',
      );
      // Two rows since 2026-09-16: the pool has a ceiling the allowance
      // sets, the scratch has none — one row was half inside and half out.
      expect(
        rows['enginePool'],
        QaNativeEngine.instance?.tilePoolParkedBytes ?? 0,
      );
      expect(rows['engineScratch'], NativeScratch.liveBytes);
      expect(
        rows['engineScratch'],
        greaterThanOrEqualTo(1000),
        reason: 'fixture: a grown scratch is on the books',
      );
      // Read after the census, so the tile outlives it.
      expect(BitmapTileImageCache.instance.imageFor(held.tile), isNotNull);

      // ⚠️And take this test's picture off the books before it ends. The
      // counter is one static for the whole file, so a release still in the
      // post when the next test reads its baseline lands in the MIDDLE of
      // that test instead — whichever order the tests run in.
      final withHeld = BitmapTileImageCache.liveImageBytes;
      held = null;
      await collectGarbageUntil(
        () => BitmapTileImageCache.liveImageBytes <= withHeld - oneImage,
      );
    });
  });

  testWidgets('a DECODED tile is on the books the same way, and off with it', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final cache = BitmapTileImageCache();
      // Settle what earlier tests let go of, so the baseline holds still.
      await collectGarbage();
      final before = BitmapTileImageCache.liveImageBytes;
      PlacedTile? placed = (
        coord: TileCoord(x: 0, y: 0),
        tile: BitmapTile(
          size: 4,
          pixels: Uint8List(oneImage)..fillRange(0, oneImage, 0xFF),
        ),
      );

      cache.ensureDecoded(placed, staleScope: BitmapTileImageCache.unfiled);
      for (var i = 0; i < 200 && cache.imageFor(placed.tile) == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(
        cache.imageFor(placed.tile),
        isNotNull,
        reason: 'fixture: the decode landed',
      );
      expect(BitmapTileImageCache.liveImageBytes - before, oneImage);

      placed = null;
      await collectGarbageUntil(
        () => BitmapTileImageCache.liveImageBytes == before,
      );

      expect(BitmapTileImageCache.liveImageBytes, before);
    });
  });
}
