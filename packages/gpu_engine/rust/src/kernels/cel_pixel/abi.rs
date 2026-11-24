//! The cel pixel kernels' C ABI. The verbs' (flip lane ⓒ): the app states
//! one over tiles named as a plan's tile set is, reads what it took the
//! pixels from, and has its tiles put in fresh slots. The lift's: what a
//! selection takes off the same tiles, kept on the GPU as a stamp's picture.
//!
//! The ink scan's (connection round 2, 잉크 상자 ㉢): the app hands
//! the tiles of a cel that owe a box — on the pool, named as a plan's tile
//! set is ([`Named::from_words`]) — and takes each walked tile's box,
//! as it takes C's `qa_alpha_bounds_tiles` answer today.
//!
//! The scan is no step of a plan: it reads the pool's pages and nothing
//! the executor composites, so a plan's shape (keys, chains, the mask) is
//! nothing to it.

#[cfg(test)]
mod tests;

use crate::device::{Engine, let_go};
use crate::fail;
use crate::kernels::composite::abi::MaskPlane;
use crate::kernels::composite::{Named, TileSet};
use crate::kernels::dab::abi::{StampPicture, kept, reported, told_body};
use crate::kernels::effects::KeyRun;
use crate::kernels::pool::{Cel, Pool};

use super::ink::{Ink, InkBox, TileInk};
use super::lift::{Lift, Lifted};
use super::{CelPixels, Channel, Incoming, Passed, Selector, Verb};

/// The words a walked tile's answer takes: its column and row, then its
/// box's left, top, right and bottom — tile-local, the far two past the
/// last column and row with ink (the app's `TileInkBounds`). A tile with
/// no ink is a box of four 0s, which is empty as the app reads one
/// (`rightExclusive <= left`); a box with ink always ends past its start.
pub(crate) const TILE_INK_WORDS: usize = 6;

/// A verb as the app states it (`GpuCelPixels.run`), field by field: its
/// channel; 2치화's cut; whether it keeps what its selector names; the
/// selector's tables, 256 words each, null for none; what the pixels taking
/// part take, `length` bytes — the value, or, where `undo` is not 0, the
/// recipe of `count` pixels `step` apart.
#[repr(C)]
pub struct VerbSpec {
    bytes: u32,
    base: u32,
    stride: u32,
    takes_empty: u32,
    threshold: u32,
    keeps_matches: u32,
    red: *const u32,
    green: *const u32,
    blue: *const u32,
    incoming: *const u8,
    length: usize,
    step: u32,
    undo: u32,
    count: u64,
}

/// The verb `spec` states.
///
/// # Safety
/// `spec`'s tables are null or hold 256 words each, and its `incoming`
/// holds `length` bytes — a null one none.
unsafe fn verb_of(spec: &VerbSpec) -> Verb<'_> {
    let table = |words: *const u32| {
        // SAFETY: see the function's contract.
        unsafe { &*words.cast::<[u32; 256]>() }
    };
    let selector = (!spec.red.is_null()).then(|| Selector {
        // The verb reads what a key names: its restores and maps say what a
        // key does to the alpha of a row it runs on.
        key: KeyRun {
            red: table(spec.red),
            green: table(spec.green),
            blue: table(spec.blue),
            restores: 0,
            maps: &[],
        },
        keeps_matches: spec.keeps_matches != 0,
    });
    let bytes = match spec.incoming.is_null() {
        true => &[][..],
        // SAFETY: see the function's contract.
        false => unsafe { std::slice::from_raw_parts(spec.incoming, spec.length) },
    };
    Verb {
        channel: Channel {
            bytes: spec.bytes,
            base: spec.base,
            stride: spec.stride,
            takes_empty: spec.takes_empty != 0,
        },
        selector,
        threshold: spec.threshold,
        incoming: match spec.undo != 0 {
            true => Incoming::Recipe { bytes, step: spec.step, count: spec.count },
            false => Incoming::Value(bytes),
        },
    }
}

/// The verbs' pass and the lift, compiled together: what the app compiles
/// once, off its isolate.
pub struct CelKernels {
    verbs: CelPixels,
    lift: Lift,
}

/// The cel's kernels, compiled. Null on failure; see the last error.
///
/// # Safety
/// `engine` is live; the kernels are freed before it.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_cel_pixels_new(engine: *const Engine) -> *mut CelKernels {
    // SAFETY: see the function's contract.
    let engine = unsafe { &*engine };
    engine.on_thread(|| {
        CelPixels::new(engine)
            .zip(Lift::new(engine))
            .map_or(std::ptr::null_mut(), |(verbs, lift)| engine.hands(CelKernels { verbs, lift }))
    })
}

/// # Safety
/// `kernels` came from `gpu_engine_cel_pixels_new`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_cel_pixels_free(kernels: *mut CelKernels) {
    // SAFETY: see the function's contract.
    unsafe { let_go(kernels) };
}

/// What `mask` takes off the cel of `columns` × `rows` tiles whose top-left
/// is column `x0`, row `y0` — named as `gpu_engine_cel_pixels_run`'s are —
/// kept where the kernel wrote it: a stamp's picture of its box at `out`,
/// straight RGBA8, a pixel it covers at all whole where `whole`, its bytes
/// never read back. `Lift::run`. Waits for the GPU to say whether it took
/// any: 1 where it did, 0 where it took nothing (`out` as it was), -1 on
/// failure — see the last error.
///
/// ↩️The box was read back into the app's bytes, and handed up again as
/// the float's picture, at every lift — 🔬with the UI thread's GC the big
/// buffers fed, a share of the 359–422 ms of the transform box's first
/// press (S5_BA cut 352 · 62 rows × 36 frames, main PC, board
/// `lifting-a-cel-goes-gpu-cpu-gpu-and-zero-fills`). 🔬Kept on the
/// engine, that press went 353 → 298 ms on a Surface Pro 11 (medians of
/// five, the same 62 rows); 28 → 26 ms with six rows.
///
/// # Safety
/// Every pointer is live, the pool, the mask and the kernels made on
/// `engine`; `tiles` holds `columns × rows` words.
#[unsafe(no_mangle)]
#[allow(clippy::too_many_arguments)]
pub unsafe extern "C" fn gpu_engine_cel_pixels_lift_picture(
    kernels: *const CelKernels,
    engine: *const Engine,
    pool: *const Pool,
    x0: i32,
    y0: i32,
    columns: u32,
    rows: u32,
    tiles: *const u32,
    mask: *const MaskPlane,
    whole: bool,
    out: *mut *mut StampPicture,
) -> i32 {
    // SAFETY: see the function's contract.
    let (kernels, engine, pool, mask) = unsafe { (&*kernels, &*engine, &*pool, (*mask).mask()) };
    engine.on_thread(|| {
        // SAFETY: see the function's contract.
        let cel = unsafe { cel_of(pool, (x0, y0, columns, rows), tiles) };
        let Some(lifted) = kernels.lift.run(engine, pool.pages(), &cel, &mask, whole) else {
            return -1;
        };
        if !lifted.anything {
            return 0;
        }
        let picture = kept(engine, Some(lifted.rgba), (mask.size.width, mask.size.height));
        if picture.is_null() {
            return -1;
        }
        // SAFETY: see the function's contract.
        unsafe { *out = picture };
        1
    })
}

/// [`gpu_engine_cel_pixels_lift_picture`] with no wait for its caller: the
/// cel's tiles read where `pool` holds them now, the lift handed to the
/// engine's thread — which waits for no GPU either (`Lift::lifted_then`) —
/// and `told` called with `number` from a thread of the engine's once the
/// GPU has said whether it took any, `out` written first: the picture it
/// took, its caller's to free, or null where it took nothing — and null
/// with `told` false where the lift failed.
///
/// 🚨WHY UNWAITED: `gpu_engine_stamp_finish_unwaited` has it — a box at
/// rest cuts its cels ahead of the press, and waits for nothing.
///
/// # Safety
/// As [`gpu_engine_cel_pixels_lift_picture`]'s, `kernels` and `mask` let
/// go of after this; `out` is live till `told` is called, and `told` is
/// one any thread may call.
#[unsafe(no_mangle)]
#[allow(clippy::too_many_arguments)]
pub unsafe extern "C" fn gpu_engine_cel_pixels_lift_picture_unwaited(
    kernels: *const CelKernels,
    engine: *const Engine,
    pool: *const Pool,
    x0: i32,
    y0: i32,
    columns: u32,
    rows: u32,
    tiles: *const u32,
    mask: *const MaskPlane,
    whole: bool,
    out: *mut *mut StampPicture,
    told: extern "C" fn(u64, bool),
    number: u64,
) {
    // SAFETY: see the function's contract.
    let (engine, pool) = unsafe { (&*engine, &*pool) };
    // SAFETY: see the function's contract.
    let cel = unsafe { cel_of(pool, (x0, y0, columns, rows), tiles) };
    let lift = move |engine: &Engine, pages: &[wgpu::Buffer], then: Box<dyn FnOnce(Option<_>) + Send>| {
        // SAFETY: each is let go of on this thread, after this (the
        // function's contract).
        let (kernels, mask) = unsafe { (&*kernels, (*mask).mask()) };
        let size = (mask.size.width, mask.size.height);
        let sized = move |lifted: Option<Lifted>| then(lifted.map(|lifted| (lifted, size)));
        kernels.lift.lifted_then(engine, pages, &cel, &mask, whole, sized);
    };
    let answer = move |engine: &Engine, lifted: Option<(Lifted, (u32, u32))>| {
        let ran = lifted.is_some();
        let picture = match lifted {
            Some((Lifted { rgba, anything: true }, size)) => kept(engine, Some(rgba), size),
            _ => std::ptr::null_mut(),
        };
        // SAFETY: live till `told` is called (the function's contract).
        unsafe { *out = picture };
        ran
    };
    // SAFETY: what `lift` holds is let go of on the engine's thread, after
    // it; `out` and `told` are the function's contract.
    engine.posted(unsafe { told_body(engine, pool, (told, number), lift, answer) });
}

/// Runs the verb `spec` states over the cel of `columns` × `rows` tiles
/// whose top-left is column `x0`, row `y0` — `tiles` row by row, each
/// `page << 16 | slot` of `pool`, or `u32::MAX` for a tile not walked —,
/// under `mask` if not null: `CelPixels::run`. Waits for the GPU.
///
/// What it left, to be freed; null on failure — see the last error.
///
/// # Safety
/// Every pointer but `mask` is live, the pool and the pass were made on
/// `engine`; `tiles` holds `columns × rows` words, and `spec` is as
/// [`verb_of`] says.
#[unsafe(no_mangle)]
#[allow(clippy::too_many_arguments)]
pub unsafe extern "C" fn gpu_engine_cel_pixels_run(
    kernels: *const CelKernels,
    engine: *const Engine,
    pool: *const Pool,
    x0: i32,
    y0: i32,
    columns: u32,
    rows: u32,
    tiles: *const u32,
    mask: *const MaskPlane,
    spec: *const VerbSpec,
) -> *mut Passed {
    // SAFETY: see the function's contract.
    let (kernels, engine, pool, spec) = unsafe { (&*kernels, &*engine, &*pool, &*spec) };
    engine.on_thread(|| {
        // SAFETY: see the function's contract.
        let cel = unsafe { cel_of(pool, (x0, y0, columns, rows), tiles) };
        // SAFETY: see the function's contract.
        let mask = unsafe { mask.as_ref() }.map(MaskPlane::mask);
        // SAFETY: see the function's contract.
        let verb = unsafe { verb_of(spec) };
        kernels
            .verbs
            .run(engine, pool.pages(), &cel, mask.as_ref(), &verb)
            .map_or(std::ptr::null_mut(), |passed| engine.hands(passed))
    })
}

/// # Safety
/// `passed` came from `gpu_engine_cel_pixels_run`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_cel_passed_free(passed: *mut Passed) {
    // SAFETY: see the function's contract.
    unsafe { let_go(passed) };
}

/// How many tiles the pass walked.
///
/// # Safety
/// `passed` is live.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_cel_passed_walked(passed: *const Passed) -> usize {
    // SAFETY: see the function's contract.
    unsafe { &*passed }.tiles.len()
}

/// Writes each walked tile's column and row, in the walk's order.
///
/// # Safety
/// `passed` is live and `out` holds two words a walked tile.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_cel_passed_tiles(passed: *const Passed, out: *mut i32) {
    // SAFETY: see the function's contract.
    let tiles = &unsafe { &*passed }.tiles;
    for (at, &(column, row)) in tiles.iter().enumerate() {
        // SAFETY: see the function's contract.
        unsafe { out.add(2 * at).write(column) };
        // SAFETY: see the function's contract.
        unsafe { out.add(2 * at + 1).write(row) };
    }
}

/// How many runs of what the pixels held the pass kept, every tile's.
///
/// # Safety
/// `passed` is live.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_cel_passed_run_count(passed: *const Passed) -> usize {
    // SAFETY: see the function's contract.
    unsafe { &*passed }.runs.iter().map(Vec::len).sum()
}

/// Writes every run — its value (the channel's byte i in bits 8i) and its
/// length —, in the walk's order.
///
/// # Safety
/// `passed` is live and `out` holds two words a run.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_cel_passed_runs(passed: *const Passed, out: *mut u32) {
    // SAFETY: see the function's contract.
    let runs = unsafe { &*passed }.runs.iter().flatten();
    for (at, &(value, length)) in runs.enumerate() {
        // SAFETY: see the function's contract.
        unsafe { out.add(2 * at).write(value) };
        // SAFETY: see the function's contract.
        unsafe { out.add(2 * at + 1).write(length) };
    }
}

/// Puts the `count` walked tiles from `first` on, each a pixel of took part
/// in, in a fresh slot of `cel`: `Passed::land`. Writes each one's `places`
/// and `changes` as `gpu_engine_stroke_land` does and returns how many
/// landed, the first of them; -1 on failure, see the last error.
///
/// # Safety
/// Every pointer is live, on `engine`; each of `places` and `changes` holds
/// `count`.
#[unsafe(no_mangle)]
#[allow(clippy::too_many_arguments)]
pub unsafe extern "C" fn gpu_engine_cel_passed_land(
    passed: *const Passed,
    engine: *const Engine,
    pool: *mut Pool,
    cel: u32,
    first: usize,
    count: usize,
    places: *mut u32,
    changes: *mut u8,
) -> isize {
    // SAFETY: see the function's contract.
    let (passed, engine, pool) = unsafe { (&*passed, &*engine, &mut *pool) };
    engine.on_thread(|| {
        let landed = passed.land(engine, (pool, Cel(cel)), first..first + count);
        // SAFETY: see the function's contract.
        unsafe { reported(landed, places, changes) }
    })
}

/// The scan, compiled. Null on failure; see the last error.
///
/// # Safety
/// `engine` is live; the scan is freed before it.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_ink_new(engine: *const Engine) -> *mut Ink {
    // SAFETY: see the function's contract.
    let engine = unsafe { &*engine };
    engine.on_thread(|| {
        Ink::new(engine).map_or(std::ptr::null_mut(), |ink| engine.hands(ink))
    })
}

/// # Safety
/// `ink` came from `gpu_engine_ink_new`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_ink_free(ink: *mut Ink) {
    // SAFETY: see the function's contract.
    unsafe { let_go(ink) };
}

/// Scans the cel of `columns` × `rows` tiles whose top-left is column `x0`,
/// row `y0` — `tiles` row by row, each `page << 16 | slot` of `pool`, or
/// `u32::MAX` for a tile it has none of — and puts each walked tile's
/// [`TILE_INK_WORDS`] into `out`, in the walk's order: row by row, the
/// tiles it has none of left out. Waits for the GPU.
///
/// Returns how many tiles it walked; -1 where `out`'s `capacity` words
/// hold fewer than a walked tile's words each, or the scan fails — see the
/// last error.
///
/// # Safety
/// Every pointer is live, the pool and the scan were made on `engine`;
/// `tiles` holds `columns × rows` words and `out` holds `capacity` — a
/// null `out` holds none, which a cel the walk finds no tile of needs.
#[unsafe(no_mangle)]
#[allow(clippy::too_many_arguments)]
pub unsafe extern "C" fn gpu_engine_ink_run(
    ink: *const Ink,
    engine: *const Engine,
    pool: *const Pool,
    x0: i32,
    y0: i32,
    columns: u32,
    rows: u32,
    tiles: *const u32,
    out: *mut i32,
    capacity: usize,
) -> isize {
    // SAFETY: see the function's contract.
    let (ink, engine, pool) = unsafe { (&*ink, &*engine, &*pool) };
    engine.on_thread(|| {
        // SAFETY: see the function's contract.
        let cel = unsafe { cel_of(pool, (x0, y0, columns, rows), tiles) };
        if !room_for(&cel, capacity) {
            return -1;
        }
        let Some(inks) = ink.run(engine, pool.pages(), &cel) else {
            return -1;
        };
        // SAFETY: `out` holds `capacity` words, which the walk's fit.
        unsafe { put_inks(&inks, out) }
    })
}

/// [`gpu_engine_ink_run`] with no wait for its caller: the cel's tiles
/// read where `pool` holds them now, the scan handed to the engine's
/// thread — which waits for no GPU either (`Ink::scanned_then`) — and
/// `told` called with `number` from a thread of the engine's once the GPU
/// has written the boxes, `out` and `walked` written first: how many tiles
/// it walked, or -1 — `told` false — where the scan failed or `out` holds
/// too few words.
///
/// 🗣️관제 2026-11-12 (the UI never waits for the GPU) — card
/// the-ui-isolate-still-waits-for-the-gpu-in-places W3.
///
/// # Safety
/// As [`gpu_engine_ink_run`]'s, `ink` let go of after this; `out` and
/// `walked` are live till `told` is called, and `told` is one any thread
/// may call.
#[unsafe(no_mangle)]
#[allow(clippy::too_many_arguments)]
pub unsafe extern "C" fn gpu_engine_ink_run_unwaited(
    ink: *const Ink,
    engine: *const Engine,
    pool: *const Pool,
    x0: i32,
    y0: i32,
    columns: u32,
    rows: u32,
    tiles: *const u32,
    out: *mut i32,
    capacity: usize,
    walked: *mut isize,
    told: extern "C" fn(u64, bool),
    number: u64,
) {
    // SAFETY: see the function's contract.
    let (engine, pool) = unsafe { (&*engine, &*pool) };
    // SAFETY: see the function's contract.
    let cel = unsafe { cel_of(pool, (x0, y0, columns, rows), tiles) };
    let scan = move |engine: &Engine, pages: &[wgpu::Buffer], then: Box<dyn FnOnce(Option<_>) + Send>| {
        if !room_for(&cel, capacity) {
            return then(None);
        }
        // SAFETY: let go of on this thread, after this (the contract).
        let ink = unsafe { &*ink };
        ink.scanned_then(engine, pages, &cel, then);
    };
    let answer = move |_: &Engine, inks: Option<Vec<TileInk>>| {
        // SAFETY: live till `told` is called, `out` holding `capacity`
        // words the walk's fit (the function's contract).
        let put = inks.map_or(-1, |inks| unsafe { put_inks(&inks, out) });
        // SAFETY: as above.
        unsafe { *walked = put };
        put >= 0
    };
    // SAFETY: what `scan` holds is let go of on the engine's thread, after
    // it; `out`, `walked` and `told` are the function's contract.
    engine.posted(unsafe { told_body(engine, pool, (told, number), scan, answer) });
}

/// Whether `capacity` words hold the [`TILE_INK_WORDS`] of each tile
/// `cel`'s walk takes — and the last error says why not where they do not.
fn room_for(cel: &TileSet, capacity: usize) -> bool {
    let walked = cel.tiles.iter().flatten().count();
    if walked * TILE_INK_WORDS <= capacity {
        return true;
    }
    fail::<()>(format!(
        "room for {capacity} words; the {walked} tiles walked put {}",
        walked * TILE_INK_WORDS
    ));
    false
}

/// Puts each of `inks`' [`TILE_INK_WORDS`] into `out`, in order: how many
/// it put.
///
/// # Safety
/// `out` holds as many words as `inks` take — none where it is null.
unsafe fn put_inks(inks: &[TileInk], out: *mut i32) -> isize {
    if inks.is_empty() {
        return 0;
    }
    // SAFETY: see the function's contract.
    let out = unsafe { std::slice::from_raw_parts_mut(out, inks.len() * TILE_INK_WORDS) };
    for (tile, words) in inks.iter().zip(out.chunks_exact_mut(TILE_INK_WORDS)) {
        let [left, top, right, bottom] = InkBox::words(tile.ink);
        words.copy_from_slice(&[tile.column, tile.row, left, top, right, bottom]);
    }
    inks.len() as isize
}

/// The cel as the app names it — `tiles` row by row, `columns` × `rows`
/// from column `x0`, row `y0` —, each tile where it lies on `pool`
/// ([`Named::lying`]). ⛔ONE: the lift, the verb and the ink scan each
/// spelled its reading.
///
/// # Safety
/// `tiles` holds `columns × rows` words.
unsafe fn cel_of(pool: &Pool, (x0, y0, columns, rows): (i32, i32, u32, u32), tiles: *const u32) -> TileSet {
    // SAFETY: see the function's contract.
    let words = unsafe { std::slice::from_raw_parts(tiles, columns as usize * rows as usize) };
    Named::from_words(x0, y0, columns, rows, words).lying(&pool.lying())
}
