//! A stroke's step handed to the engine's thread, its caller waiting for
//! none of it (card a-stroke-step-waits-for-the-engines-turn): the pile
//! ([`gpu_engine_stroke_pile`]) and the landing on its way
//! ([`gpu_engine_stroke_land_unwaited`]) through the C ABI, on a device of
//! the test's own, whose thread a test can make stand still.

use std::sync::Mutex;
use std::time::{Duration, Instant};

use super::{
    DabSpec, EVENING_ENTRIES, NO_STEP, StepSpec, Texture, gpu_engine_blurs_free, gpu_engine_blurs_new,
    gpu_engine_dab_texture_free, gpu_engine_dab_texture_new, gpu_engine_mix_ground, gpu_engine_rub_ground,
    gpu_engine_stroke_clear, gpu_engine_stroke_free, gpu_engine_stroke_land, gpu_engine_stroke_land_blur,
    gpu_engine_stroke_land_blur_unwaited, gpu_engine_stroke_land_unwaited, gpu_engine_stroke_mixed,
    gpu_engine_stroke_new, gpu_engine_stroke_pile, gpu_engine_stroke_rub, piled,
};
use crate::kernels::dab::blur::Blurs;
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
        let pool = gpu_engine_pool_new(engine, u64::MAX, u64::MAX);
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
            0,
            0,
            null(),
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

// What a pile is handed is its own (`Piled`): each tip and table a spec
// names is a copy the pile holds, as the app's — the app lets go of its
// own the moment the pile returns, before the engine's thread has run it
// — and two specs naming one are handed one copy. ⛔Not pinned by pixels:
// a pile that read a tip let go of reads whatever its memory holds next,
// which a test cannot make sure differs (that pin passed with the copy
// taken away).
#[test]
fn a_pile_names_copies_of_its_own_of_what_it_was_handed() {
    // SAFETY: CORNERS holds a side of two squared.
    let tip = unsafe { gpu_engine_dab_texture_new(CORNERS.as_ptr(), 2) };
    assert!(!tip.is_null(), "{}", last_error());
    let (coverage, piling, evening) = ([1.0, 0.5], [0.25, 0.75], vec![0.5; EVENING_ENTRIES]);
    let round = DabSpec {
        coverage: coverage.as_ptr(),
        pile: piling.as_ptr(),
        entries: 2,
        evening: evening.as_ptr(),
        ..square([0, 0, 8, 8], INK)
    };
    let specs = [tipped(tip, 8.0, [20.0, 20.0]), tipped(tip, 4.0, [40.0, 40.0]), round];
    // SAFETY: the tip is live, and each table holds its entries.
    let piled = unsafe { piled(&specs) };
    let [first, second, round] = &piled.specs[..] else { panic!("three specs") };
    let held = |at: *const Texture| piled._textures.iter().any(|kept| std::ptr::eq(&**kept, at));
    assert!(held(first.texture) && !std::ptr::eq(first.texture, tip.cast_const()), "the tip its own");
    assert!(std::ptr::eq(first.texture, second.texture), "one tip, one copy");
    // SAFETY: both are live: the app's till it is let go of below.
    assert!(unsafe { (*first.texture).words == (*tip).words }, "the copy as the app's");
    // SAFETY: each copy is held by `piled`, its entries long.
    let read = |at: *const f64, entries: usize| unsafe { std::slice::from_raw_parts(at, entries) }.to_vec();
    assert_eq!((read(round.coverage, 2), read(round.pile, 2)), (coverage.to_vec(), piling.to_vec()));
    assert_eq!(read(round.evening, EVENING_ENTRIES), evening);
    let copies = [round.coverage, round.pile, round.evening];
    let theirs = [coverage.as_ptr(), piling.as_ptr(), evening.as_ptr()];
    assert!(theirs.iter().all(|at| !copies.contains(at)), "the tables its own");
    // SAFETY: from `gpu_engine_dab_texture_new`, and nothing names it after.
    unsafe { gpu_engine_dab_texture_free(tip) };
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
        assert!(last_error().contains("a step handed over unwaited failed"), "{}", last_error());
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

// --- a blur's step and a mixing brush's ----------------------------------

/// The blurs a rub runs, on `own`'s engine.
///
/// # Safety
/// `own` came from [`open`]; let go of before its close.
unsafe fn blurs(own: &Own) -> *mut Blurs {
    // SAFETY: see the function's contract.
    let blurs = unsafe { gpu_engine_blurs_new(own.engine) };
    assert!(!blurs.is_null(), "{}", last_error());
    blurs
}

/// A tile of the cel, every pixel `pixel`: its slot's word.
///
/// # Safety
/// `own` came from [`open`].
unsafe fn stored(own: &Own, pixel: [u8; 4]) -> u32 {
    let tile = pixel.repeat(TILE_BYTES as usize / 4);
    // SAFETY: see the function's contract.
    unsafe { (&mut *own.pool).store(&*own.engine, Cel(own.cel), &[&tile]) }.expect("store")[0].word()
}

/// Rubs a blur dab over `region` at a box radius of 2 into the stroke, the
/// cel's tile told of at each tile its blur reads — `under` at (1, 0),
/// none elsewhere — as the app tells of them (`gpu_engine_rub_ground`), or
/// of none where `told` is false.
///
/// # Safety
/// `own` came from [`open`]; `blurs` from [`blurs`].
unsafe fn rub(own: &Own, blurs: *mut Blurs, region: [i32; 4], under: u32, told: bool) {
    let dab = square(region, INK);
    let radius = 2u32;
    let mut coordinates = [0i32; 2 * 16];
    // SAFETY: one dab and one radius; room for 16 tiles.
    let read = unsafe { gpu_engine_rub_ground(&dab, &radius, 1, coordinates.as_mut_ptr(), 16) };
    assert!((1..=16).contains(&read), "{}", last_error());
    let ground = if told { read as usize } else { 0 };
    let words: Vec<u32> = coordinates[..2 * ground]
        .chunks_exact(2)
        .map(|at| if at == [1, 0] { under } else { NO_TILE })
        .collect();
    // SAFETY: see the function's contract; each list holds what it says.
    unsafe {
        gpu_engine_stroke_rub(
            own.stroke,
            own.engine,
            blurs,
            own.composite,
            own.pool,
            coordinates.as_ptr(),
            words.as_ptr(),
            ground,
            &dab,
            &radius,
            1,
            std::ptr::null(),
            1.0,
            false,
        );
    }
}

/// The blur finished on the stroke's tile (0, 0) over nothing, whole, in a
/// fresh slot: handed over and told as `number` where there is one, else
/// waited for, uncompared. What it returned, and the slot's word.
///
/// # Safety
/// `own` came from [`open`]; `blurs` from [`blurs`].
unsafe fn land_blur(own: &Own, blurs: *mut Blurs, number: Option<u64>) -> (isize, u32) {
    let (asks, under) = ([0, 0], [NO_TILE]);
    let (mut places, mut changes) = ([NO_TILE], [9u8]);
    let none = std::ptr::null();
    // SAFETY: see the function's contract; each list holds one.
    let landed = unsafe {
        match number {
            Some(number) => gpu_engine_stroke_land_blur_unwaited(
                own.stroke,
                own.engine,
                blurs,
                own.composite,
                own.pool,
                own.cel,
                asks.as_ptr(),
                under.as_ptr(),
                1,
                WHOLE,
                none,
                places.as_mut_ptr(),
                changes.as_mut_ptr(),
                told,
                number,
            ),
            None => gpu_engine_stroke_land_blur(
                own.stroke,
                own.engine,
                blurs,
                own.composite,
                own.pool,
                own.cel,
                asks.as_ptr(),
                under.as_ptr(),
                1,
                WHOLE,
                none,
                false,
                places.as_mut_ptr(),
                changes.as_mut_ptr(),
            ),
        }
    };
    (landed, places[0])
}

// A blur stroke's step — its rub and its landing on its way — waits for no
// turn of the engine's thread: both return while that thread stands still;
// once it goes on, the picture is told put, the cel it was told of under
// the blur in it.
#[test]
fn a_blur_s_step_waits_for_no_turn_of_the_engine_s_thread() {
    // SAFETY: the engine is this test's own, live till its close; the
    // blurs are let go of before it.
    unsafe {
        let own = open();
        let blurs = blurs(&own);
        let ink = stored(&own, INK);
        // ⛔premise: the stroke's pages and the blurs' — the engine's
        // thread's work, which stands still below.
        rub(&own, blurs, [60, 60, 68, 68], ink, true);
        let (landed, _) = land_blur(&own, blurs, Some(801));
        assert_eq!(landed, 1, "{}", last_error());
        assert_eq!(done_here(&*own.engine), Ok(()));
        assert_eq!(was_put(801), Some(true), "⛔premise: a landing is told");
        gpu_engine_stand_still(own.engine, 2_000);
        let started = Instant::now();
        rub(&own, blurs, [124, 10, 128, 20], ink, true);
        let (landed, at) = land_blur(&own, blurs, Some(802));
        let took = started.elapsed();
        assert_eq!(landed, 1, "its slot told");
        assert_eq!(was_put(802), None, "told its slot before its picture was laid");
        assert!(took < Duration::from_millis(1_000), "the step waited {took:?} for the engine's thread");
        assert_eq!(done_here(&*own.engine), Ok(()));
        assert_eq!(was_put(802), Some(true));
        let tile = read(&own, at);
        // (127, 15) reads the ink of its six to the right — 108 of 255, as
        // the stroke's own tests work it by hand
        // (`a_rub_reads_the_cel_it_met_across_a_tile_edge`).
        assert!(pixel(&tile, 127, 15)[3].abs_diff(108) <= 1, "{:?}", pixel(&tile, 127, 15));
        assert_eq!(pixel(&tile, 123, 15), [0; 4], "LIVENESS: not rubbed there");
        gpu_engine_blurs_free(blurs);
        close(own);
    }
}

// A blur's landing on its way lays what a waited one lays: one road for
// the picture, only the wait differs.
#[test]
fn a_blur_landing_on_its_way_lays_what_a_waited_one_lays() {
    // SAFETY: as above.
    unsafe {
        let own = open();
        let blurs = blurs(&own);
        let ink = stored(&own, INK);
        rub(&own, blurs, [124, 10, 128, 20], ink, true);
        let (waited_landed, waited) = land_blur(&own, blurs, None);
        let (landed, on_its_way) = land_blur(&own, blurs, Some(811));
        assert_eq!((waited_landed, landed), (1, 1), "{}", last_error());
        assert_eq!(done_here(&*own.engine), Ok(()));
        assert_eq!(was_put(811), Some(true));
        let (waited, on_its_way) = (read(&own, waited), read(&own, on_its_way));
        assert!(on_its_way == waited, "one picture, waited or not");
        assert_ne!(pixel(&waited, 127, 15)[3], 0, "LIVENESS: the ink blurred in");
        gpu_engine_blurs_free(blurs);
        close(own);
    }
}

// 🚨A rub that met a tile it was told nothing of is refused as a pile is
// (`Stroke::refuse`): the caller's next done is not broken by it; the
// stroke's next landing on its way is told not put, and a waited one
// fails with the rub's reason.
#[test]
fn a_rub_refused_is_told_by_what_reads_the_stroke_next() {
    // SAFETY: as above.
    unsafe {
        let own = open();
        let blurs = blurs(&own);
        rub(&own, blurs, [60, 60, 68, 68], NO_TILE, false);
        assert_eq!(done_here(&*own.engine), Ok(()), "a rub refused leaves the done alone");
        let (landed, _) = land_blur(&own, blurs, Some(821));
        assert_eq!(landed, 1, "its slot told: the books are the caller's");
        assert!(done_here(&*own.engine).is_err(), "the landing not put is told by the next done");
        assert_eq!(was_put(821), Some(false));
        let (landed, _) = land_blur(&own, blurs, None);
        assert_eq!(landed, -1);
        assert!(last_error().contains("told nothing of"), "{}", last_error());
        gpu_engine_blurs_free(blurs);
        close(own);
    }
}

/// A loaded brush's step at `centre`, of `radius`, drawing `colour`: the
/// pickup, refill and laid share of the app's fit (the mixing tests'
/// `loaded`).
fn loaded(centre: [f64; 2], radius: f64, colour: [u8; 4]) -> StepSpec {
    StepSpec {
        centre,
        radius,
        refill: 0.12,
        laid: 0.3,
        density: 1.0,
        take: 0.0,
        share: 1.0,
        pick: 0.12,
        colour: u32::from_le_bytes(colour),
        dry: 0,
    }
}

/// Piles a mixing brush's `steps`, from `first`, with no dab, the cel's
/// tile told of at each ground tile they read — `under` at (0, 0), none
/// elsewhere — as the app tells of them (`gpu_engine_mix_ground`), or of
/// none where `told` is false.
///
/// # Safety
/// `own` came from [`open`].
unsafe fn pile_steps(own: &Own, steps: &[StepSpec], first: u32, under: u32, told: bool) {
    let mut coordinates = vec![0i32; 128 * steps.len()];
    // SAFETY: room for 64 tiles a step.
    let read = unsafe { gpu_engine_mix_ground(steps.as_ptr(), steps.len(), coordinates.as_mut_ptr()) };
    let ground = if told { read } else { 0 };
    let words: Vec<u32> = coordinates[..2 * ground]
        .chunks_exact(2)
        .map(|at| if at == [0, 0] { under } else { NO_TILE })
        .collect();
    // No dabs, as the host hands none: a list, never a null.
    let dabs: Vec<DabSpec> = Vec::new();
    // SAFETY: see the function's contract; each list holds what it says.
    unsafe {
        gpu_engine_stroke_pile(
            own.stroke,
            own.engine,
            dabs.as_ptr(),
            0,
            std::ptr::null(),
            1.0,
            false,
            -1,
            1.0,
            steps.as_ptr(),
            steps.len(),
            first,
            own.composite,
            own.pool,
            coordinates.as_ptr(),
            words.as_ptr(),
            ground,
        );
    }
}

/// The colour each of the stroke's first `count` steps laid, ARGB, or
/// none: the reason is the last error.
///
/// # Safety
/// `own` came from [`open`].
unsafe fn mixed(own: &Own, count: usize) -> Option<Vec<u32>> {
    let mut out = vec![0u32; count];
    // SAFETY: `out` holds `count`.
    unsafe { gpu_engine_stroke_mixed(own.stroke, own.engine, out.as_mut_ptr(), count) }.then_some(out)
}

// A mixing brush's step waits for no turn of the engine's thread: the pile
// that runs it returns while that thread stands still — and once it goes
// on, the step has read the cel it was told of under it.
#[test]
fn a_mixing_step_waits_for_no_turn_and_reads_the_cel_it_is_told_of() {
    const BLUE: [u8; 4] = [0, 0, 255, 255];
    // SAFETY: the engine is this test's own, live till its close.
    unsafe {
        let own = open();
        let under = stored(&own, UNDER);
        // ⛔premise: the mixing book — the engine's thread's work.
        pile_steps(&own, &[loaded([64.0, 64.0], 10.0, BLUE)], 0, under, true);
        assert_eq!(done_here(&*own.engine), Ok(()));
        gpu_engine_stand_still(own.engine, 2_000);
        let started = Instant::now();
        pile_steps(&own, &[loaded([64.0, 64.0], 10.0, BLUE)], 1, under, true);
        let took = started.elapsed();
        assert!(took < Duration::from_millis(1_000), "the step waited {took:?} for the engine's thread");
        let colours = mixed(&own, 2).unwrap_or_else(|| panic!("{}", last_error()));
        let green = |argb: u32| argb.to_be_bytes()[2];
        assert!(green(colours[1]) > 0, "it lifted the cel's green: {:08x}", colours[1]);
        gpu_engine_stroke_clear(own.stroke, own.engine);
        pile_steps(&own, &[loaded([64.0, 64.0], 10.0, BLUE)], 0, NO_TILE, true);
        let bare = mixed(&own, 1).unwrap_or_else(|| panic!("{}", last_error()));
        assert_eq!(green(bare[0]), 0, "LIVENESS: over no cel it lifts no green");
        close(own);
    }
}

// 🚨A mixing step that read a tile it was told nothing of is refused as a
// pile is: what reads the stroke next fails by it.
#[test]
fn a_mixing_step_told_nothing_of_its_ground_is_refused() {
    // SAFETY: the engine is this test's own, live till its close.
    unsafe {
        let own = open();
        pile_steps(&own, &[loaded([64.0, 64.0], 10.0, INK)], 0, NO_TILE, false);
        assert_eq!(done_here(&*own.engine), Ok(()), "a pile refused leaves the done alone");
        assert!(mixed(&own, 1).is_none());
        assert!(last_error().contains("told nothing of"), "{}", last_error());
        close(own);
    }
}

// The cel's tile a mixing step or a rub is told of is read where it lies
// (`told_of`): folded since it was stored, its slot scrubbed — nobody's
// to read —, each reads what it read of the tile as it was.
// 🗣️관제 2026-11-19 (F-610), of these two doors, which a scan of the source
// alone pinned till here: 「D4 실기에서 그 둘의 동작 핀을 꼭 더할 것」.
#[test]
fn a_mixing_step_and_a_rub_read_a_tile_that_lies_folded_as_it_was() {
    use crate::kernels::composite::TileAt;
    use crate::kernels::fold::{gpu_engine_fold_free, gpu_engine_fold_new};
    use crate::kernels::pool::folded_tests::{numbered, scrubbed, told as fold_told, told_within};
    use crate::kernels::pool::gpu_engine_pool_settle;
    const BLUE: [u8; 4] = [0, 0, 255, 255];
    let step = [loaded([64.0, 64.0], 10.0, BLUE)];
    // SAFETY: the engine is this test's own, live till its close; the
    // blurs and the fold's kernels are let go of before it.
    unsafe {
        let own = open();
        let blurs = blurs(&own);
        let (under, ink) = (stored(&own, UNDER), stored(&own, INK));
        // What two mixing steps lift of the cel under them, and what a rub
        // blurs in of the tile beside its own.
        let lifted = |own: &Own| {
            gpu_engine_stroke_clear(own.stroke, own.engine);
            pile_steps(own, &step, 0, under, true);
            pile_steps(own, &step, 1, under, true);
            mixed(own, 2).unwrap_or_else(|| panic!("{}", last_error()))
        };
        let rubbed = |own: &Own| {
            gpu_engine_stroke_clear(own.stroke, own.engine);
            rub(own, blurs, [124, 10, 128, 20], ink, true);
            let (landed, at) = land_blur(own, blurs, None);
            assert_eq!(landed, 1, "{}", last_error());
            read(own, at)
        };
        let as_they_were = (lifted(&own), rubbed(&own));
        let green = |argb: u32| argb.to_be_bytes()[2];
        assert!(green(as_they_were.0[1]) > 0, "LIVENESS: a step lifts the cel's green");
        assert_ne!(pixel(&as_they_were.1, 127, 15)[3], 0, "LIVENESS: the ink blurs in");

        let fold = gpu_engine_fold_new(own.engine);
        assert!(!fold.is_null(), "{}", last_error());
        // Named to the fold: their page has slots free — the pool's room,
        // whose tiles the pool hands none itself.
        let names = [under, ink].map(|word| TileAt::of_word(word).expect("a tile's name"));
        let number = numbered();
        assert_eq!((*own.pool).folds_unwaited(&*own.engine, fold, &names, crate::kernels::pool::told_by(fold_told, number)), 2);
        assert_eq!(told_within(number, Duration::from_secs(120)), Some(true));
        gpu_engine_pool_settle(own.pool, own.engine);
        assert!(names.iter().all(|&at| (*own.pool).lies(at).folded().is_some()), "⛔premise: both lie folded");
        scrubbed(&*own.engine, &*own.pool, &names);

        let folded = (lifted(&own), rubbed(&own));
        assert!(folded.0 == as_they_were.0, "a mixing step read its tile's name, not where it lies");
        assert!(folded.1 == as_they_were.1, "a rub read its tile's name, not where it lies");
        gpu_engine_fold_free(fold);
        gpu_engine_blurs_free(blurs);
        close(own);
    }
}
