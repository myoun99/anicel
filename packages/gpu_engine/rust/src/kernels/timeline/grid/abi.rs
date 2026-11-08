//! The frame grid's C ABI (grid-on-the-engine ①, 관제 2026-11-08 16:42):
//! the app hands a tile's op stream — the words `TimelineGridTileOpWriter`
//! writes — and the words its letters are read from, each where the
//! stream's GLYPH ops say it lies in the atlas, and the engine draws them
//! into a picture of its own that stays on the GPU for the view's screen
//! to lay: nothing comes back but whether it drew.

#[cfg(test)]
mod tests;

use crate::device::Engine;
use crate::kernels::letters::words::WordCover;

use super::{GridPicture, GridTile, atlas_of};

/// The tile pass, compiled for each format the first time it draws one.
///
/// # Safety
/// `engine` is live; the pass is freed before it.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_grid_new(engine: *const Engine) -> *mut GridTile {
    // SAFETY: see the function's contract.
    let engine = unsafe { &*engine };
    Box::into_raw(Box::new(GridTile::new(engine)))
}

/// # Safety
/// `grid` came from `gpu_engine_grid_new`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_grid_free(grid: *mut GridTile) {
    if !grid.is_null() {
        // SAFETY: see the function's contract.
        drop(unsafe { Box::from_raw(grid) });
    }
}

/// A clear tile `width` × `height` pixels. Null on failure; see the last
/// error.
///
/// # Safety
/// `engine` is live; the tile is freed before it.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_grid_picture_new(engine: *const Engine, width: u32, height: u32) -> *mut GridPicture {
    // SAFETY: see the function's contract.
    let engine = unsafe { &*engine };
    GridPicture::new(engine, width, height).map_or(std::ptr::null_mut(), |picture| Box::into_raw(Box::new(picture)))
}

/// # Safety
/// `picture` came from `gpu_engine_grid_picture_new`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_grid_picture_free(picture: *mut GridPicture) {
    if !picture.is_null() {
        // SAFETY: see the function's contract.
        drop(unsafe { Box::from_raw(picture) });
    }
}

/// Draws `ops` — `count` words — into `picture` over clear, its letters
/// read from an atlas of `words`, the i-th with its top-left at
/// `places[2i]`, `places[2i + 1]`; and waits for the GPU. False for a
/// stream the pass refuses, and on failure; see the last error.
///
/// ⚠️Over clear, always: a tile lays over its view's sheet (the store's
/// contract, timeline_grid_tile_store.dart), so the pass's background word
/// is nobody's to hand.
///
/// # Safety
/// Every pointer is live, made on `engine`; `ops` holds `count` words,
/// `words` `word_count` covers and `places` `2 × word_count`.
#[unsafe(no_mangle)]
#[allow(clippy::too_many_arguments)]
pub unsafe extern "C" fn gpu_engine_grid_draw(
    grid: *mut GridTile,
    engine: *const Engine,
    picture: *const GridPicture,
    ops: *const i32,
    count: usize,
    words: *const *const WordCover,
    places: *const u32,
    word_count: usize,
) -> bool {
    // SAFETY: see the function's contract.
    let (grid, engine, picture) = unsafe { (&mut *grid, &*engine, &*picture) };
    // SAFETY: see the function's contract.
    let (ops, words, places) = unsafe {
        (
            std::slice::from_raw_parts(ops, count),
            std::slice::from_raw_parts(words, word_count),
            std::slice::from_raw_parts(places, 2 * word_count),
        )
    };
    let laid: Vec<(&WordCover, [u32; 2])> = words
        .iter()
        .zip(places.chunks_exact(2))
        // SAFETY: each cover is live (the function's contract).
        .map(|(&word, place)| (unsafe { &*word }, [place[0], place[1]]))
        .collect();
    let Some(atlas) = atlas_of(engine, &laid) else {
        return false;
    };
    grid.run(engine, &picture.texture, 0, ops, atlas.as_ref()).is_some()
}
