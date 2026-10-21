import 'dart:io' show Platform;
import 'dart:isolate';

import '../../core/on_a_worker.dart';
import '../../core/turns.dart';
import '../../core/worker_count.dart';
import '../../models/bitmap_surface.dart';
import '../../models/bitmap_tile.dart';
import '../../models/brush_frame_key.dart';
import '../../models/pasteboard_bounds.dart';
import '../bitmap_surface_geometry.dart';
import 'brush_drawing_binary_codec.dart';
import 'scratch_file.dart';

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

/// [blob]'s picture behind [reach] — the wall of the store it is kept in —
/// as it [was] and as [move] leaves it ([translateBitmapSurface]), worked
/// out on a worker: both laid into the main isolate's tile blocks
/// ([BitmapTile.blocks]) for it to adopt ([laidCelSurface]). [moved] is null
/// for a move of whole tiles ([movesWholeTiles]): made where it is taken, it
/// renames the very tiles the picture had — its undo shares them — where
/// laid here it would copy every one.
///
/// ★The thaw a read of a kept cel makes on the main isolate and the blit the
/// resize then makes there (`BrushFrameStore.adoptCutCanvasSize`), made
/// here instead — the bytes cross as [layCelInWorker]'s do.
Future<({AnicelLaidCel was, AnicelLaidCel? moved})> moveCelInWorker(
  BrushFrameKey key,
  AnicelCelBlob blob, {
  required PasteboardReach reach,
  required CelMove move,
}) {
  final sent = TransferableTypedData.fromList([blob.bytes]);
  final blocks = BitmapTile.blocks;
  return onAWorker(() {
    final entry = AnicelCelBlob(sent.materialize().asUint8List()).decode();
    final here = tileBlocksHere(blocks);
    if (movesWholeTiles(dx: move.dx, dy: move.dy, tileSize: entry.tileSize)) {
      return (was: layCelEntry(entry, here), moved: null);
    }
    final laidMoved = _layMoved(
      key,
      surfaceBehindReach(entry.toSurface(), reach),
      move,
      here,
    );
    try {
      return (was: layCelEntry(entry, here), moved: laidMoved);
    } on Object {
      // Nothing else knows these blocks exist ([layCelEntry]'s own rule).
      freeLaidCel(laidMoved, here);
      rethrow;
    }
  });
}

/// A HOT cel's picture — its blocks on the main isolate, named where they
/// lie ([celBlocksOf]) — as [move] leaves it, worked out on a worker and
/// laid into that isolate's tile blocks for it to adopt ([laidCelSurface]):
/// the blit [moveCelInWorker] makes of a kept cel, for one already thawed —
/// and so already behind its store's wall, with nothing past it to cut.
///
/// 🗣️a-resize-redo-moves-every-cel-on-the-ui-thread-Q1 (유저 2026-10-22:
/// 「다시 하기도 대기 창 뒤에서 옮긴다」): a redo's cels are the ones its undo
/// put back, every one hot.
///
/// 🚨The caller holds the picture [at] names until this is done: its blocks
/// go back to the pool with it.
Future<AnicelLaidCel> moveHotCelInWorker(
  BrushFrameKey key,
  AnicelLaidCel at, {
  required CelMove move,
}) {
  final blocks = BitmapTile.blocks;
  return onAWorker(
    () => _layMoved(key, copiedCelSurface(at), move, tileBlocksHere(blocks)),
  );
}

/// [surface] moved by [move] ([translateBitmapSurface]) and laid into
/// [here]'s blocks — a kept cel's move and a hot one's.
AnicelLaidCel _layMoved(
  BrushFrameKey key,
  BitmapSurface surface,
  CelMove move,
  TileBlockHands here,
) {
  final (:canvasSize, :dx, :dy) = move;
  final moved = translateBitmapSurface(
    surface,
    dx: dx,
    dy: dy,
    canvasSize: canvasSize,
  );
  return layCelEntry(AnicelCelEntry.fromSurface(key, moved), here);
}

/// [blob]'s picture behind [reach] ([cutBehindReach]), worked out on a
/// worker: null when the wall cuts nothing of it, else the cut picture as
/// [key]'s blob, parked at [parkAt] in the room, and the picture as it
/// was, laid into the main isolate's tile blocks ([BitmapTile.blocks]) for
/// it to adopt ([laidCelSurface]) — what the undo keeps.
///
/// ★The decode, the cut, the encode and the park a move of the wall makes
/// of a kept cel on the main isolate (`BrushFrameStore._rewriteHere`),
/// made here instead — the bytes cross as [layCelInWorker]'s do. [parkAt]
/// is a path resolved there: the room's name means nothing on a worker
/// (`SessionScratch.ensureThisRunsFolder`).
///
/// Throws when the room will not take the bytes: nothing was worked out.
Future<({AnicelCelBlob blob, String path, AnicelLaidCel was})?>
cutCelInWorker(
  BrushFrameKey key,
  AnicelCelBlob blob,
  PasteboardReach reach, {
  required String parkAt,
}) async {
  final sent = TransferableTypedData.fromList([blob.bytes]);
  final blocks = BitmapTile.blocks;
  final cut = await onAWorker(() {
    final entry = AnicelCelBlob(sent.materialize().asUint8List()).decode();
    final behind = cutBehindReach(entry.toSurface(), reach);
    if (behind == null) {
      return null;
    }
    final kept = AnicelCelBlob.encode(AnicelCelEntry.fromSurface(key, behind));
    final path = ScratchFile.write(parkAt, kept.bytes);
    if (path == null) {
      throw StateError('The room would not take $parkAt.');
    }
    return (
      blob: TransferableTypedData.fromList([kept.bytes]),
      path: path,
      was: layCelEntry(entry, tileBlocksHere(blocks)),
    );
  });
  if (cut == null) {
    return null;
  }
  return (
    blob: AnicelCelBlob(cut.blob.materialize().asUint8List()),
    path: cut.path,
    was: cut.was,
  );
}
