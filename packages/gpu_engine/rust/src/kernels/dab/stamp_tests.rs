//! The stamp path on a real GPU, checked against what the app's stamp
//! holds by hand — never against a CPU copy of it (`kernels/mod.rs` has
//! why). How the executor lays it is composite's tests'.

use std::sync::OnceLock;

use super::{Gradient, Paint, Shape, Source, StampLanding, Stamped, Stamps};
use crate::device::Engine;
use crate::kernels::blend::mode::{ERASE, NORMAL};
use crate::kernels::composite::{Composite, TILE, TILE_BYTES, TileAt};
use crate::kernels::dab::abi::{
    StampPicture, gpu_engine_stamp_picture_bytes, gpu_engine_stamp_picture_carried,
    gpu_engine_stamp_picture_free, gpu_engine_stamp_picture_new, gpu_engine_stamp_picture_read,
};
use crate::kernels::dab::landing::{Asked, Laid};
use crate::kernels::mask::tests::masked;
use crate::kernels::mask::{Mask, MaskBox};
use crate::kernels::pool::{Cel, Pool};
use crate::kernels::shared::{ResampleMap, ResampleMode, le_bytes, le_words, words_buffer};
use crate::kernels::warp::Boxed;
use crate::kernels::write::Change;
use crate::testing::{first_engine, last_error, read_buffer};

/// A `within` no picture reaches past.
pub(crate) const EVERYWHERE: [i32; 4] = [i32::MIN / 2, i32::MIN / 2, i32::MAX / 2, i32::MAX / 2];

const ORANGE: [u8; 3] = [200, 100, 50];
/// ORANGE as a stamp's word at alpha 0: R in the low byte.
const ORANGE_WORD: u32 = 0x0032_64c8;
const BLACK: [u8; 4] = [0, 0, 0, 255];
const RED: [u8; 4] = [255, 0, 0, 255];

/// One compile for every test that stamps — the executor's, the fill's
/// picture's and these (blend's tests have why).
pub(crate) fn stamps() -> &'static Stamps {
    static STAMPS: OnceLock<Stamps> = OnceLock::new();
    STAMPS.get_or_init(|| Stamps::new(first_engine()))
}

/// Each of `stamped`'s pages read back, as words.
fn pages(stamped: &Stamped) -> Vec<Vec<u32>> {
    let engine = first_engine();
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

/// `source` stamped from `first_page` on, `per_page` tiles a page.
fn stamped(source: &Source, first_page: u16, per_page: usize) -> Option<Stamped> {
    stamps().stamp_by(first_engine(), source, first_page, per_page)
}

/// `mask` stamped in orange, its byte for an alpha.
fn stamp(mask: &Mask, first_page: u16, per_page: usize) -> Stamped {
    let source = Source::Mask { mask, paint: &Paint::Colour(ORANGE), whole: false };
    stamped(&source, first_page, per_page).expect("stamp")
}

/// `mask` stamped under `gradient`, or none where it is refused.
fn graded(mask: &Mask, gradient: &Gradient) -> Option<Stamped> {
    let source = Source::Mask { mask, paint: &Paint::Gradient(gradient), whole: false };
    stamps().stamp(first_engine(), &source, 0)
}

/// `words` as a picture's buffer.
fn picture(words: &[u32]) -> wgpu::Buffer {
    words_buffer(first_engine(), "picture", words, wgpu::BufferUsages::STORAGE)
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
    let short = masked((0, 0), (4, 1), |_, _| 255);
    let mask = Mask {
        size: MaskBox { width: 4, height: 2 },
        ..short.mask()
    };
    let source = Source::Mask { mask: &mask, paint: &Paint::Colour(ORANGE), whole: false };
    assert!(stamps().stamp(first_engine(), &source, 0).is_none());
}

// ---- A selection's erase (`selectionEraseDab`) ----

// Where it covers whole — no feather was asked for — a pixel the mask
// covers at all is the colour at 255, as the lift's gather takes it whole;
// one it covers none is still nothing. Not whole, the byte is the alpha.
#[test]
fn a_whole_stamp_covers_every_pixel_its_mask_touches_wholly() {
    let bytes = [0, 1, 128, 254, 255];
    let mask = masked((10, 20), (5, 1), |x, _| bytes[(x - 10) as usize]);
    let mask = mask.mask();
    for (whole, alphas) in [(true, [0, 255, 255, 255, 255]), (false, bytes)] {
        let source = Source::Mask { mask: &mask, paint: &Paint::Colour(ORANGE), whole };
        let stamped = stamped(&source, 0, usize::MAX).expect("stamp");
        let read = pages(&stamped);
        let words: Vec<u32> = (10..15).map(|x| word(&stamped, &read, 0, (x, 20))).collect();
        let want = alphas.map(|a| if a == 0 { 0 } else { ORANGE_WORD | u32::from(a) << 24 });
        assert_eq!(words, want, "whole {whole}");
    }
}

// ---- A picture: a lift's, or a warp's window ----

// A picture's words lie where its box does, each as it is — a clear word
// keeping its colour too, as the app's stamp holds it — and nothing past
// the box, though its buffer holds a row more: 3 × 2 at (126, -1) meets
// the four tiles about the canvas's first tile edge across and its top.
#[test]
fn a_picture_s_words_lie_where_its_box_does() {
    let words = [0xff00_00ff, 0x8000_ff00, 0x00ff_ffff, 0x0102_0304, 0xffff_0000, 0];
    let past = [0xdead_beef; 3];
    let pixels = picture(&[&words[..], &past].concat());
    let boxed = Boxed { pixels: &pixels, size: (3, 2) };
    let source = Source::Picture { picture: &boxed, at: (126, -1), within: EVERYWHERE };
    let stamped = stamped(&source, 2, usize::MAX).expect("stamp");
    let set = &stamped.set;
    assert_eq!((set.x0, set.y0, set.columns, set.rows), (0, -1, 2, 2));
    let read = pages(&stamped);
    for y in -2..2 {
        for x in 124..130 {
            let inside = (126..129).contains(&x) && (-1..1).contains(&y);
            let want = if inside { words[((y + 1) * 3 + x - 126) as usize] } else { 0 };
            assert_eq!(word(&stamped, &read, 2, (x, y)), want, "({x}, {y})");
        }
    }
    let put = read.concat().iter().filter(|&&word| word != 0).count();
    assert_eq!(put, 5, "a word past the box");
}

// A picture goes on to the next page as a mask does: the same words over
// two pages as over one.
#[test]
fn a_picture_past_a_page_goes_on_the_next() {
    let words: Vec<u32> = (1..=60).collect();
    let pixels = picture(&words);
    let boxed = Boxed { pixels: &pixels, size: (6, 10) };
    let source = Source::Picture { picture: &boxed, at: (-3, 120), within: EVERYWHERE };
    let whole = stamped(&source, 5, usize::MAX).expect("stamp");
    let paged = stamped(&source, 5, 2).expect("stamp");
    let at = |page, slot| Some(TileAt { page, slot });
    assert_eq!(paged.set.tiles, [at(5, 0), at(5, 1), at(6, 0), at(6, 1)]);
    let (read_whole, read_paged) = (pages(&whole), pages(&paged));
    assert_eq!(read_paged.len(), 2);
    assert!(read_paged.concat() == read_whole.concat());
}

// A picture whose buffer holds less than its box is refused, not read
// past.
#[test]
fn a_picture_short_of_its_box_is_refused() {
    let pixels = picture(&[0xffff_ffff; 5]);
    let boxed = Boxed { pixels: &pixels, size: (3, 2) };
    let source = Source::Picture { picture: &boxed, at: (0, 0), within: EVERYWHERE };
    assert!(stamps().stamp(first_engine(), &source, 0).is_none());
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
/// A row's opacity at whole, the executor's 16-bit scale.
const WHOLE: u32 = 65535;
const CEL_PIXEL: [u8; 4] = [10, 20, 30, 255];
const INK: [u8; 4] = [200, 100, 50, 255];
const NORMAL_WHOLE: Laid<'static> = Laid { opacity: WHOLE, mode: NORMAL, mask: None };

struct Landing {
    engine: &'static Engine,
    composite: Composite,
    pool: Pool,
    cel: Cel,
    landing: StampLanding,
}

fn landing() -> Landing {
    let engine = first_engine();
    let mut pool = Pool::new(engine, u64::MAX).expect("a pool");
    let cel = pool.cel();
    Landing {
        engine,
        composite: Composite::new(engine).expect("a composite"),
        pool,
        cel,
        landing: StampLanding::new(engine).expect("a landing"),
    }
}

impl Landing {
    /// A tile of the cel, every pixel `pixel`.
    fn stored(&mut self, pixel: [u8; 4]) -> TileAt {
        let bytes = pixel.repeat(TILE_BYTES as usize / 4);
        self.pool.store(self.engine, self.cel, &[&bytes]).expect("a store")[0]
    }

    /// A box of `size` every pixel `pixel`, its top-left at `at`, landed on
    /// the tiles `asked`.
    fn land(
        &mut self,
        (at, size, pixel): ((i32, i32), (u32, u32), [u8; 4]),
        asked: &[Asked],
        laid: &Laid,
    ) -> Vec<(Change, Option<TileAt>)> {
        let words = vec![u32::from_le_bytes(pixel); size.0 as usize * size.1 as usize];
        let pixels = picture(&words);
        let boxed = Boxed { pixels: &pixels, size };
        let source = Source::Picture { picture: &boxed, at, within: EVERYWHERE };
        let kit = (&self.composite, &mut self.pool, self.cel);
        self.landing.land(self.engine, kit, &source, asked, laid).expect("a landing")
    }

    fn read(&self, at: TileAt) -> Vec<u8> {
        let mut bytes = vec![0; TILE_BYTES as usize];
        self.pool.read(self.engine, &[at], &mut bytes).expect("a read");
        bytes
    }
}

fn pixel(bytes: &[u8], x: usize, y: usize) -> [u8; 4] {
    bytes[(y * 128 + x) * 4..][..4].try_into().unwrap()
}

fn asked(column: i32, row: i32, under: Option<TileAt>) -> Asked {
    Asked { column, row, under }
}

#[test]
fn a_picture_lands_on_the_cel_under_it_in_a_slot_of_its_own() {
    let mut f = landing();
    let under = f.stored(CEL_PIXEL);
    let landed = f.land(((10, 10), (10, 10), INK), &[asked(0, 0, Some(under))], &NORMAL_WHOLE);
    assert_eq!(landed.len(), 1);
    let (change, at) = landed[0];
    assert_eq!(change, Change::Inked);
    let at = at.expect("a slot");
    assert_ne!(at, under, "a stored tile is never written over");
    let bytes = f.read(at);
    assert_eq!(pixel(&bytes, 12, 12), INK);
    assert_eq!(pixel(&bytes, 5, 5), CEL_PIXEL);
    assert_eq!(pixel(&f.read(under), 12, 12), CEL_PIXEL);
}

#[test]
fn a_tile_where_the_cel_has_none_is_the_picture_alone() {
    let mut f = landing();
    let landed = f.land(((10, 10), (10, 10), INK), &[asked(0, 0, None)], &NORMAL_WHOLE);
    let bytes = f.read(landed[0].1.expect("a slot"));
    assert_eq!(pixel(&bytes, 12, 12), INK);
    assert_eq!(pixel(&bytes, 5, 5), [0, 0, 0, 0]);
}

#[test]
fn each_tile_asked_takes_its_part_of_the_picture_in_their_order() {
    let mut f = landing();
    let tiles = [asked(1, 0, None), asked(0, 0, None)];
    let landed = f.land(((120, 0), (16, 4), INK), &tiles, &NORMAL_WHOLE);
    let right = f.read(landed[0].1.expect("a slot"));
    assert_eq!(pixel(&right, 3, 1), INK);
    assert_eq!(pixel(&right, 8, 1), [0, 0, 0, 0]);
    let left = f.read(landed[1].1.expect("a slot"));
    assert_eq!(pixel(&left, 125, 1), INK);
    assert_eq!(pixel(&left, 119, 1), [0, 0, 0, 0]);
}

#[test]
fn a_picture_of_nothing_takes_no_slot() {
    let mut f = landing();
    let under = f.stored(CEL_PIXEL);
    let landed =
        f.land(((10, 10), (10, 10), [0, 0, 0, 0]), &[asked(0, 0, Some(under))], &NORMAL_WHOLE);
    assert_eq!(landed, [(Change::Same, None)]);
}

#[test]
fn an_erase_that_takes_the_whole_tile_takes_no_slot() {
    let mut f = landing();
    let under = f.stored(CEL_PIXEL);
    let erase = Laid { opacity: WHOLE, mode: ERASE, mask: None };
    let landed = f.land(((0, 0), (128, 128), INK), &[asked(0, 0, Some(under))], &erase);
    assert_eq!(landed, [(Change::Cleared, None)]);
}

#[test]
fn a_picture_lays_at_its_opacity_in_its_mode() {
    let mut f = landing();
    let under = f.stored(CEL_PIXEL);
    let at = (10, 10);
    let erase = Laid { opacity: WHOLE, mode: ERASE, mask: None };
    let erased = f.land((at, (10, 10), INK), &[asked(0, 0, Some(under))], &erase);
    assert_eq!(pixel(&f.read(erased[0].1.unwrap()), 12, 12), [0, 0, 0, 0]);
    let half = Laid { opacity: 32768, mode: NORMAL, mask: None };
    let laid = f.land((at, (10, 10), INK), &[asked(0, 0, Some(under))], &half);
    let [red, green, blue, alpha] = pixel(&f.read(laid[0].1.unwrap()), 12, 12);
    assert_eq!(alpha, 255);
    assert!((104..=106).contains(&red), "{red}");
    assert!((59..=61).contains(&green), "{green}");
    assert!((39..=41).contains(&blue), "{blue}");
}

#[test]
fn only_the_pixels_a_mask_covers_take_the_picture() {
    let mut f = landing();
    let under = f.stored(CEL_PIXEL);
    let size = MaskBox { width: 32, height: 32 };
    let usage = wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC;
    let plane = words_buffer(f.engine, "mask", &size.words_of(&[255; 32 * 32]), usage);
    let mask = Mask { plane: &plane, at: (16, 16), size };
    let laid = Laid { opacity: WHOLE, mode: NORMAL, mask: Some(&mask) };
    let landed = f.land(((0, 0), (128, 128), INK), &[asked(0, 0, Some(under))], &laid);
    let bytes = f.read(landed[0].1.expect("a slot"));
    assert_eq!(pixel(&bytes, 20, 20), INK);
    assert_eq!(pixel(&bytes, 5, 5), CEL_PIXEL);
}

#[test]
fn a_landing_asked_nothing_lands_nothing() {
    let mut f = landing();
    assert!(f.land(((0, 0), (1, 1), INK), &[], &NORMAL_WHOLE).is_empty());
}
#[test]
fn a_picture_cut_by_a_wall_reads_on_from_what_it_left_and_keeps_the_cel_past_it() {
    let mut f = landing();
    let under = f.stored(CEL_PIXEL);
    // Each pixel of the picture says where in it it lies.
    let (width, height) = (32u32, 16u32);
    let words: Vec<u32> = (0..height)
        .flat_map(|y| (0..width).map(move |x| 0xFF00_0000 | x << 8 | y))
        .collect();
    let pixels = picture(&words);
    let boxed = Boxed { pixels: &pixels, size: (width, height) };
    let source = Source::Picture { picture: &boxed, at: (4, 8), within: [10, 12, 20, 18] };
    let kit = (&f.composite, &mut f.pool, f.cel);
    let landed = f
        .landing
        .land(f.engine, kit, &source, &[asked(0, 0, Some(under))], &NORMAL_WHOLE)
        .expect("a landing");
    let bytes = f.read(landed[0].1.expect("a slot"));
    assert_eq!(pixel(&bytes, 10, 12), [4, 6, 0, 255], "the first pixel the wall left");
    assert_eq!(pixel(&bytes, 19, 17), [9, 15, 0, 255], "the last");
    for (x, y) in [(9, 12), (10, 11), (20, 12), (10, 18)] {
        assert_eq!(pixel(&bytes, x, y), CEL_PIXEL, "past the wall at {x}, {y}");
    }
}

#[test]
fn a_picture_the_wall_leaves_nothing_of_fails() {
    let f = landing();
    let pixels = picture(&[0xFFFF_FFFF]);
    let boxed = Boxed { pixels: &pixels, size: (1, 1) };
    let source = Source::Picture { picture: &boxed, at: (0, 0), within: [5, 5, 9, 9] };
    assert!(f.landing.stamps.stamp(f.engine, &source, 0).is_none());
}

/// A picture `width` × `height`, each pixel saying where in it it lies.
fn placed(width: u32, height: u32) -> Vec<u32> {
    (0..height).flat_map(|y| (0..width).map(move |x| 0xFF00_0000 | x << 8 | y)).collect()
}

/// The map that moves a picture whole pixels (`dx`, `dy`), as the app
/// hands one over.
fn moved(dx: f64, dy: f64) -> [f64; 9] {
    [1.0, 0.0, -dx, 0.0, 1.0, -dy, 0.0, 0.0, 1.0]
}

#[test]
fn a_picture_carried_is_its_pixels_through_the_map_and_nothing_past_them() {
    let f = landing();
    let pixels = picture(&placed(4, 2));
    let boxed = Boxed { pixels: &pixels, size: (4, 2) };
    let map = ResampleMap::new(moved(2.0, 1.0), 1.0, ResampleMode::Blend, 7, 4).expect("a map");
    let carried = f.landing.carried(f.engine, &boxed, Some(&map), (7, 4)).expect("a carry");
    let words = le_words(&read_buffer(f.engine, &carried));
    assert_eq!(words.len(), 7 * 4);
    let at = |x: usize, y: usize| words[y * 7 + x];
    assert_eq!(at(2, 1), 0xFF00_0000, "the picture's first pixel, moved");
    assert_eq!(at(5, 2), 0xFF00_0301, "its last");
    for (x, y) in [(1, 1), (2, 0), (6, 2), (5, 3)] {
        assert_eq!(at(x, y), 0, "past the picture at {x}, {y}");
    }
    let none = f.landing.carried(f.engine, &boxed, None, (7, 4)).expect("a carry");
    assert!(read_buffer(f.engine, &none).iter().all(|&byte| byte == 0), "no map lands nothing");
}

#[test]
fn a_carried_picture_lands_as_one_handed_over_does() {
    let mut f = landing();
    let under = f.stored(CEL_PIXEL);
    let pixels = picture(&placed(4, 2));
    let boxed = Boxed { pixels: &pixels, size: (4, 2) };
    let map = ResampleMap::new(moved(2.0, 1.0), 1.0, ResampleMode::Blend, 7, 4).expect("a map");
    let carried = f.landing.carried(f.engine, &boxed, Some(&map), (7, 4)).expect("a carry");
    let boxed = Boxed { pixels: &carried, size: (7, 4) };
    let source = Source::Picture { picture: &boxed, at: (10, 20), within: EVERYWHERE };
    let kit = (&f.composite, &mut f.pool, f.cel);
    let landed = f
        .landing
        .land(f.engine, kit, &source, &[asked(0, 0, Some(under))], &NORMAL_WHOLE)
        .expect("a landing");
    let bytes = f.read(landed[0].1.expect("a slot"));
    assert_eq!(pixel(&bytes, 12, 21), [0, 0, 0, 255], "the picture's first pixel");
    assert_eq!(pixel(&bytes, 15, 22), [1, 3, 0, 255], "its last");
    assert_eq!(pixel(&bytes, 11, 21), CEL_PIXEL, "the cel where the carry left nothing");
}

#[test]
fn the_abi_carries_a_picture_and_reads_one_back() {
    let f = landing();
    let words = placed(4, 2);
    let rgba = le_bytes(&words);
    // SAFETY: the engine is live and `rgba` holds the picture.
    let handed = unsafe { gpu_engine_stamp_picture_new(f.engine, rgba.as_ptr(), 4, 2) };
    assert!(!handed.is_null(), "{}", last_error());
    let read = |picture: *const StampPicture, pixels: usize| {
        let mut into = vec![0xAAu8; pixels * 4];
        // SAFETY: both are live and `into` holds the picture.
        assert!(
            unsafe { gpu_engine_stamp_picture_read(f.engine, picture, into.as_mut_ptr()) },
            "{}",
            last_error(),
        );
        le_words(&into)
    };
    assert_eq!(read(handed, 4 * 2), words, "a picture handed over reads back as it came");

    let inverse = moved(2.0, 1.0);
    let carry = |sampling: u32| {
        // SAFETY: all three are live and `inverse` holds nine.
        unsafe {
            gpu_engine_stamp_picture_carried(
                &f.landing,
                f.engine,
                handed,
                inverse.as_ptr(),
                1.0,
                sampling,
                7,
                4,
            )
        }
    };
    let carried = carry(ResampleMode::Blend as u32);
    assert!(!carried.is_null(), "{}", last_error());
    let read = read(carried, 7 * 4);
    assert_eq!(read[7 + 2], 0xFF00_0000, "the picture's first pixel, moved");
    assert_eq!(read[2 * 7 + 5], 0xFF00_0301, "its last");
    assert_eq!(read.iter().filter(|&&word| word != 0).count(), 4 * 2, "and no more");
    // ⚠️At least: the census is the process's, and another test's pictures
    // may be alive beside these.
    assert!(
        gpu_engine_stamp_picture_bytes() >= (4 * 2 + 7 * 4) * 4,
        "the census counts a carried picture as it counts one handed over",
    );

    assert!(carry(9).is_null(), "no sampling has the id");
    // SAFETY: each came from its new, let go of once.
    unsafe {
        gpu_engine_stamp_picture_free(carried);
        gpu_engine_stamp_picture_free(handed);
    }
}

/// 🧪What the test above cannot see (its mutants, 2026-11-11): a move of
/// whole pixels reads no neighbour, so it hears no floor; and a read counts
/// a picture's bytes, which its sides swapped make as well.
#[test]
fn the_abi_carries_by_the_floor_handed_it_into_a_picture_of_the_sides_asked() {
    let f = landing();
    let rgba = le_bytes(&placed(4, 2));
    // SAFETY: the engine is live and `rgba` holds the picture.
    let handed = unsafe { gpu_engine_stamp_picture_new(f.engine, rgba.as_ptr(), 4, 2) };
    assert!(!handed.is_null(), "{}", last_error());
    let carry = |picture: *const StampPicture, inverse: [f64; 9], floor: f64| {
        let blend = ResampleMode::Blend as u32;
        // SAFETY: all three are live and `inverse` holds nine.
        let carried = unsafe {
            gpu_engine_stamp_picture_carried(
                &f.landing,
                f.engine,
                picture,
                inverse.as_ptr(),
                floor,
                blend,
                7,
                4,
            )
        };
        assert!(!carried.is_null(), "{}", last_error());
        carried
    };
    let read = |picture: *const StampPicture| {
        let mut into = vec![0xAAu8; 7 * 4 * 4];
        // SAFETY: both are live and `into` holds the picture.
        assert!(
            unsafe { gpu_engine_stamp_picture_read(f.engine, picture, into.as_mut_ptr()) },
            "{}",
            last_error(),
        );
        le_words(&into)
    };

    // Half a pixel aside, Blend reads a pixel's neighbours: as far as its
    // floor.
    let narrow = carry(handed, moved(2.5, 1.0), 1.0);
    let wide = carry(handed, moved(2.5, 1.0), 3.0);
    assert_ne!(read(narrow), read(wide), "a wider floor blends from further");

    // 7 × 4, not 4 × 7: carried again where it lies, it is read by its sides.
    let whole = carry(handed, moved(2.0, 1.0), 1.0);
    let again = carry(whole, moved(0.0, 0.0), 1.0);
    assert_eq!(read(whole).iter().filter(|&&word| word != 0).count(), 4 * 2, "⛔CONTROL");
    assert_eq!(read(again), read(whole), "carried again where it lies, it is itself");

    // SAFETY: each came from its new, let go of once.
    unsafe {
        for picture in [narrow, wide, whole, again] {
            gpu_engine_stamp_picture_free(picture);
        }
        gpu_engine_stamp_picture_free(handed);
    }
}
