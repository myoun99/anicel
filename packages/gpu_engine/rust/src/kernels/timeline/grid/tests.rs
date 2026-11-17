//! The grid tile pass on a real GPU, checked against the ledger and against
//! what the formula gives by hand — never against a CPU copy of it
//! (`kernels/mod.rs` has why). Each hand case writes its sums out.

use super::{ATLAS_SIDE, Drawn, GridTile, MOST_RADIUS_Q9, Put};
use crate::device::{Engine, storage_texture};
use crate::testing::{assert_pinned, first_engine, last_error};

const RGBA: wgpu::TextureFormat = wgpu::TextureFormat::Rgba8Unorm;
const BGRA: wgpu::TextureFormat = wgpu::TextureFormat::Bgra8Unorm;

const FILL_RECT: i32 = 1;
const HLINE: i32 = 2;
const VLINE: i32 = 3;
const GLYPH: i32 = 4;
const RRECT_FILL: i32 = 5;
const RRECT_RING: i32 = 6;
const GRIP: i32 = 7;

/// The corners a grip's mask names, and the pixel each puts the right angle
/// in on an 8-pixel box from the tile's corner: top left, top right, bottom
/// left, bottom right.
const GRIP_CORNERS: [(i32, (u32, u32)); 4] = [(1, (0, 0)), (2, (7, 0)), (4, (0, 7)), (8, (7, 7))];

const WHITE: i32 = -1; // 0xffffffff: opaque white.

/// An RGBA word, as the grids pack one.
fn rgba(r: u32, g: u32, b: u32, a: u32) -> i32 {
    (r | g << 8 | b << 16 | a << 24) as i32
}

/// Pixels to the stream's q8.
fn q8(pixels: f64) -> i32 {
    (pixels * 256.0).round() as i32
}

/// Letters of `coverage`, `width` × `height`, rows top to bottom, at the
/// atlas's corner.
fn atlas(width: u32, height: u32, coverage: &[u8]) -> Put<'_> {
    Put {
        at: [0, 0, width, height],
        bytes: coverage,
    }
}

/// A `width` x `height` tile of `ops` over `background`, as `format`
/// stores it, by a pass whose atlas holds `letters` — None where the pass
/// refuses the stream.
fn tile(
    engine: &Engine,
    (width, height): (u32, u32),
    format: wgpu::TextureFormat,
    background: u32,
    ops: &[i32],
    letters: &[Put],
) -> Option<Vec<u8>> {
    let texture = storage_texture(engine.device(), width, height, format);
    let mut grid = GridTile::new(engine);
    grid.put_letters(engine, letters)?;
    grid.run(engine, &texture, background, ops)?;
    engine.read_texture(&texture)
}

/// An RGBA tile with no atlas over a clear background.
fn clear_tile(engine: &Engine, size: (u32, u32), ops: &[i32]) -> Vec<u8> {
    tile(engine, size, RGBA, 0, ops, &[]).expect("the pass draws the stream")
}

/// The pixel at (x, y) of a tile `width` across.
fn at(bytes: &[u8], width: u32, x: u32, y: u32) -> [u8; 4] {
    let i = ((y * width + x) * 4) as usize;
    [bytes[i], bytes[i + 1], bytes[i + 2], bytes[i + 3]]
}

/// White as it lands over clear at a coverage, stored straight: white at
/// `alpha`. A q9 coverage c gives white the 16-bit alpha (c·65535 + 256)
/// >> 9, stored as its byte (alpha + 128) / 257.
fn white(alpha: u8) -> [u8; 4] {
    [255, 255, 255, alpha]
}

#[test]
fn an_empty_stream_is_the_background_word() {
    let engine = first_engine();
    let bytes = tile(engine, (5, 3), RGBA, 0x8040_2010, &[], &[]).unwrap();
    assert!(bytes.chunks_exact(4).all(|pixel| pixel == [0x10, 0x20, 0x40, 0x80]));
}

#[test]
fn an_opaque_fill_replaces_its_box_and_stops_at_the_tile() {
    let engine = first_engine();
    let red = rgba(255, 0, 0, 255);
    let bytes = clear_tile(engine, (6, 4), &[FILL_RECT, -1, 1, 3, 2, red]);
    for (x, y) in [(0, 1), (1, 1), (0, 2), (1, 2)] {
        assert_eq!(at(&bytes, 6, x, y), [255, 0, 0, 255], "({x}, {y})");
    }
    for (x, y) in [(2, 1), (0, 0), (0, 3), (5, 2)] {
        assert_eq!(at(&bytes, 6, x, y), [0; 4], "({x}, {y})");
    }
}

// (200, 100, 50) at 128 over clear keeps its colour at 128·257 = 32896.
// Again over itself: the alpha out is 32896 + round(32896·32639 / 65535)
// = 32896 + 16383 = 49279, a byte of (49279 + 128) / 257 = 192, and the
// colour is the one colour both weights carry.
#[test]
fn a_translucent_fill_lays_over_the_one_before() {
    let engine = first_engine();
    let fill = [FILL_RECT, 0, 0, 1, 1, rgba(200, 100, 50, 128)];
    assert_eq!(clear_tile(engine, (1, 1), &fill), [200, 100, 50, 128]);
    assert_eq!(
        clear_tile(engine, (1, 1), &[fill, fill].concat()),
        [200, 100, 50, 192],
    );
}

#[test]
fn a_vertical_line_runs_its_length_down_and_a_horizontal_one_across() {
    let engine = first_engine();
    let vertical = clear_tile(engine, (5, 4), &[VLINE, 2, 0, 3, 1, WHITE]);
    for y in 0..3 {
        assert_eq!(at(&vertical, 5, 2, y), [255; 4], "row {y}");
    }
    assert_eq!(at(&vertical, 5, 2, 3), [0; 4]);
    assert_eq!(at(&vertical, 5, 1, 0), [0; 4]);
    let horizontal = clear_tile(engine, (5, 4), &[HLINE, 0, 1, 3, 2, WHITE]);
    for (x, y) in [(0, 1), (2, 1), (0, 2), (2, 2)] {
        assert_eq!(at(&horizontal, 5, x, y), [255; 4], "({x}, {y})");
    }
    assert_eq!(at(&horizontal, 5, 3, 1), [0; 4]);
    assert_eq!(at(&horizontal, 5, 0, 3), [0; 4]);
}

#[test]
fn letters_past_the_atlas_or_whose_bytes_are_not_their_box_are_refused() {
    let engine = first_engine();
    let mut grid = GridTile::new(engine);
    let put = |grid: &mut GridTile, at: [u32; 4], bytes: &[u8]| grid.put_letters(engine, &[Put { at, bytes }]);
    for length in [5, 7] {
        assert!(put(&mut grid, [0, 0, 3, 2], &vec![0; length]).is_none(), "{length}");
        assert!(last_error().contains(&format!("letters 3 × 2 of {length} bytes")), "{}", last_error());
    }
    let side = ATLAS_SIDE;
    for at in [[side - 2, 0, 3, 2], [0, side - 1, 3, 2], [u32::MAX, 0, 3, 2]] {
        assert!(put(&mut grid, at, &[0; 6]).is_none(), "{at:?}");
        assert!(last_error().contains("past the atlas"), "{}", last_error());
    }
    assert_eq!(grid.kept_bytes(), 0, "nothing refused is kept");
    assert!(put(&mut grid, [side - 3, side - 2, 3, 2], &[0; 6]).is_some(), "{}", last_error());
    assert!(put(&mut grid, [0, 0, 0, 3], &[]).is_some(), "letters of no side");
    assert_eq!(grid.kept_bytes(), u64::from(side) * u64::from(side), "the atlas, once");
}

// (10, 20, 30) opaque, its alpha scaled by the coverage: 65535 times
// 128·257 is 32896, a byte of 128; 64 gives 64; 255 lays it whole. Over
// clear the colour stays (10, 20, 30).
#[test]
fn a_letter_scales_its_colour_by_the_atlas_and_stops_at_its_edges() {
    let engine = first_engine();
    let coverage = [0, 128, 255, 255, 64, 0];
    // The same letters at the atlas's left and at its right edge.
    let right = (ATLAS_SIDE - 3) as i32;
    let letters = [
        atlas(3, 2, &coverage),
        Put {
            at: [ATLAS_SIDE - 3, 0, 3, 2],
            bytes: &coverage,
        },
    ];
    let ink = rgba(10, 20, 30, 255);
    let ops = [
        [GLYPH, 1, 1, 0, 0, 3, 2, ink],
        // Its window runs a column past the atlas.
        [GLYPH, 0, 3, right + 1, 0, 3, 1, ink],
        // And this one starts a column before it.
        [GLYPH, 3, 0, -1, 1, 2, 1, ink],
    ]
    .concat();
    let bytes = tile(engine, (5, 4), RGBA, 0, &ops, &letters).unwrap();
    assert_eq!(at(&bytes, 5, 1, 1), [0; 4]);
    assert_eq!(at(&bytes, 5, 2, 1), [10, 20, 30, 128]);
    assert_eq!(at(&bytes, 5, 3, 1), [10, 20, 30, 255]);
    assert_eq!(at(&bytes, 5, 1, 2), [10, 20, 30, 255]);
    assert_eq!(at(&bytes, 5, 2, 2), [10, 20, 30, 64]);
    assert_eq!(at(&bytes, 5, 3, 2), [0; 4]);
    assert_eq!(at(&bytes, 5, 0, 3), [10, 20, 30, 128]);
    assert_eq!(at(&bytes, 5, 1, 3), [10, 20, 30, 255]);
    assert_eq!(at(&bytes, 5, 2, 3), [0; 4], "past the atlas");
    assert_eq!(at(&bytes, 5, 3, 0), [0; 4], "before the atlas");
    assert_eq!(at(&bytes, 5, 4, 0), [10, 20, 30, 255]);
}

// A box from x = 1.25 to 3.25, four tall. On row 2, a pixel's coverage is
// half a pixel less its centre's distance in: x 0 sits 0.75 out → none;
// x 1, 0.25 in → 0.75, 384 in q9 → 49151, a byte of 191; x 2, 0.75 in →
// all; x 3, 0.25 out → 0.25 → 16384, a byte of 64; x 4, 1.25 out → none.
#[test]
fn a_rounded_box_covers_a_pixel_by_half_a_pixel_less_its_distance() {
    let engine = first_engine();
    let ops = [RRECT_FILL, q8(1.25), 0, q8(2.0), q8(4.0), 0, 0, WHITE];
    let bytes = clear_tile(engine, (6, 4), &ops);
    let row: Vec<[u8; 4]> = (0..5).map(|x| at(&bytes, 6, x, 2)).collect();
    assert_eq!(row, [[0; 4], white(191), [255; 4], white(64), [0; 4]]);
}

// An 8-pixel box rounding one corner by 2. Pixel (0, 0)'s centre is 1.5
// in each way from the top left corner's centre at (2, 2): in q9 768 and
// 768, isqrt_round(2·768²) = isqrt_round(1179648) = 1086 (√ = 1086.1),
// less the radius 1024 is 62 out, so 256 − 62 = 194 covered → 24832, a
// byte of 97 — and so for each corner's pixel. The square corners
// cover their pixels whole.
#[test]
fn a_corner_rounds_only_where_its_mask_says() {
    let engine = first_engine();
    // Top left, top right, bottom left, bottom right.
    let corners = [(0, 0), (7, 0), (0, 7), (7, 7)];
    for (bit, mask) in [1, 2, 4, 8].into_iter().enumerate() {
        let ops = [RRECT_FILL, 0, 0, q8(8.0), q8(8.0), q8(2.0), mask, WHITE];
        let bytes = clear_tile(engine, (8, 8), &ops);
        for (corner, (x, y)) in corners.into_iter().enumerate() {
            let pixel = if corner == bit { white(97) } else { [255; 4] };
            assert_eq!(at(&bytes, 8, x, y), pixel, "mask {mask}, ({x}, {y})");
        }
    }
}

// A 16-pixel box rounding every corner by 4. Pixel (0, 3) reaches 3.5 and
// 0.5 past the corner's square, 1792 and 256 in q9 — farther than two
// pixels, nearer than the radius and a half — so it is under the arc:
// isqrt_round(1792² + 256²) = isqrt_round(3276800) = 1810 (√ = 1810.19),
// 238 inside the radius 2048, so 256 + 238 = 494 → 63231, a byte of
// 246.
#[test]
fn a_corner_wider_than_two_pixels_covers_what_lies_under_its_arc() {
    let engine = first_engine();
    let ops = [RRECT_FILL, 0, 0, q8(16.0), q8(16.0), q8(4.0), 15, WHITE];
    let bytes = clear_tile(engine, (16, 16), &ops);
    assert_eq!(at(&bytes, 16, 0, 3), white(246));
    assert_eq!(at(&bytes, 16, 3, 0), white(246));
}

// An 8 x 2 box asking for corners of 4 gets 1, half its height: pixel
// (0, 0) reaches 0.5 past the corner's square each way, 256 in q9,
// isqrt_round(2·256²) = isqrt_round(131072) = 362, 150 inside the radius
// 512, so 406 → 51967, a byte of 202. Pixel (1, 0) is past the arc.
#[test]
fn a_corner_is_held_to_half_the_shorter_side() {
    let engine = first_engine();
    let ops = [RRECT_FILL, 0, 0, q8(8.0), q8(2.0), q8(4.0), 15, WHITE];
    let bytes = clear_tile(engine, (8, 2), &ops);
    assert_eq!(at(&bytes, 8, 0, 0), white(202));
    assert_eq!(at(&bytes, 8, 0, 1), white(202));
    assert_eq!(at(&bytes, 8, 7, 1), white(202));
    assert_eq!(at(&bytes, 8, 1, 0), [255; 4]);
}

// Two 16-pixel boxes rounded by 4, 139.5 pixels left of the tile and
// above it, so pixel (0, 8) — and (8, 0) — lies 2¹⁶ in q9 past a corner's
// square: its square is 2³², which a u32 holds as 0. The field's cut
// leaves it uncovered before it is squared.
#[test]
fn a_box_far_from_a_pixel_leaves_it_alone() {
    let engine = first_engine();
    let far = -35712;
    let ops = [
        [RRECT_FILL, far, 0, q8(16.0), q8(16.0), q8(4.0), 15, WHITE],
        [RRECT_FILL, 0, far, q8(16.0), q8(16.0), q8(4.0), 15, WHITE],
    ]
    .concat();
    let bytes = clear_tile(engine, (16, 16), &ops);
    assert!(bytes.iter().all(|&byte| byte == 0));
}

#[test]
fn a_box_with_no_width_or_height_draws_nothing() {
    let engine = first_engine();
    // Each would put its edge on a pixel's centre.
    let ops = [
        [RRECT_FILL, q8(0.5), 0, 0, q8(4.0), 0, 0, WHITE],
        [RRECT_FILL, 0, q8(0.5), q8(4.0), 0, 0, 0, WHITE],
    ]
    .concat();
    let rings = [
        [RRECT_RING, q8(0.5), 0, 0, q8(4.0), 0, 0, q8(1.0), 0, WHITE],
        [RRECT_RING, 0, q8(0.5), q8(4.0), 0, 0, 0, q8(1.0), 0, WHITE],
    ]
    .concat();
    for ops in [&ops[..], &rings] {
        assert!(clear_tile(engine, (4, 4), ops).iter().all(|&byte| byte == 0));
    }
}

// An 8-pixel box rounded by 2, a 1-pixel line: its hole runs from 1 to 7,
// rounded by 1. Pixel (0, 4) is half a pixel inside the box and half
// outside the hole: all of it. Pixel (1, 4) is inside both: none. Pixel
// (1, 1) is under both arcs: the box's covers it, the hole's 0.5 past its
// square each way, isqrt_round(2·256²) = 362, 150 inside the radius 512,
// so 406 of it — leaving 106 → 13568, a byte of 53. An open side's
// hole runs 3 pixels past it, so that side's stroke is gone.
#[test]
fn a_ring_leaves_its_hole_and_opens_the_sides_it_is_told() {
    let engine = first_engine();
    let ring = |open: i32, line: f64| {
        [RRECT_RING, 0, 0, q8(8.0), q8(8.0), q8(2.0), 15, q8(line), open, WHITE]
    };
    let closed = clear_tile(engine, (8, 8), &ring(0, 1.0));
    assert_eq!(at(&closed, 8, 0, 4), [255; 4]);
    assert_eq!(at(&closed, 8, 1, 4), [0; 4]);
    assert_eq!(at(&closed, 8, 4, 4), [0; 4]);
    assert_eq!(at(&closed, 8, 1, 1), white(53));
    // Left, top, right, bottom: the side it opens, and the one across.
    let sides = [(0, 4), (4, 0), (7, 4), (4, 7)];
    for (bit, open) in [1, 2, 4, 8].into_iter().enumerate() {
        let (gone, kept) = (sides[bit], sides[(bit + 2) % 4]);
        let bytes = clear_tile(engine, (8, 8), &ring(open, 1.0));
        assert_eq!(at(&bytes, 8, gone.0, gone.1), [0; 4], "open {open}");
        assert_eq!(at(&bytes, 8, kept.0, kept.1), [255; 4], "open {open}");
        assert_eq!(at(&closed, 8, gone.0, gone.1), [255; 4], "closed");
    }
    // No line, or one below none, leaves nothing of the box — whichever
    // sides it opens.
    for (open, line) in [(0, 0.0), (0, -1.0), (15, 0.0), (5, -1.0)] {
        let bytes = clear_tile(engine, (8, 8), &ring(open, line));
        assert!(bytes.iter().all(|&byte| byte == 0), "open {open}, line {line}");
    }
}

// A 16-pixel box rounded by 6, open on the left with a 1-pixel line: the
// hole's corner, 5, sits 1 + 2 pixels out past the left side, so its arc
// clears the box's — nothing is left of the corner below the top stroke.
// Pixel (2, 1) is under the box's arc, 1792 and 2304 past its square:
// isqrt_round(8519680) = 2919, 153 inside 3072, so 409 of it; the hole's
// straight top covers all of it.
#[test]
fn an_open_side_leaves_no_sliver_of_its_corner() {
    let engine = first_engine();
    let ops = [RRECT_RING, 0, 0, q8(16.0), q8(16.0), q8(6.0), 15, q8(1.0), 1, WHITE];
    let bytes = clear_tile(engine, (16, 16), &ops);
    for y in 1..4 {
        for x in 0..4 {
            assert_eq!(at(&bytes, 16, x, y), [0; 4], "({x}, {y})");
        }
    }
}

// A square ring's hole keeps square corners, however thin its line. With
// a line of 205/256 its hole starts at 410 in q9, so pixel (0, 0) lies
// 154 past the hole's corner each way: isqrt_round(2·154²) = 218, the
// hole covers 38 of it, the ring 474 → 60671, a byte of 236.
#[test]
fn a_square_ring_has_a_square_hole() {
    let engine = first_engine();
    let ops = [RRECT_RING, 0, 0, q8(8.0), q8(8.0), 0, 0, 205, 0, WHITE];
    assert_eq!(at(&clear_tile(engine, (8, 8), &ops), 8, 0, 0), white(236));
}

// A 3-pixel box with a 1.5-pixel line has a hole of nothing, centred on
// pixel (1, 1) — no hole, so the ring is the box.
#[test]
fn a_ring_whose_line_fills_its_box_is_the_box() {
    let engine = first_engine();
    let ops = [RRECT_RING, 0, 0, q8(3.0), q8(3.0), 0, 0, q8(1.5), 0, WHITE];
    assert!(clear_tile(engine, (3, 3), &ops).iter().all(|&byte| byte == 255));
}

// The largest corner, 64 pixels (r = 2¹⁵ in q9), on a 128-pixel box from
// (1, 1): the corner's centre is at (65, 65). Pixel (0, 0) reaches the
// radius and half a pixel past it each way — 33024 — the farthest the
// field takes: 2·33024² = 2181169152 is still a u32, isqrt_round gives
// 46703 (√ = 46702.99), 13935 out: nothing. Pixel (19, 19) is 23296 each
// way: isqrt_round(2·23296²) = isqrt_round(1085407232) = 32946 (√ =
// 32945.52), 178 out, so 256 − 178 = 78 → 9984, a byte of 39.
#[test]
fn the_largest_corner_is_taken_whole_and_a_larger_one_is_refused() {
    let engine = first_engine();
    let largest = MOST_RADIUS_Q9 / 2;
    assert_eq!(largest, q8(64.0), "the premise: 64 pixels");
    let corner = |radius: i32, side: f64| {
        [RRECT_FILL, q8(1.0), q8(1.0), q8(side), q8(side), radius, 1, WHITE]
    };
    let bytes = clear_tile(engine, (24, 24), &corner(largest, 128.0));
    assert_eq!(at(&bytes, 24, 0, 0), [0; 4]);
    assert_eq!(at(&bytes, 24, 19, 19), white(39));
    assert_eq!(at(&bytes, 24, 23, 23), [255; 4]);

    let past = tile(engine, (24, 24), RGBA, 0, &corner(largest + 1, 129.0), &[]);
    assert!(past.is_none(), "a corner past 64 pixels is refused");
    // One the box holds to less is drawn as the box holds it.
    let held = tile(engine, (24, 24), RGBA, 0, &corner(q8(100.0), 16.0), &[]);
    assert!(held.is_some());
}

// An 8-pixel box, its right angle in the top right and no paper corner:
// legs 4096 in q9 each way, its far side 4096·√2 long, isqrt_round(2·4096²)
// = isqrt_round(33554432) = 5793 (√ = 5792.6). Pixel (0, 0)'s centre is 7.5
// in from the right and 0.5 down — on the far side, u/w + v/h = 1: half a
// pixel, 256 → 32768, a byte of 128. So is (3, 3): 4.5 in, 3.5 down. Pixel
// (4, 3), 3.5 in each way, is 4096·(1792 + 1792 − 4096) / 5793 = −362 past
// it: 256 + 362, all of it. Pixel (0, 7) is as far the other way: none.
#[test]
fn a_grip_is_the_right_triangle_in_its_corner() {
    let engine = first_engine();
    let ops = [GRIP, 0, 0, q8(8.0), q8(8.0), 0, 0, 2, WHITE];
    let bytes = clear_tile(engine, (8, 8), &ops);
    assert_eq!(at(&bytes, 8, 7, 0), [255; 4], "the right angle");
    assert_eq!(at(&bytes, 8, 0, 0), white(128), "the far side's end");
    assert_eq!(at(&bytes, 8, 3, 3), white(128), "on the far side");
    assert_eq!(at(&bytes, 8, 4, 3), [255; 4], "inside it");
    assert_eq!(at(&bytes, 8, 0, 7), [0; 4], "past it");
}

// The same box as each mask names its corner: the right angle whole, the
// pixel across the box from it bare.
#[test]
fn a_grip_stands_in_the_one_corner_its_mask_names() {
    let engine = first_engine();
    for (mask, (x, y)) in GRIP_CORNERS {
        let ops = [GRIP, 0, 0, q8(8.0), q8(8.0), 0, 0, mask, WHITE];
        let bytes = clear_tile(engine, (8, 8), &ops);
        assert_eq!(at(&bytes, 8, x, y), [255; 4], "mask {mask}");
        assert_eq!(at(&bytes, 8, 7 - x, 7 - y), [0; 4], "mask {mask}");
    }
}

// The paper's corner of 4 pixels cuts the right angle: its circle stands
// 2048 in q9 in from both legs. Pixel (7, 0)'s centre is 256 in each way,
// 1792 past the circle's centre each way: isqrt_round(2·1792²) =
// isqrt_round(6422528) = 2534 (√ = 2534.3), 486 outside the radius 2048 —
// none. Pixel (6, 1), 1280 past each way: isqrt_round(3276800) = 1810
// (√ = 1810.19), 238 inside, 494 → 63231, a byte of 246; so is (4, 0),
// 256 and 1792 past. Pixel (3, 0) is 2304 in, past the circle's centre:
// the paper is square there, and it is whole.
#[test]
fn a_grip_follows_its_papers_corner() {
    let engine = first_engine();
    let ops = [GRIP, 0, 0, q8(8.0), q8(8.0), q8(4.0), 0, 2, WHITE];
    let bytes = clear_tile(engine, (8, 8), &ops);
    assert_eq!(at(&bytes, 8, 7, 0), [0; 4], "the corner the paper cuts");
    assert_eq!(at(&bytes, 8, 6, 1), white(246), "under its arc");
    assert_eq!(at(&bytes, 8, 4, 0), white(246), "under its arc, on the leg");
    assert_eq!(at(&bytes, 8, 3, 0), [255; 4], "past the round");
}

// A bleed of a pixel, 512 in q9, widens the circle to 2560: pixel (6, 1),
// 1810 from its centre, is whole; pixel (7, 0), 2534, is 26 inside — 282
// → 36095, a byte of 140. The legs do not move: on a 12-pixel tile with the
// box from x = 2, pixel (10, 4)'s centre is half a pixel past the right
// leg, 256 − 256 = none, bleed or no bleed.
#[test]
fn a_grips_bleed_widens_its_round_end_alone() {
    let engine = first_engine();
    let ops = [GRIP, 0, 0, q8(8.0), q8(8.0), q8(4.0), q8(1.0), 2, WHITE];
    let bytes = clear_tile(engine, (8, 8), &ops);
    assert_eq!(at(&bytes, 8, 6, 1), [255; 4]);
    assert_eq!(at(&bytes, 8, 7, 0), white(140));
    for bleed in [0.0, 1.0] {
        let ops = [GRIP, q8(2.0), 0, q8(8.0), q8(8.0), q8(4.0), q8(bleed), 2, WHITE];
        let bytes = clear_tile(engine, (12, 8), &ops);
        assert_eq!(at(&bytes, 12, 9, 4), [255; 4], "inside the leg, bleed {bleed}");
        assert_eq!(at(&bytes, 12, 10, 4), [0; 4], "past the leg, bleed {bleed}");
    }
}

// A side of 8192 pixels — 2²² in q9, where half a pixel times the far
// side's length leaves an i32 — a corner below square or past 64 pixels, a
// bleed below none, and a mask naming no one corner are refused; a step
// inside each is drawn. A place past the reach is refused as every op's is.
// A box 100 by 120 pixels, 51200 by 61440 in q9, its right angle in the top
// right. Pixel (0, 119)'s centre is 50944 in and 61184 down: h·u alone is
// 61440 · 50944 = 3130000000-odd, past an i32, and a wrapped sum would read
// the corner across from the right angle as inside. Its length, of sides
// shifted down one to 25600 and 30720: isqrt_round(1599078400) = 39988,
// back up, 79976 (√ = 79976.9); half a pixel of it, 20473856. On row 59
// (v = 30464): pixel (49, 59), u = 25856, sums 61440 · 25856 + 51200 ·
// (30464 − 61440) = 2621440, inside half a pixel — 2621440 / 79976 = 32
// past the far side, 224 covered → 28672, a byte of 112. Pixel (50, 59),
// u = 25344, is −28835840: more than half a pixel in, all of it. Pixel
// (48, 59), u = 26368, is 34078720: more than half a pixel out, none.
#[test]
fn a_long_grip_takes_its_far_side_whole() {
    let engine = first_engine();
    let ops = [GRIP, 0, 0, q8(100.0), q8(120.0), 0, 0, 2, WHITE];
    let bytes = clear_tile(engine, (100, 120), &ops);
    assert_eq!(at(&bytes, 100, 99, 0), [255; 4], "the right angle");
    assert_eq!(at(&bytes, 100, 0, 119), [0; 4], "across from it");
    assert_eq!(at(&bytes, 100, 49, 59), white(112), "on the far side");
    assert_eq!(at(&bytes, 100, 50, 59), [255; 4], "inside it");
    assert_eq!(at(&bytes, 100, 48, 59), [0; 4], "past it");
}

#[test]
fn a_grip_the_pass_cannot_draw_is_refused() {
    let engine = first_engine();
    let drawn = |ops: &[i32]| tile(engine, (4, 4), RGBA, 0, ops, &[]).is_some();
    let grip = |x: i32, w: i32, h: i32, corner: i32, bleed: i32, mask: i32| {
        [GRIP, x, 0, w, h, corner, bleed, mask, WHITE]
    };
    let side = q8(8192.0);
    assert!(!drawn(&grip(0, side, 256, 0, 0, 2)), "8192 pixels across");
    assert!(!drawn(&grip(0, 256, side, 0, 0, 2)), "8192 pixels down");
    assert!(drawn(&grip(0, side - 1, side - 1, 0, 0, 2)), "just under");
    let corner = MOST_RADIUS_Q9 / 2;
    assert!(!drawn(&grip(0, 256, 256, corner + 1, 0, 2)), "a corner past 64");
    assert!(drawn(&grip(0, 256, 256, corner, 0, 2)), "a corner of 64");
    assert!(!drawn(&grip(0, 256, 256, -1, 0, 2)), "a corner below square");
    assert!(!drawn(&grip(0, 256, 256, 0, -1, 2)), "a bleed below none");
    for mask in [0, 3, 6, 15, 16] {
        assert!(!drawn(&grip(0, 256, 256, 0, 0, mask)), "mask {mask}");
    }
    let reach = 1 << 28;
    assert!(!drawn(&grip(reach, 256, 256, 0, 0, 2)), "a place past the reach");
    assert!(drawn(&grip(reach - 1, 256, 256, 0, 0, 2)), "one inside it");
}

#[test]
fn a_stream_the_pass_cannot_draw_is_refused() {
    let engine = first_engine();
    let refused = |ops: &[i32]| tile(engine, (4, 4), RGBA, 0, ops, &[]).is_none();
    assert!(refused(&[FILL_RECT, 0, 0]), "cut short");
    assert!(refused(&[9, 0, 0, 0, 0, 0]), "no such op");
    assert!(refused(&[GLYPH, 0, 0, 0, 0, 1, 1, WHITE]), "a letter, no atlas");
    assert!(refused(&[RRECT_FILL, 0, 0, 256, 256, -1, 15, WHITE]), "below square");
}

// Each op's places and lengths, one at a time at 2²⁸ either way — the bound
// inside which nothing the field sums can wrap (mod.rs) —
// refused there, drawn a step inside it.
#[test]
fn a_place_or_length_past_the_reach_is_refused() {
    let engine = first_engine();
    let reach = 1 << 28;
    let letters = [atlas(1, 1, &[255])];
    let drawn = |ops: &[i32]| tile(engine, (4, 4), RGBA, 0, ops, &letters).is_some();
    let ops: [&[i32]; 6] = [
        &[FILL_RECT, 0, 0, 1, 1, WHITE],
        &[HLINE, 0, 0, 1, 1, WHITE],
        &[VLINE, 0, 0, 1, 1, WHITE],
        &[GLYPH, 0, 0, 0, 0, 1, 1, WHITE],
        &[RRECT_FILL, 0, 0, 256, 256, 0, 15, WHITE],
        &[RRECT_RING, 0, 0, 256, 256, 0, 15, 64, 15, WHITE],
    ];
    let reaches: [&[usize]; 6] = [
        &[1, 2, 3, 4],
        &[1, 2, 3, 4],
        &[1, 2, 3, 4],
        &[1, 2, 3, 4, 5, 6],
        &[1, 2, 3, 4, 5],
        &[1, 2, 3, 4, 5, 7],
    ];
    for (op, words) in ops.iter().zip(reaches) {
        assert!(drawn(op), "{op:?}");
        for &word in words {
            for (value, takes) in [
                (reach, false),
                (-reach, false),
                (reach - 1, true),
                (1 - reach, true),
            ] {
                let mut moved = op.to_vec();
                moved[word] = value;
                // A corner that far would be refused as past 64 pixels or
                // below square first; it is held by the box here instead.
                let fair = word != 5 || value > 0;
                if fair {
                    assert_eq!(drawn(&moved), takes, "word {word} = {value}");
                }
            }
        }
    }
}

/// Every op at once on a 96 x 28 tile — lines, fills, rounded runs on
/// fractional pixels with their corners picked, a ring with a side open,
/// a mark's disc, letters, and translucent ones over the others.
fn mixed(engine: &Engine, format: wgpu::TextureFormat) -> Vec<u8> {
    let coverage: Vec<u8> = (0..64u32)
        .map(|i| (((i % 8) * 7 + (i / 8) * 13) * 3 % 256) as u8)
        .collect();
    let letters = [atlas(8, 8, &coverage)];
    let (gold, teal) = (rgba(200, 180, 120, 255), rgba(120, 200, 180, 200));
    let (violet, ring) = (rgba(180, 120, 200, 255), rgba(250, 250, 250, 230));
    let ops = [
        &[FILL_RECT, 0, 0, 96, 28, rgba(30, 30, 34, 255)][..],
        &[VLINE, 12, 0, 28, 1, rgba(60, 60, 66, 255)],
        &[VLINE, 24, 0, 28, 2, rgba(60, 60, 66, 160)],
        &[HLINE, 0, 27, 96, 1, rgba(90, 90, 99, 255)],
        &[RRECT_FILL, q8(2.3), q8(3.1), q8(30.7), q8(21.4), q8(6.0), 5, gold],
        &[RRECT_FILL, q8(40.6), q8(3.0), q8(20.2), q8(21.5), q8(6.0), 15, teal],
        &[RRECT_FILL, q8(70.25), q8(2.75), q8(30.0), q8(22.0), q8(6.0), 10, violet],
        &[RRECT_RING, q8(10.5), q8(5.5), q8(40.0), q8(16.0), q8(6.0), 15, q8(1.5), 1, ring],
        &[RRECT_FILL, q8(80.2), q8(10.4), q8(5.6), q8(5.6), q8(2.8), 15, rgba(20, 20, 20, 255)],
        &[GLYPH, 4, 8, 0, 0, 8, 8, rgba(240, 240, 240, 255)],
        &[GLYPH, 9, 10, 2, 1, 6, 7, rgba(255, 64, 32, 128)],
    ]
    .concat();
    tile(engine, (96, 28), format, 0, &ops, &letters).unwrap()
}

#[test]
fn every_device_writes_the_pinned_bytes() {
    let engine = first_engine();
    assert_pinned("timeline/grid-96x28-mixed-rgba", &mixed(engine, RGBA));
}

// The format moves where each channel sits, not what is stored.
#[test]
fn the_two_orders_differ_only_by_red_and_blue() {
    let engine = first_engine();
    let storable = engine
        .device()
        .features()
        .contains(wgpu::Features::BGRA8UNORM_STORAGE);
    assert!(storable, "this adapter cannot store to bgra8unorm");
    let swapped: Vec<u8> = mixed(engine, BGRA)
        .chunks_exact(4)
        .flat_map(|texel| [texel[2], texel[1], texel[0], texel[3]])
        .collect();
    assert_eq!(swapped, mixed(engine, RGBA));
}

// Tiles of a batch each drawn as alone, whatever their order or the batch
// beside them: one pass, a dispatch a tile, each its own part of the plane
// — the first and the last of a part, where a neighbour's would show.
#[test]
fn a_batch_draws_each_tile_as_it_is_drawn_alone() {
    let engine = first_engine();
    let coverage: Vec<u8> = (0..64u32).map(|i| (i * 37 % 256) as u8).collect();
    let letters = [atlas(8, 8, &coverage)];
    let streams: [Vec<i32>; 4] = [
        vec![FILL_RECT, 0, 0, 5, 3, rgba(200, 10, 10, 255), GLYPH, 1, 0, 0, 0, 8, 8, WHITE],
        vec![],
        vec![VLINE, 2, 0, 7, 1, rgba(10, 200, 10, 128), HLINE, 0, 5, 9, 2, rgba(10, 10, 200, 255)],
        vec![RRECT_FILL, q8(0.5), q8(0.5), q8(6.0), q8(4.0), q8(2.0), 15, rgba(90, 90, 90, 255)],
    ];
    let sizes = [(6, 4), (3, 3), (9, 7), (7, 5)];
    let alone: Vec<Vec<u8>> = streams
        .iter()
        .zip(sizes)
        .map(|(ops, size)| tile(engine, size, RGBA, 0, ops, &letters).unwrap())
        .collect();
    let mut grid = GridTile::new(engine);
    grid.put_letters(engine, &letters).unwrap();
    let textures: Vec<wgpu::Texture> = sizes
        .iter()
        .map(|&(width, height)| storage_texture(engine.device(), width, height, RGBA))
        .collect();
    for order in [[0, 1, 2, 3], [3, 2, 1, 0]] {
        let drawn: Vec<Drawn> = order
            .iter()
            .map(|&i| Drawn {
                tile: &textures[i],
                background: 0,
                ops: &streams[i],
            })
            .collect();
        let mut encoder = engine
            .device()
            .create_command_encoder(&wgpu::CommandEncoderDescriptor::default());
        grid.encode(engine, &mut encoder, &drawn).unwrap();
        engine.queue.submit([encoder.finish()]);
        for (i, texture) in textures.iter().enumerate() {
            assert_eq!(engine.read_texture(texture).unwrap(), alone[i], "tile {i} in {order:?}");
        }
    }
}

// A stream the pass refuses refuses its batch: nothing of it is encoded.
#[test]
fn a_batch_with_a_stream_refused_draws_none_of_it() {
    let engine = first_engine();
    let mut grid = GridTile::new(engine);
    let first = storage_texture(engine.device(), 2, 2, RGBA);
    let second = storage_texture(engine.device(), 2, 2, RGBA);
    let fill = [FILL_RECT, 0, 0, 2, 2, WHITE];
    let drawn = [
        Drawn { tile: &first, background: 0, ops: &fill },
        Drawn { tile: &second, background: 0, ops: &[9, 0, 0, 0, 0, 0] },
    ];
    let mut encoder = engine
        .device()
        .create_command_encoder(&wgpu::CommandEncoderDescriptor::default());
    assert!(grid.encode(engine, &mut encoder, &drawn).is_none());
    assert!(last_error().starts_with("tile 1: "), "{}", last_error());
    engine.queue.submit([encoder.finish()]);
    assert!(engine.read_texture(&first).unwrap().iter().all(|&byte| byte == 0));
}

// What a batch keeps — its plane — goes when it is let go of, and the
// atlas with it: a letter drawn after reads none till it is put again.
#[test]
fn what_a_batch_keeps_is_let_go_of_whole() {
    let engine = first_engine();
    let mut grid = GridTile::new(engine);
    let letters = [atlas(1, 1, &[255])];
    grid.put_letters(engine, &letters).unwrap();
    let texture = storage_texture(engine.device(), 2, 2, RGBA);
    let letter = [GLYPH, 0, 0, 0, 0, 1, 1, WHITE];
    grid.run(engine, &texture, 0, &letter).unwrap();
    assert!(grid.kept_bytes() > u64::from(ATLAS_SIDE) * u64::from(ATLAS_SIDE), "the atlas and the plane");
    grid.let_go_kept();
    assert_eq!(grid.kept_bytes(), 0);
    assert!(grid.run(engine, &texture, 0, &letter).is_none(), "a letter, no atlas");
}
