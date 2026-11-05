//! The blur brush's dab on the GPU (I-75 흐리기 — `BrushBlurPicture.blurDab`,
//! C's `qa_blur_dab`; gpu-canonical-store D5, 01:13): the stroke's picture
//! under each dab moved toward its blur by what the dab lays as paint onto
//! nothing. `blur.wgsl` has what a dab reads and moves; the passes are the
//! fx Gaussian's box law and its two schedules (`effects/blur/box.wgsl`,
//! `three.wgsl`, `pass.wgsl`; the ranges and the cut gaussian.rs's
//! `within`), the coverage the dab kernel's own (`dab_source`) — no second
//! copy of any. A dab goes by strips, a way's three passes a dispatch
//! (`blur_three.wgsl`), up to MOST_STRIPS_RADIUS; past it a pass a dispatch
//! (`blur_pass.wgsl`, 01:13 ③).
//!
//! The picture is made from the cel — every tile a dab's window meets — and
//! finished back as the cel stores it (`qa_blur_result_tile`) by
//! `blur_cel.wgsl`, the cel read as the executor copies a row whole and
//! the finished tiles going out as its output does (캔버스 베이스 11-06
//! 02:29) — no read of the pool of the blur's own.
//!
//! The picture is kept on pages as the pool is (shared/pages.rs, 캔버스
//! 베이스 11-06 03:36): a binding holds 128 MB on some devices, and one dab
//! of 2000 reaches 1,089 tiles of 128 KB. A dab binds the pages its window
//! reads; the cel's passes bind theirs, a run of tiles at a time.

#[cfg(test)]
#[path = "blur_tests.rs"]
mod tests;

use std::cell::Cell;
use std::collections::HashMap;
use std::ops::Range;

use wgpu::util::DeviceExt;

use super::{Dab, Paper, Plans, StrokeTile, TILE, bytes};
use crate::device::Engine;
use crate::fail;
use crate::kernels::blend::BLEND_WGSL;
use crate::kernels::blend::mode::NORMAL;
use crate::kernels::composite::{self, Composite, Composited, TILE_TEXELS, TileSet};
use crate::kernels::effects::blur::fits;
use crate::kernels::effects::blur::gaussian::{
    BOX_WGSL, PASS_WGSL, PASS_WORDS, Strips, THREE_WGSL, within,
};
use crate::kernels::shared::{ISQRT_WGSL, Pages, ResampleMap, TILE_WGSL, page_table, pipeline};

/// blur.wgsl's block: the words before its passes, and before its grid.
const PASSES_AT: usize = 8;
const GRID_AT: usize = PASSES_AT + 6 * PASS_WORDS;
/// A dab's storage buffers besides the picture's pages — the plan, and the
/// two planes a pass a dispatch alternates between, strips using the first
/// — and the binding its pages begin at (blur.wgsl, blur_pass.wgsl). A
/// device that binds sixteen pages past them binds them past two as well,
/// so no test here tells a count one short (mutant r02, 11-06); a device of
/// four storage buffers would compile a pass binding five.
const OWN: u32 = 3;
const PAGES_AT: u32 = 7;
/// blur_cel.wgsl's: the cel and the slots, the pages from binding 2.
const CEL_OWN: u32 = 2;
/// blur_cel.wgsl's BLUR_CEL_GROUP: the texels of a tile a workgroup takes.
const CEL_GROUP: u64 = 256;
/// The cel's copy has no edge: a stroke reaches past the canvas onto the
/// pasteboard (BrushBlurPicture's wall), where the cel has tiles too.
const NO_EDGE: [i32; 4] = [i32::MIN, i32::MIN, i32::MAX, i32::MAX];

/// The widest box a dab goes by strips. Past it a pass a dispatch is the
/// faster: a strip's halo of 6r leaves it few of its 1024 pixels to put,
/// so it reads the same line over again (11-06, the main PC's GPU, a dab,
/// µs by strips against a pass a dispatch — r 75: 248, 497; r 90: 517,
/// 637; r 100: 705, 642; r 120: 1,121, 730; r 150: 4,255, 1,016; r 167:
/// 25,374, 1,328). The Gaussian's crossing on a whole picture is lower
/// (gaussian.rs's 56): a dab's six dispatches cost more against its
/// small window.
///
/// The second of two such choices — the other is the fx Gaussian's
/// (effects/blur/gaussian.rs's MOST_STRIPS_RADIUS and Route): they stay
/// apart, each threshold measured for its own use, until a third comes and
/// one function beside `strips` takes the threshold (rule of three, 캔버스
/// 베이스 11-06 03:05).
const MOST_STRIPS_RADIUS: u32 = 90;

/// How a dab's passes go: by strips where a strip of them has room and the
/// box is no wider than MOST_STRIPS_RADIUS — a pass a dispatch past that —
/// or every pass a dispatch, as the tests send them too, to see both move
/// the same pixels.
#[derive(Clone, Copy)]
enum Route {
    Strips,
    Passes,
}

pub(crate) struct Blurs {
    /// A dab's dispatches binding one page a pass, as a dab whose window is
    /// on one goes — nearly every one —, and binding as many as the device
    /// lets. A page's words are read and put by a switch over the pages a
    /// pass binds: over sixteen a dab of 100 went a fifth slower than over
    /// one (11-06, the main PC: 46 µs a dab against 39.6; 37 before the
    /// pages).
    one: Dispatches,
    widest: Dispatches,
    /// blur_cel.wgsl's two: the picture made from the cel, and finished;
    /// and the picture's pages as they bind them.
    filling: wgpu::ComputePipeline,
    finishing: wgpu::ComputePipeline,
    cel_pages: Pages,
    plans: Plans,
    /// What one dispatch of a dab puts for the next, and the plane a pass a
    /// dispatch alternates with it: each grown, never shrunk.
    between: Option<wgpu::Buffer>,
    second: Option<wgpu::Buffer>,
}

/// The `index`-th pass's word `word` among `passes` (box.wgsl's `BoxPass`:
/// down, radius, first, end, line_first, line_end, …).
fn word(passes: &[u32], index: usize, word: usize) -> i32 {
    passes[index * PASS_WORDS + word] as i32
}

/// How a dab's passes are dispatched: a way's three a dispatch, each way cut
/// into strips; or each pass a dispatch of these workgroups.
enum Ways {
    Strips { rows: Strips, columns: Strips },
    Passes(Vec<(u32, u32)>),
}

/// What a dab's blur reads and how its dispatches cut it.
struct Window {
    passes: Vec<u32>,
    /// The first of the tiles it reads, and how many a row.
    first_tile: (i32, i32),
    tile_columns: usize,
    /// Each of those tiles' index among the stroke's, row after row, and
    /// the k of its page among `pages`.
    grid: Vec<(usize, u32)>,
    /// The picture's pages those tiles are on, in binding order.
    pages: Vec<u16>,
    ways: Ways,
    /// The bytes one dispatch puts for the next: the rows' blur, or each of
    /// the two planes a pass a dispatch alternates between.
    between: u64,
}

impl Window {
    fn of(
        dab: &Dab,
        radius: u32,
        (tiles, at): (&[StrokeTile], &HashMap<(i32, i32), usize>),
        route: Route,
    ) -> Option<Window> {
        let Some(within) = within(dab.region, radius) else {
            return fail("a blur of no radius changes no pixel");
        };
        let r = radius as i32;
        let pass = |index, field| word(&within.words, index, field);
        // The rows' first pass reads one radius past what it puts: that is
        // the window; its lines are the window's rows.
        let (left, right) = (pass(0, 2) - r, pass(0, 3) + r);
        let (top, bottom) = (pass(0, 4), pass(0, 5));
        let lines = u64::from((bottom - top) as u32);
        let ways = match (route, within.rows, within.columns) {
            (Route::Strips, Some(rows), Some(columns)) if radius <= MOST_STRIPS_RADIUS => {
                Ways::Strips { rows, columns }
            }
            _ => Ways::Passes(within.groups),
        };
        let between = match ways {
            // The rows' blur: the dab's columns on the window's lines.
            Ways::Strips { .. } => lines * (pass(2, 3) - pass(2, 2)) as u64 * 8,
            // A plane as the rows' first pass puts.
            Ways::Passes(_) => lines * (pass(0, 3) - pass(0, 2)) as u64 * 8,
        };
        let first_tile = (left.div_euclid(TILE), top.div_euclid(TILE));
        let (last_column, last_row) = ((right - 1).div_euclid(TILE), (bottom - 1).div_euclid(TILE));
        let mut grid = Vec::new();
        let mut pages = Vec::new();
        for row in first_tile.1..=last_row {
            for column in first_tile.0..=last_column {
                let Some(&index) = at.get(&(column, row)) else {
                    return fail(format!(
                        "a blur dab reads tile ({column}, {row}), which the stroke has no slot \
                         for"
                    ));
                };
                let page = tiles[index].at.page;
                let k = pages.iter().position(|&bound| bound == page).unwrap_or_else(|| {
                    pages.push(page);
                    pages.len() - 1
                });
                grid.push((index, k as u32));
            }
        }
        Some(Window {
            first_tile,
            tile_columns: (last_column - first_tile.0 + 1) as usize,
            grid,
            pages,
            ways,
            between,
            passes: within.words,
        })
    }

    /// The words a strip dispatch reads of the block: each way's lines and
    /// run a workgroup — nothing a pass a dispatch reads.
    fn strip_words(&self) -> [u32; 4] {
        match &self.ways {
            Ways::Strips { rows, columns } => [rows.lines, rows.run, columns.lines, columns.run],
            Ways::Passes(_) => [0; 4],
        }
    }

    /// Its dispatches, in order.
    fn steps(&self) -> Vec<Step> {
        match &self.ways {
            Ways::Strips { rows, columns } => vec![
                Step {
                    entry: Entry::Rows,
                    pass: 0,
                    groups: rows.groups,
                },
                Step {
                    entry: Entry::Columns,
                    pass: 0,
                    groups: columns.groups,
                },
            ],
            Ways::Passes(groups) => groups
                .iter()
                .enumerate()
                .map(|(pass, &groups)| Step {
                    entry: Entry::Pass,
                    pass: pass as u32,
                    groups,
                })
                .collect(),
        }
    }
}

/// The blur's entry points: a way's three by strips, rows or columns
/// (blur_three.wgsl), or one pass (blur_pass.wgsl).
#[derive(Clone, Copy)]
enum Entry {
    Rows,
    Columns,
    Pass,
}

/// One dispatch of a dab: its entry, the pass it is of the block's six (a
/// pass a dispatch), and its workgroups.
struct Step {
    entry: Entry,
    pass: u32,
    groups: (u32, u32),
}

/// A dab's pipelines, compiled for the pages a pass of them binds.
struct Dispatches {
    pages: Pages,
    rows: wgpu::ComputePipeline,
    columns: wgpu::ComputePipeline,
    pass: wgpu::ComputePipeline,
}

impl Dispatches {
    /// Binding no more than `most` pages a pass.
    fn new(engine: &Engine, most: usize) -> Option<Self> {
        let pages = Pages::writable(engine, OWN, PAGES_AT, most)?;
        let (dab, blur) = (include_str!("dab.wgsl"), include_str!("blur.wgsl"));
        let paged = pages.source();
        let way = [ISQRT_WGSL, BLEND_WGSL, TILE_WGSL, dab, BOX_WGSL, paged.as_str()];
        let strips = [&way[..], &[THREE_WGSL, blur, include_str!("blur_three.wgsl")]].concat();
        let passes = [&way[..], &[PASS_WGSL, blur, include_str!("blur_pass.wgsl")]].concat();
        Some(Self {
            rows: pipeline(engine, &strips, "blur_rows_pass"),
            columns: pipeline(engine, &strips, "blur_columns_pass"),
            pass: pipeline(engine, &passes, "blur_pass_one"),
            pages,
        })
    }

    fn of(&self, entry: Entry) -> &wgpu::ComputePipeline {
        match entry {
            Entry::Rows => &self.rows,
            Entry::Columns => &self.columns,
            Entry::Pass => &self.pass,
        }
    }
}

impl Blurs {
    pub(crate) fn new(engine: &Engine) -> Option<Self> {
        let cel_pages = Pages::writable(engine, CEL_OWN, CEL_OWN, usize::MAX)?;
        let cel_paged = cel_pages.source();
        let cel_source = include_str!("blur_cel.wgsl");
        let cel = [ISQRT_WGSL, BLEND_WGSL, TILE_WGSL, cel_paged.as_str(), cel_source];
        Some(Self {
            one: Dispatches::new(engine, 1)?,
            widest: Dispatches::new(engine, usize::MAX)?,
            filling: pipeline(engine, &cel, "blur_fill"),
            finishing: pipeline(engine, &cel, "blur_finish"),
            cel_pages,
            plans: Plans::new(),
            between: None,
            second: None,
        })
    }

    /// Blurs the stroke's `picture` — `tiles`' planes on its pages, two
    /// words a pixel, a tile a slot of a page — under each of `dabs`, in
    /// their order, at its box radius (the app's
    /// `BrushBlurPicture.blurRadiusOf`), over `paper`; submits the work, the
    /// caller waits. Every tile a dab's window meets — what its blur reads,
    /// three radii past it each side — is the caller's to have among
    /// `tiles`.
    pub(crate) fn blur(
        &mut self,
        engine: &Engine,
        tiles: &[StrokeTile],
        dabs: &[(Dab, u32)],
        paper: Option<&Paper>,
        picture: &[wgpu::Buffer],
    ) -> Option<()> {
        let pages_per_pass = self.widest.pages.per_pass();
        self.blur_by(engine, tiles, dabs, paper, picture, (Route::Strips, pages_per_pass))
    }

    /// `blur`, the passes going by `route` and a dab binding no more than
    /// `pages_per_pass` pages — a test's fewer than the device's, to see
    /// where a smaller device refuses.
    fn blur_by(
        &mut self,
        engine: &Engine,
        tiles: &[StrokeTile],
        dabs: &[(Dab, u32)],
        paper: Option<&Paper>,
        picture: &[wgpu::Buffer],
        (route, pages_per_pass): (Route, usize),
    ) -> Option<()> {
        // The colour is not the dab's to lay: white and opaque, it measures
        // its coverage alone; and it lays, never erases (BrushBlurPicture).
        // A second tip's dab lays nothing on a stroke with no second plane
        // (qa_dab_blend_tile), so it blurs nothing; nor does a dab of no
        // region.
        let dabs: Vec<(Dab, u32)> = dabs
            .iter()
            .filter(|(dab, _)| {
                let [left, top, right, bottom] = dab.region;
                !dab.second && left < right && top < bottom
            })
            .map(|&(dab, radius)| (Dab { colour: [255; 4], erase: false, ..dab }, radius))
            .collect();
        if dabs.is_empty() {
            return Some(());
        }
        on_the_picture(tiles, picture)?;
        let at: HashMap<(i32, i32), usize> = tiles
            .iter()
            .enumerate()
            .map(|(index, tile)| ((tile.column, tile.row), index))
            .collect();
        let windows: Vec<Window> = dabs
            .iter()
            .map(|(dab, radius)| Window::of(dab, *radius, (tiles, &at), route))
            .collect::<Option<_>>()?;
        // A pixel reads around where it lands, all the way across the
        // window, so a dab's pages are never parted: one whose window is on
        // more pages than a pass binds is refused, as the executor refuses
        // an output tile reading more (composite's `grouped`).
        if let Some(window) = windows.iter().find(|window| window.pages.len() > pages_per_pass) {
            return fail(format!(
                "a blur dab reads {} pages of the picture; a pass binds {pages_per_pass}",
                window.pages.len()
            ));
        }
        let steps: Vec<Vec<Step>> = windows.iter().map(Window::steps).collect();
        let between_bytes = windows.iter().map(|window| window.between).max()?;
        // No test lays a window past a binding here (2 GB) or a dispatch's
        // groups, so none tells this line from its absence (mutants f01, f02,
        // 11-06); a device of 128 MB refuses a dab of size 2000 by it.
        fits(engine, &[between_bytes], steps.iter().flatten().map(|step| step.groups))?;
        grown(engine, &mut self.between, between_bytes, "blur between");
        let by_passes = windows
            .iter()
            .filter(|window| matches!(window.ways, Ways::Passes(_)))
            .map(|window| window.between)
            .max();
        if let Some(bytes) = by_passes {
            grown(engine, &mut self.second, bytes, "blur between second");
        }
        let white: Vec<Dab> = dabs.iter().map(|(dab, _)| *dab).collect();
        // Each dab's block, after the plan's own words: where it starts
        // among the blocks.
        let places: Vec<usize> = windows
            .iter()
            .scan(0, |end, window| {
                let place = *end;
                *end += GRID_AT + 2 * window.grid.len();
                Some(place)
            })
            .collect();
        let blocks_at = Cell::new(0);
        let plan = self.plans.write(engine, tiles, &white, paper, None, |plan| {
            let mut words = Vec::new();
            for (index, window) in windows.iter().enumerate() {
                words.extend([
                    plan.record_at(index),
                    window.first_tile.0 as u32,
                    window.first_tile.1 as u32,
                    window.tile_columns as u32,
                ]);
                words.extend(window.strip_words());
                words.extend(&window.passes);
                words.extend(window.grid.iter().flat_map(|&(tile, k)| [plan.tile_at(tile), k]));
            }
            blocks_at.set(plan.end());
            Some(words)
        });
        let plan = plan?;
        // Each dispatch's own words: its dab's block and its pass.
        let align = u64::from(engine.device.limits().min_uniform_buffer_offset_alignment);
        let count: usize = steps.iter().map(Vec::len).sum();
        let mut uniform = vec![0u8; align as usize * count];
        let mut slot = 0;
        for (place, steps) in places.iter().zip(&steps) {
            let block = (blocks_at.get() + place) as u32;
            for step in steps {
                let at = &mut uniform[slot * align as usize..];
                at[..4].copy_from_slice(&block.to_le_bytes());
                at[4..8].copy_from_slice(&step.pass.to_le_bytes());
                slot += 1;
            }
        }
        let uniform = engine.device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
            label: Some("blur dabs"),
            contents: &uniform,
            usage: wgpu::BufferUsages::UNIFORM,
        });
        // A dab whose window is on one page goes by the dispatches that bind
        // one. The widest bind it too, so no test tells the two apart — only
        // the time (`Blurs::one`; mutant r07, 11-06).
        let ways: Vec<&Dispatches> = windows
            .iter()
            .map(|window| if window.pages.len() == 1 { &self.one } else { &self.widest })
            .collect();
        let (between, second) = (self.between.as_ref()?, self.second.as_ref());
        let bound = |step: &Step, (window, way): (&Window, &Dispatches), index: usize| {
            let entry = |binding, resource| wgpu::BindGroupEntry { binding, resource };
            let mut entries = vec![
                entry(0, plan.as_entire_binding()),
                entry(4, between.as_entire_binding()),
                entry(5, wgpu::BindingResource::Buffer(wgpu::BufferBinding {
                    buffer: &uniform,
                    offset: index as u64 * align,
                    size: wgpu::BufferSize::new(16),
                })),
            ];
            if let (Entry::Pass, Some(second)) = (step.entry, second) {
                entries.push(entry(6, second.as_entire_binding()));
            }
            let read = window.pages.iter().map(|&page| &picture[usize::from(page)]);
            entries.extend(way.pages.entries(read));
            engine.device.create_bind_group(&wgpu::BindGroupDescriptor {
                label: Some("blur dab"),
                layout: &way.of(step.entry).get_bind_group_layout(0),
                entries: &entries,
            })
        };
        let dispatches: Vec<(&Step, &wgpu::ComputePipeline, wgpu::BindGroup)> = windows
            .iter()
            .zip(&ways)
            .zip(&steps)
            .flat_map(|((window, &way), steps)| steps.iter().map(move |step| (step, window, way)))
            .enumerate()
            .map(|(index, (step, window, way))| {
                (step, way.of(step.entry), bound(step, (window, way), index))
            })
            .collect();
        let mut encoder = engine
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor::default());
        {
            let mut pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor::default());
            for (step, pipeline, bind_group) in &dispatches {
                pass.set_pipeline(pipeline);
                pass.set_bind_group(0, bind_group, &[]);
                pass.dispatch_workgroups(step.groups.0, step.groups.1, 1);
            }
        }
        engine.queue.submit([encoder.finish()]);
        Some(())
    }

    /// Makes `tiles`' picture of the cel's (`blur_fill`): each tile of
    /// `cel` — its tiles on the pool's `pages` — as the executor copies it
    /// whole over nothing, premultiplied into the tile's slot of `picture`;
    /// nothing where the cel has no tile. Submits the work, the caller
    /// waits.
    pub(crate) fn fill(
        &self,
        engine: &Engine,
        executor: &Composite,
        cel: (&[wgpu::Buffer], &TileSet),
        tiles: &[StrokeTile],
        picture: &[wgpu::Buffer],
    ) -> Option<()> {
        self.fill_by(engine, executor, cel, tiles, picture, self.widest(engine))
    }

    /// `fill`, a pass taking no more than `most` (pages, tiles).
    fn fill_by(
        &self,
        engine: &Engine,
        executor: &Composite,
        (pages, cel): (&[wgpu::Buffer], &TileSet),
        tiles: &[StrokeTile],
        picture: &[wgpu::Buffer],
        most: (usize, usize),
    ) -> Option<()> {
        on_the_picture(tiles, picture)?;
        let copied = copied(engine, executor, (pages, cel), tiles)?;
        self.through_cel(engine, &self.filling, &copied.out, (tiles, picture), most)
    }

    /// `tiles` finished (`blur_finish`): their picture stored as the cel
    /// stores it — straight RGBA8, tile after tile in `tiles`' order, as
    /// the executor's output is. Submits the work, the caller waits.
    pub(crate) fn finish(
        &self,
        engine: &Engine,
        tiles: &[StrokeTile],
        picture: &[wgpu::Buffer],
    ) -> Option<wgpu::Buffer> {
        self.finish_by(engine, tiles, picture, self.widest(engine))
    }

    /// `finish`, a pass taking no more than `most` (pages, tiles).
    fn finish_by(
        &self,
        engine: &Engine,
        tiles: &[StrokeTile],
        picture: &[wgpu::Buffer],
        most: (usize, usize),
    ) -> Option<wgpu::Buffer> {
        on_the_picture(tiles, picture)?;
        let finished = engine.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("blur finished"),
            size: (tiles.len().max(1) as u64) * TILE_TEXELS * 4,
            usage: wgpu::BufferUsages::STORAGE
                | wgpu::BufferUsages::COPY_DST
                | wgpu::BufferUsages::COPY_SRC,
            mapped_at_creation: false,
        });
        self.through_cel(engine, &self.finishing, &finished, (tiles, picture), most)?;
        Some(finished)
    }

    /// The most a pass of the cel's takes on this device: the pages it
    /// binds, and the tiles of the cel a binding holds and a dispatch
    /// reaches. No test lays a cel past a binding (2 GB here, 32,768
    /// tiles), so none tells a tile's bytes from its words in this line
    /// (mutant r19, 11-06).
    fn widest(&self, engine: &Engine) -> (usize, usize) {
        let limits = engine.device.limits();
        let room = u64::from(limits.max_storage_buffer_binding_size).min(limits.max_buffer_size);
        let reach = u64::from(limits.max_compute_workgroups_per_dimension);
        let tiles = (room / (TILE_TEXELS * 4)).min(reach);
        (self.cel_pages.per_pass(), tiles as usize)
    }

    /// One of blur_cel.wgsl's passes between `picture` and `cel`, `tiles`
    /// one after another as the executor puts them, a run of them a
    /// dispatch ([`runs`]).
    fn through_cel(
        &self,
        engine: &Engine,
        pass: &wgpu::ComputePipeline,
        cel: &wgpu::Buffer,
        (tiles, picture): (&[StrokeTile], &[wgpu::Buffer]),
        (pages_per_pass, most): (usize, usize),
    ) -> Option<()> {
        let tile_bytes = TILE_TEXELS * 4;
        let layout = pass.get_bind_group_layout(0);
        let dispatches: Vec<(u32, wgpu::BindGroup)> = runs(tiles, pages_per_pass, most)
            .into_iter()
            .map(|(run, pages)| {
                let table: Vec<u32> = page_table(&pages, picture.len()).collect();
                let slots: Vec<u32> = tiles[run.clone()]
                    .iter()
                    .flat_map(|tile| [table[usize::from(tile.at.page)], u32::from(tile.at.slot)])
                    .collect();
                let slots = engine.device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
                    label: Some("blur cel slots"),
                    contents: &bytes(&slots),
                    usage: wgpu::BufferUsages::STORAGE,
                });
                let mut entries = vec![
                    wgpu::BindGroupEntry {
                        binding: 0,
                        resource: wgpu::BindingResource::Buffer(wgpu::BufferBinding {
                            buffer: cel,
                            offset: run.start as u64 * tile_bytes,
                            size: wgpu::BufferSize::new(run.len() as u64 * tile_bytes),
                        }),
                    },
                    wgpu::BindGroupEntry {
                        binding: 1,
                        resource: slots.as_entire_binding(),
                    },
                ];
                let read = pages.iter().map(|&page| &picture[usize::from(page)]);
                entries.extend(self.cel_pages.entries(read));
                let bind_group = engine.device.create_bind_group(&wgpu::BindGroupDescriptor {
                    label: Some("blur cel"),
                    layout: &layout,
                    entries: &entries,
                });
                (run.len() as u32, bind_group)
            })
            .collect();
        let mut encoder = engine
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor::default());
        {
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor::default());
            compute.set_pipeline(pass);
            for (count, bind_group) in &dispatches {
                compute.set_bind_group(0, bind_group, &[]);
                compute.dispatch_workgroups((TILE_TEXELS / CEL_GROUP) as u32, *count, 1);
            }
        }
        engine.queue.submit([encoder.finish()]);
        Some(())
    }
}

/// Whether every one of `tiles` is on a page of `picture`.
fn on_the_picture(tiles: &[StrokeTile], picture: &[wgpu::Buffer]) -> Option<()> {
    match tiles.iter().find(|tile| usize::from(tile.at.page) >= picture.len()) {
        Some(tile) => fail(format!(
            "tile ({}, {}) is on page {}; the picture has {}",
            tile.column,
            tile.row,
            tile.at.page,
            picture.len()
        )),
        None => Some(()),
    }
}

/// `slot` holding a buffer of `bytes` at least, made anew where it holds
/// less.
fn grown(engine: &Engine, slot: &mut Option<wgpu::Buffer>, bytes: u64, label: &str) {
    if slot.as_ref().is_none_or(|buffer| buffer.size() < bytes) {
        *slot = Some(engine.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some(label),
            size: bytes,
            usage: wgpu::BufferUsages::STORAGE,
            mapped_at_creation: false,
        }));
    }
}

/// `tiles` cut into the runs blur_cel.wgsl's passes take, in order, each
/// with the pages it binds: a run ends where its next tile would bring it
/// past `pages_per_pass` pages or `most` tiles.
///
/// The second greedy cut by the pages a pass binds — the executor's `cut`
/// (composite/mod.rs) is the first, which holds stack levels too: the two
/// stay apart until a third comes (rule of three, CLAUDE.md absolute
/// rule 1).
fn runs(
    tiles: &[StrokeTile],
    pages_per_pass: usize,
    most: usize,
) -> Vec<(Range<usize>, Vec<u16>)> {
    let mut runs = Vec::new();
    let mut first = 0;
    let mut pages: Vec<u16> = Vec::new();
    for (index, tile) in tiles.iter().enumerate() {
        let fresh = !pages.contains(&tile.at.page);
        if index - first == most || (fresh && pages.len() == pages_per_pass) {
            runs.push((first..index, std::mem::take(&mut pages)));
            first = index;
        }
        if !pages.contains(&tile.at.page) {
            pages.push(tile.at.page);
        }
    }
    if first < tiles.len() {
        runs.push((first..tiles.len(), pages));
    }
    runs
}

/// `tiles` of `cel` — its tiles on the pool's `pages` — as the executor
/// copies a row whole over nothing: its stored bytes, tile after tile.
fn copied(
    engine: &Engine,
    executor: &Composite,
    (pages, cel): (&[wgpu::Buffer], &TileSet),
    tiles: &[StrokeTile],
) -> Option<Composited> {
    let steps = [composite::Step::Row {
        set: 0,
        keys: None,
        map: ResampleMap::moved(0, 0),
        // Whole. 65534 copies the same bytes — a stored byte's step is 257
        // on this scale — so no test tells the two apart (mutant r04, 11-06).
        opacity: 65535,
        mode: NORMAL,
    }];
    let plan = composite::Plan {
        pages,
        sets: std::slice::from_ref(cel),
        keys: &[],
        steps: &steps,
    };
    let at: Vec<(i32, i32)> = tiles.iter().map(|tile| (tile.column, tile.row)).collect();
    executor.run(engine, &plan, &at, NO_EDGE, executor.widest())
}
