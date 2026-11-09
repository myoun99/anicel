//! The screen pass on a real GPU, against pixels set by hand: tiles the
//! tile pass draws (tests.rs has it checked), laid and read back here alone
//! — a test may read a screen, the app never does (관제 11-05 14:02).

use std::ops::Range;

use super::super::{GridPicture, GridTile};
use super::{GridLay, Laid};
use crate::device::{Engine, storage_texture};
use crate::testing::{first_engine, last_error};

const RGBA: wgpu::TextureFormat = wgpu::TextureFormat::Rgba8Unorm;
const BGRA: wgpu::TextureFormat = wgpu::TextureFormat::Bgra8Unorm;

const FILL_RECT: i32 = 1;

const RED: [u8; 4] = [255, 0, 0, 255];
const GREEN: [u8; 4] = [0, 255, 0, 255];
const BLUE: [u8; 4] = [0, 0, 255, 255];
const CLEAR: [u8; 4] = [0; 4];

/// An RGBA word, as the grids pack one.
fn word([r, g, b, a]: [u8; 4]) -> i32 {
    i32::from_le_bytes([r, g, b, a])
}

/// A tile `width` × `height` of the fills `fills` — (x, y, w, h, colour)
/// each, in pixels — over clear, drawn by the tile pass.
fn picture(engine: &Engine, (width, height): (u32, u32), fills: &[(i32, i32, i32, i32, [u8; 4])]) -> GridPicture {
    let picture = GridPicture::new(engine, width, height).expect("a tile");
    let ops: Vec<i32> = fills
        .iter()
        .flat_map(|&(x, y, w, h, colour)| [FILL_RECT, x, y, w, h, word(colour)])
        .collect();
    GridTile::new(engine).run(engine, &picture.texture, 0, &ops, None).expect("the tile pass draws");
    picture
}

/// A tile of one colour.
fn plain(engine: &Engine, (width, height): (u32, u32), colour: [u8; 4]) -> GridPicture {
    picture(engine, (width, height), &[(0, 0, width as i32, height as i32, colour)])
}

/// `screen` with `laid` over its `rect`, read back.
fn laid_on(engine: &Engine, screen: &wgpu::Texture, rect: [u32; 4], laid: &[Laid]) -> Vec<u8> {
    GridLay::new().lay(engine, screen, rect, laid).unwrap_or_else(|| panic!("{}", last_error()));
    engine.read_texture(screen).expect("the screen reads back")
}

/// The pixel at (x, y) of a screen `width` across.
fn at(bytes: &[u8], width: u32, x: u32, y: u32) -> [u8; 4] {
    let i = ((y * width + x) * 4) as usize;
    [bytes[i], bytes[i + 1], bytes[i + 2], bytes[i + 3]]
}

// (200, 100, 50) at 128 over clear is stored straight, and laid
// premultiplied as premultiply.wgsl rounds — p = ka + 128, then
// (p + (p >> 8)) >> 8: 25728 → 100, 12928 → 50, 6528 → 25.
#[test]
fn a_tile_laid_at_whole_pixels_is_its_pixels_premultiplied() {
    let engine = first_engine();
    let tile = picture(engine, (3, 2), &[(0, 0, 2, 2, [200, 100, 50, 128]), (2, 0, 1, 2, RED)]);
    let screen = storage_texture(&engine.device, 5, 4, RGBA);
    let laid = [Laid { picture: &tile, from: [0.0, 0.0, 3.0, 2.0], onto: [1.0, 1.0, 4.0, 3.0] }];
    let bytes = laid_on(engine, &screen, [0, 0, 5, 4], &laid);
    for (x, y) in [(1, 1), (2, 2)] {
        assert_eq!(at(&bytes, 5, x, y), [100, 50, 25, 128], "({x}, {y})");
    }
    assert_eq!(at(&bytes, 5, 3, 1), RED);
    for (x, y) in [(0, 0), (0, 1), (4, 1), (1, 3), (4, 3)] {
        assert_eq!(at(&bytes, 5, x, y), CLEAR, "({x}, {y})");
    }
}

#[test]
fn a_pixel_is_laid_by_the_tile_whose_box_holds_its_centre() {
    let engine = first_engine();
    let (green, blue) = (plain(engine, (2, 1), GREEN), plain(engine, (2, 1), BLUE));
    let screen = storage_texture(&engine.device, 4, 1, RGBA);
    // Pixel 1's centre, 1.5, is where the green box ends and the blue one
    // begins: it is the blue one's alone.
    let laid = [
        Laid { picture: &green, from: [0.0, 0.0, 2.0, 1.0], onto: [0.0, 0.0, 1.5, 1.0] },
        Laid { picture: &blue, from: [0.0, 0.0, 2.0, 1.0], onto: [1.5, 0.0, 3.0, 1.0] },
    ];
    let bytes = laid_on(engine, &screen, [0, 0, 4, 1], &laid);
    let pixels: Vec<[u8; 4]> = (0..4).map(|x| at(&bytes, 4, x, 0)).collect();
    assert_eq!(pixels, [GREEN, BLUE, BLUE, CLEAR]);
}

#[test]
fn a_stand_in_is_stretched_by_the_texel_each_centre_lands_on() {
    let engine = first_engine();
    let tile = picture(engine, (2, 1), &[(0, 0, 1, 1, RED), (1, 0, 1, 1, GREEN)]);
    let screen = storage_texture(&engine.device, 6, 1, RGBA);
    // Twice over: the centres 0.5 · 1.5 land at 0.25 · 0.75, the red texel;
    // 2.5 · 3.5 at 1.25 · 1.75, the green. Then the green half alone, over
    // two pixels.
    let laid = [
        Laid { picture: &tile, from: [0.0, 0.0, 2.0, 1.0], onto: [0.0, 0.0, 4.0, 1.0] },
        Laid { picture: &tile, from: [1.0, 0.0, 2.0, 1.0], onto: [4.0, 0.0, 6.0, 1.0] },
    ];
    let bytes = laid_on(engine, &screen, [0, 0, 6, 1], &laid);
    let pixels: Vec<[u8; 4]> = (0..6).map(|x| at(&bytes, 6, x, 0)).collect();
    assert_eq!(pixels, [RED, RED, GREEN, GREEN, GREEN, GREEN]);
}

// A tile laid a third of a pixel off whole pixels joins the next one with
// no pixel of less ink between them — Blend's tent would fade both toward
// the edge they meet at (lay.rs `laid_by`).
#[test]
fn tiles_laid_off_whole_pixels_join_with_no_seam() {
    let engine = first_engine();
    let (red, green) = (plain(engine, (3, 1), RED), plain(engine, (3, 1), GREEN));
    let screen = storage_texture(&engine.device, 8, 1, RGBA);
    let third = 1.0 / 3.0;
    let laid = [
        Laid { picture: &red, from: [0.0, 0.0, 3.0, 1.0], onto: [third, 0.0, 3.0 + third, 1.0] },
        Laid { picture: &green, from: [0.0, 0.0, 3.0, 1.0], onto: [3.0 + third, 0.0, 6.0 + third, 1.0] },
    ];
    let bytes = laid_on(engine, &screen, [0, 0, 8, 1], &laid);
    let pixels: Vec<[u8; 4]> = (0..8).map(|x| at(&bytes, 8, x, 0)).collect();
    assert_eq!(pixels, [RED, RED, RED, GREEN, GREEN, GREEN, CLEAR, CLEAR]);
}

/// The span [from, to) of a strip a pixel thick, along x or down y.
fn strip(down: bool, from: f64, to: f64) -> [f64; 4] {
    if down { [0.0, from, 1.0, to] } else { [from, 0.0, to, 1.0] }
}

/// A strip's tile of one colour.
fn strip_tile(engine: &Engine, down: bool, length: u32, colour: [u8; 4]) -> GridPicture {
    plain(engine, if down { (1, length) } else { (length, 1) }, colour)
}

/// `laid` over the pixels `span` of a strip, read back along it.
fn strip_laid(engine: &Engine, down: bool, length: u32, span: Range<u32>, laid: &[Laid]) -> Vec<[u8; 4]> {
    let (width, height) = if down { (1, length) } else { (length, 1) };
    let screen = storage_texture(&engine.device, width, height, RGBA);
    let rect = if down { [0, span.start, 1, span.end] } else { [span.start, 0, span.end, 1] };
    let bytes = laid_on(engine, &screen, rect, laid);
    span.map(|p| if down { at(&bytes, width, 0, p) } else { at(&bytes, width, p, 0) }).collect()
}

// A span of 539 points at a ratio of 1.5 ends at 808.5 and its tile is 809
// wide, so a tile is stretched by 809/808.5 and the next one starts on a
// pixel's centre. R1's scale is a Q.20 word, a hair under that stretch: the
// pixel on the edge landed 0.0004 before the tile (S5 at 312 %, a column of
// the sheet showing through a block, card
// the-grid-screen-lets-a-frame-line-through-a-white-block).
#[test]
fn a_pixel_centred_on_a_tiles_edge_reads_the_tile() {
    let engine = first_engine();
    for down in [false, true] {
        let (red, green) = (strip_tile(engine, down, 809, RED), strip_tile(engine, down, 809, GREEN));
        let whole = strip(down, 0.0, 809.0);
        let laid = [
            Laid { picture: &red, from: whole, onto: strip(down, 0.0, 808.5) },
            Laid { picture: &green, from: whole, onto: strip(down, 808.5, 1617.0) },
        ];
        let pixels = strip_laid(engine, down, 1700, 806..811, &laid);
        assert_eq!(pixels, [RED, RED, GREEN, GREEN, GREEN], "down: {down}");
    }
}

// The far end of the same stretch, its scale a hair over it this time, and
// a centre a double's noise inside the box: the last pixel landed on the
// column after the tile's.
#[test]
fn a_pixel_centred_a_hair_inside_a_tiles_far_edge_reads_the_tile() {
    let engine = first_engine();
    for down in [false, true] {
        let red = strip_tile(engine, down, 811, RED);
        let laid = [Laid {
            picture: &red,
            from: strip(down, 0.0, 811.0),
            onto: strip(down, 0.0, 810.5 + 1e-9),
        }];
        let pixels = strip_laid(engine, down, 900, 808..813, &laid);
        assert_eq!(pixels, [RED, RED, RED, CLEAR, CLEAR], "down: {down}");
    }
}

#[test]
fn what_no_tile_holds_is_made_clear_and_past_the_rect_is_left_as_it_was() {
    let engine = first_engine();
    let tile = plain(engine, (4, 1), RED);
    let screen = storage_texture(&engine.device, 4, 1, RGBA);
    let whole = [Laid { picture: &tile, from: [0.0, 0.0, 4.0, 1.0], onto: [0.0, 0.0, 4.0, 1.0] }];
    laid_on(engine, &screen, [0, 0, 4, 1], &whole);
    let bytes = laid_on(engine, &screen, [1, 0, 3, 1], &[]);
    let pixels: Vec<[u8; 4]> = (0..4).map(|x| at(&bytes, 4, x, 0)).collect();
    assert_eq!(pixels, [RED, CLEAR, CLEAR, RED]);
}

#[test]
fn a_bgra_screen_holds_the_same_pixels_in_its_order() {
    let engine = first_engine();
    let tile = plain(engine, (1, 1), RED);
    let screen = storage_texture(&engine.device, 1, 1, BGRA);
    let laid = [Laid { picture: &tile, from: [0.0, 0.0, 1.0, 1.0], onto: [0.0, 0.0, 1.0, 1.0] }];
    assert_eq!(laid_on(engine, &screen, [0, 0, 1, 1], &laid), [0, 0, 255, 255]);
}

// ⚠️By their text, for what no pixel here shows: a lay has one clear to
// lose and lost it about once in forty thousand under load, and two passes
// held on this GPU with or without the barrier (`land_storage_writes`).
#[test]
fn a_lay_lands_its_clear_before_it_lays_a_tile() {
    let block = "let (clear, tiles) = encoded.split_at(1);\n        \
                 encode_on(engine, &mut encoder, clear);\n        \
                 land_storage_writes(&mut encoder, target);\n        \
                 encode_on(engine, &mut encoder, tiles);";
    assert!(include_str!("lay.rs").replace("\r\n", "\n").contains(block));
}

#[test]
fn a_lay_past_its_screen_or_its_tile_is_refused_with_why() {
    let engine = first_engine();
    let tile = plain(engine, (2, 2), RED);
    let screen = storage_texture(&engine.device, 4, 4, RGBA);
    let mut lay = GridLay::new();
    let one = |from: [f64; 4], onto: [f64; 4]| [Laid { picture: &tile, from, onto }];
    assert!(lay.lay(engine, &screen, [0, 0, 5, 4], &[]).is_none());
    assert!(last_error().contains("is no rectangle of a 4 × 4 screen"), "{}", last_error());
    assert!(lay.lay(engine, &screen, [2, 0, 2, 4], &[]).is_none());
    assert!(lay.lay(engine, &screen, [0, 0, 4, 4], &one([0.0, 0.0, 2.5, 2.0], [0.0; 4])).is_none());
    assert!(last_error().contains("laid from [0.0, 0.0, 2.5, 2.0]"), "{}", last_error());
    assert!(lay.lay(engine, &screen, [0, 0, 4, 4], &one([0.0, 0.0, 2.0, 2.0], [1.0, 0.0, 1.0, 2.0])).is_none());
    assert!(last_error().contains("laid onto [1.0, 0.0, 1.0, 2.0]"), "{}", last_error());
    let whole = one([0.0, 0.0, 2.0, 2.0], [0.0, 0.0, 2.0, 2.0]);
    assert!(lay.lay(engine, &screen, [0, 0, 4, 4], &whole).is_some(), "{}", last_error());
}
