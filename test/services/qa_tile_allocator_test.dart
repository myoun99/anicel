import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/native/qa_engine_abi.dart';
import 'package:anicel/src/native/qa_native_engine.dart';

/// R20-E1: the C tile free-list allocator. Freed tile blocks must PARK on
/// exact-size lists and be handed straight back — adoption (R19-Z) sends
/// commit scratch out as finished tiles, so without recycling every
/// full-canvas fill paid ~1024 fresh mallocs. Skips (loudly) when no
/// locally built binary is found.
void main() {
  final dllPath =
      '${Directory.current.path}\\build\\native_standalone\\Release\\qa_engine.dll';
  final available = File(dllPath).existsSync();

  setUp(() {
    QaNativeEngine.debugResetForTests();
    debugQaEngineLibraryPathOverride = dllPath;
    QaNativeEngine.debugForceDartFallback = false;
  });

  tearDown(() {
    QaNativeEngine.debugResetForTests();
    debugQaEngineLibraryPathOverride = null;
    QaNativeEngine.debugForceDartFallback = false;
  });

  void requireEngine() {
    if (!available) {
      markTestSkipped(
        'qa_engine.dll not built — run: cmake -S packages/qa_native/src -B '
        'build/native_standalone && cmake --build build/native_standalone '
        '--config Release',
      );
    }
  }

  test('free parks the block and the next same-size alloc reuses it', () {
    requireEngine();
    if (!available) return;
    final engine = QaNativeEngine.instance!;

    // A distinctive size so no other machinery races this bucket.
    const size = 77_776;
    final before = engine.debugTilePoolCachedBytes();

    final first = engine.tileAlloc(size);
    final view = first.asTypedList(size);
    view[0] = 0xAB;
    view[size - 1] = 0xCD;
    expect(view[0], 0xAB);
    expect(view[size - 1], 0xCD);

    engine.tileFree(first);
    expect(
      engine.debugTilePoolCachedBytes(),
      before + size,
      reason: 'the freed block must PARK, not free()',
    );

    final second = engine.tileAlloc(size);
    expect(
      second.address,
      first.address,
      reason: 'exact-size reuse must hand the parked block back (LIFO)',
    );
    expect(engine.debugTilePoolCachedBytes(), before);
    engine.tileFree(second);
  });

  test('different sizes park independently', () {
    requireEngine();
    if (!available) return;
    final engine = QaNativeEngine.instance!;

    const sizeA = 55_552;
    const sizeB = 66_664;
    final a = engine.tileAlloc(sizeA);
    final b = engine.tileAlloc(sizeB);
    engine.tileFree(a);
    engine.tileFree(b);

    // Reuse must match by exact size, not allocation order.
    final b2 = engine.tileAlloc(sizeB);
    final a2 = engine.tileAlloc(sizeA);
    expect(b2.address, b.address);
    expect(a2.address, a.address);
    engine.tileFree(a2);
    engine.tileFree(b2);
  });

  test('acquireTileBuffer recycles through the C free list', () {
    requireEngine();
    if (!available) return;
    final engine = QaNativeEngine.instance!;

    const byteLength = 44_440;
    final buffer = engine.acquireTileBuffer(byteLength, zeroed: true);
    expect(buffer.view.every((byte) => byte == 0), isTrue);
    buffer.view.fillRange(0, byteLength, 7);
    engine.releaseTileBuffer(buffer);

    // Same block comes back; zeroed=true must scrub the stale bytes.
    final again = engine.acquireTileBuffer(byteLength, zeroed: true);
    expect(again.pointer.address, buffer.pointer.address);
    expect(again.view.every((byte) => byte == 0), isTrue);
    engine.releaseTileBuffer(again);
  });

  test('BitmapTile allocates from the engine and round-trips bytes', () {
    requireEngine();
    if (!available) return;
    expect(QaNativeEngine.instance, isNotNull);

    const size = 16;
    final pixels = Uint8List(size * size * BitmapTile.bytesPerPixel);
    for (var i = 0; i < pixels.length; i += 1) {
      pixels[i] = i & 0xFF;
    }
    final tile = BitmapTile(
      coord: TileCoord(x: 1, y: 2),
      size: size,
      pixels: pixels,
    );
    expect(tile.pixels, pixels);

    final blank = BitmapTile.blank(coord: TileCoord(x: 0, y: 0), size: 8);
    expect(blank.isFullyTransparent, isTrue);
  });
}
