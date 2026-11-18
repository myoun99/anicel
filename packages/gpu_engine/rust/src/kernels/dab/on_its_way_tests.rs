//! A stroke's step handed to the engine's thread, its caller waiting for
//! none of it (card a-stroke-step-waits-for-the-engines-turn): the pile
//! ([`gpu_engine_stroke_pile`]) and the landing on its way
//! ([`gpu_engine_stroke_land_unwaited`]) through the C ABI, on a device of
//! the test's own, whose thread a test can make stand still.

use std::sync::Mutex;
use std::time::{Duration, Instant};

use super::{
    DabSpec, NO_STEP, Texture, gpu_engine_dab_texture_free, gpu_engine_dab_texture_new,
    gpu_engine_stroke_clear, gpu_engine_stroke_free, gpu_engine_stroke_land,
    gpu_engine_stroke_land_unwaited, gpu_engine_stroke_new, gpu_engine_stroke_pile,
};
use crate::device::{Engine, gpu_engine_close, gpu_engine_open_first, gpu_engine_stand_still};
use crate::kernels::blend::mode::NORMAL;
use crate::kernels::composite::abi::{
    MaskPlane, gpu_engine_composite_free, gpu_engine_composite_new, gpu_engine_mask_free,
    gpu_engine_mask_new,
};
use crate::kernels::composite::{Composite, NO_TILE, TILE_BYTES};
use crate::kernels::dab::stroke::Stroke;
use crate::kernels::pool::{
    Cel, Pool, gpu_engine_pool_cel, gpu_engine_pool_free, gpu_engine_pool_new, gpu_engine_pool_read,
};
use crate::testing::{DeviceTurn, a_device_of_its_own, done_here, last_error};

const WHOLE: u32 = 65535;
/// The opacity 128 is: 128 · 257.
const HALF: u32 = 32896;
const INK: [u8; 4] = [200, 100, 50, 255];
const UNDER: [u8; 4] = [10, 220, 90, 255];
/// A 2 × 2 tip, row after row: 255, 128 over 64, 0 (the kernel's tests).
const CORNERS: [f64; 4] = [1.0, 128.0 / 255.0, 64.0 / 255.0, 0.0];

/// What landings on their way told: each one's number and whether its
/// picture was put.
static TOLD: Mutex<Vec<(u64, bool)>> = Mutex::new(Vec::new());

extern "C" fn told(number: u64, put: bool) {
    TOLD.lock().unwrap().push((number, put));
}

fn was_put(number: u64) -> Option<bool> {
    TOLD.lock().unwrap().iter().find(|&&(told, _)| told == number).map(|&(_, put)| put)
}

/// A square dab of `colour` over `region`, whole: the kernel's
/// `tests::square` as the app hands one.
fn square(region: [i32; 4], colour: [u8; 4]) -> DabSpec {
    DabSpec {
        centre: [0.0, 0.0],
        opacity: 1.0,
        flow: 1.0,
        contrast: 1.0,
        radius: 0.0,
        cos: 1.0,
        sin: 0.0,
        roundness: 1.0,
        scale: 0.0,
        reach: 0.0,
        inner: 0.0,
        density: 1.0,
        texture: std::ptr::null(),
        coverage: std::ptr::null(),
        pile: std::ptr::null(),
        evening: std::ptr::null(),
        entries: 0,
        row_length: 0,
        flags: 0,
        region,
        colour: u32::from_le_bytes(colour),
        mix: NO_STEP,
    }
}

/// A bitmap tip of `texture` and `radius` at `centre`, unturned, over its
/// box.
fn tipped(texture: *const Texture, radius: f64, [cx, cy]: [f64; 2]) -> DabSpec {
    DabSpec {
        centre: [cx, cy],
        radius,
        texture,
        region: [
            (cx - radius).floor() as i32,
            (cy - radius).floor() as i32,
            (cx + radius).ceil() as i32,
            (cy + radius).ceil() as i32,
        ],
        ..square([0; 4], INK)
    }
}

/// An engine of the test's own, under the tests' turn for one, and what a
/// stroke lands with on it.
struct Own {
    engine: *mut Engine,
    composite: *mut Composite,
    pool: *mut Pool,
    cel: u32,
    stroke: *mut Stroke,
    _turn: DeviceTurn,
}

fn open() -> Own {
    let turn = a_device_of_its_own();
    let engine = gpu_engine_open_first();
    assert!(!engine.is_null(), "{}", last_error());
    // SAFETY: the engine is live.
    unsafe {
        let composite = gpu_engine_composite_new(engine);
        assert!(!composite.is_null(), "{}", last_error());
        let pool = gpu_engine_pool_new(engine, u64::MAX);
        let cel = gpu_engine_pool_cel(pool);
        let stroke = gpu_engine_stroke_new(engine);
        assert!(!stroke.is_null(), "{}", last_error());
        Own { engine, composite, pool, cel, stroke, _turn: turn }
    }
}

/// # Safety
/// `own` came from [`open`], and nothing names what it holds.
unsafe fn close(own: Own) {
    // SAFETY: see the function's contract.
    unsafe {
        gpu_engine_stroke_free(own.stroke);
        gpu_engine_pool_free(own.pool);
        gpu_engine_composite_free(own.composite);
        gpu_engine_close(own.engine);
    }
}

/// Piles `dabs` on the stroke: no paper, no second tip, no mixing.
///
/// # Safety
/// `own` came from [`open`]; each dab's texture is live.
unsafe fn pile(own: &Own, dabs: &[DabSpec]) {
    use std::ptr::null;
    // SAFETY: see the function's contract.
    unsafe {
        gpu_engine_stroke_pile(
            own.stroke,
            own.engine,
            dabs.as_ptr(),
            dabs.len(),
            null(),
            1.0,
            false,
            -1,
            1.0,
            null(),
            null(),
            null(),
            0,
        )
    }
}

/// The stroke's tile (0, 0) over `under` at `opacity` in normal under
/// `mask`, in a fresh slot: handed over and told as `number` where there
/// is one, else waited for, uncompared. What it returned, and the slot's
/// word.
///
/// # Safety
/// `own` came from [`open`]; `mask` is live or null.
unsafe fn land(own: &Own, under: u32, opacity: u32, mask: *const MaskPlane, number: Option<u64>) -> (isize, u32) {
    let (asks, under) = ([0, 0], [under]);
    let (mut places, mut changes) = ([NO_TILE], [9u8]);
    // SAFETY: see the function's contract; each list holds one.
    let landed = unsafe {
        match number {
            Some(number) => gpu_engine_stroke_land_unwaited(
                own.stroke,
                own.engine,
                own.composite,
                own.pool,
                own.cel,
                asks.as_ptr(),
                under.as_ptr(),
                1,
                opacity,
                NORMAL,
                mask,
                places.as_mut_ptr(),
                changes.as_mut_ptr(),
                told,
                number,
            ),
            None => gpu_engine_stroke_land(
                own.stroke,
                own.engine,
                own.composite,
                own.pool,
                own.cel,
                asks.as_ptr(),
                under.as_ptr(),
                1,
                opacity,
                NORMAL,
                mask,
                false,
                places.as_mut_ptr(),
                changes.as_mut_ptr(),
            ),
        }
    };
    if landed == 1 {
        assert_eq!(changes[0], 1, "landed inked");
    }
    (landed, places[0])
}

/// The bytes of the slot `word` names.
///
/// # Safety
/// `own` came from [`open`].
unsafe fn read(own: &Own, word: u32) -> Vec<u8> {
    let mut bytes = vec![0; TILE_BYTES as usize];
    // SAFETY: see the function's contract; `bytes` holds a tile.
    let read = unsafe { gpu_engine_pool_read(own.pool, own.engine, &word, 1, bytes.as_mut_ptr()) };
    assert!(read, "{}", last_error());
    bytes
}

fn pixel(bytes: &[u8], x: usize, y: usize) -> [u8; 4] {
    bytes[(y * 128 + x) * 4..][..4].try_into().unwrap()
}

// A step of a stroke — its pile and its landing on its way — waits for no
// turn of the engine's thread: both return while that thread stands still,
// its slot told and its picture not yet put; once the thread goes on, the
// picture is told put, with the step's pile in it.
#[test]
fn a_stroke_s_step_waits_for_no_turn_of_the_engine_s_thread() {
    // SAFETY: the engine is this test's own, live till its close.
    unsafe {
        let own = open();
        // ⛔premise: the stroke's pages and a pool's page with room made —
        // the engine's thread's work, which stands still below.
        pile(&own, &[square([0, 0, 64, 64], INK)]);
        let (landed, first) = land(&own, NO_TILE, WHOLE, std::ptr::null(), Some(701));
        assert_eq!(landed, 1, "{}", last_error());
        assert_eq!(done_here(&*own.engine), Ok(()));
        assert_eq!(was_put(701), Some(true), "⛔premise: a landing is told");
        gpu_engine_stand_still(own.engine, 2_000);
        let started = Instant::now();
        pile(&own, &[square([32, 32, 96, 96], INK)]);
        let (landed, second) = land(&own, NO_TILE, WHOLE, std::ptr::null(), Some(702));
        let took = started.elapsed();
        assert_eq!(landed, 1, "its slot told");
        assert_eq!(was_put(702), None, "told its slot before its picture was laid");
        assert!(took < Duration::from_millis(1_000), "the step waited {took:?} for the engine's thread");
        assert_eq!(done_here(&*own.engine), Ok(()));
        assert_eq!(was_put(702), Some(true));
        let (first, second) = (read(&own, first), read(&own, second));
        assert_eq!(pixel(&first, 10, 10), INK);
        assert_eq!(pixel(&first, 80, 80)[3], 0, "⛔premise: the first pile is not past (64, 64)");
        assert_eq!(pixel(&second, 80, 80), INK, "the step's pile is in its landing");
        assert_eq!(pixel(&second, 10, 10), INK);
        close(own);
    }
}

// A pile holds what it was handed (`Piled`): a tip let go of the moment the
// pile returns, before the engine's thread has run it — its memory taken
// by a tip of nothing at once — lays as one kept. ⚠️A tip the stroke has
// not sent yet: a tip is sent once, known again by its id (`placing`), and
// one sent is not read again.
#[test]
fn a_tip_let_go_of_as_its_pile_returns_lays_as_one_kept() {
    // SAFETY: the engine is this test's own, live till its close; each tip
    // is live till it is let go of, and no pile names it after.
    unsafe {
        let own = open();
        let tip = gpu_engine_dab_texture_new(CORNERS.as_ptr(), 2);
        assert!(!tip.is_null(), "{}", last_error());
        pile(&own, &[tipped(tip, 8.0, [20.0, 20.0])]);
        let (_, kept) = land(&own, NO_TILE, WHOLE, std::ptr::null(), Some(711));
        assert_eq!(done_here(&*own.engine), Ok(()));
        gpu_engine_stroke_clear(own.stroke, own.engine);
        gpu_engine_stand_still(own.engine, 500);
        let again = gpu_engine_dab_texture_new(CORNERS.as_ptr(), 2);
        pile(&own, &[tipped(again, 8.0, [20.0, 20.0])]);
        gpu_engine_dab_texture_free(again);
        let nothing = gpu_engine_dab_texture_new([0.0; 4].as_ptr(), 2);
        let (_, freed) = land(&own, NO_TILE, WHOLE, std::ptr::null(), Some(712));
        assert_eq!(done_here(&*own.engine), Ok(()));
        assert_eq!((was_put(711), was_put(712)), (Some(true), Some(true)));
        let (kept, freed) = (read(&own, kept), read(&own, freed));
        assert!(kept.chunks_exact(4).any(|pixel| pixel[3] != 0), "LIVENESS: the tip was laid");
        assert!(freed == kept, "the tip let go of lays as the one kept");
        gpu_engine_dab_texture_free(nothing);
        gpu_engine_dab_texture_free(tip);
        close(own);
    }
}

// A landing on its way lays what a waited one lays — over the cel's tile
// under it, at its opacity, under its mask —: one road for the picture,
// only the wait differs.
#[test]
fn a_landing_on_its_way_lays_what_a_waited_one_lays() {
    // SAFETY: the engine is this test's own, live till its close; the mask
    // is live till it is let go of, after the landings.
    unsafe {
        let own = open();
        let tile = UNDER.repeat(TILE_BYTES as usize / 4);
        let under = (&mut *own.pool).store(&*own.engine, Cel(own.cel), &[&tile]).expect("store")[0].word();
        let row = [255u8, 128, 0];
        let mask = gpu_engine_mask_new(own.engine, row.as_ptr(), 0, 5, 3, 1);
        assert!(!mask.is_null(), "{}", last_error());
        pile(&own, &[square([0, 0, 64, 64], INK)]);
        let (waited_landed, waited) = land(&own, under, HALF, mask, None);
        let (landed, on_its_way) = land(&own, under, HALF, mask, Some(721));
        assert_eq!((waited_landed, landed), (1, 1), "{}", last_error());
        assert_eq!(done_here(&*own.engine), Ok(()));
        assert_eq!(was_put(721), Some(true));
        let (waited, on_its_way) = (read(&own, waited), read(&own, on_its_way));
        assert!(on_its_way == waited, "one picture, waited or not");
        assert_eq!(pixel(&waited, 2, 5), UNDER, "LIVENESS: the mask's nought keeps the tile under");
        assert_ne!(pixel(&waited, 0, 5), UNDER, "LIVENESS: the stroke over it");
        assert_ne!(pixel(&waited, 0, 5), pixel(&waited, 1, 5), "LIVENESS: under the mask's byte");
        assert_eq!(pixel(&waited, 0, 6), UNDER, "LIVENESS: nothing past the mask's box");
        gpu_engine_mask_free(mask);
        close(own);
    }
}

// 🚨A pile's refusal is the stroke's, not the engine's (`Stroke::refuse`):
// the caller's next done is not broken by it; the stroke's next landing on
// its way is told not put — and that done is —, a waited one fails with
// the pile's reason, and a stroke cleared lands again.
#[test]
fn a_pile_refused_is_told_by_what_reads_the_stroke_next() {
    // SAFETY: the engine is this test's own, live till its close; the tip
    // is live till it is let go of, after the piles.
    unsafe {
        let own = open();
        let tip = gpu_engine_dab_texture_new(CORNERS.as_ptr(), 2);
        // A tip past what the integers hold (the kernel's tests).
        pile(&own, &[tipped(tip, 0.001, [10.0, 10.0])]);
        assert_eq!(done_here(&*own.engine), Ok(()), "a pile refused leaves the done alone");
        let (landed, _) = land(&own, NO_TILE, WHOLE, std::ptr::null(), Some(731));
        assert_eq!(landed, 1, "its slot told: the books are the caller's");
        assert!(done_here(&*own.engine).is_err(), "the landing not put is told by the next done");
        assert_eq!(was_put(731), Some(false));
        let (landed, _) = land(&own, NO_TILE, WHOLE, std::ptr::null(), None);
        assert_eq!(landed, -1);
        assert!(last_error().contains("a pile handed over unwaited failed"), "{}", last_error());
        gpu_engine_stroke_clear(own.stroke, own.engine);
        pile(&own, &[square([0, 0, 64, 64], INK)]);
        let (landed, at) = land(&own, NO_TILE, WHOLE, std::ptr::null(), Some(732));
        assert_eq!(landed, 1, "{}", last_error());
        assert_eq!(done_here(&*own.engine), Ok(()));
        assert_eq!(was_put(732), Some(true), "a stroke cleared lands again");
        assert_eq!(pixel(&read(&own, at), 10, 10), INK);
        gpu_engine_dab_texture_free(tip);
        close(own);
    }
}
