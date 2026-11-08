// Bindings to the Rust engine (rust/src/). hook/build.dart ships the crate
// as this library's code asset, which is what @Native resolves to.
import 'dart:ffi';

final class Engine extends Opaque {}

final class Surface extends Opaque {}

final class Fill extends Opaque {}

/// The texture a kernel writes: a surface's, or a window's next image.
final class Texture extends Opaque {}

final class Window extends Opaque {}

final class Pool extends Opaque {}

final class Planned extends Opaque {}

final class Composite extends Opaque {}

final class Composited extends Opaque {}

final class Export extends Opaque {}

final class Readout extends Opaque {}

final class Ink extends Opaque {}

final class Faces extends Opaque {}

final class Lettering extends Opaque {}

final class Lettered extends Opaque {}

@Native<Pointer<Engine> Function(Uint64)>(symbol: 'gpu_engine_open')
external Pointer<Engine> engineOpen(int luid);

@Native<Pointer<Engine> Function()>(symbol: 'gpu_engine_open_sole')
external Pointer<Engine> engineOpenSole();

@Native<Pointer<Engine> Function()>(symbol: 'gpu_engine_open_first')
external Pointer<Engine> engineOpenFirst();

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

@Native<Uint32 Function()>(symbol: 'gpu_engine_tile_side')
external int tileSide();

@Native<Pointer<Pool> Function(Pointer<Engine>, Uint64)>(
  symbol: 'gpu_engine_pool_new',
)
external Pointer<Pool> poolNew(Pointer<Engine> engine, int mostBytes);

@Native<Void Function(Pointer<Pool>)>(symbol: 'gpu_engine_pool_free')
external void poolFree(Pointer<Pool> pool);

@Native<Uint32 Function(Pointer<Pool>)>(symbol: 'gpu_engine_pool_cel')
external int poolCel(Pointer<Pool> pool);

@Native<
  IntPtr Function(
    Pointer<Pool>,
    Pointer<Engine>,
    Uint32,
    Pointer<Pointer<Uint8>>,
    Size,
    Pointer<Uint16>,
    Pointer<Uint16>,
  )
>(symbol: 'gpu_engine_pool_store')
external int poolStore(
  Pointer<Pool> pool,
  Pointer<Engine> engine,
  int cel,
  Pointer<Pointer<Uint8>> tiles,
  int count,
  Pointer<Uint16> pages,
  Pointer<Uint16> slots,
);

@Native<Bool Function(Pointer<Pool>, Uint16, Uint16)>(
  symbol: 'gpu_engine_pool_release',
)
external bool poolRelease(Pointer<Pool> pool, int page, int slot);

@Native<Void Function(Pointer<Pool>, Uint64)>(
  symbol: 'gpu_engine_pool_most_bytes',
)
external void poolMostBytes(Pointer<Pool> pool, int mostBytes);

@Native<Void Function(Pointer<Pool>, Pointer<Engine>, Uint64)>(
  symbol: 'gpu_engine_pool_give_back',
)
external void poolGiveBack(
  Pointer<Pool> pool,
  Pointer<Engine> engine,
  int mostBytes,
);

@Native<Uint64 Function(Pointer<Pool>)>(symbol: 'gpu_engine_pool_bytes')
external int poolBytes(Pointer<Pool> pool);

@Native<Pointer<Planned> Function()>(symbol: 'gpu_engine_plan_new')
external Pointer<Planned> planNew();

@Native<Void Function(Pointer<Planned>)>(symbol: 'gpu_engine_plan_free')
external void planFree(Pointer<Planned> plan);

@Native<
  Uint32 Function(
    Pointer<Planned>,
    Int32,
    Int32,
    Uint32,
    Uint32,
    Pointer<Uint32>,
  )
>(symbol: 'gpu_engine_plan_set')
external int planSet(
  Pointer<Planned> plan,
  int x0,
  int y0,
  int columns,
  int rows,
  Pointer<Uint32> tiles,
);

@Native<Int32 Function(Pointer<Planned>, Pointer<Double>)>(
  symbol: 'gpu_engine_plan_matrix',
)
external int planMatrix(Pointer<Planned> plan, Pointer<Double> matrix);

@Native<
  Int32 Function(
    Pointer<Planned>,
    Uint32,
    Int32,
    Int32,
    Int32,
    Pointer<Double>,
    Double,
    Uint32,
    Uint32,
    Uint32,
    Uint32,
    Uint32,
  )
>(symbol: 'gpu_engine_plan_row')
external int planRow(
  Pointer<Planned> plan,
  int set,
  int matrix,
  int keys,
  int chain,
  Pointer<Double> inverse,
  double radiusFloor,
  int sampling,
  int columns,
  int rows,
  int opacity,
  int mode,
);

@Native<Void Function(Pointer<Planned>, Bool)>(symbol: 'gpu_engine_plan_open')
external void planOpen(Pointer<Planned> plan, bool opaque);

@Native<
  Void Function(Pointer<Planned>, Uint32, Uint32, Int32, Int32, Uint32)
>(symbol: 'gpu_engine_plan_close')
external void planClose(
  Pointer<Planned> plan,
  int opacity,
  int mode,
  int matrix,
  int chain,
  int mix,
);

@Native<Void Function(Pointer<Planned>)>(symbol: 'gpu_engine_plan_close_atop')
external void planCloseAtop(Pointer<Planned> plan);

@Native<Void Function(Pointer<Planned>, Uint32, Int32, Int32, Int32, Int32)>(
  symbol: 'gpu_engine_plan_solid',
)
external void planSolid(
  Pointer<Planned> plan,
  int colour,
  int left,
  int top,
  int right,
  int bottom,
);

@Native<Uint32 Function(Pointer<Planned>)>(symbol: 'gpu_engine_plan_keys')
external int planKeys(Pointer<Planned> plan);

@Native<
  Int32 Function(
    Pointer<Planned>,
    Uint32,
    Pointer<Uint32>,
    Pointer<Uint32>,
    Pointer<Uint32>,
    Uint32,
    Pointer<Uint8>,
    Uint32,
  )
>(symbol: 'gpu_engine_plan_key_run')
external int planKeyRun(
  Pointer<Planned> plan,
  int keys,
  Pointer<Uint32> red,
  Pointer<Uint32> green,
  Pointer<Uint32> blue,
  int restores,
  Pointer<Uint8> maps,
  int count,
);

@Native<Uint32 Function(Pointer<Planned>, Int32, Int32, Uint32, Uint32)>(
  symbol: 'gpu_engine_plan_chain',
)
external int planChain(
  Pointer<Planned> plan,
  int x0,
  int y0,
  int columns,
  int rows,
);

@Native<Int32 Function(Pointer<Planned>, Uint32, Pointer<Double>)>(
  symbol: 'gpu_engine_plan_chain_matrix',
)
external int planChainMatrix(
  Pointer<Planned> plan,
  int chain,
  Pointer<Double> matrix,
);

@Native<Int32 Function(Pointer<Planned>, Uint32, Uint32)>(
  symbol: 'gpu_engine_plan_chain_keys',
)
external int planChainKeys(Pointer<Planned> plan, int chain, int keys);

@Native<
  Int32 Function(
    Pointer<Planned>,
    Uint32,
    Pointer<Double>,
    Pointer<Uint32>,
    Pointer<Int32>,
    Uint32,
    Pointer<Int32>,
  )
>(symbol: 'gpu_engine_plan_chain_gaussian')
external int planChainGaussian(
  Pointer<Planned> plan,
  int chain,
  Pointer<Double> sigmas,
  Pointer<Uint32> reaches,
  Pointer<Int32> picture,
  int repeats,
  Pointer<Int32> puts,
);

@Native<
  Int32 Function(
    Pointer<Planned>,
    Uint32,
    Pointer<Int32>,
    Pointer<Uint32>,
    Pointer<Double>,
    Size,
  )
>(symbol: 'gpu_engine_plan_chain_line')
external int planChainLine(
  Pointer<Planned> plan,
  int chain,
  Pointer<Int32> plate,
  Pointer<Uint32> taps,
  Pointer<Double> maps,
  int count,
);

@Native<
  Int32 Function(
    Pointer<Planned>,
    Uint32,
    Pointer<Int32>,
    Uint32,
    Pointer<Double>,
    Bool,
    Pointer<Int32>,
    Int32,
  )
>(symbol: 'gpu_engine_plan_chain_lens')
external int planChainLens(
  Pointer<Planned> plan,
  int chain,
  Pointer<Int32> picture,
  int sides,
  Pointer<Double> lens,
  bool linear,
  Pointer<Int32> paper,
  int map,
);

@Native<
  Int32 Function(Pointer<Planned>, Pointer<Composited>, Uint32, Double, Bool)
>(symbol: 'gpu_engine_plan_map_laid')
external int planMapLaid(
  Pointer<Planned> plan,
  Pointer<Composited> composited,
  int channel,
  double focal,
  bool inverts,
);

@Native<Uint32 Function(Pointer<Planned>)>(symbol: 'gpu_engine_plan_steps')
external int planSteps(Pointer<Planned> plan);

@Native<Int32 Function(Pointer<Planned>, Uint32, Uint32, Double, Bool)>(
  symbol: 'gpu_engine_plan_map_drawn',
)
external int planMapDrawn(
  Pointer<Planned> plan,
  int first,
  int channel,
  double focal,
  bool inverts,
);

@Native<Pointer<Composite> Function(Pointer<Engine>)>(
  symbol: 'gpu_engine_composite_new',
)
external Pointer<Composite> compositeNew(Pointer<Engine> engine);

@Native<Void Function(Pointer<Composite>)>(symbol: 'gpu_engine_composite_free')
external void compositeFree(Pointer<Composite> composite);

@Native<
  Pointer<Composited> Function(
    Pointer<Composite>,
    Pointer<Engine>,
    Pointer<Pool>,
    Pointer<Planned>,
    Pointer<Int32>,
    Size,
    Pointer<Int32>,
  )
>(symbol: 'gpu_engine_composite_run')
external Pointer<Composited> compositeRun(
  Pointer<Composite> composite,
  Pointer<Engine> engine,
  Pointer<Pool> pool,
  Pointer<Planned> plan,
  Pointer<Int32> tiles,
  int count,
  Pointer<Int32> extent,
);

@Native<
  Bool Function(Pointer<Engine>, Pointer<Composited>, Pointer<Uint8>, Size)
>(symbol: 'gpu_engine_composited_read')
external bool compositedRead(
  Pointer<Engine> engine,
  Pointer<Composited> composited,
  Pointer<Uint8> bytes,
  int capacity,
);

@Native<Uint64 Function(Size)>(symbol: 'gpu_engine_composited_bytes')
external int compositedBytes(int count);

@Native<Void Function(Pointer<Composited>)>(
  symbol: 'gpu_engine_composited_free',
)
external void compositedFree(Pointer<Composited> composited);

@Native<
  IntPtr Function(
    Pointer<Composite>,
    Pointer<Engine>,
    Pointer<Pool>,
    Pointer<Planned>,
    Pointer<Surface>,
    Pointer<Uint32>,
  )
>(symbol: 'gpu_engine_composite_show')
external int compositeShow(
  Pointer<Composite> composite,
  Pointer<Engine> engine,
  Pointer<Pool> pool,
  Pointer<Planned> plan,
  Pointer<Surface> surface,
  Pointer<Uint32> rect,
);

@Native<Pointer<Export> Function()>(symbol: 'gpu_engine_export_new')
external Pointer<Export> exportNew();

@Native<Void Function(Pointer<Export>)>(symbol: 'gpu_engine_export_free')
external void exportFree(Pointer<Export> passes);

@Native<
  Pointer<Readout> Function(
    Pointer<Export>,
    Pointer<Engine>,
    Pointer<Composited>,
    Pointer<Uint32>,
  )
>(symbol: 'gpu_engine_export_nv12')
external Pointer<Readout> exportNv12(
  Pointer<Export> passes,
  Pointer<Engine> engine,
  Pointer<Composited> frame,
  Pointer<Uint32> shape,
);

@Native<
  Pointer<Readout> Function(
    Pointer<Export>,
    Pointer<Engine>,
    Pointer<Composited>,
    Uint32,
    Uint32,
    Uint32,
    Int32,
  )
>(symbol: 'gpu_engine_export_over_ground')
external Pointer<Readout> exportOverGround(
  Pointer<Export> passes,
  Pointer<Engine> engine,
  Pointer<Composited> frame,
  int width,
  int height,
  int ground,
  int cut,
);

@Native<
  Pointer<Readout> Function(
    Pointer<Export>,
    Pointer<Engine>,
    Pointer<Composited>,
    Uint32,
    Uint32,
    Uint8,
  )
>(symbol: 'gpu_engine_export_clear')
external Pointer<Readout> exportClear(
  Pointer<Export> passes,
  Pointer<Engine> engine,
  Pointer<Composited> frame,
  int width,
  int height,
  int cut,
);

@Native<
  Pointer<Readout> Function(
    Pointer<Export>,
    Pointer<Engine>,
    Pointer<Composited>,
    Uint32,
    Uint32,
  )
>(symbol: 'gpu_engine_export_opaque')
external Pointer<Readout> exportOpaque(
  Pointer<Export> passes,
  Pointer<Engine> engine,
  Pointer<Composited> frame,
  int width,
  int height,
);

@Native<
  Pointer<Readout> Function(
    Pointer<Export>,
    Pointer<Engine>,
    Pointer<Composited>,
    Uint32,
    Uint32,
  )
>(symbol: 'gpu_engine_export_png_rgba')
external Pointer<Readout> exportPngRgba(
  Pointer<Export> passes,
  Pointer<Engine> engine,
  Pointer<Composited> frame,
  int width,
  int height,
);

@Native<
  Pointer<Readout> Function(
    Pointer<Export>,
    Pointer<Engine>,
    Pointer<Readout>,
    Uint32,
    Uint32,
  )
>(symbol: 'gpu_engine_export_png_rgb')
external Pointer<Readout> exportPngRgb(
  Pointer<Export> passes,
  Pointer<Engine> engine,
  Pointer<Readout> rgb,
  int width,
  int height,
);

@Native<Uint64 Function(Uint32, Uint32)>(
  symbol: 'gpu_engine_export_png_row_bytes',
)
external int exportPngRowBytes(int width, int pixelBytes);

@Native<Uint64 Function(Pointer<Readout>)>(symbol: 'gpu_engine_readout_bytes')
external int readoutBytes(Pointer<Readout> readout);

@Native<Bool Function(Pointer<Engine>, Pointer<Readout>)>(
  symbol: 'gpu_engine_readout_map',
)
external bool readoutMap(Pointer<Engine> engine, Pointer<Readout> readout);

@Native<
  Bool Function(
    Pointer<Readout>,
    Uint64,
    Uint64,
    Uint64,
    Uint64,
    Pointer<Uint8>,
    Uint64,
  )
>(symbol: 'gpu_engine_readout_rows')
external bool readoutRows(
  Pointer<Readout> readout,
  int offset,
  int stride,
  int rowBytes,
  int rows,
  Pointer<Uint8> dst,
  int dstStride,
);

@Native<Void Function(Pointer<Readout>)>(symbol: 'gpu_engine_readout_free')
external void readoutFree(Pointer<Readout> readout);

@Native<Pointer<Ink> Function(Pointer<Engine>)>(symbol: 'gpu_engine_ink_new')
external Pointer<Ink> inkNew(Pointer<Engine> engine);

@Native<Void Function(Pointer<Ink>)>(symbol: 'gpu_engine_ink_free')
external void inkFree(Pointer<Ink> ink);

@Native<
  IntPtr Function(
    Pointer<Ink>,
    Pointer<Engine>,
    Pointer<Pool>,
    Int32,
    Int32,
    Uint32,
    Uint32,
    Pointer<Uint32>,
    Pointer<Int32>,
    Size,
  )
>(symbol: 'gpu_engine_ink_run')
external int inkRun(
  Pointer<Ink> ink,
  Pointer<Engine> engine,
  Pointer<Pool> pool,
  int x0,
  int y0,
  int columns,
  int rows,
  Pointer<Uint32> tiles,
  Pointer<Int32> out,
  int capacity,
);

@Native<
  Pointer<Faces> Function(
    Pointer<Pointer<Uint8>>,
    Pointer<UintPtr>,
    Pointer<Uint32>,
    Size,
  )
>(symbol: 'gpu_engine_faces_new')
external Pointer<Faces> facesNew(
  Pointer<Pointer<Uint8>> files,
  Pointer<UintPtr> lengths,
  Pointer<Uint32> families,
  int count,
);

@Native<Void Function(Pointer<Faces>)>(symbol: 'gpu_engine_faces_free')
external void facesFree(Pointer<Faces> faces);

@Native<Pointer<Lettering> Function()>(symbol: 'gpu_engine_letters_new')
external Pointer<Lettering> lettersNew();

@Native<Void Function(Pointer<Lettering>)>(symbol: 'gpu_engine_letters_free')
external void lettersFree(Pointer<Lettering> letters);

@Native<Bool Function(Pointer<Lettering>, Uint32, Bool, Int32)>(
  symbol: 'gpu_engine_letters_pass',
)
external bool lettersPass(
  Pointer<Lettering> letters,
  int colour,
  bool hard,
  int outline,
);

@Native<
  Bool Function(
    Pointer<Lettering>,
    Pointer<Float>,
    Int32,
    Bool,
    Bool,
    Pointer<Uint8>,
    Size,
    Pointer<Uint32>,
    Pointer<Int32>,
    Size,
  )
>(symbol: 'gpu_engine_letters_run')
external bool lettersRun(
  Pointer<Lettering> letters,
  Pointer<Float> at,
  int size,
  bool bold,
  bool italic,
  Pointer<Uint8> text,
  int length,
  Pointer<Uint32> ends,
  Pointer<Int32> origins,
  int count,
);

@Native<Bool Function(Pointer<Lettering>, Pointer<Float>, Pointer<Int32>)>(
  symbol: 'gpu_engine_letters_rect',
)
external bool lettersRect(
  Pointer<Lettering> letters,
  Pointer<Float> at,
  Pointer<Int32> rect,
);

@Native<
  Pointer<Lettered> Function(
    Pointer<Lettering>,
    Pointer<Engine>,
    Pointer<Composite>,
    Pointer<Faces>,
    Pointer<Float>,
    Pointer<Int32>,
  )
>(symbol: 'gpu_engine_letters_set')
external Pointer<Lettered> lettersSet(
  Pointer<Lettering> letters,
  Pointer<Engine> engine,
  Pointer<Composite> composite,
  Pointer<Faces> faces,
  Pointer<Float> toGrid,
  Pointer<Int32> rect,
);

@Native<
  Bool Function(Pointer<Engine>, Pointer<Lettered>, Pointer<Uint8>, Size)
>(symbol: 'gpu_engine_lettered_read')
external bool letteredRead(
  Pointer<Engine> engine,
  Pointer<Lettered> lettered,
  Pointer<Uint8> bytes,
  int capacity,
);

@Native<Void Function(Pointer<Lettered>)>(symbol: 'gpu_engine_lettered_free')
external void letteredFree(Pointer<Lettered> lettered);

@Native<Size Function(Pointer<Uint8>, Size)>(symbol: 'gpu_engine_last_error')
external int lastError(Pointer<Uint8> buffer, int capacity);
