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
//! ⏳The picture made from the cel — every tile a dab's window meets — and
//! the finished tile laid back on the cel (`qa_blur_result_tile`) are the
//! next piece's: the executor reads the cel's tiles as a one-row copy plan,
//! and the finished tiles go out as its output does (캔버스 베이스 11-06
//! 02:29).

#[cfg(test)]
#[path = "blur_tests.rs"]
mod tests;

use std::cell::Cell;
use std::collections::HashMap;

use wgpu::util::DeviceExt;

use super::{Dab, Paper, Plans, StrokeTile, TILE};
use crate::device::Engine;
use crate::fail;
use crate::kernels::blend::BLEND_WGSL;
use crate::kernels::effects::blur::fits;
use crate::kernels::effects::blur::gaussian::{
    BOX_WGSL, PASS_WGSL, PASS_WORDS, Strips, THREE_WGSL, within,
};
use crate::kernels::shared::{ISQRT_WGSL, TILE_WGSL, pipeline};

/// blur.wgsl's block: the words before its passes, and before its grid.
const PASSES_AT: usize = 8;
const GRID_AT: usize = PASSES_AT + 6 * PASS_WORDS;

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
    rows: wgpu::ComputePipeline,
    columns: wgpu::ComputePipeline,
    pass: wgpu::ComputePipeline,
    plans: Plans,
    /// What one dispatch of a dab puts for the next: grown, never shrunk.
    between: Option<wgpu::Buffer>,
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
    /// Each of those tiles' index among the stroke's, row after row.
    grid: Vec<usize>,
    ways: Ways,
    /// The bytes one dispatch puts for the next: the rows' blur, or the
    /// two planes a pass a dispatch alternates between.
    between: u64,
}

impl Window {
    fn of(
        dab: &Dab,
        radius: u32,
        at: &HashMap<(i32, i32), usize>,
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
            // Two planes as the rows' first pass puts.
            Ways::Passes(_) => 2 * lines * (pass(0, 3) - pass(0, 2)) as u64 * 8,
        };
        let first_tile = (left.div_euclid(TILE), top.div_euclid(TILE));
        let (last_column, last_row) = ((right - 1).div_euclid(TILE), (bottom - 1).div_euclid(TILE));
        let mut grid = Vec::new();
        for row in first_tile.1..=last_row {
            for column in first_tile.0..=last_column {
                match at.get(&(column, row)) {
                    Some(&index) => grid.push(index),
                    None => {
                        return fail(format!(
                            "a blur dab reads tile ({column}, {row}), which the stroke has no \
                             slot for"
                        ));
                    }
                }
            }
        }
        Some(Window {
            first_tile,
            tile_columns: (last_column - first_tile.0 + 1) as usize,
            grid,
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

impl Blurs {
    pub(crate) fn new(engine: &Engine) -> Self {
        let dab = include_str!("dab.wgsl");
        let blur = include_str!("blur.wgsl");
        let strips = [ISQRT_WGSL, BLEND_WGSL, TILE_WGSL, dab, BOX_WGSL, THREE_WGSL, blur];
        let strips = [&strips[..], &[include_str!("blur_three.wgsl")]].concat();
        let passes = [ISQRT_WGSL, BLEND_WGSL, TILE_WGSL, dab, BOX_WGSL, PASS_WGSL, blur];
        let passes = [&passes[..], &[include_str!("blur_pass.wgsl")]].concat();
        Self {
            rows: pipeline(engine, &strips, "blur_rows_pass"),
            columns: pipeline(engine, &strips, "blur_columns_pass"),
            pass: pipeline(engine, &passes, "blur_pass_one"),
            plans: Plans::new(),
            between: None,
        }
    }

    /// Blurs the stroke's `picture` — `tiles`' planes, two words a pixel, a
    /// slot a tile — under each of `dabs`, in their order, at its box radius
    /// (the app's `BrushBlurPicture.blurRadiusOf`), over `paper`; submits
    /// the work, the caller waits. Every tile a dab's window meets — what
    /// its blur reads, three radii past it each side — is the caller's to
    /// have among `tiles`.
    pub(crate) fn blur(
        &mut self,
        engine: &Engine,
        tiles: &[StrokeTile],
        dabs: &[(Dab, u32)],
        paper: Option<&Paper>,
        picture: &wgpu::Buffer,
    ) -> Option<()> {
        self.blur_by(engine, tiles, dabs, paper, picture, Route::Strips)
    }

    /// `blur`, the passes going by `route`.
    fn blur_by(
        &mut self,
        engine: &Engine,
        tiles: &[StrokeTile],
        dabs: &[(Dab, u32)],
        paper: Option<&Paper>,
        picture: &wgpu::Buffer,
        route: Route,
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
        let at: HashMap<(i32, i32), usize> = tiles
            .iter()
            .enumerate()
            .map(|(index, tile)| ((tile.column, tile.row), index))
            .collect();
        let windows: Vec<Window> = dabs
            .iter()
            .map(|(dab, radius)| Window::of(dab, *radius, &at, route))
            .collect::<Option<_>>()?;
        let steps: Vec<Vec<Step>> = windows.iter().map(Window::steps).collect();
        let between_bytes = windows.iter().map(|window| window.between).max()?;
        // No test lays a window past a binding here (2 GB) or a dispatch's
        // groups, so none tells this line from its absence (mutants f01, f02,
        // 11-06); a device of 128 MB refuses a dab of size 2000 by it.
        fits(engine, &[between_bytes], steps.iter().flatten().map(|step| step.groups))?;
        if self.between.as_ref().is_none_or(|buffer| buffer.size() < between_bytes) {
            self.between = Some(engine.device.create_buffer(&wgpu::BufferDescriptor {
                label: Some("blur between"),
                size: between_bytes,
                usage: wgpu::BufferUsages::STORAGE,
                mapped_at_creation: false,
            }));
        }
        let white: Vec<Dab> = dabs.iter().map(|(dab, _)| *dab).collect();
        // Each dab's block, after the plan's own words: where it starts
        // among the blocks.
        let places: Vec<usize> = windows
            .iter()
            .scan(0, |end, window| {
                let place = *end;
                *end += GRID_AT + window.grid.len();
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
                words.extend(window.grid.iter().map(|&tile| plan.tile_at(tile)));
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
        let between = self.between.as_ref()?;
        let bound = |pipeline: &wgpu::ComputePipeline, index: usize| {
            let entry = |binding, resource| wgpu::BindGroupEntry { binding, resource };
            engine.device.create_bind_group(&wgpu::BindGroupDescriptor {
                label: Some("blur dab"),
                layout: &pipeline.get_bind_group_layout(0),
                entries: &[
                    entry(0, plan.as_entire_binding()),
                    entry(1, picture.as_entire_binding()),
                    entry(4, between.as_entire_binding()),
                    entry(5, wgpu::BindingResource::Buffer(wgpu::BufferBinding {
                        buffer: &uniform,
                        offset: index as u64 * align,
                        size: wgpu::BufferSize::new(16),
                    })),
                ],
            })
        };
        let steps: Vec<Step> = steps.into_iter().flatten().collect();
        let pipeline = |entry| match entry {
            Entry::Rows => &self.rows,
            Entry::Columns => &self.columns,
            Entry::Pass => &self.pass,
        };
        let bind_groups: Vec<wgpu::BindGroup> = steps
            .iter()
            .enumerate()
            .map(|(slot, step)| bound(pipeline(step.entry), slot))
            .collect();
        let mut encoder = engine
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor::default());
        {
            let mut pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor::default());
            for (step, bind_group) in steps.iter().zip(&bind_groups) {
                pass.set_pipeline(pipeline(step.entry));
                pass.set_bind_group(0, bind_group, &[]);
                pass.dispatch_workgroups(step.groups.0, step.groups.1, 1);
            }
        }
        engine.queue.submit([encoder.finish()]);
        Some(())
    }
}
