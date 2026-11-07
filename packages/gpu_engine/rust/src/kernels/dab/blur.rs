//! The blur brush's dab on the GPU (I-75 흐리기 — `BrushBlurPicture.blurDab`,
//! C's `qa_blur_dab`; gpu-canonical-store D5, 01:13): the stroke's picture
//! under each dab moved toward its blur by what the dab lays as paint onto
//! nothing. `blur.wgsl` has what a dab reads and moves; the passes are the
//! box law and its two schedules (`effects/blur/box.wgsl`, `three.wgsl`,
//! `pass.wgsl`; the ranges and the cut boxes.rs's `within`), the coverage
//! the dab kernel's own (`dab_source`) — no second copy of any. A dab goes
//! by strips, a way's three passes a dispatch (`blur_three.wgsl`), up to
//! MOST_STRIPS_RADIUS; past it a pass a dispatch (`blur_pass.wgsl`, 01:13
//! ③).
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

use super::{Dab, Paper, Plans, StrokeTile, TILE, of_pages, on_pages};
use crate::device::Engine;
use crate::fail;
use crate::kernels::blend::BLEND_WGSL;
use crate::kernels::composite::{Composite, Composited, TILE_TEXELS, TileSet};
use crate::kernels::effects::blur::boxes::{
    BOX_WGSL, PASS_WGSL, PASS_WORDS, Strips, THREE_WGSL, within,
};
use crate::kernels::mask::{BYTE_WGSL, Mask};
use crate::kernels::shared::{
    Encoded, ISQRT_WGSL, Own, Pages, TILE_WGSL, encode, encode_on, fits, flat,
    given, page_table, pipeline, plane, range, runs, tiles_a_pass, whole,
};

/// blur.wgsl's block: the words before its passes, and before its grid.
const PASSES_AT: usize = 8;
const GRID_AT: usize = PASSES_AT + 6 * PASS_WORDS;
/// A dab's storage buffers besides the picture's pages — the plan, and the
/// two planes a pass a dispatch alternates between, strips using the first
/// — and the binding its pages begin at (blur.wgsl, blur_pass.wgsl). A
/// device that binds sixteen pages past them binds them past two as well,
/// so no test here tells a count one short (mutant r02, 11-06); a device of
/// four storage buffers would compile a pass binding five. Past them the
/// dab's words, a uniform one, so counted as well.
const OWN: Own = Own { storage: 3, uniform: 1 };
/// Any binding past the dab's own, 0 to 3, does as well (mutant d04, 11-06).
const PAGES_AT: u32 = 4;
/// blur_cel.wgsl's: the cel and what a pass is given, the pages from
/// binding 2.
const CEL_OWN: Own = Own { storage: 2, uniform: 0 };
/// blur_cel.wgsl's BLUR_CEL_GROUP: the texels of a tile a workgroup takes.
const CEL_GROUP: u64 = 256;
/// blur_cel.wgsl's BLUR_COVER_WORDS and BLUR_TILE_WORDS: what a pass is
/// given before its tiles, and for each of them.
const COVER_WORDS: usize = 8;
const TILE_PLACE_WORDS: u64 = 4;

/// How far a finish moves a pixel of the cel toward the picture: the tool's
/// `opacity` (65535 whole) under the selection's `mask` where one covers
/// the stroke — resultTile's mask, as a paint stroke's row is laid (R28).
#[derive(Clone, Copy)]
pub(crate) struct Cover<'a> {
    pub(crate) opacity: u32,
    pub(crate) mask: Option<&'a Mask<'a>>,
}

/// The widest box a dab goes by strips. Past it a pass a dispatch is the
/// faster: a strip's halo of 6r leaves it few of its 1024 pixels to put,
/// so it reads the same line over again (11-06, the main PC's GPU, a dab,
/// µs by strips against a pass a dispatch — r 75: 248, 497; r 90: 517,
/// 637; r 100: 705, 642; r 120: 1,121, 730; r 150: 4,255, 1,016; r 167:
/// 25,374, 1,328). The fx Gaussian's boxes crossed lower on a whole
/// picture, at 56, while it went by them: a dab's six dispatches cost more
/// against its small window.
///
/// The Surface (Arc 140V) crosses sooner, between 67 and 82 (캔버스 베이스
/// 11-06 04:35 — µs, a dab of 128 px, strips against a pass a dispatch:
/// r 60: 715, 980; r 75: 1,180, 1,174; r 82: 1,296, 1,236; r 90: 1,434,
/// 1,260): there 90 goes r 68 to 90 by strips at up to 14% more. Kept at
/// 90 — any one threshold costs one of the two devices in the band between
/// them, both keep clear of the strips' cliff, and choosing it by device
/// would be a rule of its own.
///
/// ↩️It was the second of two such choices, the fx Gaussian's the other
/// (rule of three, 캔버스 베이스 11-06 03:05), till that went by the
/// Gaussian itself (🗣️유저 gpu-canonical-store-Q2): the boxes are the
/// dab's alone.
const MOST_STRIPS_RADIUS: u32 = 90;

/// The most workgroups — its rows' and its columns' together — a dab goes in
/// turn with: one after another with the dabs about it in one workgroup
/// (blur_three.wgsl's `blur_dabs_in_turn`) instead of its two dispatches.
/// A small dab's two dispatches were its floor: two thirds of its time was
/// theirs on the GPU, the rest the CPU making them. One workgroup puts a
/// way's strips and bands one after another, so in turn loses as they grow.
/// µs a dab apart against in turn, 64 dabs warm, by its workgroups (and
/// radius):
/// - the main PC's RTX 4080 (11-06): 2 (r 2): 27, 15; 3 (r 3): 29, 18.5 to
///   21.5; 5 (r 4): 30, 27.6 to 30.3; 6 (r 5): 30 to 34, 37 to 42;
/// - the Surface's Arc 140V (11-07): 2 (r 2): 30, 22; 3 (r 3): 35 to 37, 32
///   to 35; 4 (r 4): 40, 49; 5 (r 4): 40, 57; 6 (r 5): 41, 76 to 79.
/// At 3 no device goes slower than by its two dispatches — the Arc still
/// gains at 3 and loses a quarter at 4 —, where 4 would set the weaker
/// device back on that step (the old-device policy, 유저 11-05: 「구형 =
/// 성능 약한 기기」). The main PC gives up only what it gained at 4, not
/// measured: no number there turns a stronger device's gain against a
/// weaker one's loss. One threshold for every device, as
/// MOST_STRIPS_RADIUS: a device's own would be a rule more (브러시/렌더링,
/// gpu-canonical-store 11-07 13:24). Size 12 went 22.5 µs a dab in C
/// (gpu-canonical-store 03:40).
const MOST_IN_TURN: u32 = 3;
/// blur_three.wgsl's BLUR_TURN_WORDS: a dab's block, and its rows' and its
/// columns' workgroups across and down.
const TURN_WORDS: usize = 5;

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
    /// pages). The executor's composite gains no more than 8% so, and binds
    /// its widest alone (캔버스 베이스 11-06 04:35, the Surface). The first
    /// of two such choices — the other is the pile's (mod.rs's `Dabs::one`):
    /// they stay apart until a third comes (rule of three, CLAUDE.md
    /// absolute rule 1).
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
/// down, radius, first, end, line_first, line_end).
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

    /// Its rows' and its columns' workgroups, where it goes by strips with
    /// no more than MOST_IN_TURN of them — a dab that goes in turn with the
    /// dabs about it on the pages it binds.
    ///
    /// Each way of such a dab is one strip along: a second leaves room for
    /// one line a band, and a window's lines are seven and more (its
    /// columns' three radii up and down). So only its bands go one after
    /// another, and no test reaches a second strip (mutant t09, 11-06).
    fn in_turn(&self) -> Option<[u32; 4]> {
        let Ways::Strips { rows, columns } = &self.ways else {
            return None;
        };
        let ((rx, ry), (cx, cy)) = (rows.groups, columns.groups);
        (rx * ry + cx * cy <= MOST_IN_TURN).then_some([rx, ry, cx, cy])
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

/// The blur's entry points: a way's three by strips, rows or columns, or
/// dabs of few workgroups in turn (blur_three.wgsl); or one pass
/// (blur_pass.wgsl).
#[derive(Clone, Copy)]
enum Entry {
    Rows,
    Columns,
    InTurn,
    Pass,
}

/// One dispatch of a dab: its entry, the pass it is of the block's six (a
/// pass a dispatch), and its workgroups.
struct Step {
    entry: Entry,
    pass: u32,
    groups: (u32, u32),
}

/// One dispatch of a blur: a run of dabs going in turn on the same pages, or a
/// step of a dab going apart.
enum Planned<'a> {
    InTurn(Range<usize>),
    Apart(usize, &'a Step),
}

/// A dab's pipelines, compiled for the pages a pass of them binds.
struct Dispatches {
    pages: Pages,
    rows: wgpu::ComputePipeline,
    columns: wgpu::ComputePipeline,
    in_turn: wgpu::ComputePipeline,
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
            in_turn: pipeline(engine, &strips, "blur_dabs_in_turn"),
            pass: pipeline(engine, &passes, "blur_pass_one"),
            pages,
        })
    }

    fn of(&self, entry: Entry) -> &wgpu::ComputePipeline {
        match entry {
            Entry::Rows => &self.rows,
            Entry::Columns => &self.columns,
            Entry::InTurn => &self.in_turn,
            Entry::Pass => &self.pass,
        }
    }
}

impl Blurs {
    pub(crate) fn new(engine: &Engine) -> Option<Self> {
        let cel_pages = Pages::writable(engine, CEL_OWN, CEL_OWN.storage, usize::MAX)?;
        let cel_paged = cel_pages.source();
        let cel_source = include_str!("blur_cel.wgsl");
        let cel = [ISQRT_WGSL, BLEND_WGSL, TILE_WGSL, cel_paged.as_str(), BYTE_WGSL, cel_source];
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
        on_pages(tiles, picture)?;
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
        // The dispatches: each dab's steps, but a run of dabs that go in turn
        // on the same pages one dispatch.
        let mut planned: Vec<Planned> = Vec::new();
        for (index, window) in windows.iter().enumerate() {
            if window.in_turn().is_none() {
                planned.extend(steps[index].iter().map(|step| Planned::Apart(index, step)));
                continue;
            }
            if let Some(Planned::InTurn(run)) = planned.last_mut()
                && windows[run.start].pages == window.pages
            {
                run.end = index + 1;
                continue;
            }
            planned.push(Planned::InTurn(index..index + 1));
        }
        let stride = engine.device.limits().min_uniform_buffer_offset_alignment as usize / 4;
        let steps_at = Cell::new(0);
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
            let blocks_at = plan.end();
            // Each run in turn's list: its dabs' blocks and workgroups.
            let mut lists = Vec::with_capacity(planned.len());
            for each in &planned {
                lists.push((blocks_at + words.len()) as u32);
                if let Planned::InTurn(run) = each {
                    for index in run.clone() {
                        let [rx, ry, cx, cy] = windows[index].in_turn()?;
                        let block = (blocks_at + places[index]) as u32;
                        let turn: [u32; TURN_WORDS] = [block, rx, ry, cx, cy];
                        words.extend(turn);
                    }
                }
            }
            // Each dispatch's own words — its dab's block and its pass, or
            // its run's list and how many dabs it holds — on the plan past
            // the blocks, at an offset a binding may start at, as a pile's
            // runs' are (mod.rs: on a buffer of their own they cost a pile 5
            // to 7 µs more made anew). The first of two such uniforms: they
            // stay apart until a third comes (rule of three, CLAUDE.md
            // absolute rule 1).
            let at = (blocks_at + words.len()).next_multiple_of(stride);
            steps_at.set(at);
            words.resize(at - blocks_at, 0);
            for (each, &list) in planned.iter().zip(&lists) {
                words.extend(match each {
                    Planned::InTurn(run) => [list, run.len() as u32],
                    Planned::Apart(index, step) => [(blocks_at + places[*index]) as u32, step.pass],
                });
                words.resize(words.len() + stride - 2, 0);
            }
            Some(words)
        });
        let plan = plan?;
        let (between, second) = (self.between.as_ref()?, self.second.as_ref());
        let dispatches: Vec<Encoded> = planned
            .iter()
            .enumerate()
            .map(|(index, each)| {
                let (window, entry, groups) = match each {
                    Planned::InTurn(run) => (&windows[run.start], Entry::InTurn, (1, 1)),
                    Planned::Apart(at, step) => (&windows[*at], step.entry, step.groups),
                };
                // A dab whose window is on one page goes by the dispatches
                // that bind one. The widest bind it too, so no test tells the
                // two apart — only the time (`Blurs::one`; mutant r07, 11-06).
                let way = if window.pages.len() == 1 { &self.one } else { &self.widest };
                let mut bound = whole(&[(0, plan), (1, between)]);
                let at = ((steps_at.get() + index * stride) * 4) as u64;
                bound.push(wgpu::BindGroupEntry { binding: 2, resource: range(plan, at..at + 16) });
                if let (Entry::Pass, Some(second)) = (entry, second) {
                    bound.extend(whole(&[(3, second)]));
                }
                bound.extend(way.pages.entries(of_pages(picture, &window.pages)));
                Encoded { pipeline: way.of(entry), bound, groups: flat(groups) }
            })
            .collect();
        encode(engine, &dispatches);
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
        self.fill_by(engine, executor, cel, tiles, picture, self.widest(engine, None)?)
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
        on_pages(tiles, picture)?;
        let copied = copied(engine, executor, (pages, cel), tiles)?;
        self.through_cel(engine, &self.filling, &copied.out, (tiles, picture), None, most)
    }

    /// `tiles` finished (`blur_finish`): each pixel of `cel` — its tiles on
    /// the pool's pages, copied as the executor copies a row whole — moved
    /// toward the picture by `cover`, stored as the cel stores it: straight
    /// RGBA8, tile after tile in `tiles`' order, as the executor's output
    /// is. Submits the work, the caller waits.
    pub(crate) fn finish(
        &self,
        engine: &Engine,
        executor: &Composite,
        cel: (&[wgpu::Buffer], &TileSet),
        (tiles, picture): (&[StrokeTile], &[wgpu::Buffer]),
        cover: Cover,
    ) -> Option<wgpu::Buffer> {
        let most = self.widest(engine, cover.mask)?;
        self.finish_by(engine, executor, cel, (tiles, picture), cover, most)
    }

    /// `finish`, a pass taking no more than `most` (pages, tiles).
    fn finish_by(
        &self,
        engine: &Engine,
        executor: &Composite,
        (pages, cel): (&[wgpu::Buffer], &TileSet),
        (tiles, picture): (&[StrokeTile], &[wgpu::Buffer]),
        cover: Cover,
        most: (usize, usize),
    ) -> Option<wgpu::Buffer> {
        on_pages(tiles, picture)?;
        if let Some(mask) = cover.mask {
            mask.checked()?;
        }
        let copied = copied(engine, executor, (pages, cel), tiles)?;
        let finishing = &self.finishing;
        self.through_cel(engine, finishing, &copied.out, (tiles, picture), Some(cover), most)?;
        Some(copied.out)
    }

    /// The most a pass of the cel's takes on this device: the pages it
    /// binds, and the tiles of the cel a binding holds and a dispatch
    /// reaches — and of what it is given, a tile's place and, under `mask`,
    /// a tile row of the mask's rows at their worst. No test lays a cel past
    /// a binding (2 GB here, 32,768 tiles), so none tells a tile's bytes
    /// from its words in this line (mutant r19, 11-06), the mask's rows
    /// from none (v21), or a finish under a mask cut as under none (v22).
    fn widest(&self, engine: &Engine, mask: Option<&Mask>) -> Option<(usize, usize)> {
        let band = mask.map_or(0, Mask::per_tile);
        let per_tile = (TILE_TEXELS * 4).max(TILE_PLACE_WORDS * 4 + band);
        let most = tiles_a_pass(engine, per_tile, COVER_WORDS as u64 * 4)?;
        Some((self.cel_pages.per_pass(), most))
    }

    /// One of blur_cel.wgsl's passes between `picture` and `cel`, `tiles`
    /// one after another as the executor puts them, a run of them a
    /// dispatch ([`runs`]), each given the finish's `cover` and the rows of
    /// its mask the run's tiles lie on.
    fn through_cel(
        &self,
        engine: &Engine,
        pass: &wgpu::ComputePipeline,
        cel: &wgpu::Buffer,
        (tiles, picture): (&[StrokeTile], &[wgpu::Buffer]),
        cover: Option<Cover>,
        (pages_per_pass, most): (usize, usize),
    ) -> Option<()> {
        let tile_bytes = TILE_TEXELS * 4;
        let mask = cover.and_then(|cover| cover.mask);
        let on = tiles.iter().map(|tile| Some(tile.at.page));
        // Under a mask a pass reaches no more tile rows than it takes tiles,
        // as it is given the mask's rows they lie on. No test lays a band
        // past a binding (2 GB here), so none tells the rows from none
        // (mutant v19, 11-06).
        let rows: Option<Vec<i32>> = mask.map(|_| tiles.iter().map(|tile| tile.row).collect());
        let runs = runs(on, rows.as_deref(), pages_per_pass, most);
        let mut encoder = engine
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor::default());
        let given: Vec<wgpu::Buffer> = runs
            .iter()
            .map(|(run, pages)| {
                let ran = &tiles[run.clone()];
                let table: Vec<u32> = page_table(pages, picture.len()).collect();
                let mut words = vec![0; COVER_WORDS];
                words.extend(ran.iter().flat_map(|tile| {
                    let k = table[usize::from(tile.at.page)];
                    [k, u32::from(tile.at.slot), tile.column as u32, tile.row as u32]
                }));
                let band = mask.map(|mask| {
                    let rows = mask.band(ran.iter().map(|tile| tile.row));
                    let shape = [
                        1,
                        words.len() as u32,
                        mask.size.width,
                        // The rows here, not the box's: past them a pixel
                        // reads past what the pass is given, which this
                        // device reads as nothing — so no test here tells
                        // the two apart (mutant v18, 11-06).
                        rows.len() as u32,
                        mask.size.stride(),
                        mask.at.0 as u32,
                        (mask.at.1 + rows.start as i32) as u32,
                    ];
                    words[1..COVER_WORDS].copy_from_slice(&shape);
                    mask.rows(&rows)
                });
                words[0] = cover.map_or(0, |cover| cover.opacity);
                given(engine, &mut encoder, &words, band)
            })
            .collect::<Option<_>>()?;
        let dispatches: Vec<Encoded> = runs
            .iter()
            .zip(&given)
            .map(|((run, pages), given)| {
                let bytes = run.start as u64 * tile_bytes..run.end as u64 * tile_bytes;
                let resource = range(cel, bytes);
                let mut bound = vec![wgpu::BindGroupEntry { binding: 0, resource }];
                bound.extend(whole(&[(1, given)]));
                bound.extend(self.cel_pages.entries(of_pages(picture, pages)));
                let groups = ((TILE_TEXELS / CEL_GROUP) as u32, run.len() as u32, 1);
                Encoded { pipeline: pass, bound, groups }
            })
            .collect();
        encode_on(engine, &mut encoder, &dispatches);
        engine.queue.submit([encoder.finish()]);
        Some(())
    }
}

/// `slot` holding a buffer of `bytes` at least, made anew where it holds
/// less.
fn grown(engine: &Engine, slot: &mut Option<wgpu::Buffer>, bytes: u64, label: &str) {
    if slot.as_ref().is_none_or(|buffer| buffer.size() < bytes) {
        *slot = Some(plane(engine, label, bytes));
    }
}

/// `tiles` of `cel` — its tiles on the pool's `pages` — as the executor
/// copies a row whole over nothing (`Composite::copied`): its stored
/// bytes, tile after tile.
fn copied(
    engine: &Engine,
    executor: &Composite,
    (pages, cel): (&[wgpu::Buffer], &TileSet),
    tiles: &[StrokeTile],
) -> Option<Composited> {
    let at: Vec<(i32, i32)> = tiles.iter().map(|tile| (tile.column, tile.row)).collect();
    executor.copied(engine, pages, cel, &at, executor.widest())
}
