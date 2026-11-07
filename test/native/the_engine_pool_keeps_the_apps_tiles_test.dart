import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart';

import 'package:anicel/src/native/app_gpu_engine.dart';

/// The app stores its tiles in the engine's pool through the package's
/// Dart (screen-on-the-engine): the places come back in the order the tiles
/// went, a cel keeps to pages of its own, and a slot let go is free once.
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

  test('each tile stored lands in a slot of its own, a cel to its pages', () {
    final a = pool.cel();
    final b = pool.cel();
    final first = pool.store(a, made(3));
    final second = pool.store(b, made(1));

    expect(first.toSet(), hasLength(3));
    expect({for (final tile in first) tile.page}, hasLength(1));
    expect(second.single.page, isNot(first.first.page));
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
}
