//! A stroke's C ABI (flip lane ⓒ): the app piles its dabs on a stroke, and
//! asks it what it makes of the tiles of a cel.

use super::stroke::{Asked, Laid, Stroke};
use super::{Dab, Edge, Paper, RoundProfile, Shape, Texture, Turn};
use crate::device::Engine;
use crate::kernels::composite::abi::MaskPlane;
use crate::kernels::composite::{Composite, NO_TILE, TileAt};
use crate::kernels::pool::{Cel, Pool};
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
    _pad: u32,
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
    Texture::new(texels, side).map_or(std::ptr::null_mut(), |texture| Box::into_raw(Box::new(texture)))
}

/// # Safety
/// `texture` came from `gpu_engine_dab_texture_new`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_dab_texture_free(texture: *mut Texture) {
    if !texture.is_null() {
        // SAFETY: see the function's contract.
        drop(unsafe { Box::from_raw(texture) });
    }
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
    Stroke::new(engine).map_or(std::ptr::null_mut(), |stroke| Box::into_raw(Box::new(stroke)))
}

/// # Safety
/// `stroke` came from `gpu_engine_stroke_new`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_stroke_free(stroke: *mut Stroke) {
    if !stroke.is_null() {
        // SAFETY: see the function's contract.
        drop(unsafe { Box::from_raw(stroke) });
    }
}

/// The bytes of `stroke`'s pages.
///
/// # Safety
/// `stroke` is live.
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
    stroke.clear(engine);
}

/// Piles `dabs`, `count` of them, in their order, over the paper — `paper`,
/// null for none, at `paper_scale` px a texel, 高さ where `paper_height` —
/// with a second tip shown by `second_mode` at `second_density` where that
/// is not -1. False on failure; see the last error.
///
/// # Safety
/// `stroke` and `engine` are live, the stroke made on it; `dabs` holds
/// `count`, each as `DabSpec` says; `paper` is live or null.
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
) -> bool {
    // SAFETY: see the function's contract.
    let (stroke, engine, specs) =
        unsafe { (&mut *stroke, &*engine, std::slice::from_raw_parts(dabs, count)) };
    // SAFETY: a spec's tables are as `DabSpec` says.
    let profiles: Vec<Option<RoundProfile>> =
        specs.iter().map(|spec| unsafe { profile_of(spec) }).collect();
    let dabs: Vec<Dab> = specs
        .iter()
        .zip(&profiles)
        // SAFETY: a spec's texture and evening are as `DabSpec` says.
        .map(|(spec, profile)| unsafe { dab_of(spec, profile.as_ref()) })
        .collect();
    // SAFETY: see the function's contract.
    let paper = (!paper.is_null()).then(|| Paper {
        texture: unsafe { &*paper },
        scale: paper_scale,
        height: paper_height,
    });
    let second = (second_mode != -1).then_some((second_mode as u32, second_density));
    stroke.pile(engine, &dabs, paper.as_ref(), second).is_some()
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
    let (stroke, engine, composite, pool, asks, under) = unsafe {
        (
            &*stroke,
            &*engine,
            &*composite,
            &mut *pool,
            std::slice::from_raw_parts(asks, 2 * count),
            std::slice::from_raw_parts(under, count),
        )
    };
    let asked: Vec<Asked> = asks
        .chunks_exact(2)
        .zip(under)
        .map(|(tile, &word)| Asked { column: tile[0], row: tile[1], under: TileAt::of_word(word) })
        .collect();
    // SAFETY: see the function's contract.
    let mask = unsafe { mask.as_ref() }.map(MaskPlane::mask);
    let laid = Laid { opacity, mode, mask: mask.as_ref() };
    let Some(landed) = stroke.land(engine, (composite, pool, Cel(cel)), &asked, &laid, compared)
    else {
        return -1;
    };
    for (at, (change, place)) in landed.iter().enumerate() {
        // SAFETY: `places` and `changes` hold `count` each, and no more land.
        unsafe {
            *places.add(at) = place.map_or(NO_TILE, TileAt::word);
            *changes.add(at) = match change {
                Change::Same => 0,
                Change::Inked => 1,
                Change::Cleared => 2,
            };
        }
    }
    landed.len() as isize
}
