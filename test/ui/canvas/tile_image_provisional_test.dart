import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/ui/canvas/bitmap_tile_image_cache.dart';

/// The stand-in slot: a tile may SHOW a synthesized picture of itself while
/// its own decode is still in flight.
///
/// The contract that matters is what a stand-in must NOT do. It must not
/// stop the real decode, and it must not survive it — a composed picture is
/// the same operation the screen was already performing, but it is not
/// byte-identical to the commit kernel's output, so letting it become the
/// tile's permanent picture would pin an off-by-two forever
/// (`tile_image_sync_compose_parity_test` measures that).
void main() {
  BitmapTile tileAt(int x, int y) => BitmapTile.blank(
    coord: TileCoord(x: x, y: y),
    size: 4,
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

  testWidgets('a stand-in draws, is not truth, and does not block the decode', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final cache = BitmapTileImageCache();
      final tile = tileAt(0, 0);

      expect(cache.displayImageFor(tile), isNull);
      expect(cache.needsDecodeStart(tile), isTrue);

      cache.putProvisional(tile, await anImage());

      // Draws.
      expect(cache.displayImageFor(tile), isNotNull);
      expect(cache.hasProvisional(tile), isTrue);
      // Is not truth: `imageFor` is what adoption, seeding and the stale
      // bucket read, and none of them may see a synthesized picture.
      expect(cache.imageFor(tile), isNull);
      // 🚨 The load-bearing one. If a stand-in stopped the decode, the
      // off-by-two would become permanent and nothing would ever say so.
      expect(cache.needsDecodeStart(tile), isTrue);
    });
  });

  testWidgets('the real decode replaces the stand-in', (tester) async {
    await tester.runAsync(() async {
      final cache = BitmapTileImageCache();
      final tile = tileAt(1, 0);
      cache.putProvisional(tile, await anImage());
      final standIn = cache.displayImageFor(tile);

      cache.ensureDecoded(tile);
      // `decodeImageFromPixels` never completes inside `pump`'s fake async,
      // so settle it for real.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(cache.imageFor(tile), isNotNull, reason: 'the decode landed');
      expect(cache.hasProvisional(tile), isFalse);
      expect(
        identical(cache.displayImageFor(tile), standIn),
        isFalse,
        reason: 'the drawn picture must switch to the tile own decode',
      );
      expect(
        identical(cache.displayImageFor(tile), cache.imageFor(tile)),
        isTrue,
      );
    });
  });

  testWidgets('adoption also retires a stand-in', (tester) async {
    await tester.runAsync(() async {
      final cache = BitmapTileImageCache();
      final tile = tileAt(2, 0);
      cache.putProvisional(tile, await anImage());

      cache.adoptDecoded(tile, await anImage());

      expect(cache.imageFor(tile), isNotNull);
      expect(cache.hasProvisional(tile), isFalse);
    });
  });

  testWidgets('a tile that already has a picture takes no stand-in', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final cache = BitmapTileImageCache();
      final tile = tileAt(3, 0);
      final real = await anImage();
      cache.adoptDecoded(tile, real);

      cache.putProvisional(tile, await anImage());

      expect(cache.hasProvisional(tile), isFalse);
      expect(identical(cache.imageFor(tile), real), isTrue);
    });
  });

  testWidgets('a stand-in never enters the coordinate fallback', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final cache = BitmapTileImageCache();
      const scope = 'cel';
      final tile = tileAt(4, 0);

      cache.putProvisional(tile, await anImage());

      // The whole point of the stand-in is that it is a picture of THIS
      // tile. Letting it seed the per-coordinate bucket would hand the
      // off-by-two to a later generation as if it were truth — the exact
      // shape of the bug this work exists to remove.
      expect(cache.latestImageForCoord(tile.coord, scope: scope), isNull);
    });
  });
}
