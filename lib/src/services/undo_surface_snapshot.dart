import 'dart:isolate';

import '../models/bitmap_surface.dart';
import '../models/bitmap_tile.dart';
import '../models/brush_frame_key.dart';
import '../models/canvas_size.dart';
import '../models/tile_coord.dart';
import 'persistence/brush_drawing_binary_codec.dart';
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

  int get residentBytes => before.residentBytes;

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
       _owned = snapshot.tilesNotSharedWith(sharedWith) {
    _shared = {
      for (final entry in snapshot.tiles.entries)
        if (!_owned!.containsKey(entry.key)) entry.key: entry.value,
    };
  }

  /// Which cel these pixels are — the blob header wants it, and a crash
  /// dump of the room can then say which drawing it was looking at.
  final BrushFrameKey key;

  final CanvasSize _canvasSize;
  final int _tileSize;

  /// The tiles somebody else is holding anyway. Kept BY REFERENCE across a
  /// park: they cost this snapshot nothing, and holding them is what lets
  /// the way back rebuild the surface without reading them off disk.
  late final Map<TileCoord, BitmapTile> _shared;

  /// The tiles only this snapshot holds — null once they are on disk.
  Map<TileCoord, BitmapTile>? _owned;

  BitmapSurface? _surface;
  String? _parkedPath;

  bool get isParked => _parkedPath != null;

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
  BitmapSurface? get surface {
    final resident = _surface;
    if (resident != null) {
      return resident;
    }
    final path = _parkedPath;
    if (path == null) {
      return null;
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
      tiles: {..._shared, ...owned},
    );
    _parkedPath = null;
    ScratchFile.remove(path);
    return _surface;
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
  Future<bool> park() async {
    if (isParked) {
      return true;
    }
    final owned = _owned;
    if (owned == null || owned.isEmpty) {
      // Nothing of its own to move — every tile is somebody else's, so it
      // is already weightless and there is nothing a file would free.
      return true;
    }
    final entry = AnicelCelEntry.fromSurface(
      key,
      BitmapSurface(
        canvasSize: _canvasSize,
        tileSize: _tileSize,
        tiles: owned,
      ),
    );
    final blob = await Isolate.run(() => AnicelCelBlob.encode(entry));
    final path = VolatileScratchFiles.write(blob.bytes);
    if (path == null) {
      return false;
    }
    _parkedPath = path;
    _owned = null;
    _surface = null;
    return true;
  }

  /// The entry holding this is leaving the stack: nobody can ask for
  /// these bytes again, so the room takes the file back.
  ///
  /// ⚠️It stays a valid snapshot afterwards — one that answers null. The
  /// alternative, leaving it able to read a file that is gone, is the
  /// same answer by a slower route.
  void drop() {
    final path = _parkedPath;
    if (path == null) {
      return;
    }
    _parkedPath = null;
    ScratchFile.remove(path);
  }
}
