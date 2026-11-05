//! The blur on a real GPU, checked against the ledger and against what the
//! box passes give by hand — never against a CPU copy of them
//! (`kernels/mod.rs` has why). Every hand case is worked on the 16-bit
//! premultiplied scale, a pass's mean rounded half up, then stored. Each
//! goes both ways a blur's passes go — a way's three in one dispatch, and a
//! pass a dispatch — and both put the same pixels.

use std::sync::OnceLock;

use super::super::TileRect;
use super::super::pictures::{Blurred, LEDGER_TILES, ONE_TILE, WHITE, pattern, tiles, white};
use super::{BoxBlur, EDGE_NOTHING, Edge, MOST_RADIUS, Route, passes, strips};
use crate::device::Engine;
use crate::kernels::effects::tests::rgba;
use crate::testing::{assert_pinned, first_engine};

struct Rig {
    engine: &'static Engine,
    blur: BoxBlur,
}

/// One device and one compiled pass for every test here (blend's tests
/// have why).
fn rig() -> &'static Rig {
    static RIG: OnceLock<Rig> = OnceLock::new();
    RIG.get_or_init(|| {
        let engine = first_engine();
        Rig {
            engine,
            blur: BoxBlur::new(engine),
        }
    })
}

/// The tiles of `rect` holding `pixel`, blurred, the passes going by
/// `route` — `None` where the blur refused them.
fn blur_by(
    rect: TileRect,
    radius: (u32, u32),
    edge: Edge,
    pixel: impl Fn(i32, i32) -> u32,
    route: Route,
) -> Option<Blurred> {
    let Rig { engine, blur } = rig();
    let out = blur.run_by(engine, &tiles(engine, rect, pixel), rect, radius, edge, route)?;
    Some(Blurred::read(engine, rect, &out))
}

/// The tiles of `rect` holding `pixel`, blurred as a blur goes, once the
/// passes a dispatch each are seen to put them alike.
fn blur(
    rect: TileRect,
    radius: (u32, u32),
    edge: Edge,
    pixel: impl Fn(i32, i32) -> u32,
) -> Option<Blurred> {
    let Rig { engine, blur } = rig();
    let picture = tiles(engine, rect, &pixel);
    let blurred = blur
        .run(engine, &picture, rect, radius, edge)
        .map(|out| Blurred::read(engine, rect, &out));
    let passes = blur_by(rect, radius, edge, &pixel, Route::Passes);
    assert_eq!(
        blurred.as_ref().map(|blurred| &blurred.words),
        passes.as_ref().map(|blurred| &blurred.words),
        "{radius:?} {edge:?}"
    );
    blurred
}

/// One opaque pixel, three boxes of radius 1: the first spreads 65535 to
/// thirds, 21845 each; the second to 7282 · 14563 · 21845 · 14563 · 7282;
/// the third to 2427 · 7282 · 14563 · 16990 · …, bytes 9 · 28 · 57 · 66.
const SPIKE: [u32; 9] = [0, 9, 28, 57, 66, 57, 28, 9, 0];

#[test]
fn one_pixel_spreads_along_its_row_by_three_boxes() {
    let blurred = blur(ONE_TILE, (1, 0), Edge::Nothing, |x, y| {
        if (x, y) == (60, 60) { WHITE } else { 0 }
    })
    .expect("blur");
    assert_eq!(blurred.row(60, 56..65), white(&SPIKE));
    // A way of radius 0 is left as it is.
    assert_eq!(blurred.row(59, 56..65), vec![0; 9]);
    assert_eq!(blurred.row(61, 56..65), vec![0; 9]);
}

#[test]
fn one_pixel_spreads_down_its_column_by_the_same_boxes() {
    let blurred = blur(ONE_TILE, (0, 1), Edge::Nothing, |x, y| {
        if (x, y) == (60, 60) { WHITE } else { 0 }
    })
    .expect("blur");
    assert_eq!(blurred.column(60, 56..65), white(&SPIKE));
    assert_eq!(blurred.column(59, 56..65), vec![0; 9]);
}

/// Both ways: the columns blur the rows' 16-bit pixels, not their bytes —
/// 16990 at the middle goes to 5663, 5663, then 4404: 17, not 66.
#[test]
fn the_columns_blur_what_the_rows_left() {
    let blurred = blur(ONE_TILE, (1, 1), Edge::Nothing, |x, y| {
        if (x, y) == (60, 60) { WHITE } else { 0 }
    })
    .expect("blur");
    let both = white(&[0, 2, 7, 15, 17, 15, 7, 2, 0]);
    assert_eq!(blurred.column(60, 56..65), both);
    assert_eq!(blurred.row(60, 56..65), both);
    // 2427 spread down three boxes is 629 at most: no byte.
    assert_eq!(blurred.at(57, 57), 0);
}

/// Half-clear red over nothing: premultiplied, the nothing beside it
/// carries no colour, so what spreads stays red — only its alpha falls
/// (32896 to 8528 · 7310 · 3655 · 1218).
#[test]
fn a_clear_neighbour_lends_no_colour() {
    let blurred = blur(ONE_TILE, (1, 0), Edge::Nothing, |x, y| {
        if (x, y) == (60, 60) { rgba(255, 0, 0, 128) } else { 0 }
    })
    .expect("blur");
    let red: Vec<u32> = [5, 14, 28, 33, 28, 14, 5].iter().map(|&a| rgba(255, 0, 0, a)).collect();
    assert_eq!(blurred.row(60, 57..64), red);
}

/// Red beside blue: at a pixel each lends what its spike left there over
/// the alpha both left — 16990 and 14563 over 31554 at the pair, 14563 and
/// 7282 over 21845 one out.
#[test]
fn two_colours_meet_by_what_each_lends() {
    let blurred = blur(ONE_TILE, (1, 0), Edge::Nothing, |x, y| match (x, y) {
        (60, 60) => rgba(255, 0, 0, 255),
        (61, 60) => rgba(0, 0, 255, 255),
        _ => 0,
    })
    .expect("blur");
    assert_eq!(
        blurred.row(60, 59..63),
        [
            rgba(170, 0, 85, 85),
            rgba(137, 0, 118, 123),
            rgba(118, 0, 137, 123),
            rgba(85, 0, 170, 85),
        ]
    );
}

/// On the tiles' first and last column a pixel blurs as one inside does:
/// each pass is worked out past the tiles as far as the next one reads.
#[test]
fn a_pixel_on_the_tiles_edge_blurs_as_an_inner_one() {
    let rect = TileRect {
        x0: -1,
        y0: 0,
        columns: 1,
        rows: 1,
    };
    let blurred = blur(rect, (1, 0), Edge::Nothing, |x, y| match (x, y) {
        (-128, 5) | (-1, 9) => WHITE,
        _ => 0,
    })
    .expect("blur");
    assert_eq!(blurred.row(5, -128..-123), white(&SPIKE[4..]));
    assert_eq!(blurred.row(9, -5..0), white(&SPIKE[..5]));
}

/// Repeat Edge Pixels: black then white across a 4 × 2 rectangle, red all
/// round it. Read past the rectangle, a pixel is the nearest inside — never
/// the red — so the rows go 0 · 0 · W · W out to either side and blur to
/// 9709 · 24272 · 41263 · 55826 (bytes 38 · 94 · 161 · 217), and the
/// columns, a pixel the same all the way down, keep them; outside, nothing.
#[test]
fn repeat_reads_the_nearest_pixel_inside_and_puts_nothing_outside() {
    let inside = [10, 20, 14, 22];
    let blurred = blur(ONE_TILE, (1, 1), Edge::Repeat(inside), |x, y| {
        if (10..14).contains(&x) && (20..22).contains(&y) {
            if x < 12 { rgba(0, 0, 0, 255) } else { WHITE }
        } else {
            rgba(255, 0, 0, 255)
        }
    })
    .expect("blur");
    let grey: Vec<u32> = [38, 94, 161, 217].iter().map(|&c| rgba(c, c, c, 255)).collect();
    assert_eq!(blurred.row(20, 10..14), grey);
    assert_eq!(blurred.row(21, 10..14), grey);
    for (x, y) in [(9, 20), (14, 21), (10, 19), (13, 22), (0, 0), (127, 127)] {
        assert_eq!(blurred.at(x, y), 0, "({x}, {y})");
    }
}

/// A picture longer along a way than one strip holds is cut into strips —
/// two of them here, each way — and they meet with no seam: both edges,
/// rows and columns, put what a pass a dispatch puts.
#[test]
fn strips_of_a_long_picture_meet_with_no_seam() {
    let wide = TileRect {
        x0: -2,
        y0: 0,
        columns: 9,
        rows: 1,
    };
    let tall = TileRect {
        x0: 0,
        y0: -1,
        columns: 1,
        rows: 9,
    };
    let scenes = [
        (wide, (5, 3), Edge::Nothing, false),
        (wide, (5, 3), Edge::Repeat([-250, 5, 880, 125]), false),
        (tall, (3, 5), Edge::Nothing, true),
        (tall, (3, 5), Edge::Repeat([5, -100, 120, 1020]), true),
    ];
    for (rect, radius, edge, down) in scenes {
        let picture = match edge {
            Edge::Nothing => rect.pixels(),
            Edge::Repeat(inside) => inside,
        };
        let way = passes(picture, radius, EDGE_NOTHING);
        let way = if down { &way[3..] } else { &way[..3] };
        assert!(strips(way).expect("strips").groups.0 > 1, "{radius:?} {edge:?}");
        let blurred = blur(rect, radius, edge, pattern).expect("blur");
        assert!(blurred.words.iter().any(|&word| word != 0), "{radius:?} {edge:?}");
    }
}

/// A box past MOST_STRIPS_RADIUS goes a pass a dispatch, whether a strip of
/// it has room (57) or none (171 — three radii each side are more than a
/// strip's 1024 pixels): a picture the same everywhere, its edge repeated,
/// blurs to itself.
#[test]
fn a_box_past_the_strips_widest_goes_a_pass_a_dispatch() {
    let inside = [0, 0, 128, 128];
    assert!(strips(&passes(inside, (57, 0), EDGE_NOTHING)).is_some());
    assert!(strips(&passes(inside, (171, 0), EDGE_NOTHING)).is_none());
    let grey = rgba(90, 120, 150, 255);
    for radius in [(57, 1), (1, 57), (171, 1), (1, 171)] {
        let blurred = blur(ONE_TILE, radius, Edge::Repeat(inside), |_, _| grey).expect("blur");
        assert!(blurred.words.iter().all(|&word| word == grey), "{radius:?}");
    }
}

#[test]
fn a_blur_of_no_radius_is_refused() {
    assert!(blur(ONE_TILE, (0, 0), Edge::Nothing, |_, _| WHITE).is_none());
}

#[test]
fn a_radius_past_the_widest_box_is_refused() {
    assert!(blur(ONE_TILE, (MOST_RADIUS + 1, 1), Edge::Nothing, |_, _| WHITE).is_none());
    assert!(blur(ONE_TILE, (1, MOST_RADIUS + 1), Edge::Nothing, |_, _| WHITE).is_none());
}

#[test]
fn a_repeat_reaching_past_the_tiles_or_holding_nothing_is_refused() {
    for inside in [[-1, 0, 10, 10], [0, 0, 129, 10], [5, 5, 5, 10], [5, 9, 9, 8]] {
        assert!(
            blur(ONE_TILE, (1, 1), Edge::Repeat(inside), |_, _| WHITE).is_none(),
            "{inside:?}"
        );
    }
}

// ---- The ledger ----

/// Each way alone and both, both edges, and radii of more than a run's
/// pixels at the edges of runs.
fn scenes() -> Vec<((u32, u32), Edge)> {
    vec![
        ((3, 5), Edge::Nothing),
        ((2, 0), Edge::Nothing),
        ((0, 4), Edge::Repeat([-100, 10, 90, 200])),
        ((70, 2), Edge::Repeat([-128, 0, 128, 256])),
        ((1, 33), Edge::Nothing),
    ]
}

/// The same pin either way the passes go (gpu-canonical-store 01:15 (b) ②).
#[test]
fn every_device_blurs_the_pinned_picture() {
    for route in [Route::Strips, Route::Passes] {
        let bytes: Vec<u8> = scenes()
            .into_iter()
            .flat_map(|(radius, edge)| {
                blur_by(LEDGER_TILES, radius, edge, pattern, route).expect("blur").words
            })
            .flat_map(|word| word.to_le_bytes())
            .collect();
        assert_pinned("effects/blur", &bytes);
    }
}
