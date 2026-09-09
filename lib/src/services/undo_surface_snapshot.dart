
import '../models/bitmap_surface.dart';
import '../models/bitmap_tile.dart';
import '../models/brush_frame_key.dart';
import '../models/canvas_size.dart';
import '../models/tile_coord.dart';
import 'persistence/brush_drawing_binary_codec.dart';
import 'persistence/compress_in_worker.dart';
import 'persistence/scratch_file.dart';
import 'persistence/volatile_scratch_files.dart';

/// The two pictures one undo entry holds — before the edit and after it.
///
/// 🚨★★★**THE BILL NAMES THE BEFORE; THE PARK MOVES BOTH.** That reads
/// like an inconsistency and is the opposite: entry n's [after] IS entry
/// n+1's [before], the same object by structural sharing, so charging
/// both would count a neighbour's bytes twice — and by that very sharing
/// a [before] let go on its own frees nothing, because the tiles stay
/// alive through the previous entry's [after].
///
/// ⚠️Two commands hold exactly this shape (a stroke and a confirmed
/// move), and they held it as two identical bodies until the clone scan
/// said so. The asymmetry above is the reason it is a TYPE rather than a
/// helper: written twice, one of the two copies eventually starts
/// charging for [after].
class UndoSurfacePair {
  UndoSurfacePair({
    required BrushFrameKey key,
    required BitmapSurface before,
    required BitmapSurface after,
  }) : before = UndoSurfaceSnapshot(
         key: key,
         snapshot: before,
         sharedWith: after,
       ),
       after = UndoSurfaceSnapshot(
         key: key,
         snapshot: after,
         sharedWith: before,
       );

  final UndoSurfaceSnapshot before;
  final UndoSurfaceSnapshot after;

  /// The half the cel is NOT currently showing — see
  /// [RetainedBytesCommand.estimatedRetainedBytes] for why the question
  /// needs [undone] and for the 11.5-vs-18.5 MiB that says so.
  ///
  /// ⛔Never the sum. Entry n's [after] IS entry n+1's [before], so on
  /// either stack adding both halves would count a neighbour's tiles
  /// twice — and the two stacks are symmetric, not different: applied
  /// entries owe their befores, undone entries owe their afters, and
  /// neither run overlaps itself.
  int residentBytes({required bool undone}) =>
      undone ? after.residentBytes : before.residentBytes;

  Future<bool> park() => UndoSurfaceSnapshot.parkAll([before, after]);

  void drop() => UndoSurfaceSnapshot.dropAll([before, after]);
}

/// ONE surface an undo entry is holding, and its residence: in memory, or
/// parked in the run's 휘발성 room.
///
/// 🚨★★★**THE BUDGET STOPS THROWING WORK AWAY.** An over-budget undo
/// payload used to be DELETED — the entry left the deep end of the stack
/// and the user's older edits simply stopped being undoable. Of the tools
/// the audit read, not one answers a byte ceiling that way: Krita swaps
/// its undo tiles out first, OpenToonz parks them in the image cache's
/// disk tier, Photoshop pages them to the scratch file it already keeps
/// for the document. 유저 확정 2026-09-07 (`cold-tier`).
///
/// 🚨★★★**ONLY THE TILES THIS SNAPSHOT ALONE HOLDS ARE WRITTEN.** The
/// rest are the same OBJECTS the live surface holds ([tilesNotSharedWith]
/// is how that is decided, and it is the same law the byte budget bills
/// by) — writing them would copy bytes that are not going anywhere and
/// would hand back new objects on the way in, breaking the structural
/// sharing that makes the next snapshot cheap. OpenToonz makes exactly
/// that mistake in its Refer Fill capture and throws away the tile-grid
/// saving it had already earned.
///
/// ⚠️**A PARKED SNAPSHOT REPORTS ZERO, AND THAT IS A CLAIM ABOUT RAM.**
/// It is only true if every other reference to those tiles went with it —
/// which is why [HistoryManager] parks a CONTIGUOUS DEEP PREFIX rather
/// than whichever entry looks heaviest: entry n's post-surface IS entry
/// n+1's pre-surface, so one entry letting go on its own frees nothing.
///
/// ⚠️No format of its own: the payload is an [AnicelCelBlob], the same
/// thing a cooled cel becomes, so the codec is picked in the one place
/// that picks codecs and a second encoder cannot drift from it.
///
/// ⚠️And that reuse is what pins the codec HERE too, with no second test:
/// `the_cooling_path_is_zstd_test` drives `AnicelCelBlob.encode` through
/// `Isolate.run`, which is exactly the call [park] makes. The hazard it
/// watches — statics do not cross an isolate boundary, so a worker that
/// cannot find the engine silently writes deflate and nothing goes red —
/// is one hazard, not two. ⛔A copy of that test aimed at this class
/// would measure the same thing twice.
class UndoSurfaceSnapshot {
  /// Parks every snapshot an entry holds, answering false if ANY refused
  /// — an entry stops holding RAM only when all of it has moved.
  ///
  /// ⚠️The same shape as `parkPayloadsOf`, over snapshots rather than
  /// commands, and deliberately NOT merged with it: this is the second of
  /// the two, and in this house a third has to turn up before two become
  /// one. Merging them now would mean a helper that takes a list of
  /// "things that might park", which names nothing.
  static Future<bool> parkAll(Iterable<UndoSurfaceSnapshot> snapshots) async {
    var parked = true;
    for (final snapshot in snapshots) {
      if (!await snapshot.park()) {
        parked = false;
      }
    }
    return parked;
  }

  /// Gives the room back every parked snapshot an entry held.
  static void dropAll(Iterable<UndoSurfaceSnapshot> snapshots) {
    for (final snapshot in snapshots) {
      snapshot.drop();
    }
  }

  UndoSurfaceSnapshot({
    required this.key,
    required BitmapSurface snapshot,
    required BitmapSurface? sharedWith,
  }) : _canvasSize = snapshot.canvasSize,
       _tileSize = snapshot.tileSize,
       _surface = snapshot,
       _owned = snapshot.tilesNotSharedWith(sharedWith);

  /// Which cel these pixels are — the blob header wants it, and a crash
  /// dump of the room can then say which drawing it was looking at.
  final BrushFrameKey key;

  final CanvasSize _canvasSize;
  final int _tileSize;

  /// WHERE the tiles somebody else is holding are — coordinates only.
  ///
  /// 🚨★★★**IT HELD THE TILES THEMSELVES, AND THAT QUIETLY DEFEATED
  /// PARKING.** The comment here said they「cost this snapshot nothing」
  /// because somebody else holds them — true at the instant of measuring,
  /// and false the moment the picture moves past them. A tile that is
  /// [_owned] by entry n is [_shared] by every entry below n, and [park]
  /// dropped `_owned` while keeping `_shared`: the deep prefix reported
  /// zero and the bytes stayed. 🧪Measured on a 60-tap pass, parking the
  /// whole prefix: **billed 34.3 MiB, freed 22.3 MiB, 12.0 MiB still
  /// pinned** by this field alone (2026-09-09).
  ///
  /// ⛔So it cannot hold a tile at all now. The rebuild takes them from
  /// the surface handed to [surfaceOver], which by the stack's own LIFO
  /// order is the very surface this one was measured against.
  ///
  /// ⚠️**AND IT IS FILLED IN BY [_releaseTiles], NOT BY THE CONSTRUCTOR.**
  /// It can only be computed while [_surface] is still here, and it is
  /// only ever NEEDED once [_surface] is gone — so building it eagerly
  /// walked the whole cel for every snapshot ever made, parked or not.
  /// A pair holds two of these, and a stroke makes a pair: 🧪two full
  /// walks of the cel per commit, spent on an answer almost none of them
  /// would be asked for. Null until the tiles are let go.
  Set<TileCoord>? _sharedCoords;

  /// The tiles only this snapshot holds — null once they are on disk.
  Map<TileCoord, BitmapTile>? _owned;

  BitmapSurface? _surface;

  /// The file, when there was anything worth writing. ⛔NOT the answer to
  /// "has it parked" — a snapshot that owned no tile lets go of its
  /// surface without writing a byte, and asking this would call that one
  /// resident forever.
  String? _parkedPath;

  /// Whether the tiles have left RAM, by either route.
  bool _letGo = false;

  bool get isParked => _letGo;

  /// RAM this snapshot is holding on its own: zero once parked, because
  /// the bytes are then a file.
  int get residentBytes =>
      (_owned?.length ?? 0) * BitmapTile.bytesFor(_tileSize);

  /// The surface, read back from the room if it is parked — or NULL when
  /// the payload will not come back.
  ///
  /// ⛔**Nullable, and never the shared tiles alone.** A snapshot that
  /// answered with only the tiles it happens to still hold would be a
  /// surface with holes where the drawing was, and undo would silently
  /// paint that over the picture. A refusal is honest: the caller leaves
  /// the canvas exactly as it is.
  ///
  /// Reading is SYNCHRONOUS, and that is the shape undo has: the stack is
  /// stepped from a keystroke. It is affordable because the spill parks
  /// the DEEP end — the entry the user is about to press Ctrl+Z on is the
  /// last one that would ever be on disk.
  ///
  /// 🚨★★★**[live] IS THE SURFACE THIS ONE WAS MEASURED AGAINST**, which
  /// for a history entry is simply the cel as it stands right now: the
  /// stack steps LIFO, so when entry n is undone the cel IS entry n's
  /// post-surface, and when it is redone the cel IS its pre-surface. Both
  /// are the `sharedWith` this snapshot was built with. The shared tiles
  /// are read back out of it rather than held here — see [_sharedCoords]
  /// for the 12 MiB that cost.
  ///
  /// ⛔It REFUSES rather than guessing when [live] cannot answer for a
  /// shared coordinate. A surface assembled from a stale base would be the
  /// wrong picture painted over the right one, which is worse than the
  /// undo not happening.
  BitmapSurface? surfaceOver(BitmapSurface? live) {
    // ⛔THE DROP COMES FIRST, and [drop]'s own doc is why: it「stays a
    // valid snapshot afterwards — one that answers null」. Without this
    // the shared half would still assemble, and a snapshot whose owned
    // tiles were taken back would answer with a picture full of holes —
    // the one answer this getter exists to refuse.
    if (_dropped) {
      return null;
    }
    final resident = _surface;
    if (resident != null) {
      return resident;
    }
    if (!_letGo) {
      return null;
    }
    final shared = _sharedTilesFrom(live);
    if (shared == null) {
      return null;
    }
    final path = _parkedPath;
    if (path == null) {
      // It let go without writing anything: it owned no tile, so the
      // shared ones ARE the whole picture and there are no holes in it.
      _letGo = false;
      return _surface = BitmapSurface(
        canvasSize: _canvasSize,
        tileSize: _tileSize,
        tiles: shared,
      );
    }
    final bytes = ScratchFile.read(path);
    if (bytes == null) {
      return null;
    }
    final Map<TileCoord, BitmapTile> owned;
    try {
      owned = AnicelCelBlob(bytes).decode().toSurface().tiles;
    } on Object {
      return null;
    }
    // Resident again, and the file is dead the moment its bytes are back:
    // a later park writes a fresh one, and leaving this behind would grow
    // the room by a copy per undo.
    _owned = owned;
    _surface = BitmapSurface(
      canvasSize: _canvasSize,
      tileSize: _tileSize,
      tiles: {...shared, ...owned},
    );
    _parkedPath = null;
    // Resident again by every measure — [isParked] has to say so, or a
    // later park would take its own early return and never write.
    _letGo = false;
    ScratchFile.remove(path);
    return _surface;
  }

  /// The shared tiles, taken from [live] — or null when it cannot answer
  /// for every coordinate this snapshot expects of it.
  Map<TileCoord, BitmapTile>? _sharedTilesFrom(BitmapSurface? live) {
    final shared = _sharedCoords;
    if (shared == null) {
      // Never let go, so nothing pinned the coordinates — and a snapshot
      // that still HOLDS its surface never reaches here.
      return null;
    }
    if (shared.isEmpty) {
      return const {};
    }
    if (live == null) {
      return null;
    }
    final tiles = <TileCoord, BitmapTile>{};
    for (final coord in shared) {
      final tile = live.tileAt(coord);
      if (tile == null) {
        return null;
      }
      tiles[coord] = tile;
    }
    return tiles;
  }

  /// Moves the owned tiles into the run's 휘발성 room. Answers false when
  /// the room refused — the caller then still HOLDS the bytes and has to
  /// decide whether to keep them or drop the entry.
  ///
  /// 🚨★★★**PARK IT BEFORE LETTING GO OF IT**, the same order
  /// `BrushFrameStore._coolLoop` keeps: the write can fail, so the
  /// reference is dropped only once the room has answered yes.
  ///
  /// ⚠️Compression happens HERE, in a background isolate, and nowhere
  /// else. Not at record time — a stroke would pay for a spill that may
  /// never happen — and not inside [VolatileScratchFiles], which takes
  /// bytes and has no opinion about them. Every tool the audit read
  /// compresses on the way OUT, and two of them do it synchronously on
  /// the thread that noticed the pressure; this is that mistake avoided
  /// rather than reproduced.
  /// The park in flight, so a second ask joins it instead of starting a
  /// second one.
  ///
  /// 🚨A park spans an isolate hop, and the window between「encode」and
  /// 「the path is mine」is wide open. Two memory warnings in quick
  /// succession — the OS sends them in bursts — would each encode the same
  /// tiles and each write a file, and only the second path would be
  /// remembered: the first file becomes bytes on the user's disk that
  /// nothing will ever read or remove. The history stack serialises its
  /// own passes; a tool holding a lifted selection does not.
  Future<bool>? _parking;

  Future<bool> park() {
    final parking = _parking;
    if (parking != null) {
      return parking;
    }
    final started = _park();
    _parking = started;
    return started.whenComplete(() => _parking = null);
  }

  Future<bool> _park() async {
    if (isParked) {
      return true;
    }
    final owned = _owned;
    if (owned == null || owned.isEmpty) {
      // Nothing of its own to move — every tile is somebody else's, so no
      // file would free anything.
      //
      // 🚨★★★**BUT IT STILL HAD TO LET GO.** "Somebody else's" is a claim
      // about the instant it was measured; [_surface] is a reference to
      // the WHOLE picture, and once the drawing moves past those tiles it
      // is the last one holding them. This early return kept it, so the
      // one snapshot the budget was sure cost nothing was the one that
      // went on costing — the same mistake [_sharedCoords] records, in the
      // branch that looked too trivial to have it.
      _releaseTiles();
      _letGo = true;
      return true;
    }
    // 🎯ONE copy of the payload, not four. The surface serialises
    // straight into a flat buffer (no per-tile defensive copy), the
    // buffer MOVES to the worker, and the compressed bytes move back
    // — see [compressAnicelPayloadInWorker] for the measurement.
    final body = encodeCelEntryFromSurface(
      key,
      BitmapSurface(
        canvasSize: _canvasSize,
        tileSize: _tileSize,
        tiles: owned,
      ),
    );
    final compressed = await compressAnicelPayloadInWorker(body);
    final blob = AnicelCelBlob.fromCompressedBody(
      key: key,
      canvasSize: _canvasSize,
      tileSize: _tileSize,
      codec: compressed.codec,
      body: compressed.bytes,
    );
    final path = VolatileScratchFiles.write(blob.bytes);
    if (path == null) {
      return false;
    }
    if (_dropped) {
      // 🚨THE ENTRY LEFT THE STACK WHILE THE ENCODE WAS IN THE ISOLATE.
      // [drop] could not give this file back — it did not exist yet, and
      // `_parkedPath` was still null — so the only place that can is here,
      // on the way out. Without it the spill leaves one unreadable,
      // unremovable file per shed entry, which is the exact shape
      // [ParkableCommand.dropPayload] exists to prevent. The window is
      // wide open in practice: the stack sheds and trims from `_push`,
      // synchronously, while this await is parked on the event loop.
      ScratchFile.remove(path);
      _releaseTiles();
      return true;
    }
    _parkedPath = path;
    _releaseTiles();
    _letGo = true;
    return true;
  }

  /// Lets go of the tiles — and pins [_sharedCoords] on the way out.
  ///
  /// 🚨★★★**THE TWO ARE ONE STEP, AND THAT IS THE WHOLE REASON THIS IS A
  /// METHOD.** Which coordinates somebody else holds can only be worked
  /// out while [_surface] is still here, and it is only ever ASKED for
  /// after [_surface] is gone. Written as two statements the answer was
  /// built in the CONSTRUCTOR — for every snapshot ever made, parked or
  /// not — which is a walk of the whole cel, twice per commit, for an
  /// answer almost none of them are asked. Written as one step, exactly
  /// the snapshots that let go pay for it, and the order cannot be got
  /// wrong: there is no way to drop the surface without pinning the
  /// coordinates first.
  ///
  /// ⚠️Idempotent on purpose — the dropped-mid-encode branch of [_park]
  /// releases without setting [_letGo], so a later [park] can arrive
  /// here a second time and must not throw or widen the answer.
  void _releaseTiles() {
    final surface = _surface;
    if (surface != null) {
      final owned = _owned;
      _sharedCoords = {
        for (final coord in surface.tiles.keys)
          if (owned == null || !owned.containsKey(coord)) coord,
      };
    }
    _owned = null;
    _surface = null;
  }

  /// The entry holding this is leaving the stack: nobody can ask for
  /// these bytes again, so the room takes the file back.
  ///
  /// ⚠️It stays a valid snapshot afterwards — one that answers null. The
  /// alternative, leaving it able to read a file that is gone, is the
  /// same answer by a slower route.
  void drop() {
    // ⚠️SET FIRST, and it is the whole point of the flag: a park may be in
    // the isolate right now, in which case there is no path to remove yet
    // and [_park] has to do it when it lands. Reading `_parkedPath` alone
    // made this a silent no-op exactly when the room was busiest.
    _dropped = true;
    final path = _parkedPath;
    if (path == null) {
      return;
    }
    _parkedPath = null;
    ScratchFile.remove(path);
  }

  /// Whether the entry holding this has left the stack. Never unset: an
  /// entry does not come back, and a park that lands afterwards must give
  /// its file straight back rather than record it.
  bool _dropped = false;
}
