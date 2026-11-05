//! The dab kernel — 3단계 (gpu-canonical-store ⑥, 1a (3/3 보탬)): a
//! stroke's dabs piled on its 16-bit plane on the GPU, and the plane's bytes
//! beside it. `dab.wgsl` has the walk and the arithmetic; this file turns
//! the app's numbers into the integers it reads — the one place a float
//! becomes one (1a 보탬 「넘겨받기」). Rust never fuses a multiply and an
//! add, and each number here is one rounding of one product, so every
//! device makes the same integers.
//!
//! D1 lays a square dab and a round tip — its profile along the radius, or
//! a small circle's square tables —, the edge, the ceiling, the share and
//! the level a dab settles at, over and erase. A tip's bitmap, the paper
//! and the second tip come in the lanes after (design (1), 11-05 21:53).

// ⏳Nothing outside the tests calls it until the app's connection round,
// which 관제 opens (gpu-canonical-store 21:41).
#![cfg_attr(not(test), allow(dead_code))]

#[cfg(test)]
mod tests;

use std::collections::HashMap;

use wgpu::util::DeviceExt;

use crate::device::Engine;
use crate::fail;
use crate::kernels::blend::BLEND_WGSL;
use crate::kernels::shared::{ISQRT_WGSL, TILE_WGSL};

/// A tile's side in pixels (1a ①).
const TILE: i32 = 128;
const TILE_WORDS: usize = 5;
const DAB_WORDS: usize = 21;
const NO_TABLE: u32 = u32::MAX;

// The C engine's flags (QA_DAB_FLAG_*), as dab.wgsl reads them.
const ERASE: u32 = 1;
const ROUND: u32 = 2;
const THRESHOLD: u32 = 32;
const EDGE_HELD: u32 = 128;

/// A scale is kept under this, so a distance under 2^15 times it stays in
/// u32 (1a 보탬 기하).
const SCALE_BOUND: f64 = 131072.0;

/// A round tip's two tables and how they are read — `RoundTipProfile`'s
/// numbers as the app builds them.
pub(crate) struct RoundProfile<'a> {
    /// What a pixel lays, entry by entry, on 0..=1.
    pub(crate) coverage: &'a [f64],
    /// What of it piles.
    pub(crate) pile: &'a [f64],
    /// Entries per canvas pixel.
    pub(crate) scale: f64,
    /// Nothing at or past this distance — along each axis where the tables
    /// are square.
    pub(crate) reach: f64,
    /// At or within it a pixel lays 1, all of it piling; under 0 for none.
    pub(crate) inner: f64,
    /// Entries a row holds where the tables are square, or 0.
    pub(crate) row_length: u32,
}

/// What a dab covers before its edge.
pub(crate) enum Shape<'a> {
    /// All of its region.
    Square,
    Round(&'a RoundProfile<'a>),
}

/// The brush's edge (`brushDabEdgeLaw`).
pub(crate) enum Edge {
    /// 없음: a cut at half.
    Threshold,
    /// A contrast about half; 1 leaves the coverage as it is.
    Contrast(f64),
}

/// A dab as the app has it (`qa_dab_spec`).
pub(crate) struct Dab<'a> {
    pub(crate) centre: [f64; 2],
    /// The pixels it may touch, [left, top, right, bottom).
    pub(crate) region: [i32; 4],
    /// Red, green, blue, and the colour's own alpha.
    pub(crate) colour: [u8; 4],
    pub(crate) opacity: f64,
    pub(crate) flow: f64,
    pub(crate) edge: Edge,
    /// Whether the tip holds an edge that does not pile (`tipHoldsAnEdge`).
    pub(crate) edge_held: bool,
    pub(crate) erase: bool,
    pub(crate) shape: Shape<'a>,
    /// The table it lays its share through, 1026 entries, or none.
    pub(crate) evening: Option<&'a [f64]>,
}

/// A tile of the stroke: its column and row on the canvas's grid, and its
/// slot in the planes and their view.
#[derive(Clone, Copy)]
pub(crate) struct StrokeTile {
    pub(crate) column: i32,
    pub(crate) row: i32,
    pub(crate) slot: u32,
}

pub(crate) struct Dabs {
    pipeline: wgpu::ComputePipeline,
}

impl Dabs {
    pub(crate) fn new(engine: &Engine) -> Self {
        let source = [ISQRT_WGSL, BLEND_WGSL, TILE_WGSL, include_str!("dab.wgsl")].join("\n");
        let module = engine
            .device
            .create_shader_module(wgpu::ShaderModuleDescriptor {
                label: Some("dab"),
                source: wgpu::ShaderSource::Wgsl(source.into()),
            });
        let pipeline = engine
            .device
            .create_compute_pipeline(&wgpu::ComputePipelineDescriptor {
                label: Some("dab"),
                layout: None,
                module: &module,
                entry_point: Some("walk"),
                compilation_options: Default::default(),
                cache: None,
            });
        Self { pipeline }
    }

    /// Piles `dabs`, in their order, on the stroke `tiles` — `planes` two
    /// words a pixel, `view` one, a slot a tile — and writes each tile's
    /// bytes; submits the work, the caller waits. A dab's pixels on a tile
    /// not among `tiles` are the caller's to have given.
    pub(crate) fn pile(
        &self,
        engine: &Engine,
        tiles: &[StrokeTile],
        dabs: &[Dab],
        planes: &wgpu::Buffer,
        view: &wgpu::Buffer,
    ) -> Option<()> {
        if tiles.is_empty() {
            return Some(());
        }
        let most = engine.device.limits().max_compute_workgroups_per_dimension;
        if tiles.len() > most as usize {
            return fail(format!("{} stroke tiles exceed a dispatch's {most}", tiles.len()));
        }
        let words = planned(tiles, dabs)?;
        let plan = engine
            .device
            .create_buffer_init(&wgpu::util::BufferInitDescriptor {
                label: Some("dab plan"),
                contents: &words.iter().flat_map(|word| word.to_le_bytes()).collect::<Vec<_>>(),
                usage: wgpu::BufferUsages::STORAGE,
            });
        let bind_group = engine.device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("dab"),
            layout: &self.pipeline.get_bind_group_layout(0),
            entries: &[
                wgpu::BindGroupEntry {
                    binding: 0,
                    resource: plan.as_entire_binding(),
                },
                wgpu::BindGroupEntry {
                    binding: 1,
                    resource: planes.as_entire_binding(),
                },
                wgpu::BindGroupEntry {
                    binding: 2,
                    resource: view.as_entire_binding(),
                },
            ],
        });
        let mut encoder = engine
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor::default());
        {
            let mut pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor::default());
            pass.set_pipeline(&self.pipeline);
            pass.set_bind_group(0, &bind_group, &[]);
            let groups = (TILE / 8) as u32;
            pass.dispatch_workgroups(groups, groups, tiles.len() as u32);
        }
        engine.queue.submit([encoder.finish()]);
        Some(())
    }
}

/// The plan dab.wgsl reads: the tiles, each tile's list, the records, the
/// tables — each table once, however many dabs read it.
fn planned(tiles: &[StrokeTile], dabs: &[Dab]) -> Option<Vec<u32>> {
    let at: HashMap<(i32, i32), usize> = tiles
        .iter()
        .enumerate()
        .map(|(index, tile)| ((tile.column, tile.row), index))
        .collect();
    // A dab's tiles are looked for within the stroke's, however far its
    // region runs.
    let columns = tiles.iter().map(|tile| tile.column);
    let rows = tiles.iter().map(|tile| tile.row);
    let (first_column, last_column) = (columns.clone().min()?, columns.max()?);
    let (first_row, last_row) = (rows.clone().min()?, rows.max()?);
    let mut lists = vec![Vec::new(); tiles.len()];
    for (index, dab) in dabs.iter().enumerate() {
        let [left, top, right, bottom] = dab.region;
        if right <= left || bottom <= top {
            continue;
        }
        let down = top.div_euclid(TILE).max(first_row)
            ..=(bottom - 1).div_euclid(TILE).min(last_row);
        for row in down {
            let across = left.div_euclid(TILE).max(first_column)
                ..=(right - 1).div_euclid(TILE).min(last_column);
            for column in across {
                if let Some(&tile) = at.get(&(column, row)) {
                    lists[tile].push(index);
                }
            }
        }
    }
    let listed: usize = lists.iter().map(Vec::len).sum();
    let records_at = tiles.len() * TILE_WORDS + listed;
    let tables_at = records_at + dabs.len() * DAB_WORDS;
    let mut words = Vec::with_capacity(tables_at);
    let mut first = tiles.len() * TILE_WORDS;
    for (tile, list) in tiles.iter().zip(&lists) {
        let (column, row) = (tile.column as u32, tile.row as u32);
        words.extend([column, row, tile.slot, first as u32, list.len() as u32]);
        first += list.len();
    }
    for list in &lists {
        words.extend(list.iter().map(|&dab| (records_at + dab * DAB_WORDS) as u32));
    }
    let mut tables = Tables { words: Vec::new(), at: tables_at, placed: HashMap::new() };
    for dab in dabs {
        words.extend(record(dab, &mut tables)?);
    }
    words.extend(tables.words);
    Some(words)
}

/// The tables the records point at, each placed once.
struct Tables {
    words: Vec<u32>,
    /// Where the plan's tables begin.
    at: usize,
    /// A table's place, by where the app keeps it.
    placed: HashMap<(usize, usize), u32>,
}

impl Tables {
    fn place(&mut self, table: &[f64]) -> u32 {
        let key = (table.as_ptr() as usize, table.len());
        if let Some(&place) = self.placed.get(&key) {
            return place;
        }
        let place = (self.at + self.words.len()) as u32;
        self.words.extend(table.iter().map(|&entry| wide(entry)));
        self.placed.insert(key, place);
        place
    }
}

/// A number on 0..=1 on the 16-bit scale, rounded once.
fn wide(value: f64) -> u32 {
    (value * 65535.0).round() as u32
}

/// A scale as `per_unit` × 2^point in an integer under [`SCALE_BOUND`],
/// the point as far as it goes.
fn fixed(per_unit: f64) -> (u32, u32) {
    let mut point = 0;
    while point < 31 && (per_unit * f64::from(1u32 << (point + 1))).round() < SCALE_BOUND {
        point += 1;
    }
    ((per_unit * f64::from(1u32 << point)).round() as u32, point)
}

fn record(dab: &Dab, tables: &mut Tables) -> Option<[u32; DAB_WORDS]> {
    let [left, top, right, bottom] = dab.region;
    let [red, green, blue, alpha] = dab.colour.map(u32::from);
    let (threshold, contrast) = match dab.edge {
        Edge::Threshold => (THRESHOLD, 256),
        Edge::Contrast(contrast) => (0, (contrast * 256.0).round() as u32),
    };
    let flags = threshold
        | if dab.erase { ERASE } else { 0 }
        | if dab.edge_held { EDGE_HELD } else { 0 }
        | if matches!(dab.shape, Shape::Round(_)) { ROUND } else { 0 };
    let mut words = [0u32; DAB_WORDS];
    words[..13].copy_from_slice(&[
        (dab.centre[0] * 256.0).round() as i32 as u32,
        (dab.centre[1] * 256.0).round() as i32 as u32,
        left as u32,
        top as u32,
        right as u32,
        bottom as u32,
        flags,
        red | green << 8 | blue << 16,
        alpha * 257,
        wide(dab.opacity),
        wide(dab.flow),
        contrast,
        dab.evening.map_or(NO_TABLE, |table| tables.place(table)),
    ]);
    if let Shape::Round(profile) = dab.shape {
        // 1a 보탬 기하: distances are taken shifted s bits off 1/256 px,
        // s the least that keeps one under 2^15 within the reach.
        let reach8 = (profile.reach * 256.0).ceil() as u32 + 256;
        let shift = (32 - reach8.leading_zeros()).saturating_sub(15);
        let unit = 256.0 / f64::from(1u32 << shift);
        let (scale, point) = fixed(profile.scale / unit);
        if point < 15 {
            // A unit of distance over four entries: no tip the app draws,
            // whose tables hold 16 entries a pixel at most and whose unit
            // is 1/32 px or finer to its size of 2000.
            return fail(format!("a tip of {} entries a pixel at shift {shift}", profile.scale));
        }
        words[13..].copy_from_slice(&[
            shift,
            (profile.reach * unit).ceil() as u32,
            (profile.inner * unit).floor() as i32 as u32,
            scale,
            point,
            profile.row_length,
            tables.place(profile.coverage),
            tables.place(profile.pile),
        ]);
    }
    Some(words)
}
