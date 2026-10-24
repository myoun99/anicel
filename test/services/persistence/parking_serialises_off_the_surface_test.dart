import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

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
import 'package:anicel/src/services/persistence/brush_drawing_binary_codec.dart';
import 'package:anicel/src/services/persistence/compress_in_worker.dart';

/// 🚨★★★**PARKING IS WHAT MEMORY PRESSURE DOES, SO IT MUST NOT ASK FOR
/// MEMORY.** The park and cool paths built an `AnicelCelEntry` first — a
/// defensive `tile.pixels` copy per tile — and sent that object graph
/// into the isolate. Serialising straight off the surface removes the
/// per-tile copy, and it is the only shape that CAN send flat bytes:
/// `BitmapTile` is `Finalizable` and cannot cross an isolate boundary at
/// all.
///
/// ⚠️**THE SPEED-UP IS NOT A "MOVE".** `TransferableTypedData.fromList`
/// copies its lists into one external buffer and the caller's list stays
/// readable — I asserted the opposite here first and the probe said no.
/// What it buys is the crossing (see `compressAnicelPayloadInWorker` for
/// the table). That is a timing property, so it is documented there
/// rather than pinned as a test; what IS pinned here is that the blob made
/// around the worker's bytes is the one made here.
///
/// ↩️It also pinned that the stream off the surface was the one an entry
/// wrote: that second writer went with format 29 (2026-10-24), when every
/// blob came to be made from a picture.
void main() {
  const tileSize = 128;
  const key = BrushFrameKey(
    projectId: ProjectId('p'),
    trackId: TrackId('t'),
    cutId: CutId('c'),
    layerId: LayerId('l'),
    frameId: FrameId('f'),
  );

  BitmapSurface celOf(int tileCount) {
    final tiles = <TileCoord, BitmapTile>{};
    for (var i = 0; i < tileCount; i += 1) {
      final pixels = Uint8List(BitmapTile.bytesFor(tileSize));
      for (var p = 3; p < pixels.length; p += 4) {
        pixels[p] = (p + i) & 0xFF;
      }
      tiles[TileCoord(x: i % 4, y: i ~/ 4)] =
          BitmapTile(size: tileSize, pixels: pixels);
    }
    return BitmapSurface(
      canvasSize: const CanvasSize(width: 1024, height: 1024),
      tileSize: tileSize,
      tiles: tiles,
    );
  }

  test('a blob built around worker bytes is byte-identical to one made '
      'here', () async {
    final surface = celOf(2);
    final inline = AnicelCelBlob.ofSurface(key, surface);

    final body = encodeCelEntryFromSurface(key, surface);
    // Anti-vacuity: this is a real payload, not an empty buffer.
    expect(body.length, greaterThan(2 * BitmapTile.bytesFor(tileSize)));
    final compressed = await compressAnicelPayloadInWorker(body);
    final assembled = AnicelCelBlob.fromCompressedBody(
      key: key,
      canvasSize: surface.canvasSize,
      tileSize: surface.tileSize,
      photoPaths: const [],
      showsSomething: surface.showsSomething,
      codec: compressed.codec,
      body: compressed.bytes,
    );

    expect(assembled.bytes, inline.bytes);
    expect(assembled.codec, inline.codec);
    // And it still reads back as the same picture.
    expect(assembled.decode().tiles.length, surface.tiles.length);
  });
}
