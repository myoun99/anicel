/// Anicel's GPU engine: one wgpu device on the adapter Flutter draws with,
/// the pool the app's tiles are stored in, and its kernels
/// (gpu-engine-skeleton, screen-on-the-engine).
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';

import 'src/engine_ffi.dart' as rust;
import 'src/texture_shim.dart' as shim;

/// The Android plugin (android/src/main/kotlin/.../GpuEnginePlugin.kt).
const _plugin = MethodChannel('gpu_engine');

String _lastError() => using((arena) {
  const capacity = 1024;
  final buffer = arena<Uint8>(capacity);
  final length = rust.lastError(buffer, capacity);
  final count = length < capacity ? length : capacity;
  return utf8.decode(buffer.asTypedList(count), allowMalformed: true);
});

/// The entries an array of [count] is allocated, for the C ABI to read
/// [count] of: one at least, since a calloc of nothing may answer null
/// (POSIX), which ffi's allocator throws on.
int _held(int count) => count == 0 ? 1 : count;

/// What a C entry answered — an index, a count —, or its last error thrown
/// where it answered -1.
int _checked(int answer) {
  if (answer < 0) {
    throw StateError(_lastError());
  }
  return answer;
}

/// [rect] — [left, top, right, bottom) — as four words of [arena]'s.
Pointer<Int32> _rect(Arena arena, (int, int, int, int) rect) {
  final (left, top, right, bottom) = rect;
  return arena<Int32>(4)..asTypedList(4).setAll(0, [left, top, right, bottom]);
}

/// [_rect]'s, or null for none.
Pointer<Int32> _rectOrNull(Arena arena, (int, int, int, int)? rect) =>
    rect == null ? nullptr : _rect(arena, rect);

/// [values] as doubles of [arena]'s.
Pointer<Double> _doubles(Arena arena, List<double> values) =>
    arena<Double>(_held(values.length))
      ..asTypedList(values.length).setAll(0, values);

/// [matrix], checked to be `ColorFilter.matrix`'s twenty.
List<double> _twenty(List<double> matrix) {
  if (matrix.length != 20) {
    throw ArgumentError('a colour matrix of ${matrix.length}, not 20');
  }
  return matrix;
}

/// A kernel's submit-to-done time from its C ABI, which gives -1 on
/// failure.
Duration _ran(int nanos) {
  if (nanos < 0) {
    throw StateError(_lastError());
  }
  return Duration(microseconds: nanos ~/ 1000);
}

/// One wgpu device on the adapter Flutter draws with.
class GpuEngine {
  GpuEngine._(this._engine, this.adapterLuid);

  /// Opens on Flutter's own adapter, so what the engine writes lives on
  /// the GPU that shows it: on Windows the one Flutter names by LUID;
  /// elsewhere Flutter names none to a plugin, so the only one there is
  /// (rust/src/device.rs, `open_sole`).
  factory GpuEngine.onFlutterAdapter() {
    if (!Platform.isWindows) {
      return GpuEngine._(_opened(rust.engineOpenSole()), null);
    }
    final luid = shim.flutterAdapterLuid();
    if (luid == 0) {
      throw StateError('Flutter gave no graphics adapter');
    }
    return GpuEngine._(_opened(rust.engineOpen(luid)), luid);
  }

  /// Opens on the platform's first adapter — `flutter test`'s, where no
  /// Flutter names one (rust/src/device.rs, `open_first`).
  factory GpuEngine.onFirstAdapter() =>
      GpuEngine._(_opened(rust.engineOpenFirst()), null);

  /// [open] — one of the factories above — run on an isolate of its own,
  /// the engine coming back by its address, so the caller's isolate goes
  /// on while a device opens (0.6–1.2 s, 보드/인프라 2026-11-07). The device
  /// opens on a thread of the engine's own either way (rust/src/device.rs,
  /// `opened`), but the isolate that asks waits for that thread
  /// (grid-on-the-engine, 관제 2026-11-08 20:54: 「장치는 첫 프레임 뒤에」).
  static Future<GpuEngine> opening(GpuEngine Function() open) async {
    final (address, luid) = await Isolate.run(() {
      final engine = open();
      return (engine._engine.address, engine.adapterLuid);
    });
    return GpuEngine._(Pointer.fromAddress(address), luid);
  }

  static Pointer<rust.Engine> _opened(Pointer<rust.Engine> engine) {
    if (engine == nullptr) {
      throw StateError(_lastError());
    }
    return engine;
  }

  final Pointer<rust.Engine> _engine;

  /// The adapter's LUID where Flutter names its adapter by one (Windows).
  final int? adapterLuid;
  Pointer<rust.Fill>? _fill;

  Pointer<rust.Fill> get _fillKernel => _fill ??= rust.fillNew(_engine);

  String get adapterName => using((arena) {
    const capacity = 256;
    final buffer = arena<Uint8>(capacity);
    final length = rust.engineAdapterName(_engine, buffer, capacity);
    final count = length < capacity ? length : capacity;
    return utf8.decode(buffer.asTypedList(count), allowMalformed: true);
  });

  /// This process's use of the adapter's local video memory, in bytes; 0
  /// where the platform cannot say (Android, Linux).
  int get videoMemoryBytes => rust.engineVideoMemory(_engine);

  /// A texture of [width] × [height] 8-bit texels, BGRA when [bgra].
  GpuSurface surface(int width, int height, {required bool bgra}) {
    final surface = rust.surfaceNew(_engine, width, height, bgra);
    if (surface == nullptr) {
      throw StateError(_lastError());
    }
    return GpuSurface._(this, surface, width, height, bgra);
  }

  /// A Flutter texture of [width] × [height] RGBA texels that the engine
  /// presents into — Android's way to the screen.
  Future<GpuWindow> window(int width, int height) async {
    final made = (await _plugin.invokeMapMethod<String, int>('window', {
      'width': width,
      'height': height,
    }))!;
    final textureId = made['textureId']!;
    final window = rust.windowNew(
      _engine,
      Pointer.fromAddress(made['window']!),
      width,
      height,
    );
    if (window == nullptr) {
      final error = _lastError();
      await _plugin.invokeMethod<void>('release', {'textureId': textureId});
      throw StateError(error);
    }
    return GpuWindow._(this, window, textureId);
  }

  /// Frees the device; every surface must be freed first.
  void close() {
    final fill = _fill;
    if (fill != null) {
      rust.fillFree(fill);
    }
    rust.engineClose(_engine);
  }
}

/// What a kernel writes for the screen to show: a [GpuSurface] Flutter
/// shows through a [SharedTexture], or a [GpuWindow]'s next image — one
/// kernel entry for both (rust/src/kernels/mod.rs).
sealed class GpuTarget {
  GpuTarget(this._engine);

  final GpuEngine _engine;

  /// The texture the kernel writes.
  Pointer<rust.Texture> get _texture;

  /// Fills the target with the pattern for [seed] and waits for the GPU;
  /// returns the submit-to-done time.
  Duration fill(int seed) => _ran(
    rust.fillRun(_engine._fillKernel, _engine._engine, _texture, seed),
  );
}

/// A texture the compute pass fills and Flutter shows.
class GpuSurface extends GpuTarget {
  GpuSurface._(
    super._engine,
    this._surface,
    this.width,
    this.height,
    this.bgra,
  );

  final Pointer<rust.Surface> _surface;
  final int width;
  final int height;
  final bool bgra;

  Pointer<Void> get _handle => rust.surfaceHandle(_surface);

  @override
  Pointer<rust.Texture> get _texture => rust.surfaceTexture(_surface);

  /// The CRC-32 of the surface's bytes, read back from the GPU — the
  /// fingerprint the ledger `test/fixtures/fingerprints.json` pins.
  int fingerprint() => using((arena) {
    final hash = arena<Uint32>();
    if (!rust.surfaceFingerprint(_engine._engine, _surface, hash)) {
      throw StateError(_lastError());
    }
    return hash.value;
  });

  /// What a D3D11 device of Flutter's adapter sees when it opens the
  /// handle, as ANGLE will; null when it cannot open it, and off Windows,
  /// where Flutter draws with no ANGLE.
  ({int format, int bindFlags, int miscFlags})? inspect() => using((arena) {
    if (!Platform.isWindows) {
      return null;
    }
    final format = arena<Uint32>();
    final bindFlags = arena<Uint32>();
    final miscFlags = arena<Uint32>();
    if (!shim.inspectShared(_handle, format, bindFlags, miscFlags)) {
      return null;
    }
    return (
      format: format.value,
      bindFlags: bindFlags.value,
      miscFlags: miscFlags.value,
    );
  });

  /// Frees the surface; Flutter must no longer show it.
  void free() => rust.surfaceFree(_surface);
}

/// The side of the tiles a [GpuPool] stores, in texels: a tile is that
/// square of straight RGBA8, [gpuTileBytes] long.
final int gpuTileSide = rust.tileSide();

/// The bytes of a tile a [GpuPool] stores.
final int gpuTileBytes = gpuTileSide * gpuTileSide * 4;

/// Where a [GpuPool] keeps a tile: a slot of one of its pages.
typedef GpuTile = ({int page, int slot});

/// A tile with nothing on it, as a tile set names one.
const _noTile = 0xFFFFFFFF;

/// [tiles] — a tile set's [columns] × [rows], row by row, null for one with
/// nothing on it — as the words the C ABI names a set by: `page << 16 |
/// slot` each (`TileAt::word`), [_noTile] for none. A plan's tile sets and
/// the ink scan's cel alike.
Pointer<Uint32> _tileWords(
  Arena arena,
  int columns,
  int rows,
  List<GpuTile?> tiles,
) {
  if (tiles.length != columns * rows) {
    throw ArgumentError('$columns × $rows tiles, not ${tiles.length}');
  }
  final words = arena<Uint32>(_held(tiles.length));
  for (var at = 0; at < tiles.length; at++) {
    final tile = tiles[at];
    words[at] = tile == null ? _noTile : tile.page << 16 | tile.slot;
  }
  return words;
}

/// The engine's pages of tiles (rust/src/kernels/pool): each tile stored
/// lands in a fresh slot of its cel and stays there until let go.
class GpuPool {
  /// A pool on [engine] that makes no page past [mostBytes].
  factory GpuPool(GpuEngine engine, int mostBytes) {
    final pool = rust.poolNew(engine._engine, mostBytes);
    if (pool == nullptr) {
      throw StateError(_lastError());
    }
    return GpuPool._(engine, pool);
  }

  GpuPool._(this._engine, this._pool);

  final GpuEngine _engine;
  final Pointer<rust.Pool> _pool;

  /// A cel: the tiles stored under it go to pages of theirs first, then to
  /// any page with room (rust/src/kernels/pool/mod.rs).
  int cel() => rust.poolCel(_pool);

  /// Stores [tiles] — [gpuTileBytes] at each, alive for the call — under
  /// [cel], each in a fresh slot, and returns where each landed, in order:
  /// all of them, or the first few where the pool is full at the next.
  List<GpuTile> store(int cel, List<Pointer<Uint8>> tiles) {
    return using((arena) {
      final count = tiles.length;
      final at = arena<Pointer<Uint8>>(_held(count));
      for (var tile = 0; tile < count; tile++) {
        at[tile] = tiles[tile];
      }
      final pages = arena<Uint16>(_held(count));
      final slots = arena<Uint16>(_held(count));
      final stored = rust.poolStore(
        _pool,
        _engine._engine,
        cel,
        at,
        count,
        pages,
        slots,
      );
      if (stored < 0) {
        throw StateError(_lastError());
      }
      return [
        for (var tile = 0; tile < stored; tile++)
          (page: pages[tile], slot: slots[tile]),
      ];
    });
  }

  /// Lets [tile] go; false where no tile is held there.
  bool release(GpuTile tile) => rust.poolRelease(_pool, tile.page, tile.slot);

  /// Makes no page more past [mostBytes]: the pages made stay — till
  /// [giveBackPast] — and the next is made only within it.
  void makeNoPagePast(int mostBytes) => rust.poolMostBytes(_pool, mostBytes);

  /// Gives back the pages none of whose tiles is held, the last first, till
  /// the pages made hold [mostBytes]; a cel that needs a page again has it
  /// made again (rust/src/kernels/pool/mod.rs).
  void giveBackPast(int mostBytes) =>
      rust.poolGiveBack(_pool, _engine._engine, mostBytes);

  /// The bytes of the pages made, each counted whole — one given back by
  /// the tile's stand-in left in its place.
  int get bytes => rust.poolBytes(_pool);

  /// Frees the pool's pages; before its engine is closed.
  void free() => rust.poolFree(_pool);
}

/// The blends the executor has beside the app's table of 1 to 27 — the C
/// engine's stroke ids, which blend.wgsl follows (`BLEND_NORMAL` and on):
/// the app names those itself (brush_stroke_blend.dart), these only the
/// engine has.
abstract final class GpuBlend {
  /// Source over.
  static const int normal = 28;

  /// The eraser: what is there loses the alpha of what lands, its colour
  /// kept — a stroke's.
  static const int erase = 29;

  /// Flutter's `BlendMode.plus`: an adjustment's crossfade adds its second
  /// pass onto its first by it.
  static const int plus = 30;
}

/// How a row's pose samples its pixels: R1's modes, by the engine's ids.
enum GpuSampling {
  /// The tent mean — a reduction's.
  blend(0),

  /// The area vote: the one colour covering most of the preimage.
  pick(1),

  /// The one source pixel where the pixel's centre lands.
  nearest(3);

  const GpuSampling(this.id);

  final int id;
}

/// The channel a blur map is read through, by the engine's ids.
enum GpuMapChannel {
  red(0),
  green(1),
  blue(2),
  alpha(3),
  luminance(4);

  const GpuMapChannel(this.id);

  final int id;
}

/// One way of fx Gaussian Blur: its sigma in pixels, and how many pixels
/// either side of a pixel its weights reach — none where the way is not
/// blurred (rust/src/kernels/effects/blur/gaussian.rs).
typedef GpuGaussianWay = ({double sigma, int reach});

/// One pass of a blur along a way — the app's `LineBoxPass` with its maps
/// worked out: `taps` taps, the i-th at centre + M_i·(at − centre) +
/// step·(i − (taps − 1)/2), M_i = each^i · first, a map its columns as the
/// app writes them (rust/src/kernels/effects/blur/line.rs).
typedef GpuLinePass = ({
  int taps,
  (double, double) step,
  (double, double) centre,
  List<double> first,
  List<double> each,
});

/// fx Camera Lens Blur's settings — the app's `IrisGatherPass` but its map
/// (rust/src/kernels/effects/blur/lens.rs): an iris of `sides`, its
/// `roundness` (0 to 1) and `aspect`, its rotation's, half a side's and a
/// whole side's turns as cosine and sine; the `radius` and the `fringe` (0
/// to 500); the light's `gain`, `threshold` and `saturation`, `linear` or
/// not; and the `paper` whose edge pixels it repeats past it, if any.
typedef GpuLens = ({
  int sides,
  double roundness,
  double aspect,
  (double, double) turn,
  (double, double) halfSide,
  (double, double) side,
  double radius,
  double fringe,
  double gain,
  double threshold,
  double saturation,
  bool linear,
  (int, int, int, int)? paper,
});

/// A plan the executor runs, built step by step, bottom to top
/// (rust/src/kernels/composite/abi.rs): tile sets of the pool, key chains,
/// colour matrices, effect chains and the blur maps their lens blurs read,
/// and rows, folders, clips and solid colours laying them. The executor
/// checks it where it runs.
class GpuPlan {
  GpuPlan() : _plan = rust.planNew();

  final Pointer<rust.Planned> _plan;

  /// Adds the tile set of [columns] × [rows] canvas tiles whose top-left is
  /// column [x0], row [y0] — [tiles] row by row, null for one with nothing
  /// on it — and returns the index a row lays it by.
  int set(int x0, int y0, int columns, int rows, List<GpuTile?> tiles) =>
      using(
        (arena) => rust.planSet(
          _plan,
          x0,
          y0,
          columns,
          rows,
          _tileWords(arena, columns, rows, tiles),
        ),
      );

  /// Adds a key chain of no runs and returns the index a row or a chain's
  /// op keys by.
  int keys() => rust.planKeys(_plan);

  /// Adds to key chain [keys] a run of colour keys as the app's tables give
  /// one: for each channel's byte — [red], [green], [blue], 256 words each
  /// — which keys are within their tolerance of it, bit k for key k;
  /// [restores], the keys that give back instead of erasing; and [maps],
  /// each key's 256-byte alpha map, one after another.
  void keyRun(
    int keys, {
    required Uint32List red,
    required Uint32List green,
    required Uint32List blue,
    required int restores,
    required Uint8List maps,
  }) {
    if ([red, green, blue].any((table) => table.length != 256) ||
        maps.length % 256 != 0) {
      throw ArgumentError('tables of 256 words, maps of 256 bytes a key');
    }
    _checked(
      using((arena) {
        Pointer<Uint32> words(Uint32List table) =>
            arena<Uint32>(256)..asTypedList(256).setAll(0, table);
        final bytes = arena<Uint8>(_held(maps.length))
          ..asTypedList(maps.length).setAll(0, maps);
        return rust.planKeyRun(
          _plan,
          keys,
          words(red),
          words(green),
          words(blue),
          restores,
          bytes,
          maps.length ~/ 256,
        );
      }),
    );
  }

  /// Adds the colour matrix of [matrix] — `ColorFilter.matrix`'s twenty —
  /// and returns the index a row or a close runs it by.
  int matrix(List<double> matrix) => _checked(
    using((arena) => rust.planMatrix(_plan, _doubles(arena, _twenty(matrix)))),
  );

  /// Adds an effect chain of no ops over the canvas tiles of [columns] ×
  /// [rows] whose top-left is column [x0], row [y0] — a row's in its own
  /// space, a folder's on the canvas — and returns the index a row or a
  /// close runs it by.
  int chain(int x0, int y0, int columns, int rows) =>
      rust.planChain(_plan, x0, y0, columns, rows);

  /// Adds to effect chain [chain] the colour matrix of [matrix] —
  /// `ColorFilter.matrix`'s twenty.
  void chainMatrix(int chain, List<double> matrix) => _checked(
    using(
      (arena) => rust.planChainMatrix(
        _plan,
        chain,
        _doubles(arena, _twenty(matrix)),
      ),
    ),
  );

  /// Adds to effect chain [chain] the runs of key chain [keys], every key
  /// against the alpha of what the op reads.
  void chainKeys(int chain, int keys) =>
      _checked(rust.planChainKeys(_plan, chain, keys));

  /// Adds to effect chain [chain] fx Gaussian Blur, the Gaussian itself a
  /// way a pass, [across] and [down]: reading [picture] — past it nothing,
  /// or its nearest pixel where it [repeats] (Repeat Edge Pixels) — and
  /// putting [puts], nothing outside it; both inside the chain's tiles.
  void chainGaussian(
    int chain, {
    required GpuGaussianWay across,
    required GpuGaussianWay down,
    required (int, int, int, int) picture,
    bool repeats = false,
    required (int, int, int, int) puts,
  }) => _checked(
    using((arena) {
      final reaches = arena<Uint32>(2)
        ..[0] = across.reach
        ..[1] = down.reach;
      return rust.planChainGaussian(
        _plan,
        chain,
        _doubles(arena, [across.sigma, down.sigma]),
        reaches,
        _rect(arena, picture),
        repeats ? 1 : 0,
        _rect(arena, puts),
      );
    }),
  );

  /// Adds to effect chain [chain] fx Directional or Radial Blur's [passes]
  /// over [plate], inside the chain's tiles.
  void chainLine(
    int chain,
    (int, int, int, int) plate,
    List<GpuLinePass> passes,
  ) {
    if (passes.any((pass) => pass.first.length != 4 || pass.each.length != 4)) {
      throw ArgumentError('maps of four, column by column');
    }
    _checked(
      using((arena) {
        final taps = arena<Uint32>(_held(passes.length));
        for (var at = 0; at < passes.length; at++) {
          taps[at] = passes[at].taps;
        }
        final maps = _doubles(arena, [
          for (final pass in passes) ...[
            pass.step.$1,
            pass.step.$2,
            pass.centre.$1,
            pass.centre.$2,
            ...pass.first,
            ...pass.each,
          ],
        ]);
        return rust.planChainLine(
          _plan,
          chain,
          _rect(arena, plate),
          taps,
          maps,
          passes.length,
        );
      }),
    );
  }

  /// Adds to effect chain [chain] fx Camera Lens Blur over [picture] by
  /// [lens], reading blur map [map] if any.
  void chainLens(
    int chain,
    (int, int, int, int) picture,
    GpuLens lens, {
    int? map,
  }) => _checked(
    using(
      (arena) => rust.planChainLens(
        _plan,
        chain,
        _rect(arena, picture),
        lens.sides,
        _doubles(arena, [
          lens.roundness,
          lens.aspect,
          lens.turn.$1,
          lens.turn.$2,
          lens.halfSide.$1,
          lens.halfSide.$2,
          lens.side.$1,
          lens.side.$2,
          lens.radius,
          lens.fringe,
          lens.gain,
          lens.threshold,
          lens.saturation,
        ]),
        lens.linear,
        _rectOrNull(arena, lens.paper),
        map ?? -1,
      ),
    ),
  );

  /// Adds a blur map read from the tiles [tiles] holds — over the blur's
  /// own rectangle, as a run over its tiles put them — through [channel],
  /// in focus at [focal] (0 to 255) and inverted where [inverts]; returns
  /// the index a lens blur reads it by. The plan keeps the tiles past
  /// [tiles]' own free.
  int mapLaid(
    GpuComposited tiles, {
    required GpuMapChannel channel,
    required double focal,
    bool inverts = false,
  }) => _checked(
    rust.planMapLaid(_plan, tiles._composited, channel.id, focal, inverts),
  );

  /// How many steps the plan has: where the steps a blur map is drawn
  /// from begin ([mapDrawn]).
  int get steps => rust.planSteps(_plan);

  /// Takes the plan's steps from step [first] on as the steps a blur map is
  /// drawn from — drawn alone over the blur's rectangle, as they show by
  /// themselves —, read as [mapLaid]'s; returns the index a lens blur
  /// reads it by.
  int mapDrawn(
    int first, {
    required GpuMapChannel channel,
    required double focal,
    bool inverts = false,
  }) => _checked(rust.planMapDrawn(_plan, first, channel.id, focal, inverts));

  /// Adds a row: tile set [set], keyed by key chain [keys] or run through
  /// effect chain [chain] if one is named (not both: a chain's keys are
  /// its ops), posed by [inverse] — canvas pixel to the row's own,
  /// row-major with the homogeneous row last, over an output of [columns]
  /// × [rows] pixels — sampled by [sampling], Blend's radius at least
  /// [radiusFloor], through colour matrix [matrix] if any, laid at
  /// [opacity] (65535 whole) in blend mode [mode] (the engine's id).
  ///
  /// False where its pose lands nothing, so it lays nothing and is left
  /// out.
  bool row({
    required int set,
    required List<double> inverse,
    required GpuSampling sampling,
    required int columns,
    required int rows,
    required int mode,
    int? matrix,
    int? keys,
    int? chain,
    double radiusFloor = 1,
    int opacity = 65535,
  }) {
    if (inverse.length != 9) {
      throw ArgumentError('an inverse of ${inverse.length}, not 9');
    }
    final added = using(
      (arena) => rust.planRow(
        _plan,
        set,
        matrix ?? -1,
        keys ?? -1,
        chain ?? -1,
        _doubles(arena, inverse),
        radiusFloor,
        sampling.id,
        columns,
        rows,
        opacity,
        mode,
      ),
    );
    return _checked(added) == 1;
  }

  /// Opens a transparent buffer — a folder's, a clip's base or its scope —
  /// or, where [opaque], one holding the buffer under it with its alpha
  /// made whole: a clip's scope whose rows blend with the base.
  void open({bool opaque = false}) => rust.planOpen(_plan, opaque);

  /// Closes the open buffer onto the one under it at [opacity] in [mode],
  /// through effect chain [chain] if any — what it puts laid against the
  /// buffer it ran on at [mix] (65535 whole) — then colour matrix [matrix]
  /// if any.
  void close({
    required int mode,
    int opacity = 65535,
    int? matrix,
    int? chain,
    int mix = 65535,
  }) => rust.planClose(_plan, opacity, mode, matrix ?? -1, chain ?? -1, mix);

  /// Closes a clip's scope onto its base by the base's alpha.
  void closeAtop() => rust.planCloseAtop(_plan);

  /// Lays [colour] — straight RGBA8, A<<24|B<<16|G<<8|R — over the canvas
  /// pixels [[left], [top], [right], [bottom]) in normal.
  void solid(int colour, int left, int top, int right, int bottom) =>
      rust.planSolid(_plan, colour, left, top, right, bottom);

  void free() => rust.planFree(_plan);
}

/// The executor: plans of the pool's tiles composited on the GPU.
class GpuComposite {
  /// The executor on [engine], its full pass compiled.
  factory GpuComposite(GpuEngine engine) {
    final composite = rust.compositeNew(engine._engine);
    if (composite == nullptr) {
      throw StateError(_lastError());
    }
    return GpuComposite._(engine, composite);
  }

  GpuComposite._(this._engine, this._composite);

  final GpuEngine _engine;
  final Pointer<rust.Composite> _composite;

  /// Composites [plan] of [pool]'s tiles over the output [tiles] — canvas
  /// tile columns and rows — with nothing outside the pixels [extent],
  /// [left, top, right, bottom), and submits the work.
  GpuComposited run(
    GpuPool pool,
    GpuPlan plan,
    List<(int, int)> tiles,
    (int, int, int, int) extent,
  ) {
    final out = using((arena) {
      final at = arena<Int32>(_held(2 * tiles.length));
      for (var tile = 0; tile < tiles.length; tile++) {
        at[2 * tile] = tiles[tile].$1;
        at[2 * tile + 1] = tiles[tile].$2;
      }
      return rust.compositeRun(
        _composite,
        _engine._engine,
        pool._pool,
        plan._plan,
        at,
        tiles.length,
        _rect(arena, extent),
      );
    });
    if (out == nullptr) {
      throw StateError(_lastError());
    }
    return GpuComposited._(_engine, out, tiles.length);
  }

  /// Composites [plan] of [pool]'s tiles onto the pixels [rect] of
  /// [target] — [left, top, right, bottom) — leaving the rest of it as it
  /// was, and waits for the GPU; returns how many passes it took.
  int show(
    GpuPool pool,
    GpuPlan plan,
    GpuTarget target,
    (int, int, int, int) rect,
  ) => _checked(
    using(
      (arena) => rust.compositeShow(
        _composite,
        _engine._engine,
        pool._pool,
        plan._plan,
        target._texture,
        _edges(arena, rect),
      ),
    ),
  );

  /// Frees the executor; before its engine is closed.
  void free() => rust.compositeFree(_composite);
}

/// [rect] — [left, top, right, bottom) of a target's pixels — as four
/// unsigned words of [arena]'s.
Pointer<Uint32> _edges(Arena arena, (int, int, int, int) rect) {
  final (left, top, right, bottom) = rect;
  return arena<Uint32>(4)..asTypedList(4).setAll(0, [left, top, right, bottom]);
}

/// A canvas's screen (rust/src/kernels/composite/screen.rs): the canvas's
/// composite kept at its own pixels, made again where it changed
/// ([compose]), and shown through the camera ([show]) — a pan or a zoom
/// shows what is kept, the canvas's pixels magnified, so what is shown
/// while working is the result (gpu-canonical-store ④⑤).
class GpuScreen {
  /// The screen of a canvas's composite over the pixels [extent] — [left,
  /// top, right, bottom): the page and what lies past it — on
  /// [composite]'s engine, shown on Blend's radius [radiusFloor] at least,
  /// nothing composed on it yet.
  factory GpuScreen(
    GpuComposite composite,
    (int, int, int, int) extent, {
    double radiusFloor = 1,
  }) {
    final screen = using(
      (arena) => rust.screenNew(_rect(arena, extent), radiusFloor),
    );
    if (screen == nullptr) {
      throw StateError(_lastError());
    }
    return GpuScreen._(composite, screen);
  }

  GpuScreen._(this._composite, this._screen);

  final GpuComposite _composite;
  final Pointer<rust.Screen> _screen;

  /// Composites [plan] of [pool]'s tiles onto the kept canvas over its
  /// tiles that meet the pixels [changed] — [left, top, right, bottom); the
  /// whole canvas the first time — and submits the work. The tiles
  /// [changed] meets none of are kept as they were: where the composite
  /// changed is the caller's to say.
  void compose(GpuPool pool, GpuPlan plan, (int, int, int, int) changed) {
    final composed = using(
      (arena) => rust.screenCompose(
        _screen,
        _composite._composite,
        _composite._engine._engine,
        pool._pool,
        plan._plan,
        _rect(arena, changed),
      ),
    );
    if (!composed) {
      throw StateError(_lastError());
    }
  }

  /// Shows the kept canvas through the camera onto the pixels [rect] of
  /// [target] — [left, top, right, bottom) — leaving the rest of it as it
  /// was, and waits for the GPU; returns how many passes it took. The
  /// camera is [inverse] — a screen pixel to the canvas's, row-major with
  /// the homogeneous row last — over a screen of [columns] × [rows]
  /// pixels at display [scale], device pixels a canvas pixel, sampled by
  /// [sampling].
  int show(
    GpuTarget target, {
    required List<double> inverse,
    required double scale,
    required GpuSampling sampling,
    required int columns,
    required int rows,
    required (int, int, int, int) rect,
  }) {
    if (inverse.length != 9) {
      throw ArgumentError('an inverse of ${inverse.length}, not 9');
    }
    return _checked(
      using(
        (arena) => rust.screenShow(
          _screen,
          _composite._composite,
          _composite._engine._engine,
          _doubles(arena, inverse),
          scale,
          sampling.id,
          columns,
          rows,
          target._texture,
          _edges(arena, rect),
        ),
      ),
    );
  }

  /// Frees the screen; before its executor is.
  void free() => rust.screenFree(_screen);
}

/// What a run put: its output tiles' pixels, on the GPU.
class GpuComposited {
  GpuComposited._(this._engine, this._composited, this.tiles);

  final GpuEngine _engine;
  final Pointer<rust.Composited> _composited;

  /// How many output tiles it put.
  final int tiles;

  /// Its pixels once the GPU is done — straight RGBA8, tile after tile in
  /// the order asked, each [gpuTileSide] rows of [gpuTileSide].
  Uint8List read() => using((arena) {
    final count = rust.compositedBytes(tiles);
    final bytes = arena<Uint8>(_held(count));
    // ⚠️No test reaches the throw: a read fails only where the device does.
    if (!rust.compositedRead(_engine._engine, _composited, bytes, count)) {
      throw StateError(_lastError());
    }
    return Uint8List.fromList(bytes.asTypedList(count));
  });

  void free() => rust.compositedFree(_composited);
}

/// The export's conversions of a frame a run put, on the GPU before its
/// readback (gpu-export-path ①), each pass compiled where it is first
/// asked. A frame is a [GpuComposited] over its picture's tiles, row by
/// row from its top-left tile; the picture is its width × height from the
/// frame's top-left pixel.
class GpuExport {
  /// The export's passes on [engine], none compiled yet.
  GpuExport(GpuEngine engine)
    : _engine = engine,
      _export = rust.exportNew();

  final GpuEngine _engine;
  final Pointer<rust.Export> _export;

  /// The picture of [width] × [height] in [frame] as an encoder's NV12
  /// frame of [frameWidth] × [frameHeight], rows [stride] bytes apart —
  /// the writer's frame as it opened its encoder: `frameHeight` Y rows,
  /// then `frameHeight / 2` CbCr rows.
  GpuReadout nv12(
    GpuComposited frame,
    int width,
    int height, {
    required int frameWidth,
    required int frameHeight,
    required int stride,
  }) => _readout(
    using((arena) {
      final words = [width, height, frameWidth, frameHeight, stride];
      final shape = arena<Uint32>(5)..asTypedList(5).setAll(0, words);
      return rust.exportNv12(
        _export,
        _engine._engine,
        frame._composited,
        shape,
      );
    }),
  );

  /// The picture of [width] × [height] in [frame] over [ground] —
  /// B<<16|G<<8|R — three bytes a pixel, row after row with nothing
  /// between; its alpha cut at [cut] where a GIF cuts it (null: its
  /// shades; 0: a GIF with no clear colour).
  GpuReadout overGround(
    GpuComposited frame,
    int width,
    int height,
    int ground, {
    int? cut,
  }) => _readout(
    rust.exportOverGround(
      _export,
      _engine._engine,
      frame._composited,
      width,
      height,
      ground,
      cut ?? -1,
    ),
  );

  /// The pixels of the picture of [width] × [height] in [frame] whose
  /// alpha is under [cut]: pixel i is bit i % 8 of byte i ~/ 8, low bit
  /// first, row after row with nothing between.
  GpuReadout clear(GpuComposited frame, int width, int height, int cut) =>
      _readout(
        rust.exportClear(
          _export,
          _engine._engine,
          frame._composited,
          width,
          height,
          cut,
        ),
      );

  /// Whether every pixel of the picture of [width] × [height] in [frame]
  /// is opaque, once the GPU is done.
  bool opaque(GpuComposited frame, int width, int height) {
    final readout = _readout(
      rust.exportOpaque(
        _export,
        _engine._engine,
        frame._composited,
        width,
        height,
      ),
    );
    try {
      return using((arena) {
        final word = arena<Uint8>(4);
        readout
          ..map()
          ..rows(
            word,
            offset: 0,
            stride: 4,
            rowBytes: 4,
            rows: 1,
            dstStride: 4,
          );
        final answer = ByteData.sublistView(word.asTypedList(4));
        return answer.getUint32(0, Endian.little) == 255;
      });
    } finally {
      readout.free();
    }
  }

  /// The rows of a PNG of the picture of [width] × [height] in [frame],
  /// four bytes a pixel, under their filters: each its filter's byte and
  /// its own, [pngRowBytes] from the last.
  GpuReadout pngRgba(GpuComposited frame, int width, int height) => _readout(
    rust.exportPngRgba(
      _export,
      _engine._engine,
      frame._composited,
      width,
      height,
    ),
  );

  /// [pngRgba] for a PNG of three bytes a pixel, from [rgb] — what
  /// [overGround] put for the same picture, which stays on the GPU.
  GpuReadout pngRgb(GpuReadout rgb, int width, int height) => _readout(
    rust.exportPngRgb(_export, _engine._engine, rgb._readout, width, height),
  );

  /// Where each of a PNG's filtered rows starts from the last's, for a
  /// picture [width] wide of [pixelBytes] a pixel.
  static int pngRowBytes(int width, int pixelBytes) =>
      rust.exportPngRowBytes(width, pixelBytes);

  GpuReadout _readout(Pointer<rust.Readout> readout) {
    if (readout == nullptr) {
      throw StateError(_lastError());
    }
    return GpuReadout._(_engine, readout);
  }

  /// Frees the passes; before their engine is closed.
  void free() => rust.exportFree(_export);
}

/// What a conversion put: on the GPU until it is mapped, then copied row
/// by row straight into wherever its writer takes it.
class GpuReadout {
  GpuReadout._(this._engine, this._readout);

  final GpuEngine _engine;
  final Pointer<rust.Readout> _readout;

  /// The bytes of it its writer takes.
  int get bytes => rust.readoutBytes(_readout);

  /// Waits for the GPU and maps its bytes — once: a second call finds
  /// them mapped.
  void map() {
    if (!rust.readoutMap(_engine._engine, _readout)) {
      throw StateError(_lastError());
    }
  }

  /// Copies [rows] rows of [rowBytes] — the first at [offset], each
  /// [stride] from the last — into [dst], each [dstStride] from the last.
  /// It is mapped, and the rows end within its [bytes].
  void rows(
    Pointer<Uint8> dst, {
    required int offset,
    required int stride,
    required int rowBytes,
    required int rows,
    required int dstStride,
  }) {
    final copied = rust.readoutRows(
      _readout,
      offset,
      stride,
      rowBytes,
      rows,
      dst,
      dstStride,
    );
    if (!copied) {
      throw StateError(_lastError());
    }
  }

  void free() => rust.readoutFree(_readout);
}

/// A walked tile's ink: where it is on its cel's grid, and its box —
/// tile-local, the far edges past the last column and row with ink — or
/// null where it holds none.
typedef GpuTileInk = ({
  int column,
  int row,
  ({int left, int top, int right, int bottom})? box,
});

/// The words the scan puts for a walked tile (cel_pixel/abi.rs's
/// TILE_INK_WORDS): its column and row, then its box's four edges — four 0s
/// where it holds no ink.
const _tileInkWords = 6;

/// The ink scan (rust/src/kernels/cel_pixel/ink.rs): where each of a cel's
/// tiles on the pool holds ink, as the app's `TileInkBounds` says it.
class GpuInk {
  /// The scan on [engine], compiled.
  factory GpuInk(GpuEngine engine) {
    final ink = rust.inkNew(engine._engine);
    if (ink == nullptr) {
      throw StateError(_lastError());
    }
    return GpuInk._(engine, ink);
  }

  GpuInk._(this._engine, this._ink);

  final GpuEngine _engine;
  final Pointer<rust.Ink> _ink;

  /// Each tile of the cel of [columns] × [rows] tiles whose top-left is
  /// column [x0], row [y0] — [tiles] of [pool] row by row, null for one it
  /// has none of — and its ink, in that order, the tiles it has none of
  /// left out. Waits for the GPU.
  List<GpuTileInk> run(
    GpuPool pool,
    int x0,
    int y0,
    int columns,
    int rows,
    List<GpuTile?> tiles,
  ) => using((arena) {
    final words = _tileWords(arena, columns, rows, tiles);
    final capacity = tiles.nonNulls.length * _tileInkWords;
    final out = arena<Int32>(_held(capacity));
    final walked = rust.inkRun(
      _ink,
      _engine._engine,
      pool._pool,
      x0,
      y0,
      columns,
      rows,
      words,
      out,
      capacity,
    );
    if (walked < 0) {
      throw StateError(_lastError());
    }
    final put = out.asTypedList(capacity);
    return [
      for (var tile = 0; tile < walked; tile++)
        _walkedAt(put, tile * _tileInkWords),
    ];
  });

  void free() => rust.inkFree(_ink);
}

/// The faces letters are set in (rust/src/kernels/letters/glyphs.rs): each
/// family's files, the families in the order a letter goes down them.
class GpuFaces {
  /// [families], each one's files read whole — copied for the engine,
  /// which keeps them.
  factory GpuFaces(List<List<Uint8List>> families) {
    final files = [
      for (final (family, files) in families.indexed)
        for (final file in files) (family: family, bytes: file),
    ];
    final faces = using((arena) {
      final count = _held(files.length);
      final at = arena<Pointer<Uint8>>(count);
      final lengths = arena<UintPtr>(count);
      final named = arena<Uint32>(count);
      for (final (index, file) in files.indexed) {
        final bytes = file.bytes;
        at[index] = arena<Uint8>(_held(bytes.length))
          ..asTypedList(bytes.length).setAll(0, bytes);
        lengths[index] = bytes.length;
        named[index] = file.family;
      }
      return rust.facesNew(at, lengths, named, files.length);
    });
    if (faces == nullptr) {
      throw StateError(_lastError());
    }
    return GpuFaces._(faces);
  }

  GpuFaces._(this._faces);

  final Pointer<rust.Faces> _faces;

  /// These families in the order [order] names them, each by where it
  /// stands in this one — sharing their files, and freed on its own,
  /// before or after these.
  GpuFaces ordered(List<int> order) {
    final faces = using((arena) {
      final at = arena<Uint32>(_held(order.length));
      at.asTypedList(order.length).setAll(0, order);
      return rust.facesOrdered(_faces, at, order.length);
    });
    if (faces == nullptr) {
      throw StateError(_lastError());
    }
    return GpuFaces._(faces);
  }

  void free() => rust.facesFree(_faces);
}

/// A cluster of letters as the app's layout set it: its text, its box's
/// left and its line's baseline — 64ths of a px.
typedef GpuCluster = ({String text, int x, int y});

/// A PICTURE OF LETTERS (rust/src/kernels/letters): passes bottom to top,
/// each of runs of letters as the app's layout set them and of boxes and
/// lines, set in [GpuFaces] on the GPU into the straight RGBA8 tiles of one
/// rectangle of the grid. Where a shape stands in the layout is the six
/// floats a, b, c, d, e, f: x' = a·x + c·y + e, y' = b·x + d·y + f.
class GpuLetters {
  GpuLetters() : _letters = rust.lettersNew();

  final Pointer<rust.Lettering> _letters;

  /// Begins a pass over the ones before it: its shapes in [colour] —
  /// straight RGBA8, A<<24|B<<16|G<<8|R, its alpha the pass's strength —
  /// cut [hard] or not, filled where [outline] is 0 and else outlined that
  /// wide, 64ths of a px.
  void pass(int colour, {required bool hard, int outline = 0}) =>
      _done(rust.lettersPass(_letters, colour, hard, outline));

  /// Adds to the pass begun last a run of [clusters] in one style — [size]
  /// 64ths of a px — standing in the layout where [at] puts its own space.
  /// [weight] is a `FontWeight`'s value.
  void run(
    List<double> at, {
    required int size,
    required int weight,
    required bool italic,
    required List<GpuCluster> clusters,
  }) => using((arena) {
    final (:text, :length, :ends, :origins) = _clustered(arena, clusters);
    _done(
      rust.lettersRun(
        _letters,
        _floats(arena, _six(at)),
        size,
        weight,
        italic,
        text,
        length,
        ends,
        origins,
        clusters.length,
      ),
    );
  });

  /// Adds to the pass begun last a box or a line — [rect], [left, top,
  /// right, bottom), 64ths of a px — standing in the layout where [at] puts
  /// its own space.
  void rect(List<double> at, (int, int, int, int) rect) => using(
    (arena) => _done(
      rust.lettersRect(_letters, _floats(arena, _six(at)), _rect(arena, rect)),
    ),
  );

  /// The letters set in [faces] and laid on the grid by [toGrid] — the
  /// layout's space to the grid's — by [composite]; the work submitted.
  /// Null for letters that cover no pixel.
  GpuLettered? set(
    GpuComposite composite,
    GpuFaces faces,
    List<double> toGrid,
  ) => using((arena) {
    final rect = arena<Int32>(4)..asTypedList(4).fillRange(0, 4, -1);
    final lettered = rust.lettersSet(
      _letters,
      composite._engine._engine,
      composite._composite,
      faces._faces,
      _floats(arena, _six(toGrid)),
      rect,
    );
    final [x0, y0, columns, rows] = rect.asTypedList(4).toList();
    if (lettered == nullptr) {
      return columns == 0 ? null : throw StateError(_lastError());
    }
    return GpuLettered._(composite._engine, lettered, (
      x0: x0,
      y0: y0,
      columns: columns,
      rows: rows,
    ));
  });

  void free() => rust.lettersFree(_letters);
}

/// [clusters] as a run is handed them, in [arena]'s: their letters as
/// UTF-8, [length] bytes, the i-th ending at `ends[i]` and set at
/// `origins[2i]`, `origins[2i + 1]`.
({
  Pointer<Uint8> text,
  int length,
  Pointer<Uint32> ends,
  Pointer<Int32> origins,
})
_clustered(Arena arena, List<GpuCluster> clusters) {
  final text = <int>[];
  final ends = arena<Uint32>(_held(clusters.length));
  final origins = arena<Int32>(_held(2 * clusters.length));
  for (final (index, cluster) in clusters.indexed) {
    text.addAll(utf8.encode(cluster.text));
    ends[index] = text.length;
    origins[2 * index] = cluster.x;
    origins[2 * index + 1] = cluster.y;
  }
  final bytes = arena<Uint8>(_held(text.length))
    ..asTypedList(text.length).setAll(0, text);
  return (text: bytes, length: text.length, ends: ends, origins: origins);
}

/// A WORD OF THE APP'S OWN SCREENS (rust/src/kernels/letters/words.rs): its
/// runs as the app's layout set them, baked into the coverage of its final
/// device pixels — what a frame grid's tile reads its letters from
/// ([GpuGrid.draw]) and what a screen draws a narrowed word from. No GPU
/// is asked: the bake is the engine's, on the CPU.
class GpuWord {
  GpuWord() : _word = rust.wordNew();

  final Pointer<rust.Wording> _word;

  /// Adds a run of [clusters] in one style — [size] 64ths of a px,
  /// [weight] a `FontWeight`'s value — where the word's layout set it.
  void run({
    required int size,
    required int weight,
    required bool italic,
    required List<GpuCluster> clusters,
  }) => using((arena) {
    final (:text, :length, :ends, :origins) = _clustered(arena, clusters);
    _done(
      rust.wordRun(
        _word,
        size,
        weight,
        italic,
        text,
        length,
        ends,
        origins,
        clusters.length,
      ),
    );
  });

  /// The word — its box [width] × [height] px of its layout — set in
  /// [faces] at [dpr] device pixels a px, rastered [times] times over and
  /// narrowed to [along] and [down] of itself, each over 0 and 1 at the
  /// most; null where the bake refuses it, and the word is painted as it
  /// always was.
  GpuWordCover? bake(
    GpuFaces faces, {
    required double dpr,
    required int times,
    required double width,
    required double height,
    required double along,
    required double down,
  }) {
    final cover = rust.wordBake(
      _word,
      faces._faces,
      dpr,
      times,
      width,
      height,
      along,
      down,
    );
    return cover == nullptr ? null : GpuWordCover._(cover);
  }

  void free() => rust.wordFree(_word);
}

/// A word's coverage ([GpuWord.bake]): a byte a pixel, [width] ×
/// [height] row by row, a pixel of margin round its ink.
class GpuWordCover {
  factory GpuWordCover._(Pointer<rust.WordCover> cover) => using((arena) {
    final size = arena<Uint32>(2);
    rust.wordCoverSize(cover, size);
    return GpuWordCover._sized(cover, size[0], size[1]);
  });

  GpuWordCover._sized(this._cover, this.width, this.height);

  final Pointer<rust.WordCover> _cover;
  final int width;
  final int height;

  /// Its bytes, row by row.
  Uint8List read() => using((arena) {
    final count = width * height;
    final bytes = arena<Uint8>(_held(count));
    rust.wordCoverRead(_cover, bytes, count);
    return Uint8List.fromList(bytes.asTypedList(count));
  });

  void free() => rust.wordCoverFree(_cover);
}

/// The A8 atlas a frame grid's tile reads its letters from: [alpha], row
/// by row, [width] across and [height] down.
typedef GpuGridAtlas = ({Uint8List alpha, int width, int height});

/// THE FRAME GRID'S TILE PASS (rust/src/kernels/timeline/grid): a tile's op
/// stream — `TimelineGridTileOpWriter`'s words — drawn into a picture the
/// engine keeps, for the view's screen to lay.
class GpuGrid {
  GpuGrid(this._engine) : _grid = rust.gridNew(_engine._engine);

  final GpuEngine _engine;
  final Pointer<rust.Grid> _grid;

  /// Draws [ops] into [picture] over clear, its letters read from [atlas]
  /// where its GLYPH ops say — submitted, not waited for: what reads the
  /// picture after ([GpuGridLay.lay], [GpuGridPicture.read]) waits. Throws
  /// for a stream the pass refuses.
  void draw(GpuGridPicture picture, Int32List ops, {GpuGridAtlas? atlas}) =>
      using((arena) {
        final stream = arena<Int32>(_held(ops.length))
          ..asTypedList(ops.length).setAll(0, ops);
        final alpha = atlas?.alpha ?? Uint8List(0);
        if (atlas != null && alpha.length != atlas.width * atlas.height) {
          // The engine reads width × height bytes of it.
          throw ArgumentError(
            'an atlas ${atlas.width} × ${atlas.height} of ${alpha.length} '
            'bytes',
          );
        }
        final bytes = arena<Uint8>(_held(alpha.length))
          ..asTypedList(alpha.length).setAll(0, alpha);
        _done(
          rust.gridDraw(
            _grid,
            _engine._engine,
            picture._picture,
            stream,
            ops.length,
            bytes,
            atlas?.width ?? 0,
            atlas?.height ?? 0,
          ),
        );
      });

  void free() => rust.gridFree(_grid);
}

/// A frame grid's tile as the engine keeps it: [width] × [height] pixels,
/// straight, drawn by [GpuGrid.draw] and laid by [GpuGridLay.lay].
class GpuGridPicture {
  factory GpuGridPicture(GpuEngine engine, int width, int height) {
    final picture = rust.gridPictureNew(engine._engine, width, height);
    if (picture == nullptr) {
      throw StateError(_lastError());
    }
    return GpuGridPicture._(engine, picture, width, height);
  }

  GpuGridPicture._(this._engine, this._picture, this.width, this.height);

  final GpuEngine _engine;
  final Pointer<rust.GridPicture> _picture;
  final int width;
  final int height;

  /// Its pixels once the GPU is done — straight RGBA8, row by row.
  Uint8List read() => using((arena) {
    final count = width * height * 4;
    final bytes = arena<Uint8>(_held(count));
    // ⚠️No test reaches the throw: a read fails only where the device does.
    if (!rust.gridPictureRead(_engine._engine, _picture, bytes, count)) {
      throw StateError(_lastError());
    }
    return Uint8List.fromList(bytes.asTypedList(count));
  });

  void free() => rust.gridPictureFree(_picture);
}

/// A tile laid on a view's screen: the part [from] of its [picture], in its
/// pixels, onto the part [onto] of the screen, in the screen's — each
/// (left, top, right, bottom).
typedef GpuGridLaid = ({
  GpuGridPicture picture,
  (double, double, double, double) from,
  (double, double, double, double) onto,
});

/// THE VIEW'S SCREEN OF FRAME GRID TILES (rust/src/kernels/timeline/grid/
/// lay.rs): the tiles a sheet's rows lay, onto what the view shows.
class GpuGridLay {
  GpuGridLay(this._engine) : _lay = rust.gridLayNew();

  final GpuEngine _engine;
  final Pointer<rust.GridLay> _lay;

  /// The pixels [rect] of [target] — (left, top, right, bottom) — clear,
  /// and each of [laid] over the pixels whose centres its `onto` holds, a
  /// later one over an earlier; waits for the GPU. Throws for a rect past
  /// the target and a tile laid from past its picture or onto no box.
  void lay(
    GpuTarget target,
    (int, int, int, int) rect,
    List<GpuGridLaid> laid,
  ) => using((arena) {
    final (left, top, right, bottom) = rect;
    final edges = arena<Uint32>(4)
      ..asTypedList(4).setAll(0, [left, top, right, bottom]);
    final pictures = arena<Pointer<rust.GridPicture>>(_held(laid.length));
    final boxes = arena<Double>(_held(8 * laid.length));
    for (final (index, (:picture, :from, :onto)) in laid.indexed) {
      pictures[index] = picture._picture;
      final (x0, y0, x1, y1) = from;
      final (u0, v0, u1, v1) = onto;
      boxes
          .asTypedList(8 * laid.length)
          .setAll(8 * index, [x0, y0, x1, y1, u0, v0, u1, v1]);
    }
    _done(
      rust.gridLay(
        _lay,
        _engine._engine,
        target._texture,
        edges,
        pictures,
        boxes,
        laid.length,
      ),
    );
  });

  void free() => rust.gridLayFree(_lay);
}

/// [argb] — a `Color`'s, A<<24|R<<16|G<<8|B — as the engine's colours
/// are: straight RGBA8, A<<24|B<<16|G<<8|R.
int gpuColourOf(int argb) =>
    argb & 0xFF00FF00 | (argb >> 16 & 0xFF) | (argb & 0xFF) << 16;

/// [values] as floats of [arena]'s.
Pointer<Float> _floats(Arena arena, List<double> values) =>
    arena<Float>(_held(values.length))
      ..asTypedList(values.length).setAll(0, values);

/// [affine], checked to be the six floats a placement is.
List<double> _six(List<double> affine) {
  if (affine.length != 6) {
    throw ArgumentError('a placement of ${affine.length}, not 6');
  }
  return affine;
}

/// What a C entry answering whether it did answered: nothing, or its last
/// error thrown.
void _done(bool done) {
  if (!done) {
    throw StateError(_lastError());
  }
}

/// A picture of letters set ([GpuLetters.set]): the straight RGBA8 tiles of
/// [rect] — its first tile's column and row, and how many columns and rows
/// of tiles it spans — on the GPU.
class GpuLettered {
  GpuLettered._(this._engine, this._lettered, this.rect);

  final GpuEngine _engine;
  final Pointer<rust.Lettered> _lettered;
  final ({int x0, int y0, int columns, int rows}) rect;

  /// Its pixels once the GPU is done — tile after tile, row by row of
  /// [rect], each [gpuTileSide] rows of [gpuTileSide].
  Uint8List read() => using((arena) {
    final count = rect.columns * rect.rows * gpuTileBytes;
    final bytes = arena<Uint8>(_held(count));
    // ⚠️No test reaches the throw: a read fails only where the device does.
    if (!rust.letteredRead(_engine._engine, _lettered, bytes, count)) {
      throw StateError(_lastError());
    }
    return Uint8List.fromList(bytes.asTypedList(count));
  });

  void free() => rust.letteredFree(_lettered);
}

/// The walked tile whose words start at [at] of [words].
GpuTileInk _walkedAt(Int32List words, int at) {
  final [column, row, left, top, right, bottom] = words.sublist(
    at,
    at + _tileInkWords,
  );
  return (
    column: column,
    row: row,
    box: right > left
        ? (left: left, top: top, right: right, bottom: bottom)
        : null,
  );
}

/// The fingerprint of [bytes] by the engine's own code — for bytes read off
/// Flutter's screen, so they are compared as the GPU's are.
int fingerprintBytes(Uint8List bytes) => using((arena) {
  final buffer = arena<Uint8>(bytes.length);
  buffer.asTypedList(bytes.length).setAll(0, bytes);
  return rust.fingerprintBytes(buffer, bytes.length);
});

/// A Flutter texture the engine presents into: a SurfaceProducer's window,
/// whose images Flutter shows without a copy (Android).
class GpuWindow extends GpuTarget {
  GpuWindow._(super._engine, this._window, this.textureId);

  final Pointer<rust.Window> _window;

  /// What a `Texture` widget shows the window by.
  final int textureId;

  /// Whether the kernels store straight into the window's images; when
  /// not, each present copies the engine's own texture into one.
  bool get direct => rust.windowDirect(_window);

  /// The window's next image — [present] shows what a kernel wrote there.
  @override
  Pointer<rust.Texture> get _texture {
    final target = rust.windowTarget(_window);
    if (target == nullptr) {
      throw StateError(_lastError());
    }
    return target;
  }

  /// Hands the image a kernel last wrote ([fill], [GpuScreen.show]) to
  /// Flutter.
  void present() {
    if (!rust.windowPresent(_engine._engine, _window)) {
      throw StateError(_lastError());
    }
  }

  /// Frees the swapchain, then Flutter's producer: the window it presents
  /// into must outlive it.
  Future<void> free() async {
    rust.windowFree(_window);
    await _plugin.invokeMethod<void>('release', {'textureId': textureId});
  }
}

/// A Flutter external texture that shows [front], or [back] once
/// [show] picks slot 1 — Windows', iOS', macOS' and Linux' way to the
/// screen: the engine makes the texture, Flutter shows it.
class SharedTexture {
  SharedTexture._(this.id);

  factory SharedTexture.register(GpuSurface front, {GpuSurface? back}) {
    final id = shim.textureRegister(
      front._handle,
      back?._handle ?? nullptr,
      front.width,
      front.height,
      front.bgra,
    );
    if (id < 0) {
      throw StateError('Flutter refused the texture');
    }
    return SharedTexture._(id);
  }

  final int id;

  /// Shows slot 0 (front) or 1 (back) on the next frame.
  bool show(int slot) => shim.textureShow(id, slot);

  /// Flutter must no longer show the texture: on Linux nothing tells the
  /// plugin when Flutter stops drawing it (linux/gpu_engine_plugin.cc).
  void unregister() => shim.textureUnregister(id);
}
