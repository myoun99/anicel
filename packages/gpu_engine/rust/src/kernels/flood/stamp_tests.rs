//! A fill's colour stamp on a real GPU, checked against what the app's
//! stamp holds by hand — never against a CPU copy of it (`kernels/mod.rs`
//! has why). How the executor lays it is composite's tests'.

use super::super::tests::{Rig, rig};
use super::{Gradient, Paint, Shape, Stamped};
use crate::kernels::composite::{TILE, TileAt};
use crate::kernels::mask::tests::masked;
use crate::kernels::mask::{Mask, MaskBox};
use crate::testing::read_buffer;

const ORANGE: [u8; 3] = [200, 100, 50];
/// ORANGE as a stamp's word at alpha 0: R in the low byte.
const ORANGE_WORD: u32 = 0x0032_64c8;
const BLACK: [u8; 4] = [0, 0, 0, 255];
const RED: [u8; 4] = [255, 0, 0, 255];

/// Each of `stamped`'s pages read back, as words.
fn pages(stamped: &Stamped) -> Vec<Vec<u32>> {
    let engine = rig().engine;
    stamped
        .pages
        .iter()
        .map(|page| {
            read_buffer(engine, page)
                .chunks_exact(4)
                .map(|word| u32::from_le_bytes(word.try_into().unwrap()))
                .collect()
        })
        .collect()
}

fn stamp(mask: &Mask, first_page: u16, per_page: usize) -> Stamped {
    let Rig { engine, flood, .. } = rig();
    let paint = Paint::Colour(ORANGE);
    flood.stamp_by(engine, mask, &paint, first_page, per_page).expect("stamp")
}

/// `mask` stamped under `gradient`, or none where it is refused.
fn graded(mask: &Mask, gradient: &Gradient) -> Option<Stamped> {
    let Rig { engine, flood, .. } = rig();
    flood.stamp(engine, mask, &Paint::Gradient(gradient), 0)
}

/// A gradient of `shape` from `from` to `to`, `start` to `end`.
fn gradient(shape: Shape, from: (f64, f64), to: (f64, f64), ends: [[u8; 4]; 2]) -> Gradient {
    let [start, end] = ends;
    Gradient {
        shape,
        from,
        to,
        start,
        end,
    }
}

/// The word of canvas pixel (`x`, `y`) on its tile `at` of `stamped`, its
/// pages read back as `read`.
fn word(stamped: &Stamped, read: &[Vec<u32>], first_page: u16, (x, y): (i32, i32)) -> u32 {
    let side = TILE as i32;
    let set = &stamped.set;
    let (column, row) = (x.div_euclid(side) - set.x0, y.div_euclid(side) - set.y0);
    let TileAt { page, slot } = set.tiles[(row * set.columns as i32 + column) as usize].unwrap();
    let texel = (y.rem_euclid(side) * side + x.rem_euclid(side)) as usize;
    read[usize::from(page - first_page)][usize::from(slot) * (side * side) as usize + texel]
}

// A pixel the mask covers is the colour under its byte, and one it covers
// none — inside the box or past it — is nothing: [0, 128, 255] over
// [1, 0, 7] at (130, 5), on tile (1, 0) alone, the plane's 255 past the
// box's width read by none.
#[test]
fn a_stamp_is_its_colour_under_the_mask_s_byte() {
    let mask = masked((130, 5), (3, 2), |x, y| match (x - 130, y - 5) {
        (0, 0) | (1, 1) => 0,
        (1, 0) => 128,
        (2, 0) => 255,
        (0, 1) => 1,
        _ => 7,
    });
    let stamped = stamp(&mask.mask(), 3, usize::MAX);
    let set = &stamped.set;
    assert_eq!((set.x0, set.y0, set.columns, set.rows), (1, 0, 1, 1));
    assert_eq!(set.tiles, [Some(TileAt { page: 3, slot: 0 })]);
    let read = pages(&stamped);
    let at = |x, y| word(&stamped, &read, 3, (x, y));
    assert_eq!([at(130, 5), at(131, 6)], [0; 2]);
    assert_eq!(at(131, 5), ORANGE_WORD | 128 << 24);
    assert_eq!(at(132, 5), ORANGE_WORD | 255 << 24);
    assert_eq!(at(130, 6), ORANGE_WORD | 1 << 24);
    assert_eq!(at(132, 6), ORANGE_WORD | 7 << 24);
    let others = read[0].iter().enumerate().filter(|&(texel, &word)| {
        let (x, y) = (128 + (texel % 128) as i32, (texel / 128) as i32);
        word != 0 && !((130..133).contains(&x) && (5..7).contains(&y))
    });
    assert_eq!(others.count(), 0, "a word past the box");
}

// The row is every tile the box meets, row after row on the canvas's grid
// — a box across the canvas's corner meets the four about it —, each a
// pixel the colour whole inside the box and nothing past it.
#[test]
fn a_stamp_s_tiles_are_every_tile_its_box_meets() {
    let (left, top, width, height) = (-3, -8, 6, 10);
    let mask = masked((left, top), (width, height), |_, _| 255);
    let stamped = stamp(&mask.mask(), 0, usize::MAX);
    let set = &stamped.set;
    assert_eq!((set.x0, set.y0, set.columns, set.rows), (-1, -1, 2, 2));
    let slots: Vec<_> = (0..4).map(|slot| Some(TileAt { page: 0, slot })).collect();
    assert_eq!(set.tiles, slots);
    let read = pages(&stamped);
    for y in -128..128 {
        for x in -128..128 {
            let inside = (left..left + width as i32).contains(&x)
                && (top..top + height as i32).contains(&y);
            let want = if inside { ORANGE_WORD | 255 << 24 } else { 0 };
            assert_eq!(word(&stamped, &read, 0, (x, y)), want, "({x}, {y})");
        }
    }
}

// A page holds the tiles it can, and the next takes the rest: four tiles
// two a page are pages 5 and 6, slots 0 and 1 each, the same words.
#[test]
fn a_stamp_past_a_page_goes_on_the_next() {
    let mask = masked((-3, 120), (6, 10), |x, y| (x + 3 + 10 * (y - 120)) as u8 + 1);
    let whole = stamp(&mask.mask(), 5, usize::MAX);
    let paged = stamp(&mask.mask(), 5, 2);
    let at = |page, slot| Some(TileAt { page, slot });
    assert_eq!(paged.set.tiles, [at(5, 0), at(5, 1), at(6, 0), at(6, 1)]);
    let (read_whole, read_paged) = (pages(&whole), pages(&paged));
    assert_eq!(read_paged.len(), 2);
    assert!(read_paged.concat() == read_whole.concat());
}

// A box that ends on a tile's edge meets no tile past it: a tile's own
// box is that tile alone.
#[test]
fn a_box_ending_on_a_tile_s_edge_meets_no_tile_past_it() {
    let side = TILE as i32;
    let mask = masked((side, -side), (TILE, TILE), |_, _| 255);
    let stamped = stamp(&mask.mask(), 0, usize::MAX);
    let set = &stamped.set;
    assert_eq!((set.x0, set.y0, set.columns, set.rows), (1, -1, 1, 1));
}

// A box with no pixels meets no tile, and puts no page — none across, or
// none down.
#[test]
fn an_empty_mask_stamps_no_tile() {
    for (size, tiles) in [((0, 3), (0, 1)), ((3, 0), (1, 0))] {
        let mask = masked((40, 40), size, |_, _| 255);
        let stamped = stamp(&mask.mask(), 0, usize::MAX);
        assert_eq!((stamped.set.columns, stamped.set.rows), tiles);
        assert!(stamped.set.tiles.is_empty() && stamped.pages.is_empty());
    }
}

// A plane that holds less than its box is refused, not read past.
#[test]
fn a_mask_short_of_its_box_is_refused() {
    let Rig { engine, flood, .. } = rig();
    let short = masked((0, 0), (4, 1), |_, _| 255);
    let mask = Mask {
        size: MaskBox { width: 4, height: 2 },
        ..short.mask()
    };
    assert!(flood.stamp(engine, &mask, &Paint::Colour(ORANGE), 0).is_none());
}

// ---- Under a gradient (I-160) ----

/// The word `stamped` holds at each of `points`.
fn graded_words(stamped: &Stamped, points: &[(i32, i32)]) -> Vec<u32> {
    let read = pages(stamped);
    points.iter().map(|&point| word(stamped, &read, 0, point)).collect()
}

/// Red at `level`, whole.
fn red(level: u32) -> u32 {
    level | 255 << 24
}

// A line's stop at a pixel is its centre's projection onto it, the nearest
// of 1024 from `from` to `to`, a half going up, and a stop's channel the
// nearest level between the ends: from (0, 0) to (1023, 0) pixel x's centre
// lies x + ½ along — stop x + 1 —, so black to red is round(255·(x + 1) /
// 1023) there (2: 765/1023 → 1, 511: 128, 1021: 254.75 → 255); the first
// behind `from`, the last past `to`.
#[test]
fn a_line_s_stop_is_the_nearest_to_a_pixel_s_centre() {
    let mask = masked((-8, 0), (1048, 1), |_, _| 255);
    let line = gradient(Shape::Line, (0.0, 0.0), (1023.0, 0.0), [BLACK, RED]);
    let stamped = graded(&mask.mask(), &line).expect("stamp");
    let points = [(-8, 0), (0, 0), (1, 0), (2, 0), (511, 0), (1021, 0), (1022, 0), (1039, 0)];
    let want = [0, 0, 0, 1, 128, 255, 255, 255].map(red);
    assert_eq!(graded_words(&stamped, &points), want);
}

// On a slant a pixel's stop takes both of its offsets: from (0, 10) to
// (1023, 1033) pixel (x, y)'s centre lies (x + y − 9) / 2 along, so (300,
// 410), (700, 10) and (0, 710) at 350.5, stop 351, red round(87.496) =
// 87, and (511, 521) at stop 512, red 128.
#[test]
fn a_line_s_stop_on_a_slant_takes_both_offsets() {
    let mask = masked((0, 0), (1024, 1034), |_, _| 255);
    let slant = gradient(Shape::Line, (0.0, 10.0), (1023.0, 1033.0), [BLACK, RED]);
    let stamped = graded(&mask.mask(), &slant).expect("stamp");
    let points = [(0, 0), (300, 410), (700, 10), (0, 710), (511, 521), (1023, 1033)];
    let want = [0, 87, 87, 87, 128, 255].map(red);
    assert_eq!(graded_words(&stamped, &points), want);
}

// A circle's stop at a pixel is its centre's distance from `from` over the
// radius, the nearest, a half going up: from the centre of (0, 0) out 2046,
// pixel (x, y) lies at stop round(√(x² + y²) / 2) — (5, 0) at 2.5, stop 3,
// red round(765/1023) = 1; (6, 8) at 5, (600, 800) at 500, red 125, (1500,
// 0) at 750, red round(186.95) = 187 —, and the last from (2045, 0), at
// 1022.5, on: at the radius and past it.
#[test]
fn a_circle_s_stop_is_the_nearest_to_a_pixel_s_distance() {
    let mask = masked((-8, -8), (2100, 1010), |_, _| 255);
    let circle = gradient(Shape::Circle, (0.5, 0.5), (2046.5, 0.5), [BLACK, RED]);
    let stamped = graded(&mask.mask(), &circle).expect("stamp");
    let points = [
        (0, 0),
        (5, 0),
        (6, 8),
        (-6, -8),
        (600, 800),
        (1500, 0),
        (2045, 0),
        (2046, 0),
        (2000, 1000),
    ];
    let want = [0, 1, 1, 1, 125, 187, 255, 255, 255].map(red);
    assert_eq!(graded_words(&stamped, &points), want);
}

// A stop just short of a half stays below it: out 105300/256 px from the
// centre of (0, 0), pixel (1, 0) lies 1023 · 256 / 105300 = 2.487 stops
// out — stop 2, red 0 —, though 4·1023² · 256² / 105300² = 24.74 rounds
// to 25: the root is of its floor. (2, 0) lies 4.97 out, stop 5, red 1.
#[test]
fn a_circle_s_stop_just_short_of_a_half_stays_below() {
    let mask = masked((0, 0), (3, 1), |_, _| 255);
    let circle = gradient(Shape::Circle, (0.5, 0.5), (411.828125, 0.5), [BLACK, RED]);
    let stamped = graded(&mask.mask(), &circle).expect("stamp");
    assert_eq!(graded_words(&stamped, &[(1, 0), (2, 0)]), [red(0), red(1)]);
}

// A stop's alpha is under the mask's byte, a clear stop keeps its colour
// as the app's stamp does, and none of the mask is nothing: orange to
// clear along (0, 0)–(1023, 0) is alpha 255 at stop 1, 255 − 128 = 127 at
// stop 512 (round(−127.6)), 0 at the last — under a byte of 128, 128 and
// round(63.75) = 64.
#[test]
fn a_stop_s_alpha_is_under_the_mask_s_byte() {
    let mask = masked((0, 0), (1023, 3), |x, y| match (x, y) {
        (_, 1) => 0,
        (0, _) | (_, 2) => 128,
        _ => 255,
    });
    let [r, g, b] = ORANGE;
    let clear = gradient(Shape::Line, (0.0, 0.0), (1023.0, 0.0), [[r, g, b, 255], [r, g, b, 0]]);
    let stamped = graded(&mask.mask(), &clear).expect("stamp");
    let points = [(0, 0), (511, 0), (511, 2), (1022, 0), (0, 1), (511, 1)];
    let orange = |alpha: u32| ORANGE_WORD | alpha << 24;
    let want = [orange(128), orange(127), orange(64), orange(0), 0, 0];
    assert_eq!(graded_words(&stamped, &points), want);
}

// A gradient of no length lays its first stop everywhere, a line or a
// circle (I-160-Q5: a press that never moved is a gradient too).
#[test]
fn a_gradient_of_no_length_lays_its_start() {
    let mask = masked((-5, -5), (10, 10), |_, _| 255);
    for shape in [Shape::Line, Shape::Circle] {
        let still = gradient(shape, (0.25, 0.25), (0.25, 0.25), [BLACK, RED]);
        let stamped = graded(&mask.mask(), &still).expect("stamp");
        let points = [(-5, -5), (0, 0), (4, 4)];
        assert_eq!(graded_words(&stamped, &points), [red(0); 3]);
    }
}

// An end lies at its nearest 1/256 px: 0.6 of one from `from` is a line
// of one, every centre past it — the end's colour from pixel 0 on —, and
// 0.4 of one no line, its start everywhere.
#[test]
fn an_end_lies_at_its_nearest_256th_of_a_pixel() {
    let mask = masked((-2, 0), (4, 1), |_, _| 255);
    let points = [(-1, 0), (0, 0), (1, 0)];
    for (along, want) in [(0.6, [0, 255, 255]), (0.4, [0, 0, 0])] {
        let short = gradient(Shape::Line, (0.0, 0.0), (along / 256.0, 0.0), [BLACK, RED]);
        let stamped = graded(&mask.mask(), &short).expect("stamp");
        assert_eq!(graded_words(&stamped, &points), want.map(red), "{along}");
    }
}

// An end, or a box, past what the sums hold is refused, as is an end that
// is no number; one on the reach is not.
#[test]
fn a_gradient_past_its_reach_is_refused() {
    let mask = masked((0, 0), (4, 4), |_, _| 255);
    let (reach, far) = (65536.0, 65536.5);
    let ends = [
        ((far, 0.0), (0.0, 0.0)),
        ((0.0, 0.0), (0.0, -far)),
        ((f64::NAN, 0.0), (0.0, 0.0)),
        ((0.0, 0.0), (f64::INFINITY, 0.0)),
    ];
    for (from, to) in ends {
        let past = gradient(Shape::Line, from, to, [BLACK, RED]);
        assert!(graded(&mask.mask(), &past).is_none(), "{from:?} {to:?}");
    }
    let on = gradient(Shape::Line, (-reach, 0.0), (0.0, reach), [BLACK, RED]);
    assert!(graded(&mask.mask(), &on).is_some());
    let near = gradient(Shape::Line, (0.0, 0.0), (1.0, 0.0), [BLACK, RED]);
    let boxes = [
        ((65530, 0), (7, 1), true),
        ((-65537, 0), (4, 1), true),
        ((0, 65534), (1, 3), true),
        ((0, -65537), (1, 4), true),
        ((65530, 65535), (6, 1), false),
    ];
    for (at, size, past) in boxes {
        let boxed = masked(at, size, |_, _| 255);
        assert_eq!(graded(&boxed.mask(), &near).is_none(), past, "{at:?} {size:?}");
    }
}
