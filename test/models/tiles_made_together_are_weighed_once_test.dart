@Tags(['gc'])
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/native/tile_blocks.dart';
import 'package:anicel/src/services/persistence/brush_drawing_binary_codec.dart';

import '../helpers/cel_text_fixture.dart';
import '../helpers/collect_garbage.dart';

/// Card a-thawed-cel-is-adopted-on-the-ui-thread: the tiles of a cel made
/// at once tell the collector their weight ONCE ([TileWeight]) — each told
/// its own, the VM scavenged three times a cel to free what stayed — and
/// each block is still freed as its own tile is.
void main() {
  /// Of two colours: a tile of one holds no block of its own.
  Uint8List inked(int side) =>
      Uint8List(BitmapTile.bytesFor(side))..[3] = 255;

  /// The weights told so far, and their bytes.
  ({int told, int bytes}) told() =>
      (told: TileWeight.debugTold, bytes: TileWeight.debugToldBytes);

  /// A cel of [side] whose first tiles are [pixels], in a row.
  AnicelCelEntry celOf(int side, List<Uint8List> pixels) => AnicelCelEntry(
    key: celTextTestKey,
    canvasSize: CanvasSize(width: side * pixels.length, height: side),
    tileSize: side,
    tiles: [
      for (final (x, one) in pixels.indexed) (x: x, y: 0, pixels: one),
    ],
  );

  test('a cel laid on a worker is weighed once, as all of its blocks — a '
      'tile of one colour weighs nothing', () {
    const side = 16;
    final laid = layCelEntry(
      celOf(side, [
        inked(side),
        inked(side),
        Uint8List(BitmapTile.bytesFor(side)),
      ]),
    );
    final before = told();

    final surface = laidCelSurface(laid);

    expect(surface.tiles, hasLength(3), reason: 'fixture: all three came');
    expect(
      told(),
      (told: before.told + 1, bytes: before.bytes + 2 * 16 * 16 * 4),
    );
  });

  test('a cel copied in on this isolate is weighed once too', () {
    const side = 16;
    final entry = celOf(side, [inked(side), inked(side), inked(side)]);
    final before = told();

    final surface = entry.toSurface();

    expect(surface.tiles, hasLength(3), reason: 'fixture: all three came');
    expect(
      told(),
      (told: before.told + 1, bytes: before.bytes + 3 * 16 * 16 * 4),
    );
  });

  test('a tile made alone weighs itself, and a cel of one colour has nothing '
      'to weigh: neither tells a weight', () {
    const side = 16;
    final before = told();

    final alone = BitmapTile(size: side, pixels: inked(side));
    final clear = celOf(side, [Uint8List(BitmapTile.bytesFor(side))]);
    final surface = clear.toSurface();

    expect(alone.ownBytes, BitmapTile.bytesFor(side), reason: 'fixture');
    expect(surface.tiles, hasLength(1), reason: 'fixture');
    expect(told(), before);
  });

  test('a weight is told once: a tile made with it after is refused', () {
    const side = 16;
    late TileWeight kept;
    TileWeight.together((weight) {
      kept = weight;
      return BitmapTile(size: side, pixels: inked(side), weighedBy: weight);
    });

    expect(
      () => BitmapTile(size: side, pixels: inked(side), weighedBy: kept),
      throwsStateError,
    );
  });

  test('🚨a block whose tile goes first comes back while the rest of its '
      'cel stands — the weight frees no block', () async {
    // A side no other tile wears, so the blocks held of its size
    // ([TileBlocks.debugHeld]) are these tiles' alone.
    const side = 44;
    final length = BitmapTile.bytesFor(side);
    BitmapTile? gone;
    late BitmapTile stays;
    TileWeight.together((weight) {
      gone = BitmapTile(size: side, pixels: inked(side), weighedBy: weight);
      stays = BitmapTile(size: side, pixels: inked(side), weighedBy: weight);
    });
    expect(gone!.ownBytes, length, reason: 'fixture: a block of its own');
    expect(TileBlocks.debugHeld(length), 2, reason: 'fixture: one each');
    final bytes = stays.pixels;
    gone = null;

    await collectGarbageUntil(() => TileBlocks.debugHeld(length) < 2);

    expect(
      TileBlocks.debugHeld(length),
      1,
      reason: 'its own tile went, and nothing else frees it — nor the '
          'other\'s, which stands',
    );
    expect(stays.pixels, bytes);
  });

  test('🚨the weight goes with the LAST tile made with it — not before',
      () async {
    const side = 45;
    BitmapTile? first;
    BitmapTile? last;
    late WeakReference<TileWeight> weight;
    TileWeight.together((made) {
      weight = WeakReference(made);
      first = BitmapTile(size: side, pixels: inked(side), weighedBy: made);
      last = BitmapTile(size: side, pixels: inked(side), weighedBy: made);
    });
    expect(first!.ownBytes, BitmapTile.bytesFor(side), reason: 'fixture');
    first = null;

    await collectGarbage();
    await collectGarbage();

    expect(weight.target, isNotNull, reason: 'a tile made with it stands');
    expect(last!.ownBytes, BitmapTile.bytesFor(side), reason: 'fixture');
    last = null;

    await collectGarbageUntil(() => weight.target == null);

    expect(weight.target, isNull, reason: 'the last of its tiles went');
  });
}
