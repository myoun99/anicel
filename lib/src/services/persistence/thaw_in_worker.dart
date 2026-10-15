import 'dart:io' show Platform;
import 'dart:isolate';

import '../../core/on_a_worker.dart';
import '../../core/turns.dart';
import '../../core/worker_count.dart';
import '../../models/bitmap_tile.dart';
import 'brush_drawing_binary_codec.dart';

/// [blob] inflated, parsed and laid into tile blocks on a worker isolate,
/// from the allocator [blocks] names — the main isolate's
/// ([BitmapTile.blocks]) — so all that is left there is adopting them
/// ([laidCelSurface]).
///
/// 🔬On the UI thread (card `cel-thaw-holds-the-ui-thread`, a profile build,
/// 2026-10-15) this was 60–70 ms of a first playback's late frames: the tile
/// copies ~40, zstd 20–27.
///
/// The bytes cross as a [TransferableTypedData], the parking path's way
/// (`compressAnicelPayloadInWorker` says why).
Future<AnicelLaidCel> layCelInWorker(AnicelCelBlob blob, TileBlocks blocks) {
  final sent = TransferableTypedData.fromList([blob.bytes]);
  return onAWorker(
    () => layCelEntry(
      AnicelCelBlob(sent.materialize().asUint8List()).decode(),
      tileBlocksHere(blocks),
    ),
  );
}

/// The turns a thaw on a worker takes, whichever store asks — the machine's
/// workers are not a project's (card `cel-thaw-holds-the-ui-thread` ⑧).
///
/// 🔬The ceiling where it was measured (2026-10-15, an 8-core Surface,
/// `flutter test`, 13 line-art cels of 1920×1080 asked at once — a frame's
/// rows): **1 worker 274–323 ms · 2 165–198 · 3 136–152 · 4 108–128 · 7
/// 72–81**, against 208–243 ms on the UI thread. Still falling at seven, the
/// most that machine gives, so the ceiling is the import pools' eight rather
/// than the four first written here; each thaw on a worker holds its cel
/// about twice (bytes inflated, tiles laid) until it is adopted.
final Turns celThawTurns = Turns(
  workersFor(Platform.numberOfProcessors, ceiling: 8),
);
