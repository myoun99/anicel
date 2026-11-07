//! The executor's C ABI (screen-on-the-engine 2a, 2b): the app builds a
//! plan call by call — each tile set, key chain, colour matrix, effect
//! chain and its ops, blur map and step one call, so the plan's layout is
//! written here alone and nowhere in Dart — and runs it over output tiles,
//! or shows it onto a surface. The plan is checked where it runs
//! ([`Composite`]'s walk), as one built in Rust is; a call checks only the
//! indices it adds to — a chain's or a key chain's —, which no plan holds.
//!
//! ⏳All but the selection's mask and the fill range's mark, which come
//! with the flip lane.

#[cfg(test)]
mod tests;

use crate::device::Engine;
use crate::fail;
use crate::kernels::chain::{Chained, MapTiles, Op};
use crate::kernels::effects::blur::TileRect;
use crate::kernels::effects::blur::gaussian::{Blur, Edge, Way};
use crate::kernels::effects::blur::iris::{Focus, Iris};
use crate::kernels::effects::blur::lens::{BlurMap, Lens, Light, MapChannel};
use crate::kernels::effects::blur::line::LinePass;
use crate::kernels::effects::{KEYS_PER_RUN, KeyRun, MATRIX_WORDS, matrix_words};
use crate::kernels::pool::Pool;
use crate::kernels::shared::{ResampleMap, ResampleMode};
use crate::platform::Surface;

use super::{BufferChain, Composite, Composited, KeyChain, Plan, Step, TILE_BYTES, TileSet};

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
}

/// An effect chain as the app builds it: its ops, a lens blur's with its
/// map's index of the plan's, and the rectangle they run over.
struct PlannedChain {
    ops: Vec<(Op<'static>, Option<usize>)>,
    rect: TileRect,
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
    /// The plan of `pages` and `chains` — [`Self::chained`]'s.
    fn plan<'a>(&'a self, pages: &'a [wgpu::Buffer], chains: &'a [Chained<'a>]) -> Plan<'a> {
        Plan {
            pages,
            sets: &self.sets,
            keys: &self.keys,
            matrices: &self.matrices,
            chains,
            steps: &self.steps,
            mask: None,
        }
    }

    /// The effect chains as a plan names them, each lens blur reading its
    /// map.
    fn chained(&self) -> Vec<Chained<'_>> {
        let chained = |chain: &PlannedChain| Chained {
            ops: chain.ops.iter().map(|(op, map)| self.mapped(op, *map)).collect(),
            rect: chain.rect,
        };
        self.chains.iter().map(chained).collect()
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
    plan.chains.push(PlannedChain { ops: Vec::new(), rect: TileRect { x0, y0, columns, rows } });
    plan.chains.len() as u32 - 1
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
    let chains = plan.chained();
    let ran = composite.run(engine, &plan.plan(pool.pages(), &chains), &tiles, extent, composite.widest());
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

/// Composites `plan` onto the pixels `rect` of `surface` — [left, top,
/// right, bottom) — leaving the rest of it as it was, and submits the work;
/// returns how many passes it took, -1 on failure (see the last error).
///
/// # Safety
/// Every pointer is live, made on `engine`; `rect` holds four words.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_composite_show(
    composite: *const Composite,
    engine: *const Engine,
    pool: *const Pool,
    plan: *const Planned,
    surface: *const Surface,
    rect: *const u32,
) -> isize {
    // SAFETY: see the function's contract.
    let (composite, engine, pool, plan, surface) = unsafe { (&*composite, &*engine, &*pool, &*plan, &*surface) };
    // SAFETY: see the function's contract.
    let rect = unsafe { *rect.cast::<[u32; 4]>() };
    let chains = plan.chained();
    let shown = composite.show(engine, &plan.plan(pool.pages(), &chains), &surface.texture, rect, composite.widest());
    shown.map_or(-1, |passes| passes as isize)
}
