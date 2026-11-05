//! V1, the cel pixel pass on the GPU (gpu-census V1; gpu-canonical-store
//! 11-06 04:39): 색 편집's verbs — 색 변환, 픽셀 비우기, 2치화, 색 삭제,
//! 색 유지 — over a cel's stored tiles, as C's `qa_cel_pixel_pass_tile` and
//! the app's `overwriteCelPixels` run them, with no CPU copy of the law
//! (`kernels/mod.rs`); cel_pixel.wgsl has it.
//!
//! The walk is the cel's tiles row by row, those it has none of left out:
//! the app's `celPixelWalkFor` order. An undo replays its recipe by
//! position, so the order is the contract.
//!
//! A pass reads the cel's tiles from the pool's pages as they are stored,
//! not through the executor's copy: 픽셀 비우기 leaves a colour under an
//! alpha of 0, which a copy through the 16-bit scale makes 0 — and the
//! selector, reading R, G and B alone, would then name other pixels than
//! the ones the recipe's walk took (캔버스 베이스 11-06 04:39 ①).

// ⏳Nothing outside the tests runs it until the app's bridge round
// (gpu-canonical-store ⑧).
#![cfg_attr(not(test), allow(dead_code))]

#[cfg(test)]
mod tests;

use std::collections::BTreeSet;

use wgpu::util::DeviceExt;

use crate::device::Engine;
use crate::fail;
use crate::kernels::composite::{TILE_TEXELS, TileAt, TileSet};
use crate::kernels::effects::{KEY_WGSL, KeyRun};
use crate::kernels::shared::{Pages, TILE_WGSL, pipeline};

/// The storage buffers a pass binds besides its pages: what it is given,
/// the new pixels, and the counts or the runs.
const OWN_BUFFERS: u32 = 3;
/// cel_pixel.wgsl's CEL_TILE_WORDS.
const TILE_WORDS: usize = 5;

/// The channel a verb writes, as the app stages it (`CelPixelStage`): its
/// bytes, where byte i sits in a pixel's word — byte `base + i · stride` —
/// and whether a pixel with no ink takes part.
#[derive(Clone, Copy, Debug)]
pub(crate) struct Channel {
    pub(crate) bytes: u32,
    pub(crate) base: u32,
    pub(crate) stride: u32,
    pub(crate) takes_empty: bool,
}

/// The colour selector: a run of one key — the fx colour key's tables
/// (`KeyRun`), from the app's one definition, `CelColorKey` — and whether
/// the verb keeps what the key names (색 유지) rather than takes it (색 삭제).
pub(crate) struct Selector<'a> {
    pub(crate) key: KeyRun<'a>,
    pub(crate) keeps_matches: bool,
}

/// What the pixels taking part take.
pub(crate) enum Incoming<'a> {
    /// Going forward: the channel's bytes, one value for every pixel.
    Value(&'a [u8]),
    /// An undo: the recipe laid out (`CelPixelRestore.streamFor`) — the
    /// i-th pixel's channel bytes at `i · step` — and how many pixels it
    /// holds.
    Recipe { bytes: &'a [u8], step: u32, count: u64 },
}

/// One verb: C's `qa_cel_pixel_spec`.
pub(crate) struct Verb<'a> {
    pub(crate) channel: Channel,
    pub(crate) selector: Option<Selector<'a>>,
    /// 2치화's cut, 0 for none: a channel byte under it takes 0.
    pub(crate) threshold: u32,
    pub(crate) incoming: Incoming<'a>,
}

impl Verb<'_> {
    /// Fails where the channel is no bytes of a pixel's word or the
    /// incoming bytes cannot be read as it reads them.
    fn checked(&self) -> Option<()> {
        let Channel { bytes, base, stride, .. } = self.channel;
        if !(1..=3).contains(&bytes) || base + (bytes - 1) * stride > 3 {
            return fail(format!("{:?} is no channel of a pixel's four bytes", self.channel));
        }
        if self.threshold > 255 {
            return fail(format!("a cut of {} is past a byte", self.threshold));
        }
        let wanted = u64::from(bytes);
        match self.incoming {
            Incoming::Value(value) if value.len() as u64 != wanted => {
                fail(format!("a value of {} bytes for a channel of {bytes}", value.len()))
            }
            // The app's assert: `overwriteCelPixels`'s.
            Incoming::Recipe { .. } if self.threshold != 0 => {
                fail("an undo assigns its recipe — a cut has nothing to say to it")
            }
            Incoming::Recipe { bytes: stream, step, count }
                if count > 0 && (count - 1) * u64::from(step) + wanted > stream.len() as u64 =>
            {
                fail(format!("a recipe of {count} pixels reaches past its {} bytes", stream.len()))
            }
            _ => Some(()),
        }
    }

    fn is_undo(&self) -> bool {
        matches!(self.incoming, Incoming::Recipe { .. })
    }

    /// The incoming bytes, four a word, low first.
    fn incoming_words(&self) -> Vec<u32> {
        let bytes = match self.incoming {
            Incoming::Value(value) => value,
            Incoming::Recipe { bytes, .. } => bytes,
        };
        bytes
            .chunks(4)
            .map(|four| four.iter().rev().fold(0, |word, &byte| word << 8 | u32::from(byte)))
            .collect()
    }

    /// cel_pixel.wgsl's `CelPass` past where a pass's tiles start, its
    /// selector's tables and its incoming bytes are in what it is given.
    fn words(&self, [tiles_at, tables_at, incoming_at]: [u32; 3]) -> [u32; 13] {
        let Channel { bytes, base, stride, takes_empty } = self.channel;
        let step = match self.incoming {
            Incoming::Value(_) => 0,
            Incoming::Recipe { step, .. } => step,
        };
        [
            tiles_at,
            tables_at,
            incoming_at,
            bytes,
            base,
            stride,
            u32::from(takes_empty),
            u32::from(self.selector.is_some()),
            u32::from(self.selector.as_ref().is_some_and(|selector| selector.keeps_matches)),
            u32::from(self.is_undo()),
            step,
            self.threshold,
            // The app builds a recipe going forward only (`_RestoreBuilder`
            // stands where a value is given), so only then are runs put.
            u32::from(!self.is_undo()),
        ]
    }
}

/// What a pass left: the walked tiles — the cel's (column, row), in walk
/// order —, their new pixels, straight RGBA8 tile after tile in that order
/// (the executor's output's form, so one write path takes both), each one's
/// pixels that took part and — going forward — what those held, as runs of
/// a value (the channel's byte i in bits 8i) and a length.
pub(crate) struct Passed {
    pub(crate) tiles: Vec<(i32, i32)>,
    pub(crate) out: wgpu::Buffer,
    pub(crate) touched: Vec<u32>,
    pub(crate) runs: Vec<Vec<(u32, u32)>>,
}

/// A walked tile: where it is on the cel's grid, where it is stored.
struct Walked {
    column: i32,
    row: i32,
    at: TileAt,
}

/// The pass, compiled once for as many pages as the device lets it bind.
pub(crate) struct CelPixels {
    count: wgpu::ComputePipeline,
    apply: wgpu::ComputePipeline,
    pages: Pages,
}

impl CelPixels {
    pub(crate) fn new(engine: &Engine) -> Option<Self> {
        let pages = Pages::new(engine, OWN_BUFFERS, OWN_BUFFERS + 1)?;
        let read = pages.source();
        let sources = [KEY_WGSL, TILE_WGSL, &read, include_str!("cel_pixel.wgsl")];
        Some(Self {
            count: pipeline(engine, &sources, "cel_count"),
            apply: pipeline(engine, &sources, "cel_apply"),
            pages,
        })
    }

    /// Runs `verb` over `cel`, its tiles on the pool's `pool` pages; waits
    /// for the GPU twice — for the counts that place each tile's pixels and
    /// runs among the walk's, and for the runs.
    pub(crate) fn run(
        &self,
        engine: &Engine,
        pool: &[wgpu::Buffer],
        cel: &TileSet,
        verb: &Verb,
    ) -> Option<Passed> {
        self.run_by(engine, pool, cel, verb, self.pages.per_pass())
    }

    /// `run`, binding `per_pass` pages a pass at most — a smaller device's
    /// passes, which the tests take.
    fn run_by(
        &self,
        engine: &Engine,
        pool: &[wgpu::Buffer],
        cel: &TileSet,
        verb: &Verb,
        per_pass: usize,
    ) -> Option<Passed> {
        if per_pass == 0 || per_pass > self.pages.per_pass() {
            return fail(format!(
                "{per_pass} pages a pass; this device binds 1 to {}",
                self.pages.per_pass()
            ));
        }
        verb.checked()?;
        let walk = walk(cel, pool.len())?;
        let tiles: Vec<(i32, i32)> = walk.iter().map(|tile| (tile.column, tile.row)).collect();
        let out_bytes = (walk.len().max(1) as u64) * TILE_TEXELS * 4;
        fits(engine, out_bytes)?;
        let out = storage(engine, "cel pixels out", out_bytes);
        if walk.is_empty() {
            return Some(Passed { tiles, out, touched: Vec::new(), runs: Vec::new() });
        }
        let passes = passes(engine, &walk, per_pass);
        let counts = storage(engine, "cel pixel counts", walk.len() as u64 * 8);
        let given = Given::of(engine, &walk, &passes, &vec![(0, 0); walk.len()], verb);
        self.encode(engine, pool, &passes, &given, &self.count, [None, Some(&counts)]);
        let (touched, runs): (Vec<u32>, Vec<u32>) = words(&engine.read_buffer(&counts)?)
            .chunks_exact(2)
            .map(|two| (two[0], two[1]))
            .unzip();
        let total = touched.iter().map(|&each| u64::from(each)).sum::<u64>();
        if let Incoming::Recipe { count, .. } = verb.incoming
            && total > count
        {
            // `overwriteCelPixels`' refusal, before a pixel is written.
            return fail(format!(
                "the recipe holds {count} pixels and the walk it replays goes past them"
            ));
        }
        if total > u64::from(u32::MAX) {
            return fail(format!("{total} pixels take part — past a word's walk index"));
        }
        let starts = starts(&touched, &runs);
        let all_runs: u64 = runs.iter().map(|&each| u64::from(each)).sum();
        let run_bytes = if verb.is_undo() { 16 } else { (all_runs * 8).max(16) };
        fits(engine, run_bytes)?;
        let put = storage(engine, "cel pixel runs", run_bytes);
        let given = Given::of(engine, &walk, &passes, &starts, verb);
        self.encode(engine, pool, &passes, &given, &self.apply, [Some(&out), Some(&put)]);
        if verb.is_undo() {
            engine.wait()?;
            return Some(Passed { tiles, out, touched, runs: Vec::new() });
        }
        let runs = lengths(&words(&engine.read_buffer(&put)?), &touched, &runs, &starts);
        Some(Passed { tiles, out, touched, runs })
    }

    /// Encodes `pipeline` over each of `passes` and submits it, the new
    /// pixels and the counts or runs bound at 2 and 3 where given.
    fn encode(
        &self,
        engine: &Engine,
        pool: &[wgpu::Buffer],
        passes: &[Pass],
        given: &Given,
        pipeline: &wgpu::ComputePipeline,
        [out, put]: [Option<&wgpu::Buffer>; 2],
    ) {
        let layout = pipeline.get_bind_group_layout(0);
        let mut encoder = engine
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor::default());
        for (pass, uniform) in passes.iter().zip(&given.uniforms) {
            let mut entries = vec![
                wgpu::BindGroupEntry {
                    binding: 0,
                    resource: uniform.as_entire_binding(),
                },
                wgpu::BindGroupEntry {
                    binding: 1,
                    resource: given.words.as_entire_binding(),
                },
            ];
            for (binding, buffer) in [(2, out), (3, put)] {
                if let Some(buffer) = buffer {
                    entries.push(wgpu::BindGroupEntry {
                        binding,
                        resource: buffer.as_entire_binding(),
                    });
                }
            }
            let bound = pass.pages.iter().map(|&page| &pool[usize::from(page)]);
            entries.extend(self.pages.entries(bound));
            let bind_group = engine.device.create_bind_group(&wgpu::BindGroupDescriptor {
                label: Some("cel pixels"),
                layout: &layout,
                entries: &entries,
            });
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor::default());
            compute.set_pipeline(pipeline);
            compute.set_bind_group(0, &bind_group, &[]);
            compute.dispatch_workgroups(pass.tiles.len() as u32, 1, 1);
        }
        engine.queue.submit([encoder.finish()]);
    }
}

/// Where each walked tile's pixels and runs start among the walk's, from
/// how many of each it has.
fn starts(touched: &[u32], runs: &[u32]) -> Vec<(u32, u32)> {
    touched
        .iter()
        .zip(runs)
        .scan((0, 0), |sum, (&touched, &runs)| {
            let start = *sum;
            *sum = (sum.0 + touched, sum.1 + runs);
            Some(start)
        })
        .collect()
}

/// Each walked tile's runs as the apply entry `put` them — a value and the
/// rank in its tile of its first pixel, the tile's `runs` of them from its
/// start among `starts` — as a value and a length: to the next run's first
/// pixel, or to the tile's `touched`.
fn lengths(
    put: &[u32],
    touched: &[u32],
    runs: &[u32],
    starts: &[(u32, u32)],
) -> Vec<Vec<(u32, u32)>> {
    touched
        .iter()
        .zip(runs)
        .zip(starts)
        .map(|((&touched, &count), &(_, first))| {
            let held = &put[first as usize * 2..(first + count) as usize * 2];
            let ranks: Vec<(u32, u32)> = held.chunks_exact(2).map(|two| (two[0], two[1])).collect();
            let ends = ranks.iter().skip(1).map(|&(_, rank)| rank).chain([touched]);
            ranks.iter().zip(ends).map(|(&(value, rank), end)| (value, end - rank)).collect()
        })
        .collect()
}

/// The walk: `cel`'s tiles row by row, those it has none of left out, each
/// on one of the pool's `pool` pages.
fn walk(cel: &TileSet, pool: usize) -> Option<Vec<Walked>> {
    if cel.tiles.len() as u64 != u64::from(cel.columns) * u64::from(cel.rows) {
        return fail(format!(
            "{} tiles for a set of {} × {}",
            cel.tiles.len(),
            cel.columns,
            cel.rows
        ));
    }
    let mut walk = Vec::new();
    for (index, tile) in cel.tiles.iter().enumerate() {
        let Some(at) = *tile else {
            continue;
        };
        if usize::from(at.page) >= pool {
            return fail(format!("the cel names page {} of a pool of {pool}", at.page));
        }
        let index = index as u32;
        walk.push(Walked {
            column: cel.x0 + (index % cel.columns) as i32,
            row: cel.y0 + (index / cel.columns) as i32,
            at,
        });
    }
    Some(walk)
}

/// One dispatch: the pages it binds, in binding order, and the walked tiles
/// it takes, a workgroup each — by their index in the walk, with the
/// binding of each one's page.
struct Pass {
    pages: Vec<u16>,
    tiles: Vec<(usize, u32)>,
}

/// The walk's pages, `per_pass` a pass in the order of their numbers, each
/// pass taking the walked tiles on its pages — as many dispatches of them
/// as a dispatch's workgroups reach. A tile reads its own pixels alone, and
/// each one's place among the walk's is added up between the two entries,
/// so passes may take the walk in any order.
fn passes(engine: &Engine, walk: &[Walked], per_pass: usize) -> Vec<Pass> {
    let most = engine.device.limits().max_compute_workgroups_per_dimension as usize;
    let pages: Vec<u16> =
        walk.iter().map(|tile| tile.at.page).collect::<BTreeSet<_>>().into_iter().collect();
    let mut passes = Vec::new();
    for bound in pages.chunks(per_pass) {
        let tiles: Vec<(usize, u32)> = walk
            .iter()
            .enumerate()
            .filter_map(|(index, tile)| {
                let k = bound.iter().position(|&page| page == tile.at.page)?;
                Some((index, k as u32))
            })
            .collect();
        for some in tiles.chunks(most) {
            passes.push(Pass {
                pages: bound.to_vec(),
                tiles: some.to_vec(),
            });
        }
    }
    passes
}

/// What every pass is given — its tiles, the selector's key run, the
/// incoming bytes — and each pass's `CelPass`.
struct Given {
    words: wgpu::Buffer,
    uniforms: Vec<wgpu::Buffer>,
}

impl Given {
    /// For `passes` over `walk`, each walked tile's pixels and runs starting
    /// at `starts` among the walk's.
    fn of(
        engine: &Engine,
        walk: &[Walked],
        passes: &[Pass],
        starts: &[(u32, u32)],
        verb: &Verb,
    ) -> Given {
        let mut words: Vec<u32> = Vec::new();
        let mut tiles_at = Vec::with_capacity(passes.len());
        for pass in passes {
            tiles_at.push(words.len() as u32);
            for &(index, k) in &pass.tiles {
                let tile = &walk[index];
                let (touched, runs) = starts[index];
                let entry: [u32; TILE_WORDS] = [
                    k,
                    u32::from(tile.at.slot),
                    index as u32,
                    touched,
                    runs,
                ];
                words.extend(entry);
            }
        }
        let tables_at = words.len() as u32;
        if let Some(selector) = &verb.selector {
            words.extend(selector.key.words());
        }
        let incoming_at = words.len() as u32;
        words.extend(verb.incoming_words());
        let uniforms = tiles_at
            .iter()
            .map(|&at| {
                let words = verb.words([at, tables_at, incoming_at]);
                buffer(engine, "cel pass", &words, wgpu::BufferUsages::UNIFORM)
            })
            .collect();
        Given {
            words: buffer(engine, "cel pixels given", &words, wgpu::BufferUsages::STORAGE),
            uniforms,
        }
    }
}

/// Fails where a buffer of `size` bytes is past what one binding holds.
fn fits(engine: &Engine, size: u64) -> Option<()> {
    let limits = engine.device.limits();
    let room = u64::from(limits.max_storage_buffer_binding_size).min(limits.max_buffer_size);
    if size > room {
        return fail(format!("a cel pixel pass's {size} bytes exceed a binding of {room}"));
    }
    Some(())
}

/// A buffer a pass puts, of `bytes` — zeroes at first — that a copy reads.
fn storage(engine: &Engine, label: &str, bytes: u64) -> wgpu::Buffer {
    engine.device.create_buffer(&wgpu::BufferDescriptor {
        label: Some(label),
        size: bytes,
        usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
        mapped_at_creation: false,
    })
}

/// `words` as a buffer of `usage`.
fn buffer(engine: &Engine, label: &str, words: &[u32], usage: wgpu::BufferUsages) -> wgpu::Buffer {
    let bytes: Vec<u8> = words.iter().flat_map(|word| word.to_le_bytes()).collect();
    engine.device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
        label: Some(label),
        contents: if bytes.is_empty() { &[0; 4] } else { &bytes },
        usage,
    })
}

fn words(bytes: &[u8]) -> Vec<u32> {
    bytes
        .chunks_exact(4)
        .map(|four| u32::from_le_bytes([four[0], four[1], four[2], four[3]]))
        .collect()
}
