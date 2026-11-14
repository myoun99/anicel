import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart';

import 'package:anicel/src/native/app_gpu_engine.dart';

/// The app finds where its tiles hold ink through the package's Dart
/// (connection round 2, 잉크 상자): what it stored on the pool comes back as
/// each walked tile's place and box, a tile of no ink as none, and what the
/// C entry refuses throws why. That the box is the scan's is the crate's to
/// pin (rust/src/kernels/cel_pixel/abi/tests.rs) — here, what Dart hands it
/// and reads back.
void main() {
  late GpuPool pool;
  late GpuInk ink;
  final held = <Pointer<Uint8>>[];

  setUpAll(() => ink = GpuInk(appGpuEngine));
  tearDownAll(() => ink.free());
  setUp(() => pool = GpuPool(appGpuEngine, 1 << 30));
  tearDown(() {
    pool.free();
    held
      ..forEach(calloc.free)
      ..clear();
  });

  /// A tile each of [inked], its pixels there an opaque red and none
  /// elsewhere, stored under a cel of their own.
  List<GpuTile> stored(List<List<(int, int)>> inked) {
    final side = gpuTileSide;
    final tiles = [for (final _ in inked) calloc<Uint8>(gpuTileBytes)];
    held.addAll(tiles);
    for (var tile = 0; tile < inked.length; tile++) {
      final words = tiles[tile].cast<Uint32>().asTypedList(side * side);
      for (final (x, y) in inked[tile]) {
        words[y * side + x] = 0xFF0000FF;
      }
    }
    return pool.store(pool.cel(), tiles);
  }

  // A 3 × 2 cel from (−2, −1), its second tile missing: each box unlike the
  // others and unlike itself turned, and one tile stored with no ink.
  test('each walked tile comes back where it is, with its box', () {
    final [a, b, empty, d, e] = stored([
      [(3, 5), (90, 40)],
      [(120, 2)],
      [],
      [(0, 127), (7, 64)],
      [(60, 61)],
    ]);

    expect(ink.run(pool, -2, -1, 3, 2, [a, null, b, empty, d, e]), [
      (column: -2, row: -1, box: (left: 3, top: 5, right: 91, bottom: 41)),
      (column: 0, row: -1, box: (left: 120, top: 2, right: 121, bottom: 3)),
      (column: -2, row: 0, box: null),
      (column: -1, row: 0, box: (left: 0, top: 64, right: 8, bottom: 128)),
      (column: 0, row: 0, box: (left: 60, top: 61, right: 61, bottom: 62)),
    ]);
  });

  test('a cel of no tiles walks none', () {
    expect(ink.run(pool, 0, 0, 2, 1, [null, null]), isEmpty);
  });

  test('what the C entry refuses throws why', () {
    final [tile] = stored([
      [(1, 1)],
    ]);

    expect(
      () => ink.run(pool, 0, 0, 2, 1, [tile, (page: 1, slot: 0)]),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('names page 1 of a pool of 1'),
        ),
      ),
    );
    expect(() => ink.run(pool, 0, 0, 2, 1, [tile]), throwsArgumentError);
  });
}
