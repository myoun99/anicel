//! The fill's C ABI on a real GPU, checked by hand: a press floods the
//! picture its plan shows and comes back as the box its mask covers and
//! the mask's bytes, each knob the one the tool turns; a posed picture is
//! pressed in its own space; one picture serves every press; and what is
//! refused says why.

use std::sync::OnceLock;

use super::*;
use crate::kernels::blend::mode::NORMAL;
use crate::kernels::composite::abi::{
    gpu_engine_plan_free, gpu_engine_plan_new, gpu_engine_plan_row, gpu_engine_plan_set,
};
use crate::kernels::composite::tests::rig as composite_rig;
use crate::kernels::composite::{TILE, WHOLE};
use crate::kernels::shared::le_bytes;
use crate::testing::{last_error, stored};

const IDENTITY: [f64; 9] = [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0];
const BLEND: u32 = 0;
const BLACK: u32 = 255 << 24;
/// The two tiles a test's cel is drawn on, side by side from the origin.
const CANVAS: [i32; 4] = [0, 0, 256, 128];

struct Rig(*mut Floods);

// SAFETY: the kernels are made once and only read after.
unsafe impl Send for Rig {}
// SAFETY: as above.
unsafe impl Sync for Rig {}

/// The fill's kernels compiled through the ABI, once for every test here,
/// on the composite's one device.
fn floods() -> *const Floods {
    static RIG: OnceLock<Rig> = OnceLock::new();
    let rig = RIG.get_or_init(|| {
        // SAFETY: the engine is live for the process.
        Rig(unsafe { gpu_engine_floods_new(composite_rig().engine) })
    });
    rig.0
}

/// A cel of two tiles side by side from the canvas's origin whose pixel at
/// (x, y) is `pixel`'s, stored, and the plan that lays it whole.
fn drawn(pixel: impl Fn(i32, i32) -> u32) -> (Pool, *mut Planned) {
    let side = TILE as i32;
    let tile = |column: i32| {
        let across = |y: i32| (0..side).map(move |x| (column * side + x, y));
        le_bytes(&(0..side).flat_map(across).map(|(x, y)| pixel(x, y)).collect::<Vec<_>>())
    };
    let (pool, at) = stored(&[tile(0), tile(1)]);
    let plan = gpu_engine_plan_new();
    // Its one tile set, and no matrix, keys or chain.
    let (set, none) = (0, -1);
    // SAFETY: `plan` is live; each array holds what its call reads.
    unsafe {
        let tiles = [at[0].word(), at[1].word()];
        assert_eq!(gpu_engine_plan_set(plan, 0, 0, 2, 1, tiles.as_ptr()), set);
        let (pose, across) = (IDENTITY.as_ptr(), 2 * TILE);
        let laid = gpu_engine_plan_row(
            plan, set, none, none, none, pose, 1.0, BLEND, across, TILE, WHOLE, NORMAL,
        );
        assert_eq!(laid, 1);
    }
    (pool, plan)
}

/// A black ring, a pixel wide, from (20, 20) to (180, 100) across both
/// tiles, but for the `holes` in it — and a black dot inside it at
/// (60, 60) —, on nothing.
fn ring(holes: &'static [(i32, i32)]) -> impl Fn(i32, i32) -> u32 {
    move |x, y| {
        let on = (20..=180).contains(&x) && (20..=100).contains(&y);
        let wall = on && (x == 20 || x == 180 || y == 20 || y == 100);
        let inked = (wall && !holes.contains(&(x, y))) || (x, y) == (60, 60);
        if inked { BLACK } else { 0 }
    }
}

/// What `plan` shows over `extent`, through the ABI: null where refused.
fn picture(pool: &Pool, plan: *const Planned, extent: [i32; 4]) -> *mut Shown {
    let rig = composite_rig();
    // SAFETY: every pointer is live, made on the engine; `extent` holds four.
    unsafe { gpu_engine_flood_picture_new(&rig.composite, rig.engine, pool, plan, extent.as_ptr()) }
}

/// The fill tool's knobs as the ABI takes them.
#[derive(Clone, Copy, Default)]
struct Knobs {
    tolerance: u32,
    gap: u32,
    expand: u32,
    anti_alias: bool,
}

/// A finished fill read back: the box its mask covers — [left, top,
/// width, height] — and the mask's bytes.
struct Read {
    covers: [i32; 4],
    bytes: Vec<u8>,
}

impl Read {
    /// The mask's byte at (`x`, `y`) of the picture's space — nothing past
    /// its box.
    fn at(&self, x: i32, y: i32) -> u8 {
        let [left, top, width, height] = self.covers;
        let inside = (left..left + width).contains(&x) && (top..top + height).contains(&y);
        if inside { self.bytes[((y - top) * width + x - left) as usize] } else { 0 }
    }

    /// Fails unless it covers every pixel of [`CANVAS`] where `covered`,
    /// whole, and none where not.
    #[track_caller]
    fn covers_where(&self, covered: impl Fn(i32, i32) -> bool) {
        let [left, top, right, bottom] = CANVAS;
        let pixels = (top..bottom).flat_map(|y| (left..right).map(move |x| (x, y)));
        let want = |x, y| if covered(x, y) { 255 } else { 0 };
        let off: Vec<_> = pixels.filter(|&(x, y)| self.at(x, y) != want(x, y)).take(8).collect();
        assert!(off.is_empty(), "the mask is off at {off:?}, among others");
    }
}

/// A press at `at` of `picture`'s space by `knobs`, through the ABI: the
/// fill read back, none where it was refused.
fn pressed(picture: *const Shown, (x, y): (i32, i32), knobs: Knobs) -> Option<Read> {
    let engine = composite_rig().engine;
    let Knobs { tolerance, gap, expand, anti_alias } = knobs;
    let mut covers = [-7; 4];
    // SAFETY: every pointer is live, made on the engine; `covers` holds four.
    let filled = unsafe {
        let covers = covers.as_mut_ptr();
        gpu_engine_flood_run(
            floods(), engine, picture, x, y, tolerance, gap, expand, anti_alias, covers,
        )
    };
    if filled.is_null() {
        return None;
    }
    let mut bytes = vec![7; (covers[2] * covers[3]) as usize];
    let (into, length) = (bytes.as_mut_ptr(), bytes.len());
    // SAFETY: `filled` is live and `bytes` holds its length.
    let read = unsafe { gpu_engine_flood_filled_read(engine, filled, into, length) };
    assert!(read, "{}", last_error());
    // SAFETY: `filled` came from the run.
    unsafe { gpu_engine_flood_filled_free(filled) };
    Some(Read { covers, bytes })
}

/// Lets go of what a test made through the ABI.
fn done(pictures: &[*mut Shown], plan: *mut Planned) {
    // SAFETY: each came from its new, let go of once.
    unsafe {
        for &picture in pictures {
            gpu_engine_flood_picture_free(picture);
        }
        gpu_engine_plan_free(plan);
    }
}

/// Whether (x, y) is inside the ring, its walls not among them.
fn in_the_ring(x: i32, y: i32) -> bool {
    (21..=179).contains(&x) && (21..=99).contains(&y)
}

// A press inside the ring fills the ring's inside and nothing else — not
// its walls, not the dot — and comes back as the box of what it filled, a
// byte a pixel: a box 159 wide, whose rows are no whole words, read row
// after row with none of a plane's padding. A press outside it on the same
// picture fills the rest — the picture as it was, whatever was pressed
// before — to the canvas's edge.
#[test]
fn a_press_fills_what_it_reaches_and_comes_back_as_its_box_and_bytes() {
    let (pool, plan) = drawn(ring(&[]));
    let shown = picture(&pool, plan, CANVAS);
    assert!(!shown.is_null(), "{}", last_error());
    let inside = pressed(shown, (150, 30), Knobs::default()).expect("inside");
    assert_eq!(inside.covers, [21, 21, 159, 79]);
    inside.covers_where(|x, y| in_the_ring(x, y) && (x, y) != (60, 60));
    let outside = pressed(shown, (5, 110), Knobs::default()).expect("outside");
    assert_eq!(outside.covers, [0, 0, 256, 128]);
    outside.covers_where(|x, y| !(20..=180).contains(&x) || !(20..=100).contains(&y));
    done(&[shown], plan);
}

// The fill is grown as many pixels as the tool says, a generation of the
// four neighbours a pixel: two of them cover what lies two steps from the
// ring's inside — its walls, the dot, a row past the walls, and no
// corner past them — and the box is two wider every way.
#[test]
fn a_fill_is_grown_the_pixels_the_tool_says() {
    let (pool, plan) = drawn(ring(&[]));
    let shown = picture(&pool, plan, CANVAS);
    let knobs = Knobs { expand: 2, ..Knobs::default() };
    let grown = pressed(shown, (150, 30), knobs).expect("grown");
    assert_eq!(grown.covers, [19, 19, 163, 83]);
    let steps = |x: i32, y: i32| (21 - x).max(x - 179).max(0) + (21 - y).max(y - 99).max(0);
    grown.covers_where(|x, y| steps(x, y) <= 2);
    done(&[shown], plan);
}

// Anti-aliased, the fill is softened a pixel past its outline: the box is
// one wider every way, the wall beside the fill is covered in part where a
// hard fill leaves it bare, and the fill's own pixels stay whole.
#[test]
fn a_fill_is_softened_past_its_outline_where_the_tool_anti_aliases() {
    let (pool, plan) = drawn(ring(&[]));
    let shown = picture(&pool, plan, CANVAS);
    let knobs = Knobs { anti_alias: true, ..Knobs::default() };
    let soft = pressed(shown, (150, 30), knobs).expect("soft");
    assert_eq!(soft.covers, [20, 20, 161, 81]);
    assert!((1..255).contains(&soft.at(20, 50)), "{}", soft.at(20, 50));
    assert_eq!([soft.at(100, 50), soft.at(22, 22)], [255; 2]);
    done(&[shown], plan);
}

// A pixel fills where every channel lies within the tolerance of the
// pressed one's, the tolerance itself among them (F-416): a half 10 off
// the pressed half's red is walled at 9 and filled at 10.
#[test]
fn a_fill_takes_what_lies_within_its_tolerance_and_at_it() {
    let grey = |red: u32| red | 100 << 8 | 100 << 16 | 255 << 24;
    let (pool, plan) = drawn(move |x, _| if x < 128 { grey(100) } else { grey(110) });
    let shown = picture(&pool, plan, CANVAS);
    let within = |tolerance| {
        let knobs = Knobs { tolerance, ..Knobs::default() };
        pressed(shown, (10, 10), knobs).expect("pressed").covers
    };
    assert_eq!([within(9), within(10)], [[0, 0, 128, 128], [0, 0, 256, 128]]);
    done(&[shown], plan);
}

// A ring with a pixel out of its wall leaks a plain fill to the canvas's
// edge; one that closes gaps of three pixels stays inside it — the wall
// and the gap in it at most —, and fills the ring.
#[test]
fn a_fill_that_closes_gaps_stays_inside_a_wall_with_a_pixel_out() {
    let (pool, plan) = drawn(ring(&[(20, 60)]));
    let shown = picture(&pool, plan, CANVAS);
    let leaked = pressed(shown, (150, 30), Knobs::default()).expect("leaked");
    assert_eq!(leaked.covers, [0, 0, 256, 128]);
    let knobs = Knobs { gap: 3, ..Knobs::default() };
    let closed = pressed(shown, (150, 30), knobs).expect("closed");
    let [left, top, width, height] = closed.covers;
    assert!(left >= 20 && top >= 21, "{:?}", closed.covers);
    assert!(left + width <= 180 && top + height <= 100, "{:?}", closed.covers);
    assert_eq!([closed.at(150, 30), closed.at(100, 90), closed.at(19, 60)], [255, 255, 0]);
    done(&[shown], plan);
}

// A picture posed is pressed in its own space: read from a space 37
// pixels left of the canvas and 9 below it — nine doubles, row-major —
// the ring's inside is filled where it lies there, the dot with it.
#[test]
fn a_posed_picture_is_pressed_in_its_own_space() {
    let (pool, plan) = drawn(ring(&[]));
    let rig = composite_rig();
    let to_canvas = [1.0, 0.0, 37.0, 0.0, 1.0, -9.0, 0.0, 0.0, 1.0];
    let asked = [-37, 9, 219, 137];
    // SAFETY: every pointer is live, made on the engine; `to_canvas` holds
    // nine doubles, `asked` and the world — the canvas — four words each.
    let posed = unsafe {
        let (pose, asked, world) = (to_canvas.as_ptr(), asked.as_ptr(), CANVAS.as_ptr());
        gpu_engine_flood_picture_posed(&rig.composite, rig.engine, &pool, plan, pose, asked, world)
    };
    assert!(!posed.is_null(), "{}", last_error());
    let inside = pressed(posed, (150 - 37, 30 + 9), Knobs::default()).expect("inside");
    assert_eq!(inside.covers, [21 - 37, 21 + 9, 159, 79]);
    assert_eq!([inside.at(60 - 37, 60 + 9), inside.at(61 - 37, 60 + 9)], [0, 255]);
    done(&[posed], plan);
}

// What cannot be filled is refused with why: a press off the picture's
// tiles, a press on them past the box the picture was asked over, a
// picture of a box with no pixel, and a read into bytes that are not the
// mask's.
#[test]
fn what_cannot_be_filled_is_refused_with_why() {
    let (pool, plan) = drawn(ring(&[]));
    let shown = picture(&pool, plan, [0, 0, 200, 128]);
    assert!(pressed(shown, (300, 10), Knobs::default()).is_none());
    assert!(last_error().contains("off the picture"), "{}", last_error());
    assert!(pressed(shown, (220, 10), Knobs::default()).is_none());
    assert!(last_error().contains("off the picture's"), "{}", last_error());
    assert!(picture(&pool, plan, [5, 5, 5, 9]).is_null());
    assert!(last_error().contains("shows no pixel"), "{}", last_error());
    let engine = composite_rig().engine;
    let mut covers = [0; 4];
    // SAFETY: every pointer is live, made on the engine; `covers` holds
    // four words and `short` its length.
    unsafe {
        let run = |covers| {
            gpu_engine_flood_run(floods(), engine, shown, 150, 30, 0, 0, 0, false, covers)
        };
        let filled = run(covers.as_mut_ptr());
        assert!(!filled.is_null(), "{}", last_error());
        let mut short = vec![7u8; 159 * 79 - 1];
        assert!(!gpu_engine_flood_filled_read(engine, filled, short.as_mut_ptr(), short.len()));
        assert!(last_error().contains("are not a mask"), "{}", last_error());
        assert!(short.iter().all(|&byte| byte == 7));
        gpu_engine_flood_filled_free(filled);
    }
    done(&[shown], plan);
}
