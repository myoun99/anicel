//! The fill's C ABI (gpu-canonical-store stage 5's connection — the app's
//! bucket fill runs here, and no C of it is left): the app has the picture
//! a fill reads made of the plan it shows — the screen's with the paper
//! left out — over a box on the canvas, carried into a posed row's space
//! where the pen is on one; floods it from a press and finishes it by the
//! tool's knobs; and reads the finished mask back into its own bytes,
//! where a range is kept and laid as stamps (`FillRange`).
//!
//! One picture serves every press of a tap: each copy a symmetry makes of
//! the seed floods the same one, untouched by the copies before it.

#[cfg(test)]
#[path = "abi_tests.rs"]
mod tests;

use crate::device::Engine;
use crate::fail;
use crate::kernels::composite::Composite;
use crate::kernels::composite::abi::Planned;
use crate::kernels::mask::{MaskBox, MaskPasses};
use crate::kernels::pool::Pool;
use crate::kernels::shared::Counted;

use super::picture::Shown;
use super::{Flood, counted, flood_bytes};

/// The flood's passes and the mask's it finishes by, compiled together:
/// what the app compiles once, off its isolate.
pub struct Floods {
    flood: Flood,
    masks: MaskPasses,
}

/// A fill finished: its mask, bytes over `size` (mask.wgsl's layout).
pub struct Filled {
    pub(crate) mask: wgpu::Buffer,
    pub(crate) size: MaskBox,
    _counted: Counted,
}

impl Filled {
    /// `mask`, bytes over `size`, counted among the fill's for as long as
    /// the app has it.
    pub(crate) fn new(mask: wgpu::Buffer, size: MaskBox) -> Filled {
        let _counted = counted(&mask);
        Filled { mask, size, _counted }
    }
}

/// The fill's kernels, compiled.
///
/// # Safety
/// `engine` is live; the kernels are freed before it.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_floods_new(engine: *const Engine) -> *mut Floods {
    // SAFETY: see the function's contract.
    let engine = unsafe { &*engine };
    let (flood, masks) = (Flood::new(engine), MaskPasses::new(engine));
    Box::into_raw(Box::new(Floods { flood, masks }))
}

/// # Safety
/// `floods` came from `gpu_engine_floods_new`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_floods_free(floods: *mut Floods) {
    if !floods.is_null() {
        // SAFETY: see the function's contract.
        drop(unsafe { Box::from_raw(floods) });
    }
}

/// The picture a fill reads: what `plan` shows over the pixels `extent` —
/// the canvas's, [left, top, right, bottom), nothing past it — and submits
/// the work. Null on failure — a box of no pixel, or one past what a
/// binding holds —; see the last error.
///
/// # Safety
/// Every pointer is live, the pool and the executor were made on `engine`;
/// `extent` holds four words.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_flood_picture_new(
    composite: *const Composite,
    engine: *const Engine,
    pool: *const Pool,
    plan: *const Planned,
    extent: *const i32,
) -> *mut Shown {
    // SAFETY: see the function's contract.
    let (composite, engine, pool, plan) = unsafe { (&*composite, &*engine, &*pool, &*plan) };
    // SAFETY: see the function's contract.
    let extent = unsafe { *extent.cast::<[i32; 4]>() };
    let shown = plan.laid(pool, |laid| Shown::of(engine, composite, laid, extent));
    shown.map_or(std::ptr::null_mut(), |shown| Box::into_raw(Box::new(shown)))
}

/// The picture a fill on a row posed on the canvas reads
/// ([`Shown::through`]): what `plan` shows as that row's space reads it,
/// over the pixels `extent` of the space — [left, top, right, bottom) —,
/// each what shows where `to_canvas` lands it — the space's pixel to the
/// canvas's, row-major with the homogeneous row last —, and nothing past
/// the canvas pixels `within`, the world the plan draws in; and submits
/// the work. Null on failure — a pose that lands nothing among them —;
/// see the last error.
///
/// # Safety
/// Every pointer is live, the pool and the executor were made on `engine`;
/// `to_canvas` holds nine doubles, `extent` and `within` four words each.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_flood_picture_posed(
    composite: *const Composite,
    engine: *const Engine,
    pool: *const Pool,
    plan: *const Planned,
    to_canvas: *const f64,
    extent: *const i32,
    within: *const i32,
) -> *mut Shown {
    // SAFETY: see the function's contract.
    let (composite, engine, pool, plan) = unsafe { (&*composite, &*engine, &*pool, &*plan) };
    // SAFETY: see the function's contract.
    let to_canvas = unsafe { *to_canvas.cast::<[f64; 9]>() };
    // SAFETY: see the function's contract.
    let (extent, within) = unsafe { (*extent.cast::<[i32; 4]>(), *within.cast::<[i32; 4]>()) };
    let shown = plan.laid(pool, |laid| {
        Shown::through(engine, composite, laid, to_canvas, extent, within)
    });
    shown.map_or(std::ptr::null_mut(), |shown| Box::into_raw(Box::new(shown)))
}

/// # Safety
/// `picture` came from `gpu_engine_flood_picture_new` or
/// `gpu_engine_flood_picture_posed`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_flood_picture_free(picture: *mut Shown) {
    if !picture.is_null() {
        // SAFETY: see the function's contract.
        drop(unsafe { Box::from_raw(picture) });
    }
}

/// The fill a press at (`x`, `y`) of `picture`'s space makes: what it
/// reaches through pixels within `tolerance` of the one pressed — closing
/// gaps of `gap` pixels where that is not 0 —, grown `expand` pixels and
/// softened past its outline where `anti_alias`. Puts the box its mask
/// covers in `covers` — [left, top, width, height], `picture`'s space —
/// and waits for the GPU between the flood's rounds. Null on failure — a
/// press off the picture's box among them —; see the last error.
///
/// # Safety
/// Every pointer is live, the kernels and the picture were made on
/// `engine`; `covers` holds four words.
#[unsafe(no_mangle)]
#[allow(clippy::too_many_arguments)]
pub unsafe extern "C" fn gpu_engine_flood_run(
    floods: *const Floods,
    engine: *const Engine,
    picture: *const Shown,
    x: i32,
    y: i32,
    tolerance: u32,
    gap: u32,
    expand: u32,
    anti_alias: bool,
    covers: *mut i32,
) -> *mut Filled {
    // SAFETY: see the function's contract.
    let (Floods { flood, masks }, engine, shown) = unsafe { (&*floods, &*engine, &*picture) };
    let filled = || {
        let Some(seed) = shown.on_grid((x, y)) else {
            return fail(format!("a press at ({x}, {y}) is off the picture"));
        };
        let picture = shown.picture();
        // A gap of 0 floods as a plain flood does (`Flood::gap_closed`),
        // by the passes that measure no distance.
        let flooded = match gap {
            0 => flood.region(engine, &picture, seed, tolerance),
            gap => flood.gap_closed(engine, masks, &picture, seed, tolerance, gap),
        }?;
        let finished = flood.finish(engine, masks, &flooded, expand, anti_alias)?;
        let (at, size) = {
            let mask = shown.on_canvas(&finished);
            (mask.at, mask.size)
        };
        Some((Filled::new(finished.mask, size), at))
    };
    let Some((filled, (left, top))) = filled() else {
        return std::ptr::null_mut();
    };
    let MaskBox { width, height } = filled.size;
    // SAFETY: see the function's contract.
    unsafe { *covers.cast::<[i32; 4]>() = [left, top, width as i32, height as i32] };
    Box::into_raw(Box::new(filled))
}

/// Copies `filled`'s mask — a byte a pixel, row after row, the app's
/// `Uint8List` as it is: as many as its box's width × height — into
/// `bytes` once the GPU is done. False where `capacity` is not that many,
/// or on failure; see the last error.
///
/// # Safety
/// `engine` and `filled` are live and `bytes` holds `capacity`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_flood_filled_read(
    engine: *const Engine,
    filled: *const Filled,
    bytes: *mut u8,
    capacity: usize,
) -> bool {
    // SAFETY: see the function's contract.
    let (engine, Filled { mask, size, .. }) = unsafe { (&*engine, &*filled) };
    // SAFETY: `bytes` holds `capacity`.
    let into = unsafe { std::slice::from_raw_parts_mut(bytes, capacity) };
    size.read_into(engine, mask, into)
}

/// # Safety
/// `filled` came from `gpu_engine_flood_run`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_flood_filled_free(filled: *mut Filled) {
    if !filled.is_null() {
        // SAFETY: see the function's contract.
        drop(unsafe { Box::from_raw(filled) });
    }
}

/// The bytes of every picture a fill reads and every fill finished, made
/// and not yet freed.
#[unsafe(no_mangle)]
pub extern "C" fn gpu_engine_flood_bytes() -> u64 {
    flood_bytes()
}
