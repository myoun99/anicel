//! The lift on a real GPU, checked against the app's gather by hand — never
//! against a CPU copy of it (`kernels/mod.rs` has why) — and against the
//! ledger. The cels and masks are the verbs' (`cel_pixel/tests.rs`).

use std::sync::OnceLock;

use super::{Lift, Lifted};
use crate::device::Engine;
use crate::kernels::cel_pixel::tests::{
    CUTS, Cel, INK, OTHER, SIDE, hashed, hashed_cel, hashed_cel_on, one, rgba,
};
use crate::kernels::cel_pixel::words;
use crate::kernels::composite::tests::mix;
use crate::kernels::mask::tests::{Masked, masked};
use crate::kernels::mask::{Mask, MaskBox};
use crate::kernels::shared::{plane, room};
use crate::testing::{assert_pinned, first_engine, read_buffer};

struct Rig {
    engine: &'static Engine,
    lift: Lift,
}

/// One device and one compiled lift for every test here (blend's tests
/// have why).
fn rig() -> &'static Rig {
    static RIG: OnceLock<Rig> = OnceLock::new();
    RIG.get_or_init(|| {
        let engine = first_engine();
        let lift = Lift::new(engine).expect("compile the lift");
        Rig { engine, lift }
    })
}

/// What `mask` takes off `cel`, whole or feathered, its passes cut at
/// `cut`'s pages and tiles or as the device cuts them: the box's words, row
/// after row, and whether it took any.
fn lifted(
    cel: &Cel,
    mask: &Masked,
    whole: bool,
    cut: Option<(usize, usize)>,
) -> Option<(Vec<u32>, bool)> {
    let Rig { engine, lift } = rig();
    let pages = cel.pool.upload(engine);
    let mask = mask.mask();
    let Lifted { rgba, anything } = match cut {
        Some(cut) => lift.run_by(engine, &pages, &cel.set, &mask, whole, cut),
        None => lift.run(engine, &pages, &cel.set, &mask, whole),
    }?;
    Some((words(&read_buffer(engine, &rgba)), anything))
}

/// Over tile (0, 0): ink under alpha 200, another colour, a colour under
/// alpha 0, ink under alpha 1, ink the mask leaves out and another colour
/// under alpha 50 — the box's last pixel — in a box of 3 × 2 from (2, 1),
/// and ink just past its right edge, where the mask's last word holds 255.
fn scene() -> (Cel, Masked) {
    let cel = one(&[
        ((2, 1), INK | 200 << 24),
        ((3, 1), OTHER | 255 << 24),
        ((4, 1), rgba(9, 9, 9, 0)),
        ((5, 1), INK | 255 << 24),
        ((2, 2), INK | 1 << 24),
        ((3, 2), OTHER | 90 << 24),
        ((4, 2), OTHER | 50 << 24),
    ]);
    let coverage = [[255, 128, 255], [1, 0, 200]];
    let mask = masked((2, 1), (3, 2), move |x, y| coverage[(y - 1) as usize][(x - 2) as usize]);
    (cel, mask)
}

/// A pixel the mask covers at all travels whole — its colour and its alpha
/// as they are, under a coverage of 128, 200 or 1 alike; one with no ink,
/// one the mask leaves out, and one past the box stay where they are.
#[test]
fn a_lift_takes_each_covered_pixel_whole() {
    let (cel, mask) = scene();
    let (words, anything) = lifted(&cel, &mask, true, None).expect("lift");
    let row = [INK | 200 << 24, OTHER | 255 << 24, 0];
    assert_eq!(words, [row, [INK | 1 << 24, 0, OTHER | 50 << 24]].concat());
    assert!(anything);
}

/// Under a feather the alpha is scaled by the coverage, as the premultiply
/// rounds: 200 under 255 stays 200, 255 under 128 is 128, 50 under 200 is
/// 39, and 1 under 1 is 0 — a pixel taken with its colour and no alpha,
/// which the app's gather counts as taken all the same.
#[test]
fn a_feathered_lift_scales_each_alpha_by_its_coverage() {
    let (cel, mask) = scene();
    let (words, anything) = lifted(&cel, &mask, false, None).expect("lift");
    let row = [INK | 200 << 24, OTHER | 128 << 24, 0];
    assert_eq!(words, [row, [INK, 0, OTHER | 39 << 24]].concat());
    assert!(anything);
}

/// A box over ink the mask leaves out takes nothing, and so does one over a
/// colour under alpha 0 — with ink past its edge in the mask's last word —
/// and one over no tile of the cel: nothing is laid, and nothing was taken.
#[test]
fn a_lift_over_nothing_takes_nothing() {
    let (cel, _) = scene();
    let out = masked((3, 2), (2, 1), |_, _| 0);
    let inkless = masked((4, 1), (1, 1), |_, _| 255);
    let past = masked((300, 0), (5, 4), |_, _| 255);
    for (mask, pixels) in [(out, 2), (inkless, 1), (past, 20)] {
        let (words, anything) = lifted(&cel, &mask, true, None).expect("lift");
        assert_eq!(words, vec![0; pixels]);
        assert!(!anything);
    }
}

/// A quarter of the pixels 0, a quarter 255, the rest hashed.
fn hashed_coverage(x: i32, y: i32) -> u8 {
    let h = mix(x as u32 ^ mix(y as u32 ^ 0x11f7));
    match h & 3 {
        0 => 0,
        1 => 255,
        _ => (h >> 8) as u8,
    }
}

/// The hashed coverage over `hashed_cel`'s two rows of tiles, from (-140,
/// -10), 300 × 30 — past its last column, into its missing tile and across
/// the edge between its rows.
fn hashed_mask() -> Masked {
    masked((-140, -10), (300, 30), hashed_coverage)
}

/// Whether `hashed_cel` holds the tile pixel (x, y) is on: its six tiles
/// from (-2, -1) but (0, 0).
fn held(x: i32, y: i32) -> bool {
    let tile = (x.div_euclid(SIDE), y.div_euclid(SIDE));
    (-2..=0).contains(&tile.0) && (-1..=0).contains(&tile.1) && tile != (0, 0)
}

/// The hashed cel lifted whole under the hashed mask, in one pass and cut
/// into passes by its pages and its tiles: every pass binds its own rows of
/// the box, from where a binding may start, and lays each pixel the mask
/// covers as it is held — what the pass in one piece lays too, and what
/// the scene says by hand (브러시/렌더링's u06: a cut is held against more
/// than another cut).
#[test]
fn a_lift_cut_into_passes_lays_what_one_pass_lays() {
    let mask = hashed_mask();
    let mut wanted = Vec::new();
    for y in -10..20 {
        for x in -140..160 {
            let pixel = hashed(x, y);
            let taken = held(x, y) && hashed_coverage(x, y) != 0 && pixel >> 24 != 0;
            wanted.push(if taken { pixel } else { 0 });
        }
    }
    let (whole, anything) = lifted(&hashed_cel_on(|_| 0), &mask, true, Some((1, 6))).unwrap();
    assert_eq!(whole, wanted);
    assert!(anything);
    let (feathered, _) = lifted(&hashed_cel_on(|_| 0), &mask, false, Some((1, 6))).unwrap();
    for cut in CUTS {
        let cel = hashed_cel();
        assert_eq!(lifted(&cel, &mask, true, Some(cut)).unwrap(), (whole.clone(), true), "{cut:?}");
        let (words, _) = lifted(&cel, &mask, false, Some(cut)).unwrap();
        assert!(words == feathered, "{cut:?}");
    }
}

/// The most tiles a lift's pass takes fit a binding at their worst, and
/// one more would not: over a box so wide that a binding, not a dispatch,
/// ends a pass, a tile's worst is its 128 rows of the box, past the box's
/// first row bound from where a binding may start.
#[test]
fn a_lift_pass_takes_as_many_tiles_as_a_binding_holds() {
    let Rig { engine, .. } = rig();
    let room = room(engine);
    let limits = engine.device.limits();
    let reach = u64::from(limits.max_compute_workgroups_per_dimension);
    let align = u64::from(limits.min_storage_buffer_offset_alignment);
    let width = (room / reach / 512 + 1) as u32;
    let plane = plane(engine, "no mask", 4);
    let mask = Mask {
        plane: &plane,
        at: (0, 0),
        size: MaskBox { width, height: 1 },
    };
    let most = super::most(engine, &mask).expect("most") as u64;
    let rows = 128 * u64::from(width) * 4;
    assert!(most < reach, "{most} of {reach}");
    assert!(most * rows + align <= room, "{most} tiles of {rows} bytes in {room}");
    assert!((most + 1) * rows + align > room, "{most} tiles of {rows} bytes in {room}");
}

/// The hashed cel lifted whole and feathered under the hashed mask.
#[test]
fn every_device_lifts_the_pinned_selection() {
    let cel = hashed_cel();
    let mask = hashed_mask();
    let mut bytes = Vec::new();
    for whole in [true, false] {
        let (words, anything) = lifted(&cel, &mask, whole, None).expect("lift");
        bytes.extend(words.iter().flat_map(|word| word.to_le_bytes()));
        bytes.push(u8::from(anything));
    }
    assert_pinned("cel_pixel/lifted", &bytes);
}
