import 'dart:ffi';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart';

import 'package:anicel/src/models/separable_blend_mode.dart';
import 'package:anicel/src/native/app_gpu_engine.dart';
import 'package:anicel/src/services/brush_stroke_blend.dart';

import '../helpers/pinned_fingerprints.dart';

/// The app composites its tiles through the package's Dart
/// (screen-on-the-engine 2a · 2b): what it stored comes back through a row
/// copied over nothing, a plan shown onto a surface lays what a run puts,
/// and each step's numbers reach the step they name — a row's keys, its
/// effect chain's ops and the blur maps they read among them. That a plan
/// built call by call is the plan built in Rust is the crate's to pin
/// (rust/src/kernels/composite/abi/tests.rs) — here, what Dart hands it.
void main() {
  late GpuPool pool;
  late GpuComposite composite;
  final held = <Pointer<Uint8>>[];
  const all = (-1 << 31, -1 << 31, (1 << 31) - 1, (1 << 31) - 1);
  // blend.wgsl's BLEND_NORMAL: the brush's table has no normal of its own.
  const normal = 28;
  final multiply = separableBlendModeNativeId(SeparableBlendMode.multiply);
  final screen = separableBlendModeNativeId(SeparableBlendMode.screen);
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

  /// A surface of [width] × [height] as the platform makes the ones it
  /// shows: RGBA where it can, else BGRA — Apple's make BGRA alone
  /// (platform/apple.rs), Linux's RGBA alone.
  GpuSurface surfaceOf(int width, int height) {
    try {
      return appGpuEngine.surface(width, height, bgra: false);
    } on StateError {
      return appGpuEngine.surface(width, height, bgra: true);
    }
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

  // Columns red, blue, red, three to a pixel: the pixel's centre lands on
  // the blue, which nearest lays; pick votes by colour, and the two reds
  // outweigh it; the tent mixes them.
  test('each sampling samples by its own', () {
    const red = [255, 0, 0, 255];
    const blue = [0, 0, 255, 255];
    final side = gpuTileSide;
    final stripes = Uint8List(gpuTileBytes);
    for (var at = 0; at < side * side; at++) {
      stripes.setAll(4 * at, at % side % 3 == 1 ? blue : red);
    }
    final tiles = storedOf(stripes);
    const third = [3.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0];
    List<int> sampled(GpuSampling sampling) => pixel(
      ran(oneRow(tiles, inverse: third, sampling: sampling), [(0, 0)]),
      [(0, 0)],
      5,
      5,
    );

    expect(sampled(GpuSampling.nearest), blue);
    expect(sampled(GpuSampling.pick), red);
    expect(sampled(GpuSampling.blend), isNot(anyOf([equals(red), blue])));
  });

  // Off a whole-pixel move — R1 copies one, in any mode, by any floor: a
  // quarter pixel to the left.
  test("a row's radius floor widens its tent, and is 1 unless named", () {
    final tiles = storedOf(noise(1));
    const quarter = [1.0, 0.0, 0.25, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0];
    Uint8List floored(double radius) =>
        ran(oneRow(tiles, inverse: quarter, radiusFloor: radius), [(0, 0)]);
    final unnamed = GpuPlan();
    addTearDown(unnamed.free);
    unnamed.row(
      set: unnamed.set(0, 0, 1, 1, tiles),
      inverse: quarter,
      sampling: GpuSampling.blend,
      columns: gpuTileSide,
      rows: gpuTileSide,
      mode: normal,
    );

    expect(floored(3), isNot(floored(1)));
    expect(ran(unnamed, [(0, 0)]), floored(1));
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
    final surface = surfaceOf(2 * side, side);
    addTearDown(surface.free);
    final rowByRow = Uint8List(put.length);
    for (var y = 0; y < side; y++) {
      for (var x = 0; x < 2 * side; x++) {
        final [r, g, b, a] = pixel(put, tiles, x, y);
        rowByRow.setAll(
          (y * 2 * side + x) * 4,
          surface.bgra ? [b, g, r, a] : [r, g, b, a],
        );
      }
    }

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

  test('a plan the executor refuses says why, run or shown', () {
    final plan = GpuPlan()..close(mode: normal);
    addTearDown(plan.free);
    final surface = surfaceOf(8, 8);
    addTearDown(surface.free);
    final refused = throwsA(
      isA<StateError>().having(
        (error) => error.message,
        'message',
        contains('not open'),
      ),
    );

    expect(() => composite.run(pool, plan, [(0, 0)], all), refused);
    expect(() => composite.show(pool, plan, surface, (0, 0, 8, 8)), refused);
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

  /// A plan of one row of [tiles] from tile [column] of a tile row, keyed
  /// by the key chain or run through the effect chain [through] adds to
  /// the plan.
  GpuPlan throughRow(
    List<GpuTile?> tiles,
    ({int? keys, int? chain}) Function(GpuPlan plan) through, {
    int column = 0,
  }) {
    final plan = GpuPlan();
    addTearDown(plan.free);
    final set = plan.set(column, 0, tiles.length, 1, tiles);
    final (:keys, :chain) = through(plan);
    final added = plan.row(
      set: set,
      inverse: identity,
      sampling: GpuSampling.blend,
      columns: (column + tiles.length) * gpuTileSide,
      rows: gpuTileSide,
      mode: normal,
      keys: keys,
      chain: chain,
    );
    expect(added, isTrue);
    return plan;
  }

  /// One tile, red on its left half and blue on its right.
  List<GpuTile> redAndBlue() {
    final side = gpuTileSide;
    final halves = Uint32List(side * side);
    for (var at = 0; at < side * side; at++) {
      halves[at] = at % side < side ~/ 2 ? 0xFF0000FF : 0xFFFF0000;
    }
    return storedOf(halves.buffer.asUint8List());
  }

  /// A run of one key naming the reds — red over 127, any green, blue
  /// under 128 — that leaves a third of the alpha it reads, or gives back
  /// what the run erased where it [restores].
  void keyTheReds(GpuPlan plan, int keys, {bool restores = false}) {
    Uint32List table(bool Function(int byte) inside) => Uint32List.fromList([
      for (var byte = 0; byte < 256; byte++) if (inside(byte)) 1 else 0,
    ]);
    plan.keyRun(
      keys,
      red: table((byte) => byte > 127),
      green: table((_) => true),
      blue: table((byte) => byte < 128),
      restores: restores ? 1 : 0,
      maps: Uint8List.fromList([
        for (var alpha = 0; alpha < 256; alpha++) alpha ~/ 3,
      ]),
    );
  }

  // Erasing leaves a third of 255; giving back after it, 255 less a third
  // of the 170 erased — each run against the alpha before the chain.
  test("a row's key chain walks its runs in turn over the colours named", () {
    final tiles = redAndBlue();
    Uint8List keyed(List<bool> runs) => ran(
      throughRow(tiles, (plan) {
        final keys = plan.keys();
        for (final restores in runs) {
          keyTheReds(plan, keys, restores: restores);
        }
        return (keys: keys, chain: null);
      }),
      [(0, 0)],
    );

    final erased = keyed([false]);
    expect(pixel(erased, [(0, 0)], 3, 3), [255, 0, 0, 85]);
    expect(pixel(erased, [(0, 0)], gpuTileSide - 3, 3), [0, 0, 255, 255]);
    expect(pixel(keyed([false, true]), [(0, 0)], 3, 3), [255, 0, 0, 199]);
    expect(pixel(keyed([true]), [(0, 0)], 3, 3), [255, 0, 0, 255]);
  });

  // Two keys in one run, each by its own map: the reds keep a third of
  // their alpha, the blues 200 whatever they held.
  test("a run's keys each leave what their own map says", () {
    final tiles = redAndBlue();
    Uint32List table(int Function(int byte) keys) => Uint32List.fromList([
      for (var byte = 0; byte < 256; byte++) keys(byte),
    ]);
    final plan = throughRow(tiles, (plan) {
      final keys = plan.keys();
      plan.keyRun(
        keys,
        red: table((byte) => byte > 127 ? 1 : 2),
        green: table((_) => 3),
        blue: table((byte) => byte > 127 ? 2 : 1),
        restores: 0,
        maps: Uint8List.fromList([
          for (var alpha = 0; alpha < 256; alpha++) alpha ~/ 3,
          for (var alpha = 0; alpha < 256; alpha++) 200,
        ]),
      );
      return (keys: keys, chain: null);
    });
    final put = ran(plan, [(0, 0)]);

    expect(pixel(put, [(0, 0)], 3, 3), [255, 0, 0, 85]);
    expect(pixel(put, [(0, 0)], gpuTileSide - 3, 3), [0, 0, 255, 200]);
  });

  // The matrix's row lies a tile in: a chain over its own tiles there runs
  // on them, and not on where nothing is.
  test("a chain's keys and matrix are the row's own", () {
    final tiles = redAndBlue();
    final keyed = throughRow(tiles, (plan) {
      final keys = plan.keys();
      keyTheReds(plan, keys);
      return (keys: keys, chain: null);
    });
    final chained = throughRow(tiles, (plan) {
      final keys = plan.keys();
      keyTheReds(plan, keys);
      final chain = plan.chain(0, 0, 1, 1);
      plan.chainKeys(chain, keys);
      return (keys: null, chain: chain);
    });
    final greened = throughRow(column: 1, tiles, (plan) {
      final chain = plan.chain(1, 0, 1, 1);
      plan.chainMatrix(chain, green);
      return (keys: null, chain: chain);
    });
    const aside = [(1, 0)];

    expect(ran(chained, [(0, 0)]), ran(keyed, [(0, 0)]));
    expect(
      pixel(ran(greened, aside), aside, gpuTileSide + 3, 3),
      [0, 255, 0, 255],
    );
  });

  /// One tile with nothing on it but a white pixel at (64, 64).
  List<GpuTile> aWhitePixel() {
    final dot = Uint32List(gpuTileSide * gpuTileSide);
    dot[64 * gpuTileSide + 64] = 0xFFFFFFFF;
    return storedOf(dot.buffer.asUint8List());
  }

  /// The alpha a run of [plan] put at ([x], [y]) of its one tile.
  int alphaAt(GpuPlan plan, int x, int y) =>
      pixel(ran(plan, [(0, 0)]), [(0, 0)], x, y)[3];

  test("a chain's Gaussian blurs across and down by its own, inside its "
      'repeat where one is named', () {
    final tiles = aWhitePixel();
    GpuPlan blurred((int, int, int, int)? repeat) {
      return throughRow(tiles, (plan) {
        final chain = plan.chain(0, 0, 1, 1);
        plan.chainGaussian(chain, 10, 0, repeat: repeat);
        return (keys: null, chain: chain);
      });
    }

    final repeated = blurred((50, 60, 70, 80));

    expect(alphaAt(repeated, 55, 64), greaterThan(0));
    expect(alphaAt(repeated, 64, 70), 0);
    expect(alphaAt(repeated, 72, 64), 0);
    expect(alphaAt(blurred(null), 72, 64), greaterThan(0));
  });

  // Five taps a pixel apart about each pixel: the dot spreads two each way
  // along the step, and no further.
  test("a chain's blur along a way takes its taps along its step", () {
    final tiles = aWhitePixel();
    const still = [1.0, 0.0, 0.0, 1.0];
    GpuPlan along((double, double) step) => throughRow(tiles, (plan) {
      final chain = plan.chain(0, 0, 1, 1);
      plan.chainLine(chain, (0, 0, gpuTileSide, gpuTileSide), [
        (taps: 5, step: step, centre: (0, 0), first: still, each: still),
      ]);
      return (keys: null, chain: chain);
    });
    final across = along((1, 0));

    expect(alphaAt(across, 66, 64), greaterThan(0));
    expect(alphaAt(across, 67, 64), 0);
    expect(alphaAt(across, 64, 66), 0);
    expect(alphaAt(along((0, 1)), 64, 66), greaterThan(0));
  });

  /// An iris of six sides turned by 20°, a little round and drawn out, at
  /// [radius], with no fringe, light or paper unless named.
  GpuLens hexagon(
    double radius, {
    double fringe = 0,
    double gain = 0,
    double threshold = 1,
    double saturation = 0,
    bool linear = false,
    (int, int, int, int)? paper,
  }) {
    (double, double) turn(double degrees) {
      final radians = degrees * math.pi / 180;
      return (math.cos(radians), math.sin(radians));
    }

    return (
      sides: 6,
      roundness: 0.25,
      aspect: 1.25,
      turn: turn(20),
      halfSide: turn(30),
      side: turn(60),
      radius: radius,
      fringe: fringe,
      gain: gain,
      threshold: threshold,
      saturation: saturation,
      linear: linear,
      paper: paper,
    );
  }

  /// A row of tile set [set] over three tiles, posed by [inverse], keyed
  /// by [keys] or run through [chain] if any.
  void threeTileRow(
    GpuPlan plan,
    int set, {
    List<double> inverse = identity,
    int? keys,
    int? chain,
    int opacity = 65535,
    int? mode,
  }) => plan.row(
    set: set,
    inverse: inverse,
    sampling: GpuSampling.blend,
    columns: 3 * gpuTileSide,
    rows: gpuTileSide,
    mode: mode ?? normal,
    keys: keys,
    chain: chain,
    opacity: opacity,
  );
  const nudged = [1.0, 0.0, 0.5, 0.0, 1.0, 0.25, 0.0, 0.0, 1.0];

  // The same rows, drawn alone by the plan or laid from a run of them —
  // freed before the plan runs, which keeps its tiles. The solid under
  // them stays the plan's: a map takes the steps from where it is told.
  test('a blur map laid from a run is the one drawn from its rows', () {
    final tiles = storedOf(noise(3));
    final out = [(0, 0), (1, 0), (2, 0)];
    GpuPlan lensed(int Function(GpuPlan plan, int set) map) {
      final plan = GpuPlan();
      addTearDown(plan.free);
      final set = plan.set(0, 0, 3, 1, tiles);
      plan.solid(0xFF00FF00, 0, 0, 40, 40);
      final blurMap = map(plan, set);
      final chain = plan.chain(0, 0, 3, 1);
      final picture = (0, 0, 3 * gpuTileSide, gpuTileSide);
      plan.chainLens(chain, picture, hexagon(5), map: blurMap);
      threeTileRow(plan, set, chain: chain);
      return plan;
    }

    int drawnFrom(GpuPlan plan, int first) => plan.mapDrawn(
      first,
      channel: GpuMapChannel.blue,
      focal: 90,
      inverts: true,
    );
    final drawn = lensed((plan, set) {
      final first = plan.steps;
      threeTileRow(plan, set, inverse: nudged);
      return drawnFrom(plan, first);
    });
    final laid = lensed((plan, set) {
      final rows = GpuPlan();
      addTearDown(rows.free);
      threeTileRow(rows, rows.set(0, 0, 3, 1, tiles), inverse: nudged);
      final put = composite.run(pool, rows, out, all);
      final map = plan.mapLaid(
        put,
        channel: GpuMapChannel.blue,
        focal: 90,
        inverts: true,
      );
      put.free();
      return map;
    });
    final unmapped = lensed((plan, set) => drawnFrom(plan, plan.steps));

    expect(ran(laid, out), ran(drawn, out));
    expect(ran(drawn, out), isNot(ran(unmapped, out)));
  });

  // Each map a solid with one channel at the focal value and the rest off
  // it: through that channel the blur is in focus everywhere, alike for
  // every channel, and through the next it is not. Luminance is the
  // ledger plan's.
  test('a blur map reads the channel it names', () {
    final tiles = storedOf(noise(1));
    const channels = [
      GpuMapChannel.red,
      GpuMapChannel.green,
      GpuMapChannel.blue,
      GpuMapChannel.alpha,
    ];
    // A<<24|B<<16|G<<8|R: 200 in the channel at its place, 10 in the
    // colours elsewhere, the alpha whole elsewhere.
    const atFocal = [0xFF0A0AC8, 0xFF0AC80A, 0xFFC80A0A, 0xC80A0A0A];
    Uint8List lensed(GpuMapChannel channel, int map) {
      final plan = GpuPlan();
      addTearDown(plan.free);
      final set = plan.set(0, 0, 1, 1, tiles);
      plan.solid(atFocal[map], 0, 0, gpuTileSide, gpuTileSide);
      final read = plan.mapDrawn(0, channel: channel, focal: 200);
      final chain = plan.chain(0, 0, 1, 1);
      final picture = (0, 0, gpuTileSide, gpuTileSide);
      plan
        ..chainLens(chain, picture, hexagon(6), map: read)
        ..row(
          set: set,
          inverse: identity,
          sampling: GpuSampling.blend,
          columns: gpuTileSide,
          rows: gpuTileSide,
          mode: normal,
          chain: chain,
        );
      return ran(plan, [(0, 0)]);
    }

    final inFocus = lensed(channels.first, 0);
    for (var at = 0; at < channels.length; at++) {
      final next = channels[(at + 1) % channels.length];
      expect(lensed(channels[at], at), inFocus, reason: '${channels[at]}');
      expect(lensed(next, at), isNot(inFocus), reason: '$next');
    }
  });

  // Every number each call of a chain takes reaches its op: the crate pins
  // that a plan built call by call composites as one built in Rust
  // (abi/tests.rs), this the calls Dart makes, every field of them read
  // by a pixel. The ledger's row was pinned by this device; another that
  // differs fails, naming its adapter.
  test('a plan of every chain op Dart builds composites as pinned', () {
    final [a, b, c] = storedOf(noise(3));
    final plan = GpuPlan();
    addTearDown(plan.free);
    final pair = plan.set(0, 0, 2, 1, [a, b]);
    final one = plan.set(1, 0, 1, 1, [c]);
    final keys = plan.keys();
    keyTheReds(plan, keys);
    keyTheReds(plan, keys, restores: true);
    threeTileRow(plan, one);
    final map = plan.mapDrawn(
      0,
      channel: GpuMapChannel.luminance,
      focal: 140,
      inverts: true,
    );
    final rowChain = plan.chain(0, 0, 2, 1);
    // The blurs before it gather the noise about a luma of a half: a
    // threshold under that lights it, so its gain and saturation show.
    final lens = hexagon(
      4.5,
      fringe: 80,
      gain: 1.5,
      threshold: 0.3,
      saturation: 0.4,
      linear: true,
      paper: (0, 0, 250, 128),
    );
    plan
      ..chainMatrix(rowChain, const [
        1.4, 0, 0, 0, -20, //
        0, 1.2, 0.1, 0, 5,
        0, 0, 0.8, 0, 30,
        0, 0, 0, 1, 0,
      ])
      ..chainKeys(rowChain, keys)
      ..chainGaussian(rowChain, 3, 2, repeat: (4, 6, 200, 120))
      ..chainLine(rowChain, (6, 0, 250, 128), const [
        (
          taps: 5,
          step: (1.5, 0.5),
          centre: (100, 60),
          first: [1, 0, 0, 1],
          each: [0.99, 0.01, -0.01, 0.99],
        ),
        (
          taps: 3,
          step: (0, 2),
          centre: (120, 40),
          first: [1, 0.05, 0, 1],
          each: [1, 0, 0, 1.02],
        ),
      ])
      ..chainLens(rowChain, (0, 0, 2 * gpuTileSide, gpuTileSide), lens,
          map: map);
    final closeChain = plan.chain(0, 0, 3, 1);
    plan
      ..chainGaussian(closeChain, 2, 0)
      ..open();
    threeTileRow(
      plan,
      pair,
      inverse: nudged,
      keys: keys,
      opacity: 60000,
      mode: multiply,
    );
    threeTileRow(plan, pair, chain: rowChain, opacity: 50000, mode: screen);
    plan.close(mode: normal, opacity: 45000, chain: closeChain, mix: 40000);
    final put = ran(plan, [(0, 0), (1, 0), (2, 0)], (0, 0, 300, 120));

    expect(
      fingerprintHex(put),
      pinnedFingerprint('composite/every-chain-op-from-dart'),
      reason: appGpuEngine.adapterName,
    );
  });

  test("what a chain's call cannot add says why", () {
    final plan = GpuPlan();
    addTearDown(plan.free);
    Matcher saying(String why) => throwsA(
      isA<StateError>().having(
        (error) => error.message,
        'message',
        contains(why),
      ),
    );
    final twenty = [
      for (var at = 0; at < 20; at++) if (at % 6 == 0) 1.0 else 0.0,
    ];
    final keys = plan.keys();
    final chain = plan.chain(0, 0, 1, 1);
    final table = Uint32List(256);
    void keyRun(int keys, {Uint32List? red, int maps = 256}) => plan.keyRun(
      keys,
      red: red ?? table,
      green: table,
      blue: table,
      restores: 0,
      maps: Uint8List(maps),
    );

    expect(() => keyRun(keys, red: Uint32List(255)), throwsArgumentError);
    expect(() => keyRun(keys, maps: 300), throwsArgumentError);
    const four = [1.0, 0.0, 0.0, 1.0];
    for (final (first, each) in const [(four, <double>[1]), ([1.0], four)]) {
      expect(
        () => plan.chainLine(chain, (0, 0, 8, 8), [
          (taps: 3, step: (1, 0), centre: (0, 0), first: first, each: each),
        ]),
        throwsArgumentError,
      );
    }
    expect(() => keyRun(keys, maps: 33 * 256), saying('a run of 33 keys'));
    expect(() => keyRun(keys, maps: 32 * 256), returnsNormally);
    expect(() => keyRun(keys + 1), saying('no key chain ${keys + 1}'));
    expect(
      () => plan.chainKeys(chain, keys + 1),
      saying('no key chain ${keys + 1}'),
    );
    for (final add in <void Function(int chain)>[
      (chain) => plan.chainMatrix(chain, twenty),
      (chain) => plan.chainKeys(chain, keys),
      (chain) => plan.chainGaussian(chain, 1, 1),
      (chain) => plan.chainLine(chain, (0, 0, 8, 8), const [
        (taps: 3, step: (1, 0), centre: (0, 0), first: four, each: four),
      ]),
      (chain) => plan.chainLens(chain, (0, 0, 8, 8), hexagon(2)),
    ]) {
      expect(() => add(chain + 1), saying('no effect chain ${chain + 1}'));
    }
    expect(
      () => plan.chainMatrix(chain, [1e6, ...twenty.skip(1)]),
      saying('colour matrix'),
    );
    expect(
      () => plan.chainLens(chain, (0, 0, 8, 8), hexagon(2), map: 0),
      saying('no blur map 0'),
    );
    expect(
      () => plan.mapDrawn(1, channel: GpuMapChannel.red, focal: 0),
      saying('a map drawn from step 1 of 0'),
    );
    expect(plan.keys(), keys + 1);
    expect(plan.chain(0, 0, 1, 1), chain + 1);
    final map = plan.mapDrawn(0, channel: GpuMapChannel.red, focal: 0);
    expect(plan.mapDrawn(0, channel: GpuMapChannel.red, focal: 0), map + 1);
  });

  test('a row or a close naming what the plan lacks is refused where it '
      'runs', () {
    final tiles = storedOf(noise(1));
    void refused(void Function(GpuPlan plan, int set) build, String why) {
      final plan = GpuPlan();
      addTearDown(plan.free);
      build(plan, plan.set(0, 0, 1, 1, tiles));
      expect(
        () => composite.run(pool, plan, [(0, 0)], all),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains(why),
          ),
        ),
      );
    }

    void row(GpuPlan plan, int set, {int? keys, int? chain}) => plan.row(
      set: set,
      inverse: identity,
      sampling: GpuSampling.blend,
      columns: gpuTileSide,
      rows: gpuTileSide,
      mode: normal,
      keys: keys,
      chain: chain,
    );

    refused((plan, set) => row(plan, set, keys: 3), 'keys by chain 3 of 0');
    refused((plan, set) => row(plan, set, chain: 2), 'effect chain 2 of 0');
    refused(
      (plan, set) =>
          row(plan, set, keys: plan.keys(), chain: plan.chain(0, 0, 1, 1)),
      'names keys and an effect chain',
    );
    refused((plan, set) {
      final chain = plan.chain(0, 0, 1, 1);
      plan
        ..chainGaussian(chain, 1, 1)
        ..open();
      row(plan, set);
      plan.close(mode: normal, chain: chain, mix: 70000);
    }, 'mixes its chain at 70000');
  });
}
