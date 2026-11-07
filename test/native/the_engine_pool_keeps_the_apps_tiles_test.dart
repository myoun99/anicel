import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart';

import 'package:anicel/src/models/bitmap_surface.dart'
    show defaultCelTileSize;
import 'package:anicel/src/native/app_gpu_engine.dart';

/// The app stores its tiles in the engine's pool through the package's
/// Dart (screen-on-the-engine): the places come back in the order the tiles
/// went, a cel shares a page where it has room, a slot let go is free
/// once, and the pages nobody holds go back.
/// What lands in a slot is the engine's own tests' to pin
/// (rust/src/kernels/pool/tests.rs) — here, what Dart makes of its C ABI.
void main() {
  late GpuPool pool;
  final tiles = <Pointer<Uint8>>[];

  setUp(() => pool = GpuPool(appGpuEngine, 1 << 30));
  tearDown(() {
    pool.free();
    tiles
      ..forEach(calloc.free)
      ..clear();
  });

  List<Pointer<Uint8>> made(int count) {
    final made = [
      for (var tile = 0; tile < count; tile++) calloc<Uint8>(gpuTileBytes),
    ];
    tiles.addAll(made);
    return made;
  }

  test('the app opens one engine, however often it asks', () {
    expect(identical(appGpuEngine, appGpuEngine), isTrue);
  });

  // The store reads a tile's bytes at each pointer: an engine tile of other
  // bytes than the app's cel tile reads past each or leaves its end unread.
  test("the engine's tile is the app's cel tile", () {
    expect(gpuTileSide, defaultCelTileSize);
  });

  test('each tile stored lands in a slot of its own, a cel on a page with '
      'room', () {
    final a = pool.cel();
    final b = pool.cel();
    final first = pool.store(a, made(3));
    final second = pool.store(b, made(1));

    expect(first.toSet(), hasLength(3));
    expect({for (final tile in first) tile.page}, hasLength(1));
    expect(second.single.page, first.first.page);
    expect(first, isNot(contains(second.single)));
  });

  test('a pool given no bytes stores none', () {
    final none = GpuPool(appGpuEngine, 0);
    addTearDown(none.free);

    expect(none.store(none.cel(), made(2)), isEmpty);
  });

  test('a slot let go is free once, and handed out again', () {
    final cel = pool.cel();
    final [kept, let] = pool.store(cel, made(2));

    expect(pool.release(let), isTrue);
    expect(pool.release(let), isFalse);
    expect(pool.store(cel, made(1)), [let]);
    expect(pool.release(kept), isTrue);
  });

  test('the pages nobody holds go back till the pages hold the bytes asked',
      () {
    final [tile] = pool.store(pool.cel(), made(1));
    final page = pool.bytes;

    pool.giveBackPast(0);
    expect(pool.bytes, page, reason: 'a page held stays');
    pool.release(tile);
    pool.giveBackPast(page);
    expect(pool.bytes, page, reason: 'within the bytes asked');
    pool.giveBackPast(0);
    expect(pool.bytes, 0);
  });
}
