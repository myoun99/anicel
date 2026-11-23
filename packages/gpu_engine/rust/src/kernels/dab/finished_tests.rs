//! A stamp's landing and a lift asked with no wait (card
//! opening-a-transform-box-holds-the-ui-over-half-a-second): the finish
//! ([`gpu_engine_stamp_finish_unwaited`], its mask's), the landing of what
//! it finished ([`gpu_engine_finished_land_unwaited`]) and the lift
//! (`gpu_engine_cel_pixels_lift_picture_unwaited`) through the C ABI, each
//! beside the waited verb it is the unwaited road of — on a device of the
//! test's own, whose thread a test can make stand still. And what a
//! stroke's tiles put already are told to be
//! ([`gpu_engine_stroke_tiles_told_unwaited`]): the answer a compared
//! landing waits for, with no wait.

use std::time::{Duration, Instant};

use super::{
    Finished, StampLanding, StampPicture, Stroke, gpu_engine_finished_changes, gpu_engine_finished_free,
    gpu_engine_finished_land_unwaited, gpu_engine_stamp_finish_mask_unwaited, gpu_engine_stamp_finish_unwaited,
    gpu_engine_stamp_land, gpu_engine_stamp_land_mask, gpu_engine_stamp_landing_free,
    gpu_engine_stamp_landing_new, gpu_engine_stamp_picture_free, gpu_engine_stamp_picture_new,
    gpu_engine_stamp_picture_read, gpu_engine_stroke_free, gpu_engine_stroke_new,
    gpu_engine_stroke_tiles_told_unwaited,
};
use crate::device::{Engine, gpu_engine_close, gpu_engine_open_first, gpu_engine_stand_still};
use crate::kernels::blend::mode::{ERASE, NORMAL};
use crate::kernels::cel_pixel::abi::{
    CelKernels, gpu_engine_cel_pixels_free, gpu_engine_cel_pixels_lift_picture,
    gpu_engine_cel_pixels_lift_picture_unwaited, gpu_engine_cel_pixels_new,
};
use crate::kernels::composite::abi::{
    MaskPlane, gpu_engine_composite_free, gpu_engine_composite_new, gpu_engine_mask_free,
    gpu_engine_mask_new,
};
use crate::kernels::composite::{Composite, NO_TILE, TILE_BYTES, TileAt};
use crate::kernels::composite::tests::rig;
use crate::kernels::pool::folded_tests::{numbered, settled, tile, told, told_within};
use crate::kernels::pool::{
    Cel, Pool, gpu_engine_pool_cel, gpu_engine_pool_free, gpu_engine_pool_new, gpu_engine_pool_read,
    gpu_engine_pool_store,
};
use crate::testing::{DeviceTurn, a_device_of_its_own, done_here, last_error};

const WHOLE: u32 = 65535;
const INK: [u8; 4] = [200, 100, 50, 255];
const UNDER: [u8; 4] = [10, 220, 90, 255];
const OTHER: [u8; 4] = [90, 10, 220, 255];
/// A tile's side.
const SIDE: u32 = 128;
/// As long as a telling is waited for before its test fails.
const LONG: Duration = Duration::from_secs(120);

/// An engine of the test's own, under the tests' turn for one, and what a
/// stamp lands with on it.
struct Own {
    engine: *mut Engine,
    composite: *mut Composite,
    pool: *mut Pool,
    cel: u32,
    landing: *mut StampLanding,
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
        let landing = gpu_engine_stamp_landing_new(engine);
        assert!(!landing.is_null(), "{}", last_error());
        Own { engine, composite, pool, cel, landing, _turn: turn }
    }
}

/// # Safety
/// `own` came from [`open`], and nothing names what it holds.
unsafe fn close(own: Own) {
    // SAFETY: see the function's contract.
    unsafe {
        gpu_engine_stamp_landing_free(own.landing);
        gpu_engine_pool_free(own.pool);
        gpu_engine_composite_free(own.composite);
        gpu_engine_close(own.engine);
    }
}

/// A tile of `colour` stored for the cel: its word.
///
/// # Safety
/// `own` came from [`open`].
unsafe fn stored(own: &Own, colour: [u8; 4]) -> u32 {
    let tile = colour.repeat(TILE_BYTES as usize / 4);
    // SAFETY: see the function's contract.
    let (pool, engine) = unsafe { (&mut *own.pool, &*own.engine) };
    pool.store(engine, Cel(own.cel), &[&tile]).expect("store")[0].word()
}

/// A picture of `width` × `height` pixels of `colour`.
///
/// # Safety
/// `own` came from [`open`].
unsafe fn picture(own: &Own, colour: [u8; 4], width: u32, height: u32) -> *mut StampPicture {
    let rgba = colour.repeat((width * height) as usize);
    // SAFETY: see the function's contract; `rgba` holds the picture.
    let picture = unsafe { gpu_engine_stamp_picture_new(own.engine, rgba.as_ptr(), width, height) };
    assert!(!picture.is_null(), "{}", last_error());
    picture
}

/// A mask of `width` × `height` pixels, each covered whole, from (`x`, `y`).
///
/// # Safety
/// `own` came from [`open`].
unsafe fn covering(own: &Own, [x, y]: [i32; 2], width: u32, height: u32) -> *mut MaskPlane {
    let bytes = vec![255u8; (width * height) as usize];
    // SAFETY: see the function's contract; `bytes` holds the mask.
    let mask = unsafe { gpu_engine_mask_new(own.engine, bytes.as_ptr(), x, y, width, height) };
    assert!(!mask.is_null(), "{}", last_error());
    mask
}

/// The tiles (0, 0), (1, 0), … a stamp is asked of — as many as it is
/// handed tiles to lie over — and the canvas they are of.
fn asked(count: usize) -> (Vec<i32>, [i32; 4]) {
    let asks = (0..count as i32).flat_map(|x| [x, 0]).collect();
    (asks, [0, 0, SIDE as i32 * count as i32, SIDE as i32])
}

/// `picture` laid from the canvas's top-left, whole and in normal, on the
/// tiles over `under`, waited for ([`gpu_engine_stamp_land`]): each
/// tile's place and what it is.
///
/// # Safety
/// `own` came from [`open`]; `picture` is live on its engine.
unsafe fn landed(own: &Own, picture: *const StampPicture, under: &[u32]) -> (Vec<u32>, Vec<u8>) {
    let (asks, within) = asked(under.len());
    let (mut places, mut changes) = (vec![NO_TILE; under.len()], vec![9u8; under.len()]);
    // SAFETY: see the function's contract; each list holds a tile's each.
    let count = unsafe {
        gpu_engine_stamp_land(
            own.landing,
            own.engine,
            own.composite,
            own.pool,
            own.cel,
            picture,
            0,
            0,
            within.as_ptr(),
            asks.as_ptr(),
            under.as_ptr(),
            under.len(),
            WHOLE,
            NORMAL,
            std::ptr::null(),
            places.as_mut_ptr(),
            changes.as_mut_ptr(),
        )
    };
    assert_eq!(count, under.len() as isize, "{}", last_error());
    (places, changes)
}

/// Where a telling writes what it made: live till it is told, and unlike
/// a null till it is written.
fn out_of<T>() -> Box<*mut T> {
    Box::new(std::ptr::NonNull::dangling().as_ptr())
}

/// [`landed`]'s asking with no wait ([`gpu_engine_stamp_finish_unwaited`]),
/// told by `number`: where its landing finished is written.
///
/// # Safety
/// As [`landed`]'s.
unsafe fn finish(own: &Own, picture: *const StampPicture, under: &[u32], number: u64) -> Box<*mut Finished> {
    let (asks, within) = asked(under.len());
    let mut out = out_of();
    // SAFETY: see the function's contract; `out` is live till it is told.
    unsafe {
        gpu_engine_stamp_finish_unwaited(
            own.landing,
            own.engine,
            own.composite,
            own.pool,
            picture,
            0,
            0,
            within.as_ptr(),
            asks.as_ptr(),
            under.as_ptr(),
            under.len(),
            WHOLE,
            NORMAL,
            std::ptr::null(),
            &mut *out,
            told,
            number,
        );
    }
    out
}

/// [`finish`] told, and what it finished.
///
/// # Safety
/// As [`landed`]'s.
unsafe fn finished(own: &Own, picture: *const StampPicture, under: &[u32]) -> *mut Finished {
    let number = numbered();
    // SAFETY: see the function's contract.
    let out = unsafe { finish(own, picture, under, number) };
    assert_eq!(told_within(number, LONG), Some(true), "{}", last_error());
    assert!(!out.is_null(), "told finished, and none written");
    *out
}

/// What `finished` says each tile it was asked is.
///
/// # Safety
/// `finished` is live.
unsafe fn changes_of(finished: *const Finished) -> Vec<u8> {
    // SAFETY: see the function's contract; a null holds none.
    let count = unsafe { gpu_engine_finished_changes(finished, std::ptr::null_mut()) };
    let mut changes = vec![9u8; count];
    // SAFETY: see the function's contract; `changes` holds one each.
    assert_eq!(unsafe { gpu_engine_finished_changes(finished, changes.as_mut_ptr()) }, count);
    changes
}

/// The inked of `finished` from its `first` on given their slots
/// ([`gpu_engine_finished_land_unwaited`]), told by `number`: the places
/// given — `room` of them at most.
///
/// # Safety
/// `own` came from [`open`]; `finished` is live, with no more than `room`
/// inked past `first`.
unsafe fn land(own: &Own, finished: *const Finished, first: usize, room: usize, number: u64) -> Vec<u32> {
    let mut places = vec![NO_TILE; room];
    // SAFETY: see the function's contract.
    let given = unsafe {
        gpu_engine_finished_land_unwaited(
            finished,
            own.engine,
            own.pool,
            own.cel,
            first,
            places.as_mut_ptr(),
            told,
            number,
        )
    };
    places.truncate(given);
    places
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
    bytes[(y * SIDE as usize + x) * 4..][..4].try_into().unwrap()
}

// A finish says of each tile what a waited landing says, and what it
// finished lands the bytes a waited landing lands — the inked alone in a
// slot: one road for the picture, only the wait differs.
#[test]
fn a_finish_says_what_a_waited_landing_says_and_lands_the_bytes_it_lands() {
    // SAFETY: the engine is this test's own, live till its close; the
    // picture and what was finished are let go of after the last use.
    unsafe {
        let own = open();
        let under = [stored(&own, UNDER), stored(&own, OTHER), NO_TILE];
        // Over the left half of the first tile: that one inked, the second
        // and a third no tile lies on as they were.
        let half = picture(&own, INK, SIDE / 2, SIDE);
        let (places, changes) = landed(&own, half, &under);
        assert_eq!(changes, [1, 0, 0], "⛔premise: inked, the same, the same");
        let told_of = finished(&own, half, &under);
        assert_eq!(changes_of(told_of), changes);
        let put = numbered();
        let given = land(&own, told_of, 0, under.len(), put);
        assert_eq!(given.len(), 1, "the inked alone takes a slot");
        assert_eq!(told_within(put, LONG), Some(true), "{}", last_error());
        let (waited, unwaited) = (read(&own, places[0]), read(&own, given[0]));
        assert_eq!((pixel(&unwaited, 10, 10), pixel(&unwaited, 100, 10)), (INK, UNDER), "the picture over the cel's");
        assert!(waited == unwaited, "the bytes a waited landing lands");
        gpu_engine_finished_free(told_of);
        gpu_engine_stamp_picture_free(half);
        close(own);
    }
}

// A finish and the landing of what one finished wait for no turn of the
// engine's thread: both return while it stands still, neither told; once
// it goes on, both are.
#[test]
fn a_finish_and_its_landing_wait_for_no_turn_of_the_engine_s_thread() {
    // SAFETY: as the first test's.
    unsafe {
        let own = open();
        let under = [stored(&own, UNDER)];
        let ink = picture(&own, INK, SIDE / 2, SIDE / 2);
        // ⛔premise: the kernels' passes compiled and the pool's page made
        // — the engine's thread's work, which stands still below.
        let first = finished(&own, ink, &under);
        gpu_engine_stand_still(own.engine, 2_000);
        let started = Instant::now();
        let (second, put) = (numbered(), numbered());
        let out = finish(&own, ink, &under, second);
        let given = land(&own, first, 0, 1, put);
        let took = started.elapsed();
        assert_eq!(given.len(), 1, "its slot told");
        assert!(took < Duration::from_millis(1_000), "waited {took:?} for the engine's thread");
        let told_yet = (told_within(second, Duration::ZERO), told_within(put, Duration::ZERO));
        assert_eq!(told_yet, (None, None), "neither told while the thread stands");
        assert_eq!((told_within(second, LONG), told_within(put, LONG)), (Some(true), Some(true)));
        assert_eq!(pixel(&read(&own, given[0]), 10, 10), INK);
        gpu_engine_finished_free(*out);
        gpu_engine_finished_free(first);
        gpu_engine_stamp_picture_free(ink);
        close(own);
    }
}

// What was finished is let go of with no turn of the engine's thread
// waited for, right behind the put it handed over — which lands its bytes
// all the same: the put holds the tiles made as its own.
#[test]
fn what_was_finished_is_let_go_of_behind_its_put_with_no_wait() {
    // SAFETY: as the first test's.
    unsafe {
        let own = open();
        let under = [stored(&own, UNDER)];
        let ink = picture(&own, INK, SIDE / 2, SIDE / 2);
        let first = finished(&own, ink, &under);
        gpu_engine_stand_still(own.engine, 2_000);
        let (started, put) = (Instant::now(), numbered());
        let given = land(&own, first, 0, 1, put);
        gpu_engine_finished_free(first);
        let took = started.elapsed();
        assert!(took < Duration::from_millis(1_000), "waited {took:?} for the engine's thread");
        assert_eq!(told_within(put, Duration::ZERO), None, "⛔premise: freed before its put was made");
        assert_eq!(told_within(put, LONG), Some(true), "{}", last_error());
        assert_eq!(pixel(&read(&own, given[0]), 10, 10), INK, "what was finished, put");
        gpu_engine_stamp_picture_free(ink);
        close(own);
    }
}

// A finish reads the cel as it stood where it was asked: the tile under
// it let go and its slot handed out again behind the asking, the finish
// lays its picture over the tile that was.
#[test]
fn a_finish_reads_the_cel_as_it_stood_where_it_was_asked() {
    // SAFETY: as the first test's.
    unsafe {
        let own = open();
        let was = stored(&own, UNDER);
        let half = picture(&own, INK, SIDE / 2, SIDE);
        gpu_engine_finished_free(finished(&own, half, &[was]));
        gpu_engine_stand_still(own.engine, 500);
        let number = numbered();
        let out = finish(&own, half, &[was], number);
        (&mut *own.pool).release(TileAt::of_word(was).expect("a slot's word")).expect("release");
        assert_eq!(stored(&own, OTHER), was, "⛔premise: its slot handed out again, to another tile");
        assert_eq!(told_within(number, LONG), Some(true), "{}", last_error());
        let put = numbered();
        let given = land(&own, *out, 0, 1, put);
        assert_eq!(told_within(put, LONG), Some(true), "{}", last_error());
        let landed = read(&own, given[0]);
        assert_eq!((pixel(&landed, 10, 10), pixel(&landed, 100, 10)), (INK, UNDER), "over the tile that was");
        gpu_engine_finished_free(*out);
        gpu_engine_stamp_picture_free(half);
        close(own);
    }
}

// What a finish finished lands from its `first` inked on — a landing the
// pool was full for goes on from where it ended —, and past its last
// gives none and tells nothing.
#[test]
fn what_was_finished_lands_from_its_first_inked_on() {
    // SAFETY: as the first test's.
    unsafe {
        let own = open();
        // The first tile whole and half the second: two inked, unlike, and
        // a third as it was.
        let wide = picture(&own, INK, SIDE + SIDE / 2, SIDE);
        let told_of = finished(&own, wide, &[NO_TILE; 3]);
        assert_eq!(changes_of(told_of), [1, 1, 0], "⛔premise");
        let (all, rest) = (numbered(), numbered());
        let both = land(&own, told_of, 0, 2, all);
        let second = land(&own, told_of, 1, 2, rest);
        assert_eq!((both.len(), second.len()), (2, 1));
        assert_eq!((told_within(all, LONG), told_within(rest, LONG)), (Some(true), Some(true)));
        assert_ne!(second[0], both[1], "in a slot of its own");
        let (whole, half) = (read(&own, both[0]), read(&own, second[0]));
        assert_eq!((pixel(&whole, 100, 10), pixel(&half, 100, 10)[3]), (INK, 0), "⛔premise: the two unlike");
        assert!(half == read(&own, both[1]), "the second inked");
        let none = numbered();
        assert!(land(&own, told_of, 2, 2, none).is_empty(), "none inked past the second");
        assert_eq!(done_here(&*own.engine), Ok(()));
        assert_eq!(told_within(none, Duration::ZERO), None, "and nothing told");
        gpu_engine_finished_free(told_of);
        gpu_engine_stamp_picture_free(wide);
        close(own);
    }
}

// A finish of no tile is told false, and null written: there is nothing
// to land. A mask's under a paint the host knows none of is not asked at
// all.
#[test]
fn a_finish_of_nothing_is_told_false_and_hands_nothing() {
    // SAFETY: as the first test's; the mask is let go of after its use.
    unsafe {
        let own = open();
        let ink = picture(&own, INK, SIDE, SIDE);
        let number = numbered();
        let out = finish(&own, ink, &[], number);
        assert_eq!(told_within(number, LONG), Some(false));
        assert!(out.is_null(), "null written where nothing finished");
        let cover = covering(&own, [0, 0], SIDE, SIDE);
        let (asks, _) = asked(1);
        let (mut out, unknown, number) = (out_of::<Finished>(), [7.0, 0.0], numbered());
        let was_asked = gpu_engine_stamp_finish_mask_unwaited(
            own.landing,
            own.engine,
            own.composite,
            own.pool,
            cover,
            unknown.as_ptr(),
            true,
            asks.as_ptr(),
            [NO_TILE].as_ptr(),
            1,
            WHOLE,
            NORMAL,
            std::ptr::null(),
            &mut *out,
            told,
            number,
        );
        assert!(!was_asked, "a paint of no tag the host knows");
        assert_eq!(done_here(&*own.engine), Ok(()));
        assert_eq!(told_within(number, Duration::ZERO), None, "not handed over, and not told");
        gpu_engine_mask_free(cover);
        gpu_engine_stamp_picture_free(ink);
        close(own);
    }
}

// A mask's finish says what its waited landing says — a selection's own
// mask laid by the eraser clears the tile it covers whole, and laid in a
// colour inks it with the bytes the waited landing lands.
#[test]
fn a_mask_s_finish_says_what_its_waited_landing_says() {
    // SAFETY: as the first test's; the mask is let go of after its use.
    unsafe {
        let own = open();
        let under = [stored(&own, UNDER), stored(&own, OTHER)];
        let cover = covering(&own, [0, 0], SIDE, SIDE);
        let (asks, _) = asked(under.len());
        // A colour: its tag, and the pixel's word.
        let paint = [0.0, f64::from(u32::from_le_bytes(INK))];
        for (mode, says) in [(ERASE, [2u8, 0]), (NORMAL, [1, 0])] {
            let (mut places, mut changes) = ([NO_TILE; 2], [9u8; 2]);
            let count = gpu_engine_stamp_land_mask(
                own.landing,
                own.engine,
                own.composite,
                own.pool,
                own.cel,
                cover,
                paint.as_ptr(),
                true,
                asks.as_ptr(),
                under.as_ptr(),
                under.len(),
                WHOLE,
                mode,
                std::ptr::null(),
                places.as_mut_ptr(),
                changes.as_mut_ptr(),
            );
            assert_eq!((count, changes), (2, says), "⛔premise, mode {mode}: {}", last_error());
            let (mut out, number) = (out_of::<Finished>(), numbered());
            let was_asked = gpu_engine_stamp_finish_mask_unwaited(
                own.landing,
                own.engine,
                own.composite,
                own.pool,
                cover,
                paint.as_ptr(),
                true,
                asks.as_ptr(),
                under.as_ptr(),
                under.len(),
                WHOLE,
                mode,
                std::ptr::null(),
                &mut *out,
                told,
                number,
            );
            assert!(was_asked, "{}", last_error());
            assert_eq!(told_within(number, LONG), Some(true), "{}", last_error());
            assert_eq!(changes_of(*out), says, "mode {mode}");
            let put = numbered();
            let given = land(&own, *out, 0, 2, put);
            if mode == NORMAL {
                assert_eq!(told_within(put, LONG), Some(true), "{}", last_error());
                assert!(read(&own, given[0]) == read(&own, places[0]), "the bytes its waited landing lands");
            } else {
                assert!(given.is_empty(), "a tile cleared takes no slot");
            }
            gpu_engine_finished_free(*out);
        }
        gpu_engine_mask_free(cover);
        close(own);
    }
}

/// What a lift took, read back: the picture's pixels, a mask's box of
/// `width` × `height`.
///
/// # Safety
/// `own` came from [`open`]; `picture` is live, of that box.
unsafe fn lifted_pixels(own: &Own, picture: *const StampPicture, width: u32, height: u32) -> Vec<u8> {
    let mut rgba = vec![0u8; (width * height * 4) as usize];
    // SAFETY: see the function's contract.
    let read = unsafe { gpu_engine_stamp_picture_read(own.engine, picture, rgba.as_mut_ptr()) };
    assert!(read, "{}", last_error());
    rgba
}

/// A lift of the one tile `tiles` names under `mask`, asked with no wait
/// and told by `number`: where its picture is written.
///
/// # Safety
/// `own` came from [`open`]; `kernels` and `mask` are live on its engine.
unsafe fn lift(
    own: &Own,
    kernels: *const CelKernels,
    tiles: &[u32; 1],
    mask: *const MaskPlane,
    number: u64,
) -> Box<*mut StampPicture> {
    let mut out = out_of();
    // SAFETY: see the function's contract; `out` is live till it is told.
    unsafe {
        gpu_engine_cel_pixels_lift_picture_unwaited(
            kernels,
            own.engine,
            own.pool,
            0,
            0,
            1,
            1,
            tiles.as_ptr(),
            mask,
            true,
            &mut *out,
            told,
            number,
        );
    }
    out
}

// A lift asked with no wait takes what a waited one takes — the picture
// of the mask's box —, takes nothing where the mask covers no ink, told
// it ran, and waits for no turn of the engine's thread.
#[test]
fn a_lift_asked_with_no_wait_takes_what_a_waited_one_takes() {
    // SAFETY: as the first test's; the kernels, the mask and each picture
    // are let go of after their last use.
    unsafe {
        let own = open();
        let kernels = gpu_engine_cel_pixels_new(own.engine);
        assert!(!kernels.is_null(), "{}", last_error());
        let (tiles, box_of) = ([stored(&own, UNDER)], (64, 32));
        let mask = covering(&own, [16, 8], box_of.0, box_of.1);
        let mut waited: *mut StampPicture = std::ptr::null_mut();
        let took = gpu_engine_cel_pixels_lift_picture(
            kernels, own.engine, own.pool, 0, 0, 1, 1, tiles.as_ptr(), mask, true, &mut waited,
        );
        assert_eq!(took, 1, "{}", last_error());
        let number = numbered();
        let out = lift(&own, kernels, &tiles, mask, number);
        assert_eq!(told_within(number, LONG), Some(true), "{}", last_error());
        assert!(!out.is_null(), "it took the mask's box");
        let (theirs, ours) = (
            lifted_pixels(&own, waited, box_of.0, box_of.1),
            lifted_pixels(&own, *out, box_of.0, box_of.1),
        );
        assert_eq!(ours[..4], UNDER, "the cel's pixels");
        assert!(theirs == ours, "the picture a waited lift takes");
        // No tile under the mask: nothing taken, and told it ran.
        let (none, number) = ([NO_TILE], numbered());
        let nothing = lift(&own, kernels, &none, mask, number);
        assert_eq!(told_within(number, LONG), Some(true), "{}", last_error());
        assert!(nothing.is_null(), "null written where it took nothing");
        // And no turn of the engine's thread waited for.
        gpu_engine_stand_still(own.engine, 2_000);
        let (started, number) = (Instant::now(), numbered());
        let standing = lift(&own, kernels, &tiles, mask, number);
        let took = started.elapsed();
        assert!(took < Duration::from_millis(1_000), "waited {took:?} for the engine's thread");
        assert_eq!(told_within(number, Duration::ZERO), None, "not told while the thread stands");
        assert_eq!(told_within(number, LONG), Some(true), "{}", last_error());
        for picture in [waited, *out, *standing] {
            gpu_engine_stamp_picture_free(picture);
        }
        gpu_engine_mask_free(mask);
        gpu_engine_cel_pixels_free(kernels);
        close(own);
    }
}

/// What a stroke's tiles `tiles` — each over the cel's `under` — are
/// told to be with no wait ([`gpu_engine_stroke_tiles_told_unwaited`]),
/// told by `number`: where what it finished is written.
///
/// # Safety
/// `engine`, `pool` and `stroke` are live, on one engine; `tiles` and
/// `under` hold one each.
unsafe fn tell(
    (engine, pool, stroke): (*const Engine, *const Pool, *const Stroke),
    tiles: &[u32],
    under: &[u32],
    number: u64,
) -> Box<*mut Finished> {
    let (asks, _) = asked(under.len());
    let mut out = out_of();
    // SAFETY: see the function's contract; `out` is live till it is told.
    unsafe {
        gpu_engine_stroke_tiles_told_unwaited(
            stroke,
            engine,
            pool,
            tiles.as_ptr(),
            asks.as_ptr(),
            under.as_ptr(),
            tiles.len(),
            &mut *out,
            told,
            number,
        );
    }
    out
}

/// [`tell`] on [`open`]'s engine, waited for till it is told: what each
/// tile is ([`changes_of`]), what was finished let go of.
///
/// # Safety
/// As [`tell`]'s.
unsafe fn told_of(own: &Own, stroke: *const Stroke, tiles: &[u32], under: &[u32]) -> Vec<u8> {
    let number = numbered();
    // SAFETY: see the function's contract.
    let out = unsafe { tell((own.engine, own.pool, stroke), tiles, under, number) };
    assert_eq!(told_within(number, LONG), Some(true), "{}", last_error());
    assert!(!out.is_null(), "told finished, and none written");
    // SAFETY: what was finished is live till here.
    unsafe {
        let changes = changes_of(*out);
        gpu_engine_finished_free(*out);
        changes
    }
}

/// A stroke made on [`open`]'s engine.
///
/// # Safety
/// `own` came from [`open`].
unsafe fn a_stroke(own: &Own) -> *mut Stroke {
    // SAFETY: see the function's contract.
    let stroke = unsafe { gpu_engine_stroke_new(own.engine) };
    assert!(!stroke.is_null(), "{}", last_error());
    stroke
}

// A stroke's tiles put already are told what a compared landing tells of
// the tiles it makes: the same as the tile under it — or as nothing,
// where none is under it —, unlike it with ink, unlike it with none.
#[test]
fn a_stroke_s_tiles_are_told_what_a_compared_landing_says_of_its_own() {
    // SAFETY: as the first test's; the stroke is let go of after its use.
    unsafe {
        let own = open();
        let stroke = a_stroke(&own);
        let clear = [0u8; 4];
        let under = [stored(&own, UNDER), stored(&own, OTHER), stored(&own, UNDER), NO_TILE, NO_TILE];
        let tiles = [stored(&own, UNDER), stored(&own, INK), stored(&own, clear), stored(&own, clear), stored(&own, INK)];
        assert_ne!(tiles[0], under[0], "⛔premise: a tile of its own, of the same bytes");
        assert_eq!(told_of(&own, stroke, &tiles, &under), [0, 1, 2, 0, 1], "same, inked, cleared, same, inked");
        gpu_engine_stroke_free(stroke);
        close(own);
    }
}

// The telling waits for no turn of the engine's thread, and reads a tile
// behind every put handed over before it: one stored with no wait just
// before it was asked is told as its bytes, not as the slot's nothing.
#[test]
fn a_stroke_s_tiles_are_told_with_no_wait_and_behind_the_puts_before() {
    // SAFETY: as the first test's; the stroke is let go of after its use,
    // the tile's bytes after its store is told.
    unsafe {
        let own = open();
        let stroke = a_stroke(&own);
        // ⛔premise: the kernels' passes compiled and the pool's page made
        // — the engine's thread's work, which stands still below.
        assert_eq!(told_of(&own, stroke, &[stored(&own, INK)], &[NO_TILE]), [1]);
        gpu_engine_stand_still(own.engine, 2_000);
        let started = Instant::now();
        let bytes = INK.repeat(TILE_BYTES as usize / 4);
        let (tiles, mut page, mut slot, put) = ([bytes.as_ptr()], 0u16, 0u16, numbered());
        let given = gpu_engine_pool_store(own.pool, own.engine, own.cel, tiles.as_ptr(), 1, &mut page, &mut slot, told, put);
        assert_eq!(given, 1, "{}", last_error());
        let word = TileAt { page, slot }.word();
        let number = numbered();
        let out = tell((own.engine, own.pool, stroke), &[word], &[NO_TILE], number);
        let took = started.elapsed();
        assert!(took < Duration::from_millis(1_000), "waited {took:?} for the engine's thread");
        assert_eq!(told_within(number, Duration::ZERO), None, "not told while the thread stands");
        assert_eq!((told_within(put, LONG), told_within(number, LONG)), (Some(true), Some(true)));
        assert_eq!(changes_of(*out), [1], "the tile put before it was asked, as put");
        gpu_engine_finished_free(*out);
        gpu_engine_stroke_free(stroke);
        close(own);
    }
}

// What cannot be told is told false, null written: a tile that names
// none, and no tile asked.
#[test]
fn a_stroke_s_tiles_that_name_none_or_none_at_all_are_told_false() {
    // SAFETY: as the first test's; the stroke is let go of after its use.
    unsafe {
        let own = open();
        let stroke = a_stroke(&own);
        for (tiles, under) in [(&[NO_TILE][..], &[NO_TILE][..]), (&[][..], &[][..])] {
            let number = numbered();
            let out = tell((own.engine, own.pool, stroke), tiles, under, number);
            assert_eq!(told_within(number, LONG), Some(false), "{} asked", tiles.len());
            assert!(out.is_null(), "null written where nothing finished");
        }
        gpu_engine_stroke_free(stroke);
        close(own);
    }
}

// A tile that lies folded is told false: the engine's thread has no fold
// to hand to unfold it, where the pool's own reads have.
#[test]
fn a_stroke_s_tile_that_lies_folded_is_told_false() {
    let engine = rig().engine;
    // SAFETY: the pool and the stroke are the test's own, made on the
    // rig's engine and let go of after their last use.
    unsafe {
        let pool = gpu_engine_pool_new(engine, u64::MAX, u64::MAX);
        let stroke = gpu_engine_stroke_new(engine);
        assert!(!stroke.is_null(), "{}", last_error());
        let one = tile(1, 1);
        let cel = (&mut *pool).cel();
        let places = (&mut *pool).store(engine, cel, &[one.as_slice()]).expect("store");
        let (at_rest, number) = (places[0].word(), numbered());
        let out = tell((engine, pool, stroke), &[at_rest], &[NO_TILE], number);
        assert_eq!(told_within(number, LONG), Some(true), "⛔premise: told as it lies as it is");
        gpu_engine_finished_free(*out);
        assert_eq!(settled(&mut *pool, &places), 1, "⛔premise: folded");
        let number = numbered();
        let out = tell((engine, pool, stroke), &[at_rest], &[NO_TILE], number);
        assert_eq!(told_within(number, LONG), Some(false), "folded");
        assert!(out.is_null(), "null written where nothing finished");
        gpu_engine_stroke_free(stroke);
        gpu_engine_pool_free(pool);
    }
}
