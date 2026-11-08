//! The executor's C ABI (screen-on-the-engine 2a, 2b): the app builds a
//! plan call by call — each tile set, key chain, colour matrix, effect
//! chain and its ops, blur map and step one call, so the plan's layout is
//! written here alone and nowhere in Dart — and runs it over output tiles,
//! shows it onto a surface, or composites it onto a canvas's screen
//! (screen.rs) that the camera shows (screen-on-the-engine c6). The plan
//! is checked where it runs
//! ([`Composite`]'s walk), as one built in Rust is; a call checks only the
//! indices it adds to — a chain's or a key chain's —, which no plan holds.
//!
//! The fill range's mark is laid under a mask the app keeps on the GPU
//! ([`MaskPlane`]) — made once, for as long as the range lasts, and named
//! by each plan that marks it (flip lane ⓐ-3). ⏳A row laid under the
//! plan's mask (R28's `masked`) has no call yet.

#[cfg(test)]
mod tests;

use std::sync::atomic::{AtomicU64, Ordering};

use crate::device::Engine;
use crate::fail;
use crate::kernels::chain::{Chained, MapTiles, Op};
use crate::kernels::effects::blur::TileRect;
use crate::kernels::effects::blur::gaussian::{Blur, Edge, Way};
use crate::kernels::effects::blur::iris::{Focus, Iris};
use crate::kernels::effects::blur::lens::{BlurMap, Lens, Light, MapChannel};
use crate::kernels::effects::blur::line::LinePass;
use crate::kernels::effects::{KEYS_PER_RUN, KeyRun, MATRIX_WORDS, matrix_words};
use crate::kernels::mask::{Mask, MaskBox};
use crate::kernels::pool::Pool;
use crate::kernels::shared::{ResampleMap, ResampleMode, words_buffer};

use super::halvings::Camera;
use super::held::{HeldChains, held_bytes};
use super::screen::Screen;
use super::{
    BufferChain, Composite, Composited, KeyChain, Over, Plan, Step, TILE_BYTES, TileSet,
};

/// A plan as the app builds it: what [`Plan`] borrows, owned. It names
/// the pool's slots and holds none of them: build it, and run it before
/// the pool lets those slots go (캔버스 베이스 패널, 11-07 22:30).
#[derive(Default)]
pub(crate) struct Planned {
    sets: Vec<TileSet>,
    keys: Vec<KeyChain>,
    matrices: Vec<[u32; MATRIX_WORDS]>,
    chains: Vec<PlannedChain>,
    maps: Vec<PlannedMap>,
    steps: Vec<Step>,
    mask: Option<MaskPlane>,
}

/// A mask the app keeps on the GPU: a plane of bytes (mask.wgsl's layout)
/// over the box `size` whose top-left pixel is `at` — the fill range's, in
/// the space of the row it lies on (fill_range_mark.dart).
#[derive(Clone)]
pub(crate) struct MaskPlane {
    plane: wgpu::Buffer,
    at: (i32, i32),
    size: MaskBox,
}

impl MaskPlane {
    fn mask(&self) -> Mask<'_> {
        Mask { plane: &self.plane, at: self.at, size: self.size }
    }
}

/// An effect chain as the app builds it: its ops, a lens blur's with its
/// map's index of the plan's, the rectangle they run over and the hold
/// that keeps what it puts, under the number the app gives it, if any.
struct PlannedChain {
    ops: Vec<(Op<'static>, Option<usize>)>,
    rect: TileRect,
    held: Option<(HeldChains, u32)>,
}

/// A blur map as the app names it ([`BlurMap`]), what it is read from
/// owned.
struct PlannedMap {
    tiles: MapFrom,
    channel: MapChannel,
    focus: Focus,
}

/// What a blur map is read from: the tiles a run put, or the steps it is
/// drawn from.
enum MapFrom {
    Laid(wgpu::Buffer),
    Drawn(Vec<Step>),
}

impl Planned {
    /// The plan of `pages`, `chains` — [`Self::chained`]'s — and `mask` —
    /// [`Self::masked`]'s.
    fn plan<'a>(
        &'a self,
        pages: &'a [wgpu::Buffer],
        chains: &'a [Chained<'a>],
        mask: Option<&'a Mask<'a>>,
    ) -> Plan<'a> {
        Plan {
            pages,
            sets: &self.sets,
            keys: &self.keys,
            matrices: &self.matrices,
            chains,
            steps: &self.steps,
            mask,
        }
    }

    /// The mask its masked steps are laid under, if it names one.
    fn masked(&self) -> Option<Mask<'_>> {
        self.mask.as_ref().map(MaskPlane::mask)
    }

    /// The effect chains as a plan names them, each lens blur reading its
    /// map.
    fn chained(&self) -> Vec<Chained<'_>> {
        self.chains
            .iter()
            .map(|chain| Chained {
                ops: chain.ops.iter().map(|(op, map)| self.mapped(op, *map)).collect(),
                rect: chain.rect,
                held: chain.held.as_ref().map(|(held, id)| (held, *id)),
            })
            .collect()
    }

    /// `op`, reading map `map` of the plan's where it names one.
    fn mapped(&self, op: &Op<'static>, map: Option<usize>) -> Op<'_> {
        let (Op::Lens { picture, lens, .. }, Some(at)) = (op, map) else {
            return op.clone();
        };
        let PlannedMap { tiles, channel, focus } = &self.maps[at];
        let tiles = match tiles {
            MapFrom::Laid(tiles) => MapTiles::Laid(tiles),
            MapFrom::Drawn(steps) => MapTiles::Drawn(steps),
        };
        let map = BlurMap { tiles, channel: *channel, focus: *focus };
        Op::Lens { picture: *picture, lens: *lens, map: Some(map) }
    }

    /// Adds `op` to effect chain `chain`, reading map `map` if any: 0, or
    /// -1 where the plan has no such chain or map (see the last error).
    fn op(&mut self, chain: u32, op: Op<'static>, map: Option<usize>) -> i32 {
        if let Some(at) = map.filter(|&at| at >= self.maps.len()) {
            fail::<()>(format!("no blur map {at}"));
            return -1;
        }
        let Some(planned) = self.chains.get_mut(chain as usize) else {
            fail::<()>(format!("no effect chain {chain}"));
            return -1;
        };
        planned.ops.push((op, map));
        0
    }

    /// Adds the map of `tiles` read through `channel` at `focus` and
    /// returns its index.
    fn map(&mut self, tiles: MapFrom, channel: MapChannel, focus: Focus) -> i32 {
        self.maps.push(PlannedMap { tiles, channel, focus });
        self.maps.len() as i32 - 1
    }

    /// Where the buffer open on top was opened among the steps, if one is.
    fn open_buffer(&self) -> Option<usize> {
        let mut closed = 0usize;
        for (at, step) in self.steps.iter().enumerate().rev() {
            match step {
                Step::Open | Step::OpenOpaque if closed == 0 => return Some(at),
                Step::Open | Step::OpenOpaque => closed -= 1,
                Step::Close { .. } | Step::CloseAtop | Step::CloseRow { .. } => closed += 1,
                Step::Row { .. } | Step::Solid { .. } | Step::Mark { .. } => {}
            }
        }
        None
    }
}

/// The channel the app names a blur map's by: [`MapChannel`]'s own.
fn map_channel(id: u32) -> Option<MapChannel> {
    match id {
        0 => Some(MapChannel::Red),
        1 => Some(MapChannel::Green),
        2 => Some(MapChannel::Blue),
        3 => Some(MapChannel::Alpha),
        4 => Some(MapChannel::Luminance),
        _ => fail(format!("no map channel has id {id}")),
    }
}

/// The rectangle at `rect`, or none for null.
///
/// # Safety
/// `rect` is null or holds four words.
unsafe fn rect_or_none(rect: *const i32) -> Option<[i32; 4]> {
    // SAFETY: see the function's contract.
    (!rect.is_null()).then(|| unsafe { *rect.cast::<[i32; 4]>() })
}

/// The sampling id the app names a row's by: R1's mode's own.
fn sampling(id: u32) -> Option<ResampleMode> {
    match id {
        0 => Some(ResampleMode::Blend),
        1 => Some(ResampleMode::Pick),
        3 => Some(ResampleMode::Nearest),
        _ => fail(format!("no sampling has id {id}")),
    }
}

/// An index the app names, or none for -1.
fn named(index: i32) -> Option<usize> {
    usize::try_from(index).ok()
}

/// A plan of no steps.
#[unsafe(no_mangle)]
pub extern "C" fn gpu_engine_plan_new() -> *mut Planned {
    Box::into_raw(Box::default())
}

/// # Safety
/// `plan` came from `gpu_engine_plan_new`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_plan_free(plan: *mut Planned) {
    if !plan.is_null() {
        // SAFETY: see the function's contract.
        drop(unsafe { Box::from_raw(plan) });
    }
}

/// Adds the tile set of `columns` × `rows` canvas tiles whose top-left is
/// column `x0`, row `y0` — `tiles` row by row, each `page << 16 | slot` of
/// the pool, or `u32::MAX` for a tile with nothing on it — and returns the
/// index a row lays it by.
///
/// # Safety
/// `plan` is live and `tiles` holds `columns × rows` words.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_plan_set(
    plan: *mut Planned,
    x0: i32,
    y0: i32,
    columns: u32,
    rows: u32,
    tiles: *const u32,
) -> u32 {
    // SAFETY: see the function's contract.
    let (plan, words) =
        unsafe { (&mut *plan, std::slice::from_raw_parts(tiles, columns as usize * rows as usize)) };
    plan.sets.push(TileSet::from_words(x0, y0, columns, rows, words));
    plan.sets.len() as u32 - 1
}

/// Adds the colour matrix of `matrix` — `ColorFilter.matrix`'s twenty — and
/// returns its index; -1 where one of them is past what the matrix holds
/// (`effects::matrix_words`), see the last error.
///
/// # Safety
/// `plan` is live and `matrix` holds twenty doubles.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_plan_matrix(plan: *mut Planned, matrix: *const f64) -> i32 {
    // SAFETY: see the function's contract.
    let (plan, matrix) = unsafe { (&mut *plan, &*matrix.cast::<[f64; MATRIX_WORDS]>()) };
    let Some(words) = matrix_words(matrix) else {
        fail::<()>("a colour matrix entry past what the matrix holds");
        return -1;
    };
    plan.matrices.push(words);
    plan.matrices.len() as i32 - 1
}

/// Adds a row: tile set `set`, keyed by key chain `keys` or run through
/// effect chain `chain` where one is not -1 (not both: a chain's keys are
/// its ops), posed by `inverse` — canvas pixel to the row's own,
/// row-major, the homogeneous row last, over an output of `columns` ×
/// `rows` pixels, sampled by `sampling` (0 blend, 1 pick, 3 nearest) with
/// Blend's radius at least `radius_floor` — through colour matrix `matrix`
/// if not -1, laid at `opacity` (65535 whole) in blend mode `mode`
/// (blend.wgsl's id).
///
/// Returns 1 where the row was added, 0 where its pose lands nothing and
/// so it lays nothing — not added ([`ResampleMap::new`]) — and -1 for a
/// sampling no mode has; see the last error.
///
/// # Safety
/// `plan` is live and `inverse` holds nine doubles.
#[unsafe(no_mangle)]
#[allow(clippy::too_many_arguments)]
pub unsafe extern "C" fn gpu_engine_plan_row(
    plan: *mut Planned,
    set: u32,
    matrix: i32,
    keys: i32,
    chain: i32,
    inverse: *const f64,
    radius_floor: f64,
    sampling_id: u32,
    columns: u32,
    rows: u32,
    opacity: u32,
    mode: u32,
) -> i32 {
    // SAFETY: see the function's contract.
    let (plan, inverse) = unsafe { (&mut *plan, *inverse.cast::<[f64; 9]>()) };
    let Some(sampled) = sampling(sampling_id) else {
        return -1;
    };
    let Some(map) = ResampleMap::new(inverse, radius_floor, sampled, columns, rows) else {
        return 0;
    };
    plan.steps.push(Step::Row {
        set: set as usize,
        keys: named(keys),
        chain: named(chain),
        map,
        matrix: named(matrix),
        opacity,
        mode,
        masked: false,
    });
    1
}

/// Opens a transparent buffer — a folder's, a clip's base or its scope —
/// or, where `opaque`, one holding the buffer under it with its alpha made
/// whole: a clip's scope whose rows blend with the base.
///
/// # Safety
/// `plan` is live.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_plan_open(plan: *mut Planned, opaque: bool) {
    // SAFETY: see the function's contract.
    let plan = unsafe { &mut *plan };
    plan.steps.push(if opaque { Step::OpenOpaque } else { Step::Open });
}

/// Closes the open buffer onto the one under it at `opacity` in `mode`,
/// through effect chain `chain` if not -1 — what it puts laid against the
/// buffer it ran on at `mix` (65535 whole) — then colour matrix `matrix`
/// if not -1.
///
/// # Safety
/// `plan` is live.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_plan_close(
    plan: *mut Planned,
    opacity: u32,
    mode: u32,
    matrix: i32,
    chain: i32,
    mix: u32,
) {
    // SAFETY: see the function's contract.
    let plan = unsafe { &mut *plan };
    let chain = named(chain).map(|chain| BufferChain { chain, mix });
    plan.steps.push(Step::Close { opacity, mode, matrix: named(matrix), chain });
}

/// Closes the open buffer — opened on nothing, its steps laid in a row's
/// own space — as that row: drawn over effect chain `chain`'s tiles if not
/// -1, through it, else over the row's tiles `tiles` (x0, y0, columns,
/// rows), and laid as [`gpu_engine_plan_row`] lays a row, posed by
/// `inverse` and the rest.
///
/// Returns 1 where it was closed, 0 where its pose lands nothing and so it
/// lays nothing — the buffer and its steps taken out —, and -1 for a
/// sampling no mode has, a chain and tiles both named or neither, or no
/// buffer open; see the last error.
///
/// # Safety
/// `plan` is live, `inverse` holds nine doubles and `tiles` is null or
/// holds four words.
#[unsafe(no_mangle)]
#[allow(clippy::too_many_arguments)]
pub unsafe extern "C" fn gpu_engine_plan_close_row(
    plan: *mut Planned,
    chain: i32,
    tiles: *const i32,
    matrix: i32,
    inverse: *const f64,
    radius_floor: f64,
    sampling_id: u32,
    columns: u32,
    rows: u32,
    opacity: u32,
    mode: u32,
) -> i32 {
    // SAFETY: see the function's contract.
    let (plan, inverse, tiles) =
        unsafe { (&mut *plan, *inverse.cast::<[f64; 9]>(), rect_or_none(tiles)) };
    let over = match (named(chain), tiles) {
        (Some(chain), None) => Over::Chain(chain),
        (None, Some([x0, y0, columns, rows])) => {
            let (Ok(columns), Ok(rows)) = (u32::try_from(columns), u32::try_from(rows)) else {
                fail::<()>(format!("{columns} × {rows} tiles"));
                return -1;
            };
            Over::Tiles(TileRect { x0, y0, columns, rows })
        }
        _ => {
            fail::<()>("a row's buffer is drawn over its chain's tiles or its own, one");
            return -1;
        }
    };
    let Some(sampled) = sampling(sampling_id) else {
        return -1;
    };
    let Some(open) = plan.open_buffer() else {
        fail::<()>("no buffer is open to close as a row");
        return -1;
    };
    let Some(map) = ResampleMap::new(inverse, radius_floor, sampled, columns, rows) else {
        plan.steps.truncate(open);
        return 0;
    };
    plan.steps.push(Step::CloseRow { over, map, matrix: named(matrix), opacity, mode });
    1
}

/// Closes a clip's scope onto its base by the base's alpha.
///
/// # Safety
/// `plan` is live.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_plan_close_atop(plan: *mut Planned) {
    // SAFETY: see the function's contract.
    let plan = unsafe { &mut *plan };
    plan.steps.push(Step::CloseAtop);
}

/// Lays `colour` — straight RGBA8, A<<24|B<<16|G<<8|R — over the canvas
/// pixels [`left`, `top`, `right`, `bottom`) in normal.
///
/// # Safety
/// `plan` is live.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_plan_solid(
    plan: *mut Planned,
    colour: u32,
    left: i32,
    top: i32,
    right: i32,
    bottom: i32,
) {
    // SAFETY: see the function's contract.
    let plan = unsafe { &mut *plan };
    plan.steps.push(Step::Solid { colour, rect: [left, top, right, bottom] });
}

/// The bytes of every mask the app keeps — made ([`gpu_engine_mask_new`])
/// and not yet freed —, counted where they are made and let go: what the
/// memory census is to read of them ([`gpu_engine_mask_bytes`]; ⏳once the
/// screen is the engine's, flip lane ⓑ).
static MASK_BYTES: AtomicU64 = AtomicU64::new(0);

/// A mask of `width` × `height` bytes at `bytes` — a byte a pixel, row
/// after row, the app's `Uint8List` as it is — whose top-left pixel is
/// (`x`, `y`), kept on the GPU for the plans that name it
/// ([`gpu_engine_plan_mask`]). Null where it holds no pixel; see the last
/// error.
///
/// # Safety
/// `engine` is live and `bytes` holds `width × height`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_mask_new(
    engine: *const Engine,
    bytes: *const u8,
    x: i32,
    y: i32,
    width: u32,
    height: u32,
) -> *mut MaskPlane {
    let size = MaskBox { width, height };
    if width == 0 || height == 0 {
        fail::<()>(format!("{size:?} holds no pixel"));
        return std::ptr::null_mut();
    }
    // SAFETY: see the function's contract.
    let (engine, bytes) =
        unsafe { (&*engine, std::slice::from_raw_parts(bytes, width as usize * height as usize)) };
    let usage = wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC;
    let plane = words_buffer(engine, "mask", &size.words_of(bytes), usage);
    MASK_BYTES.fetch_add(size.bytes(), Ordering::Relaxed);
    Box::into_raw(Box::new(MaskPlane { plane, at: (x, y), size }))
}

/// # Safety
/// `mask` came from `gpu_engine_mask_new`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_mask_free(mask: *mut MaskPlane) {
    if !mask.is_null() {
        // SAFETY: see the function's contract.
        let mask = unsafe { Box::from_raw(mask) };
        MASK_BYTES.fetch_sub(mask.size.bytes(), Ordering::Relaxed);
    }
}

/// The bytes of every mask the app keeps, made and not yet freed.
#[unsafe(no_mangle)]
pub extern "C" fn gpu_engine_mask_bytes() -> u64 {
    MASK_BYTES.load(Ordering::Relaxed)
}

/// Lays the plan's masked steps under `mask`: 0, or -1 where it names one
/// already — a plan has one ([`Plan::mask`]); see the last error.
///
/// # Safety
/// `plan` and `mask` are live.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_plan_mask(plan: *mut Planned, mask: *const MaskPlane) -> i32 {
    // SAFETY: see the function's contract.
    let (plan, mask) = unsafe { (&mut *plan, &*mask) };
    if plan.mask.is_some() {
        fail::<()>("a plan lays its masked steps under one mask");
        return -1;
    }
    plan.mask = Some(mask.clone());
    0
}

/// Adds a fill range's mark ([`Step::Mark`]) under the plan's mask, posed
/// as [`gpu_engine_plan_row`] poses a row — the mark's row's pose — its
/// cells pushed (`shift_x`, `shift_y`), Q.16 of the row's pixels.
///
/// Returns 1 where it was added, 0 where its pose lands nothing and so it
/// lays nothing — not added —, and -1 for a sampling no mode has; see the
/// last error.
///
/// # Safety
/// `plan` is live and `inverse` holds nine doubles.
#[unsafe(no_mangle)]
#[allow(clippy::too_many_arguments)]
pub unsafe extern "C" fn gpu_engine_plan_mark(
    plan: *mut Planned,
    inverse: *const f64,
    radius_floor: f64,
    sampling_id: u32,
    columns: u32,
    rows: u32,
    shift_x: i32,
    shift_y: i32,
) -> i32 {
    // SAFETY: see the function's contract.
    let (plan, inverse) = unsafe { (&mut *plan, *inverse.cast::<[f64; 9]>()) };
    let Some(sampled) = sampling(sampling_id) else {
        return -1;
    };
    let Some(map) = ResampleMap::new(inverse, radius_floor, sampled, columns, rows) else {
        return 0;
    };
    plan.steps.push(Step::Mark { map, shift: [shift_x, shift_y] });
    1
}

/// Adds a key chain of no runs and returns the index a row or a chain's
/// op keys by.
///
/// # Safety
/// `plan` is live.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_plan_keys(plan: *mut Planned) -> u32 {
    // SAFETY: see the function's contract.
    let plan = unsafe { &mut *plan };
    plan.keys.push(KeyChain { runs: Vec::new() });
    plan.keys.len() as u32 - 1
}

/// Adds to key chain `keys` a run of `count` colour keys, as the app's
/// tables give one: for each channel's byte — `red`, `green`, `blue`, 256
/// words each — which keys are within their tolerance of it, bit k for key
/// k; `restores`, the keys that give back instead of erasing; and `maps`,
/// each key's 256-byte alpha map. -1 where `keys` names no chain or
/// `count` is past a run's, see the last error.
///
/// # Safety
/// `plan` is live, the tables hold 256 words each and `maps` 256 × `count`
/// bytes.
#[unsafe(no_mangle)]
#[allow(clippy::too_many_arguments)]
pub unsafe extern "C" fn gpu_engine_plan_key_run(
    plan: *mut Planned,
    keys: u32,
    red: *const u32,
    green: *const u32,
    blue: *const u32,
    restores: u32,
    maps: *const u8,
    count: u32,
) -> i32 {
    // SAFETY: see the function's contract.
    let plan = unsafe { &mut *plan };
    if count as usize > KEYS_PER_RUN {
        fail::<()>(format!("a run of {count} keys; one holds {KEYS_PER_RUN}"));
        return -1;
    }
    let Some(chain) = plan.keys.get_mut(keys as usize) else {
        fail::<()>(format!("no key chain {keys}"));
        return -1;
    };
    // SAFETY: see the function's contract.
    let run = unsafe {
        KeyRun {
            red: &*red.cast::<[u32; 256]>(),
            green: &*green.cast::<[u32; 256]>(),
            blue: &*blue.cast::<[u32; 256]>(),
            restores,
            maps: std::slice::from_raw_parts(maps, 256 * count as usize),
        }
    };
    chain.runs.push(run.words());
    1
}

/// Adds an effect chain of no ops over the canvas tiles of `columns` ×
/// `rows` whose top-left is column `x0`, row `y0` — a row's in its own
/// space, a folder's on the canvas — and returns the index a row or a
/// close runs it by.
///
/// # Safety
/// `plan` is live.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_plan_chain(plan: *mut Planned, x0: i32, y0: i32, columns: u32, rows: u32) -> u32 {
    // SAFETY: see the function's contract.
    let plan = unsafe { &mut *plan };
    let rect = TileRect { x0, y0, columns, rows };
    plan.chains.push(PlannedChain { ops: Vec::new(), rect, held: None });
    plan.chains.len() as u32 - 1
}

/// Holds what effect chain `chain` puts in `held` under `id`, the number
/// the app gives what it shows: a run whose hold under `id` keeps what it
/// put over the chain's rectangle lays that, and does not run it
/// ([`HeldChains`]). 0, or -1 where the plan has no such chain; see the
/// last error.
///
/// # Safety
/// `plan` and `held` are live.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_plan_chain_held(
    plan: *mut Planned,
    chain: u32,
    held: *const HeldChains,
    id: u32,
) -> i32 {
    // SAFETY: see the function's contract.
    let (plan, held) = unsafe { (&mut *plan, &*held) };
    let Some(planned) = plan.chains.get_mut(chain as usize) else {
        fail::<()>(format!("no effect chain {chain}"));
        return -1;
    };
    planned.held = Some((held.clone(), id));
    0
}

/// A hold for what the chains of the plans that name it put
/// ([`gpu_engine_plan_chain_held`]), empty.
#[unsafe(no_mangle)]
pub extern "C" fn gpu_engine_held_new() -> *mut HeldChains {
    Box::into_raw(Box::default())
}

/// Lets go of everything `held` keeps that no plan names; what one does is
/// let go with the plan.
///
/// # Safety
/// `held` came from `gpu_engine_held_new`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_held_free(held: *mut HeldChains) {
    if !held.is_null() {
        // SAFETY: see the function's contract.
        drop(unsafe { Box::from_raw(held) });
    }
}

/// Lets go of what `held` keeps under `id`, if anything.
///
/// # Safety
/// `held` is live.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_held_let_go(held: *const HeldChains, id: u32) {
    // SAFETY: see the function's contract.
    unsafe { &*held }.let_go(id);
}

/// The bytes `held` keeps under `id` — none where it keeps nothing.
///
/// # Safety
/// `held` is live.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_held_bytes_of(held: *const HeldChains, id: u32) -> u64 {
    // SAFETY: see the function's contract.
    unsafe { &*held }.bytes_of(id)
}

/// The bytes every hold keeps, kept and not yet let go.
#[unsafe(no_mangle)]
pub extern "C" fn gpu_engine_held_bytes() -> u64 {
    held_bytes()
}

/// Adds to effect chain `chain` the colour matrix of `matrix` —
/// `ColorFilter.matrix`'s twenty. 0, or -1 where the plan has no such chain
/// or an entry is past what the matrix holds; see the last error.
///
/// # Safety
/// `plan` is live and `matrix` holds twenty doubles.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_plan_chain_matrix(plan: *mut Planned, chain: u32, matrix: *const f64) -> i32 {
    // SAFETY: see the function's contract.
    let (plan, matrix) = unsafe { (&mut *plan, &*matrix.cast::<[f64; MATRIX_WORDS]>()) };
    let Some(words) = matrix_words(matrix) else {
        fail::<()>("a colour matrix entry past what the matrix holds");
        return -1;
    };
    plan.op(chain, Op::Matrix(words), None)
}

/// Adds to effect chain `chain` the runs of key chain `keys`, every key
/// against the alpha of what the op reads. 0, or -1 where the plan has no
/// such chain; see the last error.
///
/// # Safety
/// `plan` is live.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_plan_chain_keys(plan: *mut Planned, chain: u32, keys: u32) -> i32 {
    // SAFETY: see the function's contract.
    let plan = unsafe { &mut *plan };
    let Some(keyed) = plan.keys.get(keys as usize).cloned() else {
        fail::<()>(format!("no key chain {keys}"));
        return -1;
    };
    plan.op(chain, Op::Keys(keyed), None)
}

/// Adds to effect chain `chain` fx Gaussian Blur: across by sigma
/// `sigmas[0]` reaching `reaches[0]` pixels either side, down by
/// `sigmas[1]` reaching `reaches[1]` — a way of no reach not blurred —,
/// reading `picture` — past it nothing, or where `repeats` is 1 its nearest
/// pixel — and putting `puts`, nothing outside it: [left, top, right,
/// bottom) each, inside the chain's tiles. 0, or -1 where the plan has no
/// such chain; see the last error.
///
/// # Safety
/// `plan` is live, `sigmas` and `reaches` hold two words each, `picture`
/// and `puts` four.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_plan_chain_gaussian(
    plan: *mut Planned,
    chain: u32,
    sigmas: *const f64,
    reaches: *const u32,
    picture: *const i32,
    repeats: u32,
    puts: *const i32,
) -> i32 {
    // SAFETY: see the function's contract.
    let (plan, sigmas, reaches, picture, puts) = unsafe {
        (
            &mut *plan,
            *sigmas.cast::<[f64; 2]>(),
            *reaches.cast::<[u32; 2]>(),
            *picture.cast::<[i32; 4]>(),
            *puts.cast::<[i32; 4]>(),
        )
    };
    let way = |at: usize| Way { sigma: sigmas[at], reach: reaches[at] };
    let blur = Blur {
        across: way(0),
        down: way(1),
        picture,
        edge: if repeats == 1 { Edge::Repeat } else { Edge::Nothing },
        puts,
    };
    plan.op(chain, Op::Gaussian(blur), None)
}

/// Adds to effect chain `chain` fx Directional or Radial Blur's `count`
/// passes over `plate`, [left, top, right, bottom): pass i of `taps[i]`
/// taps and twelve of `maps` — its step, centre, first and each, as
/// [`LinePass`] has them. 0, or -1 where the plan has no such chain; see
/// the last error.
///
/// # Safety
/// `plan` is live, `plate` holds four words, `taps` `count` and `maps`
/// twelve doubles a pass.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_plan_chain_line(
    plan: *mut Planned,
    chain: u32,
    plate: *const i32,
    taps: *const u32,
    maps: *const f64,
    count: usize,
) -> i32 {
    // SAFETY: see the function's contract.
    let (plan, plate, taps, maps) = unsafe {
        (
            &mut *plan,
            *plate.cast::<[i32; 4]>(),
            std::slice::from_raw_parts(taps, count),
            std::slice::from_raw_parts(maps, 12 * count),
        )
    };
    let pass = |(&taps, m): (&u32, &[f64])| LinePass {
        taps,
        step: [m[0], m[1]],
        centre: [m[2], m[3]],
        first: [m[4], m[5], m[6], m[7]],
        each: [m[8], m[9], m[10], m[11]],
    };
    let passes = taps.iter().zip(maps.chunks_exact(12)).map(pass).collect();
    plan.op(chain, Op::Line { plate, passes }, None)
}

/// Adds to effect chain `chain` fx Camera Lens Blur over `picture`, [left,
/// top, right, bottom): an iris of `sides` and `lens`'s thirteen — the
/// iris's roundness and aspect, its rotation's, half a side's and a whole
/// side's turns as cosine and sine; the radius and the fringe; the light's
/// gain, threshold and saturation —, the light linear where `linear`,
/// repeating the paper `paper` past it where not null, through blur map
/// `map` where not -1. 0, or -1 where the plan has no such chain or map;
/// see the last error.
///
/// # Safety
/// `plan` is live, `picture` holds four words, `lens` thirteen doubles and
/// `paper` is null or holds four words.
#[unsafe(no_mangle)]
#[allow(clippy::too_many_arguments)]
pub unsafe extern "C" fn gpu_engine_plan_chain_lens(
    plan: *mut Planned,
    chain: u32,
    picture: *const i32,
    sides: u32,
    lens: *const f64,
    linear: bool,
    paper: *const i32,
    map: i32,
) -> i32 {
    // SAFETY: see the function's contract.
    let (plan, picture, l, paper) =
        unsafe { (&mut *plan, *picture.cast::<[i32; 4]>(), &*lens.cast::<[f64; 13]>(), rect_or_none(paper)) };
    let lens = Lens {
        iris: Iris {
            sides,
            roundness: l[0],
            aspect: l[1],
            turn: [l[2], l[3]],
            half_side: [l[4], l[5]],
            side: [l[6], l[7]],
        },
        radius: l[8],
        fringe: l[9],
        light: Light { gain: l[10], threshold: l[11], saturation: l[12], linear },
        paper,
    };
    plan.op(chain, Op::Lens { picture, lens, map: None }, named(map))
}

/// Adds a blur map read from the tiles `composited` holds — over the blur's
/// own rectangle, as a run over its tiles put them — through channel
/// `channel` (0 red, 1 green, 2 blue, 3 alpha, 4 luminance), in focus at
/// `focal` (0 to 255) and inverted where `inverts`; returns the index a
/// lens blur reads it by, or -1 for no such channel (see the last error).
///
/// # Safety
/// `plan` and `composited` are live.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_plan_map_laid(
    plan: *mut Planned,
    composited: *const Composited,
    channel: u32,
    focal: f64,
    inverts: bool,
) -> i32 {
    // SAFETY: see the function's contract.
    let (plan, composited) = unsafe { (&mut *plan, &*composited) };
    let Some(channel) = map_channel(channel) else {
        return -1;
    };
    plan.map(MapFrom::Laid(composited.out.clone()), channel, Focus { focal, inverts })
}

/// How many steps the plan has: where the steps a blur map is drawn from
/// begin ([`gpu_engine_plan_map_drawn`]).
///
/// # Safety
/// `plan` is live.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_plan_steps(plan: *const Planned) -> u32 {
    // SAFETY: see the function's contract.
    unsafe { &*plan }.steps.len() as u32
}

/// Takes the plan's steps from step `first` on as the steps a blur map is
/// drawn from — drawn alone over the blur's rectangle, as they show by
/// themselves —, read through `channel`, in focus at `focal` and inverted
/// where `inverts` as [`gpu_engine_plan_map_laid`]'s; returns the index a
/// lens blur reads it by, or -1 where the plan has fewer steps or no such
/// channel (see the last error).
///
/// # Safety
/// `plan` is live.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_plan_map_drawn(
    plan: *mut Planned,
    first: u32,
    channel: u32,
    focal: f64,
    inverts: bool,
) -> i32 {
    // SAFETY: see the function's contract.
    let plan = unsafe { &mut *plan };
    let first = first as usize;
    if first > plan.steps.len() {
        fail::<()>(format!("a map drawn from step {first} of {}", plan.steps.len()));
        return -1;
    }
    let Some(channel) = map_channel(channel) else {
        return -1;
    };
    let steps = plan.steps.split_off(first);
    plan.map(MapFrom::Drawn(steps), channel, Focus { focal, inverts })
}

/// The executor, its full pass compiled. Null on failure; see the last
/// error.
///
/// # Safety
/// `engine` is live; the executor is freed before it.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_composite_new(engine: *const Engine) -> *mut Composite {
    // SAFETY: see the function's contract.
    let engine = unsafe { &*engine };
    Composite::new(engine).map_or(std::ptr::null_mut(), |composite| Box::into_raw(Box::new(composite)))
}

/// # Safety
/// `composite` came from `gpu_engine_composite_new`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_composite_free(composite: *mut Composite) {
    if !composite.is_null() {
        // SAFETY: see the function's contract.
        drop(unsafe { Box::from_raw(composite) });
    }
}

/// Composites `plan` over the `count` output tiles at `tiles` — a canvas
/// tile column then row each — with nothing outside the pixels `extent`,
/// [left, top, right, bottom), and submits the work. Null on failure; see
/// the last error.
///
/// # Safety
/// Every pointer is live, the pool and the executor were made on `engine`;
/// `tiles` holds `2 × count` words and `extent` four.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_composite_run(
    composite: *const Composite,
    engine: *const Engine,
    pool: *const Pool,
    plan: *const Planned,
    tiles: *const i32,
    count: usize,
    extent: *const i32,
) -> *mut Composited {
    // SAFETY: see the function's contract.
    let (composite, engine, pool, plan) = unsafe { (&*composite, &*engine, &*pool, &*plan) };
    // SAFETY: see the function's contract.
    let (words, extent) = unsafe { (std::slice::from_raw_parts(tiles, 2 * count), *extent.cast::<[i32; 4]>()) };
    let tiles: Vec<(i32, i32)> = words.chunks_exact(2).map(|tile| (tile[0], tile[1])).collect();
    let (chains, mask) = (plan.chained(), plan.masked());
    let laid = plan.plan(pool.pages(), &chains, mask.as_ref());
    let ran = composite.run(engine, &laid, &tiles, extent, composite.widest());
    ran.map_or(std::ptr::null_mut(), |composited| Box::into_raw(Box::new(composited)))
}

/// Copies `composited`'s pixels — straight RGBA8, tile after tile in the
/// order asked — into `bytes` once the GPU is done, `capacity` of them at
/// most. False on failure; see the last error.
///
/// # Safety
/// `engine` and `composited` are live and `bytes` holds `capacity`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_composited_read(
    engine: *const Engine,
    composited: *const Composited,
    bytes: *mut u8,
    capacity: usize,
) -> bool {
    // SAFETY: see the function's contract.
    let (engine, composited) = unsafe { (&*engine, &*composited) };
    let Some(read) = engine.read_buffer(&composited.out) else {
        return false;
    };
    let count = read.len().min(capacity);
    // SAFETY: `bytes` holds `capacity`, and `count` is no more.
    unsafe { std::ptr::copy_nonoverlapping(read.as_ptr(), bytes, count) };
    true
}

/// The bytes a run over `count` output tiles puts.
#[unsafe(no_mangle)]
pub extern "C" fn gpu_engine_composited_bytes(count: usize) -> u64 {
    count as u64 * TILE_BYTES
}

/// # Safety
/// `composited` came from `gpu_engine_composite_run`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_composited_free(composited: *mut Composited) {
    if !composited.is_null() {
        // SAFETY: see the function's contract.
        drop(unsafe { Box::from_raw(composited) });
    }
}

/// Composites `plan` onto the pixels `rect` of `target` — [left, top,
/// right, bottom) — leaving the rest of it as it was, and waits for the GPU;
/// returns how many passes it took, -1 on failure (see the last error).
/// `target` is what the screen shows: a surface's texture
/// (`gpu_engine_surface_texture`) or a window's next image
/// (`gpu_engine_window_target`), one entry for both (kernels/mod.rs).
///
/// # Safety
/// Every pointer is live, made on `engine`; `rect` holds four words.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_composite_show(
    composite: *const Composite,
    engine: *const Engine,
    pool: *const Pool,
    plan: *const Planned,
    target: *const wgpu::Texture,
    rect: *const u32,
) -> isize {
    // SAFETY: see the function's contract.
    let (composite, engine, pool, plan, target) = unsafe { (&*composite, &*engine, &*pool, &*plan, &*target) };
    // SAFETY: see the function's contract.
    let rect = unsafe { *rect.cast::<[u32; 4]>() };
    let (chains, mask) = (plan.chained(), plan.masked());
    let laid = plan.plan(pool.pages(), &chains, mask.as_ref());
    let shown = composite.show(engine, &laid, target, rect, composite.widest());
    shown.map_or(-1, |passes| passes as isize)
}

/// The screen of a canvas's composite over the pixels `extent` — [left,
/// top, right, bottom): the page and what lies past it — shown on Blend's
/// radius `floor` at least, nothing composed on it yet. Null on failure;
/// see the last error.
///
/// # Safety
/// `extent` holds four words.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_screen_new(extent: *const i32, floor: f64) -> *mut Screen {
    // SAFETY: see the function's contract.
    let extent = unsafe { *extent.cast::<[i32; 4]>() };
    Screen::new(extent, floor).map_or(std::ptr::null_mut(), |screen| Box::into_raw(Box::new(screen)))
}

/// # Safety
/// `screen` came from `gpu_engine_screen_new`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_screen_free(screen: *mut Screen) {
    if !screen.is_null() {
        // SAFETY: see the function's contract.
        drop(unsafe { Box::from_raw(screen) });
    }
}

/// The bytes `screen` keeps — its canvas's pages and its halvings': what
/// the budgets and the memory census weigh it by.
///
/// # Safety
/// `screen` came from `gpu_engine_screen_new`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_screen_bytes(screen: *const Screen) -> u64 {
    // SAFETY: see the function's contract.
    unsafe { &*screen }.bytes()
}

/// The bytes of every picture the engine keeps — every screen's canvas and
/// halvings, made and not yet dropped.
#[unsafe(no_mangle)]
pub extern "C" fn gpu_engine_kept_bytes() -> u64 {
    super::halvings::kept_bytes()
}

/// Composites `plan` onto `screen`'s canvas over its tiles that meet the
/// pixels `changed` — [left, top, right, bottom); the whole canvas the
/// first time — and submits the work. False on failure; see the last error.
///
/// # Safety
/// Every pointer is live, the pool and the executor were made on `engine`;
/// `changed` holds four words.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_screen_compose(
    screen: *mut Screen,
    composite: *const Composite,
    engine: *const Engine,
    pool: *const Pool,
    plan: *const Planned,
    changed: *const i32,
) -> bool {
    // SAFETY: see the function's contract.
    let (screen, composite, engine, pool, plan) = unsafe { (&mut *screen, &*composite, &*engine, &*pool, &*plan) };
    // SAFETY: see the function's contract.
    let changed = unsafe { *changed.cast::<[i32; 4]>() };
    let (chains, mask) = (plan.chained(), plan.masked());
    let plan = plan.plan(pool.pages(), &chains, mask.as_ref());
    screen.compose(engine, composite, &plan, changed, composite.widest()).is_some()
}

/// Composites `plan` onto `screen`'s canvas, nothing composed on it yet,
/// over its tiles that meet the pixels `fresh` — [left, top, right,
/// bottom) — and copies every other tile `film`'s canvas keeps from it as
/// it is; submits the work. False on failure; see the last error.
///
/// # Safety
/// Every pointer is live, the pool and the executor were made on `engine`,
/// `film` is not `screen`; `fresh` holds four words.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_screen_compose_over(
    screen: *mut Screen,
    film: *const Screen,
    composite: *const Composite,
    engine: *const Engine,
    pool: *const Pool,
    plan: *const Planned,
    fresh: *const i32,
) -> bool {
    // SAFETY: see the function's contract.
    let (screen, film, composite, engine, pool, plan) =
        unsafe { (&mut *screen, &*film, &*composite, &*engine, &*pool, &*plan) };
    // SAFETY: see the function's contract.
    let fresh = unsafe { *fresh.cast::<[i32; 4]>() };
    let (chains, mask) = (plan.chained(), plan.masked());
    let plan = plan.plan(pool.pages(), &chains, mask.as_ref());
    screen.compose_over(engine, composite, &plan, film, fresh, composite.widest()).is_some()
}

/// Shows `screen`'s canvas through the camera onto the pixels `rect` of
/// `target` — [left, top, right, bottom) — leaving the rest of it as it
/// was, and waits for the GPU; returns how many passes it took, -1 on
/// failure (see the last error). The camera is `inverse` — a screen pixel
/// to the canvas's, the affine `[a, b, c, d, e, f]` — at display `scale`,
/// device pixels a canvas pixel, sampled by `sampling` (0 blend, 1 pick,
/// 3 nearest). `target` is a surface's texture or a window's next image,
/// as `gpu_engine_composite_show`'s is.
///
/// # Safety
/// Every pointer is live, made on `engine`; `inverse` holds six doubles
/// and `rect` four words.
#[unsafe(no_mangle)]
#[allow(clippy::too_many_arguments)]
pub unsafe extern "C" fn gpu_engine_screen_show(
    screen: *mut Screen,
    composite: *const Composite,
    engine: *const Engine,
    inverse: *const f64,
    scale: f64,
    sampling_id: u32,
    target: *const wgpu::Texture,
    rect: *const u32,
) -> isize {
    // SAFETY: see the function's contract.
    let (screen, composite, engine, target) = unsafe { (&mut *screen, &*composite, &*engine, &*target) };
    // SAFETY: see the function's contract.
    let (inverse, rect) = unsafe { (*inverse.cast::<[f64; 6]>(), *rect.cast::<[u32; 4]>()) };
    let Some(mode) = sampling(sampling_id) else {
        return -1;
    };
    let camera = Camera { inverse, scale, mode };
    let shown = screen.show(engine, composite, camera, target, rect, composite.widest());
    shown.map_or(-1, |passes| passes as isize)
}
