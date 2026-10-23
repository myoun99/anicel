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

/// [blob] inflated, parsed, put behind the wall of [reach] ([_behindReach])
/// and laid into tile blocks on a worker isolate, from the allocator
/// [blocks] names — the main isolate's ([BitmapTile.blocks]) — so all that
/// is left there is adopting them standing behind [reach]
/// ([laidCelSurface]).
///
/// 🔬On the UI thread (card `cel-thaw-holds-the-ui-thread`, a profile build,
/// 2026-10-15) this was 60–70 ms of a first playback's late frames: the tile
/// copies ~40, zstd 20–27.
///
/// The bytes cross as a [TransferableTypedData], the parking path's way
/// (`compressAnicelPayloadInWorker` says why).
Future<AnicelLaidCel> layCelInWorker(
  AnicelCelBlob blob,
  TileBlocks blocks, {
  required PasteboardReach reach,
}) {
  final sent = TransferableTypedData.fromList([blob.bytes]);
  return onAWorker(
    () => layCelEntry(
      _behindReach(
        AnicelCelBlob(sent.materialize().asUint8List()).decode(),
        reach,
      ),
      tileBlocksHere(blocks),
    ),
  );
}

/// [entry] behind the wall of [reach] — its tiles and its texts' plates cut
/// as [surfaceBehindReach] cuts a picture's, a file's picture left whole
/// ([tileBytesBehindReach]) — made of its bytes before they are laid: a
/// tile the wall keeps whole is laid as it came, and only one it crosses is
/// copied. Itself at [PasteboardReach.whole], the wall bytes laid as they
/// are stand behind ([laidCelSurface]).
///
/// 🗣️Card `a-thawed-cel-is-walled-again-on-the-ui-thread`: kept bytes carry
/// no wall (the file's format), so a kept cel was laid with none and walled
/// on the main isolate — every tile the wall crosses copied there again, on
/// every thaw. 🔬S5_BA (2026-10-22, 122 cels, `flutter test`): with the
/// pasteboard off 61 ms and 1,186 tiles, up to 2 ms a cel — some 26 ms of a
/// frame whose 13 rows thaw at once.
///
/// ⛔Not by way of a surface ([AnicelCelEntry.toSurface], then back): every
/// tile would be copied twice more on the worker, and the copies were most
/// of a thaw's time.
AnicelCelEntry _behindReach(AnicelCelEntry entry, PasteboardReach reach) {
  if (reach == PasteboardReach.whole) {
    return entry;
  }
  List<AnicelTileRecord> behind(List<AnicelTileRecord> tiles) =>
      tileBytesBehindReach(
        tiles,
        canvasSize: entry.canvasSize,
        reach: reach,
        tileSize: entry.tileSize,
        laid: entry.laidBounds,
      );
  return AnicelCelEntry(
    key: entry.key,
    canvasSize: entry.canvasSize,
    tileSize: entry.tileSize,
    tiles: behind(entry.tiles),
    texts: [
      for (final text in entry.texts)
        (id: text.id, content: text.content, plate: behind(text.plate)),
    ],
    photos: entry.photos,
    laidBounds: entry.laidBounds,
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
/// ([BitmapTile.blocks]) for it to adopt standing behind [reach]
/// ([laidCelSurface]). [moved] is null
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
    final was = _behindReach(entry, reach);
    if (movesWholeTiles(dx: move.dx, dy: move.dy, tileSize: entry.tileSize)) {
      return (was: layCelEntry(was, here), moved: null);
    }
    final laidMoved = layCelEntry(
      AnicelCelEntry.fromSurface(
        key,
        movedBy(surfaceBehindReach(entry.toSurface(), reach), move),
      ),
      here,
    );
    try {
      return (was: layCelEntry(was, here), moved: laidMoved);
    } on Object {
      // Nothing else knows these blocks exist ([layCelEntry]'s own rule).
      freeLaidCel(laidMoved, here);
      rethrow;
    }
  });
}

/// A HOT cel's [surface] as [move] leaves it, worked out on a worker that
/// reads its blocks where they lie: the blit [moveCelInWorker] makes of a
/// kept cel, for one already thawed — and so already behind its store's
/// wall, with nothing past it to cut.
///
/// 🗣️a-resize-redo-moves-every-cel-on-the-ui-thread-Q1 (유저 2026-10-22:
/// 「다시 하기도 대기 창 뒤에서 옮긴다」): a redo's cels are the ones its undo
/// put back, every one hot.
///
/// 🚨The caller holds [surface] until this is done: its blocks go back to
/// the pool with it.
Future<BitmapSurface> moveHotCelInWorker(
  BrushFrameKey key,
  BitmapSurface surface, {
  required CelMove move,
}) async => (await _remakeHotCelInWorker(
  key,
  surface,
  (copy) => movedBy(copy, move),
))!;

/// A HOT cel's [surface] behind [reach] ([cutBehindReach]): the tiles the
/// wall crosses cleared on a worker as [moveHotCelInWorker] moves them
/// ([wallCrossingsOf]), and the rest decided here as a cut here decides it
/// ([surfaceBehindReach]) — so a tile it keeps whole is still the very
/// tile, and the undo shares it. Null where the wall cuts nothing of it.
/// The cut [cutCelInWorker] makes of a kept cel, for one already thawed.
///
/// 🗣️[F-432] (유저 2026-10-21: 「이런 시간 걸리는 로직은 규칙으로서 공용
/// 로딩창 표시해야함」): a pasteboard's step undone and done again lays back
/// hot every cel its first run cut, and the redo cut them on the UI thread.
/// ⚠️Every tile laid anew, the undo of S5_BA's 92 cels held them twice.
Future<BitmapSurface?> cutHotCelInWorker(
  BrushFrameKey key,
  BitmapSurface surface,
  PasteboardReach reach,
) async {
  final crossed = await _remakeHotCelInWorker(key, surface, (copy) {
    final behind = cutBehindReach(copy, reach);
    return behind == null ? null : wallCrossingsOf(copy, behind);
  });
  return crossed == null
      ? null
      : surfaceBehindReach(surface, reach, crossed: crossed);
}

/// A hot cel's [surface] — its blocks, read where they lie ([celBlocksOf])
/// — copied into a worker's own tiles ([copiedCelSurface]), made anew there
/// by [remake], laid into this isolate's tile blocks and adopted behind the
/// wall [remake] left it at; null where [remake] leaves the picture as it
/// is.
///
/// ⚠️A laid cel carries no wall of its own, so the wall crosses beside it:
/// adopted with none and walled on the main isolate, every tile the wall
/// crosses would be copied a second time there ([surfaceBehindReach]) — and
/// a move made against no wall clips where the main isolate's would not.
Future<BitmapSurface?> _remakeHotCelInWorker(
  BrushFrameKey key,
  BitmapSurface surface,
  BitmapSurface? Function(BitmapSurface copy) remake,
) async {
  final at = celBlocksOf(surface);
  final standsBehind = surface.pasteboardReach;
  final blocks = BitmapTile.blocks;
  final made = await onAWorker(() {
    final made = remake(copiedCelSurface(at, standsBehind: standsBehind));
    return made == null
        ? null
        : (
            laid: layCelEntry(
              AnicelCelEntry.fromSurface(key, made),
              tileBlocksHere(blocks),
            ),
            standsBehind: made.pasteboardReach,
          );
  });
  return made == null
      ? null
      : laidCelSurface(made.laid, standsBehind: made.standsBehind);
}

/// [blob]'s picture behind [reach] ([cutBehindReach]), worked out on a
/// worker: null when the wall cuts nothing of it, else the cut picture as
/// [key]'s blob, parked at [parkAt] in the room, and the picture as it
/// was — behind [standsBehind], the wall its store keeps it at
/// ([_behindReach]) — laid into the main isolate's tile blocks
/// ([BitmapTile.blocks]) for it to adopt standing there
/// ([laidCelSurface]): what the undo keeps, and lays back behind that wall.
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
  required PasteboardReach standsBehind,
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
      was: layCelEntry(
        _behindReach(entry, standsBehind),
        tileBlocksHere(blocks),
      ),
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
