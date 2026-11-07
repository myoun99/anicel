/// Anicel's GPU engine: one wgpu device on the adapter Flutter draws with,
/// the pool the app's tiles are stored in, and its kernels
/// (gpu-engine-skeleton, screen-on-the-engine).
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

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

/// A texture the compute pass fills and Flutter shows.
class GpuSurface {
  GpuSurface._(this._engine, this._surface, this.width, this.height, this.bgra);

  final GpuEngine _engine;
  final Pointer<rust.Surface> _surface;
  final int width;
  final int height;
  final bool bgra;

  Pointer<Void> get _handle => rust.surfaceHandle(_surface);

  /// Fills the surface with the pattern for [seed] and waits for the GPU;
  /// returns the submit-to-done time.
  Duration fill(int seed) => _ran(
    rust.fillRun(
      _engine._fillKernel,
      _engine._engine,
      rust.surfaceTexture(_surface),
      seed,
    ),
  );

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

  /// A cel of its own: the tiles stored under it keep to pages of theirs.
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

  /// Frees the pool's pages; before its engine is closed.
  void free() => rust.poolFree(_pool);
}

/// How a row's pose samples its pixels: R1's modes, by the engine's ids.
enum GpuSampling {
  /// The tent mean — a reduction's.
  blend(0),

  /// The area vote: the one source pixel covering most of the preimage.
  pick(1),

  /// The one source pixel where the pixel's centre lands.
  nearest(3);

  const GpuSampling(this.id);

  final int id;
}

/// A plan the executor runs, built step by step, bottom to top
/// (rust/src/kernels/composite/abi.rs): tile sets of the pool, colour
/// matrices, and rows, folders, clips and solid colours laying them. The
/// executor checks it where it runs.
class GpuPlan {
  GpuPlan() : _plan = rust.planNew();

  final Pointer<rust.Planned> _plan;

  /// Adds the tile set of [columns] × [rows] canvas tiles whose top-left is
  /// column [x0], row [y0] — [tiles] row by row, null for one with nothing
  /// on it — and returns the index a row lays it by.
  int set(int x0, int y0, int columns, int rows, List<GpuTile?> tiles) {
    if (tiles.length != columns * rows) {
      throw ArgumentError('$columns × $rows tiles, not ${tiles.length}');
    }
    return using((arena) {
      final words = arena<Uint32>(_held(tiles.length));
      for (var at = 0; at < tiles.length; at++) {
        final tile = tiles[at];
        words[at] = tile == null ? _noTile : tile.page << 16 | tile.slot;
      }
      return rust.planSet(_plan, x0, y0, columns, rows, words);
    });
  }

  /// Adds the colour matrix of [matrix] — `ColorFilter.matrix`'s twenty —
  /// and returns the index a row or a close runs it by.
  int matrix(List<double> matrix) {
    if (matrix.length != 20) {
      throw ArgumentError('a colour matrix of ${matrix.length}, not 20');
    }
    final at = using((arena) {
      final entries = arena<Double>(20);
      entries.asTypedList(20).setAll(0, matrix);
      return rust.planMatrix(_plan, entries);
    });
    if (at < 0) {
      throw StateError(_lastError());
    }
    return at;
  }

  /// Adds a row: tile set [set] posed by [inverse] — canvas pixel to the
  /// row's own, row-major with the homogeneous row last, over an output of
  /// [columns] × [rows] pixels — sampled by [sampling], Blend's radius at
  /// least [radiusFloor], through colour matrix [matrix] if any, laid at
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
    double radiusFloor = 1,
    int opacity = 65535,
  }) {
    if (inverse.length != 9) {
      throw ArgumentError('an inverse of ${inverse.length}, not 9');
    }
    final added = using((arena) {
      final entries = arena<Double>(9);
      entries.asTypedList(9).setAll(0, inverse);
      return rust.planRow(
        _plan,
        set,
        matrix ?? -1,
        entries,
        radiusFloor,
        sampling.id,
        columns,
        rows,
        opacity,
        mode,
      );
    });
    if (added < 0) {
      throw StateError(_lastError());
    }
    return added == 1;
  }

  /// Opens a transparent buffer — a folder's, a clip's base or its scope —
  /// or, where [opaque], one holding the buffer under it with its alpha
  /// made whole: a clip's scope whose rows blend with the base.
  void open({bool opaque = false}) => rust.planOpen(_plan, opaque);

  /// Closes the open buffer onto the one under it at [opacity] in [mode],
  /// through colour matrix [matrix] if any.
  void close({required int mode, int opacity = 65535, int? matrix}) =>
      rust.planClose(_plan, opacity, mode, matrix ?? -1);

  /// Closes a clip's scope onto its base by the base's alpha.
  void closeAtop() => rust.planCloseAtop(_plan);

  /// Lays [colour] — straight RGBA8, A<<24|B<<16|G<<8|R — over the canvas
  /// pixels [[left], [top], [right], [bottom]) in normal.
  void solid(int colour, int left, int top, int right, int bottom) =>
      rust.planSolid(_plan, colour, left, top, right, bottom);

  void free() => rust.planFree(_plan);
}

/// A tile with nothing on it, as a tile set names one.
const _noTile = 0xFFFFFFFF;

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
      final edges = arena<Int32>(4);
      final (left, top, right, bottom) = extent;
      edges.asTypedList(4).setAll(0, [left, top, right, bottom]);
      return rust.compositeRun(
        _composite,
        _engine._engine,
        pool._pool,
        plan._plan,
        at,
        tiles.length,
        edges,
      );
    });
    if (out == nullptr) {
      throw StateError(_lastError());
    }
    return GpuComposited._(_engine, out, tiles.length);
  }

  /// Composites [plan] of [pool]'s tiles onto the pixels [rect] of
  /// [surface] — [left, top, right, bottom) — leaving the rest of it as it
  /// was, and submits the work; returns how many passes it took.
  int show(
    GpuPool pool,
    GpuPlan plan,
    GpuSurface surface,
    (int, int, int, int) rect,
  ) {
    final passes = using((arena) {
      final edges = arena<Uint32>(4);
      final (left, top, right, bottom) = rect;
      edges.asTypedList(4).setAll(0, [left, top, right, bottom]);
      return rust.compositeShow(
        _composite,
        _engine._engine,
        pool._pool,
        plan._plan,
        surface._surface,
        edges,
      );
    });
    if (passes < 0) {
      throw StateError(_lastError());
    }
    return passes;
  }

  /// Frees the executor; before its engine is closed.
  void free() => rust.compositeFree(_composite);
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
    if (!rust.compositedRead(_engine._engine, _composited, bytes, count)) {
      throw StateError(_lastError());
    }
    return Uint8List.fromList(bytes.asTypedList(count));
  });

  void free() => rust.compositedFree(_composited);
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
class GpuWindow {
  GpuWindow._(this._engine, this._window, this.textureId);

  final GpuEngine _engine;
  final Pointer<rust.Window> _window;

  /// What a `Texture` widget shows the window by.
  final int textureId;

  /// Whether the kernels store straight into the window's images; when
  /// not, each present copies the engine's own texture into one.
  bool get direct => rust.windowDirect(_window);

  /// Fills the window's next image with the pattern for [seed] and waits
  /// for the GPU; returns the submit-to-done time. [present] shows it.
  Duration fill(int seed) {
    final target = rust.windowTarget(_window);
    if (target == nullptr) {
      throw StateError(_lastError());
    }
    return _ran(
      rust.fillRun(_engine._fillKernel, _engine._engine, target, seed),
    );
  }

  /// Hands the image [fill] wrote to Flutter.
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
