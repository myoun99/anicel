//! The row composite — 2단계's executor, round E1 (gpu-canonical-store):
//! a plan of rows, folders and clipping groups, composited on the GPU into
//! output tiles in the blend family's one integer formula. Every route that
//! composites rows — the editing screen, a frame's picture, a panel, an
//! export — is to run this one executor, so what is shown while working and
//! what comes out cannot differ.
//!
//! The plan is the composite tree flattened into steps, bottom to top
//! ([`Step`]); the tree itself stays the app's (composite_tree.dart). E1
//! takes the five node kinds that close per pixel: a row in any pose R1
//! takes (a whole-pixel move being its copy), a folder's buffer, a row over
//! its backdrop (its own mode), a clipping group and its base made opaque.
//! A row's colour keys run on its stored pixels, before R1 poses them.
//! The other effects, adjustments and a cel number's letters (drawn by the
//! engine's glyph path, then a row here) come in later rounds.
//!
//! The pages a pass can bind are few — `max_storage_buffers_per_shader_stage`
//! less the plan and the work buffer, 2 where GLES reports 4 — so a plan is
//! cut into passes, each binding the pages of its run of rows. A copied row
//! whose tiles lie on several pages becomes one step per page: a pixel
//! reads one tile of it, so exactly one of them lays it. Any other pose
//! reads around where a pixel lands, so an output tile's pages are never
//! parted: its row is one step binding every page it reaches or, reaching
//! more than a pass binds, a step for each group of output tiles whose
//! pages a pass does bind. An output tile whose pixels alone reach more is
//! refused. A pass holds a window of the stack in its registers, [`DEPTH`]
//! levels at most, so a tree nested deeper is cut where it leaves the
//! window. Between passes the stack is kept on the 16-bit scale as it was,
//! so the cuts change no value.
//!
//! A row is sampled only on the output tiles where its pose reads a stored
//! tile of it; on any other it would show nothing, so it is skipped there.
//!
//! A row may be laid under the plan's selection (R28 — a stroke landing on
//! its cel under one): its opacity under the mask's byte at the output
//! pixel, nothing past the box, by blend.wgsl's `blend_cover`; a row under
//! none takes 255 by the same multiply. A pass is given the rows of the
//! mask its output tiles lie on, copied into `work` on the GPU and not
//! bound on their own, as the cel pixel verbs are given theirs — so a
//! pass's output tiles span no more tile rows than it takes tiles.
//!
//! A run puts its pixels as output tiles — straight, nothing outside the
//! output's extent, a page a later run can lay as a row — or on a surface
//! Flutter shows, premultiplied, inside a rectangle of it
//! ([`Composite::show`]). The screen is the second with one row: the
//! canvas's composite tiles posed by the camera. The canvas is composited
//! on its own grid first, so a magnified screen shows the canvas's pixels
//! — the result's — and a pan or a zoom runs the screen alone
//! (gpu-canonical-store ④⑤).

// ⏳Nothing outside the tests calls it until the app's bridge round
// (gpu-canonical-store 14:49 — the app connects after the bridges land).
#![cfg_attr(not(test), allow(dead_code))]

#[cfg(test)]
pub(crate) mod tests;

use std::sync::{Arc, Mutex, PoisonError};

use wgpu::util::DeviceExt;

use crate::device::Engine;
use crate::fail;
use crate::kernels::blend::BLEND_WGSL;
use crate::kernels::effects::KEY_WGSL;
use crate::kernels::mask::{BYTE_WGSL, Mask};
use crate::kernels::shared::{
    Encoded, ISQRT_WGSL, Own, PREMULTIPLY_WGSL, Pages, RESAMPLE_WGSL, ResampleMap, TILE_WGSL,
    ResampleModes, WIDE_WGSL, encode_on, le_bytes, page_table, pipeline_with, runs, storage_format,
    tiles_a_pass, whole, words_buffer,
};

/// A tile's side in pixels (1a ①).
pub(crate) const TILE: u32 = 128;
/// A tile's pixels — and its words, one RGBA8 pixel to a word.
pub(crate) const TILE_TEXELS: u64 = (TILE * TILE) as u64;
/// A tile's bytes, straight RGBA8 — as the pool stores it and a pass puts
/// it.
pub(crate) const TILE_BYTES: u64 = TILE_TEXELS * 4;
/// The most stack levels a pass holds in its registers — composite.wgsl's
/// DEPTH. Folders and clips nest deeper by cutting passes where the walk
/// leaves the levels a pass holds; the rest wait in the work buffer.
pub(crate) const DEPTH: usize = 8;
const STEP_WORDS: usize = 13;
const NO_TILE: u32 = u32::MAX;
/// The plan and the work buffer: the storage buffers a pass binds besides
/// its pages — and its pass's words, a uniform one. A device that binds
/// sixteen pages past them binds them past one fewer as well, so no test
/// here tells a count one short; a device of 19 buffers a stage would
/// compile a pass binding twenty.
const OWN_BUFFERS: u32 = 2;

/// Where a stored tile is: a page of the pool, a slot in it.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub(crate) struct TileAt {
    pub(crate) page: u16,
    pub(crate) slot: u16,
}

/// A row's picture on the canvas's tile grid: the tiles of the rectangle
/// whose top-left tile is column `x0`, row `y0`, row by row. `None` is a
/// tile with nothing on it.
pub(crate) struct TileSet {
    pub(crate) x0: i32,
    pub(crate) y0: i32,
    pub(crate) columns: u32,
    pub(crate) rows: u32,
    pub(crate) tiles: Vec<Option<TileAt>>,
}

impl TileSet {
    fn at(&self, column: i32, row: i32) -> Option<TileAt> {
        let (c, r) = (column - self.x0, row - self.y0);
        if c < 0 || r < 0 || c as u32 >= self.columns || r as u32 >= self.rows {
            return None;
        }
        self.tiles[(r as u32 * self.columns + c as u32) as usize]
    }

    /// The tiles of the set under the pixels `[left, top, right, bottom)`,
    /// or all of them for `None`.
    fn under(&self, pixels: Option<[i64; 4]>) -> impl Iterator<Item = TileAt> + '_ {
        let side = i64::from(TILE);
        // In tiles, ends excluded.
        let first = (i64::from(self.x0), i64::from(self.y0));
        let end = (first.0 + i64::from(self.columns), first.1 + i64::from(self.rows));
        let [left, top, right, bottom] = match pixels {
            None => [first.0, first.1, end.0, end.1],
            Some([l, t, r, b]) => [
                l.div_euclid(side).max(first.0),
                t.div_euclid(side).max(first.1),
                (r.saturating_sub(1).div_euclid(side) + 1).min(end.0),
                (b.saturating_sub(1).div_euclid(side) + 1).min(end.1),
            ],
        };
        (top..bottom)
            .flat_map(move |row| (left..right).map(move |column| (column, row)))
            .filter_map(|(column, row)| self.at(column as i32, row as i32))
    }
}

/// A row's colour keys: its runs, `KeyRun::words` each, in the chain's
/// order. They are walked on the row's stored pixels before R1 poses them,
/// as the app keys a cel before it is placed (캔버스 베이스,
/// gpu-canonical-store 11-05 18:24), every run against the pixel's stored
/// alpha.
pub(crate) struct KeyChain {
    pub(crate) runs: Vec<Vec<u32>>,
}

/// One step of a plan, bottom to top. An opacity is on the 16-bit scale
/// (65535 is whole); a mode is blend.wgsl's id, the eraser's among them.
#[derive(Clone, Copy, Debug)]
pub(crate) enum Step {
    /// Tile set `set`, keyed by chain `keys` if any, posed by `map` —
    /// canvas pixel to the row's own — laid at `opacity` in `mode`, under
    /// the plan's mask where `masked`.
    Row {
        set: usize,
        keys: Option<usize>,
        map: ResampleMap,
        opacity: u32,
        mode: u32,
        masked: bool,
    },
    /// Opens a transparent buffer: a folder's, a clip's base or its scope.
    Open,
    /// Opens a buffer holding the one under it with its alpha made whole —
    /// a clip's scope whose rows blend with the base (CompositeOpaque).
    OpenOpaque,
    /// Closes a buffer onto the one under it at `opacity` in `mode`.
    Close { opacity: u32, mode: u32 },
    /// Closes a clip's scope onto its base by the base's alpha (srcATop).
    CloseAtop,
}

/// What one pass may take: pages to bind, output tiles — as many as the
/// work buffer, stack and all, fits in one binding — and stack levels to
/// hold, 2 (a buffer and the one it closes onto) to [`DEPTH`].
#[derive(Clone, Copy, Debug)]
pub(crate) struct Budget {
    pub(crate) pages: usize,
    pub(crate) tiles: usize,
    pub(crate) levels: usize,
}

/// What a run left: every output tile's pixels, straight RGBA8, tile after
/// tile in the order asked — a page a later run can lay as a row, as the
/// screen lays the canvas's — and how many passes it took.
pub(crate) struct Composited {
    pub(crate) out: wgpu::Buffer,
    pub(crate) passes: usize,
}

/// What a plan lays: the pool's pages, the rows' tile sets and key chains,
/// the steps, bottom to top, and the selection its masked rows are laid
/// under — one a plan: the stroke being drawn is the row there is one for
/// (R28, 11-06 06:51).
pub(crate) struct Plan<'a> {
    pub(crate) pages: &'a [wgpu::Buffer],
    pub(crate) sets: &'a [TileSet],
    pub(crate) keys: &'a [KeyChain],
    pub(crate) steps: &'a [Step],
    pub(crate) mask: Option<&'a Mask<'a>>,
}

/// Where a run's last pass puts its pixels.
enum Target<'a> {
    Tiles(&'a wgpu::Buffer),
    Surface(wgpu::TextureView),
}

/// A step as the GPU reads it, the pages it lays a row from — one for a
/// copied row's step, every one its output tiles reach for any other
/// pose's — and, output
/// tile by output tile, whether it lays anything there: a row only where
/// it reads a stored tile on its pages, any other step everywhere.
struct Laid {
    step: Step,
    pages: Vec<u16>,
    live: Vec<bool>,
}

/// A run of steps one pass takes: the pages it binds, in binding order,
/// the lowest stack level it holds, and the depth it starts at.
struct Batch {
    begin: usize,
    end: usize,
    base: usize,
    depth_in: usize,
    depth_out: usize,
    pages: Vec<u16>,
}

/// The composite pass, compiled for as many pages as the device lets a pass
/// bind, once for each output and set of R1 modes ([`Compiled`]).
pub(crate) struct Composite {
    /// Shared with the threads that compile passes apart.
    passes: Arc<Mutex<Passes>>,
    /// The pages of the pool a pass binds, past the plan and the work.
    pages: Pages,
}

impl Composite {
    pub(crate) fn new(engine: &Engine) -> Option<Self> {
        let own = Own { storage: OWN_BUFFERS, uniform: 1 };
        let pages = Pages::new(engine, own, OWN_BUFFERS + 1)?;
        let composite = Self {
            passes: Arc::default(),
            pages,
        };
        composite.pass(engine, Compiled { surface: None, modes: ResampleModes::ALL });
        Some(composite)
    }

    /// All this device lets a pass take.
    pub(crate) fn widest(&self) -> Budget {
        Budget {
            pages: self.pages.per_pass(),
            tiles: usize::MAX,
            levels: DEPTH,
        }
    }

    /// Composites `plan` over the output `tiles` (canvas tile columns and
    /// rows), with nothing outside `extent` — the output's pixels, [left,
    /// top, right, bottom): a canvas's picture ends at the canvas — and
    /// submits the work; the caller waits. A `budget` under
    /// [`Composite::widest`] cuts the run where a smaller device would.
    pub(crate) fn run(
        &self,
        engine: &Engine,
        plan: &Plan,
        tiles: &[(i32, i32)],
        extent: [i32; 4],
        budget: Budget,
    ) -> Option<Composited> {
        let out = engine.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("composite out"),
            size: (tiles.len().max(1) as u64) * TILE_TEXELS * 4,
            usage: wgpu::BufferUsages::STORAGE
                | wgpu::BufferUsages::COPY_DST
                | wgpu::BufferUsages::COPY_SRC,
            mapped_at_creation: false,
        });
        let target = Target::Tiles(&out);
        let passes = self.walk(engine, plan, tiles, extent, None, &target, budget)?;
        Some(Composited { out, passes })
    }

    /// Composites `plan` onto the pixels `rect` of `surface` — [left, top,
    /// right, bottom), the output's pixels being the surface's own — and
    /// leaves the rest of it as it was, the other panels of an atlas;
    /// submits the work, the caller waits, and returns how many passes it
    /// took. The screen is this with one row: the canvas's composite posed
    /// by the camera (gpu-canonical-store ④⑤).
    pub(crate) fn show(
        &self,
        engine: &Engine,
        plan: &Plan,
        surface: &wgpu::Texture,
        rect: [u32; 4],
        budget: Budget,
    ) -> Option<usize> {
        let [left, top, right, bottom] = rect;
        if left >= right || top >= bottom || right > surface.width() || bottom > surface.height() {
            return fail(format!(
                "{rect:?} is no rectangle of a {} × {} surface",
                surface.width(),
                surface.height()
            ));
        }
        let Some(token) = storage_format(surface.format()) else {
            return fail(format!("the composite cannot store to {:?}", surface.format()));
        };
        let tiles: Vec<(i32, i32)> = (top / TILE..bottom.div_ceil(TILE))
            .flat_map(|row| {
                (left / TILE..right.div_ceil(TILE)).map(move |column| (column as i32, row as i32))
            })
            .collect();
        let target = Target::Surface(surface.create_view(&Default::default()));
        let extent = rect.map(|edge| edge as i32);
        self.walk(engine, plan, &tiles, extent, Some(token), &target, budget)
    }

    /// The surface's binding: past the plan, the work buffer and the pages.
    fn surface_binding(&self) -> u32 {
        self.pages.end()
    }

    /// The pass for `wanted`'s output that reads maps of `wanted`'s modes:
    /// the one compiled for those modes once a thread has made it, and
    /// until then the one compiled for every mode, which composites the
    /// same bytes, slower. A compile takes seconds where a frame takes
    /// milliseconds (1.7 s to 6 s cold on this PC, 11-06), so no plan waits
    /// on one but an output's first, compiled for every mode where it is
    /// first asked for — the tiles' in `new` — as before modes came apart.
    fn pass(&self, engine: &Engine, wanted: Compiled) -> wgpu::ComputePipeline {
        let every = Compiled { modes: ResampleModes::ALL, ..wanted };
        let mut passes = self.passes.lock().unwrap_or_else(PoisonError::into_inner);
        if let Some(pipeline) = passes.made(wanted) {
            return pipeline;
        }
        if wanted != every && !passes.making.contains(&wanted) {
            passes.making.push(wanted);
            self.compile_apart(engine, wanted);
        }
        if let Some(pipeline) = passes.made(every) {
            return pipeline;
        }
        let pipeline = compile(engine, &self.pages.source(), &self.output(every), every.modes);
        passes.made.push((every, pipeline.clone()));
        pipeline
    }

    /// `wanted`'s pass compiled on a thread of its own, kept once made.
    fn compile_apart(&self, engine: &Engine, wanted: Compiled) {
        let (engine, passes) = (engine.clone(), Arc::clone(&self.passes));
        let (pages, output) = (self.pages.source(), self.output(wanted));
        std::thread::spawn(move || {
            let pipeline = compile(&engine, &pages, &output, wanted.modes);
            let mut passes = passes.lock().unwrap_or_else(PoisonError::into_inner);
            passes.making.retain(|making| *making != wanted);
            passes.made.push((wanted, pipeline));
        });
    }

    /// What `compiled`'s pass puts its pixels by: to_tiles.wgsl's `put`, or
    /// to_surface.wgsl's for its surface's format.
    fn output(&self, compiled: Compiled) -> String {
        match compiled.surface {
            None => include_str!("to_tiles.wgsl").to_string(),
            Some(token) => include_str!("to_surface.wgsl")
                .replace("__BINDING__", &self.surface_binding().to_string())
                .replace("__FORMAT__", token),
        }
    }

    /// Waits for the passes threads are compiling.
    #[cfg(test)]
    pub(crate) fn settle(&self) {
        let deadline = std::time::Instant::now() + std::time::Duration::from_secs(60);
        while !self.passes.lock().unwrap_or_else(PoisonError::into_inner).making.is_empty() {
            assert!(std::time::Instant::now() < deadline, "a pass compiled apart never came");
            std::thread::sleep(std::time::Duration::from_millis(1));
        }
    }

    /// Walks `plan` over the output `tiles` in passes whose last puts each
    /// pixel to `target` — the output tiles, or a surface of the format
    /// `surface` names —, inside `extent` as it is and outside nothing or
    /// nowhere, and submits the work; returns how many passes it took.
    fn walk(
        &self,
        engine: &Engine,
        plan: &Plan,
        tiles: &[(i32, i32)],
        extent: [i32; 4],
        surface: Option<&'static str>,
        target: &Target,
        budget: Budget,
    ) -> Option<usize> {
        let pages_per_pass = budget.pages;
        if pages_per_pass == 0 || pages_per_pass > self.pages.per_pass() {
            return fail(format!(
                "{pages_per_pass} pages a pass; this device binds 1 to {}",
                self.pages.per_pass()
            ));
        }
        if !(2..=DEPTH).contains(&budget.levels) {
            return fail(format!("{} stack levels a pass; one holds 2 to {DEPTH}", budget.levels));
        }
        check_depth(plan.steps, plan.sets.len(), plan.keys.len())?;
        check_mask(plan)?;
        let laid = lay(plan.steps, plan.sets, tiles, plan.pages.len(), pages_per_pass)?;
        self.walk_laid(engine, plan, &laid, tiles, extent, surface, target, budget)
    }

    /// [`Composite::walk`] from the steps as `lay` laid them.
    fn walk_laid(
        &self,
        engine: &Engine,
        plan: &Plan,
        laid: &[Laid],
        tiles: &[(i32, i32)],
        extent: [i32; 4],
        surface: Option<&'static str>,
        target: &Target,
        budget: Budget,
    ) -> Option<usize> {
        let page_count = plan.pages.len();
        let batches = cut(laid, budget.pages, budget.levels)?;
        let written = plan_words(laid, &batches, plan.sets, plan.keys, tiles, page_count);
        let pipeline = &self.pass(engine, Compiled { surface, modes: written.modes });
        let steps = engine
            .device
            .create_buffer_init(&wgpu::util::BufferInitDescriptor {
                label: Some("composite plan"),
                contents: &written.words,
                usage: wgpu::BufferUsages::STORAGE,
            });
        // The stack is kept between passes only; one pass keeps none.
        let kept = batches[..batches.len() - 1]
            .iter()
            .map(|batch| batch.depth_out as u64 + 1)
            .max()
            .unwrap_or(0);
        // Output tiles wait in `work` past the stack until they are copied
        // out; a surface takes its pixels from the last pass itself.
        let waiting = u64::from(matches!(target, Target::Tiles(_)));
        let held = (kept * 2 + waiting) * TILE_TEXELS * 4;
        let band = plan.mask.map_or(0, Mask::per_tile);
        let per_tile = held + band;
        let chunk = tiles_a_pass(engine, per_tile, 0)?.min(budget.tiles).min(tiles.len().max(1));
        if chunk == 0 {
            return fail("a budget of no tiles a pass");
        }
        let work = engine.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("composite work"),
            // A binding holds something, even where nothing waits.
            size: (chunk as u64 * per_tile).max(16),
            usage: wgpu::BufferUsages::STORAGE
                | wgpu::BufferUsages::COPY_SRC
                | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });
        let mut encoder = engine
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor::default());
        let [left, top, right, bottom] = extent.map(|edge| edge as u32);
        let mut passes = 0;
        let rows: Option<Vec<i32>> =
            plan.mask.map(|_| tiles.iter().map(|&(_, row)| row).collect());
        // An output tile binds no page of the pool.
        for (run, _) in runs(tiles.iter().map(|_| None), rows.as_deref(), 1, chunk) {
            let (first_tile, chunk_tiles) = (run.start, run.len());
            let out_at = kept * 2 * TILE_TEXELS * chunk_tiles as u64;
            let mask_at = out_at + waiting * TILE_TEXELS * chunk_tiles as u64;
            let shape = plan.mask.map_or([0; 6], |mask| {
                let rows = mask.band(tiles[run.clone()].iter().map(|&(_, row)| row));
                let (plane, bytes) = mask.rows(&rows);
                if !bytes.is_empty() {
                    let length = bytes.end - bytes.start;
                    encoder.copy_buffer_to_buffer(plane, bytes.start, &work, mask_at * 4, length);
                }
                [
                    mask_at as u32,
                    mask.size.width,
                    rows.len() as u32,
                    mask.size.stride(),
                    mask.at.0 as u32,
                    (mask.at.1 + rows.start as i32) as u32,
                ]
            });
            let uniforms: Vec<wgpu::Buffer> = batches
                .iter()
                .enumerate()
                .map(|(index, batch)| {
                    let mut words = vec![
                        (batch.begin) as u32,
                        batch.end as u32,
                        batch.depth_in as u32,
                        u32::from(index == 0),
                        u32::from(index == batches.len() - 1),
                        written.tiles_at + written.tile_words * first_tile as u32,
                        written.tile_words,
                        chunk_tiles as u32,
                        out_at as u32,
                        written.tables_at + (index * page_count) as u32,
                        batch.base as u32,
                        left,
                        top,
                        right,
                        bottom,
                    ];
                    words.extend(shape);
                    words_buffer(engine, "composite pass", &words, wgpu::BufferUsages::UNIFORM)
                })
                .collect();
            let dispatches: Vec<Encoded> = batches
                .iter()
                .zip(&uniforms)
                .map(|(batch, uniform)| {
                    let mut bound = whole(&[(0, uniform), (1, &steps), (2, &work)]);
                    let pages = batch.pages.iter().map(|&page| &plan.pages[usize::from(page)]);
                    bound.extend(self.pages.entries(pages));
                    if let Target::Surface(view) = target {
                        bound.push(wgpu::BindGroupEntry {
                            binding: self.surface_binding(),
                            resource: wgpu::BindingResource::TextureView(view),
                        });
                    }
                    let groups = (TILE / 16, TILE / 16, chunk_tiles as u32);
                    Encoded { pipeline, bound, groups }
                })
                .collect();
            encode_on(engine, &mut encoder, &dispatches);
            passes += dispatches.len();
            if let Target::Tiles(out) = target {
                encoder.copy_buffer_to_buffer(
                    &work,
                    out_at * 4,
                    out,
                    first_tile as u64 * TILE_TEXELS * 4,
                    chunk_tiles as u64 * TILE_TEXELS * 4,
                );
            }
        }
        engine.queue.submit([encoder.finish()]);
        Some(passes)
    }
}

/// What a composite pass is compiled for: where it puts its pixels — the
/// output tiles, or a surface of the format `surface` names — and the R1
/// modes its plan's maps hold, the rest compiled out (resample.wgsl).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct Compiled {
    surface: Option<&'static str>,
    modes: ResampleModes,
}

/// The composite passes made so far, and those a thread is compiling.
#[derive(Default)]
struct Passes {
    made: Vec<(Compiled, wgpu::ComputePipeline)>,
    making: Vec<Compiled>,
}

impl Passes {
    fn made(&self, compiled: Compiled) -> Option<wgpu::ComputePipeline> {
        let made = self.made.iter().find(|(made, _)| *made == compiled);
        made.map(|(_, pipeline)| pipeline.clone())
    }
}

/// The composite pass binding the pages `pages` declares, putting each
/// pixel by `output`'s `put` and reading maps of `modes` alone.
fn compile(
    engine: &Engine,
    pages: &str,
    output: &str,
    modes: ResampleModes,
) -> wgpu::ComputePipeline {
    let body = include_str!("composite.wgsl").replace("//__OUTPUT__", output);
    let sources = [
        ISQRT_WGSL,
        BLEND_WGSL,
        WIDE_WGSL,
        RESAMPLE_WGSL,
        TILE_WGSL,
        KEY_WGSL,
        PREMULTIPLY_WGSL,
        BYTE_WGSL,
        pages,
        &body,
    ];
    pipeline_with(engine, &sources, "composite", &modes.constants())
}

/// Fails where a row is masked and the plan has no mask, or where the mask's
/// plane holds less than its box.
fn check_mask(plan: &Plan) -> Option<()> {
    let masked = plan.steps.iter().position(|step| matches!(step, Step::Row { masked: true, .. }));
    match (plan.mask, masked) {
        (Some(mask), _) => mask.checked(),
        (None, Some(index)) => fail(format!("step {index} is masked and the plan has no mask")),
        (None, None) => Some(()),
    }
}

/// Fails unless every buffer the steps open is closed, none is closed that
/// was not opened, and every row names a tile set and a key chain there
/// are.
fn check_depth(steps: &[Step], sets: usize, chains: usize) -> Option<()> {
    let mut depth = 0usize;
    for (index, step) in steps.iter().enumerate() {
        match *step {
            Step::Row { set, .. } if set >= sets => {
                return fail(format!("step {index} lays tile set {set} of {sets}"));
            }
            Step::Row {
                keys: Some(chain), ..
            } if chain >= chains => {
                return fail(format!("step {index} keys by chain {chain} of {chains}"));
            }
            Step::Row { .. } => {}
            Step::Open | Step::OpenOpaque => depth += 1,
            Step::Close { .. } | Step::CloseAtop if depth == 0 => {
                return fail(format!("step {index} closes a buffer that is not open"));
            }
            Step::Close { .. } | Step::CloseAtop => depth -= 1,
        }
    }
    if depth != 0 {
        return fail(format!("{depth} buffers are left open"));
    }
    Some(())
}

/// `steps` as the GPU takes them: a row with the pages of the tiles its
/// pose reads for the output tiles — a copied row once for each page, any
/// other pose once for each group of them ([`grouped`]) — and not at all
/// where it reads none; each live on the output tiles where it reads a
/// stored tile on its pages.
fn lay(
    steps: &[Step],
    sets: &[TileSet],
    tiles: &[(i32, i32)],
    page_count: usize,
    pages_per_pass: usize,
) -> Option<Vec<Laid>> {
    let side = i64::from(TILE);
    let mut laid = Vec::new();
    for step in steps {
        let Step::Row { set, map, .. } = *step else {
            laid.push(Laid {
                step: *step,
                pages: Vec::new(),
                live: vec![true; tiles.len()],
            });
            continue;
        };
        // The pages each output tile reads.
        let mut reads: Vec<Vec<u16>> = Vec::with_capacity(tiles.len());
        for &(column, row) in tiles {
            let (x0, y0) = (i64::from(column) * side, i64::from(row) * side);
            let mut read: Vec<u16> = Vec::new();
            for at in sets[set].under(map.reads(x0, y0, x0 + side, y0 + side)) {
                if usize::from(at.page) >= page_count {
                    return fail(format!("tile set {set} names page {}", at.page));
                }
                if !read.contains(&at.page) {
                    read.push(at.page);
                }
            }
            reads.push(read);
        }
        if map.is_copy() {
            let mut pages: Vec<u16> = reads.iter().flatten().copied().collect();
            pages.sort_unstable();
            pages.dedup();
            laid.extend(pages.into_iter().map(|page| Laid {
                step: *step,
                pages: vec![page],
                live: reads.iter().map(|read| read.contains(&page)).collect(),
            }));
        } else {
            laid.extend(grouped(*step, &reads, pages_per_pass));
        }
    }
    Some(laid)
}

/// A row in a pose other than a copy, laid once for each group of the
/// output tiles that read it, `reads` being the pages each reads: a tile
/// joins the first group whose pages and its own a pass of `pages_per_pass`
/// binds, or starts one. A pixel reads around where it lands, so a tile's
/// pages are never parted; one tile reading more than a pass binds is a
/// group of its own, which `cut` refuses.
fn grouped(step: Step, reads: &[Vec<u16>], pages_per_pass: usize) -> Vec<Laid> {
    let mut groups: Vec<Laid> = Vec::new();
    for (tile, read) in reads.iter().enumerate() {
        if read.is_empty() {
            continue;
        }
        let joins = groups.iter().position(|group| {
            let fresh = read.iter().filter(|page| !group.pages.contains(page)).count();
            group.pages.len() + fresh <= pages_per_pass
        });
        let k = joins.unwrap_or_else(|| {
            groups.push(Laid {
                step,
                pages: Vec::new(),
                live: vec![false; reads.len()],
            });
            groups.len() - 1
        });
        let group = &mut groups[k];
        for &page in read {
            if !group.pages.contains(&page) {
                group.pages.push(page);
            }
        }
        group.live[tile] = true;
    }
    groups
}

/// `laid` cut into passes, in order. A pass ends where the next step would
/// bind more than `pages_per_pass` pages, or reach outside the `levels`
/// stack levels it holds — opening past the top, or closing onto a level
/// under its base. The next pass then holds the levels around the depth
/// there. None where one step reads more pages than a pass binds.
fn cut(laid: &[Laid], pages_per_pass: usize, levels: usize) -> Option<Vec<Batch>> {
    let mut batches = Vec::new();
    let mut batch = Batch {
        begin: 0,
        end: 0,
        base: 0,
        depth_in: 0,
        depth_out: 0,
        pages: Vec::new(),
    };
    let mut depth = 0usize;
    for (index, each) in laid.iter().enumerate() {
        if each.pages.len() > pages_per_pass {
            return fail(format!(
                "a row reads {} pages at once; a pass binds {pages_per_pass}",
                each.pages.len()
            ));
        }
        let fresh = each.pages.iter().filter(|page| !batch.pages.contains(page)).count();
        // The levels the step reads and writes, lowest and highest.
        let (low, high) = match each.step {
            Step::Open | Step::OpenOpaque => (depth, depth + 1),
            Step::Close { .. } | Step::CloseAtop => (depth - 1, depth),
            Step::Row { .. } => (depth, depth),
        };
        let outside = low < batch.base || high >= batch.base + levels;
        if batch.pages.len() + fresh > pages_per_pass || outside {
            // Half the levels under the depth, but never so low that `high`
            // is past the top. Half is at least one, so `low` is held too.
            let base = if outside {
                depth
                    .saturating_sub(levels / 2)
                    .max((high + 1).saturating_sub(levels))
            } else {
                batch.base
            };
            batch.end = index;
            batch.depth_out = depth;
            let next = Batch {
                begin: index,
                end: index,
                base,
                depth_in: depth,
                depth_out: depth,
                pages: Vec::new(),
            };
            batches.push(std::mem::replace(&mut batch, next));
        }
        for &page in &each.pages {
            if !batch.pages.contains(&page) {
                batch.pages.push(page);
            }
        }
        match each.step {
            Step::Open | Step::OpenOpaque => depth += 1,
            Step::Close { .. } | Step::CloseAtop => depth -= 1,
            Step::Row { .. } => {}
        }
    }
    batch.end = laid.len();
    batch.depth_out = depth;
    batches.push(batch);
    Some(batches)
}

/// The plan buffer's words, where its output tiles start and how many words
/// each takes, where its passes' tables of pages start, one after another,
/// and the R1 modes its rows' maps hold.
struct PlanWords {
    words: Vec<u8>,
    tiles_at: u32,
    tile_words: u32,
    tables_at: u32,
    modes: ResampleModes,
}

/// The steps, then each tile set's map, the key chains — an empty list,
/// then each chain's list (how many runs, where each is) and its runs —
/// each row's R1 map, each pass's table of pages — for every page of the
/// pool the binding holding it, or NO_PAGE — and the output tiles: each its
/// column and row, then a bit a step, step k bit k % 32 of word k / 32,
/// set where the step is live there.
fn plan_words(
    laid: &[Laid],
    batches: &[Batch],
    sets: &[TileSet],
    keys: &[KeyChain],
    tiles: &[(i32, i32)],
    page_count: usize,
) -> PlanWords {
    let mut words: Vec<u32> = Vec::with_capacity(laid.len() * STEP_WORDS);
    let maps_at = (laid.len() * STEP_WORDS) as u32;
    let mut map_at = Vec::with_capacity(sets.len());
    let mut maps: Vec<u32> = Vec::new();
    for set in sets {
        map_at.push(maps_at + maps.len() as u32);
        maps.extend(set.tiles.iter().map(|tile| match tile {
            Some(at) => (u32::from(at.page) << 16) | u32::from(at.slot),
            None => NO_TILE,
        }));
    }
    let chains_at = maps_at + maps.len() as u32;
    // The empty list also keeps the plan from being empty, as a storage
    // binding must hold something.
    let mut chains: Vec<u32> = vec![0];
    let mut chain_at = Vec::with_capacity(keys.len());
    for chain in keys {
        let list_at = chains_at + chains.len() as u32;
        chain_at.push(list_at);
        chains.push(chain.runs.len() as u32);
        let mut run_at = list_at + 1 + chain.runs.len() as u32;
        for run in &chain.runs {
            chains.push(run_at);
            run_at += run.len() as u32;
        }
        for run in &chain.runs {
            chains.extend(run);
        }
    }
    let poses_at = chains_at + chains.len() as u32;
    let mut poses: Vec<u32> = Vec::new();
    let mut modes = ResampleModes::default();
    for each in laid {
        let step = match each.step {
            Step::Row {
                set,
                keys,
                map,
                opacity,
                mode,
                masked,
            } => {
                let pose_at = poses_at + poses.len() as u32;
                let pose = map.words();
                modes = modes.with(&pose);
                poses.extend(pose);
                let pages = || each.pages.iter().copied().map(u32::from);
                let tiles = &sets[set];
                [
                    0,
                    mode,
                    opacity,
                    pages().min().expect("a laid row has its pages"),
                    pages().max().expect("a laid row has its pages"),
                    map_at[set],
                    tiles.x0 as u32,
                    tiles.y0 as u32,
                    tiles.columns,
                    tiles.rows,
                    pose_at,
                    keys.map_or(chains_at, |chain| chain_at[chain]),
                    u32::from(masked),
                ]
            }
            Step::Open => [1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
            Step::OpenOpaque => [2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
            Step::Close { opacity, mode } => [3, mode, opacity, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
            Step::CloseAtop => [4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        };
        words.extend(step);
    }
    words.extend(maps);
    words.extend(chains);
    words.extend(poses);
    let tables_at = words.len() as u32;
    for batch in batches {
        words.extend(page_table(&batch.pages, page_count));
    }
    let tiles_at = words.len() as u32;
    let masks = laid.len().div_ceil(32);
    for (tile, &(column, row)) in tiles.iter().enumerate() {
        words.extend([column as u32, row as u32]);
        let mut mask = vec![0u32; masks];
        for (k, each) in laid.iter().enumerate() {
            mask[k / 32] |= u32::from(each.live[tile]) << (k % 32);
        }
        words.extend(mask);
    }
    PlanWords {
        words: le_bytes(&words),
        tiles_at,
        tile_words: 2 + masks as u32,
        tables_at,
        modes,
    }
}
