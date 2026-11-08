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

/// `ops` drawn into a fresh `size` tile through the ABI, its letters from
/// `words` at their places: whether it drew, and the tile's bytes.
fn drawn(size: (u32, u32), ops: &[i32], words: &[(&WordCover, [u32; 2])]) -> (bool, Vec<u8>) {
    let engine = first_engine();
    // SAFETY: the engine is live.
    let grid = unsafe { gpu_engine_grid_new(engine) };
    let tile = picture(size.0, size.1);
    assert!(!tile.is_null(), "{}", last_error());
    let covers: Vec<*const WordCover> = words.iter().map(|(word, _)| *word as *const _).collect();
    let places: Vec<u32> = words.iter().flat_map(|(_, place)| *place).collect();
    // A binding of none is still a pointer, as the app hands one.
    let (covers, places) = (
        if covers.is_empty() { vec![std::ptr::null()] } else { covers },
        if places.is_empty() { vec![0] } else { places },
    );
    // SAFETY: every pointer is live and holds what it is said to.
    let ok = unsafe {
        gpu_engine_grid_draw(grid, engine, tile, ops.as_ptr(), ops.len(), covers.as_ptr(), places.as_ptr(), words.len())
    };
    // SAFETY: both came from their news.
    let bytes = unsafe { engine.read_texture(&(*tile).texture).expect("read back") };
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
    let (ok, bytes) = drawn((4, 3), &[FILL_RECT, 1, 1, 2, 1, red], &[]);
    assert!(ok, "{}", last_error());
    assert_eq!(at(&bytes, 4, 1, 1), [255, 0, 0, 255]);
    assert_eq!(at(&bytes, 4, 2, 1), [255, 0, 0, 255]);
    for (x, y) in [(0, 0), (0, 1), (3, 1), (1, 2), (3, 2)] {
        assert_eq!(at(&bytes, 4, x, y), [0; 4], "({x}, {y})");
    }
}

// Two words in an atlas, the second below and right of the first: each
// letter reads its word where its place put it. Opaque white scaled by a
// coverage c over clear is c in every channel.
#[test]
fn a_letter_reads_its_word_where_its_place_put_it() {
    let first = WordCover { width: 2, height: 1, bytes: vec![255, 128] };
    let second = WordCover { width: 1, height: 2, bytes: vec![64, 32] };
    let white = rgba(255, 255, 255, 255);
    let ops = [[GLYPH, 0, 0, 0, 0, 2, 1, white], [GLYPH, 3, 0, 2, 1, 1, 2, white]].concat();
    let (ok, bytes) = drawn((4, 2), &ops, &[(&first, [0, 0]), (&second, [2, 1])]);
    assert!(ok, "{}", last_error());
    assert_eq!(at(&bytes, 4, 0, 0), [255; 4]);
    assert_eq!(at(&bytes, 4, 1, 0), [128; 4]);
    assert_eq!(at(&bytes, 4, 3, 0), [64; 4]);
    assert_eq!(at(&bytes, 4, 3, 1), [32; 4]);
    // What lies between the words in the atlas is nothing.
    let (_, between) = drawn((2, 2), &[GLYPH, 0, 0, 0, 1, 2, 1, white], &[(&first, [0, 0]), (&second, [2, 1])]);
    assert_eq!(at(&between, 2, 0, 0), [0; 4]);
    assert_eq!(at(&between, 2, 1, 0), [0; 4]);
}

#[test]
fn a_stream_the_pass_refuses_draws_nothing_and_says_why() {
    let white = rgba(255, 255, 255, 255);
    let (ok, bytes) = drawn((2, 2), &[GLYPH, 0, 0, 0, 0, 1, 1, white], &[]);
    assert!(!ok);
    assert!(last_error().contains("has no atlas"), "{}", last_error());
    assert!(bytes.iter().all(|&byte| byte == 0));
}

#[test]
fn an_atlas_past_the_device_is_refused_with_why() {
    let most = first_engine().device.limits().max_texture_dimension_2d;
    let word = WordCover { width: 1, height: 1, bytes: vec![255] };
    let (ok, _) = drawn((1, 1), &[], &[(&word, [most, 0])]);
    assert!(!ok);
    assert!(last_error().contains(&format!("a letters' atlas {} × 1", most + 1)), "{}", last_error());
    let (ok, _) = drawn((1, 1), &[], &[(&word, [most - 1, 0])]);
    assert!(ok, "an atlas as wide as the device makes: {}", last_error());
    // A place past the last pixel — a negative one, as a Uint32 reads it.
    let (ok, _) = drawn((1, 1), &[], &[(&word, [u32::MAX, 0])]);
    assert!(!ok);
    assert!(last_error().contains("past its 4294967295th pixel"), "{}", last_error());
}
