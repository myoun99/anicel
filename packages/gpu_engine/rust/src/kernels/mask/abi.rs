//! The selection's mask, made where it is read (gpu-int-spec-canvas 1b S1 ·
//! S2): the app hands a selection's steps as it holds them, spelled as a
//! program ([`gpu_engine_selection_mask_new`]), with the tool's knobs and
//! the box to make it over, and keeps the plane it is given (`MaskPlane`)
//! for the verbs that read a selection on the GPU. ↩️The app made these
//! bytes itself — `buildSelectionMask`, at every move of a stroke under a
//! selection — and handed them up (`gpu_engine_mask_new`).

#[cfg(test)]
#[path = "abi_tests.rs"]
mod tests;

use super::region::{Combine, Operand, RegionMask, Step};
use super::runs::{MaskRuns, SelectionRuns};
use super::within::MaskWithin;
use super::{Finish, MaskBox, MaskPasses, Part};
use crate::device::{Engine, hands_bytes, let_go, let_go_bytes, on_thread_of};
use crate::fail;
use crate::kernels::composite::abi::MaskPlane;

/// The selection's passes — its hard mask's and its finishing's —, compiled
/// together: what the app compiles once.
pub struct SelectionMasks {
    region: RegionMask,
    passes: MaskPasses,
    within: MaskWithin,
    runs: MaskRuns,
}

/// The selection's kernels, compiled.
///
/// # Safety
/// `engine` is live; the kernels are freed before it.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_selection_masks_new(
    engine: *const Engine,
) -> *mut SelectionMasks {
    // SAFETY: see the function's contract.
    let engine = unsafe { &*engine };
    engine.on_thread(|| {
        let (region, passes) = (RegionMask::new(engine), MaskPasses::new(engine));
        let (within, runs) = (MaskWithin::new(engine), MaskRuns::new(engine));
        engine.hands(SelectionMasks { region, passes, within, runs })
    })
}

/// # Safety
/// `masks` came from `gpu_engine_selection_masks_new`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_selection_masks_free(masks: *mut SelectionMasks) {
    // SAFETY: see the function's contract.
    unsafe { let_go(masks) };
}

/// The bytes `masks` keeps between its folds: the bit planes a selection
/// is folded in (`RegionMask`).
///
/// # Safety
/// `masks` is live.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_selection_masks_bytes(masks: *const SelectionMasks) -> u64 {
    // SAFETY: see the function's contract.
    unsafe { &*masks }.region.kept_bytes()
}

/// Lets go of what `masks` keeps between its folds.
///
/// # Safety
/// `masks` is live.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_selection_masks_let_go(masks: *const SelectionMasks) {
    // SAFETY: see the function's contract.
    unsafe { on_thread_of(masks, || (*masks).region.let_go()) };
}

/// The mask of the selection `program` spells over `points` ([`steps_of`])
/// on the pixel box `width` × `height` whose top-left pixel is (`x`, `y`),
/// finished by the knobs `grow`, `feather` and `anti_alias`, kept as a
/// plane for the app. The work is submitted, and what reads the plane
/// after it reads it done: no one waits. Null where the program does not spell a selection or a box
/// or point lies past the reach; see the last error.
///
/// # Safety
/// `masks` and `engine` are live, the masks compiled on `engine`;
/// `program` holds `program_length` words and `points` `points_length`.
#[unsafe(no_mangle)]
#[allow(clippy::too_many_arguments)]
pub unsafe extern "C" fn gpu_engine_selection_mask_new(
    masks: *const SelectionMasks,
    engine: *const Engine,
    program: *const u32,
    program_length: usize,
    points: *const f64,
    points_length: usize,
    x: i32,
    y: i32,
    width: u32,
    height: u32,
    grow: i32,
    feather: f64,
    anti_alias: bool,
) -> *mut MaskPlane {
    // SAFETY: see the function's contract.
    let (masks, engine, program, points) = unsafe {
        (
            &*masks,
            &*engine,
            std::slice::from_raw_parts(program, program_length),
            std::slice::from_raw_parts(points, points_length),
        )
    };
    let size = MaskBox { width, height };
    let finish = Finish { grow, feather, anti_alias };
    engine.on_thread(|| match masked(masks, engine, program, points, (x, y), size, finish) {
        Some(plane) => MaskPlane::kept(engine, plane, (x, y), size),
        None => std::ptr::null_mut(),
    })
}

/// `mask` cut by the selection `by` (within.wgsl) — a fill's range as its
/// mark shows it under a selection: a new plane over `mask`'s box, whole
/// where both hold any of the pixel and 0 elsewhere, kept for the app. The
/// work is submitted, and what reads the plane after it reads it done.
/// Null where either holds less than its box or a plane is past a
/// binding; see the last error.
///
/// # Safety
/// `masks` and `engine` are live, the masks compiled on `engine`, and
/// `mask` and `by` are live planes made on `engine`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_selection_mask_cut(
    masks: *const SelectionMasks,
    engine: *const Engine,
    mask: *const MaskPlane,
    by: *const MaskPlane,
) -> *mut MaskPlane {
    // SAFETY: see the function's contract.
    let (masks, engine, mask, by) = unsafe { (&*masks, &*engine, (*mask).mask(), (*by).mask()) };
    engine.on_thread(|| match masks.within.cut(engine, &mask, &by) {
        Some(plane) => MaskPlane::kept(engine, plane, mask.at, mask.size),
        None => std::ptr::null_mut(),
    })
}

/// The AREA `program` spells over `points` ([`steps_of`]) on the pixel box
/// `width` × `height` whose top-left pixel is (`x`, `y`) — its hard mask,
/// finished as a fill finishes what it flooded ([`MaskPasses::fill`]:
/// grown `expand` generations, softened past its outline where
/// `anti_alias`) — over the `count` parts of the box `parts` names, and cut
/// into a plane for each, kept for the app, written in their order to
/// `planes`. A part is its left, top, width and height, canvas pixels: a
/// run of the tiles the area reaches, which the app lays as a stamp's
/// coverage (`regionFillPieces`), or the box whole, which it reads
/// (`regionFillRange`). The work is submitted, and what reads a plane after
/// it reads it done: no one waits. False where the program does not spell
/// a selection, a box or point lies past the reach, or a part holds no
/// pixel or lies past the box; see the last error.
///
/// 🚨★★★FINISHED ONLY WHERE IT REACHES (board `an-area-dab-costs-its-box`,
/// and `an-areas-finish-is-a-second-spelling-of-the-floods` — 관제
/// 2026-11-14 22:1x): the finish runs over the parts alone, so they hold
/// every pixel it leaves any of, as the app's runs say exactly. ↩️The app
/// finished each piece in a window of its own on the CPU
/// (`_finishedWindow`), a second spelling of the bucket's finish.
///
/// # Safety
/// `masks` and `engine` are live, the masks compiled on `engine`;
/// `program` holds `program_length` words, `points` `points_length`,
/// `parts` `count` × 4 and `planes` room for `count`.
#[unsafe(no_mangle)]
#[allow(clippy::too_many_arguments)]
pub unsafe extern "C" fn gpu_engine_area_masks_new(
    masks: *const SelectionMasks,
    engine: *const Engine,
    program: *const u32,
    program_length: usize,
    points: *const f64,
    points_length: usize,
    x: i32,
    y: i32,
    width: u32,
    height: u32,
    expand: u32,
    anti_alias: bool,
    parts: *const i32,
    count: usize,
    planes: *mut *mut MaskPlane,
) -> bool {
    // SAFETY: see the function's contract.
    let (masks, engine, program, points, parts) = unsafe {
        (
            &*masks,
            &*engine,
            std::slice::from_raw_parts(program, program_length),
            std::slice::from_raw_parts(points, points_length),
            std::slice::from_raw_parts(parts, count * 4),
        )
    };
    let size = MaskBox { width, height };
    engine.on_thread(|| {
        let Some(parts) = parts_of(parts, (x, y)) else {
            return false;
        };
        let Some(made) = area(masks, engine, program, points, (x, y), size, expand, anti_alias, &parts)
        else {
            return false;
        };
        for (at, (plane, part)) in made.into_iter().zip(&parts).enumerate() {
            let corner = (x + part.left as i32, y + part.top as i32);
            let kept = MaskPlane::kept(engine, plane, corner, part.size());
            // SAFETY: see the function's contract — room for `count`.
            unsafe { *planes.add(at) = kept };
        }
        true
    })
}

/// `parts` — left, top, width and height each, canvas pixels — as parts
/// of the box whose top-left pixel is `at`; none where one lies before it
/// or holds no pixel (see the last error), as `MaskPasses` refuses one past
/// it.
fn parts_of(parts: &[i32], (x, y): (i32, i32)) -> Option<Vec<Part>> {
    parts
        .chunks_exact(4)
        .map(|part| {
            let &[left, top, width, height] = part else { unreachable!() };
            let from = |at: i32, corner: i32| u32::try_from(i64::from(at) - i64::from(corner)).ok();
            let (Some(left), Some(top)) = (from(left, x), from(top, y)) else {
                return fail(format!("the part {part:?} lies before the box at ({x}, {y})"));
            };
            let (Ok(width), Ok(height)) = (u32::try_from(width), u32::try_from(height)) else {
                return fail(format!("the part {part:?} holds no pixel"));
            };
            Some(Part { left, top, right: left + width, bottom: top + height })
        })
        .collect()
}

/// [`gpu_engine_area_masks_new`]'s planes.
#[allow(clippy::too_many_arguments)]
fn area(
    masks: &SelectionMasks,
    engine: &Engine,
    program: &[u32],
    points: &[f64],
    at: (i32, i32),
    size: MaskBox,
    expand: u32,
    anti_alias: bool,
    parts: &[Part],
) -> Option<Vec<wgpu::Buffer>> {
    let steps = steps_of(program, points)?;
    let hard = masks.region.selection(engine, &steps, at, size)?;
    let finished = if expand == 0 && !anti_alias {
        hard
    } else {
        masks.passes.fill(engine, &hard, size, expand, anti_alias, parts)?
    };
    masks.passes.crop(engine, &finished, size, parts)
}

/// The hard mask of the selection `program` spells over `points`
/// ([`steps_of`]) on the pixel box `width` × `height` whose top-left pixel
/// is (`x`, `y`), read back as its runs ([`SelectionRuns`]) — where each
/// row's selected pixels start and end, what the app's CPU readers of a
/// selection ask. Writes how many ends they hold to `ends`. Waits for the
/// GPU. Null where the program does not spell a selection or a box or
/// point lies past the reach; see the last error.
///
/// # Safety
/// `masks` and `engine` are live, the masks compiled on `engine`;
/// `program` holds `program_length` words and `points` `points_length`;
/// `ends` is a place to write.
#[unsafe(no_mangle)]
#[allow(clippy::too_many_arguments)]
pub unsafe extern "C" fn gpu_engine_selection_runs(
    masks: *const SelectionMasks,
    engine: *const Engine,
    program: *const u32,
    program_length: usize,
    points: *const f64,
    points_length: usize,
    x: i32,
    y: i32,
    width: u32,
    height: u32,
    ends: *mut usize,
) -> *mut SelectionRuns {
    // SAFETY: see the function's contract.
    let (masks, engine, program, points) = unsafe {
        (
            &*masks,
            &*engine,
            std::slice::from_raw_parts(program, program_length),
            std::slice::from_raw_parts(points, points_length),
        )
    };
    let size = MaskBox { width, height };
    engine.on_thread(|| {
        let read = steps_of(program, points)
            .and_then(|steps| masks.region.folded(engine, &steps, (x, y), size))
            .and_then(|folded| masks.runs.read(engine, &folded, size));
        let Some(runs) = read else {
            return std::ptr::null_mut();
        };
        // SAFETY: see the function's contract.
        unsafe { ends.write(runs.ends.len()) };
        hands_bytes(runs)
    })
}

/// Writes `runs`' rows' offsets — the box's height and one more — to
/// `offsets` and their ends to `ends`: row r's are `ends[offsets[r] ..
/// offsets[r + 1]]`, a start and an end in turn, columns from the box's
/// left.
///
/// # Safety
/// `runs` is live; `offsets` holds a word more than its box has rows and
/// `ends` as many as [`gpu_engine_selection_runs`] wrote.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_selection_runs_read(
    runs: *const SelectionRuns,
    offsets: *mut u32,
    ends: *mut u32,
) {
    // SAFETY: see the function's contract.
    let runs = unsafe { &*runs };
    // SAFETY: see the function's contract.
    unsafe {
        offsets.copy_from_nonoverlapping(runs.offsets.as_ptr(), runs.offsets.len());
        ends.copy_from_nonoverlapping(runs.ends.as_ptr(), runs.ends.len());
    }
}

/// # Safety
/// `runs` came from `gpu_engine_selection_runs`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_selection_runs_free(runs: *mut SelectionRuns) {
    // SAFETY: see the function's contract.
    unsafe { let_go_bytes(runs) };
}

/// [`gpu_engine_selection_mask_new`]'s plane.
fn masked(
    masks: &SelectionMasks,
    engine: &Engine,
    program: &[u32],
    points: &[f64],
    at: (i32, i32),
    size: MaskBox,
    finish: Finish,
) -> Option<wgpu::Buffer> {
    let steps = steps_of(program, points)?;
    let hard = masks.region.selection(engine, &steps, at, size)?;
    if finish.is_hard() {
        return Some(hard);
    }
    masks.passes.selection(engine, &hard, size, finish)
}

/// The steps of a selection as the app spells them (`engine_selection_mask`
/// in the app): its steps' count, then each step — its fold
/// (`SelectionCombineMode`'s index, [`Combine`]'s value) and its operand's
/// kind: 0 and its polygons' count, then each polygon's points' count
/// (`CanvasSelectionCopies`), or 1 and a whole selection spelled so
/// (`CanvasSelectionNested`). `points` holds every polygon's points in that
/// order, x then y. None where the words do not spell that, or spell less
/// or more than they hold.
fn steps_of(program: &[u32], points: &[f64]) -> Option<Vec<Step>> {
    let mut read = Program { words: program, points, word: 0, point: 0 };
    let steps = read.steps()?;
    if read.word != program.len() || read.point != points.len() {
        return fail(format!(
            "a selection spelled in {} words of {} and {} points of {}",
            read.word,
            program.len(),
            read.point / 2,
            points.len() / 2,
        ));
    }
    Some(steps)
}

/// A program read from its start: the next word and the next point.
struct Program<'a> {
    words: &'a [u32],
    points: &'a [f64],
    word: usize,
    point: usize,
}

impl Program<'_> {
    fn take(&mut self) -> Option<u32> {
        let Some(&word) = self.words.get(self.word) else {
            return fail("a selection's program ends before its last step");
        };
        self.word += 1;
        Some(word)
    }

    fn steps(&mut self) -> Option<Vec<Step>> {
        let count = self.take()?;
        if count == 0 {
            return fail("a selection of no step");
        }
        (0..count).map(|_| self.step()).collect()
    }

    fn step(&mut self) -> Option<Step> {
        let combine = match self.take()? {
            0 => Combine::Replace,
            1 => Combine::Add,
            2 => Combine::Subtract,
            3 => Combine::Intersect,
            other => return fail(format!("{other} is no way a step folds")),
        };
        let operand = match self.take()? {
            0 => {
                let count = self.take()?;
                if count == 0 {
                    return fail("a step of no polygon");
                }
                Operand::Copies((0..count).map(|_| self.polygon()).collect::<Option<_>>()?)
            }
            1 => Operand::Region(self.steps()?),
            other => return fail(format!("{other} is no kind of operand")),
        };
        Some(Step { combine, operand })
    }

    fn polygon(&mut self) -> Option<Vec<[f64; 2]>> {
        let count = self.take()? as usize;
        let end = self.point + 2 * count;
        let Some(points) = self.points.get(self.point..end) else {
            return fail("a polygon's points run past the points given");
        };
        self.point = end;
        Some(points.chunks_exact(2).map(|point| [point[0], point[1]]).collect())
    }
}
