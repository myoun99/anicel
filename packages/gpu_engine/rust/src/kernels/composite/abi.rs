//! The executor's C ABI (screen-on-the-engine 2a): the app builds a plan
//! call by call — each tile set, colour matrix and step one call, so the
//! plan's layout is written here alone and nowhere in Dart — and runs it
//! over output tiles, or shows it onto a surface. The plan is checked where
//! it runs ([`Composite`]'s walk), as one built in Rust is.
//!
//! ⏳Rows, folders, clips, adjustments' matrices and the solid colour, the
//! steps the app's tree is flattened into first (connection-round-checklist
//! D ②③⑤⑦). A row's colour keys and effect chains come in 2b; the
//! selection's mask and the fill range's mark with the flip lane.

#[cfg(test)]
mod tests;

use crate::device::Engine;
use crate::fail;
use crate::kernels::effects::{MATRIX_WORDS, matrix_words};
use crate::kernels::pool::Pool;
use crate::kernels::shared::{ResampleMap, ResampleMode};
use crate::platform::Surface;

use super::{Composite, Composited, NO_TILE, Plan, Step, TILE_BYTES, TileAt, TileSet};

/// A plan as the app builds it: what [`Plan`] borrows, owned.
#[derive(Default)]
pub(crate) struct Planned {
    sets: Vec<TileSet>,
    matrices: Vec<[u32; MATRIX_WORDS]>,
    steps: Vec<Step>,
}

impl Planned {
    fn plan<'a>(&'a self, pages: &'a [wgpu::Buffer]) -> Plan<'a> {
        Plan {
            pages,
            sets: &self.sets,
            keys: &[],
            matrices: &self.matrices,
            chains: &[],
            steps: &self.steps,
            mask: None,
        }
    }
}

/// The sampling id the app names a row's by: R1's mode's own.
fn sampling(id: u32) -> Option<ResampleMode> {
    match id {
        0 => Some(ResampleMode::Blend),
        1 => Some(ResampleMode::Pick),
        3 => Some(ResampleMode::Nearest),
        _ => fail(format!("no sampling has id {id}")),
    }
}

/// An index the app names, or none for -1.
fn named(index: i32) -> Option<usize> {
    usize::try_from(index).ok()
}

/// A plan of no steps.
#[unsafe(no_mangle)]
pub extern "C" fn gpu_engine_plan_new() -> *mut Planned {
    Box::into_raw(Box::default())
}

/// # Safety
/// `plan` came from `gpu_engine_plan_new`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_plan_free(plan: *mut Planned) {
    if !plan.is_null() {
        // SAFETY: see the function's contract.
        drop(unsafe { Box::from_raw(plan) });
    }
}

/// Adds the tile set of `columns` × `rows` canvas tiles whose top-left is
/// column `x0`, row `y0` — `tiles` row by row, each `page << 16 | slot` of
/// the pool, or `u32::MAX` for a tile with nothing on it — and returns the
/// index a row lays it by.
///
/// # Safety
/// `plan` is live and `tiles` holds `columns × rows` words.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_plan_set(
    plan: *mut Planned,
    x0: i32,
    y0: i32,
    columns: u32,
    rows: u32,
    tiles: *const u32,
) -> u32 {
    // SAFETY: see the function's contract.
    let (plan, words) =
        unsafe { (&mut *plan, std::slice::from_raw_parts(tiles, columns as usize * rows as usize)) };
    let tiles = words
        .iter()
        .map(|&word| (word != NO_TILE).then(|| TileAt { page: (word >> 16) as u16, slot: word as u16 }))
        .collect();
    plan.sets.push(TileSet { x0, y0, columns, rows, tiles });
    plan.sets.len() as u32 - 1
}

/// Adds the colour matrix of `matrix` — `ColorFilter.matrix`'s twenty — and
/// returns its index; -1 where one of them is past what the matrix holds
/// (`effects::matrix_words`), see the last error.
///
/// # Safety
/// `plan` is live and `matrix` holds twenty doubles.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_plan_matrix(plan: *mut Planned, matrix: *const f64) -> i32 {
    // SAFETY: see the function's contract.
    let (plan, matrix) = unsafe { (&mut *plan, &*matrix.cast::<[f64; MATRIX_WORDS]>()) };
    let Some(words) = matrix_words(matrix) else {
        fail::<()>("a colour matrix entry past what the matrix holds");
        return -1;
    };
    plan.matrices.push(words);
    plan.matrices.len() as i32 - 1
}

/// Adds a row: tile set `set` posed by `inverse` — canvas pixel to the
/// row's own, row-major, the homogeneous row last, over an output of
/// `columns` × `rows` pixels, sampled by `sampling` (0 blend, 1 pick, 3
/// nearest) with Blend's radius at least `radius_floor` — through colour
/// matrix `matrix` if not -1, laid at `opacity` (65535 whole) in blend
/// mode `mode` (blend.wgsl's id).
///
/// Returns 1 where the row was added, 0 where its pose lands nothing and
/// so it lays nothing — not added ([`ResampleMap::new`]) — and -1 for a
/// sampling no mode has; see the last error.
///
/// # Safety
/// `plan` is live and `inverse` holds nine doubles.
#[unsafe(no_mangle)]
#[allow(clippy::too_many_arguments)]
pub unsafe extern "C" fn gpu_engine_plan_row(
    plan: *mut Planned,
    set: u32,
    matrix: i32,
    inverse: *const f64,
    radius_floor: f64,
    sampling_id: u32,
    columns: u32,
    rows: u32,
    opacity: u32,
    mode: u32,
) -> i32 {
    // SAFETY: see the function's contract.
    let (plan, inverse) = unsafe { (&mut *plan, *inverse.cast::<[f64; 9]>()) };
    let Some(sampled) = sampling(sampling_id) else {
        return -1;
    };
    let Some(map) = ResampleMap::new(inverse, radius_floor, sampled, columns, rows) else {
        return 0;
    };
    plan.steps.push(Step::Row {
        set: set as usize,
        keys: None,
        chain: None,
        map,
        matrix: named(matrix),
        opacity,
        mode,
        masked: false,
    });
    1
}

/// Opens a transparent buffer — a folder's, a clip's base or its scope —
/// or, where `opaque`, one holding the buffer under it with its alpha made
/// whole: a clip's scope whose rows blend with the base.
///
/// # Safety
/// `plan` is live.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_plan_open(plan: *mut Planned, opaque: bool) {
    // SAFETY: see the function's contract.
    let plan = unsafe { &mut *plan };
    plan.steps.push(if opaque { Step::OpenOpaque } else { Step::Open });
}

/// Closes the open buffer onto the one under it at `opacity` in `mode`,
/// through colour matrix `matrix` if not -1.
///
/// # Safety
/// `plan` is live.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_plan_close(plan: *mut Planned, opacity: u32, mode: u32, matrix: i32) {
    // SAFETY: see the function's contract.
    let plan = unsafe { &mut *plan };
    plan.steps.push(Step::Close { opacity, mode, matrix: named(matrix), chain: None });
}

/// Closes a clip's scope onto its base by the base's alpha.
///
/// # Safety
/// `plan` is live.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_plan_close_atop(plan: *mut Planned) {
    // SAFETY: see the function's contract.
    let plan = unsafe { &mut *plan };
    plan.steps.push(Step::CloseAtop);
}

/// Lays `colour` — straight RGBA8, A<<24|B<<16|G<<8|R — over the canvas
/// pixels [`left`, `top`, `right`, `bottom`) in normal.
///
/// # Safety
/// `plan` is live.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_plan_solid(
    plan: *mut Planned,
    colour: u32,
    left: i32,
    top: i32,
    right: i32,
    bottom: i32,
) {
    // SAFETY: see the function's contract.
    let plan = unsafe { &mut *plan };
    plan.steps.push(Step::Solid { colour, rect: [left, top, right, bottom] });
}

/// The executor, its full pass compiled. Null on failure; see the last
/// error.
///
/// # Safety
/// `engine` is live; the executor is freed before it.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_composite_new(engine: *const Engine) -> *mut Composite {
    // SAFETY: see the function's contract.
    let engine = unsafe { &*engine };
    Composite::new(engine).map_or(std::ptr::null_mut(), |composite| Box::into_raw(Box::new(composite)))
}

/// # Safety
/// `composite` came from `gpu_engine_composite_new`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_composite_free(composite: *mut Composite) {
    if !composite.is_null() {
        // SAFETY: see the function's contract.
        drop(unsafe { Box::from_raw(composite) });
    }
}

/// Composites `plan` over the `count` output tiles at `tiles` — a canvas
/// tile column then row each — with nothing outside the pixels `extent`,
/// [left, top, right, bottom), and submits the work. Null on failure; see
/// the last error.
///
/// # Safety
/// Every pointer is live, the pool and the executor were made on `engine`;
/// `tiles` holds `2 × count` words and `extent` four.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_composite_run(
    composite: *const Composite,
    engine: *const Engine,
    pool: *const Pool,
    plan: *const Planned,
    tiles: *const i32,
    count: usize,
    extent: *const i32,
) -> *mut Composited {
    // SAFETY: see the function's contract.
    let (composite, engine, pool, plan) = unsafe { (&*composite, &*engine, &*pool, &*plan) };
    // SAFETY: see the function's contract.
    let (words, extent) = unsafe { (std::slice::from_raw_parts(tiles, 2 * count), *extent.cast::<[i32; 4]>()) };
    let tiles: Vec<(i32, i32)> = words.chunks_exact(2).map(|tile| (tile[0], tile[1])).collect();
    let ran = composite.run(engine, &plan.plan(pool.pages()), &tiles, extent, composite.widest());
    ran.map_or(std::ptr::null_mut(), |composited| Box::into_raw(Box::new(composited)))
}

/// Copies `composited`'s pixels — straight RGBA8, tile after tile in the
/// order asked — into `bytes` once the GPU is done, `capacity` of them at
/// most. False on failure; see the last error.
///
/// # Safety
/// `engine` and `composited` are live and `bytes` holds `capacity`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_composited_read(
    engine: *const Engine,
    composited: *const Composited,
    bytes: *mut u8,
    capacity: usize,
) -> bool {
    // SAFETY: see the function's contract.
    let (engine, composited) = unsafe { (&*engine, &*composited) };
    let Some(read) = engine.read_buffer(&composited.out) else {
        return false;
    };
    let count = read.len().min(capacity);
    // SAFETY: `bytes` holds `capacity`, and `count` is no more.
    unsafe { std::ptr::copy_nonoverlapping(read.as_ptr(), bytes, count) };
    true
}

/// The bytes a run over `count` output tiles puts.
#[unsafe(no_mangle)]
pub extern "C" fn gpu_engine_composited_bytes(count: usize) -> u64 {
    count as u64 * TILE_BYTES
}

/// # Safety
/// `composited` came from `gpu_engine_composite_run`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_composited_free(composited: *mut Composited) {
    if !composited.is_null() {
        // SAFETY: see the function's contract.
        drop(unsafe { Box::from_raw(composited) });
    }
}

/// Composites `plan` onto the pixels `rect` of `surface` — [left, top,
/// right, bottom) — leaving the rest of it as it was, and submits the work;
/// returns how many passes it took, -1 on failure (see the last error).
///
/// # Safety
/// Every pointer is live, made on `engine`; `rect` holds four words.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_composite_show(
    composite: *const Composite,
    engine: *const Engine,
    pool: *const Pool,
    plan: *const Planned,
    surface: *const Surface,
    rect: *const u32,
) -> isize {
    // SAFETY: see the function's contract.
    let (composite, engine, pool, plan, surface) = unsafe { (&*composite, &*engine, &*pool, &*plan, &*surface) };
    // SAFETY: see the function's contract.
    let rect = unsafe { *rect.cast::<[u32; 4]>() };
    let shown = composite.show(engine, &plan.plan(pool.pages()), &surface.texture, rect, composite.widest());
    shown.map_or(-1, |passes| passes as isize)
}
