//! The ink scan's C ABI (connection round 2, 잉크 상자 ㉢): the app hands
//! the tiles of a cel that owe a box — on the pool, named as a plan's tile
//! set is ([`TileSet::from_words`]) — and takes each walked tile's box,
//! as it takes C's `qa_alpha_bounds_tiles` answer today.
//!
//! The scan is no step of a plan: it reads the pool's pages and nothing
//! the executor composites, so a plan's shape (keys, chains, the mask) is
//! nothing to it.

#[cfg(test)]
mod tests;

use crate::device::Engine;
use crate::fail;
use crate::kernels::composite::TileSet;
use crate::kernels::pool::Pool;

use super::ink::Ink;

/// The words a walked tile's answer takes: its column and row, then its
/// box's left, top, right and bottom — tile-local, the far two past the
/// last column and row with ink (the app's `TileInkBounds`). A tile with
/// no ink is a box of four 0s, which is empty as the app reads one
/// (`rightExclusive <= left`); a box with ink always ends past its start.
pub(crate) const TILE_INK_WORDS: usize = 6;

/// The scan, compiled. Null on failure; see the last error.
///
/// # Safety
/// `engine` is live; the scan is freed before it.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_ink_new(engine: *const Engine) -> *mut Ink {
    // SAFETY: see the function's contract.
    let engine = unsafe { &*engine };
    Ink::new(engine).map_or(std::ptr::null_mut(), |ink| Box::into_raw(Box::new(ink)))
}

/// # Safety
/// `ink` came from `gpu_engine_ink_new`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_ink_free(ink: *mut Ink) {
    if !ink.is_null() {
        // SAFETY: see the function's contract.
        drop(unsafe { Box::from_raw(ink) });
    }
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
    // SAFETY: see the function's contract.
    let words = unsafe { std::slice::from_raw_parts(tiles, columns as usize * rows as usize) };
    let cel = TileSet::from_words(x0, y0, columns, rows, words);
    let walked = cel.tiles.iter().flatten().count();
    if walked * TILE_INK_WORDS > capacity {
        fail::<()>(format!(
            "room for {capacity} words; the {walked} tiles walked put {}",
            walked * TILE_INK_WORDS
        ));
        return -1;
    }
    let Some(inks) = ink.run(engine, pool.pages(), &cel) else {
        return -1;
    };
    if inks.is_empty() {
        return 0;
    }
    // SAFETY: `out` holds `capacity` words, and the walk's are no more.
    let out = unsafe { std::slice::from_raw_parts_mut(out, walked * TILE_INK_WORDS) };
    for (tile, words) in inks.iter().zip(out.chunks_exact_mut(TILE_INK_WORDS)) {
        let [left, top, right, bottom] =
            tile.ink.map_or([0; 4], |ink| [ink.left, ink.top, ink.right, ink.bottom].map(|edge| edge as i32));
        words.copy_from_slice(&[tile.column, tile.row, left, top, right, bottom]);
    }
    inks.len() as isize
}
