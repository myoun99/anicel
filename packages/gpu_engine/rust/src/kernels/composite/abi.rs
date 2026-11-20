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

use std::sync::atomic::{AtomicI64, AtomicU64, Ordering};
use std::sync::{Arc, Mutex, MutexGuard, PoisonError, Weak};

use crate::device::{Engine, Sent, let_go, let_go_unwaited, posted_of};
use crate::fail;
use crate::kernels::chain::{ChainRead, Chained, MapTiles, Op};
use crate::kernels::effects::blur::TileRect;
use crate::kernels::effects::blur::gaussian::{Blur, Edge, Way};
use crate::kernels::effects::blur::iris::{Focus, Iris};
use crate::kernels::effects::blur::lens::{BlurMap, Lens, Light, MapChannel};
use crate::kernels::effects::blur::line::LinePass;
use crate::kernels::effects::{KEYS_PER_RUN, KeyRun, MATRIX_WORDS, matrix_words};
use crate::kernels::mask::{Mask, MaskBox};
use crate::kernels::pool::{Lying, Pool, Stamps, Taken, Weighs};
use crate::kernels::shared::{Counted, ResampleMap, ResampleMode, words_buffer};
use crate::platform::surface_format;

use super::held::{HeldChains, held_bytes};
use super::kept::Kept;
use super::screen::{Camera, Screen};
use super::{
    BufferChain, Composite, Composited, KeyChain, Named, Nesting, Over, Plan, Step, TILE_BYTES,
    TileSet,
};

/// A plan as the app builds it: what [`Plan`] borrows, owned. It names
/// the pool's slots and holds none of them: build it, and run it before
/// the pool lets those slots go (캔버스 베이스 패널, 11-07 22:30).
#[derive(Default)]
pub(crate) struct Planned {
    sets: Vec<Named>,
    /// Its sets as last laid — each tile where it lay by the pool's books
    /// of the number kept with them ([`Lying::as_of`]) —, till the books
    /// say another or a set is added: a plan is laid at each run, show
    /// and compose of a frame, and a tile moves once it is at rest.
    sets_laid: Mutex<Option<(u64, Arc<Vec<TileSet>>)>>,
    keys: Vec<KeyChain>,
    matrices: Vec<[u32; MATRIX_WORDS]>,
    chains: Vec<PlannedChain>,
    maps: Vec<PlannedMap>,
    steps: Vec<Step>,
    mask: Option<MaskPlane>,
    weighed: Weighed,
}

/// The tiles a picture of a plan was weighed as ([`gpu_engine_plan_weigh`]):
/// written on the engine's thread, read on its caller's once that body has
/// told it ([`gpu_engine_plan_weighed`]) — -1 before any, and where it
/// could not be weighed.
struct Weighed(AtomicI64);

impl Default for Weighed {
    fn default() -> Self {
        Self(AtomicI64::new(-1))
    }
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
    /// `plane` — bytes over `size` whose top-left pixel is `at`, of
    /// `engine` — kept for the app, counted among its masks until it lets
    /// it go ([`gpu_engine_mask_free`]).
    pub(crate) fn kept(engine: &Engine, plane: wgpu::Buffer, at: (i32, i32), size: MaskBox) -> *mut MaskPlane {
        engine.hands_counted(MaskPlane { plane, at, size }, Counted::among(&MASK_BYTES, size.bytes()))
    }

    pub(crate) fn mask(&self) -> Mask<'_> {
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
    /// It as the plan a run walks — `pool`'s pages, its chains and its
    /// mask named — handed to `run`: what `run` makes of it. ⛔ONE LAYING:
    /// the run, the show and the screen's two composes each spelled it,
    /// and the fill's picture came as a fifth (11-12).
    pub(crate) fn laid<T>(&self, pool: &Pool, run: impl FnOnce(&Plan) -> T) -> T {
        self.laid_on((pool.pages(), &pool.lying(), None), run)
    }

    /// [`Self::laid`] on a pool as it was taken ([`Pool::taken`]) — its
    /// stamps with it, by which a picture kept of the plan is told by what
    /// it is made of ([`Plan::stamps`]): what a body handed over unwaited
    /// lays it on, the pool's books its caller's to keep meanwhile
    /// ([`gpu_engine_screen_compose`]).
    fn laid_as_taken<T>(&self, pool: &Taken, run: impl FnOnce(&Plan) -> T) -> T {
        self.laid_on((&pool.pages, &pool.lying, Some(&pool.stamps)), run)
    }

    /// It laid on `pages`, each tile its sets name where it lies by
    /// `lying` ([`Named::lying`]).
    fn laid_on<T>(
        &self,
        (pages, lying, stamps): (&[wgpu::Buffer], &Lying, Option<&Stamps>),
        run: impl FnOnce(&Plan) -> T,
    ) -> T {
        let (chains, mask, sets) = (self.chained(), self.masked(), self.sets_lying(lying));
        let plan = Plan {
            pages,
            sets: &sets,
            keys: &self.keys,
            matrices: &self.matrices,
            chains: &chains,
            steps: &self.steps,
            mask: mask.as_ref(),
            stamps,
        };
        run(&plan)
    }

    /// Its tile sets, each tile where it lies by `lying` — those last laid,
    /// where the books say the number they were laid by.
    fn sets_lying(&self, lying: &Lying) -> Arc<Vec<TileSet>> {
        let mut laid = self.sets_laid.lock().unwrap_or_else(PoisonError::into_inner);
        match &*laid {
            Some((as_of, sets)) if *as_of == lying.as_of() => sets.clone(),
            _ => {
                let sets: Vec<TileSet> = self.sets.iter().map(|set| set.lying(lying)).collect();
                let sets = Arc::new(sets);
                *laid = Some((lying.as_of(), sets.clone()));
                sets
            }
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

    /// Whether the plan has every tile set of `sets` — false, the last
    /// error, where it has not.
    fn names_sets(&self, sets: &[u32]) -> bool {
        match sets.iter().find(|&&set| set as usize >= self.sets.len()) {
            Some(set) => fail::<()>(format!("no tile set {set} of {}", self.sets.len())).is_some(),
            None => true,
        }
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
            match step.nesting() {
                Nesting::Opens if closed == 0 => return Some(at),
                Nesting::Opens => closed -= 1,
                Nesting::Closes => closed += 1,
                Nesting::Draws => {}
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
pub(crate) fn sampling(id: u32) -> Option<ResampleMode> {
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

/// A plan of no steps, `engine`'s to let go of.
///
/// # Safety
/// `engine` is live.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_plan_new(engine: *const Engine) -> *mut Planned {
    // SAFETY: see the function's contract.
    let engine = unsafe { &*engine };
    engine.hands(Planned::default())
}

/// Lets go of `plan` on the engine's thread, its caller waiting for none of
/// it: a plan is let go of as a compose handed over unwaited is through
/// with it — behind it in turn (`gpu_engine_screen_compose`) — and a plan
/// counts nothing to read as its free returns (`device::let_go_unwaited`
/// has which do). 🚨Waited for, the UI's thread stood behind the compose
/// it had just handed over, every frame.
///
/// # Safety
/// `plan` came from `gpu_engine_plan_new`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_plan_free(plan: *mut Planned) {
    // SAFETY: see the function's contract.
    unsafe { let_go_unwaited(plan) };
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
    plan.sets.push(Named::from_words(x0, y0, columns, rows, words));
    // What was laid of its sets was laid of one fewer.
    *plan.sets_laid.get_mut().unwrap_or_else(PoisonError::into_inner) = None;
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
    engine.on_thread(|| {
        let usage = wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC;
        let plane = words_buffer(engine, "mask", &size.words_of(bytes), usage);
        MaskPlane::kept(engine, plane, (x, y), size)
    })
}

/// # Safety
/// `mask` came from `gpu_engine_mask_new` or
/// `gpu_engine_selection_mask_new`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_mask_free(mask: *mut MaskPlane) {
    // SAFETY: see the function's contract.
    unsafe { let_go_unwaited(mask) };
}

/// Copies `mask`'s bytes — a byte a pixel, row after row, the app's
/// `Uint8List` as it is: as many as its box's width × height — into
/// `bytes` once the GPU is done. False where `capacity` is not that many,
/// or on failure; see the last error.
///
/// # Safety
/// `engine` and `mask` are live, `mask` made on `engine`, and `bytes`
/// holds `capacity`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_mask_read(
    engine: *const Engine,
    mask: *const MaskPlane,
    bytes: *mut u8,
    capacity: usize,
) -> bool {
    // SAFETY: see the function's contract.
    let (engine, MaskPlane { plane, size, .. }) = unsafe { (&*engine, &*mask) };
    engine.on_thread(|| {
        // SAFETY: `bytes` holds `capacity`.
        let into = unsafe { std::slice::from_raw_parts_mut(bytes, capacity) };
        size.read_into(engine, plane, into)
    })
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

/// Weighs the picture a screen makes of `plan` laid afresh over the pixels
/// `extent` — [left, top, right, bottom) —: of the tiles it lays anything
/// on, each the engine's pictures keep none for yet
/// ([`Kept::tiles_made`]). On the engine's thread, its caller waiting for
/// none of it ([`Engine::posted`]); `told` is called there with `number`
/// once it is weighed — false where `extent` lies past the grid — and
/// what it weighs is read from then on ([`gpu_engine_plan_weighed`]). The
/// pool's pages and its stamps are taken as it is called, as the compose
/// that makes the picture takes them ([`gpu_engine_screen_compose`]);
/// `plan` is read as it runs.
///
/// ⛔Not a failure of its caller's next done, as a body's is: that done
/// is a screen's, asked for the frame it puts up, and the weigh has its
/// own word.
///
/// 🚨ON THE ENGINE'S THREAD, IN ITS TURN (F-610, 2026-11-19) — not on its
/// caller's, where a plan was weighed till then, by the tiles it lays on
/// alone: the pictures' books are held while a page of their pool is made
/// (`Pictures::fresh`), and the UI's thread asking them stood behind
/// that; and behind the composes handed over before it, a picture is
/// weighed against those as kept — a cut's second against its first, which
/// is still on its way when the second is asked for.
///
/// # Safety
/// Every pointer is live, the pool made on `engine`; `extent` holds four
/// words. Nothing adds to `plan` from here on, and it is let go of on the
/// engine's thread ([`let_go`]), behind this in turn. `told` is one any
/// thread may call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_plan_weigh(
    plan: *const Planned,
    engine: *const Engine,
    pool: *const Pool,
    extent: *const i32,
    told: extern "C" fn(u64, bool),
    number: u64,
) {
    // SAFETY: see the function's contract.
    let (extent, pool) = unsafe { (*extent.cast::<[i32; 4]>(), (*pool).taken()) };
    let handed = Sent((plan, engine));
    // SAFETY: see the function's contract.
    unsafe { &*engine }.posted(move || {
        let (plan, engine) = handed.taken();
        // SAFETY: live till let go of, behind this (the function's
        // contract).
        let (plan, engine) = unsafe { (&*plan, &*engine) };
        let tiles = plan.laid_as_taken(&pool, |laid| Kept::tiles_made(laid, extent, &engine.pictures));
        let weighed = tiles.map_or(-1, |tiles| i64::try_from(tiles).unwrap_or(i64::MAX));
        plan.weighed.0.store(weighed, Ordering::Relaxed);
        told(number, tiles.is_some());
        Some(())
    });
}

/// The tiles `plan`'s picture was weighed as, by the last weigh of it that
/// has told ([`gpu_engine_plan_weigh`]) — -1 before any, and where that
/// one could not weigh it.
///
/// # Safety
/// `plan` is live.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_plan_weighed(plan: *const Planned) -> i64 {
    // SAFETY: see the function's contract.
    unsafe { &*plan }.weighed.0.load(Ordering::Relaxed)
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

/// Adds to effect chain `chain` a read of what the ops before it put
/// ([`Op::Read`]), kept on the device for a plug-in to run over, with
/// `rows` — `count` of the plan's tile sets, the rows its layer values name
/// by slot — kept as they are stored over the chain's rectangle. 0, or -1
/// where the plan has no such chain or set; see the last error.
///
/// # Safety
/// `plan` and `read` are live, and `rows` holds `count` words.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_plan_chain_read(
    plan: *mut Planned,
    chain: u32,
    read: *const ChainRead,
    rows: *const u32,
    count: usize,
) -> i32 {
    // SAFETY: see the function's contract.
    let (plan, read) = unsafe { (&mut *plan, &*read) };
    let rows = match count {
        0 => Vec::new(),
        // SAFETY: see the function's contract.
        _ => unsafe { std::slice::from_raw_parts(rows, count) }.to_vec(),
    };
    if !plan.names_sets(&rows) {
        return -1;
    }
    plan.op(chain, Op::Read { read: read.clone(), rows }, None)
}

/// Adds to effect chain `chain` what a plug-in made ([`Op::Put`]): the
/// plan's tile set `set`, its tiles as the plug-in's run landed them in the
/// pool, laid over the chain's rectangle in place of what the ops before it
/// put. 0, or -1 where the plan has no such chain or set; see the last
/// error.
///
/// 🚨★A KEPT STEP IS PUT BY EVERY PLAN (ink-trails-further-on-intel-since-
/// the-screen-waits-for-the-gpu, 관제 2026-11-13 「한 번 만들고 계획마다
/// 이름만」): a frame is planned again at each write a pen makes, and the
/// plug-in's picture kept past its recording came as bytes each time —
/// copied twice a plan. 🔬Surface Pro 11, 11-13: 25–40 ms of a write's 33
/// planned, 29.7–44.5 MB of 2–3 pictures, while what the pen changed was
/// some 50 × 43 pixels. Its tiles stay in the pool: a plan names them.
///
/// # Safety
/// `plan` is live.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_plan_chain_put(plan: *mut Planned, chain: u32, set: u32) -> i32 {
    // SAFETY: see the function's contract.
    let plan = unsafe { &mut *plan };
    if !plan.names_sets(&[set]) {
        return -1;
    }
    plan.op(chain, Op::Put(set), None)
}

/// A read of a chain's picture for the host ([`ChainRead`]), empty,
/// `engine`'s to let go of.
///
/// # Safety
/// `engine` is live.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_chain_read_new(engine: *const Engine) -> *mut ChainRead {
    // SAFETY: see the function's contract.
    let engine = unsafe { &*engine };
    engine.hands(ChainRead::default())
}

/// Lets go of what `read` keeps that no plan names.
///
/// # Safety
/// `read` came from `gpu_engine_chain_read_new`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_chain_read_free(read: *mut ChainRead) {
    // SAFETY: see the function's contract.
    unsafe { let_go(read) };
}

/// Reads into `out`, `length` bytes, what `read` kept of the rectangle its
/// four edges `picture` name — of its chain, or of its row `row` where that is
/// not negative. False where no plan ran through it, it keeps no such row,
/// or the device failed; see the last error. ⚠️Waits for the GPU: a test's
/// read, and a test's stand-in plug-in's (`ChainRead::pixels`).
///
/// # Safety
/// `engine` and `read` are live, `picture` holds four edges and `out` holds
/// `length` writable bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_chain_read_pixels(
    engine: *const Engine,
    read: *const ChainRead,
    picture: *const i32,
    row: i32,
    out: *mut u8,
    length: usize,
) -> bool {
    // SAFETY: see the function's contract.
    let (engine, read, picture) = unsafe { (&*engine, &*read, *picture.cast::<[i32; 4]>()) };
    let row = usize::try_from(row).ok();
    engine.on_thread(|| {
        let Some(bytes) = read.pixels(engine, picture, row) else {
            return false;
        };
        if bytes.len() != length {
            return fail::<()>(format!("{} bytes read into {length}", bytes.len())).is_some();
        }
        // SAFETY: `out` holds `length` writable bytes, and `bytes` as many.
        unsafe { std::ptr::copy_nonoverlapping(bytes.as_ptr(), out, length) };
        true
    })
}

/// A hold for what the chains of the plans that name it put
/// ([`gpu_engine_plan_chain_held`]), empty, `engine`'s to let go of.
///
/// # Safety
/// `engine` is live.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_held_new(engine: *const Engine) -> *mut HeldChains {
    // SAFETY: see the function's contract.
    let engine = unsafe { &*engine };
    engine.hands(HeldChains::default())
}

/// Lets go of everything `held` keeps that no plan names; what one does is
/// let go with the plan.
///
/// # Safety
/// `held` came from `gpu_engine_held_new`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_held_free(held: *mut HeldChains) {
    // SAFETY: see the function's contract.
    unsafe { let_go(held) };
}

/// Lets go of what `held` keeps under `id`, if anything — buffers, so on
/// its engine's thread: in turn behind the bodies handed there before
/// it, its caller waiting for none of it ([`posted_of`] has why, and
/// when the bytes read gone). What is handed over is the same hold
/// ([`HeldChains`] — a clone is), so it outlives a free asked behind it.
///
/// # Safety
/// `held` is live.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_held_let_go(held: *const HeldChains, id: u32) {
    // SAFETY: see the function's contract.
    let chains = unsafe { &*held }.clone();
    // SAFETY: see the function's contract.
    unsafe { posted_of(held, move || chains.let_go(id)) };
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
    engine.on_thread(|| {
        Composite::new(engine).map_or(std::ptr::null_mut(), |composite| engine.hands(composite))
    })
}

/// The executor, its full pass compiled and with it the one that stores to
/// a surface of BGRA or RGBA 8-bit unorm texels — as
/// `gpu_engine_surface_new` makes for the same `bgra`, and a window is
/// RGBA — the two at once ([`Composite::showing`]): an app asks where it
/// makes the executor, off the thread its frames are built on, and its
/// first show compiles nothing there. Null on failure; see the last error.
///
/// # Safety
/// `engine` is live; the executor is freed before it.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_composite_showing(engine: *const Engine, bgra: bool) -> *mut Composite {
    // SAFETY: see the function's contract.
    let engine = unsafe { &*engine };
    engine.on_thread(|| {
        Composite::showing(engine, Some(surface_format(bgra)))
            .map_or(std::ptr::null_mut(), |composite| engine.hands(composite))
    })
}

/// Compiles the effect chains' blurs on the calling thread if they are not
/// compiled, and waits where another thread is at it
/// ([`Composite::chains`]): an app asks off the thread its frames are built
/// on, and runs no plan that names a chain before this has returned.
///
/// # Safety
/// `composite` and `engine` are live.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_composite_chains(composite: *const Composite, engine: *const Engine) {
    // SAFETY: see the function's contract.
    let (composite, engine) = unsafe { (&*composite, &*engine) };
    engine.on_thread(|| {
        composite.chains(engine);
    })
}

/// # Safety
/// `composite` came from `gpu_engine_composite_new`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_composite_free(composite: *mut Composite) {
    // SAFETY: see the function's contract.
    unsafe { let_go(composite) };
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
    engine.on_thread(|| {
        // SAFETY: see the function's contract.
        let (words, extent) = unsafe { (std::slice::from_raw_parts(tiles, 2 * count), *extent.cast::<[i32; 4]>()) };
        let tiles: Vec<(i32, i32)> = words.chunks_exact(2).map(|tile| (tile[0], tile[1])).collect();
        let widest = composite.widest();
        let ran = plan.laid(pool, |laid| composite.run(engine, laid, &tiles, extent, widest));
        ran.map_or(std::ptr::null_mut(), |composited| engine.hands(composited))
    })
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
    engine.on_thread(|| {
        let Some(read) = engine.read_buffer(&composited.out) else {
            return false;
        };
        let count = read.len().min(capacity);
        // SAFETY: `bytes` holds `capacity`, and `count` is no more.
        unsafe { std::ptr::copy_nonoverlapping(read.as_ptr(), bytes, count) };
        true
    })
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
    // SAFETY: see the function's contract.
    unsafe { let_go(composited) };
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
    engine.on_thread(|| {
        // SAFETY: see the function's contract.
        let rect = unsafe { *rect.cast::<[u32; 4]>() };
        let widest = composite.widest();
        let shown = plan.laid(pool, |laid| composite.show(engine, laid, target, rect, widest));
        shown.map_or(-1, |passes| passes as isize)
    })
}

/// The screen of a canvas's composite over the pixels `extent` — [left,
/// top, right, bottom): the page and what lies past it — shown on Blend's
/// radius `floor` at least, nothing composed on it yet. Null on failure;
/// see the last error.
///
/// # Safety
/// `engine` is live, and `extent` holds four words.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_screen_new(
    engine: *const Engine,
    extent: *const i32,
    floor: f64,
) -> *mut Arc<ScreenAndBytes> {
    // SAFETY: see the function's contract.
    let engine = unsafe { &*engine };
    // SAFETY: see the function's contract.
    let extent = unsafe { *extent.cast::<[i32; 4]>() };
    Screen::new(extent, floor).map_or(std::ptr::null_mut(), |screen| {
        let screen = Arc::new(ScreenAndBytes::new(screen));
        // Its canvas is kept in the engine's pictures (`Kept::made`),
        // whose rest tells it to weigh again ([`Weighs`]).
        let weighs: Weak<ScreenAndBytes> = Arc::downgrade(&screen);
        engine.pictures.weighed_by(weighs);
        engine.hands(screen)
    })
}

/// Lets go of `screen` on the engine's thread, its caller waiting for none
/// of it — behind the bodies handed over ahead, which read it as they
/// run —, its part of [`KEPT_BYTES`] counted off here first
/// ([`ScreenAndBytes::counted_off`]; `device::let_go_unwaited` has why a
/// free that counts does so). 🚨Waited for, the UI stood behind every
/// compose handed over ahead of it: 44.2 ms as a row's onion came on, 80.4
/// and 36.0 ms with every one on (🔬캔버스 베이스 패널, the Surface, profile,
/// 2026-11-15 18:17 — the-ui-thread-never-enters-the-driver, 「다음 문」).
/// ⏳브러시/렌더링 2026-11-16; the user's to overturn.
///
/// # Safety
/// `screen` came from `gpu_engine_screen_new`, and is let go of once.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_screen_free(screen: *mut Arc<ScreenAndBytes>) {
    // SAFETY: see the function's contract.
    if let Some(kept) = unsafe { screen.as_ref() } {
        kept.counted_off();
    }
    // SAFETY: see the function's contract.
    unsafe { let_go_unwaited(screen) };
}

/// The bytes `screen` keeps — its canvas's tiles: what the budgets and
/// the memory census weigh it by, as its last body handed
/// over left them, and as the last rest's folds, through, left them
/// since ([`ScreenAndBytes`]).
///
/// # Safety
/// `screen` came from `gpu_engine_screen_new`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_screen_bytes(screen: *const Arc<ScreenAndBytes>) -> u64 {
    // SAFETY: see the function's contract.
    unsafe { &*screen }.bytes.load(Ordering::Relaxed)
}

/// A screen as the ABI hands it out: the screen, in the hands of its
/// verbs' bodies alone — each handed to the engine's thread unwaited
/// ([`Engine::posted`]) — and the bytes it keeps, told there as they
/// change: what the budgets and the census read on their own thread
/// ([`gpu_engine_screen_bytes`]) while such a body is under way, and its
/// part of [`KEPT_BYTES`] till its free.
///
/// Handed out in an `Arc`: the pictures' pool keeps a hand on it too,
/// weak, to tell it to weigh again once a rest's folds are through
/// ([`Weighs`]) — a picture no body comes to after the rest, a
/// playback's, would tell what it weighed before the folds for good.
pub(crate) struct ScreenAndBytes {
    screen: Mutex<Screen>,
    bytes: AtomicU64,
    /// Whether [`KEPT_BYTES`] holds `bytes` still: till its free counts
    /// them off ([`ScreenAndBytes::counted_off`]) on its caller's thread,
    /// as a body handed over ahead may still run and tell. Told and
    /// counted off under it alone: a body's tail holds it for two words,
    /// and never the free for the body.
    counted: Mutex<bool>,
}

impl ScreenAndBytes {
    fn new(screen: Screen) -> Self {
        let bytes = screen.bytes();
        KEPT_BYTES.fetch_add(bytes, Ordering::Relaxed);
        let (screen, bytes) = (Mutex::new(screen), AtomicU64::new(bytes));
        Self { screen, bytes, counted: Mutex::new(true) }
    }

    fn kept(&self) -> MutexGuard<'_, Screen> {
        self.screen.lock().unwrap_or_else(PoisonError::into_inner)
    }

    /// What `work` makes of the screen, in its hands — and the bytes it
    /// keeps told after.
    fn with<T>(&self, work: impl FnOnce(&mut Screen) -> T) -> T {
        let mut screen = self.kept();
        let worked = work(&mut screen);
        self.told(screen.bytes());
        worked
    }

    /// `bytes` told as what it keeps, and its part of [`KEPT_BYTES`] moved
    /// by as many in one step — till its free has counted it off.
    fn told(&self, bytes: u64) {
        let counted = self.counted.lock().unwrap_or_else(PoisonError::into_inner);
        let had = self.bytes.swap(bytes, Ordering::Relaxed);
        if *counted {
            // Up or down in one step: the difference, wrapped, takes where
            // the bytes are fewer, as `fetch_add` wraps too.
            KEPT_BYTES.fetch_add(bytes.wrapping_sub(had), Ordering::Relaxed);
        }
    }

    /// Its part of [`KEPT_BYTES`] counted off, by its free's caller: the
    /// bodies handed over ahead of the free may still run, and what they
    /// tell from here counts nowhere.
    fn counted_off(&self) {
        let mut counted = self.counted.lock().unwrap_or_else(PoisonError::into_inner);
        *counted = false;
        KEPT_BYTES.fetch_sub(self.bytes.load(Ordering::Relaxed), Ordering::Relaxed);
    }
}

impl Weighs for ScreenAndBytes {
    fn weighs_again(&self) {
        self.with(Screen::weighed_again);
    }
}

/// The bytes every screen keeps — its canvas's ([`Screen::bytes`]) —,
/// each as its last body told them, till its free:
/// what [`gpu_engine_kept_bytes`] reads, for the leak pins.
///
/// ↩️Counted where a picture's tiles were made and dropped (kept.rs's
/// `Kept`) till 2026-11-16, when a screen's free came to wait for none of
/// the bodies ahead of it ([`gpu_engine_screen_free`]): counted off where
/// it is dropped, it would read late; counted off ahead, by what its last
/// body told, a body still under way would count the tiles it made and
/// dropped past it — off twice, or below nothing. Counted where the screen
/// tells its bytes, a screen's part moves in one step, and its free takes
/// it whole.
static KEPT_BYTES: AtomicU64 = AtomicU64::new(0);

/// The bytes of every picture the engine keeps — every screen's canvas
/// ([`KEPT_BYTES`]).
#[unsafe(no_mangle)]
pub extern "C" fn gpu_engine_kept_bytes() -> u64 {
    KEPT_BYTES.load(Ordering::Relaxed)
}

/// The bytes `engine` keeps for pictures that are no picture's: the slots
/// nobody holds on the pages of their pool (kernels/pool's `Pictures`) —
/// they stay made for the next picture — the composite's work buffer
/// ([`super::Work`]) and the buffers its composes run in, kept from one
/// to the next while a hand is at work and none at rest
/// ([`super::Spares`]). For the memory census, which weighs each picture
/// by its own tiles (`gpu_engine_screen_bytes`).
///
/// # Safety
/// `engine` is live.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_pictures_idle_bytes(engine: *const Engine) -> u64 {
    // SAFETY: see the function's contract.
    let engine = unsafe { &*engine };
    engine.pictures.idle_bytes() + engine.work.bytes() + engine.spares.bytes()
}

/// The bytes of the tiles `engine`'s pictures hold that none of them
/// weighs: made by a picture let go since, and held by others made of the
/// same (kernels/pool's `Told`; F-610 — a tile is weighed once, by the
/// picture that made it, `gpu_engine_screen_bytes`). What the playback's
/// budget and the memory census weigh beside the pictures' own, as the
/// last picture let go left them.
///
/// # Safety
/// `engine` is live.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_pictures_unowned_bytes(engine: *const Engine) -> u64 {
    // SAFETY: see the function's contract.
    unsafe { &*engine }.pictures.unowned_bytes()
}

/// Gives back what `engine` keeps for pictures nobody holds
/// (`gpu_engine_pictures_idle_bytes`) till it is `most_idle` bytes: the
/// pages of their pool with every slot free, the last first
/// (`Pictures::give_back`), then the buffers the last walk made for
/// itself ([`super::Spares`]) and then the composite's work buffer
/// ([`super::Work`]), each where what is left is still past it. All of it at a
/// memory warning; where a budget moved, what lies past the room the
/// budget has left — as the cels' pool keeps within its own
/// (`gpu_engine_pool_give_back`).
///
/// # Safety
/// `engine` is live.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_pictures_give_back(engine: *const Engine, most_idle: u64) {
    // SAFETY: see the function's contract.
    let engine = unsafe { &*engine };
    engine.on_thread(|| {
        engine.pictures.give_back(engine, most_idle);
        let kept = || engine.pictures.idle_bytes() + engine.work.bytes() + engine.spares.bytes();
        if kept() > most_idle {
            engine.spares.let_go();
        }
        if kept() > most_idle {
            engine.work.let_go();
        }
    })
}

/// The hand rests: lets go of every buffer `engine`'s composes ran in and
/// kept for the next ([`super::Spares`]), and keeps none that comes home
/// from then till a compose takes one again (`Spares::rest`); and folds
/// the tiles of the pictures it keeps, till a picture is made again
/// (`Pictures::rests`) — on the
/// engine's thread, in turn behind what was handed to it before
/// ([`Engine::posted`]), its caller waiting for none of it. ⛔Not ahead of
/// that turn: a compose handed over and not yet run takes a spare as it
/// runs, a hand at work by the engine's books, and what it brought home
/// would lie there through the rest. The driver's letting go is the
/// thread for pages' (`Spares::dropping_on`).
///
/// 🗣️유저 2026-11-20 23:20 (a-transform-drag-over-folder-rows-draws-a-
/// frame-in-a-third-of-a-second-Q1 = b): 「손을 떼면 바로 놓는다」 — the
/// law and its words are at the head of spares.rs. When a hand rests is
/// its caller's to say (`GpuEngine.restsAfter`).
///
/// # Safety
/// `engine` is live, and till what is handed here has run — as what a
/// compose is handed is ([`gpu_engine_screen_compose`]).
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_pictures_rest(engine: *const Engine) {
    let handed = Sent(engine);
    // SAFETY: see the function's contract.
    unsafe { &*engine }.posted(move || {
        // SAFETY: live till this has run (the function's contract).
        let engine = unsafe { &*handed.taken() };
        engine.spares.rest();
        engine.pictures.rests(engine);
        Some(())
    });
}

/// Composites `plan` onto `screen`'s canvas over its tiles that meet the
/// pixels `changed` — [left, top, right, bottom); the whole canvas the
/// first time — and submits the work: on the engine's thread, its caller
/// waiting for none of it ([`Engine::posted`]). Its failure is the calling
/// thread's next done's (`gpu_engine_done_then`). `changed`, the pool's
/// pages and its stamps are taken as it is called; `plan` is read as it
/// runs.
///
/// 🚨THE STAMPS WITH THE PAGES, HERE (F-610): the pool's books are its
/// caller's, and a slot the plan names may be let go and handed out again
/// before this runs — its stamp then another tile's, and a picture told by
/// it taken for one made of that tile.
///
/// # Safety
/// Every pointer is live, the pool and the executor were made on `engine`;
/// `changed` holds four words. Nothing adds to `plan` from here on, and
/// what is handed is let go of on the engine's thread ([`let_go`]), behind
/// this in turn.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_screen_compose(
    screen: *const Arc<ScreenAndBytes>,
    composite: *const Composite,
    engine: *const Engine,
    pool: *const Pool,
    plan: *const Planned,
    changed: *const i32,
) {
    // SAFETY: see the function's contract.
    let (changed, pool) = unsafe { (*changed.cast::<[i32; 4]>(), (*pool).taken()) };
    let handed = Sent((screen, composite, engine, plan));
    // SAFETY: see the function's contract.
    unsafe { &*engine }.posted(move || {
        let (screen, composite, engine, plan) = handed.taken();
        // SAFETY: live till let go of, behind this (the function's
        // contract).
        let (screen, composite, engine, plan) = unsafe { (&*screen, &*composite, &*engine, &*plan) };
        plan.laid_as_taken(&pool, |plan| {
            screen.with(|screen| screen.compose(engine, composite, plan, changed, composite.widest()))
        })
    });
}

/// Composites `plan` onto `screen`'s canvas, nothing composed on it yet,
/// over its tiles that meet the pixels `fresh` — [left, top, right,
/// bottom) — and copies every other tile `film`'s canvas keeps from it as
/// it is; submits the work, as [`gpu_engine_screen_compose`] does.
///
/// # Safety
/// As [`gpu_engine_screen_compose`]'s, and `film` is not `screen`; `fresh`
/// holds four words.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gpu_engine_screen_compose_over(
    screen: *const Arc<ScreenAndBytes>,
    film: *const Arc<ScreenAndBytes>,
    composite: *const Composite,
    engine: *const Engine,
    pool: *const Pool,
    plan: *const Planned,
    fresh: *const i32,
) {
    // SAFETY: see the function's contract.
    let (fresh, pool) = unsafe { (*fresh.cast::<[i32; 4]>(), (*pool).taken()) };
    let handed = Sent((screen, film, composite, engine, plan));
    // SAFETY: see the function's contract.
    unsafe { &*engine }.posted(move || {
        let (screen, film, composite, engine, plan) = handed.taken();
        // SAFETY: live till let go of, behind this (the function's
        // contract).
        let (screen, film, composite, engine, plan) =
            unsafe { (&*screen, &*film, &*composite, &*engine, &*plan) };
        let film = film.kept();
        plan.laid_as_taken(&pool, |plan| {
            screen.with(|screen| screen.compose_over(engine, composite, plan, &film, fresh, composite.widest()))
        })
    });
}

/// Shows `screen`'s canvas through the camera onto the pixels `rect` of
/// `target` — [left, top, right, bottom) — leaving the rest of it as it
/// was, and submits the work, as [`gpu_engine_screen_compose`] does. The
/// camera is `inverse` — a screen pixel to the canvas's, the affine
/// `[a, b, c, d, e, f]` — sampled by `sampling` (0 blend, 1 pick, 3
/// nearest). `target` is a surface's texture or a window's next image, as
/// `gpu_engine_composite_show`'s is.
///
/// ↩️It took the display's scale too till 2026-11-19: which halving stage
/// the screen read under 1/16 ([`Screen::show`]).
///
/// # Safety
/// Every pointer is live, made on `engine`; `inverse` holds six doubles
/// and `rect` four words. What is handed is let go of on the engine's
/// thread ([`let_go`]), behind this in turn.
#[unsafe(no_mangle)]
#[allow(clippy::too_many_arguments)]
pub unsafe extern "C" fn gpu_engine_screen_show(
    screen: *const Arc<ScreenAndBytes>,
    composite: *const Composite,
    engine: *const Engine,
    inverse: *const f64,
    sampling_id: u32,
    target: *const wgpu::Texture,
    rect: *const u32,
) {
    // SAFETY: see the function's contract.
    let (inverse, rect) = unsafe { (*inverse.cast::<[f64; 6]>(), *rect.cast::<[u32; 4]>()) };
    let handed = Sent((screen, composite, engine, target));
    // SAFETY: see the function's contract.
    unsafe { &*engine }.posted(move || {
        let (screen, composite, engine, target) = handed.taken();
        // SAFETY: live till let go of, behind this (the function's
        // contract).
        let (screen, composite, engine, target) = unsafe { (&*screen, &*composite, &*engine, &*target) };
        let camera = Camera { inverse, mode: sampling(sampling_id)? };
        let shown = screen.with(|screen| screen.show(engine, composite, camera, target, rect, composite.widest()));
        shown.map(drop)
    });
}
