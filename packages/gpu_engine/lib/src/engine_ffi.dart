// Bindings to the Rust engine (rust/src/). hook/build.dart ships the crate
// as this library's code asset, which is what @Native resolves to.
import 'dart:ffi';

final class Engine extends Opaque {}

final class Surface extends Opaque {}

final class Fill extends Opaque {}

/// The texture a kernel writes: a surface's, or a window's next image.
final class Texture extends Opaque {}

final class Window extends Opaque {}

@Native<Pointer<Engine> Function(Uint64)>(symbol: 'gpu_engine_open')
external Pointer<Engine> engineOpen(int luid);

@Native<Pointer<Engine> Function()>(symbol: 'gpu_engine_open_sole')
external Pointer<Engine> engineOpenSole();

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

@Native<Pointer<Texture> Function(Pointer<Surface>)>(
  symbol: 'gpu_engine_surface_texture',
)
external Pointer<Texture> surfaceTexture(Pointer<Surface> surface);

@Native<
  Pointer<Window> Function(Pointer<Engine>, Pointer<Void>, Uint32, Uint32)
>(symbol: 'gpu_engine_window_new')
external Pointer<Window> windowNew(
  Pointer<Engine> engine,
  Pointer<Void> native,
  int width,
  int height,
);

@Native<Bool Function(Pointer<Window>)>(symbol: 'gpu_engine_window_direct')
external bool windowDirect(Pointer<Window> window);

@Native<Pointer<Texture> Function(Pointer<Window>)>(
  symbol: 'gpu_engine_window_target',
)
external Pointer<Texture> windowTarget(Pointer<Window> window);

@Native<Bool Function(Pointer<Engine>, Pointer<Window>)>(
  symbol: 'gpu_engine_window_present',
)
external bool windowPresent(Pointer<Engine> engine, Pointer<Window> window);

@Native<Void Function(Pointer<Window>)>(symbol: 'gpu_engine_window_free')
external void windowFree(Pointer<Window> window);

@Native<Pointer<Fill> Function(Pointer<Engine>)>(symbol: 'gpu_engine_fill_new')
external Pointer<Fill> fillNew(Pointer<Engine> engine);

@Native<Void Function(Pointer<Fill>)>(symbol: 'gpu_engine_fill_free')
external void fillFree(Pointer<Fill> fill);

@Native<
  Int64 Function(Pointer<Fill>, Pointer<Engine>, Pointer<Texture>, Uint32)
>(symbol: 'gpu_engine_fill_run')
external int fillRun(
  Pointer<Fill> fill,
  Pointer<Engine> engine,
  Pointer<Texture> texture,
  int seed,
);

@Native<Bool Function(Pointer<Engine>, Pointer<Surface>, Pointer<Uint32>)>(
  symbol: 'gpu_engine_surface_fingerprint',
)
external bool surfaceFingerprint(
  Pointer<Engine> engine,
  Pointer<Surface> surface,
  Pointer<Uint32> fingerprint,
);

@Native<Uint32 Function(Pointer<Uint8>, Size)>(
  symbol: 'gpu_engine_fingerprint_bytes',
)
external int fingerprintBytes(Pointer<Uint8> bytes, int length);

@Native<Size Function(Pointer<Uint8>, Size)>(symbol: 'gpu_engine_last_error')
external int lastError(Pointer<Uint8> buffer, int capacity);
