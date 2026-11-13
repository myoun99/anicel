import 'dart:io' show Platform;
import 'dart:isolate';

import '../../core/on_a_worker.dart';
import '../../core/turns.dart';
import '../../core/worker_count.dart';
import '../../models/bitmap_surface.dart';
import '../../models/bitmap_tile.dart';
import '../../models/brush_frame_key.dart';
import '../../models/canvas_size.dart';
import '../../models/pasteboard_bounds.dart';
import '../bitmap_surface_geometry.dart';
import 'brush_drawing_binary_codec.dart';
import 'scratch_file.dart';

/// [blob] inflated, parsed, put behind the wall of [reach] ([_behindReach])
/// and laid into tile blocks on a worker isolate (`TileBlocks`, the
/// process's one allocator) — so all that is left on the main isolate is
/// adopting them standing behind [reach] ([laidCelSurface]).
///
/// 🔬On the UI thread (card `cel-thaw-holds-the-ui-thread`, a profile build,
/// 2026-10-15) this was 60–70 ms of a first playback's late frames: the tile
/// copies ~40, zstd 20–27.
///
/// The bytes cross as a [TransferableTypedData], the parking path's way
/// (`compressCelOnAWorker` says why).
Future<AnicelLaidCel> layCelInWorker(
  AnicelCelBlob blob, {
  required PasteboardReach reach,
}) {
  final sent = TransferableTypedData.fromList([blob.bytes]);
  return onAWorker(
    () => AnicelCelBlob(
      sent.materialize().asUint8List(),
    ).decoded((entry) => layCelEntry(_behindReach(entry, reach))),
  );
}

/// [entry] behind the wall of [reach] — its tiles and its texts' plates cut
/// as [surfaceBehindReach] cuts a picture's, a file's picture left whole
/// ([tileBytesBehindWall]) — made of its bytes before they are laid: a
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
  final wall = entry.canvasSize.pasteboardAt(reach).region;
  List<AnicelTileRecord> behind(List<AnicelTileRecord> tiles) =>
      tileBytesBehindWall(
        tiles,
        wall: wall,
        laid: entry.laidBounds,
        tileSize: entry.tileSize,
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
/// out on a worker: both laid into tile blocks for the main isolate to
/// adopt standing behind [reach] ([laidCelSurface]). [moved] is null for a
/// move of whole tiles ([movesWholeTiles]): made where it is taken, it
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
  return onAWorker(
    () => AnicelCelBlob(sent.materialize().asUint8List()).decoded((entry) {
      final was = _behindReach(entry, reach);
      if (movesWholeTiles(dx: move.dx, dy: move.dy, tileSize: entry.tileSize)) {
        return (was: layCelEntry(was), moved: null);
      }
      final laidMoved = layCelEntry(
        AnicelCelEntry.fromSurface(
          key,
          movedBy(surfaceBehindReach(entry.toSurface(), reach), move),
        ),
      );
      try {
        return (was: layCelEntry(was), moved: laidMoved);
      } on Object {
        // Nothing else knows these blocks exist ([layCelEntry]'s own rule).
        freeLaidCel(laidMoved);
        rethrow;
      }
    }),
  );
}

/// A HOT cel's [surface] as [move] leaves it, worked out on a worker that
/// reads its blocks where they lie: the blit [moveCelInWorker] makes of a
/// kept cel, for one already thawed — and so already behind its store's
/// wall, with nothing past it to cut.
///
/// 🗣️a-resize-redo-moves-every-cel-on-the-ui-thread-Q1 (유저 2026-10-22:
/// 「다시 하기도 대기 창 뒤에서 옮긴다」): a redo's cels are the ones its undo
/// put back, every one hot.
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
/// The cut a move of the wall makes of a kept cel ([remakeKeptCelInWorker]
/// with [cutBehind]), for one already thawed.
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

/// A hot cel's [surface] — copied into a worker's own tiles
/// ([onAWorkerWithCelCopy]) — made anew there by [remake], laid into tile
/// blocks and adopted here behind the wall [remake] left it at; null where
/// [remake] leaves the picture as it is.
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
  final made = await onAWorkerWithCelCopy(
    key.cel,
    surface,
    _remadeAndLaid(key, remake),
  );
  return made == null
      ? null
      : laidCelSurface(made.laid, standsBehind: made.standsBehind);
}

/// What a worker makes of a hot cel's copy ([_remakeHotCelInWorker]) — made
/// HERE, the closure crossing with only these.
({AnicelLaidCel laid, PasteboardReach standsBehind})? Function(BitmapSurface)
_remadeAndLaid(
  BrushFrameKey key,
  BitmapSurface? Function(BitmapSurface copy) remake,
) => (copy) {
  final made = remake(copy);
  return made == null
      ? null
      : (
          laid: layCelEntry(AnicelCelEntry.fromSurface(key, made)),
          standsBehind: made.pasteboardReach,
        );
};

/// What a kept cel's picture is made into — null where it is left as it is
/// ([remakeKeptCel]). It crosses to a worker with the picture's bytes
/// ([remakeKeptCelInWorker]), so each is made by a function of this file
/// and holds only what it names ([cutBehind], [laidOn]).
typedef KeptCelRemake = BitmapSurface? Function(BitmapSurface picture);

/// The cut a move of the wall to [to] makes of a picture ([cutBehindReach]).
KeptCelRemake cutBehind(PasteboardReach to) =>
    (picture) => cutBehindReach(picture, to);

/// A picture laid on a canvas of [size] — top-left anchored, as a resize
/// lays it ([resizeBitmapSurfaceCanvas]) — behind the wall of [reach].
KeptCelRemake laidOn(CanvasSize size, {required PasteboardReach reach}) =>
    (picture) =>
        resizeBitmapSurfaceCanvas(surfaceBehindReach(picture, reach), size);

/// [blob]'s picture made anew by [remake] as [key]'s blob, parked at
/// [parkAt] in the room — null where [remake] leaves it as it is, and a
/// [path] of null where the room would not take the bytes. Where
/// [wasBehind] names a wall, the picture as it [was] comes too, behind
/// that wall ([_behindReach]) and laid into tile blocks for the main
/// isolate to adopt standing there ([laidCelSurface]): what an undo keeps.
///
/// 🚨★★★**ONE ALGORITHM, WHEREVER IT RUNS.** The decode, the remake, the
/// encode and the park were written out three times — on a worker for a
/// move of the wall, on the UI thread for a kept cel the worker had not
/// worked out (`BrushFrameStore._rewriteHere`), and once more for a copy
/// onto a canvas of another size (`BrushFrameStore.copyCel`). 🗣️Card
/// `a-kept-cel-copied-to-another-canvas-size-is-rewritten-on-the-ui-thread`
/// (관제 11-14, from the same law as the store's one rewrite loop): they
/// differ only in where they run, so the three call this.
RemadeKeptCel? remakeKeptCel(
  BrushFrameKey key,
  AnicelCelBlob blob,
  KeptCelRemake remake, {
  required String parkAt,
  PasteboardReach? wasBehind,
}) => blob.decoded((entry) {
  final made = remake(entry.toSurface());
  if (made == null) {
    return null;
  }
  // ⛔A worker has no engine — the app's one is the main isolate's
  // (`appGpuEngine`, a static) — so what it decoded it writes from the
  // bytes it decoded; and on the main isolate a picture decoded here holds
  // no tile of the engine's either. ⏳Till a tile's bytes are the engine's
  // alone (flip lane ⓔ), when a worker's cut works on the stream's tiles.
  final kept = AnicelCelBlob.ofSurface(key, made, bytesOf: readTilesInPlace);
  final path = ScratchFile.write(parkAt, kept.bytes);
  // ⚠️Laid only once the bytes are parked: nothing else knows the blocks
  // exist ([layCelEntry]'s own rule), so a refusal would leave them behind.
  if (path == null || wasBehind == null) {
    return (blob: kept, path: path, was: null);
  }
  return (
    blob: kept,
    path: path,
    was: layCelEntry(_behindReach(entry, wasBehind)),
  );
});

/// A kept cel remade ([remakeKeptCel]).
typedef RemadeKeptCel = ({
  AnicelCelBlob blob,
  String? path,
  AnicelLaidCel? was,
});

/// [remakeKeptCel] on a worker — the bytes cross as [layCelInWorker]'s do.
/// [parkAt] is a path resolved here: the room's name means nothing on a
/// worker (`SessionScratch.ensureThisRunsFolder`).
///
/// Throws when the room will not take the bytes: nothing was worked out.
Future<({AnicelCelBlob blob, String path, AnicelLaidCel? was})?>
remakeKeptCelInWorker(
  BrushFrameKey key,
  AnicelCelBlob blob,
  KeptCelRemake remake, {
  required String parkAt,
  PasteboardReach? wasBehind,
}) async {
  final sent = TransferableTypedData.fromList([blob.bytes]);
  final made = await onAWorker(() {
    final remade = remakeKeptCel(
      key,
      AnicelCelBlob(sent.materialize().asUint8List()),
      remake,
      parkAt: parkAt,
      wasBehind: wasBehind,
    );
    if (remade == null) {
      return null;
    }
    final path = remade.path;
    if (path == null) {
      throw StateError('The room would not take $parkAt.');
    }
    return (
      blob: TransferableTypedData.fromList([remade.blob.bytes]),
      path: path,
      was: remade.was,
    );
  });
  if (made == null) {
    return null;
  }
  return (
    blob: AnicelCelBlob(made.blob.materialize().asUint8List()),
    path: made.path,
    was: made.was,
  );
}
