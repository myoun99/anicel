import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/canvas_selection_region.dart';
import 'package:anicel/src/services/canvas_selection_shape.dart';
import 'package:anicel/src/services/command.dart';
import 'package:anicel/src/services/history_manager.dart';
import 'package:flutter_test/flutter_test.dart';

/// 🚨WHAT AN UNDO ENTRY WEIGHS — the law five commands used to answer
/// five ways, three of them wrong.
///
/// Measured 2026-09-07 before this landed: the byte budget never fired
/// once, because a selection move reported the STAMP rectangle (32 KB
/// against 64 MiB held) and a composite reported nothing. The only thing
/// bounding undo pixels was the entry count, and 200 full-canvas
/// transforms is 12.5 GiB.
///
/// Every case here is paired with the mutation that must turn it red —
/// a test that only proves the code runs proves nothing.
class _Weighted implements Command, RetainedBytesCommand {
  _Weighted(this._bytes);

  final int _bytes;

  @override
  String get description => 'weighted';

  @override
  void execute() {}

  @override
  void undo() {}

  @override
  int get estimatedRetainedBytes => _bytes;
}

BitmapSurface _surface({
  required int tiles,
  Map<TileCoord, BitmapTile> reuse = const {},
}) {
  const size = 256;
  final map = <TileCoord, BitmapTile>{};
  for (var i = 0; i < tiles; i++) {
    final coord = TileCoord(x: i, y: 0);
    map[coord] =
        reuse[coord] ?? BitmapTile.blank(coord: coord, size: size);
  }
  return BitmapSurface(
    canvasSize: const CanvasSize(width: 4000, height: 4000),
    tiles: map,
  );
}

void main() {
  group('the law: only tiles the live surface no longer holds', () {
    test('a snapshot that shares every tile with live weighs nothing', () {
      final live = _surface(tiles: 4);
      final snapshot = _surface(tiles: 4, reuse: live.tiles);
      // ⛔Not "conservative": counting the whole snapshot here is what let
      // one top-left grow evict the real history with phantom bytes.
      expect(snapshot.bytesNotSharedWith(live), 0);
    });

    test('only the unshared tiles are counted', () {
      final live = _surface(tiles: 4);
      final snapshot = _surface(tiles: 4); // all fresh objects
      expect(
        snapshot.bytesNotSharedWith(live),
        4 * BitmapTile.bytesFor(256),
      );
    });

    test('a null live surface leaves the whole snapshot ours', () {
      final snapshot = _surface(tiles: 3);
      expect(
        snapshot.bytesNotSharedWith(null),
        3 * BitmapTile.bytesFor(256),
      );
    });

    test('one 4000² full-canvas snapshot is 64 MiB, as measured', () {
      // 16×16 tiles of 256², four bytes a pixel.
      expect(256 * BitmapTile.bytesFor(256), 64 * 1024 * 1024);
    });
  });

  group('wrapping must not hide weight', () {
    test('CompositeCommand reports the sum of its children', () {
      final composite = CompositeCommand(
        description: 'two things',
        commands: [_Weighted(10), _Weighted(32), _Weighted(0)],
      );
      expect(composite, isA<RetainedBytesCommand>());
      expect((composite as RetainedBytesCommand).estimatedRetainedBytes, 42);
    });

    test('a composite on the stack is visible to the budget', () {
      final history = HistoryManager();
      history.execute(
        CompositeCommand(
          description: 'wrapped stroke',
          commands: [_Weighted(1024)],
        ),
      );
      // Was 0 before: ~30 call sites build one, and one of them wraps a
      // brush stroke.
      expect(history.retainedBytes, 1024);
    });
  });

  group('the budget sees both stacks', () {
    test('undoing does not make the bytes disappear', () {
      final history = HistoryManager()..execute(_Weighted(2048));
      expect(history.retainedBytes, 2048);
      history.undo();
      expect(history.undoCount, 0);
      expect(history.redoCount, 1);
      // 🚨The entry still holds every byte it held; only the stack it
      // sits on changed.
      expect(history.retainedBytes, 2048);
    });

    test('pressure frees the bytes an undone entry still holds', () {
      const entry = 200 * 1024 * 1024; // two of these blow the 64MB target
      final history = HistoryManager()
        ..execute(_Weighted(entry))
        ..execute(_Weighted(entry));
      history.undo(); // one on each stack
      expect(history.retainedBytes, 2 * entry);

      history.respondToMemoryPressure();

      // 🚨Before both stacks counted, the undone 200MB was invisible: the
      // sweep saw one 200MB entry, kept it (newest survives) and reported
      // itself done while 400MB was still held. On iOS the warning is the
      // last thing before the kill.
      expect(history.redoCount, 0);
      expect(history.retainedBytes, entry);
    });

    test('redo sheds before undo does', () {
      final history = HistoryManager()..byteBudget = 8192;
      history
        ..execute(_Weighted(4096))
        ..execute(_Weighted(4096));
      history.undo(); // one on each stack
      expect(history.undoCount, 1);
      expect(history.redoCount, 1);
      history.byteBudget = 4096;
      history.execute(_Weighted(0)); // pushes, clearing redo, then trims
      expect(history.retainedBytes, lessThanOrEqualTo(4096));
    });

    test('the newest undo entry always survives the byte sweep', () {
      final history = HistoryManager()..byteBudget = 1;
      history.execute(_Weighted(64 * 1024 * 1024));
      expect(history.undoCount, 1);
      expect(history.canUndo, isTrue);
    });
  });

  group('the budget scales to the machine', () {
    test('RAM/8, and never above the old fixed value', () {
      expect(
        deviceScaledUndoByteBudget(physicalMemoryBytes: 4 * 1024 * 1024 * 1024),
        512 * 1024 * 1024,
      );
      expect(
        deviceScaledUndoByteBudget(
          physicalMemoryBytes: 16 * 1024 * 1024 * 1024,
        ),
        HistoryManager.retainedByteBudget,
      );
    });

    test('a small machine gets less, down to two full-canvas transforms', () {
      expect(
        deviceScaledUndoByteBudget(physicalMemoryBytes: 2 * 1024 * 1024 * 1024),
        256 * 1024 * 1024,
      );
      expect(
        deviceScaledUndoByteBudget(physicalMemoryBytes: 512 * 1024 * 1024),
        128 * 1024 * 1024,
      );
    });

    test('unknown RAM keeps the old fixed value byte-for-byte', () {
      expect(
        deviceScaledUndoByteBudget(physicalMemoryBytes: null),
        HistoryManager.retainedByteBudget,
      );
      expect(
        deviceScaledUndoByteBudget(physicalMemoryBytes: 0),
        HistoryManager.retainedByteBudget,
      );
    });
  });

  group('a selection entry weighs its contour memo', () {
    CanvasSelectionRegion regionOf(double side) =>
        CanvasSelectionRegion.shape(
          CanvasSelectionShape.rect(
            left: 0,
            top: 0,
            right: side,
            bottom: side,
          ),
        );

    test('nothing until someone asks for the contours', () {
      expect(regionOf(64).estimatedRetainedBytes, 0);
    });

    test('the memo is what the entry actually holds', () {
      final region = regionOf(64);
      expect(region.pixelOutlineContours, isNotEmpty);
      expect(region.estimatedRetainedBytes, greaterThan(0));
    });
  });
}
