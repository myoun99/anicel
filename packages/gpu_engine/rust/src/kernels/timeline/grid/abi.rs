//! The frame grid's C ABI (grid-on-the-engine ①, 관제 2026-11-08 16:42):
//! the app hands a tile's op stream — the words `TimelineGridTileOpWriter`
//! writes — and the A8 atlas its GLYPH ops read its letters from, and the
//! engine draws them into a picture of its own that stays on the GPU for
//! the view's screen to lay: nothing comes back but whether it drew.

#[cfg(test)]
mod tests;

use crate::device::Engine;

use super::lay::{GridLay, Laid};
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

/// Copies `picture`'s pixels — straight RGBA8, row by row — into `bytes`
/// once the GPU is done, `capacity` of them at most. False on failure; see
/// the last error.
///
/// # Safety
/// `engine` and `picture` are live and `bytes` holds `capacity`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_grid_picture_read(
    engine: *const Engine,
    picture: *const GridPicture,
    bytes: *mut u8,
    capacity: usize,
) -> bool {
    // SAFETY: see the function's contract.
    let (engine, picture) = unsafe { (&*engine, &*picture) };
    let Some(read) = engine.read_texture(&picture.texture) else {
        return false;
    };
    let count = read.len().min(capacity);
    // SAFETY: `bytes` holds `capacity`, and `count` is no more.
    unsafe { std::ptr::copy_nonoverlapping(read.as_ptr(), bytes, count) };
    true
}

/// Draws `ops` — `count` words — into `picture` over clear, its letters
/// read from `atlas`, `atlas_width` × `atlas_height` A8 bytes row by row —
/// none where a side is 0 —; submitted, not waited for ([`GridTile::run`]).
/// False for a stream the pass refuses, and on failure; see the last error.
///
/// ⚠️Over clear, always: a tile lays over its view's sheet (the store's
/// contract, timeline_grid_tile_store.dart), so the pass's background word
/// is nobody's to hand.
///
/// # Safety
/// Every pointer is live, made on `engine`; `ops` holds `count` words and
/// `atlas` `atlas_width × atlas_height` bytes.
#[unsafe(no_mangle)]
#[allow(clippy::too_many_arguments)]
pub unsafe extern "C" fn gpu_engine_grid_draw(
    grid: *mut GridTile,
    engine: *const Engine,
    picture: *const GridPicture,
    ops: *const i32,
    count: usize,
    atlas: *const u8,
    atlas_width: u32,
    atlas_height: u32,
) -> bool {
    // SAFETY: see the function's contract.
    let (grid, engine, picture) = unsafe { (&mut *grid, &*engine, &*picture) };
    // SAFETY: see the function's contract.
    let ops = unsafe { std::slice::from_raw_parts(ops, count) };
    let bytes = match atlas_width as usize * atlas_height as usize {
        // No atlas: its pointer may be null, which no slice may be.
        0 => &[][..],
        // SAFETY: see the function's contract.
        length => unsafe { std::slice::from_raw_parts(atlas, length) },
    };
    let Some(atlas) = atlas_of(engine, bytes, atlas_width, atlas_height) else {
        return false;
    };
    grid.run(engine, &picture.texture, 0, ops, atlas.as_ref()).is_some()
}

/// The screen pass that lays tiles on a view's screen ([`GridLay`]),
/// compiled for each format the first time it lays onto one.
#[unsafe(no_mangle)]
pub extern "C" fn gpu_engine_grid_lay_new() -> *mut GridLay {
    Box::into_raw(Box::new(GridLay::new()))
}

/// # Safety
/// `lay` came from `gpu_engine_grid_lay_new`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_grid_lay_free(lay: *mut GridLay) {
    if !lay.is_null() {
        // SAFETY: see the function's contract.
        drop(unsafe { Box::from_raw(lay) });
    }
}

/// The pixels `rect` of `target` — [left, top, right, bottom) — clear, and
/// the `count` tiles `pictures` laid over them, the i-th from `boxes[8i ..
/// 8i + 4]` of its own pixels onto `boxes[8i + 4 .. 8i + 8]` of the
/// screen's, each [left, top, right, bottom) ([`GridLay::lay`]); waits for
/// the GPU. `target` is what the view shows: a surface's texture
/// (`gpu_engine_surface_texture`) or a window's next image
/// (`gpu_engine_window_target`). False on failure; see the last error.
///
/// # Safety
/// Every pointer is live, made on `engine`; `rect` holds four words,
/// `pictures` `count` tiles and `boxes` `8 × count` doubles.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_grid_lay(
    lay: *mut GridLay,
    engine: *const Engine,
    target: *const wgpu::Texture,
    rect: *const u32,
    pictures: *const *const GridPicture,
    boxes: *const f64,
    count: usize,
) -> bool {
    // SAFETY: see the function's contract.
    let (lay, engine, target) = unsafe { (&mut *lay, &*engine, &*target) };
    // SAFETY: see the function's contract.
    let (rect, pictures, boxes) = unsafe {
        (
            *rect.cast::<[u32; 4]>(),
            std::slice::from_raw_parts(pictures, count),
            std::slice::from_raw_parts(boxes, 8 * count),
        )
    };
    let laid: Vec<Laid> = pictures
        .iter()
        .zip(boxes.chunks_exact(8))
        .map(|(&picture, edges)| Laid {
            // SAFETY: each tile is live (the function's contract).
            picture: unsafe { &*picture },
            from: [edges[0], edges[1], edges[2], edges[3]],
            onto: [edges[4], edges[5], edges[6], edges[7]],
        })
        .collect();
    lay.lay(engine, target, rect, &laid).is_some()
}
