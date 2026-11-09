//! A stroke's C ABI (flip lane ⓒ): the app piles its dabs on a stroke, and
//! asks it what it makes of the tiles of a cel.

use std::sync::atomic::{AtomicU64, Ordering};

use super::landing::{Asked, Laid};
use super::stamp::{Source, StampLanding};
use super::stroke::Stroke;
use super::{Dab, Edge, Paper, RoundProfile, Shape, Texture, Turn};
use crate::device::Engine;
use crate::fail;
use crate::kernels::composite::abi::MaskPlane;
use crate::kernels::composite::{Composite, NO_TILE, TileAt};
use crate::kernels::pool::{Cel, Pool};
use crate::kernels::warp::Boxed;
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
    let (stroke, engine, composite, pool) =
        unsafe { (&*stroke, &*engine, &*composite, &mut *pool) };
    // SAFETY: see the function's contract.
    let asked = unsafe { asked_of(asks, under, count) };
    // SAFETY: see the function's contract.
    let mask = unsafe { mask.as_ref() }.map(MaskPlane::mask);
    let laid = Laid { opacity, mode, mask: mask.as_ref() };
    let landed = stroke.land(engine, (composite, pool, Cel(cel)), &asked, &laid, compared);
    // SAFETY: see the function's contract.
    unsafe { reported(landed, places, changes) }
}

/// The tiles a landing is asked: `asks` their column and row, `under` the
/// cel's tile at each as a tile set names one.
///
/// # Safety
/// `asks` holds `2 × count` and `under` `count`.
unsafe fn asked_of(asks: *const i32, under: *const u32, count: usize) -> Vec<Asked> {
    // SAFETY: see the function's contract.
    let (asks, under) = unsafe {
        (std::slice::from_raw_parts(asks, 2 * count), std::slice::from_raw_parts(under, count))
    };
    asks.chunks_exact(2)
        .zip(under)
        .map(|(tile, &word)| Asked { column: tile[0], row: tile[1], under: TileAt::of_word(word) })
        .collect()
}

/// Writes each landed tile's `places` and `changes`, and returns how many
/// landed; -1 where the landing failed.
///
/// # Safety
/// `places` and `changes` hold as many as were asked, and no more land.
unsafe fn reported(
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
            *changes.add(at) = match change {
                Change::Same => 0,
                Change::Inked => 1,
                Change::Cleared => 2,
            };
        }
    }
    landed.len() as isize
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
    let pixels = wgpu::util::DeviceExt::create_buffer_init(
        &engine.device,
        &wgpu::util::BufferInitDescriptor {
            label: Some("stamp picture"),
            contents: rgba,
            usage: wgpu::BufferUsages::STORAGE,
        },
    );
    STAMP_PICTURE_BYTES.fetch_add(bytes, Ordering::Relaxed);
    Box::into_raw(Box::new(StampPicture { pixels, size: (width, height) }))
}

/// # Safety
/// `picture` came from `gpu_engine_stamp_picture_new`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_stamp_picture_free(picture: *mut StampPicture) {
    if !picture.is_null() {
        // SAFETY: see the function's contract.
        let picture = unsafe { Box::from_raw(picture) };
        STAMP_PICTURE_BYTES.fetch_sub(picture.pixels.size(), Ordering::Relaxed);
    }
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
    StampLanding::new(engine).map_or(std::ptr::null_mut(), |landing| Box::into_raw(Box::new(landing)))
}

/// # Safety
/// `landing` came from `gpu_engine_stamp_landing_new`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_stamp_landing_free(landing: *mut StampLanding) {
    if !landing.is_null() {
        // SAFETY: see the function's contract.
        drop(unsafe { Box::from_raw(landing) });
    }
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
    // SAFETY: see the function's contract.
    let asked = unsafe { asked_of(asks, under, count) };
    // SAFETY: see the function's contract.
    let mask = unsafe { mask.as_ref() }.map(MaskPlane::mask);
    let laid = Laid { opacity, mode, mask: mask.as_ref() };
    let boxed = Boxed { pixels: &picture.pixels, size: picture.size };
    let source = Source::Picture { picture: &boxed, at: (left, top), within };
    let landed = landing.land(engine, (composite, pool, Cel(cel)), &source, &asked, &laid);
    // SAFETY: see the function's contract.
    unsafe { reported(landed, places, changes) }
}
