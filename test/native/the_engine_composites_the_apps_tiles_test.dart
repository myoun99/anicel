import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart';

import 'package:anicel/src/native/app_gpu_engine.dart';

/// The app composites its tiles through the package's Dart
/// (screen-on-the-engine 2a): what it stored comes back through a row
/// copied over nothing, a plan shown onto a surface lays what a run puts,
/// and each step's numbers reach the step they name. That a plan built
/// call by call is the plan built in Rust is the crate's to pin
/// (rust/src/kernels/composite/abi/tests.rs) — here, what Dart hands it.
void main() {
  late GpuPool pool;
  late GpuComposite composite;
  final held = <Pointer<Uint8>>[];
  const all = (-1 << 31, -1 << 31, (1 << 31) - 1, (1 << 31) - 1);
  const normal = 28;
  const identity = [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0];

  setUpAll(() => composite = GpuComposite(appGpuEngine));
  tearDownAll(() => composite.free());
  setUp(() => pool = GpuPool(appGpuEngine, 1 << 30));
  tearDown(() {
    pool.free();
    held
      ..forEach(calloc.free)
      ..clear();
  });

  /// Opaque tiles of bytes of their own, stored under a cel of their own.
  (List<GpuTile>, Uint8List) stored(int count) {
    final bytes = Uint8List(count * gpuTileBytes);
    for (var at = 0; at < bytes.length; at++) {
      bytes[at] = at % 4 == 3 ? 255 : (at * 2654435761 >> 13) & 255;
    }
    final tiles = [
      for (var tile = 0; tile < count; tile++)
        calloc<Uint8>(gpuTileBytes)
          ..asTypedList(gpuTileBytes).setAll(
            0,
            bytes.sublist(tile * gpuTileBytes, (tile + 1) * gpuTileBytes),
          ),
    ];
    held.addAll(tiles);
    return (pool.store(pool.cel(), tiles), bytes);
  }

  Uint8List ran(GpuPlan plan, List<(int, int)> tiles) {
    final out = composite.run(pool, plan, tiles, all);
    addTearDown(out.free);
    return out.read();
  }

  /// The pixel at ([x], [y]) of [bytes] a run put over output [tiles].
  List<int> pixel(Uint8List bytes, List<(int, int)> tiles, int x, int y) {
    final side = gpuTileSide;
    final tile = tiles.indexOf((x ~/ side, y ~/ side));
    final at = (tile * side * side + (y % side) * side + x % side) * 4;
    return bytes.sublist(at, at + 4);
  }

  test('a row copied over nothing lays back the bytes stored', () {
    final (places, bytes) = stored(3);
    final plan = GpuPlan();
    addTearDown(plan.free);
    final set = plan.set(0, 0, 3, 1, places);
    expect(
      plan.row(
        set: set,
        inverse: identity,
        sampling: GpuSampling.blend,
        columns: 3 * gpuTileSide,
        rows: gpuTileSide,
        mode: normal,
      ),
      isTrue,
    );

    expect(ran(plan, [(0, 0), (1, 0), (2, 0)]), bytes);
  });

  test('a plan shown onto a surface lays what a run puts', () {
    final side = gpuTileSide;
    final (places, _) = stored(2);
    final plan = GpuPlan();
    addTearDown(plan.free);
    plan.row(
      set: plan.set(0, 0, 2, 1, places),
      inverse: identity,
      sampling: GpuSampling.nearest,
      columns: 2 * side,
      rows: side,
      mode: normal,
    );
    final tiles = [(0, 0), (1, 0)];
    final put = ran(plan, tiles);
    final rowByRow = Uint8List(put.length);
    for (var y = 0; y < side; y++) {
      for (var x = 0; x < 2 * side; x++) {
        rowByRow.setAll((y * 2 * side + x) * 4, pixel(put, tiles, x, y));
      }
    }
    final surface = appGpuEngine.surface(2 * side, side, bgra: false);
    addTearDown(surface.free);

    expect(composite.show(pool, plan, surface, (0, 0, 2 * side, side)), 1);
    expect(surface.fingerprint(), fingerprintBytes(rowByRow));
  });

  test('a pose that lands nothing is left out', () {
    final plan = GpuPlan();
    addTearDown(plan.free);

    expect(
      plan.row(
        set: plan.set(0, 0, 1, 1, [null]),
        inverse: const [1, 0, 0, 0, 1, 0, 0, 0, -1],
        sampling: GpuSampling.blend,
        columns: gpuTileSide,
        rows: gpuTileSide,
        mode: normal,
      ),
      isFalse,
    );
  });

  test("a solid, a folder's close and its matrix each take their own", () {
    final plan = GpuPlan();
    addTearDown(plan.free);
    // Red into green: the matrix's first row reads nothing, its second
    // lays a whole 255.
    final green = plan.matrix(const [
      0, 0, 0, 0, 0, //
      0, 0, 0, 0, 255,
      0, 0, 1, 0, 0,
      0, 0, 0, 1, 0,
    ]);
    plan
      ..solid(0xFF0000FF, 0, 0, 10, 6)
      ..open()
      ..solid(0xFF0000FF, 20, 0, 30, 10)
      ..close(mode: normal, opacity: 32768, matrix: green);
    final tiles = [(0, 0)];
    final put = ran(plan, tiles);

    expect(pixel(put, tiles, 9, 5), [255, 0, 0, 255]);
    expect(pixel(put, tiles, 5, 6), [0, 0, 0, 0]);
    final closed = pixel(put, tiles, 25, 5);
    expect(closed.sublist(0, 3), [0, 255, 0]);
    expect(closed[3], inInclusiveRange(127, 128));
    expect(pixel(put, tiles, 30, 5), [0, 0, 0, 0]);
  });
}
