/// Anicel's GPU engine, stage 0 (gpu-engine-skeleton): measurement only —
/// nothing in the app uses it yet.
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'src/engine_ffi.dart' as rust;
import 'src/texture_shim.dart' as shim;

String _lastError() => using((arena) {
  const capacity = 1024;
  final buffer = arena<Uint8>(capacity);
  final length = rust.lastError(buffer, capacity);
  final count = length < capacity ? length : capacity;
  return utf8.decode(buffer.asTypedList(count), allowMalformed: true);
});

/// One wgpu device on the adapter Flutter draws with.
class GpuEngine {
  GpuEngine._(this._engine, this.adapterLuid);

  /// Opens on Flutter's own adapter, so the shared texture lives on the
  /// GPU that shows it.
  factory GpuEngine.onFlutterAdapter() {
    final luid = shim.flutterAdapterLuid();
    if (luid == 0) {
      throw StateError('Flutter gave no graphics adapter');
    }
    final engine = rust.engineOpen(luid);
    if (engine == nullptr) {
      throw StateError(_lastError());
    }
    return GpuEngine._(engine, luid);
  }

  final Pointer<rust.Engine> _engine;
  final int adapterLuid;

  String get adapterName => using((arena) {
    const capacity = 256;
    final buffer = arena<Uint8>(capacity);
    final length = rust.engineAdapterName(_engine, buffer, capacity);
    final count = length < capacity ? length : capacity;
    return utf8.decode(buffer.asTypedList(count), allowMalformed: true);
  });

  /// This process's use of the adapter's local video memory, in bytes.
  int get videoMemoryBytes => rust.engineVideoMemory(_engine);

  /// A texture of [width] × [height] 8-bit texels, BGRA when [bgra].
  GpuSurface surface(int width, int height, {required bool bgra}) {
    final surface = rust.surfaceNew(_engine, width, height, bgra);
    if (surface == nullptr) {
      throw StateError(_lastError());
    }
    return GpuSurface._(this, surface, width, height, bgra);
  }

  /// Frees the device; every surface must be freed first.
  void close() => rust.engineClose(_engine);
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
  Duration fill(int seed) {
    final nanos = rust.surfaceFill(_engine._engine, _surface, seed);
    if (nanos < 0) {
      throw StateError(_lastError());
    }
    return Duration(microseconds: nanos ~/ 1000);
  }

  /// The FNV-1a hash of the surface's bytes, read back from the GPU.
  int readHash() => using((arena) {
    final hash = arena<Uint64>();
    if (!rust.surfaceReadHash(_engine._engine, _surface, hash)) {
      throw StateError(_lastError());
    }
    return hash.value;
  });

  /// What a D3D11 device of Flutter's adapter sees when it opens the
  /// handle, as ANGLE will; null when it cannot open it.
  ({int format, int bindFlags, int miscFlags})? inspect() => using((arena) {
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

/// The hash a surface's bytes must have for [seed], worked out on the CPU.
int expectedSurfaceHash(int width, int height, int seed, {required bool bgra}) =>
    rust.expectedHash(width, height, seed, bgra);

/// The FNV-1a hash of [bytes], by the engine's own code.
int hashBytes(Uint8List bytes) => using((arena) {
  final buffer = arena<Uint8>(bytes.length);
  buffer.asTypedList(bytes.length).setAll(0, bytes);
  return rust.hashBytes(buffer, bytes.length);
});

/// A Flutter external texture that shows [front], or [back] once
/// [show] picks slot 1.
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

  void unregister() => shim.textureUnregister(id);
}
