// Bindings to the Rust engine (rust/src/lib.rs). hook/build.dart ships the
// crate as this library's code asset, which is what @Native resolves to.
import 'dart:ffi';

final class Engine extends Opaque {}

final class Surface extends Opaque {}

@Native<Pointer<Engine> Function(Uint64)>(symbol: 'gpu_engine_open')
external Pointer<Engine> engineOpen(int luid);

@Native<Void Function(Pointer<Engine>)>(symbol: 'gpu_engine_close')
external void engineClose(Pointer<Engine> engine);

@Native<Size Function(Pointer<Engine>, Pointer<Uint8>, Size)>(
  symbol: 'gpu_engine_adapter_name',
)
external int engineAdapterName(
  Pointer<Engine> engine,
  Pointer<Uint8> buffer,
  int capacity,
);

@Native<Uint64 Function(Pointer<Engine>)>(symbol: 'gpu_engine_video_memory')
external int engineVideoMemory(Pointer<Engine> engine);

@Native<Pointer<Surface> Function(Pointer<Engine>, Uint32, Uint32, Bool)>(
  symbol: 'gpu_engine_surface_new',
)
external Pointer<Surface> surfaceNew(
  Pointer<Engine> engine,
  int width,
  int height,
  bool bgra,
);

@Native<Void Function(Pointer<Surface>)>(symbol: 'gpu_engine_surface_free')
external void surfaceFree(Pointer<Surface> surface);

@Native<Pointer<Void> Function(Pointer<Surface>)>(
  symbol: 'gpu_engine_surface_handle',
)
external Pointer<Void> surfaceHandle(Pointer<Surface> surface);

@Native<Int64 Function(Pointer<Engine>, Pointer<Surface>, Uint32)>(
  symbol: 'gpu_engine_fill',
)
external int surfaceFill(
  Pointer<Engine> engine,
  Pointer<Surface> surface,
  int seed,
);

@Native<Bool Function(Pointer<Engine>, Pointer<Surface>, Pointer<Uint64>)>(
  symbol: 'gpu_engine_read_hash',
)
external bool surfaceReadHash(
  Pointer<Engine> engine,
  Pointer<Surface> surface,
  Pointer<Uint64> hash,
);

@Native<Uint64 Function(Uint32, Uint32, Uint32, Bool)>(
  symbol: 'gpu_engine_expected_hash',
)
external int expectedHash(int width, int height, int seed, bool bgra);

@Native<Uint64 Function(Pointer<Uint8>, Size)>(symbol: 'gpu_engine_hash_bytes')
external int hashBytes(Pointer<Uint8> bytes, int length);

@Native<Size Function(Pointer<Uint8>, Size)>(symbol: 'gpu_engine_last_error')
external int lastError(Pointer<Uint8> buffer, int capacity);
