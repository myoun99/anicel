import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart';

import 'package:anicel/src/models/separable_blend_mode.dart';
import 'package:anicel/src/native/app_gpu_engine.dart';
import 'package:anicel/src/services/brush_stroke_blend.dart';

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
  // blend.wgsl's BLEND_NORMAL: the brush's table has no normal of its own.
  const normal = 28;
  final multiply = separableBlendModeNativeId(SeparableBlendMode.multiply);
  const identity = [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0];
  const nothing = [0, 0, 0, 0];

  setUpAll(() => composite = GpuComposite(appGpuEngine));
  tearDownAll(() => composite.free());
  setUp(() => pool = GpuPool(appGpuEngine, 1 << 30));
  tearDown(() {
    pool.free();
    held
      ..forEach(calloc.free)
      ..clear();
  });

  /// [bytes], a tile's after a tile's, stored under a cel of their own.
  List<GpuTile> storedOf(Uint8List bytes) {
    final tiles = [
      for (var at = 0; at < bytes.length; at += gpuTileBytes)
        calloc<Uint8>(gpuTileBytes)
          ..asTypedList(gpuTileBytes).setAll(
            0,
            bytes.sublist(at, at + gpuTileBytes),
          ),
    ];
    held.addAll(tiles);
    return pool.store(pool.cel(), tiles);
  }

  /// [count] opaque tiles of bytes no two neighbours share.
  Uint8List noise(int count) {
    final bytes = Uint8List(count * gpuTileBytes);
    for (var at = 0; at < bytes.length; at++) {
      bytes[at] = at % 4 == 3 ? 255 : (at * 2654435761 >> 13) & 255;
    }
    return bytes;
  }

  Uint8List ran(
    GpuPlan plan,
    List<(int, int)> tiles, [
    (int, int, int, int) extent = all,
  ]) {
    final out = composite.run(pool, plan, tiles, extent);
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

  /// A plan of one row: [set] over a tile row of [columns] tiles.
  GpuPlan oneRow(
    List<GpuTile?> set, {
    List<double> inverse = identity,
    GpuSampling sampling = GpuSampling.blend,
    double radiusFloor = 1,
    List<double>? matrix,
    int? mode,
  }) {
    final plan = GpuPlan();
    addTearDown(plan.free);
    final added = plan.row(
      set: plan.set(0, 0, set.length, 1, set),
      inverse: inverse,
      sampling: sampling,
      columns: set.length * gpuTileSide,
      rows: gpuTileSide,
      mode: mode ?? normal,
      matrix: matrix == null ? null : plan.matrix(matrix),
      radiusFloor: radiusFloor,
    );
    expect(added, isTrue);
    return plan;
  }

  test('a row copied over nothing lays back the bytes stored', () {
    final bytes = noise(2);
    final [first, second] = storedOf(bytes);
    final plan = oneRow([first, null, second]);
    final put = ran(plan, [(0, 0), (1, 0), (2, 0)]);

    expect(put.sublist(0, gpuTileBytes), bytes.sublist(0, gpuTileBytes));
    expect(
      put.sublist(gpuTileBytes, 2 * gpuTileBytes),
      Uint8List(gpuTileBytes),
    );
    expect(put.sublist(2 * gpuTileBytes), bytes.sublist(gpuTileBytes));
  });

  // A quarter pixel to the left: a pixel's centre lands in the same pixel
  // and that pixel covers most of its preimage, so nearest and pick lay
  // back the bytes; the tent mixes the next pixel in.
  const quarter = [1.0, 0.0, 0.25, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0];

  test('each sampling samples by its own', () {
    final bytes = noise(1);
    final tiles = storedOf(bytes);
    Uint8List sampled(GpuSampling sampling) =>
        ran(oneRow(tiles, inverse: quarter, sampling: sampling), [(0, 0)]);

    expect(sampled(GpuSampling.nearest), bytes);
    expect(sampled(GpuSampling.pick), bytes);
    expect(sampled(GpuSampling.blend), isNot(bytes));
  });

  // Off a whole-pixel move: R1 copies one, in any mode, by any floor.
  test("a row's radius floor widens its tent", () {
    final tiles = storedOf(noise(1));
    Uint8List floored(double radius) =>
        ran(oneRow(tiles, inverse: quarter, radiusFloor: radius), [(0, 0)]);

    expect(floored(3), isNot(floored(1)));
  });

  // Red into green: the matrix's first row reads nothing, its second lays
  // a whole 255.
  const green = <double>[
    0, 0, 0, 0, 0, //
    0, 0, 0, 0, 255,
    0, 0, 1, 0, 0,
    0, 0, 0, 1, 0,
  ];

  test("a row's matrix runs on what it lays", () {
    final red = Uint32List(gpuTileSide * gpuTileSide)
      ..fillRange(0, gpuTileSide * gpuTileSide, 0xFF0000FF);
    final tiles = storedOf(red.buffer.asUint8List());
    final put = ran(oneRow(tiles, matrix: green), [(0, 0)]);

    expect(pixel(put, [(0, 0)], 7, 7), [0, 255, 0, 255]);
  });

  test('a plan shown onto a surface lays what a run puts', () {
    final side = gpuTileSide;
    final plan = oneRow(storedOf(noise(2)), sampling: GpuSampling.nearest);
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
    final matrix = plan.matrix(green);
    plan
      ..solid(0xFF0000FF, 0, 0, 10, 6)
      ..open()
      ..solid(0xFF0000FF, 20, 0, 30, 10)
      ..close(mode: normal, opacity: 32768, matrix: matrix);
    final tiles = [(0, 0)];
    final put = ran(plan, tiles);

    expect(pixel(put, tiles, 9, 5), [255, 0, 0, 255]);
    expect(pixel(put, tiles, 5, 6), nothing);
    final closed = pixel(put, tiles, 25, 5);
    expect(closed.sublist(0, 3), [0, 255, 0]);
    expect(closed[3], inInclusiveRange(127, 128));
    expect(pixel(put, tiles, 30, 5), nothing);

    final edged = ran(plan, tiles, (0, 0, 9, 40));
    expect(pixel(edged, tiles, 8, 5), [255, 0, 0, 255]);
    expect(pixel(edged, tiles, 9, 5), nothing);
  });

  // White multiplied onto a half-there grey base, as the crate's own clip
  // test lays it (composite/tests.rs): over the base made opaque it
  // multiplies the grey and srcATop gives it the base's alpha; opened
  // plainly it multiplies nothing and lands white. Where the base is not,
  // both are nothing.
  test('a clip reads its base made opaque where its scope is', () {
    final side = gpuTileSide;
    final white = storedOf(
      Uint8List(gpuTileBytes)..fillRange(0, gpuTileBytes, 255),
    );
    Uint8List clipped({required bool opaque}) {
      final plan = GpuPlan();
      addTearDown(plan.free);
      final set = plan.set(0, 0, 1, 1, white);
      plan
        ..open()
        ..solid(0x80808080, side ~/ 2, 0, side, side)
        ..open(opaque: opaque)
        ..row(
          set: set,
          inverse: identity,
          sampling: GpuSampling.nearest,
          columns: side,
          rows: side,
          mode: multiply,
        )
        ..closeAtop()
        ..close(mode: normal);
      return ran(plan, [(0, 0)]);
    }

    final read = clipped(opaque: true);
    final plain = clipped(opaque: false);
    expect(pixel(read, [(0, 0)], side - 1, 1), [128, 128, 128, 128]);
    expect(pixel(plain, [(0, 0)], side - 1, 1), [255, 255, 255, 128]);
    expect(pixel(read, [(0, 0)], 1, 1), nothing);
    expect(pixel(plain, [(0, 0)], 1, 1), nothing);
  });

  test('what the C entries cannot count is refused before them', () {
    final plan = GpuPlan();
    addTearDown(plan.free);

    expect(() => plan.set(0, 0, 2, 1, [null]), throwsArgumentError);
    expect(() => plan.matrix(identity), throwsArgumentError);
    expect(
      () => plan.row(
        set: 0,
        inverse: const [1, 0, 0],
        sampling: GpuSampling.blend,
        columns: 1,
        rows: 1,
        mode: normal,
      ),
      throwsArgumentError,
    );
    expect(
      () => plan.matrix(<double>[1e6, for (var at = 1; at < 20; at++) 0]),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('colour matrix'),
        ),
      ),
    );
  });
}
