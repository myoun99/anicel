//! The blur brush's dab on the GPU (I-75 흐리기 — `BrushBlurPicture.blurDab`,
//! C's `qa_blur_dab`; gpu-canonical-store D5, 01:13): the stroke's picture
//! under each dab moved toward its blur by what the dab lays as paint onto
//! nothing. `blur.wgsl` has the schedule; the passes are the fx Gaussian's
//! box law and its strips (`effects/blur/box.wgsl`, `three.wgsl`; the
//! ranges and the cut gaussian.rs's `within`), the coverage the dab
//! kernel's own (`dab_source`) — no second copy of any.
//!
//! ⏳The picture made from the cel — every tile a dab's window meets — and
//! the finished tile laid back on the cel (`qa_blur_result_tile`) are the
//! next piece's: both read the pool's pages. A radius whose strip has no
//! room in a workgroup's 16KB (r > 170, a brush past ~1000 px) goes a pass a
//! dispatch, the Gaussian's way — also to come (01:13 ③), and with it where
//! a dab's strips stop paying: on a whole picture a pass a dispatch wins past
//! r 56 (gaussian.rs's MOST_STRIPS_RADIUS), but a dab's seven dispatches
//! cost more than a picture's six, so its crossing is its own to measure.

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
use crate::kernels::effects::blur::gaussian::{BOX_WGSL, PASS_WORDS, Strips, THREE_WGSL, within};
use crate::kernels::shared::{ISQRT_WGSL, TILE_WGSL, pipeline};

/// blur.wgsl's block: the words before its passes, and before its grid.
const PASSES_AT: usize = 8;
const GRID_AT: usize = PASSES_AT + 6 * PASS_WORDS;

pub(crate) struct Blurs {
    rows: wgpu::ComputePipeline,
    columns: wgpu::ComputePipeline,
    plans: Plans,
    /// The rows' blur between a dab's two dispatches: grown, never shrunk.
    between: Option<wgpu::Buffer>,
}

/// The `index`-th pass's word `word` among `passes` (box.wgsl's `BoxPass`:
/// down, radius, first, end, line_first, line_end, …).
fn word(passes: &[u32], index: usize, word: usize) -> i32 {
    passes[index * PASS_WORDS + word] as i32
}

/// What a dab's blur reads and how its two dispatches cut it.
struct Window {
    passes: Vec<u32>,
    /// The first of the tiles it reads, and how many a row.
    first_tile: (i32, i32),
    tile_columns: usize,
    /// Each of those tiles' index among the stroke's, row after row.
    grid: Vec<usize>,
    /// How each dispatch is cut, a strip a workgroup.
    rows: Strips,
    columns: Strips,
    /// The bytes of the rows' blur between them.
    between: u64,
}

impl Window {
    fn of(dab: &Dab, radius: u32, at: &HashMap<(i32, i32), usize>) -> Option<Window> {
        if radius == 0 {
            return fail("a blur of no radius changes no pixel");
        }
        let Some(within) = within(dab.region, radius) else {
            return fail(format!(
                "a blur of radius {radius} reads past its strip further than a workgroup has \
                 room for — a radius this large waits for the pass-a-dispatch way \
                 (gpu-canonical-store 01:13 ③)"
            ));
        };
        let r = radius as i32;
        let pass = |index, field| word(&within.words, index, field);
        // The rows' first pass reads one radius past what it puts: that is
        // the window; its lines are the window's rows.
        let (left, right) = (pass(0, 2) - r, pass(0, 3) + r);
        let (top, bottom) = (pass(0, 4), pass(0, 5));
        let width = pass(2, 3) - pass(2, 2);
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
            rows: within.rows,
            columns: within.columns,
            between: u64::from((bottom - top) as u32) * width as u64 * 8,
            passes: within.words,
        })
    }
}

impl Blurs {
    pub(crate) fn new(engine: &Engine) -> Self {
        let sources = [
            ISQRT_WGSL,
            BLEND_WGSL,
            TILE_WGSL,
            include_str!("dab.wgsl"),
            BOX_WGSL,
            THREE_WGSL,
            include_str!("blur.wgsl"),
        ];
        Self {
            rows: pipeline(engine, &sources, "blur_rows_pass"),
            columns: pipeline(engine, &sources, "blur_columns_pass"),
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
            .map(|(dab, radius)| Window::of(dab, *radius, &at))
            .collect::<Option<_>>()?;
        let most = engine.device.limits().max_compute_workgroups_per_dimension;
        let groups = windows.iter().flat_map(|window| {
            let ((a, b), (c, d)) = (window.rows.groups, window.columns.groups);
            [a, b, c, d]
        });
        if groups.into_iter().any(|count| count > most) {
            return fail("a blur dab has more workgroups than a dispatch reaches");
        }
        let between_bytes = windows.iter().map(|window| window.between).max()?;
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
                    window.rows.lines,
                    window.rows.run,
                    window.columns.lines,
                    window.columns.run,
                ]);
                words.extend(&window.passes);
                words.extend(window.grid.iter().map(|&tile| plan.tile_at(tile)));
            }
            blocks_at.set(plan.end());
            Some(words)
        });
        let plan = plan?;
        let align = u64::from(engine.device.limits().min_uniform_buffer_offset_alignment);
        let mut uniform = vec![0u8; align as usize * windows.len()];
        for (index, place) in places.iter().enumerate() {
            let block = (blocks_at.get() + place) as u32;
            uniform[index * align as usize..][..4].copy_from_slice(&block.to_le_bytes());
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
        let bind_groups: Vec<[wgpu::BindGroup; 2]> = (0..windows.len())
            .map(|index| [bound(&self.rows, index), bound(&self.columns, index)])
            .collect();
        let mut encoder = engine
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor::default());
        {
            let mut pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor::default());
            for (window, [rows, columns]) in windows.iter().zip(&bind_groups) {
                pass.set_pipeline(&self.rows);
                pass.set_bind_group(0, rows, &[]);
                pass.dispatch_workgroups(window.rows.groups.0, window.rows.groups.1, 1);
                pass.set_pipeline(&self.columns);
                pass.set_bind_group(0, columns, &[]);
                let (along, across) = window.columns.groups;
                pass.dispatch_workgroups(along, across, 1);
            }
        }
        engine.queue.submit([encoder.finish()]);
        Some(())
    }
}
