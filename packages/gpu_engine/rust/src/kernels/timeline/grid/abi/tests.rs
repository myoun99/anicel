//! The frame grid's C ABI on a real GPU, checked by hand: a tile drawn
//! through it holds what its stream says, its letters read from the words
//! where their places put them, and what it cannot make or draw is refused
//! with why.

use super::*;
use crate::testing::{first_engine, last_error};

const FILL_RECT: i32 = 1;
const GLYPH: i32 = 4;

/// An RGBA word, as the grids pack one.
fn rgba(r: u32, g: u32, b: u32, a: u32) -> i32 {
    (r | g << 8 | b << 16 | a << 24) as i32
}

/// A `width` × `height` tile made through the ABI.
fn picture(width: u32, height: u32) -> *mut GridPicture {
    // SAFETY: the engine is live.
    unsafe { gpu_engine_grid_picture_new(first_engine(), width, height) }
}

/// An atlas: where its bytes lie, row by row, and its sides.
type Atlas = (*const u8, u32, u32);

/// No atlas: nothing pointed at, of no side — as a C caller may hand one.
const NO_ATLAS: Atlas = (std::ptr::null(), 0, 0);

/// `ops` drawn into a fresh `size` tile through the ABI, its letters from
/// `atlas`: whether it drew, and the tile's bytes.
fn drawn(size: (u32, u32), ops: &[i32], (atlas, width, height): Atlas) -> (bool, Vec<u8>) {
    let engine = first_engine();
    // SAFETY: the engine is live.
    let grid = unsafe { gpu_engine_grid_new(engine) };
    let tile = picture(size.0, size.1);
    assert!(!tile.is_null(), "{}", last_error());
    // SAFETY: every pointer is live and holds what it is said to.
    let ok = unsafe { gpu_engine_grid_draw(grid, engine, tile, ops.as_ptr(), ops.len(), atlas, width, height) };
    let mut bytes = vec![0; (size.0 * size.1 * 4) as usize];
    // SAFETY: both came from their news, and `bytes` holds its length.
    let read = unsafe { gpu_engine_grid_picture_read(engine, tile, bytes.as_mut_ptr(), bytes.len()) };
    assert!(read, "{}", last_error());
    // SAFETY: as above, each let go of once.
    unsafe {
        gpu_engine_grid_picture_free(tile);
        gpu_engine_grid_free(grid);
    }
    (ok, bytes)
}

/// The pixel at (x, y) of a tile `width` across.
fn at(bytes: &[u8], width: u32, x: u32, y: u32) -> [u8; 4] {
    let i = ((y * width + x) * 4) as usize;
    [bytes[i], bytes[i + 1], bytes[i + 2], bytes[i + 3]]
}

#[test]
fn a_tile_of_no_side_or_past_the_device_is_refused_with_why() {
    let most = first_engine().device.limits().max_texture_dimension_2d;
    for (width, height) in [(0, 4), (4, 0), (most + 1, 4), (4, most + 1)] {
        assert!(picture(width, height).is_null(), "{width} × {height}");
        assert!(last_error().contains(&format!("a grid tile {width} × {height}")), "{}", last_error());
    }
    let largest = picture(most, 1);
    assert!(!largest.is_null(), "{}", last_error());
    // SAFETY: it came from its new.
    unsafe { gpu_engine_grid_picture_free(largest) };
}

#[test]
fn a_stream_drawn_through_the_abi_is_over_clear() {
    let red = rgba(255, 0, 0, 255);
    let (ok, bytes) = drawn((4, 3), &[FILL_RECT, 1, 1, 2, 1, red], NO_ATLAS);
    assert!(ok, "{}", last_error());
    assert_eq!(at(&bytes, 4, 1, 1), [255, 0, 0, 255]);
    assert_eq!(at(&bytes, 4, 2, 1), [255, 0, 0, 255]);
    for (x, y) in [(0, 0), (0, 1), (3, 1), (1, 2), (3, 2)] {
        assert_eq!(at(&bytes, 4, x, y), [0; 4], "({x}, {y})");
    }
}

// A read copies as many bytes as it is handed room for, and no more.
#[test]
fn a_tile_read_through_the_abi_fills_the_room_it_is_handed() {
    let engine = first_engine();
    // SAFETY: the engine is live.
    let grid = unsafe { gpu_engine_grid_new(engine) };
    let tile = picture(2, 1);
    let ops = [FILL_RECT, 0, 0, 2, 1, rgba(255, 0, 0, 255)];
    // SAFETY: every pointer is live and holds what it is said to.
    assert!(unsafe { gpu_engine_grid_draw(grid, engine, tile, ops.as_ptr(), ops.len(), NO_ATLAS.0, 0, 0) });
    let mut bytes = [7; 8];
    // SAFETY: as above; `bytes` holds 8, and the read is handed 4.
    assert!(unsafe { gpu_engine_grid_picture_read(engine, tile, bytes.as_mut_ptr(), 4) }, "{}", last_error());
    assert_eq!(bytes, [255, 0, 0, 255, 7, 7, 7, 7]);
    // SAFETY: each came from its new, let go of once.
    unsafe {
        gpu_engine_grid_picture_free(tile);
        gpu_engine_grid_free(grid);
    }
}

// An atlas of two words, the second below and right of the first: each
// letter reads the atlas where its op says. Opaque white scaled by a
// coverage c over clear is white at c, stored straight.
#[test]
fn a_letter_reads_the_atlas_where_its_op_says() {
    // 3 × 3: [255, 128] at (0, 0), [64] over [32] at (2, 1).
    let letters = [255, 128, 0, 0, 0, 64, 0, 0, 32];
    let atlas: Atlas = (letters.as_ptr(), 3, 3);
    let white = rgba(255, 255, 255, 255);
    let ops = [[GLYPH, 0, 0, 0, 0, 2, 1, white], [GLYPH, 3, 0, 2, 1, 1, 2, white]].concat();
    let (ok, bytes) = drawn((4, 2), &ops, atlas);
    assert!(ok, "{}", last_error());
    assert_eq!(at(&bytes, 4, 0, 0), [255; 4]);
    assert_eq!(at(&bytes, 4, 1, 0), [255, 255, 255, 128]);
    assert_eq!(at(&bytes, 4, 3, 0), [255, 255, 255, 64]);
    assert_eq!(at(&bytes, 4, 3, 1), [255, 255, 255, 32]);
    // What lies between the words in the atlas is nothing.
    let (_, between) = drawn((2, 2), &[GLYPH, 0, 0, 0, 1, 2, 1, white], atlas);
    assert_eq!(at(&between, 2, 0, 0), [0; 4]);
    assert_eq!(at(&between, 2, 1, 0), [0; 4]);
}

#[test]
fn a_stream_the_pass_refuses_draws_nothing_and_says_why() {
    let white = rgba(255, 255, 255, 255);
    let (ok, bytes) = drawn((2, 2), &[GLYPH, 0, 0, 0, 0, 1, 1, white], NO_ATLAS);
    assert!(!ok);
    assert!(last_error().contains("has no atlas"), "{}", last_error());
    assert!(bytes.iter().all(|&byte| byte == 0));
}

#[test]
fn an_atlas_past_the_device_is_refused_with_why() {
    let most = first_engine().device.limits().max_texture_dimension_2d;
    let long = vec![255; most as usize + 1];
    for (width, height) in [(most + 1, 1), (1, most + 1)] {
        let (ok, _) = drawn((1, 1), &[], (long.as_ptr(), width, height));
        assert!(!ok, "{width} × {height}");
        assert!(last_error().contains(&format!("a letters' atlas {width} × {height}")), "{}", last_error());
    }
    for (width, height) in [(most, 1), (1, most)] {
        let (ok, _) = drawn((1, 1), &[], (long[1..].as_ptr(), width, height));
        assert!(ok, "an atlas {width} × {height}, as long as the device makes: {}", last_error());
    }
}

// Through the ABI a box is eight doubles, the tile's part then the
// screen's: the right half of a red-and-green tile laid on the screen's
// top-left pixel is green there, and the rest of the rect — the pixel
// below it among it — is made clear.
#[test]
fn a_tile_laid_through_the_abi_takes_its_part_onto_the_screens() {
    let engine = first_engine();
    // SAFETY: the engine is live.
    let grid = unsafe { gpu_engine_grid_new(engine) };
    let tile = picture(2, 1);
    let ops = [[FILL_RECT, 0, 0, 1, 1, rgba(255, 0, 0, 255)], [FILL_RECT, 1, 0, 1, 1, rgba(0, 255, 0, 255)]].concat();
    // SAFETY: every pointer is live and holds what it is said to.
    let drew = unsafe { gpu_engine_grid_draw(grid, engine, tile, ops.as_ptr(), ops.len(), NO_ATLAS.0, 0, 0) };
    assert!(drew, "{}", last_error());
    let screen = crate::device::storage_texture(&engine.device, 3, 2, wgpu::TextureFormat::Rgba8Unorm);
    let lay = gpu_engine_grid_lay_new();
    let tiles = [tile.cast_const()];
    let laid = |rect: [u32; 4], boxes: [f64; 8]| {
        // SAFETY: as above.
        unsafe { gpu_engine_grid_lay(lay, engine, &screen, rect.as_ptr(), tiles.as_ptr(), boxes.as_ptr(), 1) }
    };
    assert!(laid([0, 0, 3, 2], [1.0, 0.0, 2.0, 1.0, 0.0, 0.0, 1.0, 1.0]), "{}", last_error());
    let bytes = engine.read_texture(&screen).expect("read back");
    let mut want = vec![0; 4 * 6];
    want[..4].copy_from_slice(&[0, 255, 0, 255]);
    assert_eq!(bytes, want);
    assert!(!laid([0, 0, 4, 2], [0.0, 0.0, 2.0, 1.0, 0.0, 0.0, 2.0, 1.0]));
    assert!(last_error().contains("is no rectangle of a 3 × 2 screen"), "{}", last_error());
    // SAFETY: each came from its new, let go of once.
    unsafe {
        gpu_engine_grid_lay_free(lay);
        gpu_engine_grid_picture_free(tile);
        gpu_engine_grid_free(grid);
    }
}
