//! A selection's runs as the app asks for them: spelled as the app spells
//! it, read back row by row — held to which pixels' centres the selection
//! holds, worked out by hand, never to a CPU copy of the passes
//! (`kernels/mod.rs`).

use std::sync::OnceLock;

use super::super::abi::{
    SelectionMasks, gpu_engine_selection_masks_new, gpu_engine_selection_runs,
    gpu_engine_selection_runs_free, gpu_engine_selection_runs_read,
};
use crate::device::Engine;
use crate::testing::{first_engine, last_error};

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

const REPLACE: u32 = 0;
const SUBTRACT: u32 = 2;

/// `steps` — each its fold and its one polygon — spelled as the app spells
/// a selection (`steps_of`).
fn spelled(steps: &[(u32, Vec<[f64; 2]>)]) -> (Vec<u32>, Vec<f64>) {
    let mut words = vec![steps.len() as u32];
    let mut points = Vec::new();
    for (combine, polygon) in steps {
        words.extend([*combine, 0, 1, polygon.len() as u32]);
        points.extend(polygon.iter().flatten());
    }
    (words, points)
}

/// The rectangle from (`left`, `top`) to (`right`, `bottom`).
fn rect(left: f64, top: f64, right: f64, bottom: f64) -> Vec<[f64; 2]> {
    vec![[left, top], [right, top], [right, bottom], [left, bottom]]
}

/// What the engine reads back for `steps` over the box at `at`, `width` ×
/// `height` — each row's runs, a start and an end in turn — or the error
/// it refused with.
fn runs_of(
    steps: &[(u32, Vec<[f64; 2]>)],
    at: (i32, i32),
    (width, height): (u32, u32),
) -> Result<Vec<Vec<u32>>, String> {
    let Rig { engine, masks } = rig();
    let (words, points) = spelled(steps);
    let mut count = usize::MAX;
    // SAFETY: the kernels were compiled on `engine`; each slice holds what
    // it is said to.
    let runs = unsafe {
        gpu_engine_selection_runs(
            *masks,
            *engine,
            words.as_ptr(),
            words.len(),
            points.as_ptr(),
            points.len(),
            at.0,
            at.1,
            width,
            height,
            &mut count,
        )
    };
    if runs.is_null() {
        return Err(last_error());
    }
    let mut offsets = vec![u32::MAX; height as usize + 1];
    let mut ends = vec![u32::MAX; count];
    // SAFETY: `offsets` holds a word a row and one more, `ends` the count
    // written; the runs are freed once.
    unsafe {
        gpu_engine_selection_runs_read(runs, offsets.as_mut_ptr(), ends.as_mut_ptr());
        gpu_engine_selection_runs_free(runs);
    }
    assert_eq!(offsets[0], 0, "the first row starts the runs");
    assert_eq!(offsets[height as usize] as usize, count, "the last row ends them");
    Ok(offsets.windows(2).map(|row| ends[row[0] as usize..row[1] as usize].to_vec()).collect())
}

/// A rectangle holds the pixels whose centres lie inside it — from (1, 1)
/// to (5, 3), columns 1 to 4 of rows 1 and 2 —, and a row it misses has
/// no run.
#[test]
fn a_rectangle_runs_over_the_pixels_whose_centres_it_holds() {
    let runs = runs_of(&[(REPLACE, rect(1.0, 1.0, 5.0, 3.0))], (0, 0), (8, 4));
    assert_eq!(runs.unwrap(), [vec![], vec![1, 5], vec![1, 5], vec![]]);
}

/// A step taken away splits each row's run in two, the right one ending at
/// the box's right edge — the bit past the box, which nothing sets.
#[test]
fn a_hole_splits_a_row_and_a_run_ends_at_the_box_s_edge() {
    let steps = [
        (REPLACE, rect(0.0, 0.0, 8.0, 3.0)),
        (SUBTRACT, rect(2.0, 0.0, 4.0, 3.0)),
    ];
    let runs = runs_of(&steps, (0, 0), (8, 3));
    assert_eq!(runs.unwrap(), [vec![0, 2, 4, 8], vec![0, 2, 4, 8], vec![0, 2, 4, 8]]);
}

/// Columns count from the box's left, wherever the box lies — left of and
/// above the canvas's origin here — and a run that starts past the box's
/// left edge starts at its first column.
#[test]
fn columns_count_from_the_box_s_left_and_a_run_is_cut_at_its_left_edge() {
    let away = runs_of(&[(REPLACE, rect(-40.0, -3.0, -35.0, -1.0))], (-41, -4), (10, 4));
    assert_eq!(away.unwrap(), [vec![], vec![1, 6], vec![1, 6], vec![]]);
    let cut = runs_of(&[(REPLACE, rect(-5.0, 0.0, 3.0, 1.0))], (0, 0), (6, 1));
    assert_eq!(cut.unwrap(), [vec![0, 3]]);
}

/// A run across words of the plane — 32 pixels each — is one run, its
/// start in the first word and its end in the third.
#[test]
fn a_run_across_the_plane_s_words_is_one_run() {
    let runs = runs_of(&[(REPLACE, rect(30.0, 0.0, 70.0, 1.0))], (0, 0), (100, 1));
    assert_eq!(runs.unwrap(), [vec![30, 70]]);
}

/// A comb's twenty teeth are twenty runs on each of their rows and its
/// back one: every run a row has is laid, and in order.
#[test]
fn every_run_a_row_has_is_laid_in_order() {
    let mut comb = vec![[0.0, 3.0], [0.0, 0.0]];
    for tooth in 0..20 {
        let left = f64::from(tooth * 4);
        comb.extend([[left, 0.0], [left + 2.0, 0.0], [left + 2.0, 2.0], [left + 4.0, 2.0]]);
    }
    comb.extend([[80.0, 3.0]]);
    let teeth: Vec<u32> = (0..20).flat_map(|tooth| [tooth * 4, tooth * 4 + 2]).collect();
    let runs = runs_of(&[(REPLACE, comb)], (0, 0), (80, 3)).unwrap();
    assert_eq!(runs, [teeth.clone(), teeth, vec![0, 80]]);
}

/// More rows than the pass that lays the counts end to end has threads —
/// 600 rows, three to a thread —, half of them a run each: each row's runs
/// start where the rows before it end.
#[test]
fn rows_past_the_threads_that_lay_them_are_laid_end_to_end() {
    let runs = runs_of(&[(REPLACE, rect(2.0, 0.0, 4.0, 300.0))], (0, 0), (8, 600)).unwrap();
    for (row, runs) in runs.iter().enumerate() {
        let want: &[u32] = if row < 300 { &[2, 4] } else { &[] };
        assert_eq!(runs, want, "row {row}");
    }
}

/// A box past the canvas's reach is refused, as the mask over it is.
#[test]
fn a_box_past_the_reach_is_refused() {
    let refused = runs_of(&[(REPLACE, rect(0.0, 0.0, 1.0, 1.0))], (1 << 15, 0), (4, 4));
    assert!(refused.unwrap_err().contains("within the canvas's reach"));
}
