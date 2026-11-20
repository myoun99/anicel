//! A stroke's C ABI (flip lane ⓒ): the app piles its dabs on a stroke, and
//! asks it what it makes of the tiles of a cel.

#[cfg(test)]
#[path = "abi_tests.rs"]
mod tests;

#[cfg(test)]
#[path = "tiles_land_tests.rs"]
mod tiles_land_tests;

#[cfg(test)]
#[path = "on_its_way_tests.rs"]
mod on_its_way_tests;

#[cfg(test)]
#[path = "finished_tests.rs"]
mod finished_tests;

use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, Ordering};

use super::blur::{Blurs, Cover};
use super::landing::{self, Asked, Finished, Laid, Over};
use super::mix::{Ground, Step, ground_of};
use super::stamp::{Gradient, Paint, Shape as GradientShape, Source, StampLanding};
use super::stroke::{Stroke, ground_of_rubs};
use super::{Dab, Edge, Paper, RoundProfile, Shape, Texture, Turn};
use crate::device::{Engine, Sent, hands_bytes, let_go, let_go_bytes, let_go_unwaited, on_thread_of};
use crate::{fail, take_last_error};
use crate::kernels::composite::abi::{MaskPlane, sampling};
use crate::kernels::composite::{Composite, NO_TILE, Named, TileAt};
use crate::kernels::mesh::MeshGrid;
use crate::kernels::pool::{Cel, Pool, Writing};
use crate::kernels::shared::{Counted, ResampleMap};
use crate::kernels::warp::{Boxed, Window};
use crate::kernels::write::Change;

/// The entries of a table of evening (`Dab::evening`).
const EVENING_ENTRIES: usize = 1026;

// `DabSpec::flags`.
const THRESHOLD: u32 = 1;
const EDGE_HELD: u32 = 2;
const ERASE: u32 = 4;
const SECOND: u32 = 8;
const PAPER: u32 = 16;

/// A dab as the app hands one over, field by field `Dab`'s: a round tip
/// where `coverage` is not null, a bitmap one where `texture` is not, else
/// square. The tables are alive for the call, and a table two dabs share
/// comes at one address.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct DabSpec {
    centre: [f64; 2],
    opacity: f64,
    flow: f64,
    /// `Edge::Contrast`'s, where `THRESHOLD` is not set.
    contrast: f64,
    /// A bitmap tip's.
    radius: f64,
    cos: f64,
    sin: f64,
    roundness: f64,
    // A round tip's numbers (`RoundProfile`).
    scale: f64,
    reach: f64,
    inner: f64,
    /// The paper's, where `PAPER` is set.
    density: f64,
    texture: *const Texture,
    coverage: *const f64,
    pile: *const f64,
    evening: *const f64,
    /// The entries of each of `coverage` and `pile`.
    entries: usize,
    row_length: u32,
    flags: u32,
    region: [i32; 4],
    /// Red, green, blue, alpha, from the low byte.
    colour: u32,
    /// The mixing step whose colour it lays in place of `colour`
    /// (`Mixing`), [`NO_STEP`] for none.
    mix: u32,
}

/// `DabSpec::mix` of a dab that lays its own colour.
const NO_STEP: u32 = u32::MAX;

/// A mixing brush's step as the app hands one over, field by field
/// `Step`'s.
#[repr(C)]
pub struct StepSpec {
    centre: [f64; 2],
    radius: f64,
    refill: f64,
    laid: f64,
    density: f64,
    take: f64,
    share: f64,
    pick: f64,
    /// Red, green, blue, alpha, from the low byte.
    colour: u32,
    /// 1 for a dry brush.
    dry: u32,
}

impl StepSpec {
    fn step(&self) -> Step {
        Step {
            centre: self.centre,
            radius: self.radius,
            colour: self.colour.to_le_bytes(),
            refill: self.refill,
            laid: self.laid,
            density: self.density,
            take: self.take,
            share: self.share,
            pick: self.pick,
            dry: self.dry != 0,
        }
    }
}

/// The profile `spec` names, if its tip is round.
///
/// # Safety
/// `coverage` and `pile` hold `entries` each where `coverage` is not null.
unsafe fn profile_of(spec: &DabSpec) -> Option<RoundProfile<'_>> {
    if spec.coverage.is_null() {
        return None;
    }
    // SAFETY: see the function's contract.
    let (coverage, pile) = unsafe {
        (
            std::slice::from_raw_parts(spec.coverage, spec.entries),
            std::slice::from_raw_parts(spec.pile, spec.entries),
        )
    };
    Some(RoundProfile {
        coverage,
        pile,
        scale: spec.scale,
        reach: spec.reach,
        inner: spec.inner,
        row_length: spec.row_length,
    })
}

/// `spec` as the kernel reads it, its round tip's tables `profile`.
///
/// # Safety
/// `texture` is live where it is not null, and `evening` holds its entries.
unsafe fn dab_of<'a>(spec: &'a DabSpec, profile: Option<&'a RoundProfile<'a>>) -> Dab<'a> {
    let shape = match (profile, spec.texture.is_null()) {
        (Some(profile), _) => Shape::Round(profile),
        // SAFETY: see the function's contract.
        (None, false) => Shape::Tip { texture: unsafe { &*spec.texture }, radius: spec.radius },
        (None, true) => Shape::Square,
    };
    let has = |flag| spec.flags & flag != 0;
    Dab {
        centre: spec.centre,
        region: spec.region,
        colour: spec.colour.to_le_bytes(),
        opacity: spec.opacity,
        flow: spec.flow,
        edge: if has(THRESHOLD) { Edge::Threshold } else { Edge::Contrast(spec.contrast) },
        edge_held: has(EDGE_HELD),
        erase: has(ERASE),
        second: has(SECOND),
        shape,
        turn: Turn { cos: spec.cos, sin: spec.sin, roundness: spec.roundness },
        evening: (!spec.evening.is_null())
            // SAFETY: see the function's contract.
            .then(|| unsafe { std::slice::from_raw_parts(spec.evening, EVENING_ENTRIES) }),
        density: has(PAPER).then_some(spec.density),
    }
}

/// What `use_them` makes of `specs` as the kernel reads them.
///
/// # Safety
/// A spec's tables, texture and evening are as `DabSpec` says.
unsafe fn with_dabs<T>(specs: &[DabSpec], use_them: impl FnOnce(&[Dab]) -> T) -> T {
    // SAFETY: see the function's contract.
    let profiles: Vec<Option<RoundProfile>> =
        specs.iter().map(|spec| unsafe { profile_of(spec) }).collect();
    let dabs: Vec<Dab> = specs
        .iter()
        .zip(&profiles)
        // SAFETY: see the function's contract.
        .map(|(spec, profile)| unsafe { dab_of(spec, profile.as_ref()) })
        .collect();
    use_them(&dabs)
}

/// What `use_them` makes of `count` blur dabs, each with its box radius.
///
/// # Safety
/// `dabs` holds `count`, each as `DabSpec` says, and `radii` `count`.
unsafe fn with_rubs<T>(
    dabs: *const DabSpec,
    radii: *const u32,
    count: usize,
    use_them: impl FnOnce(&[(Dab, u32)]) -> T,
) -> T {
    // SAFETY: see the function's contract.
    let (specs, radii) =
        unsafe { (std::slice::from_raw_parts(dabs, count), std::slice::from_raw_parts(radii, count)) };
    // SAFETY: see the function's contract.
    unsafe {
        with_dabs(specs, |dabs| {
            let rubs: Vec<(Dab, u32)> = dabs.iter().copied().zip(radii.iter().copied()).collect();
            use_them(&rubs)
        })
    }
}

/// A bitmap a dab reads — `side` texels a side, row after row, on 0..=1 —
/// kept for the piles that read it. Null where the texels don't make one;
/// see the last error.
///
/// # Safety
/// `texels` holds `side × side`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_dab_texture_new(texels: *const f64, side: u32) -> *mut Texture {
    // SAFETY: see the function's contract.
    let texels = unsafe { std::slice::from_raw_parts(texels, side as usize * side as usize) };
    Texture::new(texels, side).map_or(std::ptr::null_mut(), hands_bytes)
}

/// # Safety
/// `texture` came from `gpu_engine_dab_texture_new`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_dab_texture_free(texture: *mut Texture) {
    // SAFETY: see the function's contract.
    unsafe { let_go_bytes(texture) };
}

/// A stroke of no tiles, its kernels compiled. Null on failure; see the last
/// error.
///
/// # Safety
/// `engine` is live; the stroke is freed before it.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_stroke_new(engine: *const Engine) -> *mut Stroke {
    // SAFETY: see the function's contract.
    let engine = unsafe { &*engine };
    engine.on_thread(|| {
        Stroke::new(engine).map_or(std::ptr::null_mut(), |stroke| engine.hands(stroke))
    })
}

/// # Safety
/// `stroke` came from `gpu_engine_stroke_new`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_stroke_free(stroke: *mut Stroke) {
    // SAFETY: see the function's contract.
    unsafe { let_go(stroke) };
}

/// The bytes of `stroke`'s pages.
///
/// ⚠️Read where it is called: of a stroke at rest alone — cleared, which
/// waits for every pile handed over before (`gpu_engine_stroke_clear`), so
/// none writes its pages meanwhile (`gpu_engine_stroke_pile`).
///
/// # Safety
/// `stroke` is live, and no pile of it is on its way.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_stroke_bytes(stroke: *const Stroke) -> u64 {
    // SAFETY: see the function's contract.
    unsafe { &*stroke }.bytes()
}

/// Clears what `stroke` wrote and lets its tiles go; the pages stay.
///
/// # Safety
/// `stroke` and `engine` are live.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_stroke_clear(stroke: *mut Stroke, engine: *const Engine) {
    // SAFETY: see the function's contract.
    let (stroke, engine) = unsafe { (&mut *stroke, &*engine) };
    engine.on_thread(|| {
        stroke.clear(engine);
    })
}

/// Writes the column and row of each ground tile a mixing brush's `steps`,
/// `count` of them, read ([`ground_of`]) to `coordinates`, and gives how
/// many: the tiles the pile that runs them is told the cel's tile under
/// (`gpu_engine_stroke_pile`). Reckoned of the steps alone, where it is
/// called — no engine's turn is waited for.
///
/// # Safety
/// `steps` holds `count`; `coordinates` has room for 128 × `count` — a step
/// reads 64 tiles at most.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_mix_ground(
    steps: *const StepSpec,
    count: usize,
    coordinates: *mut i32,
) -> usize {
    // SAFETY: see the function's contract.
    let specs = unsafe { std::slice::from_raw_parts(steps, count) };
    let steps: Vec<Step> = specs.iter().map(StepSpec::step).collect();
    let ground = ground_of(&steps);
    // SAFETY: see the function's contract.
    unsafe { written(&ground, coordinates) };
    ground.len()
}

/// Writes the column and row of each tile the blur of `dabs` reads, each at
/// its box radius of `radii`, `count` of them ([`ground_of_rubs`]), to
/// `coordinates` where it has room for them — `room` tiles — and gives how
/// many there are: the tiles a rub is told the cel's tile under
/// (`gpu_engine_stroke_rub`). -1 where a radius is none; see the last
/// error. Reckoned of the dabs alone, where it is called — no engine's turn
/// is waited for.
///
/// # Safety
/// `dabs` holds `count`, each as `DabSpec` says, and `radii` `count`;
/// `coordinates` has room for 2 × `room`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_rub_ground(
    dabs: *const DabSpec,
    radii: *const u32,
    count: usize,
    coordinates: *mut i32,
    room: usize,
) -> isize {
    // SAFETY: see the function's contract.
    let ground = unsafe { with_rubs(dabs, radii, count, ground_of_rubs) };
    let Some(ground) = ground else {
        return -1;
    };
    if ground.len() <= room {
        // SAFETY: see the function's contract.
        unsafe { written(&ground, coordinates) };
    }
    ground.len() as isize
}

/// Writes `tiles`, column then row each, to `coordinates`.
///
/// # Safety
/// `coordinates` has room for 2 × `tiles.len()`.
unsafe fn written(tiles: &[(i32, i32)], coordinates: *mut i32) {
    // SAFETY: see the function's contract.
    let out = unsafe { std::slice::from_raw_parts_mut(coordinates, 2 * tiles.len()) };
    for (&(column, row), at) in tiles.iter().zip(out.chunks_exact_mut(2)) {
        at.copy_from_slice(&[column, row]);
    }
}

/// The cel's tile under each of the `count` coordinates the app told of —
/// `coordinates` their column and row, `under` the cel's tile at each as a
/// tile set names one — by coordinate, each where it lies on `pool` as it
/// stands here (`Lying::of_word`): what a mixing step or a rub reads the
/// cel by, on the engine's thread, after its caller has gone on.
///
/// # Safety
/// `coordinates` holds 2 × `count`, and `under` `count`.
unsafe fn told_of(
    coordinates: *const i32,
    under: *const u32,
    count: usize,
    pool: &Pool,
) -> HashMap<(i32, i32), Option<TileAt>> {
    let lying = pool.lying();
    // SAFETY: see the function's contract.
    let (coordinates, under) = unsafe {
        (std::slice::from_raw_parts(coordinates, 2 * count), std::slice::from_raw_parts(under, count))
    };
    coordinates
        .chunks_exact(2)
        .zip(under)
        .map(|(at, &word)| ((at[0], at[1]), lying.of_word(word)))
        .collect()
}

/// Piles `dabs`, `count` of them, in their order, over the paper — `paper`,
/// null for none, at `paper_scale` px a texel, 高さ where `paper_height` —
/// with a second tip shown by `second_mode` at `second_density` where that
/// is not -1. Where `under` is not null the pile is a mixing brush's: its
/// `steps`, `step_count` of them, `first` the first's place in the stroke's
/// chain, are handed to the stroke (`Stroke::hand_steps`) and run first —
/// over the cel's tile under each ground tile they read, which `ground`
/// coordinates tell of (`coordinates` their column and row, `under` the
/// cel's tile at each as a tile set names one, the app reckoning them by
/// `gpu_engine_mix_ground`), on `pool`'s pages copied by `composite` — and
/// colour each dab whose `mix` names one: `Stroke::pile_mixed`. Handed to
/// the engine's thread, its caller waiting for none of it
/// ([`Engine::posted`]) — the dabs, their tables and textures, the paper,
/// the steps and the ground copied here first ([`Piled`]). A pile that
/// fails is told by what reads the stroke next (`Stroke::refuse`).
///
/// 🚨WHY UNWAITED (card a-stroke-step-waits-for-the-engines-turn,
/// 2026-11-18): a pile is a stroke's step, and the UI's thread waited for
/// each — 🔬41 piles of a stroke on S5_BA cut 352, 31–99 ms all told, 57 of
/// the 99 in line behind the band's fill on the engine's thread (the
/// lent-wait probe, k1305): what grows as the engine is busy is the wait
/// for the turn, not the pile. ↩️A mixing brush's steps were handed by a
/// call of their own that answered the tiles they read, and each step of
/// its stroke waited for the engine's turn there — 🔬41 of a stroke, 3–54
/// ms all told, 2 of them running (k1377).
///
/// # Safety
/// `stroke` and `engine` are live, the stroke made on it and let go of
/// after this (`gpu_engine_stroke_free`); `dabs` holds `count`, each as
/// `DabSpec` says; `paper` is live or null; where `under` is not null it
/// and `coordinates` hold `ground` (`coordinates` two words each),
/// `steps` holds `step_count`, and `composite` and `pool` are live, on
/// `engine`, and let go of after this.
#[unsafe(no_mangle)]
#[allow(clippy::too_many_arguments)]
pub unsafe extern "C" fn gpu_engine_stroke_pile(
    stroke: *mut Stroke,
    engine: *const Engine,
    dabs: *const DabSpec,
    count: usize,
    paper: *const Texture,
    paper_scale: f64,
    paper_height: bool,
    second_mode: i32,
    second_density: f64,
    steps: *const StepSpec,
    step_count: usize,
    first: u32,
    composite: *const Composite,
    pool: *const Pool,
    coordinates: *const i32,
    under: *const u32,
    ground: usize,
) {
    // SAFETY: see the function's contract.
    let (engine, specs) = unsafe { (&*engine, std::slice::from_raw_parts(dabs, count)) };
    // SAFETY: see the function's contract.
    let piled = unsafe { piled(specs) };
    // SAFETY: see the function's contract.
    let paper = (!paper.is_null()).then(|| unsafe { &*paper }.clone());
    let second = (second_mode != -1).then_some((second_mode as u32, second_density));
    let colours: Vec<(usize, u32)> = specs
        .iter()
        .enumerate()
        .filter(|(_, spec)| spec.mix != NO_STEP)
        .map(|(index, spec)| (index, spec.mix))
        .collect();
    // The steps, the cel's tiles under the ground they read, and the pool's
    // pages as they stand here — the pool is its caller's, who goes on
    // (`Pool::lands_unwaited`).
    // SAFETY: see the function's contract.
    let mixing = (!under.is_null()).then(|| unsafe {
        let steps: Vec<Step> =
            std::slice::from_raw_parts(steps, step_count).iter().map(StepSpec::step).collect();
        (steps, told_of(coordinates, under, ground, &*pool), (*pool).pages().to_vec())
    });
    let handed = Sent((engine.clone(), stroke, piled, paper, mixing, composite));
    engine.posted(move || {
        let (engine, stroke, piled, paper, mixing, composite) = handed.taken();
        // SAFETY: let go of on this thread, after this (the contract); and
        // nothing reads it elsewhere while a pile is on its way
        // (`gpu_engine_stroke_bytes`).
        let stroke = unsafe { &mut *stroke };
        let paper = paper.as_ref().map(|texture| Paper { texture, scale: paper_scale, height: paper_height });
        let ground = match &mixing {
            None => None,
            Some((steps, told, pages)) => match under_steps(stroke, steps, first, told) {
                Some(under) => Some((under, pages)),
                None => {
                    stroke.refuse(take_last_error());
                    return Some(());
                }
            },
        };
        let mixed = ground.as_ref().map(|(under, pages)| {
            // SAFETY: let go of on this thread, after this (the contract).
            let executor = unsafe { &*composite };
            (Ground { executor, pages, under }, colours.as_slice())
        });
        // SAFETY: the specs point at what `piled` holds.
        let piled = unsafe {
            with_dabs(&piled.specs, |dabs| stroke.pile_mixed(&engine, dabs, paper.as_ref(), second, mixed))
        };
        if piled.is_none() {
            stroke.refuse(take_last_error());
        }
        Some(())
    });
}

/// The cel's tile under each ground tile a mixing brush's `steps` read —
/// `first` the first's place in the stroke's chain — as `told` tells of
/// it, the steps handed to `stroke` to run with its pile
/// (`Stroke::hand_steps`). None where they are refused, or read a tile it
/// was told nothing of.
fn under_steps(
    stroke: &mut Stroke,
    steps: &[Step],
    first: u32,
    told: &HashMap<(i32, i32), Option<TileAt>>,
) -> Option<Vec<Option<TileAt>>> {
    if steps.is_empty() {
        return Some(Vec::new());
    }
    let read = stroke.hand_steps(steps, first)?;
    read.iter()
        .map(|at| told.get(at).copied())
        .collect::<Option<_>>()
        .or_else(|| fail("a mixing step read a tile it was told nothing of"))
}

/// What a pile is handed, its own: the dabs as specs, each table and
/// texture they name copied once — a table two dabs share comes at one
/// address, and is copied once — and the specs pointing at the copies. A
/// pile handed over unwaited runs after the app has let its arena go, and
/// may after it has freed a texture ([`Texture`]'s copy is a count).
struct Piled {
    specs: Vec<DabSpec>,
    _tables: Vec<Box<[f64]>>,
    _textures: Vec<Box<Texture>>,
}

/// `specs` as [`Piled`] holds them.
///
/// # Safety
/// A spec's tables, texture and evening are as `DabSpec` says.
unsafe fn piled(specs: &[DabSpec]) -> Piled {
    let mut tables: HashMap<*const f64, Box<[f64]>> = HashMap::new();
    let mut own = |at: *const f64, entries: usize| -> *const f64 {
        // SAFETY: a table is as `DabSpec` says (the function's contract).
        let copied = || unsafe { std::slice::from_raw_parts(at, entries) }.into();
        tables.entry(at).or_insert_with(copied).as_ptr()
    };
    let mut specs = specs.to_vec();
    for spec in &mut specs {
        if !spec.coverage.is_null() {
            spec.coverage = own(spec.coverage, spec.entries);
            spec.pile = own(spec.pile, spec.entries);
        }
        if !spec.evening.is_null() {
            spec.evening = own(spec.evening, EVENING_ENTRIES);
        }
    }
    let mut textures: HashMap<*const Texture, Box<Texture>> = HashMap::new();
    for spec in specs.iter_mut().filter(|spec| !spec.texture.is_null()) {
        let at = spec.texture;
        // SAFETY: a texture is live (the function's contract).
        let copied = || Box::new(unsafe { &*at }.clone());
        spec.texture = std::ptr::from_ref(&**textures.entry(at).or_insert_with(copied));
    }
    Piled { specs, _tables: tables.into_values().collect(), _textures: textures.into_values().collect() }
}

/// Writes the colour each of `stroke`'s first `count` mixing steps laid,
/// ARGB, to `out`: `Stroke::mixed`, read back. False on failure; see the
/// last error.
///
/// # Safety
/// `stroke` and `engine` are live, the stroke made on it; `out` has room
/// for `count`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_stroke_mixed(
    stroke: *const Stroke,
    engine: *const Engine,
    out: *mut u32,
    count: usize,
) -> bool {
    // SAFETY: see the function's contract.
    let (stroke, engine) = unsafe { (&*stroke, &*engine) };
    engine.on_thread(|| {
        let Some(colours) = stroke.mixed(engine, count) else {
            return false;
        };
        // SAFETY: see the function's contract.
        unsafe { std::slice::from_raw_parts_mut(out, count) }.copy_from_slice(&colours);
        true
    })
}

/// The blur brush's kernels, compiled — on any thread. Null on failure; see
/// the last error.
///
/// # Safety
/// `engine` is live; the kernels are freed before it.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_blurs_new(engine: *const Engine) -> *mut Blurs {
    // SAFETY: see the function's contract.
    let engine = unsafe { &*engine };
    engine.on_thread(|| {
        Blurs::new(engine).map_or(std::ptr::null_mut(), |blurs| engine.hands(blurs))
    })
}

/// Compiles the blur brush's strips' kernels, the engine's to keep
/// (`Blurs::compile_strips`) — on any thread. False on failure; see the
/// last error.
///
/// # Safety
/// `engine` is live.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_blurs_compile_strips(engine: *const Engine) -> bool {
    // SAFETY: see the function's contract.
    let engine = unsafe { &*engine };
    engine.on_thread(|| Blurs::compile_strips(engine).is_some())
}

/// Whether a stroke of `blurs` goes by strips: the engine has their
/// kernels (`Blurs::by_strips`).
///
/// # Safety
/// `blurs` is live.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_blurs_by_strips(blurs: *const Blurs) -> bool {
    // SAFETY: see the function's contract.
    unsafe { &*blurs }.by_strips()
}

/// # Safety
/// `blurs` came from `gpu_engine_blurs_new`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_blurs_free(blurs: *mut Blurs) {
    // SAFETY: see the function's contract.
    unsafe { let_go(blurs) };
}

/// The bytes `blurs` keeps between its strokes.
///
/// # Safety
/// `blurs` is live.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_blurs_bytes(blurs: *const Blurs) -> u64 {
    // SAFETY: see the function's contract.
    unsafe { &*blurs }.bytes()
}

/// Lets go of what `blurs` keeps between its strokes — buffers, so on
/// its engine's thread ([`on_thread_of`]).
///
/// # Safety
/// `blurs` is live.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_blurs_let_go(blurs: *mut Blurs) {
    // SAFETY: see the function's contract.
    unsafe { on_thread_of(blurs, || (*blurs).let_go()) };
}

/// Rubs `dabs`, `count` of them, each at its box radius of `radii`, into
/// `stroke`'s picture, over the paper — `paper`, null for none, at
/// `paper_scale` px a texel, 高さ where `paper_height` —: each tile their
/// blur reads that the stroke has not read yet made first of the cel's,
/// which `ground` coordinates tell of (`coordinates` their column and row,
/// `under` the cel's tile at each as a tile set names one, the app
/// reckoning them by `gpu_engine_rub_ground`), on `pool`'s pages copied by
/// `composite`: `Stroke::rub`. Handed to the engine's thread, its caller
/// waiting for none of it ([`Engine::posted`]) — the dabs, their tables and
/// textures, the radii, the paper and the ground copied here first
/// ([`Piled`]). A rub that fails is told by what reads the stroke next
/// (`Stroke::refuse`), as a pile's is.
///
/// ↩️Till 2026-11-18 a reach answered the tiles it met
/// (`gpu_engine_stroke_reach_blur`, `gpu_engine_stroke_met`), and the rub
/// that was handed the cel's tiles under them waited (`Stroke::rub` has
/// why it does not).
///
/// # Safety
/// `stroke` and `engine` are live, the stroke made on it and let go of
/// after this (`gpu_engine_stroke_free`); `blurs`, `composite` and `pool`
/// are live, on `engine`, and let go of after this; `coordinates` holds 2 ×
/// `ground` and `under` `ground`; `dabs` holds `count`, each as `DabSpec`
/// says, and `radii` `count`; `paper` is live or null.
#[unsafe(no_mangle)]
#[allow(clippy::too_many_arguments)]
pub unsafe extern "C" fn gpu_engine_stroke_rub(
    stroke: *mut Stroke,
    engine: *const Engine,
    blurs: *mut Blurs,
    composite: *const Composite,
    pool: *const Pool,
    coordinates: *const i32,
    under: *const u32,
    ground: usize,
    dabs: *const DabSpec,
    radii: *const u32,
    count: usize,
    paper: *const Texture,
    paper_scale: f64,
    paper_height: bool,
) {
    // SAFETY: see the function's contract.
    let (engine, specs, radii) = unsafe {
        (&*engine, std::slice::from_raw_parts(dabs, count), std::slice::from_raw_parts(radii, count).to_vec())
    };
    // SAFETY: see the function's contract.
    let piled = unsafe { piled(specs) };
    // SAFETY: see the function's contract.
    let paper = (!paper.is_null()).then(|| unsafe { &*paper }.clone());
    // SAFETY: see the function's contract.
    let told = unsafe { told_of(coordinates, under, ground, &*pool) };
    // The pool's pages as they stand here: the pool is its caller's, who
    // goes on (`Pool::lands_unwaited`).
    // SAFETY: see the function's contract.
    let pages = unsafe { (*pool).pages() }.to_vec();
    let handed = Sent((engine.clone(), stroke, blurs, composite, piled, radii, paper, told, pages));
    engine.posted(move || {
        let (engine, stroke, blurs, composite, piled, radii, paper, told, pages) = handed.taken();
        // SAFETY: each is let go of on this thread, after this (the
        // contract); and nothing reads the stroke elsewhere while a rub is
        // on its way (`gpu_engine_stroke_bytes`).
        let (stroke, blurs, composite) = unsafe { (&mut *stroke, &mut *blurs, &*composite) };
        let paper = paper.as_ref().map(|texture| Paper { texture, scale: paper_scale, height: paper_height });
        let tools = (blurs, composite, pages.as_slice());
        // SAFETY: the specs point at what `piled` holds.
        let rubbed = unsafe {
            with_dabs(&piled.specs, |dabs| {
                let rubs: Vec<(Dab, u32)> = dabs.iter().copied().zip(radii.iter().copied()).collect();
                stroke.rub(&engine, tools, &told, &rubs, paper.as_ref())
            })
        };
        if rubbed.is_none() {
            stroke.refuse(take_last_error());
        }
        Some(())
    });
}

/// Finishes `stroke`'s picture on the `count` tiles asked — `asks` their
/// column and row, `under` the cel's tile at each as a tile set names one —
/// by `opacity` under `mask` if not null, each result in a fresh slot of
/// `cel`: `Stroke::land_blur`. Reports as `gpu_engine_stroke_land` does.
///
/// # Safety
/// As `gpu_engine_stroke_land`.
#[unsafe(no_mangle)]
#[allow(clippy::too_many_arguments)]
pub unsafe extern "C" fn gpu_engine_stroke_land_blur(
    stroke: *const Stroke,
    engine: *const Engine,
    blurs: *const Blurs,
    composite: *const Composite,
    pool: *mut Pool,
    cel: u32,
    asks: *const i32,
    under: *const u32,
    count: usize,
    opacity: u32,
    mask: *const MaskPlane,
    compared: bool,
    places: *mut u32,
    changes: *mut u8,
) -> isize {
    // SAFETY: see the function's contract.
    let (stroke, engine, blurs, composite, pool) =
        unsafe { (&*stroke, &*engine, &*blurs, &*composite, &mut *pool) };
    engine.on_thread(|| {
        // SAFETY: see the function's contract.
        let asked = unsafe { asked_of(asks, under, count, &*pool) };
        // SAFETY: see the function's contract.
        let mask = unsafe { mask.as_ref() }.map(MaskPlane::mask);
        let cover = Cover { opacity, mask: mask.as_ref() };
        let kit = (blurs, composite, pool, Cel(cel));
        let landed = stroke.land_blur(engine, kit, &asked, cover, compared);
        // SAFETY: see the function's contract.
        unsafe { reported(landed, places, changes) }
    })
}

/// [`gpu_engine_stroke_land_blur`] uncompared — each result inked, in a
/// fresh slot — with no wait for the engine's turn: the places are booked
/// here and the picture finished in them on the engine's thread, behind the
/// rubs handed before it (`Stroke::made_blur`, `Pool::lands_unwaited`).
/// `told` is called from that thread with `number` and whether it put
/// them. Reports as [`gpu_engine_stroke_land`] does; the places given
/// a slot, the first of them.
///
/// 🚨WHY UNWAITED (card a-stroke-step-waits-for-the-engines-turn,
/// 2026-11-18): each step of a blur stroke lands what it shows — 🔬42
/// landings of a stroke on S5_BA cut 352, 24–41 ms of the UI's thread all
/// told (k1376); and once its rub is handed over, a landing that waits
/// waits for that rub too.
///
/// # Safety
/// As [`gpu_engine_stroke_land_blur`]'s, `stroke`, `blurs`, `composite` and
/// `mask` let go of after this; `told` is one any thread may call.
#[unsafe(no_mangle)]
#[allow(clippy::too_many_arguments)]
pub unsafe extern "C" fn gpu_engine_stroke_land_blur_unwaited(
    stroke: *const Stroke,
    engine: *const Engine,
    blurs: *const Blurs,
    composite: *const Composite,
    pool: *mut Pool,
    cel: u32,
    asks: *const i32,
    under: *const u32,
    count: usize,
    opacity: u32,
    mask: *const MaskPlane,
    places: *mut u32,
    changes: *mut u8,
    told: extern "C" fn(u64, bool),
    number: u64,
) -> isize {
    // SAFETY: see the function's contract.
    let asked = unsafe { asked_of(asks, under, count, &*pool) };
    // SAFETY: see the function's contract.
    let (engine, pool) = unsafe { (&*engine, &mut *pool) };
    let put = move |engine: &Engine, writing: &Writing| {
        // SAFETY: each is let go of on this thread, after this (the
        // function's contract).
        let (stroke, blurs, composite, mask) = unsafe { (&*stroke, &*blurs, &*composite, mask.as_ref()) };
        let mask = mask.map(MaskPlane::mask);
        let cover = Cover { opacity, mask: mask.as_ref() };
        let out = stroke.made_blur(engine, (blurs, composite, writing.pages()), &asked, cover)?;
        writing.put_from(engine, &out, 0..asked.len())
    };
    // SAFETY: what `put` holds is let go of on the engine's thread, after
    // it; `told` is one any thread may call (the function's contract).
    let given = unsafe { pool.lands_unwaited(engine, (Cel(cel), count), (told, number), put) };
    let landed = given.into_iter().map(|at| (Change::Inked, Some(at))).collect();
    // SAFETY: see the function's contract.
    unsafe { reported(Some(landed), places, changes) }
}

/// Lays `stroke` on the `count` tiles asked — `asks` their column and row,
/// `under` the cel's tile at each as a tile set names one — at `opacity` in
/// `mode`, under `mask` if not null, each result in a fresh slot of `cel`:
/// `Stroke::land`. Writes each one's `places` (a tile set's word) and
/// `changes` (0 the same, 1 inked, 2 cleared) and returns how many landed,
/// the first of them; -1 on failure, see the last error.
///
/// # Safety
/// Every pointer but `mask` is live, on `engine`; `asks` holds `2 × count`
/// and each of `under`, `places` and `changes` `count`.
#[unsafe(no_mangle)]
#[allow(clippy::too_many_arguments)]
pub unsafe extern "C" fn gpu_engine_stroke_land(
    stroke: *const Stroke,
    engine: *const Engine,
    composite: *const Composite,
    pool: *mut Pool,
    cel: u32,
    asks: *const i32,
    under: *const u32,
    count: usize,
    opacity: u32,
    mode: u32,
    mask: *const MaskPlane,
    compared: bool,
    places: *mut u32,
    changes: *mut u8,
) -> isize {
    // SAFETY: see the function's contract.
    let (stroke, engine, composite, pool) =
        unsafe { (&*stroke, &*engine, &*composite, &mut *pool) };
    engine.on_thread(|| {
        // SAFETY: see the function's contract.
        let asked = unsafe { asked_of(asks, under, count, &*pool) };
        // SAFETY: see the function's contract.
        let mask = unsafe { mask.as_ref() }.map(MaskPlane::mask);
        let laid = Laid { opacity, mode, mask: mask.as_ref() };
        let landed = stroke.land(engine, (composite, pool, Cel(cel)), &asked, &laid, compared);
        // SAFETY: see the function's contract.
        unsafe { reported(landed, places, changes) }
    })
}

/// [`gpu_engine_stroke_land`] unasked whether a result is the tile under
/// it — a stroke on its way, its frame waiting for nothing — with no wait
/// for its caller: the places are booked here, and the stroke's picture
/// over them made and put on the engine's thread ([`Pool::lands_unwaited`],
/// which says how `told` is called with `number`). Writes each one's
/// `places` and `changes` — inked, every one — and returns how many it gave
/// a slot, the first of them.
///
/// 🚨WHY UNWAITED (card a-stroke-step-waits-for-the-engines-turn,
/// 2026-11-18): each step of a stroke lands what it shows — 🔬42 landings
/// of a stroke on S5_BA cut 352, 20–34 ms all told (k1305); and once its
/// pile is handed over, a landing that waits waits for that pile too.
///
/// # Safety
/// As [`gpu_engine_stroke_land`]'s, `stroke`, `composite` and `mask` let go
/// of after this; `told` is one any thread may call.
#[unsafe(no_mangle)]
#[allow(clippy::too_many_arguments)]
pub unsafe extern "C" fn gpu_engine_stroke_land_unwaited(
    stroke: *const Stroke,
    engine: *const Engine,
    composite: *const Composite,
    pool: *mut Pool,
    cel: u32,
    asks: *const i32,
    under: *const u32,
    count: usize,
    opacity: u32,
    mode: u32,
    mask: *const MaskPlane,
    places: *mut u32,
    changes: *mut u8,
    told: extern "C" fn(u64, bool),
    number: u64,
) -> isize {
    // SAFETY: see the function's contract.
    let asked = unsafe { asked_of(asks, under, count, &*pool) };
    // SAFETY: see the function's contract.
    let (engine, pool) = unsafe { (&*engine, &mut *pool) };
    let put = move |engine: &Engine, writing: &Writing| {
        // SAFETY: each is let go of on this thread, after this (the
        // function's contract).
        let (stroke, composite, mask) = unsafe { (&*stroke, &*composite, mask.as_ref()) };
        let mask = mask.map(MaskPlane::mask);
        let laid = Laid { opacity, mode, mask: mask.as_ref() };
        let out = stroke.made(engine, (composite, writing.pages()), &asked, &laid)?;
        writing.put_from(engine, &out, 0..asked.len())
    };
    // SAFETY: what `put` holds is let go of on the engine's thread, after
    // it; `told` is one any thread may call (the function's contract).
    let given = unsafe { pool.lands_unwaited(engine, (Cel(cel), count), (told, number), put) };
    let landed = given.into_iter().map(|at| (Change::Inked, Some(at))).collect();
    // SAFETY: see the function's contract.
    unsafe { reported(Some(landed), places, changes) }
}

/// Lays the pool's tile set of `columns` × `rows` canvas tiles whose
/// top-left is column `x0`, row `y0` — `tiles` row by row, as
/// `gpu_engine_plan_set` takes them — on the `count` tiles asked as
/// [`gpu_engine_stroke_land`] says, at `opacity` in `mode`, under `mask` if
/// not null, each result in a fresh slot of `cel`, inked: a picture the
/// engine drew landed as a cel's own, with no wait for the GPU
/// (`landing::put` unasked). Returns as [`gpu_engine_stroke_land`] does.
///
/// 🚨A .CLIP VECTOR LAYER'S PICTURE IS NOT READ BACK (card
/// a-clip-vector-layer-is-read-back-to-be-tiled-again, 관제 2026-11-15:
/// 「리드백은 그때까지 쌓인 GPU 일 전부를 기다린다」 — 351–425 ms on the
/// Surface Pro 11, 5–7 on the main PC): its strokes' tiles go through the
/// layer's alpha and mask here, where they lie. ↩️Till 2026-11-16 they were
/// read back whole, cut into a canvas of RGBA on a worker, masked there and
/// cut into tiles again to be stored.
///
/// # Safety
/// As [`gpu_engine_stroke_land`]'s; `tiles` holds `columns × rows` words,
/// each naming a slot of `pool`'s or none.
#[unsafe(no_mangle)]
#[allow(clippy::too_many_arguments)]
pub unsafe extern "C" fn gpu_engine_tiles_land(
    engine: *const Engine,
    composite: *const Composite,
    pool: *mut Pool,
    cel: u32,
    x0: i32,
    y0: i32,
    columns: u32,
    rows: u32,
    tiles: *const u32,
    asks: *const i32,
    under: *const u32,
    count: usize,
    opacity: u32,
    mode: u32,
    mask: *const MaskPlane,
    places: *mut u32,
    changes: *mut u8,
) -> isize {
    // SAFETY: see the function's contract.
    let (engine, composite, pool, words) = unsafe {
        let words = std::slice::from_raw_parts(tiles, columns as usize * rows as usize);
        (&*engine, &*composite, &mut *pool, words)
    };
    engine.on_thread(|| {
        // SAFETY: see the function's contract.
        let asked = unsafe { asked_of(asks, under, count, &*pool) };
        // SAFETY: see the function's contract.
        let mask = unsafe { mask.as_ref() }.map(MaskPlane::mask);
        let laid = Laid { opacity, mode, mask: mask.as_ref() };
        // The set names the pool's own slots: the plan's pages are the
        // pool's, and none come after them.
        let set = Named::from_words(x0, y0, columns, rows, words).lying(&pool.lying());
        let over = Over { pages: &[], set };
        let landed = if asked.is_empty() {
            Some(Vec::new())
        } else {
            landing::land(engine, (composite, pool, Cel(cel)), over, &asked, &laid, None)
        };
        // SAFETY: see the function's contract.
        unsafe { reported(landed, places, changes) }
    })
}


/// The tiles a landing is asked: `asks` their column and row, `under` the
/// cel's tile at each as a tile set names one — read to where it lies on
/// `pool` (`Lying::of_word`).
///
/// # Safety
/// `asks` holds `2 × count` and `under` `count`.
unsafe fn asked_of(asks: *const i32, under: *const u32, count: usize, pool: &Pool) -> Vec<Asked> {
    let lying = pool.lying();
    // SAFETY: see the function's contract.
    let (asks, under) = unsafe {
        (std::slice::from_raw_parts(asks, 2 * count), std::slice::from_raw_parts(under, count))
    };
    asks.chunks_exact(2)
        .zip(under)
        .map(|(tile, &word)| Asked { column: tile[0], row: tile[1], under: lying.of_word(word) })
        .collect()
}

/// Writes each landed tile's `places` and `changes`, and returns how many
/// landed; -1 where the landing failed.
///
/// # Safety
/// `places` and `changes` hold as many as were asked, and no more land.
pub(crate) unsafe fn reported(
    landed: Option<Vec<(Change, Option<TileAt>)>>,
    places: *mut u32,
    changes: *mut u8,
) -> isize {
    let Some(landed) = landed else {
        return -1;
    };
    for (at, (change, place)) in landed.iter().enumerate() {
        // SAFETY: see the function's contract.
        unsafe {
            *places.add(at) = place.map_or(NO_TILE, TileAt::word);
            *changes.add(at) = byte_of(*change);
        }
    }
    landed.len() as isize
}

/// A change as the app reads one: 0 the same, 1 inked, 2 cleared.
fn byte_of(change: Change) -> u8 {
    match change {
        Change::Same => 0,
        Change::Inked => 1,
        Change::Cleared => 2,
    }
}

/// A stamp's picture kept on the GPU: a selection moved lands the same one
/// at each step of the drag, its upload once.
pub struct StampPicture {
    pixels: wgpu::Buffer,
    size: (u32, u32),
}

/// The bytes of every stamp's picture the app keeps, counted where they are
/// made and let go, for the memory census.
static STAMP_PICTURE_BYTES: AtomicU64 = AtomicU64::new(0);

/// A picture of `width` × `height` straight RGBA8 pixels at `rgba`, row
/// after row. Null where it holds no pixel; see the last error.
///
/// # Safety
/// `engine` is live and `rgba` holds `width × height × 4`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_stamp_picture_new(
    engine: *const Engine,
    rgba: *const u8,
    width: u32,
    height: u32,
) -> *mut StampPicture {
    if width == 0 || height == 0 {
        fail::<()>(format!("a picture of {width}x{height} holds no pixel"));
        return std::ptr::null_mut();
    }
    let bytes = u64::from(width) * u64::from(height) * 4;
    // SAFETY: see the function's contract.
    let (engine, rgba) = unsafe { (&*engine, std::slice::from_raw_parts(rgba, bytes as usize)) };
    engine.on_thread(|| {
        let pixels = engine.filled(
            "stamp picture",
            rgba,
            wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
        );
        kept(engine, Some(pixels), (width, height))
    })
}

/// `picture` carried through `inverse` — an output's point to `picture`'s,
/// row-major with the homogeneous row last, a pixel spanning x..x+1 (the
/// app's `ResampleTransform`) — over an output `columns` × `rows`, by R1
/// with `radius_floor`, sampled as `sampling_id` names ([`sampling`]): a
/// new picture of the output's `width` × `height` from (`left`, `top`) —
/// the whole of it, or what of it shows — which lands as any other does
/// (`StampLanding::carried`). A window keeps the whole's map, so what it
/// holds is the whole's pixels there. Nothing of it where the map lands
/// nothing ([`ResampleMap::new`]). Submits the warp; what lands the
/// picture, or reads it, waits. Null where it holds no pixel, the window
/// lies past the output, no mode has the id or the device binds no such
/// picture; see the last error.
///
/// # Safety
/// `landing`, `engine` and `picture` are live and `inverse` holds nine
/// doubles.
#[unsafe(no_mangle)]
#[allow(clippy::too_many_arguments)]
pub unsafe extern "C" fn gpu_engine_stamp_picture_carried(
    landing: *const StampLanding,
    engine: *const Engine,
    picture: *const StampPicture,
    inverse: *const f64,
    radius_floor: f64,
    sampling_id: u32,
    columns: u32,
    rows: u32,
    left: u32,
    top: u32,
    width: u32,
    height: u32,
) -> *mut StampPicture {
    // SAFETY: see the function's contract.
    let (landing, engine, picture, inverse) =
        unsafe { (&*landing, &*engine, &*picture, *inverse.cast::<[f64; 9]>()) };
    engine.on_thread(|| {
        let Some(sampled) = sampling(sampling_id) else {
            return std::ptr::null_mut();
        };
        if u64::from(left) + u64::from(width) > u64::from(columns)
            || u64::from(top) + u64::from(height) > u64::from(rows)
        {
            let past = format!("a window of {width}x{height} at ({left}, {top}) past an output of {columns}x{rows}");
            fail::<()>(past);
            return std::ptr::null_mut();
        }
        let map = ResampleMap::new(inverse, radius_floor, sampled, columns, rows);
        let boxed = Boxed { pixels: &picture.pixels, size: picture.size };
        let window = Window { at: (left as i32, top as i32), size: (width, height) };
        kept(engine, landing.carried(engine, &boxed, map.as_ref(), window), (width, height))
    })
}

/// `picture`, its top-left pixel at (`source_left`, `source_top`) on the
/// canvas, through a mesh of `columns` × `rows` cells whose corners rest at
/// `source` and were dragged to `destination` — `(columns + 1) · (rows +
/// 1)` points each, row after row, an x and a y apiece in canvas pixels —
/// by R1 with `radius_floor`, sampled as `sampling_id` names: a new picture
/// of the canvas's `width` × `height` from (`left`, `top`), each pixel by
/// the map of the triangle that paints it and nothing where none does
/// (`StampLanding::meshed`, R3). Submits the warp; what lands the picture,
/// or reads it, waits. Null where it holds no pixel, a point or the window
/// is past R3's reach, no mode has the id or the device binds no such
/// picture; see the last error.
///
/// # Safety
/// `landing`, `engine` and `picture` are live, and `source` and
/// `destination` hold `2 · (columns + 1) · (rows + 1)` doubles each.
#[unsafe(no_mangle)]
#[allow(clippy::too_many_arguments)]
pub unsafe extern "C" fn gpu_engine_stamp_picture_meshed(
    landing: *const StampLanding,
    engine: *const Engine,
    picture: *const StampPicture,
    source_left: f64,
    source_top: f64,
    columns: u32,
    rows: u32,
    source: *const f64,
    destination: *const f64,
    radius_floor: f64,
    sampling_id: u32,
    left: i32,
    top: i32,
    width: u32,
    height: u32,
) -> *mut StampPicture {
    let points = (columns as usize + 1) * (rows as usize + 1);
    // SAFETY: see the function's contract.
    let (landing, engine, picture, source, destination) = unsafe {
        (
            &*landing,
            &*engine,
            &*picture,
            std::slice::from_raw_parts(source.cast::<[f64; 2]>(), points),
            std::slice::from_raw_parts(destination.cast::<[f64; 2]>(), points),
        )
    };
    engine.on_thread(|| {
        let Some(sampled) = sampling(sampling_id) else {
            return std::ptr::null_mut();
        };
        let mesh = MeshGrid { columns, rows, source: source.to_vec(), destination: destination.to_vec() };
        let boxed = Boxed { pixels: &picture.pixels, size: picture.size };
        let window = Window { at: (left, top), size: (width, height) };
        let at = (source_left, source_top);
        let made = landing.meshed(engine, &mesh, (&boxed, at), window, (radius_floor, sampled));
        kept(engine, made, (width, height))
    })
}

/// A picture of `pixels`, `size` across and down and of `engine`, counted
/// — or null where none was made.
pub(crate) fn kept(engine: &Engine, pixels: Option<wgpu::Buffer>, size: (u32, u32)) -> *mut StampPicture {
    let Some(pixels) = pixels else {
        return std::ptr::null_mut();
    };
    let counted = Counted::among(&STAMP_PICTURE_BYTES, pixels.size());
    engine.hands_counted(StampPicture { pixels, size }, counted)
}

/// `picture`'s pixels at `into`, row after row, once the GPU has made them:
/// what the app asks of a picture whose bytes it never held (a carried
/// one's). False on failure; see the last error.
///
/// # Safety
/// `engine` and `picture` are live, and `into` holds the picture's
/// `width × height × 4`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_stamp_picture_read(
    engine: *const Engine,
    picture: *const StampPicture,
    into: *mut u8,
) -> bool {
    // SAFETY: see the function's contract.
    let (engine, picture) = unsafe { (&*engine, &*picture) };
    engine.on_thread(|| {
        let Some(read) = engine.read_buffer(&picture.pixels) else {
            return false;
        };
        // SAFETY: see the function's contract; a picture's buffer is its box.
        unsafe { std::ptr::copy_nonoverlapping(read.as_ptr(), into, read.len()) };
        true
    })
}

/// # Safety
/// `picture` came from `gpu_engine_stamp_picture_new`,
/// `gpu_engine_stamp_picture_carried` or `gpu_engine_stamp_picture_meshed`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_stamp_picture_free(picture: *mut StampPicture) {
    // SAFETY: see the function's contract.
    unsafe { let_go_unwaited(picture) };
}

/// The bytes of every stamp's picture the app keeps.
#[unsafe(no_mangle)]
pub extern "C" fn gpu_engine_stamp_picture_bytes() -> u64 {
    STAMP_PICTURE_BYTES.load(Ordering::Relaxed)
}

/// What lands a stamp on a cel, its kernels compiled. Null on failure; see
/// the last error.
///
/// # Safety
/// `engine` is live; the landing is freed before it.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_stamp_landing_new(engine: *const Engine) -> *mut StampLanding {
    // SAFETY: see the function's contract.
    let engine = unsafe { &*engine };
    engine.on_thread(|| {
        StampLanding::new(engine).map_or(std::ptr::null_mut(), |landing| engine.hands(landing))
    })
}

/// # Safety
/// `landing` came from `gpu_engine_stamp_landing_new`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_stamp_landing_free(landing: *mut StampLanding) {
    // SAFETY: see the function's contract.
    unsafe { let_go(landing) };
}

/// Lays `picture`, its top-left pixel at (`left`, `top`), what of it lies
/// `within` the canvas's [left, top, right, bottom), on the `count` tiles
/// asked as [`gpu_engine_stroke_land`] says, compared: at `opacity` in
/// `mode`, under `mask` if not null. Returns as it does.
///
/// # Safety
/// As [`gpu_engine_stroke_land`]'s, `picture` live on `engine` and `within`
/// holding four.
#[unsafe(no_mangle)]
#[allow(clippy::too_many_arguments)]
pub unsafe extern "C" fn gpu_engine_stamp_land(
    landing: *const StampLanding,
    engine: *const Engine,
    composite: *const Composite,
    pool: *mut Pool,
    cel: u32,
    picture: *const StampPicture,
    left: i32,
    top: i32,
    within: *const i32,
    asks: *const i32,
    under: *const u32,
    count: usize,
    opacity: u32,
    mode: u32,
    mask: *const MaskPlane,
    places: *mut u32,
    changes: *mut u8,
) -> isize {
    // SAFETY: see the function's contract.
    let (landing, engine, composite, pool, picture, within) = unsafe {
        (&*landing, &*engine, &*composite, &mut *pool, &*picture, *within.cast::<[i32; 4]>())
    };
    engine.on_thread(|| {
        // SAFETY: see the function's contract.
        let asked = unsafe { asked_of(asks, under, count, &*pool) };
        // SAFETY: see the function's contract.
        let mask = unsafe { mask.as_ref() }.map(MaskPlane::mask);
        let laid = Laid { opacity, mode, mask: mask.as_ref() };
        let boxed = Boxed { pixels: &picture.pixels, size: picture.size };
        let source = Source::Picture { picture: &boxed, at: (left, top), within };
        let landed = landing.land(engine, (composite, pool, Cel(cel)), &source, &asked, &laid);
        // SAFETY: see the function's contract.
        unsafe { reported(landed, places, changes) }
    })
}

/// What a finish is told by: its landing finished, or nothing.
type Then = Box<dyn FnOnce(Option<Finished>) + Send>;

/// The body a finish hands the engine's thread: `finish` run there on
/// `pool`'s pages as they stand now — where the cel's tiles lay as it was
/// asked, whatever a store or a fold makes of the pool meanwhile —, and
/// what it is told handed out by `engine` to `out`, then `told` called
/// with `number` and whether there is one.
///
/// ⛔Not a body that failed, whatever it finished: its caller's next done
/// would fail by it (`Engine::posted`) — a screen's frame, for a cut
/// ahead that landed nothing. `told` says it.
///
/// # Safety
/// What `finish` holds is alive, and in no other thread's hands, till it
/// has run; `out` is live till `told` is called, and `told` is one any
/// thread may call.
unsafe fn finishing<Finish>(
    engine: &Engine,
    pool: &Pool,
    (out, told, number): (*mut *mut Finished, extern "C" fn(u64, bool), u64),
    finish: Finish,
) -> impl FnOnce() -> Option<()> + Send + 'static + use<Finish>
where
    Finish: FnOnce(&Engine, &[wgpu::Buffer], Then) + 'static,
{
    let handed = Sent((engine.clone(), pool.pages().to_vec(), out, finish));
    move || {
        let (engine, pages, out, finish) = handed.taken();
        let (hands, out) = (engine.clone(), Sent(out));
        let then = move |finished: Option<Finished>| {
            let finished = finished.map(|finished| hands.hands(finished));
            // SAFETY: live till `told` is called (the function's contract).
            unsafe { *out.taken() = finished.unwrap_or(std::ptr::null_mut()) };
            told(number, finished.is_some());
        };
        finish(&engine, &pages, Box::new(then));
        Some(())
    }
}

/// [`gpu_engine_stamp_land`] as far as it asks the GPU, with no wait for
/// its caller and no slot taken: `picture` laid on the `count` tiles asked
/// over the cel's as `pool` holds them now, and what each result is beside
/// the tile under it asked on the engine's thread, which waits for none of
/// it either (`StampLanding::finished_then`). `told` is called with
/// `number` from a thread of the engine's once the GPU has said, `out`
/// written first: the landing finished — its caller's to land
/// ([`gpu_engine_finished_land_unwaited`]) and to free — or null, and
/// `told` false, where it failed or no tile was asked.
///
/// 🚨WHY UNWAITED (card opening-a-transform-box-holds-the-ui-over-half-a-
/// second, 2026-11-20): a box at rest cuts the cels it frames ahead of the
/// press, a cel a turn of the UI's thread — and each turn stood for the
/// GPU: the lift's word, the hole's compare and the float's, 🔬4 to 18 ms
/// a turn and 31 to 63 with the GPU's queue full (공통, S5_BA cut 352,
/// 메인 PC 테스트 VM). A cut ahead waits for nothing: it is told.
///
/// # Safety
/// As [`gpu_engine_stamp_land`]'s, `landing`, `composite`, `picture` and
/// `mask` let go of after this; `out` is live till `told` is called, and
/// `told` is one any thread may call.
#[unsafe(no_mangle)]
#[allow(clippy::too_many_arguments)]
pub unsafe extern "C" fn gpu_engine_stamp_finish_unwaited(
    landing: *const StampLanding,
    engine: *const Engine,
    composite: *const Composite,
    pool: *const Pool,
    picture: *const StampPicture,
    left: i32,
    top: i32,
    within: *const i32,
    asks: *const i32,
    under: *const u32,
    count: usize,
    opacity: u32,
    mode: u32,
    mask: *const MaskPlane,
    out: *mut *mut Finished,
    told: extern "C" fn(u64, bool),
    number: u64,
) {
    // SAFETY: see the function's contract.
    let (engine, pool, within) = unsafe { (&*engine, &*pool, *within.cast::<[i32; 4]>()) };
    // SAFETY: see the function's contract.
    let asked = unsafe { asked_of(asks, under, count, pool) };
    let finish = move |engine: &Engine, pages: &[wgpu::Buffer], then: Then| {
        // SAFETY: each is let go of on this thread, after this (the
        // function's contract).
        let (landing, composite, picture, mask) = unsafe { (&*landing, &*composite, &*picture, mask.as_ref()) };
        let mask = mask.map(MaskPlane::mask);
        let laid = Laid { opacity, mode, mask: mask.as_ref() };
        let boxed = Boxed { pixels: &picture.pixels, size: picture.size };
        let source = Source::Picture { picture: &boxed, at: (left, top), within };
        landing.finished_then(engine, (composite, pages), &source, &asked, &laid, then);
    };
    // SAFETY: what `finish` holds is let go of on the engine's thread,
    // after it; `out` and `told` are the function's contract.
    engine.posted(unsafe { finishing(engine, pool, (out, told, number), finish) });
}

/// [`gpu_engine_stamp_finish_unwaited`] of `coverage` under `paint`, as
/// [`gpu_engine_stamp_land_mask`] lays one: a selection's erase, its own
/// mask laid by the eraser. False where the paint is none the host knows
/// (the last error says): nothing is handed over, and `told` is not
/// called.
///
/// # Safety
/// As [`gpu_engine_stamp_land_mask`]'s, `landing`, `composite`, `coverage`
/// and `mask` let go of after this; `out` is live till `told` is called,
/// and `told` is one any thread may call.
#[unsafe(no_mangle)]
#[allow(clippy::too_many_arguments)]
pub unsafe extern "C" fn gpu_engine_stamp_finish_mask_unwaited(
    landing: *const StampLanding,
    engine: *const Engine,
    composite: *const Composite,
    pool: *const Pool,
    coverage: *const MaskPlane,
    paint: *const f64,
    whole: bool,
    asks: *const i32,
    under: *const u32,
    count: usize,
    opacity: u32,
    mode: u32,
    mask: *const MaskPlane,
    out: *mut *mut Finished,
    told: extern "C" fn(u64, bool),
    number: u64,
) -> bool {
    // SAFETY: see the function's contract.
    let (engine, pool) = unsafe { (&*engine, &*pool) };
    // SAFETY: see the function's contract.
    let Some(painted) = (unsafe { PaintOf::read(paint) }) else {
        return false;
    };
    // SAFETY: see the function's contract.
    let asked = unsafe { asked_of(asks, under, count, pool) };
    let finish = move |engine: &Engine, pages: &[wgpu::Buffer], then: Then| {
        // SAFETY: each is let go of on this thread, after this (the
        // function's contract).
        let (landing, composite, coverage, mask) = unsafe { (&*landing, &*composite, &*coverage, mask.as_ref()) };
        let coverage = coverage.mask();
        let mask = mask.map(MaskPlane::mask);
        let laid = Laid { opacity, mode, mask: mask.as_ref() };
        let paint = painted.paint();
        let source = Source::Mask { mask: &coverage, paint: &paint, whole };
        landing.finished_then(engine, (composite, pages), &source, &asked, &laid, then);
    };
    // SAFETY: what `finish` holds is let go of on the engine's thread,
    // after it; `out` and `told` are the function's contract.
    engine.posted(unsafe { finishing(engine, pool, (out, told, number), finish) });
    true
}

/// Writes what each tile of `finished` is to `changes` — a byte each, in
/// the order they were asked ([`byte_of`]) — and returns how many.
///
/// # Safety
/// `finished` is live, and `changes` holds as many as were asked; a null
/// `changes` holds none, which a caller that only counts hands.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_finished_changes(finished: *const Finished, changes: *mut u8) -> usize {
    // SAFETY: see the function's contract.
    let said = unsafe { &*finished }.changes();
    if !changes.is_null() {
        for (at, &change) in said.iter().enumerate() {
            // SAFETY: see the function's contract.
            unsafe { *changes.add(at) = byte_of(change) };
        }
    }
    said.len()
}

/// Gives each inked tile of `finished` from its `first` on — the inked
/// alone take a slot, as a landing compared gives one to no other
/// (`landing::placed`) — a fresh slot of `cel`, writes each one's place to
/// `places`, and hands their putting there to the engine's thread, its
/// caller waiting for none of it ([`Pool::lands_unwaited`], which says how
/// `told` is called with `number`). Returns how many it gave a slot, the
/// first of them: all, or fewer where the pool is full at the next — the
/// rest landed by a call from where this one ended.
///
/// # Safety
/// Every pointer is live, on `engine`, and the pool its caller's alone;
/// `places` holds as many as `finished` has inked past `first`, and `told`
/// is one any thread may call.
#[unsafe(no_mangle)]
#[allow(clippy::too_many_arguments)]
pub unsafe extern "C" fn gpu_engine_finished_land_unwaited(
    finished: *const Finished,
    engine: *const Engine,
    pool: *mut Pool,
    cel: u32,
    first: usize,
    places: *mut u32,
    told: extern "C" fn(u64, bool),
    number: u64,
) -> usize {
    // SAFETY: see the function's contract.
    let (finished, engine, pool) = unsafe { (&*finished, &*engine, &mut *pool) };
    let inked: Vec<usize> = finished.inked().skip(first).collect();
    let (out, count) = (finished.out().clone(), inked.len());
    let put = move |engine: &Engine, writing: &Writing| writing.put_from(engine, &out, inked);
    // SAFETY: `put` holds what is its own; `told` is one any thread may
    // call (the function's contract).
    let given = unsafe { pool.lands_unwaited(engine, (Cel(cel), count), (told, number), put) };
    for (at, place) in given.iter().enumerate() {
        // SAFETY: see the function's contract.
        unsafe { *places.add(at) = place.word() };
    }
    given.len()
}

/// # Safety
/// `finished` came from a finish told ([`gpu_engine_stamp_finish_unwaited`],
/// [`gpu_engine_stamp_finish_mask_unwaited`]).
///
/// 🚨WAITS FOR NOTHING, THOUGH NO FINALIZER CALLS IT (2026-11-20): the
/// turn that is told frees it right behind the put it handed over
/// ([`gpu_engine_finished_land_unwaited`]), and waiting here would stand
/// that turn behind the put and every body ahead of it — the wait this
/// road is there to take off the caller's thread. It counts nothing, and
/// the put holds the tiles made as its own. The app's scan names it
/// (test/architecture/a_free_the_gc_calls_waits_for_nothing_test.dart).
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_finished_free(finished: *mut Finished) {
    // SAFETY: see the function's contract.
    unsafe { let_go_unwaited(finished) };
}

/// What a mask is laid under, as the app hands it: a run of numbers whose
/// first is its tag, which says how many follow and what each is.
/// [`COLOUR`]: one, the colour — a pixel's word, red in its low byte, its
/// alpha unread. [`GRADIENT`]: seven — its shape ([`LINE`] or [`CIRCLE`]),
/// `from`'s x and y, `to`'s x and y (canvas pixels), and its start's and
/// its end's colours, a straight pixel's word each ([`Gradient`]).
enum PaintOf {
    Colour([u8; 3]),
    Gradient(Gradient),
}

/// [`PaintOf`]'s tags.
const COLOUR: f64 = 0.0;
const GRADIENT: f64 = 1.0;
/// A gradient's shapes.
const LINE: f64 = 0.0;
const CIRCLE: f64 = 1.0;

impl PaintOf {
    /// The paint at `paint`, or none where its tag or a number is none the
    /// host knows (the last error says which).
    ///
    /// # Safety
    /// `paint` holds its tag and the numbers that tag reads.
    unsafe fn read(paint: *const f64) -> Option<Self> {
        // SAFETY: see the function's contract — a tag first.
        let tag = unsafe { *paint };
        let word = |x: f64| {
            let whole = x.fract() == 0.0 && (0.0..=f64::from(u32::MAX)).contains(&x);
            if whole { Some((x as u32).to_le_bytes()) } else { fail(format!("{x} is no pixel's word")) }
        };
        if tag == COLOUR {
            // SAFETY: see the function's contract — the colour after its tag.
            let [red, green, blue, _] = word(unsafe { *paint.add(1) })?;
            return Some(PaintOf::Colour([red, green, blue]));
        }
        if tag != GRADIENT {
            return fail(format!("a paint tagged {tag}, none the host knows"));
        }
        // SAFETY: see the function's contract — a gradient's seven after its tag.
        let [shape, from_x, from_y, to_x, to_y, start, end] = unsafe { *paint.add(1).cast::<[f64; 7]>() };
        let shape = if shape == LINE {
            GradientShape::Line
        } else if shape == CIRCLE {
            GradientShape::Circle
        } else {
            return fail(format!("a gradient of shape {shape}, none the host knows"));
        };
        Some(PaintOf::Gradient(Gradient {
            shape,
            from: (from_x, from_y),
            to: (to_x, to_y),
            start: word(start)?,
            end: word(end)?,
        }))
    }

    fn paint(&self) -> Paint<'_> {
        match self {
            PaintOf::Colour(colour) => Paint::Colour(*colour),
            PaintOf::Gradient(gradient) => Paint::Gradient(gradient),
        }
    }
}

/// Lays `coverage` under `paint` ([`PaintOf`]) on the `count` tiles asked
/// as [`gpu_engine_stroke_land`] says, compared: a pixel it covers at all
/// wholly where `whole`, else its byte for an alpha, at `opacity` in
/// `mode`, under `mask` if not null — null where the paint is none the
/// host knows (the last error says). A fill's pieces in their colour or
/// under their gradient (the app's `FillRange`), and a selection's erase
/// (`selectionEraseDab`): the selection's own mask, laid by the eraser,
/// its colour never read. Returns as it does.
///
/// 🗣️브러시/렌더링 2026-11-15 08:30 (a-gradient-fill-preview-paints-its-
/// range-on-the-cpu-every-frame): ONE entry, the paint one argument that
/// mirrors [`Paint`] — its tag says which numbers follow. ⛔No sibling
/// entry (the mask, the asks and the report a second time) and no
/// gradient's places held empty under a colour.
///
/// # Safety
/// As [`gpu_engine_stroke_land`]'s, `coverage` live on `engine`; `paint`
/// holds its tag and the numbers that tag reads.
#[unsafe(no_mangle)]
#[allow(clippy::too_many_arguments)]
pub unsafe extern "C" fn gpu_engine_stamp_land_mask(
    landing: *const StampLanding,
    engine: *const Engine,
    composite: *const Composite,
    pool: *mut Pool,
    cel: u32,
    coverage: *const MaskPlane,
    paint: *const f64,
    whole: bool,
    asks: *const i32,
    under: *const u32,
    count: usize,
    opacity: u32,
    mode: u32,
    mask: *const MaskPlane,
    places: *mut u32,
    changes: *mut u8,
) -> isize {
    // SAFETY: see the function's contract.
    let (landing, engine, composite, pool, coverage) =
        unsafe { (&*landing, &*engine, &*composite, &mut *pool, &*coverage) };
    // SAFETY: see the function's contract.
    let Some(painted) = (unsafe { PaintOf::read(paint) }) else {
        return -1;
    };
    engine.on_thread(|| {
        let coverage = coverage.mask();
        // SAFETY: see the function's contract.
        let asked = unsafe { asked_of(asks, under, count, &*pool) };
        // SAFETY: see the function's contract.
        let mask = unsafe { mask.as_ref() }.map(MaskPlane::mask);
        let laid = Laid { opacity, mode, mask: mask.as_ref() };
        let paint = painted.paint();
        let source = Source::Mask { mask: &coverage, paint: &paint, whole };
        let landed = landing.land(engine, (composite, pool, Cel(cel)), &source, &asked, &laid);
        // SAFETY: see the function's contract.
        unsafe { reported(landed, places, changes) }
    })
}
