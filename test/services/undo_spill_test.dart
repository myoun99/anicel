import 'dart:io';

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
import 'package:anicel/src/services/command.dart';
import 'package:anicel/src/services/history_manager.dart';
import 'package:anicel/src/services/persistence/session_scratch.dart';
import 'package:anicel/src/services/undo_surface_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

/// 🚨★★★**OVER BUDGET MUST MEAN "MOVE IT", NOT "LOSE IT".** Until this
/// round the deep end of the undo stack was DELETED when the byte budget
/// was exceeded — the user's older edits silently stopped being undoable,
/// and nothing on screen said so. 유저 확정 2026-09-07 (`cold-tier`).
///
/// Every case here is paired with the mutation that must turn it red.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const size = 8;
  const canvas = CanvasSize(width: 64, height: 64);

  BrushFrameKey keyOf(String frame) => BrushFrameKey(
    projectId: const ProjectId('p'),
    trackId: const TrackId('t'),
    cutId: const CutId('c'),
    layerId: const LayerId('l'),
    frameId: FrameId(frame),
  );

  BitmapTile tileOf(int x, int fill) => BitmapTile(
    coord: TileCoord(x: x, y: 0),
    size: size,
    pixels: BitmapTile.blank(coord: TileCoord(x: x, y: 0), size: size).pixels
      ..fillRange(0, BitmapTile.bytesFor(size), fill),
  );

  BitmapSurface surfaceOf(Iterable<BitmapTile> tiles) => BitmapSurface(
    canvasSize: canvas,
    tileSize: size,
    tiles: {for (final tile in tiles) tile.coord: tile},
  );

  group('a snapshot moves the tiles it ALONE holds', () {
    test('parking frees exactly the unshared tiles, and the shared ones '
        'keep their identity', () async {
      final shared = tileOf(0, 11);
      final mine = tileOf(1, 22);
      final snapshot = UndoSurfaceSnapshot(
        key: keyOf('f'),
        snapshot: surfaceOf([shared, mine]),
        sharedWith: surfaceOf([shared]),
      );

      expect(snapshot.residentBytes, BitmapTile.bytesFor(size));
      expect(await snapshot.park(), isTrue);

      // 🚨The claim a parked entry makes is about RAM, so it has to be
      // zero — not "the compressed size", which would let the budget grow
      // every time it spilled and oscillate.
      expect(snapshot.residentBytes, 0);
      expect(snapshot.isParked, isTrue);

      final back = snapshot.surfaceOver(surfaceOf([shared]))!;
      expect(back.tiles.length, 2);
      // ⛔The shared tile must come back as the SAME OBJECT: writing it
      // would have copied bytes that were not going anywhere, and reading
      // it back as a new object breaks the structural sharing the next
      // snapshot's weight depends on.
      expect(identical(back.tileAt(shared.coord), shared), isTrue);
      expect(back.tileAt(mine.coord), mine);
      expect(identical(back.tileAt(mine.coord), mine), isFalse);
    });

    /// 🚨A SNAPSHOT THAT SHARES EVERYTHING WRITES NO FILE — AND STILL HAS
    /// TO LET GO. It used to return early with its whole surface still
    /// referenced, on the grounds that every tile was "somebody else's".
    /// That is true when it is measured and false the moment the drawing
    /// moves past those tiles, and then this reference is the last one:
    /// the one snapshot the budget was certain cost nothing was the one
    /// that went on costing.
    test('a snapshot that shares everything writes no file, and lets go '
        'anyway', () async {
      final shared = tileOf(0, 11);
      final live = surfaceOf([shared]);
      final snapshot = UndoSurfaceSnapshot(
        key: keyOf('f'),
        snapshot: surfaceOf([shared]),
        sharedWith: live,
      );
      final before = _volatilePaths();

      expect(snapshot.residentBytes, 0);
      expect(await snapshot.park(), isTrue);

      expect(
        _volatilePaths().difference(before),
        isEmpty,
        reason: 'nothing of its own to write',
      );
      expect(
        snapshot.isParked,
        isTrue,
        reason: 'and yet it is holding no picture any more',
      );
      expect(
        snapshot.surfaceOver(null),
        isNull,
        reason: 'which is exactly what "let go" has to mean',
      );
      expect(
        identical(snapshot.surfaceOver(live)!.tileAt(shared.coord), shared),
        isTrue,
        reason: 'and the cel gives the same tile object back',
      );
    });

    test('coming back is byte-exact, pasteboard coords included', () async {
      final tile = BitmapTile(
        coord: TileCoord(x: -1, y: 0),
        size: size,
        pixels: tileOf(0, 0).pixels..[7] = 200,
      );
      final snapshot = UndoSurfaceSnapshot(
        key: keyOf('f'),
        snapshot: surfaceOf([tile]),
        sharedWith: null,
      );

      await snapshot.park();
      final back = snapshot
          .surfaceOver(null)!
          .tileAt(TileCoord(x: -1, y: 0))!;
      expect(back.pixels, tile.pixels);
    });

    test('a payload somebody deleted answers NULL, never a surface with '
        'holes in it', () async {
      final snapshot = UndoSurfaceSnapshot(
        key: keyOf('f'),
        snapshot: surfaceOf([tileOf(0, 5), tileOf(1, 6)]),
        sharedWith: surfaceOf([tileOf(0, 5)]), // different objects: none shared
      );
      final before = _volatilePaths();
      await snapshot.park();
      // The save's own delete step reaching into the wrong room looks
      // exactly like this — and painting the survivors over the cel would
      // erase the drawing this step exists to protect.
      for (final path in _volatilePaths().difference(before)) {
        File(path).deleteSync();
      }
      expect(snapshot.surfaceOver(null), isNull);
    });

    test('reading it back removes the file — a session of undos must not '
        'grow the room by a copy per press', () async {
      final snapshot = UndoSurfaceSnapshot(
        key: keyOf('f'),
        snapshot: surfaceOf([tileOf(0, 5)]),
        sharedWith: null,
      );
      final before = _volatilePaths();
      await snapshot.park();
      final mine = _volatilePaths().difference(before);
      expect(mine, hasLength(1));

      expect(snapshot.surfaceOver(null), isNotNull);

      expect(File(mine.single).existsSync(), isFalse);
      expect(snapshot.isParked, isFalse);
      expect(snapshot.residentBytes, BitmapTile.bytesFor(size));
    });

    test('dropping gives the room back without reading', () async {
      final snapshot = UndoSurfaceSnapshot(
        key: keyOf('f'),
        snapshot: surfaceOf([tileOf(0, 5)]),
        sharedWith: null,
      );
      final before = _volatilePaths();
      await snapshot.park();
      final mine = _volatilePaths().difference(before);
      UndoSurfaceSnapshot.dropAll([snapshot]);
      expect(mine.every((path) => !File(path).existsSync()), isTrue);
      expect(snapshot.surfaceOver(null), isNull);
    });
  });

  group('the pair bills one end and moves both', () {
    /// The pair AND the two surfaces it was measured against — reading a
    /// snapshot back needs the other end, because the tiles neither end
    /// owns are not held by either of them any more.
    ({UndoSurfacePair pair, BitmapSurface before, BitmapSurface after})
    pairOf() {
      final kept = tileOf(0, 1);
      final gone = tileOf(1, 2); // only the BEFORE has this one
      final made = tileOf(2, 3); // only the AFTER has this one
      final before = surfaceOf([kept, gone]);
      final after = surfaceOf([kept, made]);
      return (
        pair: UndoSurfacePair(key: keyOf('f'), before: before, after: after),
        before: before,
        after: after,
      );
    }

    test('🚨the bill is the BEFORE alone — the after is the next entry\'s '
        'before, and charging both counts a neighbour twice', () {
      // ⛔Not "conservative": the doubled figure is what the round before
      // this one removed, and it evicted real history with phantom bytes.
      expect(
        pairOf().pair.residentBytes(undone: false),
        BitmapTile.bytesFor(size),
      );
    });

    test('🚨but the park moves BOTH — a before let go on its own frees '
        'nothing, because the previous entry\'s after holds the same tiles',
        () async {
      final session = pairOf();
      expect(await session.pair.park(), isTrue);
      expect(session.pair.before.isParked, isTrue);
      expect(session.pair.after.isParked, isTrue);
    });

    test('and both come back', () async {
      final session = pairOf();
      await session.pair.park();
      final before = session.pair.before.surfaceOver(session.after)!;
      final after = session.pair.after.surfaceOver(session.before)!;
      expect(before.tiles.length, 2);
      expect(after.tiles.length, 2);
      expect(
        identical(
          before.tileAt(TileCoord(x: 0, y: 0)),
          after.tileAt(TileCoord(x: 0, y: 0)),
        ),
        isTrue,
        reason: 'the tile neither end owns was never written',
      );
    });

    /// 🚨THE PARK USED TO REPORT BYTES IT HAD NOT ACTUALLY LET GO OF. The
    /// shared tiles were held BY REFERENCE across it, so a tile the picture
    /// had moved past stayed in RAM through every entry below the one that
    /// owned it — 12.0 MiB of a 34.3 MiB bill on a measured 60-tap pass.
    /// A parked snapshot cannot hold one now, which is why reading it back
    /// needs the other end handed in.
    test('🚨a parked snapshot holds NO tile of its own — not even a shared '
        'one', () async {
      final session = pairOf();
      await session.pair.park();

      expect(
        session.pair.before.surfaceOver(null),
        isNull,
        reason: 'with nothing to take the shared tiles from, it refuses',
      );
      expect(
        session.pair.before.surfaceOver(surfaceOf([tileOf(9, 9)])),
        isNull,
        reason: 'a base that cannot answer for a shared coord is refused too',
      );
    });
  });

  group('the stack spills instead of deleting', () {
    test('an over-budget stack keeps every entry — the bytes move, the '
        'history stays', () async {
      final history = HistoryManager()..byteBudget = 1;
      for (var i = 0; i < 3; i++) {
        history.execute(_Parkable(bytes: 4096));
      }

      await history.drainSpilling();

      // ⛔This is the whole round: before it, two of these three entries
      // were simply gone and the user's third-from-last edit stopped
      // being undoable.
      expect(history.undoCount, 3);
      expect(history.retainedBytes, 4096, reason: 'the top stays resident');
    });

    test('the top entry is never parked — it is the one about to be '
        'pressed, and reading a payload back is synchronous', () async {
      final history = HistoryManager()..byteBudget = 1;
      final entries = [
        _Parkable(bytes: 4096),
        _Parkable(bytes: 4096),
      ];
      for (final entry in entries) {
        history.execute(entry);
      }

      await history.drainSpilling();

      expect(entries.first.parked, isTrue);
      expect(entries.last.parked, isFalse);
    });

    test('a room that refuses falls back to the old answer — deleting, and '
        'only then', () async {
      final history = HistoryManager()..byteBudget = 1;
      history
        ..execute(_Parkable(bytes: 4096, refuses: true))
        ..execute(_Parkable(bytes: 4096, refuses: true));

      await history.drainSpilling();

      expect(history.undoCount, 1, reason: 'the newest always survives');
    });

    test('🚨a stack whose deep end is PARKED is never deleted to free '
        'nothing', () async {
      final history = HistoryManager()..byteBudget = 1;
      // The top alone exceeds the budget, so the sweep can never get
      // under it — and every entry below it already reports zero.
      history
        ..execute(_Parkable(bytes: 4096))
        ..execute(_Parkable(bytes: 4096))
        ..execute(_Parkable(bytes: 4096));

      await history.drainSpilling();
      // A second pass: the first one stood down, and standing down used
      // to be followed by a shed that walked the whole parked run
      // collecting nothing and took the history with it.
      history.respondToMemoryPressure();
      await history.drainSpilling();

      expect(history.undoCount, 3);
    });

    test('an entry that leaves the stack gives the room its file back',
        () async {
      final history = HistoryManager(maxEntries: 2)..byteBudget = 1;
      final first = _Parkable(bytes: 4096);
      history
        ..execute(first)
        ..execute(_Parkable(bytes: 4096));
      await history.drainSpilling();
      expect(first.parked, isTrue, reason: 'no longer the top');

      history.execute(_Parkable(bytes: 4096)); // pushes `first` off the end

      expect(history.undoCount, 2);
      expect(first.dropped, isTrue);
    });

    test('a composite forwards the park — the entries the budget most '
        'needed to move are the ones that wrap a stroke', () async {
      final inner = _Parkable(bytes: 4096);
      final history = HistoryManager()..byteBudget = 1;
      history
        ..execute(
          CompositeCommand(description: 'wrapped', commands: [inner]),
        )
        ..execute(_Parkable(bytes: 4096));

      await history.drainSpilling();

      expect(inner.parked, isTrue);
    });
  });

  /// 🚨★★★**ONCE AN ENTRY IS UNDONE, THE OTHER HALF IS THE ONE IT HOLDS.**
  /// The bill named the BEFORE either way. Applied that is right — the cel
  /// is the after, so the before is what nobody else holds. Undone it is
  /// backwards: the cel has been put back to the before, and the AFTER is
  /// the half this entry alone is keeping alive.
  ///
  /// A stroke that only CREATED tiles is where it shows worst — its before
  /// owns nothing, so it billed nearly zero while holding every tile it had
  /// made. 🧪Measured over 40 such strokes: 11.5 MiB billed applied against
  /// 18.5 MiB actually pinned once undone.
  group('the bill follows the cel, not the entry', () {
    test('a stroke that only CREATED tiles owes nothing while applied, and '
        'owes them once undone', () {
      final blank = surfaceOf(const []);
      final drawn = surfaceOf([tileOf(0, 7)]);
      final pair = UndoSurfacePair(key: keyOf('f'), before: blank, after: drawn);

      expect(
        pair.residentBytes(undone: false),
        0,
        reason: 'the cel HAS these tiles — the entry adds nothing to them',
      );
      expect(
        pair.residentBytes(undone: true),
        BitmapTile.bytesFor(size),
        reason: '⛔the whole round: undone, the cel no longer has them and '
            'this entry is the only thing that does',
      );
    });

    test('and the ordinary stroke is the mirror of it', () {
      final was = surfaceOf([tileOf(0, 1)]);
      final now = surfaceOf([tileOf(0, 2)]);
      final pair = UndoSurfacePair(key: keyOf('f'), before: was, after: now);

      expect(pair.residentBytes(undone: false), BitmapTile.bytesFor(size));
      expect(pair.residentBytes(undone: true), BitmapTile.bytesFor(size));
    });

    test('🚨the stacks answer for their own side — the redo stack is the '
        'undone one', () {
      final history = HistoryManager();
      final blank = surfaceOf(const []);
      final drawn = surfaceOf([tileOf(0, 7)]);
      history.execute(
        _PairCommand(
          UndoSurfacePair(key: keyOf('f'), before: blank, after: drawn),
        ),
      );

      expect(
        history.retainedBytes,
        0,
        reason: 'applied: the cel holds the tiles, the entry adds nothing',
      );

      history.undo();

      expect(
        history.retainedBytes,
        BitmapTile.bytesFor(size),
        reason: '⛔and this is what the budget could not see before',
      );
    });
  });
}

/// What is in the run's 휘발성 room right now.
///
/// ⚠️Read off the ROOM, not off the snapshot: a payload's file name is a
/// counter and means nothing on purpose, so a test that could ask for it
/// would be asserting on the one thing that carries no promise. The cases
/// above diff this across a park instead.
Set<String> _volatilePaths() {
  final room = Directory(SessionScratch.volatileFolder());
  if (!room.existsSync()) {
    return const {};
  }
  return room.listSync().whereType<File>().map((file) => file.path).toSet();
}

class _Parkable implements Command, RetainedBytesCommand, ParkableCommand {
  _Parkable({required this.bytes, this.refuses = false});

  final int bytes;
  final bool refuses;
  bool parked = false;
  bool dropped = false;

  @override
  int estimatedRetainedBytes({required bool undone}) => parked ? 0 : bytes;

  @override
  String get description => 'parkable';

  @override
  void execute() {}

  @override
  void undo() {}

  @override
  Future<bool> parkPayload() async {
    if (refuses) {
      return false;
    }
    parked = true;
    return true;
  }

  @override
  void dropPayload() => dropped = true;
}

/// A history entry that holds nothing but a pair — the smallest thing that
/// can show which half the stacks are billing.
class _PairCommand implements Command, RetainedBytesCommand {
  _PairCommand(this.pair);

  final UndoSurfacePair pair;

  @override
  String get description => 'Pair';

  @override
  void execute() {}

  @override
  void undo() {}

  @override
  int estimatedRetainedBytes({required bool undone}) =>
      pair.residentBytes(undone: undone);
}
