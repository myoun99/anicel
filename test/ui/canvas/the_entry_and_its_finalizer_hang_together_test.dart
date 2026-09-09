import 'dart:io';
import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/ui/canvas/bitmap_tile_image_cache.dart';

/// 🚨★★★**THE CACHE KEYS BY A TILE'S PIXELS; ITS FINALIZERS MUST TOO.**
/// Entries hang under `BitmapTile.pixelsSource` so a rebased tile (a
/// whole-tile canvas shift) finds the picture its source decoded. A
/// `Finalizer.attach(tile, …)` written beside such a write sits on a
/// DIFFERENT object whenever that tile is a rebase, and two things follow:
///
/// · **use-after-dispose** — the rebase is collected while its source is
///   still reachable (an undo snapshot holds the pre-resize surface), the
///   finalizer disposes the image, and the entry under the source keeps
///   handing it out;
/// · **double retire** — a stand-in put through one tile and dropped
///   through another detaches the wrong object, so its finalizer retires
///   the same `ui.Image` a second time.
///
/// ⚠️**A RUNNING TEST CANNOT SEE EITHER.** Dart exposes nothing about what
/// a `Finalizer` is attached to, and both failures need a GC at a
/// particular moment. So the contract is enforced on the SOURCE — the same
/// way this repo closes 「사본 금지」 — and the behavioural half below pins
/// only what is observable: that the slot itself normalises.
void main() {
  test('🚨every Finalizer in the tile image cache hangs on keyFor(...)', () {
    final source = File(
      'lib/src/ui/canvas/bitmap_tile_image_cache.dart',
    ).readAsStringSync();

    final calls = RegExp(
      r'_(?:image|provisional)Finalizer\.(?:attach|detach)\(\s*([^,)]+)',
    ).allMatches(source).map((match) => match.group(1)!.trim()).toList();

    expect(
      calls,
      isNotEmpty,
      reason: 'setup: the cache must still attach finalizers at all',
    );
    for (final target in calls) {
      expect(
        target,
        contains('keyFor('),
        reason:
            'a finalizer was hung on `$target` — the entry hangs on '
            '`keyFor(tile)`, and the two must be the same object. See this '
            "file's header for what happens when they are not.",
      );
    }
  });

  testWidgets('a stand-in put through a rebase is found — and dropped — '
      'through its source', (tester) async {
    await tester.runAsync(() async {
      final cache = BitmapTileImageCache();
      addTearDown(cache.dispose);

      final source = BitmapTile(
        coord: TileCoord(x: 0, y: 0),
        size: 4,
        pixels: Uint8List(4 * 4 * 4)..[3] = 255,
      );
      final rebase = source.rebasedTo(TileCoord(x: 1, y: 0));
      expect(identical(rebase, source), isFalse);

      // The provisional goes in through the REBASE.
      cache.putProvisional(rebase, await _anImage());
      expect(
        cache.hasProvisional(source),
        isTrue,
        reason: 'one slot, whichever of the two the caller happens to hold',
      );

      // And the real picture, decoded through the SOURCE, retires it.
      cache.ensureDecoded(source);
      for (var attempt = 0; attempt < 100; attempt += 1) {
        if (cache.imageFor(source) != null) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(cache.imageFor(source), isNotNull, reason: 'setup: it decoded');
      expect(cache.hasProvisional(rebase), isFalse);

      // Anti-vacuity: a tile with its OWN buffer keeps its own slot, so
      // the assertions above are about sharing and not about the cache
      // answering the same thing for everyone.
      final twin = BitmapTile(
        coord: TileCoord(x: 2, y: 0),
        size: 4,
        pixels: Uint8List(4 * 4 * 4)..[3] = 255,
      );
      expect(cache.hasProvisional(twin), isFalse);
      expect(cache.imageFor(twin), isNull);
    });
  });
}

Future<ui.Image> _anImage() async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    const ui.Rect.fromLTWH(0, 0, 4, 4),
    ui.Paint()..color = const ui.Color(0xFF00FF00),
  );
  final picture = recorder.endRecording();
  final image = picture.toImageSync(4, 4);
  picture.dispose();
  return image;
}
