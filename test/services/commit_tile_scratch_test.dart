import 'dart:ffi';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/native_engine_path.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/native/qa_engine_abi.dart';
import 'package:anicel/src/native/qa_native_engine.dart';
import 'package:anicel/src/services/commit_tile_scratch.dart';

/// The commit scratch (round 8 of the audit): acquire a tile's bytes to
/// blend into, then either ADOPT the buffer as the finished tile or give
/// it back. Two implementations chosen by type — native pooled memory
/// when the engine is loaded, Dart byte lists otherwise — and both keep
/// the same three promises pinned here.
void main() {
  const canvasSize = CanvasSize(width: 8, height: 8);
  const tileSize = 4;
  const byteLength = tileSize * tileSize * 4;

  BitmapSurface surfaceWithTile(TileCoord coord, int fill) => BitmapSurface(
    canvasSize: canvasSize,
    tileSize: tileSize,
    tiles: {
      coord: BitmapTile(
        size: tileSize,
        pixels: Uint8List(byteLength)..fillRange(0, byteLength, fill),
      ),
    },
  );

  void pinScratchLaws(CommitTileScratch Function(BitmapSurface) build) {
    final present = TileCoord(x: 1, y: 1);
    final missing = TileCoord(x: 0, y: 0);

    test('a MISSING tile stages zeroed bytes', () {
      final scratch = build(surfaceWithTile(present, 0x7F));
      expect(scratch.bufferFor(missing), everyElement(0));
      scratch.releaseUnfinished();
    });

    test('an existing tile stages its bytes as a COPY the tile does not '
        'see', () {
      final surface = surfaceWithTile(present, 0x7F);
      final scratch = build(surface);
      final buffer = scratch.bufferFor(present);
      expect(buffer, everyElement(0x7F));
      buffer[0] = 0x11;
      expect(
        surface.tileAt(present)!.pixels[0],
        0x7F,
        reason: 'tiles are immutable; the scratch is the mutable copy',
      );
      scratch.releaseUnfinished();
    });

    test('the same coordinate stages ONCE: a second dab sees the first '
        'dab\'s bytes', () {
      final scratch = build(surfaceWithTile(present, 0));
      scratch.bufferFor(present)[5] = 0xAB;
      expect(scratch.bufferFor(present)[5], 0xAB);
      scratch.releaseUnfinished();
    });

    test('finish hands back a tile carrying the blended bytes at the '
        'coordinate', () {
      final scratch = build(surfaceWithTile(present, 0));
      final buffer = scratch.bufferFor(present);
      buffer.fillRange(0, byteLength, 0xC3);
      scratch.bufferFor(missing);
      final tile = scratch.finish(present);
      scratch.releaseUnfinished();
  
      expect(tile.size, tileSize);
      expect(tile.pixels, everyElement(0xC3));
    });

    // ABI 40: a dab piles up on the tile's 16-bit plane (`qa_dab_store`).
    test('the 16-bit plane starts as the bytes WIDENED — every value reads '
        'back as exactly its byte', () {
      final scratch = build(surfaceWithTile(present, 0x7F));
      final planes = scratch.planesFor(present);
      expect(planes.bytes, everyElement(0x7F));
      expect(planes.wide, everyElement(0x7F * 257));
      scratch.releaseUnfinished();
    });

    test('the plane is not widened again between dabs — a dab reads the '
        'plane the dab before it left', () {
      final scratch = build(surfaceWithTile(present, 0));
      scratch.planesFor(present).wide[0] = 1234;
      expect(scratch.planesFor(present).wide[0], 1234);
      scratch.releaseUnfinished();
    });

    test('a write of the bytes alone makes the plane stale — the next dab '
        'widens what the bytes hold now', () {
      // The stamp blitter and the stroke blend write bytes only: a plane
      // that missed one would pile the next dab over the old picture.
      final scratch = build(surfaceWithTile(present, 0));
      scratch.planesFor(present).wide[0] = 1234;
      scratch.bufferFor(present)[0] = 0x40;
      expect(scratch.planesFor(present).wide[0], 0x40 * 257);
      scratch.releaseUnfinished();
    });
  }

  group('DartCommitScratch', () {
    pinScratchLaws(DartCommitScratch.new);
  });

  group('NativeCommitScratch', () {
    final dllPath = nativeEngineLibraryPathOrNull();
    late QaNativeEngine engine;

    setUp(() {
      QaNativeEngine.debugResetForTests();
      debugQaEngineLibraryPathOverride = dllPath;
      QaNativeEngine.debugForceDartFallback = false;
      final loaded = QaNativeEngine.instance;
      if (loaded == null) {
        if (nativeEngineRequired) {
          fail(nativeEngineMissingSkipReason);
        }
        markTestSkipped(nativeEngineMissingSkipReason);
        return;
      }
      engine = loaded;
    });

    tearDown(() {
      QaNativeEngine.debugResetForTests();
      debugQaEngineLibraryPathOverride = null;
      QaNativeEngine.debugForceDartFallback = false;
    });

    if (dllPath == null) {
      test(
        'needs the engine',
        () => markTestSkipped(nativeEngineMissingSkipReason),
      );
      return;
    }

    pinScratchLaws((surface) => NativeCommitScratch(engine, surface));

    test('releaseUnfinished returns exactly the UNFINISHED buffers to the '
        'pool — a finished one is the tile\'s now', () {
      final a = TileCoord(x: 0, y: 0);
      final b = TileCoord(x: 1, y: 0);
      final scratch = NativeCommitScratch(engine, surfaceWithTile(a, 0x10));
      scratch.bufferFor(a);
      scratch.bufferFor(b);
      final cachedWhileStaged = engine.tilePoolParkedBytes;
      final tile = scratch.finish(a);
      scratch.releaseUnfinished();
      expect(
        engine.tilePoolParkedBytes,
        cachedWhileStaged + byteLength,
        reason: 'one buffer (b) went back; a was adopted by the tile',
      );
      expect(tile.pixels, everyElement(0x10));
    });

    test('the span pointer and the Dart view are the SAME bytes', () {
      final coord = TileCoord(x: 0, y: 0);
      final scratch = NativeCommitScratch(engine, surfaceWithTile(coord, 0));
      scratch.bufferFor(coord)[3] = 0x5A;
      expect(scratch.pointerFor(coord).asTypedList(byteLength)[3], 0x5A);
      scratch.releaseUnfinished();
    });

    test('the dab batch\'s two pointers and the Dart planes are the SAME '
        'memory', () {
      final coord = TileCoord(x: 0, y: 0);
      final scratch = NativeCommitScratch(engine, surfaceWithTile(coord, 0));
      final planes = scratch.planesFor(coord);
      planes.bytes[3] = 0x5A;
      planes.wide[3] = 0xBEEF;
      final pointers = scratch.pointersFor(coord);
      expect(pointers.pixels.asTypedList(byteLength)[3], 0x5A);
      expect(pointers.wide.asTypedList(byteLength)[3], 0xBEEF);
      scratch.releaseUnfinished();
    });

    test('a zeroed buffer is zero even when the pool hands back a used '
        'one', () {
      // `qa_zero_bytes` (ABI 40): the pool parks a released block and hands
      // that same block, dirty, to the next acquire of its size.
      final dirty = engine.acquireTileBuffer(byteLength, zeroed: false);
      dirty.view.fillRange(0, byteLength, 0xAB);
      engine.releaseTileBuffer(dirty);
      final again = engine.acquireTileBuffer(byteLength, zeroed: true);
      expect(
        again.pointer.address,
        dirty.pointer.address,
        reason: 'premise: the pool handed the used block back',
      );
      expect(again.view, everyElement(0));
      engine.releaseTileBuffer(again);
    });

    test('finish gives the plane back to the pool — the bytes are the tile '
        'now, the plane is nobody\'s', () {
      final coord = TileCoord(x: 0, y: 0);
      final scratch = NativeCommitScratch(engine, surfaceWithTile(coord, 0));
      scratch.planesFor(coord);
      final parked = engine.tilePoolParkedBytes;
      scratch.finish(coord);
      expect(engine.tilePoolParkedBytes, parked + byteLength * 2);
      scratch.releaseUnfinished();
    });
  });
}
