//! A picture the pool holds landed as a cel's own ([`gpu_engine_tiles_land`]):
//! its tiles through an alpha and a mask, each in a slot of its own, on a
//! real GPU — checked against the numbers the executor's masked row is
//! pinned to (composite's tests), never a CPU copy of it.

use super::gpu_engine_tiles_land;
use crate::kernels::blend::mode::NORMAL;
use crate::kernels::composite::abi::{MaskPlane, gpu_engine_mask_free, gpu_engine_mask_new};
use crate::kernels::composite::tests::rig;
use crate::kernels::composite::{NO_TILE, TILE_BYTES, TileAt};
use crate::kernels::pool::Pool;
use crate::kernels::pool::folded_tests::{scrubbed, settled, tile};
use crate::testing::{last_error, stored};

const WHOLE: u32 = 65535;
const INK: [u8; 4] = [200, 100, 50, 255];
const NOTHING: [u8; 4] = [0, 0, 0, 0];
/// The mask's 128 as an opacity: 128 · 257.
const HALF: u32 = 32896;

/// What landed of each tile asked: its change (0 the same, 1 inked, 2
/// cleared) and the slot it took.
type Landed = Vec<(u8, Option<TileAt>)>;

/// The picture `set` names — (x0, y0, columns, rows) and its words — landed
/// on the tiles `asks` of a cel of `pool`'s with nothing under them, at
/// `opacity` in normal under `mask`.
fn landed(
    pool: &mut Pool,
    set: (i32, i32, u32, u32, &[u32]),
    asks: &[(i32, i32)],
    opacity: u32,
    mask: *const MaskPlane,
) -> Landed {
    landed_over(pool, set, asks, &vec![NO_TILE; asks.len()], opacity, mask)
}

/// [`landed`] over the cel's tiles `under` names, one for each of `asks`.
fn landed_over(
    pool: &mut Pool,
    (x0, y0, columns, rows, words): (i32, i32, u32, u32, &[u32]),
    asks: &[(i32, i32)],
    under: &[u32],
    opacity: u32,
    mask: *const MaskPlane,
) -> Landed {
    let rig = rig();
    let cel = pool.cel();
    let coordinates: Vec<i32> = asks.iter().flat_map(|&(column, row)| [column, row]).collect();
    let mut places = vec![0u32; asks.len()];
    let mut changes = vec![9u8; asks.len()];
    let mut inks = vec![0i32; 4 * asks.len()];
    // SAFETY: every pointer is live on the rig's engine, and each list holds
    // as many as its count says.
    let count = unsafe {
        gpu_engine_tiles_land(
            rig.engine,
            &rig.composite,
            pool,
            cel.0,
            x0,
            y0,
            columns,
            rows,
            words.as_ptr(),
            coordinates.as_ptr(),
            under.as_ptr(),
            asks.len(),
            opacity,
            NORMAL,
            mask,
            places.as_mut_ptr(),
            changes.as_mut_ptr(),
            inks.as_mut_ptr(),
        )
    };
    assert!(count >= 0, "{}", last_error());
    (0..count as usize).map(|at| (changes[at], TileAt::of_word(places[at]))).collect()
}

/// A mask one pixel high from (`x`, `y`), its bytes `bytes`.
fn mask_row(x: i32, y: i32, bytes: &[u8]) -> *mut MaskPlane {
    let width = bytes.len() as u32;
    // SAFETY: the engine is live and `bytes` holds the box's.
    let mask = unsafe { gpu_engine_mask_new(rig().engine, bytes.as_ptr(), x, y, width, 1) };
    assert!(!mask.is_null(), "{}", last_error());
    mask
}

fn read(pool: &Pool, at: TileAt) -> Vec<u8> {
    let mut bytes = vec![0; TILE_BYTES as usize];
    pool.read(rig().engine, &[at], &mut bytes).expect("a read");
    bytes
}

fn pixel(bytes: &[u8], x: usize, y: usize) -> [u8; 4] {
    bytes[(y * 128 + x) * 4..][..4].try_into().unwrap()
}

/// Whether `got` is `want` give or take one in each channel: a straight
/// colour laid at part of its alpha comes back through its premultiplied
/// sum.
fn near(got: [u8; 4], want: [u8; 4]) -> bool {
    got.iter().zip(want).all(|(&g, w)| g.abs_diff(w) <= 1)
}

// Every tile asked takes a slot of its own, inked — nothing compares, so
// nothing waits for the GPU —, a place the picture has no tile on among
// them; the picture's own tile is as it was.
#[test]
fn each_tile_asked_lands_inked_in_a_slot_of_its_own() {
    let (mut pool, places) = stored(&[INK.repeat(TILE_BYTES as usize / 4)]);
    let words = [places[0].word(), NO_TILE];
    let got = landed(&mut pool, (0, 0, 2, 1, &words), &[(0, 0), (1, 0)], WHOLE, std::ptr::null());
    assert_eq!(got.len(), 2);
    assert!(got.iter().all(|&(change, at)| change == 1 && at.is_some()), "{got:?}");
    let (ink, nothing) = (got[0].1.unwrap(), got[1].1.unwrap());
    assert_ne!(ink, places[0], "a stored tile is never written over");
    assert_eq!(pixel(&read(&pool, ink), 70, 9), INK);
    assert_eq!(pixel(&read(&pool, nothing), 70, 9), NOTHING);
    assert_eq!(pixel(&read(&pool, places[0]), 70, 9), INK);
}

// The picture lands at the opacity asked: INK whole at the mask's 128 as an
// opacity is INK at 128, as a masked row's red is (composite's tests).
#[test]
fn a_picture_lands_at_its_alpha() {
    let (mut pool, places) = stored(&[INK.repeat(TILE_BYTES as usize / 4)]);
    let picture = (0, 0, 1, 1, &[places[0].word()][..]);
    let got = landed(&mut pool, picture, &[(0, 0)], HALF, std::ptr::null());
    let at = read(&pool, got[0].1.unwrap());
    for (x, y) in [(0, 0), (64, 64), (127, 127)] {
        assert!(near(pixel(&at, x, y), [200, 100, 50, 128]), "{:?}", pixel(&at, x, y));
    }
}

// The picture lands under the mask's byte at each pixel — whole under 255,
// at 128 under 128, not at all under 0 — and not at all past the mask's
// box; the mask's box on the canvas, here on the second tile.
#[test]
fn a_picture_lands_under_the_mask_s_byte_and_nothing_past_its_box() {
    let tile = INK.repeat(TILE_BYTES as usize / 4);
    let (mut pool, places) = stored(&[tile.clone(), tile]);
    let words = [places[0].word(), places[1].word()];
    let mask = mask_row(130, 5, &[255, 128, 0]);
    let got = landed(&mut pool, (0, 0, 2, 1, &words), &[(0, 0), (1, 0)], WHOLE, mask);
    // SAFETY: the mask came from `gpu_engine_mask_new` and nothing names it.
    unsafe { gpu_engine_mask_free(mask) };
    let (left, right) = (read(&pool, got[0].1.unwrap()), read(&pool, got[1].1.unwrap()));
    assert_eq!(pixel(&right, 2, 5), INK);
    assert!(near(pixel(&right, 3, 5), [200, 100, 50, 128]), "{:?}", pixel(&right, 3, 5));
    assert_eq!(pixel(&right, 4, 5)[3], 0);
    for (x, y) in [(1, 5), (5, 5), (2, 4), (2, 6), (100, 100)] {
        assert_eq!(pixel(&right, x, y)[3], 0, "({x}, {y}) is past the box");
    }
    assert!(left.chunks_exact(4).all(|texel| texel[3] == 0), "the first tile is past the box");
}

// A picture is laid from where its tiles lie, on the cel's tile where it
// lies: both folded since they were stored, their slots' bytes written
// over, the landing puts the bytes it put before.
#[test]
fn a_picture_and_the_tile_under_it_that_lie_folded_land_as_they_did() {
    let (mut pool, places) = stored(&[tile(1, 2), tile(2, 16)]);
    let (picture, under) = ((0, 0, 1, 1, &[places[0].word()][..]), [places[1].word()]);
    let before = landed_over(&mut pool, picture, &[(0, 0)], &under, HALF, std::ptr::null());
    let as_stored = read(&pool, before[0].1.unwrap());
    assert!(as_stored != read(&pool, places[0]) && as_stored != read(&pool, places[1]));
    assert_eq!(settled(&mut pool, &places), 2);
    scrubbed(rig().engine, &pool, &places);
    let after = landed_over(&mut pool, picture, &[(0, 0)], &under, HALF, std::ptr::null());
    assert_eq!(after[0].0, 1);
    assert!(read(&pool, after[0].1.unwrap()) == as_stored);
}

// No tile asked lands none, and is no failure.
#[test]
fn no_tile_asked_lands_none() {
    let (mut pool, places) = stored(&[INK.repeat(TILE_BYTES as usize / 4)]);
    let got = landed(&mut pool, (0, 0, 1, 1, &[places[0].word()]), &[], WHOLE, std::ptr::null());
    assert!(got.is_empty());
}
