import 'dart:io' show Platform;
import 'dart:isolate';

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
  return Isolate.run(
    () => layCelEntry(
      AnicelCelBlob(sent.materialize().asUint8List()).decode(),
      tileBlocksHere(blocks),
    ),
  );
}

/// The turns a thaw on a worker takes, whichever store asks — the machine's
/// workers are not a project's (card `cel-thaw-holds-the-ui-thread` ⑧).
final Turns celThawTurns = Turns(
  workersFor(Platform.numberOfProcessors, ceiling: 4),
);
