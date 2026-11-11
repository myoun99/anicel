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

final class MaskPlane extends Opaque {}

final class HeldChains extends Opaque {}

final class ChainRead extends Opaque {}

final class Composite extends Opaque {}

final class Composited extends Opaque {}

final class Screen extends Opaque {}

final class Export extends Opaque {}

final class Readout extends Opaque {}

final class Ink extends Opaque {}

final class CelPixels extends Opaque {}

final class CelPassed extends Opaque {}

final class Faces extends Opaque {}

final class Lettering extends Opaque {}

final class Lettered extends Opaque {}

final class Grid extends Opaque {}

final class GridPicture extends Opaque {}

final class GridLay extends Opaque {}

final class DabTexture extends Opaque {}

final class Stroke extends Opaque {}

final class StampPicture extends Opaque {}

final class StampLanding extends Opaque {}

final class Floods extends Opaque {}

final class FloodPicture extends Opaque {}

final class FloodFilled extends Opaque {}

/// `VerbSpec` (rust/src/kernels/cel_pixel/abi.rs), field by field.
final class VerbSpec extends Struct {
  @Uint32()
  external int bytes;
  @Uint32()
  external int base;
  @Uint32()
  external int stride;
  @Uint32()
  external int takesEmpty;
  @Uint32()
  external int threshold;
  @Uint32()
  external int keepsMatches;
  external Pointer<Uint32> red;
  external Pointer<Uint32> green;
  external Pointer<Uint32> blue;
  external Pointer<Uint8> incoming;
  @Size()
  external int length;
  @Uint32()
  external int step;
  @Uint32()
  external int undo;
  @Uint64()
  external int count;
}

/// `DabSpec` (rust/src/kernels/dab/abi.rs), field by field.
final class DabSpec extends Struct {
  @Double()
  external double centreX;
  @Double()
  external double centreY;
  @Double()
  external double opacity;
  @Double()
  external double flow;
  @Double()
  external double contrast;
  @Double()
  external double radius;
  @Double()
  external double cos;
  @Double()
  external double sin;
  @Double()
  external double roundness;
  @Double()
  external double scale;
  @Double()
  external double reach;
  @Double()
  external double inner;
  @Double()
  external double density;
  external Pointer<DabTexture> texture;
  external Pointer<Double> coverage;
  external Pointer<Double> pile;
  external Pointer<Double> evening;
  @Size()
  external int entries;
  @Uint32()
  external int rowLength;
  @Uint32()
  external int flags;
  @Int32()
  external int left;
  @Int32()
  external int top;
  @Int32()
  external int right;
  @Int32()
  external int bottom;
  @Uint32()
  external int colour;
  @Uint32()
  external int pad;
}

/// A GPU fx plugin the device compiled (rust/src/kernels/plugin/abi.rs).
final class Plugin extends Opaque {}

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

@Native<Bool Function(Pointer<Engine>)>(symbol: 'gpu_engine_gone')
external bool engineGone(Pointer<Engine> engine);

@Native<Size Function(Pointer<Engine>, Pointer<Uint8>, Size)>(
  symbol: 'gpu_engine_noted',
)
external int engineNoted(
  Pointer<Engine> engine,
  Pointer<Uint8> buffer,
  int capacity,
);

@Native<Void Function(Pointer<Engine>)>(symbol: 'gpu_engine_lose')
external void engineLose(Pointer<Engine> engine);

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

@Native<Bool Function(Pointer<Engine>, Pointer<Surface>, Pointer<Uint8>, Size)>(
  symbol: 'gpu_engine_surface_read',
)
external bool surfaceRead(
  Pointer<Engine> engine,
  Pointer<Surface> surface,
  Pointer<Uint8> out,
  int length,
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

@Native<
  Bool Function(
    Pointer<Pool>,
    Pointer<Engine>,
    Pointer<Uint32>,
    Size,
    Pointer<Uint8>,
  )
>(symbol: 'gpu_engine_pool_read')
external bool poolRead(
  Pointer<Pool> pool,
  Pointer<Engine> engine,
  Pointer<Uint32> tiles,
  int count,
  Pointer<Uint8> into,
);

@Native<
  Pointer<Readout> Function(
    Pointer<Pool>,
    Pointer<Engine>,
    Pointer<Uint32>,
    Size,
  )
>(symbol: 'gpu_engine_pool_readout')
external Pointer<Readout> poolReadout(
  Pointer<Pool> pool,
  Pointer<Engine> engine,
  Pointer<Uint32> tiles,
  int count,
);

@Native<Void Function(Pointer<Pool>, Uint64)>(
  symbol: 'gpu_engine_pool_most_bytes',
)
external void poolMostBytes(Pointer<Pool> pool, int mostBytes);

@Native<Void Function(Pointer<Pool>, Int64)>(
  symbol: 'gpu_engine_pool_budget_instead',
)
external void poolBudgetInstead(Pointer<Pool> pool, int bytes);

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

@Native<
  Int32 Function(
    Pointer<Planned>,
    Int32,
    Pointer<Int32>,
    Int32,
    Pointer<Double>,
    Double,
    Uint32,
    Uint32,
    Uint32,
    Uint32,
    Uint32,
  )
>(symbol: 'gpu_engine_plan_close_row')
external int planCloseRow(
  Pointer<Planned> plan,
  int chain,
  Pointer<Int32> tiles,
  int matrix,
  Pointer<Double> inverse,
  double radiusFloor,
  int sampling,
  int columns,
  int rows,
  int opacity,
  int mode,
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

@Native<
  Pointer<MaskPlane> Function(
    Pointer<Engine>,
    Pointer<Uint8>,
    Int32,
    Int32,
    Uint32,
    Uint32,
  )
>(symbol: 'gpu_engine_mask_new')
external Pointer<MaskPlane> maskNew(
  Pointer<Engine> engine,
  Pointer<Uint8> bytes,
  int x,
  int y,
  int width,
  int height,
);

@Native<Void Function(Pointer<MaskPlane>)>(symbol: 'gpu_engine_mask_free')
external void maskFree(Pointer<MaskPlane> mask);

@Native<Uint64 Function()>(symbol: 'gpu_engine_mask_bytes')
external int maskBytes();

@Native<Int32 Function(Pointer<Planned>, Pointer<MaskPlane>)>(
  symbol: 'gpu_engine_plan_mask',
)
external int planMask(Pointer<Planned> plan, Pointer<MaskPlane> mask);

@Native<
  Int32 Function(
    Pointer<Planned>,
    Pointer<Double>,
    Double,
    Uint32,
    Uint32,
    Uint32,
    Int32,
    Int32,
  )
>(symbol: 'gpu_engine_plan_mark')
external int planMark(
  Pointer<Planned> plan,
  Pointer<Double> inverse,
  double radiusFloor,
  int sampling,
  int columns,
  int rows,
  int shiftX,
  int shiftY,
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

@Native<Int32 Function(Pointer<Planned>, Uint32, Pointer<HeldChains>, Uint32)>(
  symbol: 'gpu_engine_plan_chain_held',
)
external int planChainHeld(
  Pointer<Planned> plan,
  int chain,
  Pointer<HeldChains> held,
  int id,
);

@Native<Int32 Function(Pointer<Planned>, Uint32, Pointer<ChainRead>)>(
  symbol: 'gpu_engine_plan_chain_read',
)
external int planChainRead(
  Pointer<Planned> plan,
  int chain,
  Pointer<ChainRead> read,
);

@Native<
  Int32 Function(Pointer<Planned>, Uint32, Pointer<Int32>, Pointer<Uint8>, Size)
>(symbol: 'gpu_engine_plan_chain_put')
external int planChainPut(
  Pointer<Planned> plan,
  int chain,
  Pointer<Int32> picture,
  Pointer<Uint8> pixels,
  int length,
);

@Native<Pointer<ChainRead> Function()>(symbol: 'gpu_engine_chain_read_new')
external Pointer<ChainRead> chainReadNew();

@Native<Void Function(Pointer<ChainRead>)>(symbol: 'gpu_engine_chain_read_free')
external void chainReadFree(Pointer<ChainRead> read);

@Native<
  Bool Function(
    Pointer<Engine>,
    Pointer<ChainRead>,
    Pointer<Int32>,
    Pointer<Uint8>,
    Size,
  )
>(symbol: 'gpu_engine_chain_read_pixels')
external bool chainReadPixels(
  Pointer<Engine> engine,
  Pointer<ChainRead> read,
  Pointer<Int32> picture,
  Pointer<Uint8> out,
  int length,
);

@Native<Pointer<HeldChains> Function()>(symbol: 'gpu_engine_held_new')
external Pointer<HeldChains> heldNew();

@Native<Void Function(Pointer<HeldChains>)>(symbol: 'gpu_engine_held_free')
external void heldFree(Pointer<HeldChains> held);

@Native<Void Function(Pointer<HeldChains>, Uint32)>(
  symbol: 'gpu_engine_held_let_go',
)
external void heldLetGo(Pointer<HeldChains> held, int id);

@Native<Uint64 Function(Pointer<HeldChains>, Uint32)>(
  symbol: 'gpu_engine_held_bytes_of',
)
external int heldBytesOf(Pointer<HeldChains> held, int id);

@Native<Uint64 Function()>(symbol: 'gpu_engine_held_bytes')
external int heldBytes();

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

@Native<Void Function(Pointer<Composite>, Pointer<Engine>, Bool)>(
  symbol: 'gpu_engine_composite_shows',
)
external void compositeShows(
  Pointer<Composite> composite,
  Pointer<Engine> engine,
  bool bgra,
);

@Native<Void Function(Pointer<Composite>, Pointer<Engine>)>(
  symbol: 'gpu_engine_composite_chains',
)
external void compositeChains(
  Pointer<Composite> composite,
  Pointer<Engine> engine,
);

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
    Pointer<Texture>,
    Pointer<Uint32>,
  )
>(symbol: 'gpu_engine_composite_show')
external int compositeShow(
  Pointer<Composite> composite,
  Pointer<Engine> engine,
  Pointer<Pool> pool,
  Pointer<Planned> plan,
  Pointer<Texture> target,
  Pointer<Uint32> rect,
);

@Native<Pointer<Screen> Function(Pointer<Int32>, Double)>(
  symbol: 'gpu_engine_screen_new',
)
external Pointer<Screen> screenNew(Pointer<Int32> extent, double floor);

@Native<Void Function(Pointer<Screen>)>(symbol: 'gpu_engine_screen_free')
external void screenFree(Pointer<Screen> screen);

@Native<Uint64 Function(Pointer<Screen>)>(symbol: 'gpu_engine_screen_bytes')
external int screenBytes(Pointer<Screen> screen);

@Native<Uint64 Function()>(symbol: 'gpu_engine_kept_bytes')
external int keptBytes();

@Native<
  Bool Function(
    Pointer<Screen>,
    Pointer<Composite>,
    Pointer<Engine>,
    Pointer<Pool>,
    Pointer<Planned>,
    Pointer<Int32>,
  )
>(symbol: 'gpu_engine_screen_compose')
external bool screenCompose(
  Pointer<Screen> screen,
  Pointer<Composite> composite,
  Pointer<Engine> engine,
  Pointer<Pool> pool,
  Pointer<Planned> plan,
  Pointer<Int32> changed,
);

@Native<
  Bool Function(
    Pointer<Screen>,
    Pointer<Screen>,
    Pointer<Composite>,
    Pointer<Engine>,
    Pointer<Pool>,
    Pointer<Planned>,
    Pointer<Int32>,
  )
>(symbol: 'gpu_engine_screen_compose_over')
external bool screenComposeOver(
  Pointer<Screen> screen,
  Pointer<Screen> film,
  Pointer<Composite> composite,
  Pointer<Engine> engine,
  Pointer<Pool> pool,
  Pointer<Planned> plan,
  Pointer<Int32> fresh,
);

@Native<
  IntPtr Function(
    Pointer<Screen>,
    Pointer<Composite>,
    Pointer<Engine>,
    Pointer<Double>,
    Double,
    Uint32,
    Pointer<Texture>,
    Pointer<Uint32>,
  )
>(symbol: 'gpu_engine_screen_show')
external int screenShow(
  Pointer<Screen> screen,
  Pointer<Composite> composite,
  Pointer<Engine> engine,
  Pointer<Double> inverse,
  double scale,
  int sampling,
  Pointer<Texture> target,
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
  Void Function(
    Pointer<Engine>,
    Pointer<Readout>,
    Pointer<NativeFunction<Void Function(Uint64)>>,
    Uint64,
  )
>(symbol: 'gpu_engine_readout_map_then')
external void readoutMapThen(
  Pointer<Engine> engine,
  Pointer<Readout> readout,
  Pointer<NativeFunction<Void Function(Uint64)>> then,
  int wait,
);

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

@Native<Uint64 Function()>(symbol: 'gpu_engine_readout_live_bytes')
external int readoutLiveBytes();

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

@Native<Pointer<CelPixels> Function(Pointer<Engine>)>(
  symbol: 'gpu_engine_cel_pixels_new',
)
external Pointer<CelPixels> celPixelsNew(Pointer<Engine> engine);

@Native<Void Function(Pointer<CelPixels>)>(
  symbol: 'gpu_engine_cel_pixels_free',
)
external void celPixelsFree(Pointer<CelPixels> pixels);

@Native<
  Pointer<CelPassed> Function(
    Pointer<CelPixels>,
    Pointer<Engine>,
    Pointer<Pool>,
    Int32,
    Int32,
    Uint32,
    Uint32,
    Pointer<Uint32>,
    Pointer<MaskPlane>,
    Pointer<VerbSpec>,
  )
>(symbol: 'gpu_engine_cel_pixels_run')
external Pointer<CelPassed> celPixelsRun(
  Pointer<CelPixels> pixels,
  Pointer<Engine> engine,
  Pointer<Pool> pool,
  int x0,
  int y0,
  int columns,
  int rows,
  Pointer<Uint32> tiles,
  Pointer<MaskPlane> mask,
  Pointer<VerbSpec> spec,
);

@Native<
  Int32 Function(
    Pointer<CelPixels>,
    Pointer<Engine>,
    Pointer<Pool>,
    Int32,
    Int32,
    Uint32,
    Uint32,
    Pointer<Uint32>,
    Pointer<MaskPlane>,
    Bool,
    Pointer<Uint8>,
    Size,
  )
>(symbol: 'gpu_engine_cel_pixels_lift')
external int celPixelsLift(
  Pointer<CelPixels> pixels,
  Pointer<Engine> engine,
  Pointer<Pool> pool,
  int x0,
  int y0,
  int columns,
  int rows,
  Pointer<Uint32> tiles,
  Pointer<MaskPlane> mask,
  bool whole,
  Pointer<Uint8> out,
  int capacity,
);

@Native<Void Function(Pointer<CelPassed>)>(
  symbol: 'gpu_engine_cel_passed_free',
)
external void celPassedFree(Pointer<CelPassed> passed);

@Native<Size Function(Pointer<CelPassed>)>(
  symbol: 'gpu_engine_cel_passed_walked',
)
external int celPassedWalked(Pointer<CelPassed> passed);

@Native<Void Function(Pointer<CelPassed>, Pointer<Int32>)>(
  symbol: 'gpu_engine_cel_passed_tiles',
)
external void celPassedTiles(Pointer<CelPassed> passed, Pointer<Int32> out);

@Native<Size Function(Pointer<CelPassed>)>(
  symbol: 'gpu_engine_cel_passed_run_count',
)
external int celPassedRunCount(Pointer<CelPassed> passed);

@Native<Void Function(Pointer<CelPassed>, Pointer<Uint32>)>(
  symbol: 'gpu_engine_cel_passed_runs',
)
external void celPassedRuns(Pointer<CelPassed> passed, Pointer<Uint32> out);

@Native<
  IntPtr Function(
    Pointer<CelPassed>,
    Pointer<Engine>,
    Pointer<Pool>,
    Uint32,
    Size,
    Size,
    Pointer<Uint32>,
    Pointer<Uint8>,
  )
>(symbol: 'gpu_engine_cel_passed_land')
external int celPassedLand(
  Pointer<CelPassed> passed,
  Pointer<Engine> engine,
  Pointer<Pool> pool,
  int cel,
  int first,
  int count,
  Pointer<Uint32> places,
  Pointer<Uint8> changes,
);

@Native<Pointer<Floods> Function(Pointer<Engine>)>(
  symbol: 'gpu_engine_floods_new',
)
external Pointer<Floods> floodsNew(Pointer<Engine> engine);

@Native<Void Function(Pointer<Floods>)>(symbol: 'gpu_engine_floods_free')
external void floodsFree(Pointer<Floods> floods);

@Native<
  Pointer<FloodPicture> Function(
    Pointer<Composite>,
    Pointer<Engine>,
    Pointer<Pool>,
    Pointer<Planned>,
    Pointer<Int32>,
  )
>(symbol: 'gpu_engine_flood_picture_new')
external Pointer<FloodPicture> floodPictureNew(
  Pointer<Composite> composite,
  Pointer<Engine> engine,
  Pointer<Pool> pool,
  Pointer<Planned> plan,
  Pointer<Int32> extent,
);

@Native<
  Pointer<FloodPicture> Function(
    Pointer<Composite>,
    Pointer<Engine>,
    Pointer<Pool>,
    Pointer<Planned>,
    Pointer<Double>,
    Pointer<Int32>,
    Pointer<Int32>,
  )
>(symbol: 'gpu_engine_flood_picture_posed')
external Pointer<FloodPicture> floodPicturePosed(
  Pointer<Composite> composite,
  Pointer<Engine> engine,
  Pointer<Pool> pool,
  Pointer<Planned> plan,
  Pointer<Double> toCanvas,
  Pointer<Int32> extent,
  Pointer<Int32> within,
);

@Native<Void Function(Pointer<FloodPicture>)>(
  symbol: 'gpu_engine_flood_picture_free',
)
external void floodPictureFree(Pointer<FloodPicture> picture);

@Native<
  Pointer<FloodFilled> Function(
    Pointer<Floods>,
    Pointer<Engine>,
    Pointer<FloodPicture>,
    Int32,
    Int32,
    Uint32,
    Uint32,
    Uint32,
    Bool,
    Pointer<Int32>,
  )
>(symbol: 'gpu_engine_flood_run')
external Pointer<FloodFilled> floodRun(
  Pointer<Floods> floods,
  Pointer<Engine> engine,
  Pointer<FloodPicture> picture,
  int x,
  int y,
  int tolerance,
  int gap,
  int expand,
  bool antiAlias,
  Pointer<Int32> covers,
);

@Native<
  Bool Function(Pointer<Engine>, Pointer<FloodFilled>, Pointer<Uint8>, Size)
>(symbol: 'gpu_engine_flood_filled_read')
external bool floodFilledRead(
  Pointer<Engine> engine,
  Pointer<FloodFilled> filled,
  Pointer<Uint8> bytes,
  int capacity,
);

@Native<Void Function(Pointer<FloodFilled>)>(
  symbol: 'gpu_engine_flood_filled_free',
)
external void floodFilledFree(Pointer<FloodFilled> filled);

@Native<Uint64 Function()>(symbol: 'gpu_engine_flood_bytes')
external int floodBytes();

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
    Uint32,
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
  int weight,
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

@Native<Pointer<Plugin> Function(Pointer<Engine>, Pointer<Uint8>, Size, Bool)>(
  symbol: 'gpu_engine_plugin_open',
)
external Pointer<Plugin> pluginOpen(
  Pointer<Engine> engine,
  Pointer<Uint8> source,
  int length,
  bool cut,
);

@Native<Void Function(Pointer<Plugin>)>(symbol: 'gpu_engine_plugin_free')
external void pluginFree(Pointer<Plugin> plugin);

@Native<
  Int64 Function(
    Pointer<Plugin>,
    Pointer<Double>,
    Pointer<Uint32>,
    Size,
    Pointer<Double>,
    Uint32,
  )
>(symbol: 'gpu_engine_plugin_reach')
external int pluginReach(
  Pointer<Plugin> plugin,
  Pointer<Double> values,
  Pointer<Uint32> kinds,
  int count,
  Pointer<Double> moment,
  int share,
);

@Native<
  Int32 Function(
    Pointer<Plugin>,
    Pointer<Engine>,
    Pointer<Uint32>,
    Pointer<Int32>,
    Size,
    Pointer<Double>,
    Pointer<Uint32>,
    Size,
    Pointer<Double>,
    Uint32,
    Pointer<Uint32>,
  )
>(symbol: 'gpu_engine_plugin_render')
external int pluginRender(
  Pointer<Plugin> plugin,
  Pointer<Engine> engine,
  Pointer<Uint32> pixels,
  Pointer<Int32> rects,
  int layers,
  Pointer<Double> values,
  Pointer<Uint32> kinds,
  int count,
  Pointer<Double> moment,
  int share,
  Pointer<Uint32> output,
);

@Native<Size Function(Pointer<Uint8>, Size)>(symbol: 'gpu_engine_last_error')
external int lastError(Pointer<Uint8> buffer, int capacity);

@Native<Uint64 Function()>(symbol: 'gpu_engine_kernels_built_here')
external int kernelsBuiltHere();

@Native<Uint64 Function()>(symbol: 'gpu_engine_waits_here')
external int waitsHere();

@Native<Void Function(Pointer<Engine>)>(symbol: 'gpu_engine_kernels_forget')
external void kernelsForget(Pointer<Engine> engine);

@Native<Void Function(Pointer<Engine>)>(symbol: 'gpu_engine_apart_hold')
external void apartHold(Pointer<Engine> engine);

@Native<Void Function(Pointer<Engine>)>(symbol: 'gpu_engine_apart_let')
external void apartLet(Pointer<Engine> engine);

@Native<Void Function(Pointer<Engine>)>(symbol: 'gpu_engine_apart_wait')
external void apartWait(Pointer<Engine> engine);

@Native<Uint64 Function(Pointer<Engine>)>(symbol: 'gpu_engine_apart_held')
external int apartHeld(Pointer<Engine> engine);

@Native<Pointer<Grid> Function(Pointer<Engine>)>(symbol: 'gpu_engine_grid_new')
external Pointer<Grid> gridNew(Pointer<Engine> engine);

@Native<Void Function(Pointer<Grid>)>(symbol: 'gpu_engine_grid_free')
external void gridFree(Pointer<Grid> grid);

@Native<Pointer<GridPicture> Function(Pointer<Engine>, Uint32, Uint32)>(
  symbol: 'gpu_engine_grid_picture_new',
)
external Pointer<GridPicture> gridPictureNew(
  Pointer<Engine> engine,
  int width,
  int height,
);

@Native<Void Function(Pointer<GridPicture>)>(
  symbol: 'gpu_engine_grid_picture_free',
)
external void gridPictureFree(Pointer<GridPicture> picture);

@Native<
  Bool Function(Pointer<Engine>, Pointer<GridPicture>, Pointer<Uint8>, Size)
>(symbol: 'gpu_engine_grid_picture_read')
external bool gridPictureRead(
  Pointer<Engine> engine,
  Pointer<GridPicture> picture,
  Pointer<Uint8> bytes,
  int capacity,
);

@Native<
  Bool Function(
    Pointer<Grid>,
    Pointer<Engine>,
    Pointer<GridPicture>,
    Pointer<Int32>,
    Size,
    Pointer<Uint8>,
    Uint32,
    Uint32,
  )
>(symbol: 'gpu_engine_grid_draw')
external bool gridDraw(
  Pointer<Grid> grid,
  Pointer<Engine> engine,
  Pointer<GridPicture> picture,
  Pointer<Int32> ops,
  int count,
  Pointer<Uint8> atlas,
  int atlasWidth,
  int atlasHeight,
);

@Native<Pointer<GridLay> Function()>(symbol: 'gpu_engine_grid_lay_new')
external Pointer<GridLay> gridLayNew();

@Native<Void Function(Pointer<GridLay>, Pointer<Engine>, Bool)>(
  symbol: 'gpu_engine_grid_lay_ready',
)
external void gridLayReady(
  Pointer<GridLay> lay,
  Pointer<Engine> engine,
  bool bgra,
);

@Native<Void Function(Pointer<GridLay>)>(symbol: 'gpu_engine_grid_lay_free')
external void gridLayFree(Pointer<GridLay> lay);

@Native<
  Bool Function(
    Pointer<GridLay>,
    Pointer<Engine>,
    Pointer<Texture>,
    Pointer<Uint32>,
    Pointer<Pointer<GridPicture>>,
    Pointer<Double>,
    Size,
  )
>(symbol: 'gpu_engine_grid_lay')
external bool gridLay(
  Pointer<GridLay> lay,
  Pointer<Engine> engine,
  Pointer<Texture> target,
  Pointer<Uint32> rect,
  Pointer<Pointer<GridPicture>> pictures,
  Pointer<Double> boxes,
  int count,
);

@Native<Pointer<DabTexture> Function(Pointer<Double>, Uint32)>(
  symbol: 'gpu_engine_dab_texture_new',
)
external Pointer<DabTexture> dabTextureNew(Pointer<Double> texels, int side);

@Native<Void Function(Pointer<DabTexture>)>(
  symbol: 'gpu_engine_dab_texture_free',
)
external void dabTextureFree(Pointer<DabTexture> texture);

@Native<Pointer<Stroke> Function(Pointer<Engine>)>(
  symbol: 'gpu_engine_stroke_new',
)
external Pointer<Stroke> strokeNew(Pointer<Engine> engine);

@Native<Void Function(Pointer<Stroke>)>(symbol: 'gpu_engine_stroke_free')
external void strokeFree(Pointer<Stroke> stroke);

@Native<Uint64 Function(Pointer<Stroke>)>(symbol: 'gpu_engine_stroke_bytes')
external int strokeBytes(Pointer<Stroke> stroke);

@Native<Void Function(Pointer<Stroke>, Pointer<Engine>)>(
  symbol: 'gpu_engine_stroke_clear',
)
external void strokeClear(Pointer<Stroke> stroke, Pointer<Engine> engine);

@Native<
  Bool Function(
    Pointer<Stroke>,
    Pointer<Engine>,
    Pointer<DabSpec>,
    Size,
    Pointer<DabTexture>,
    Double,
    Bool,
    Int32,
    Double,
  )
>(symbol: 'gpu_engine_stroke_pile')
external bool strokePile(
  Pointer<Stroke> stroke,
  Pointer<Engine> engine,
  Pointer<DabSpec> dabs,
  int count,
  Pointer<DabTexture> paper,
  double paperScale,
  bool paperHeight,
  int secondMode,
  double secondDensity,
);

@Native<
  IntPtr Function(
    Pointer<Stroke>,
    Pointer<Engine>,
    Pointer<Composite>,
    Pointer<Pool>,
    Uint32,
    Pointer<Int32>,
    Pointer<Uint32>,
    Size,
    Uint32,
    Uint32,
    Pointer<MaskPlane>,
    Bool,
    Pointer<Uint32>,
    Pointer<Uint8>,
  )
>(symbol: 'gpu_engine_stroke_land')
external int strokeLand(
  Pointer<Stroke> stroke,
  Pointer<Engine> engine,
  Pointer<Composite> composite,
  Pointer<Pool> pool,
  int cel,
  Pointer<Int32> asks,
  Pointer<Uint32> under,
  int count,
  int opacity,
  int mode,
  Pointer<MaskPlane> mask,
  bool compared,
  Pointer<Uint32> places,
  Pointer<Uint8> changes,
);

final class Blurs extends Opaque {}

@Native<Pointer<Blurs> Function(Pointer<Engine>)>(
  symbol: 'gpu_engine_blurs_new',
)
external Pointer<Blurs> blursNew(Pointer<Engine> engine);

@Native<Bool Function(Pointer<Engine>)>(
  symbol: 'gpu_engine_blurs_compile_strips',
)
external bool blursCompileStrips(Pointer<Engine> engine);

@Native<Bool Function(Pointer<Blurs>)>(symbol: 'gpu_engine_blurs_by_strips')
external bool blursByStrips(Pointer<Blurs> blurs);

@Native<Void Function(Pointer<Blurs>)>(symbol: 'gpu_engine_blurs_free')
external void blursFree(Pointer<Blurs> blurs);

@Native<Uint64 Function(Pointer<Blurs>)>(symbol: 'gpu_engine_blurs_bytes')
external int blursBytes(Pointer<Blurs> blurs);

@Native<Void Function(Pointer<Blurs>)>(symbol: 'gpu_engine_blurs_let_go')
external void blursLetGo(Pointer<Blurs> blurs);

@Native<
  IntPtr Function(
    Pointer<Stroke>,
    Pointer<Engine>,
    Pointer<DabSpec>,
    Pointer<Uint32>,
    Size,
  )
>(symbol: 'gpu_engine_stroke_reach_blur')
external int strokeReachBlur(
  Pointer<Stroke> stroke,
  Pointer<Engine> engine,
  Pointer<DabSpec> dabs,
  Pointer<Uint32> radii,
  int count,
);

@Native<Void Function(Pointer<Stroke>, Pointer<Int32>)>(
  symbol: 'gpu_engine_stroke_met',
)
external void strokeMet(Pointer<Stroke> stroke, Pointer<Int32> coordinates);

@Native<
  Bool Function(
    Pointer<Stroke>,
    Pointer<Engine>,
    Pointer<Blurs>,
    Pointer<Composite>,
    Pointer<Pool>,
    Pointer<Uint32>,
    Size,
    Pointer<DabSpec>,
    Pointer<Uint32>,
    Size,
    Pointer<DabTexture>,
    Double,
    Bool,
  )
>(symbol: 'gpu_engine_stroke_rub')
external bool strokeRub(
  Pointer<Stroke> stroke,
  Pointer<Engine> engine,
  Pointer<Blurs> blurs,
  Pointer<Composite> composite,
  Pointer<Pool> pool,
  Pointer<Uint32> under,
  int met,
  Pointer<DabSpec> dabs,
  Pointer<Uint32> radii,
  int count,
  Pointer<DabTexture> paper,
  double paperScale,
  bool paperHeight,
);

@Native<
  IntPtr Function(
    Pointer<Stroke>,
    Pointer<Engine>,
    Pointer<Blurs>,
    Pointer<Composite>,
    Pointer<Pool>,
    Uint32,
    Pointer<Int32>,
    Pointer<Uint32>,
    Size,
    Uint32,
    Pointer<MaskPlane>,
    Bool,
    Pointer<Uint32>,
    Pointer<Uint8>,
  )
>(symbol: 'gpu_engine_stroke_land_blur')
external int strokeLandBlur(
  Pointer<Stroke> stroke,
  Pointer<Engine> engine,
  Pointer<Blurs> blurs,
  Pointer<Composite> composite,
  Pointer<Pool> pool,
  int cel,
  Pointer<Int32> asks,
  Pointer<Uint32> under,
  int count,
  int opacity,
  Pointer<MaskPlane> mask,
  bool compared,
  Pointer<Uint32> places,
  Pointer<Uint8> changes,
);

@Native<
  Pointer<StampPicture> Function(Pointer<Engine>, Pointer<Uint8>, Uint32, Uint32)
>(symbol: 'gpu_engine_stamp_picture_new')
external Pointer<StampPicture> stampPictureNew(
  Pointer<Engine> engine,
  Pointer<Uint8> rgba,
  int width,
  int height,
);

@Native<
  Pointer<StampPicture> Function(
    Pointer<StampLanding>,
    Pointer<Engine>,
    Pointer<StampPicture>,
    Pointer<Double>,
    Double,
    Uint32,
    Uint32,
    Uint32,
    Uint32,
    Uint32,
    Uint32,
    Uint32,
  )
>(symbol: 'gpu_engine_stamp_picture_carried')
external Pointer<StampPicture> stampPictureCarried(
  Pointer<StampLanding> landing,
  Pointer<Engine> engine,
  Pointer<StampPicture> picture,
  Pointer<Double> inverse,
  double radiusFloor,
  int samplingId,
  int columns,
  int rows,
  int left,
  int top,
  int width,
  int height,
);

@Native<
  Pointer<StampPicture> Function(
    Pointer<StampLanding>,
    Pointer<Engine>,
    Pointer<StampPicture>,
    Double,
    Double,
    Uint32,
    Uint32,
    Pointer<Double>,
    Pointer<Double>,
    Double,
    Uint32,
    Int32,
    Int32,
    Uint32,
    Uint32,
  )
>(symbol: 'gpu_engine_stamp_picture_meshed')
external Pointer<StampPicture> stampPictureMeshed(
  Pointer<StampLanding> landing,
  Pointer<Engine> engine,
  Pointer<StampPicture> picture,
  double sourceLeft,
  double sourceTop,
  int columns,
  int rows,
  Pointer<Double> source,
  Pointer<Double> destination,
  double radiusFloor,
  int samplingId,
  int left,
  int top,
  int width,
  int height,
);

@Native<Bool Function(Pointer<Engine>, Pointer<StampPicture>, Pointer<Uint8>)>(
  symbol: 'gpu_engine_stamp_picture_read',
)
external bool stampPictureRead(
  Pointer<Engine> engine,
  Pointer<StampPicture> picture,
  Pointer<Uint8> into,
);

@Native<Void Function(Pointer<StampPicture>)>(
  symbol: 'gpu_engine_stamp_picture_free',
)
external void stampPictureFree(Pointer<StampPicture> picture);

@Native<Uint64 Function()>(symbol: 'gpu_engine_stamp_picture_bytes')
external int stampPictureBytes();

@Native<Pointer<StampLanding> Function(Pointer<Engine>)>(
  symbol: 'gpu_engine_stamp_landing_new',
)
external Pointer<StampLanding> stampLandingNew(Pointer<Engine> engine);

@Native<Void Function(Pointer<StampLanding>)>(
  symbol: 'gpu_engine_stamp_landing_free',
)
external void stampLandingFree(Pointer<StampLanding> landing);

@Native<
  IntPtr Function(
    Pointer<StampLanding>,
    Pointer<Engine>,
    Pointer<Composite>,
    Pointer<Pool>,
    Uint32,
    Pointer<StampPicture>,
    Int32,
    Int32,
    Pointer<Int32>,
    Pointer<Int32>,
    Pointer<Uint32>,
    UintPtr,
    Uint32,
    Uint32,
    Pointer<Uint32>,
    Pointer<Uint8>,
  )
>(symbol: 'gpu_engine_stamp_land')
external int stampLand(
  Pointer<StampLanding> landing,
  Pointer<Engine> engine,
  Pointer<Composite> composite,
  Pointer<Pool> pool,
  int cel,
  Pointer<StampPicture> picture,
  int left,
  int top,
  Pointer<Int32> within,
  Pointer<Int32> asks,
  Pointer<Uint32> under,
  int count,
  int opacity,
  int mode,
  Pointer<Uint32> places,
  Pointer<Uint8> changes,
);
