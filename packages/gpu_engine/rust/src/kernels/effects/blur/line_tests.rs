//! The blur along a way on a real GPU, checked against the ledger and
//! against what its taps give by hand — never against a CPU copy of them
//! (`kernels/mod.rs` has why). A tap at a pixel's edge falls half on each
//! side; every hand case is worked on the 16-bit premultiplied scale, the
//! taps' sum over taps · 2^16 rounded half up, then stored.

use std::sync::OnceLock;

use super::super::TileRect;
use super::super::pictures::{Blurred, LEDGER_TILES, ONE_TILE, WHITE, pattern, tiles, white};
use super::{IDENTITY, LineBlur, LinePass, MOST_TAPS};
use crate::device::Engine;
use crate::kernels::effects::tests::rgba;
use crate::testing::{assert_pinned, first_engine};

struct Rig {
    engine: &'static Engine,
    blur: LineBlur,
}

/// One device and one compiled pass for every test here (blend's tests
/// have why).
fn rig() -> &'static Rig {
    static RIG: OnceLock<Rig> = OnceLock::new();
    RIG.get_or_init(|| {
        let engine = first_engine();
        Rig {
            engine,
            blur: LineBlur::new(engine),
        }
    })
}

/// The tiles of `rect` holding `pixel`, blurred by `passes` over `plate` —
/// `None` where the blur refused them.
fn blur(
    rect: TileRect,
    plate: [i32; 4],
    passes: &[LinePass],
    pixel: impl Fn(i32, i32) -> u32,
) -> Option<Blurred> {
    let Rig { engine, blur } = rig();
    let out = blur.run(engine, &tiles(engine, rect, pixel), rect, plate, passes)?;
    Some(Blurred::read(engine, rect, &out))
}

const WHOLE_TILE: [i32; 4] = [0, 0, 128, 128];
/// Pixel (60, 60)'s centre.
const MIDDLE: [f64; 2] = [60.5, 60.5];
/// x goes where y was, y where x was less: a quarter turn.
const QUARTER_TURN: [f64; 4] = [0.0, 1.0, -1.0, 0.0];

fn only(at: (i32, i32), colour: u32) -> impl Fn(i32, i32) -> u32 {
    move |x, y| if (x, y) == at { colour } else { 0 }
}

/// A pass of `taps` taps turned and scaled about `centre` alone.
fn about(centre: [f64; 2], first: [f64; 4], each: [f64; 4], taps: u32) -> LinePass {
    LinePass {
        taps,
        step: [0.0, 0.0],
        centre,
        first,
        each,
    }
}

/// Two taps a pixel apart sit on its left and right edges, each half on
/// the pixel and half on its neighbour: ¼ · ½ · ¼ — 16384 · 32768 · 16384.
#[test]
fn two_taps_a_pixel_apart_fall_half_on_each_side() {
    let pass = LinePass::along([1.0, 0.0], 2);
    let blurred = blur(ONE_TILE, WHOLE_TILE, &[pass], only((60, 60), WHITE)).expect("blur");
    assert_eq!(blurred.row(60, 58..63), white(&[0, 64, 128, 64, 0]));
    assert_eq!(blurred.row(59, 58..63), vec![0; 5]);
    assert_eq!(blurred.row(61, 58..63), vec![0; 5]);
}

/// The second pass blurs what the first left: taps two pixels apart read
/// one pixel each side, 16384 · 32768 · 16384 to 8192 · 16384 · 16384 ·
/// 16384 · 8192.
#[test]
fn a_second_pass_blurs_what_the_first_left() {
    let passes = [LinePass::along([1.0, 0.0], 2), LinePass::along([2.0, 0.0], 2)];
    let blurred = blur(ONE_TILE, WHOLE_TILE, &passes, only((60, 60), WHITE)).expect("blur");
    assert_eq!(blurred.row(60, 57..64), white(&[0, 32, 64, 64, 64, 32, 0]));
}

/// White on the plate, red all round it. A tap's pixel past the plate is
/// nothing — never the red: taps a pixel apart give the first and last
/// column ¾ (49151). And a tap past the plate is nothing however much of it
/// would fall on it: taps a pixel and a half apart give ½ there, not 5/8.
/// Past the plate nothing is put.
#[test]
fn past_the_plate_is_nothing() {
    let plate = [60, 50, 70, 70];
    let picture = |x: i32, y: i32| {
        if (60..70).contains(&x) && (50..70).contains(&y) {
            WHITE
        } else {
            rgba(255, 0, 0, 255)
        }
    };
    let pixel_apart = blur(ONE_TILE, plate, &[LinePass::along([1.0, 0.0], 2)], picture)
        .expect("blur");
    let mut row = vec![0, 191];
    row.extend([255; 8]);
    row.extend([191, 0]);
    assert_eq!(pixel_apart.row(60, 59..71), white(&row));
    let half_more = blur(ONE_TILE, plate, &[LinePass::along([1.5, 0.0], 2)], picture)
        .expect("blur");
    let mut row = vec![0, 128];
    row.extend([255; 8]);
    row.extend([128, 0]);
    assert_eq!(half_more.row(60, 59..71), white(&row));
    for (x, y) in [(65, 49), (65, 70), (0, 0), (127, 127)] {
        assert_eq!(half_more.at(x, y), 0, "({x}, {y})");
    }
}

/// A zoom about pixel (60, 60): the second tap reads twice as far out, so
/// the white at (62, 60) lands at (61, 60) by it, and on itself by the
/// first.
#[test]
fn a_scale_reads_further_from_the_centre() {
    let zoom = about(MIDDLE, IDENTITY, [2.0, 0.0, 0.0, 2.0], 2);
    let blurred = blur(ONE_TILE, WHOLE_TILE, &[zoom], only((62, 60), WHITE)).expect("blur");
    assert_eq!(blurred.row(60, 59..64), white(&[0, 0, 128, 128, 0]));
}

/// A map is its columns, where x goes then where y goes: turned a quarter,
/// a pixel one right of the centre reads the one below it.
#[test]
fn a_map_says_where_x_goes_then_where_y_goes() {
    let turn = about(MIDDLE, QUARTER_TURN, IDENTITY, 1);
    let blurred = blur(ONE_TILE, WHOLE_TILE, &[turn], only((60, 61), WHITE)).expect("blur");
    assert_eq!(blurred.at(61, 60), WHITE);
    for (x, y) in [(59, 60), (60, 59), (60, 61), (60, 60)] {
        assert_eq!(blurred.at(x, y), 0, "({x}, {y})");
    }
}

/// Each tap's map is `each` after the last one's: x stretched twice, then
/// turned — (2·dx, dy) for the first tap, (−dy, 2·dx) for the second. The
/// white two below the centre lands below it by the first and one right
/// of it by the second; stretched after the turn, it would land two right.
#[test]
fn each_tap_maps_after_the_last_tap_mapped() {
    let pass = about(MIDDLE, [2.0, 0.0, 0.0, 1.0], QUARTER_TURN, 2);
    let blurred = blur(ONE_TILE, WHOLE_TILE, &[pass], only((60, 62), WHITE)).expect("blur");
    let half = rgba(255, 255, 255, 128);
    assert_eq!(blurred.at(60, 62), half);
    assert_eq!(blurred.at(61, 60), half);
    assert_eq!(blurred.at(62, 60), 0);
}

#[test]
fn a_pass_of_no_tap_or_too_many_is_refused() {
    for taps in [0, MOST_TAPS + 1] {
        let pass = LinePass::along([1.0, 0.0], taps);
        assert!(blur(ONE_TILE, WHOLE_TILE, &[pass], |_, _| WHITE).is_none(), "{taps}");
    }
}

#[test]
fn a_blur_of_no_pass_is_refused() {
    assert!(blur(ONE_TILE, WHOLE_TILE, &[], |_, _| WHITE).is_none());
}

#[test]
fn a_plate_reaching_past_the_tiles_or_holding_nothing_is_refused() {
    let pass = LinePass::along([1.0, 0.0], 2);
    for plate in [[-1, 0, 10, 10], [0, 0, 129, 10], [5, 5, 5, 10], [5, 9, 9, 8]] {
        assert!(blur(ONE_TILE, plate, &[pass], |_, _| WHITE).is_none(), "{plate:?}");
    }
}

/// A plate's edges are under 2^15 pixels each way, so a tap on it, Q.16,
/// stays an i32.
#[test]
fn a_plate_past_its_words_is_refused() {
    let pass = LinePass::along([1.0, 0.0], 2);
    let right = TileRect {
        x0: 255,
        y0: 0,
        columns: 1,
        rows: 1,
    };
    assert!(blur(right, [32640, 0, 32767, 10], &[pass], |_, _| WHITE).is_some());
    assert!(blur(right, [32640, 0, 32768, 10], &[pass], |_, _| WHITE).is_none());
    let left = TileRect { x0: -256, ..right };
    assert!(blur(left, [-32767, 0, -32700, 10], &[pass], |_, _| WHITE).is_some());
    assert!(blur(left, [-32768, 0, -32700, 10], &[pass], |_, _| WHITE).is_none());
}

/// A map of 16 or a shift of 2^15 pixels passes what the words hold.
#[test]
fn a_pass_past_its_words_is_refused() {
    let passes = [
        about(MIDDLE, [16.0, 0.0, 0.0, 1.0], IDENTITY, 1),
        about(MIDDLE, IDENTITY, [4.0, 0.0, 0.0, 4.0], 3),
        LinePass::along([65536.0, 0.0], 2),
        about([32768.0, 0.0], IDENTITY, IDENTITY, 1),
    ];
    for pass in passes {
        assert!(blur(ONE_TILE, WHOLE_TILE, &[pass], |_, _| WHITE).is_none(), "{pass:?}");
    }
}

// ---- The ledger ----

/// A line, two lines one after the other, a zoom and a spin with a shift,
/// on plates inside the tiles and on all of them. Every map is a sum of
/// products, the same double on every device.
fn scenes() -> Vec<([i32; 4], Vec<LinePass>)> {
    let whole = LEDGER_TILES.pixels();
    let spin = LinePass {
        taps: 9,
        step: [0.5, 0.25],
        centre: [10.25, 120.75],
        first: [0.6, 0.8, -0.8, 0.6],
        each: [0.96, -0.28, 0.28, 0.96],
    };
    vec![
        (whole, vec![LinePass::along([1.5, -0.5], 7)]),
        (
            [-100, 10, 250, 200],
            vec![LinePass::along([3.0, 0.0], 5), LinePass::along([0.0, 2.25], 3)],
        ),
        (whole, vec![about([100.25, 130.5], IDENTITY, [1.0625, 0.0, 0.0, 1.0625], 8)]),
        // Inside the tiles on every side, so each side's pixels past the
        // plate are there to be wrongly read.
        ([-120, 6, 200, 250], vec![spin]),
    ]
}

#[test]
fn every_device_blurs_the_pinned_picture() {
    let bytes: Vec<u8> = scenes()
        .into_iter()
        .flat_map(|(plate, passes)| {
            blur(LEDGER_TILES, plate, &passes, pattern).expect("blur").words
        })
        .flat_map(|word| word.to_le_bytes())
        .collect();
    assert_pinned("effects/line-blur", &bytes);
}
