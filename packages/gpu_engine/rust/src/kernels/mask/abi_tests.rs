//! The selection's mask as the app asks for it: a program read into the
//! steps it spells — checked against the passes those steps make when
//! handed in as they are, never against a mask written out again here.

use std::sync::OnceLock;

use super::super::region::Combine::{Add, Replace, Subtract};
use super::super::region::{Operand, Step};
use super::super::{Finish, MaskBox, Part};
use super::{
    SelectionMasks, gpu_engine_area_masks_new, gpu_engine_selection_mask_new, gpu_engine_selection_masks_new,
};
use crate::device::Engine;
use crate::kernels::composite::abi::{MaskPlane, gpu_engine_mask_free};
use crate::testing::{first_engine, read_buffer};

struct Rig {
    engine: &'static Engine,
    masks: &'static SelectionMasks,
}

/// One device and one compile for every test here.
fn rig() -> &'static Rig {
    static RIG: OnceLock<Rig> = OnceLock::new();
    RIG.get_or_init(|| {
        let engine = first_engine();
        // SAFETY: the engine lives for the process; the kernels are never
        // freed.
        let masks = unsafe { &*gpu_engine_selection_masks_new(engine) };
        Rig { engine, masks }
    })
}

const AT: (i32, i32) = (-3, 2);
const SIZE: MaskBox = MaskBox { width: 37, height: 29 };

/// A selection the program below spells: a box, less a nested selection of
/// two boxes joined, one of them a slanted ring — every kind of word.
fn steps() -> Vec<Step> {
    vec![
        Step {
            combine: Replace,
            operand: Operand::Copies(vec![vec![
                [0.5, 3.0],
                [30.25, 3.0],
                [30.25, 27.75],
                [0.5, 27.75],
            ]]),
        },
        Step {
            combine: Subtract,
            operand: Operand::Region(vec![
                Step {
                    combine: Replace,
                    operand: Operand::Copies(vec![
                        vec![[4.0, 6.0], [12.0, 6.0], [12.0, 14.0], [4.0, 14.0]],
                        vec![[9.0, 10.0], [21.5, 12.0], [15.0, 22.0]],
                    ]),
                },
                Step {
                    combine: Add,
                    operand: Operand::Copies(vec![vec![[-2.0, 20.0], [6.0, 20.0], [6.0, 26.0]]]),
                },
            ]),
        },
    ]
}

/// [`steps`] as the app spells them.
fn program() -> (Vec<u32>, Vec<f64>) {
    let words = vec![2, 0, 0, 1, 4, 2, 1, 2, 0, 0, 2, 4, 3, 1, 0, 1, 3];
    let points = vec![
        0.5, 3.0, 30.25, 3.0, 30.25, 27.75, 0.5, 27.75, //
        4.0, 6.0, 12.0, 6.0, 12.0, 14.0, 4.0, 14.0, //
        9.0, 10.0, 21.5, 12.0, 15.0, 22.0, //
        -2.0, 20.0, 6.0, 20.0, 6.0, 26.0,
    ];
    (words, points)
}

/// A plane's bytes over [`SIZE`], row after row.
fn bytes_of(engine: &Engine, plane: &wgpu::Buffer) -> Vec<u8> {
    bytes_over(engine, plane, SIZE)
}

/// A plane's bytes over `size`, row after row.
fn bytes_over(engine: &Engine, plane: &wgpu::Buffer, size: MaskBox) -> Vec<u8> {
    let stride = (size.width.div_ceil(4) * 4) as usize;
    read_buffer(engine, plane)
        .chunks(stride)
        .take(size.height as usize)
        .flat_map(|row| row[..size.width as usize].to_vec())
        .collect()
}

/// What the app gets for `words` over `points` at `finish`, read back — or
/// none where it was refused.
fn asked(words: &[u32], points: &[f64], finish: Finish) -> Option<Vec<u8>> {
    let Rig { engine, masks } = rig();
    // SAFETY: the rig is live; the slices hold what they say.
    let plane = unsafe {
        gpu_engine_selection_mask_new(
            *masks,
            *engine,
            words.as_ptr(),
            words.len(),
            points.as_ptr(),
            points.len(),
            AT.0,
            AT.1,
            SIZE.width,
            SIZE.height,
            finish.grow,
            finish.feather,
            finish.anti_alias,
        )
    };
    if plane.is_null() {
        return None;
    }
    // SAFETY: made above, freed below.
    let read = bytes_of(engine, unsafe { &*plane }.mask().plane);
    // SAFETY: made above.
    unsafe { gpu_engine_mask_free(plane) };
    Some(read)
}

/// What the passes make of [`steps`] handed in as they are, at `finish`.
fn made(finish: Finish) -> Vec<u8> {
    let Rig { engine, masks } = rig();
    let hard = masks.region.selection(engine, &steps(), AT, SIZE).expect("a hard mask");
    if finish.is_hard() {
        return bytes_of(engine, &hard);
    }
    let finished = masks.passes.selection(engine, &hard, SIZE, finish).expect("a finish");
    bytes_of(engine, &finished)
}

const HARD: Finish = Finish { grow: 0, feather: 0.0, anti_alias: false };

#[test]
fn a_spelled_selection_is_the_selection_it_spells() {
    let (words, points) = program();
    let mask = asked(&words, &points, HARD).expect("a mask");

    assert_eq!(mask, made(HARD));
    // Liveness: the nested selection took something away, and the box
    // kept the rest.
    assert!(mask.contains(&0) && mask.contains(&255));
}

#[test]
fn it_is_finished_by_the_knobs_it_is_handed() {
    let (words, points) = program();
    for finish in [
        Finish { grow: 2, feather: 0.0, anti_alias: false },
        Finish { grow: -1, feather: 3.5, anti_alias: true },
        Finish { grow: 0, feather: 0.0, anti_alias: true },
    ] {
        let mask = asked(&words, &points, finish).expect("a mask");

        assert_eq!(mask, made(finish), "{finish:?}");
        assert_ne!(mask, made(HARD), "{finish:?}: and it is finished");
    }
}

#[test]
fn a_program_that_spells_less_or_more_than_it_holds_is_refused() {
    let (words, points) = program();
    let mut wrong_fold = words.clone();
    wrong_fold[1] = 4;
    let mut wrong_kind = words.clone();
    wrong_kind[2] = 2;
    let mut no_step = words.clone();
    no_step[0] = 0;
    for (words, points) in [
        (&words[..words.len() - 1], &points[..]),
        (&[&words[..], &[7]].concat()[..], &points[..]),
        (&words[..], &points[..points.len() - 2]),
        (&words[..], &[&points[..], &[1.0, 2.0]].concat()[..]),
        (&wrong_fold[..], &points[..]),
        (&wrong_kind[..], &points[..]),
        (&no_step[..], &points[..]),
    ] {
        assert_eq!(asked(words, points, HARD), None, "{words:?}");
    }
}

/// `MaskPlane` is what the app frees: made by the one constructor it is
/// counted by.
#[test]
fn the_plane_is_the_box_it_was_asked_for() {
    let Rig { engine, masks } = rig();
    let (words, points) = program();
    // SAFETY: the rig is live; the slices hold what they say.
    let plane: *mut MaskPlane = unsafe {
        gpu_engine_selection_mask_new(
            *masks,
            *engine,
            words.as_ptr(),
            words.len(),
            points.as_ptr(),
            points.len(),
            AT.0,
            AT.1,
            SIZE.width,
            SIZE.height,
            0,
            0.0,
            false,
        )
    };
    // SAFETY: made above, freed below.
    let mask = unsafe { &*plane }.mask();
    assert_eq!((mask.at, mask.size.width, mask.size.height), (AT, SIZE.width, SIZE.height));
    // SAFETY: made above.
    unsafe { gpu_engine_mask_free(plane) };
}

/// A part an area is cut into: its left, top, width and height, canvas
/// pixels.
type Asked = [i32; 4];

/// A plane the app got: its bytes, row after row, with the corner and the
/// box it says it has.
type Got = (Vec<u8>, (i32, i32), (u32, u32));

/// [`SIZE`] at [`AT`] in three parts that hold every pixel of it, out of
/// their order on the box: its bottom, then its top's right and left —
/// the top cut where no word of four pixels ends.
const PARTS: [Asked; 3] = [[-3, 15, 37, 16], [15, 2, 19, 13], [-3, 2, 18, 13]];

/// What the app gets for the area `words` spell over `points`, finished by
/// `expand` and `anti_alias` over `parts` and cut a plane a part — or none
/// where it was refused, and then no plane was made.
fn area_asked(words: &[u32], points: &[f64], (expand, anti_alias): (u32, bool), parts: &[Asked]) -> Option<Vec<Got>> {
    let Rig { engine, masks } = rig();
    let mut planes = vec![std::ptr::null_mut::<MaskPlane>(); parts.len()];
    // SAFETY: the rig is live; the slices hold what they say, and `planes`
    // room for a plane a part.
    let made = unsafe {
        gpu_engine_area_masks_new(
            *masks,
            *engine,
            words.as_ptr(),
            words.len(),
            points.as_ptr(),
            points.len(),
            AT.0,
            AT.1,
            SIZE.width,
            SIZE.height,
            expand,
            anti_alias,
            parts.as_ptr().cast(),
            parts.len(),
            planes.as_mut_ptr(),
        )
    };
    if !made {
        assert!(planes.iter().all(|plane| plane.is_null()), "a refusal made a plane");
        return None;
    }
    let got = |plane: *mut MaskPlane| {
        // SAFETY: made above, freed below.
        let mask = unsafe { &*plane }.mask();
        let got = (bytes_over(engine, mask.plane, mask.size), mask.at, (mask.size.width, mask.size.height));
        // SAFETY: made above.
        unsafe { gpu_engine_mask_free(plane) };
        got
    };
    Some(planes.into_iter().map(got).collect())
}

/// [`steps`]' whole box finished as a fill finishes what it flooded —
/// grown `expand` generations, softened where `anti_alias` — in one part,
/// and `part` of it cut out here.
fn area_made((expand, anti_alias): (u32, bool), part: Asked) -> Vec<u8> {
    let Rig { engine, masks } = rig();
    let hard = masks.region.selection(engine, &steps(), AT, SIZE).expect("a hard mask");
    if expand == 0 && !anti_alias {
        return cut(&bytes_of(engine, &hard), part);
    }
    let finished = masks.passes.fill(engine, &hard, SIZE, expand, anti_alias, &[SIZE.whole()]);
    cut(&bytes_of(engine, &finished.expect("a finish")), part)
}

/// `part` of `whole`, bytes over [`SIZE`] at [`AT`].
fn cut(whole: &[u8], [left, top, width, height]: Asked) -> Vec<u8> {
    let (x, y) = ((left - AT.0) as usize, (top - AT.1) as usize);
    let rows = whole.chunks(SIZE.width as usize).skip(y).take(height as usize);
    rows.flat_map(|row| row[x..x + width as usize].to_vec()).collect()
}

const AS_IT_IS: (u32, bool) = (0, false);

/// An area's planes are its whole box finished and cut: each part's own
/// bytes, at its corner, in the order the parts were asked — whichever way
/// it is finished.
#[test]
fn an_area_is_finished_and_cut_a_plane_a_part() {
    let (words, points) = program();
    for finish in [AS_IT_IS, (2, false), (0, true), (3, true)] {
        let planes = area_asked(&words, &points, finish, &PARTS).expect("planes");
        assert_eq!(planes.len(), PARTS.len());
        let mut finished = false;
        for ((bytes, at, size), part) in planes.into_iter().zip(PARTS) {
            let [left, top, width, height] = part;
            assert_eq!((at, size), ((left, top), (width as u32, height as u32)), "{part:?} at {finish:?}");
            assert!(bytes == area_made(finish, part), "{part:?} at {finish:?}: not the box's bytes there");
            assert!(bytes.contains(&255), "{part:?} at {finish:?}: the area lies in it");
            finished |= bytes != area_made(AS_IT_IS, part);
        }
        assert_eq!(finished, finish != AS_IT_IS, "{finish:?}: and it is finished");
    }
}

/// 🚨The finish runs over the parts asked and no farther (board
/// `an-area-dab-costs-its-box`): a part that holds less than the finish
/// reaches from is finished as the passes finish that part alone — which
/// is not what the whole box's finish leaves there.
#[test]
fn an_area_is_finished_over_its_parts_alone() {
    let Rig { engine, masks } = rig();
    let (words, points) = program();
    let (finish, part) = ((3, true), PARTS[1]);
    let planes = area_asked(&words, &points, finish, &[part]).expect("a plane");

    let [left, top, width, height] = part;
    let (left, top) = ((left - AT.0) as u32, (top - AT.1) as u32);
    let over = Part { left, top, right: left + width as u32, bottom: top + height as u32 };
    let hard = masks.region.selection(engine, &steps(), AT, SIZE).expect("a hard mask");
    let alone = masks.passes.fill(engine, &hard, SIZE, finish.0, finish.1, &[over]).expect("a finish");
    assert!(planes[0].0 == cut(&bytes_of(engine, &alone), part), "not the part's own finish");
    // Liveness: the whole box's finish reaches into the part from past it.
    assert!(planes[0].0 != area_made(finish, part), "fixture: nothing reaches the part from past it");
}

/// A part that is no part of the box — before it, past it, or holding no
/// pixel — is refused by name, whether or not the area is finished, and
/// so is an area asked over no part at all.
#[test]
fn a_part_that_is_none_of_the_box_is_refused() {
    let (words, points) = program();
    let refused = |finish, parts: &[Asked]| {
        assert_eq!(area_asked(&words, &points, finish, parts), None, "{parts:?}");
        crate::last_error()
    };
    let after_one = |part: Asked| refused((1, true), &[PARTS[0], part]);
    assert_eq!(after_one([-4, 2, 5, 5]), "the part [-4, 2, 5, 5] lies before the box at (-3, 2)");
    assert_eq!(after_one([-3, 1, 5, 5]), "the part [-3, 1, 5, 5] lies before the box at (-3, 2)");
    assert_eq!(after_one([0, 5, -1, 5]), "the part [0, 5, -1, 5] holds no pixel");
    assert_eq!(after_one([0, 5, 5, -1]), "the part [0, 5, 5, -1] holds no pixel");
    let of_the_box = |part: &str| format!("Part {{ {part} }} is no part of {SIZE:?}");
    assert_eq!(after_one([0, 5, 0, 5]), of_the_box("left: 3, top: 3, right: 3, bottom: 8"));
    assert_eq!(after_one([30, 5, 5, 5]), of_the_box("left: 33, top: 3, right: 38, bottom: 8"));
    assert_eq!(after_one([0, 27, 5, 5]), of_the_box("left: 3, top: 25, right: 8, bottom: 30"));
    // A part past what a pixel count holds is past the box, not a wrap
    // back into it.
    let far = of_the_box("left: 2147483650, top: 3, right: 4294967295, bottom: 2147483650");
    assert_eq!(after_one([i32::MAX, 5, i32::MAX, i32::MAX]), far);
    // The cut refuses what the finish would have, where nothing finishes.
    let past = of_the_box("left: 33, top: 3, right: 38, bottom: 8");
    assert_eq!(refused(AS_IT_IS, &[[30, 5, 5, 5]]), past);
    assert_eq!(refused(AS_IT_IS, &[]), "a pass over no part of its box");
    assert_eq!(refused((1, true), &[]), "a pass over no part of its box");
}

/// An area's program is read as a selection's is: one that spells less
/// than it holds is refused.
#[test]
fn an_area_whose_program_spells_no_selection_is_refused() {
    let (words, points) = program();
    for finish in [AS_IT_IS, (1, true)] {
        assert_eq!(area_asked(&words[..words.len() - 1], &points, finish, &PARTS), None);
        assert_eq!(area_asked(&words, &points[..points.len() - 2], finish, &PARTS), None);
    }
}
