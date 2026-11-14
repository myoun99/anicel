//! The selection's mask as the app asks for it: a program read into the
//! steps it spells — checked against the passes those steps make when
//! handed in as they are, never against a mask written out again here.

use std::sync::OnceLock;

use super::super::region::Combine::{Add, Replace, Subtract};
use super::super::region::{Operand, Step};
use super::super::{Finish, MaskBox};
use super::{SelectionMasks, gpu_engine_selection_mask_new, gpu_engine_selection_masks_new};
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
    let stride = (SIZE.width.div_ceil(4) * 4) as usize;
    read_buffer(engine, plane)
        .chunks(stride)
        .take(SIZE.height as usize)
        .flat_map(|row| row[..SIZE.width as usize].to_vec())
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
