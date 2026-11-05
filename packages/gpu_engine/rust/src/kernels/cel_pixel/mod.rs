//! V1, the cel pixel pass on the GPU (gpu-census V1; gpu-canonical-store
//! 11-06 04:39): 색 편집's verbs — 색 변환, 픽셀 비우기, 2치화, 색 삭제,
//! 색 유지 — over a cel's stored tiles, as C's `qa_cel_pixel_pass_tile` and
//! the app's `overwriteCelPixels` run them, with no CPU copy of the law
//! (`kernels/mod.rs`); cel_pixel.wgsl has it.
//!
//! The walk is the cel's tiles row by row, those it has none of left out
//! and, under a selection, those past its mask's box: the app's
//! `celPixelWalkFor`. An undo replays its recipe by position, so the order
//! is the contract.
//!
//! A selection's mask rides in what a pass is given, copied there on the
//! GPU, not in a binding of its own: a device binds four storage buffers a
//! stage at fewest (GLES), and the pass's own three and one page are four.
//!
//! The walk is cut into passes by the pages' law (`shared::runs`), each a
//! run of it in order, so a pass binds its range of the new pixels and of
//! the runs, and is given its own part of the recipe and its own rows of
//! the mask: a binding holds 128 MB on some devices, and a big cel's walk
//! and its recipe hold more (브러시/렌더링 11-06 04:54).
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

use std::ops::Range;

use crate::device::Engine;
use crate::fail;
use crate::kernels::composite::{TILE, TILE_TEXELS, TileAt, TileSet};
use crate::kernels::effects::{KEY_WGSL, KeyRun};
use crate::kernels::mask::MaskBox;
use crate::kernels::shared::{
    Encoded, PREMULTIPLY_WGSL, Pages, TILE_WGSL, encode_on, fits, le_bytes, page_table, pipeline,
    plane, room, runs, whole, words_buffer,
};

/// The storage buffers a pass binds besides its pages: what it is given,
/// the new pixels, and the counts or the runs.
const OWN_BUFFERS: u32 = 3;
/// cel_pixel.wgsl's CEL_TILE_WORDS.
const TILE_WORDS: usize = 5;
/// A tile's new pixels, straight RGBA8.
const TILE_BYTES: u64 = TILE_TEXELS * 4;

/// The selection a pass walks: a byte plane (mask.wgsl's layout) over the
/// box `size` whose top-left pixel is `at` on the cel — the app's
/// `selectionMaskOnPasteboard`. A pass with none covers every pixel whole.
pub(crate) struct Mask<'a> {
    pub(crate) plane: &'a wgpu::Buffer,
    pub(crate) at: (i32, i32),
    pub(crate) size: MaskBox,
}

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

    /// A pass's incoming bytes, four a word, low first, and the walk index
    /// of the pixel its first is for: the value, or the recipe's entries of
    /// the pixels `touched` of the walk's — none before they are counted.
    fn incoming(&self, touched: Option<Range<u32>>) -> (u32, Vec<u32>) {
        let (first, bytes) = match (&self.incoming, touched) {
            (Incoming::Value(value), _) => (0, *value),
            (Incoming::Recipe { .. }, None) => (0, &[][..]),
            (Incoming::Recipe { bytes, step, .. }, Some(touched)) => {
                let step = *step as usize;
                let from = touched.start as usize * step;
                let to = match touched.is_empty() {
                    true => from,
                    false => (touched.end as usize - 1) * step + self.channel.bytes as usize,
                };
                (touched.start, &bytes[from..to])
            }
        };
        let words = bytes
            .chunks(4)
            .map(|four| four.iter().rev().fold(0, |word, &byte| word << 8 | u32::from(byte)))
            .collect();
        (first, words)
    }

    /// cel_pixel.wgsl's `CelPass` from `bytes` to `puts_runs`.
    fn words(&self) -> [u32; 10] {
        let Channel { bytes, base, stride, takes_empty } = self.channel;
        let step = match self.incoming {
            Incoming::Value(_) => 0,
            Incoming::Recipe { step, .. } => step,
        };
        [
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

/// A walked tile: where it is on the cel's grid, where it is stored, and
/// where its top-left pixel is in the mask's box — a word's two's
/// complement, as the shader adds a pixel to it (0 with no mask).
struct Walked {
    column: i32,
    row: i32,
    at: TileAt,
    in_mask: [u32; 2],
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
        let sources =
            [KEY_WGSL, TILE_WGSL, PREMULTIPLY_WGSL, &read, include_str!("cel_pixel.wgsl")];
        Some(Self {
            count: pipeline(engine, &sources, "cel_count"),
            apply: pipeline(engine, &sources, "cel_apply"),
            pages,
        })
    }

    /// Runs `verb` over `cel`, its tiles on the pool's `pool` pages, under
    /// `mask` or over every pixel; waits for the GPU twice — for the counts
    /// that place each tile's pixels and runs among the walk's, and for the
    /// runs.
    pub(crate) fn run(
        &self,
        engine: &Engine,
        pool: &[wgpu::Buffer],
        cel: &TileSet,
        mask: Option<&Mask>,
        verb: &Verb,
    ) -> Option<Passed> {
        let most = most(engine, mask, verb)?;
        self.run_by(engine, pool, cel, mask, verb, (self.pages.per_pass(), most))
    }

    /// `run`, its passes binding `per_pass` pages and taking `most` tiles at
    /// most — a smaller device's passes, which the tests take.
    fn run_by(
        &self,
        engine: &Engine,
        pool: &[wgpu::Buffer],
        cel: &TileSet,
        mask: Option<&Mask>,
        verb: &Verb,
        (per_pass, most): (usize, usize),
    ) -> Option<Passed> {
        if per_pass == 0 || per_pass > self.pages.per_pass() || most == 0 {
            return fail(format!(
                "{per_pass} pages and {most} tiles a pass; this device binds 1 to {} pages",
                self.pages.per_pass()
            ));
        }
        verb.checked()?;
        let walk = walk(cel, pool.len(), mask)?;
        let tiles: Vec<(i32, i32)> = walk.iter().map(|tile| (tile.column, tile.row)).collect();
        let out_bytes = (walk.len().max(1) as u64) * TILE_BYTES;
        made(engine, out_bytes)?;
        let out = plane(engine, "cel pixels out", out_bytes);
        if walk.is_empty() {
            return Some(Passed { tiles, out, touched: Vec::new(), runs: Vec::new() });
        }
        let cut = runs(walk.iter().map(|tile| tile.at.page), per_pass, most);
        let counts_bytes = walk.len() as u64 * 8;
        fits(engine, &[counts_bytes], std::iter::empty())?;
        let counts = plane(engine, "cel pixel counts", counts_bytes);
        let mut encoder = engine
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor::default());
        let given = Given::all(engine, &mut encoder, pool.len(), &walk, &cut, verb, mask, None)?;
        let counted: Vec<Encoded> = cut
            .iter()
            .zip(&given)
            .map(|(pass, given)| {
                let bound = [None, Some(counts.as_entire_binding())];
                self.encoded(&self.count, pool, pass, given, bound)
            })
            .collect();
        encode_on(engine, &mut encoder, &counted);
        engine.queue.submit([encoder.finish()]);
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
        let all_runs = u64::from(starts[walk.len()].1);
        // A pass's runs are bound from an offset a binding may start at, and
        // one with none still binds a word: the room past the last run.
        let put_bytes = if verb.is_undo() { 16 } else { all_runs * 8 + alignment(engine) };
        made(engine, put_bytes)?;
        let put = plane(engine, "cel pixel runs", put_bytes);
        let mut encoder = engine
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor::default());
        let given =
            Given::all(engine, &mut encoder, pool.len(), &walk, &cut, verb, mask, Some(&starts))?;
        let applied: Vec<Encoded> = cut
            .iter()
            .zip(&given)
            .map(|(pass, given)| {
                let (run, _) = pass;
                let out = range(&out, run.start as u64 * TILE_BYTES..run.end as u64 * TILE_BYTES);
                let put = match &given.runs {
                    Some(runs) => range(&put, runs.clone()),
                    None => put.as_entire_binding(),
                };
                self.encoded(&self.apply, pool, pass, given, [Some(out), Some(put)])
            })
            .collect();
        encode_on(engine, &mut encoder, &applied);
        engine.queue.submit([encoder.finish()]);
        if verb.is_undo() {
            engine.wait()?;
            return Some(Passed { tiles, out, touched, runs: Vec::new() });
        }
        let runs = lengths(&words(&engine.read_buffer(&put)?), &touched, &runs, &starts);
        Some(Passed { tiles, out, touched, runs })
    }

    /// `pipeline` over `pass`, given `given`, its tiles a workgroup each: the
    /// new pixels and the counts or runs bound at 2 and 3 as `bound` has
    /// them, and the pass's pages.
    fn encoded<'a>(
        &'a self,
        pipeline: &'a wgpu::ComputePipeline,
        pool: &'a [wgpu::Buffer],
        (run, pages): &Run,
        given: &'a Given,
        bound: [Option<wgpu::BindingResource<'a>>; 2],
    ) -> Encoded<'a> {
        let mut entries = whole(&[(0, &given.uniform), (1, &given.words)]);
        for (binding, resource) in (2..).zip(bound) {
            if let Some(resource) = resource {
                entries.push(wgpu::BindGroupEntry { binding, resource });
            }
        }
        entries.extend(self.pages.entries(pages.iter().map(|&page| &pool[usize::from(page)])));
        Encoded { pipeline, bound: entries, groups: (run.len() as u32, 1, 1) }
    }
}

/// The most walked tiles a pass takes on this device: as many as a dispatch
/// reaches and as a binding holds at a tile's worst — its new pixels, its
/// runs (a pixel's value and rank each), and in what it is given its entry,
/// its start, its recipe (a pixel's step each) and its rows of the mask.
fn most(engine: &Engine, mask: Option<&Mask>, verb: &Verb) -> Option<usize> {
    let step = match verb.incoming {
        Incoming::Recipe { step, .. } => u64::from(step),
        Incoming::Value(_) => 0,
    };
    let band = mask.map_or(0, |mask| u64::from(mask.size.stride()) * 4 * u64::from(TILE));
    let given = TILE_WORDS as u64 * 4 + 8 + step * TILE_TEXELS + band;
    let runs = if verb.is_undo() { 0 } else { TILE_TEXELS * 8 };
    let per_tile = TILE_BYTES.max(runs).max(given);
    // The selector's tables, the value or a recipe's last pixel, and the
    // runs' offset rounded down to where a binding may start.
    let tables = verb.selector.as_ref().map_or(0, |selector| selector.key.words().len());
    let fixed = (tables as u64 + 1) * 4 + alignment(engine);
    let reach = u64::from(engine.device.limits().max_compute_workgroups_per_dimension);
    let most = (room(engine).saturating_sub(fixed) / per_tile).min(reach);
    if most == 0 {
        return fail(format!("one tile's {per_tile} bytes exceed a binding"));
    }
    Some(most as usize)
}

/// Fails where this device makes no buffer of `bytes`: the new pixels and
/// the runs are one buffer each, bound a pass's range at a time.
fn made(engine: &Engine, bytes: u64) -> Option<()> {
    let largest = engine.device.limits().max_buffer_size;
    if bytes > largest {
        return fail(format!("{bytes} bytes exceed a buffer of {largest}"));
    }
    Some(())
}

/// Where a binding may start in a storage buffer, in bytes.
fn alignment(engine: &Engine) -> u64 {
    u64::from(engine.device.limits().min_storage_buffer_offset_alignment)
}

/// `bytes` of `buffer` as a binding.
fn range(buffer: &wgpu::Buffer, bytes: Range<u64>) -> wgpu::BindingResource<'_> {
    wgpu::BindingResource::Buffer(wgpu::BufferBinding {
        buffer,
        offset: bytes.start,
        size: wgpu::BufferSize::new(bytes.end - bytes.start),
    })
}

/// Where each walked tile's pixels and runs start among the walk's, from
/// how many of each it has, and past the last the walk's whole.
fn starts(touched: &[u32], runs: &[u32]) -> Vec<(u32, u32)> {
    let mut sum = (0, 0);
    let mut starts = Vec::with_capacity(touched.len() + 1);
    for (&touched, &runs) in touched.iter().zip(runs) {
        starts.push(sum);
        sum = (sum.0 + touched, sum.1 + runs);
    }
    starts.push(sum);
    starts
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

/// The walk: `cel`'s tiles row by row, those it has none of and — under
/// `mask` — those past its box left out, each on one of the pool's `pool`
/// pages.
fn walk(cel: &TileSet, pool: usize, mask: Option<&Mask>) -> Option<Vec<Walked>> {
    if cel.tiles.len() as u64 != u64::from(cel.columns) * u64::from(cel.rows) {
        return fail(format!(
            "{} tiles for a set of {} × {}",
            cel.tiles.len(),
            cel.columns,
            cel.rows
        ));
    }
    if let Some(mask) = mask
        && mask.plane.size() < mask.size.bytes()
    {
        return fail(format!("{:?} is no mask of {} bytes", mask.size, mask.plane.size()));
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
        let column = cel.x0 + (index % cel.columns) as i32;
        let row = cel.y0 + (index / cel.columns) as i32;
        let in_mask = match mask {
            None => [0, 0],
            Some(Mask { at: (left, top), size, .. }) => {
                match (within(column, *left, size.width), within(row, *top, size.height)) {
                    (Some(x), Some(y)) => [x, y],
                    _ => continue,
                }
            }
        };
        walk.push(Walked { column, row, at, in_mask });
    }
    Some(walk)
}

/// Where tile `tile`'s first pixel lies past pixel `from`, as a word's two's
/// complement — none where the tile's pixels miss `from`'s `length`.
fn within(tile: i32, from: i32, length: u32) -> Option<u32> {
    let first = i64::from(tile) * i64::from(TILE) - i64::from(from);
    (first < i64::from(length) && first + i64::from(TILE) > 0).then_some(first as u32)
}

/// A pass: its run of the walk, and the pages it binds — a page's k its
/// place among them ([`runs`]).
type Run = (Range<usize>, Vec<u16>);

/// The rows of `mask`'s box that `run`'s tiles lie on: from its first
/// tile's row to its last's, as the walk goes row by row.
fn band(walk: &[Walked], run: &Range<usize>, mask: &Mask) -> Range<u32> {
    let from = |row: i32| {
        let y = i64::from(row) * i64::from(TILE) - i64::from(mask.at.1);
        y.clamp(0, i64::from(mask.size.height)) as u32
    };
    from(walk[run.start].row)..from(walk[run.end - 1].row + 1)
}

/// What a pass is given — its tiles, the selector's key run, its incoming
/// bytes, where its tiles' pixels and runs start among the walk's and its
/// rows of the mask —, its `CelPass`, and where its runs go in what the
/// apply entry puts.
struct Given {
    words: wgpu::Buffer,
    uniform: wgpu::Buffer,
    runs: Option<Range<u64>>,
}

impl Given {
    /// Each pass of `cut` over `walk` — its tiles on the pool's `pool`
    /// pages — under `mask`; the apply entry's, with `starts`, the count
    /// entry's without. The copies of the mask's rows are encoded on
    /// `encoder`, before the passes that read them.
    fn all(
        engine: &Engine,
        encoder: &mut wgpu::CommandEncoder,
        pool: usize,
        walk: &[Walked],
        cut: &[Run],
        verb: &Verb,
        mask: Option<&Mask>,
        starts: Option<&[(u32, u32)]>,
    ) -> Option<Vec<Given>> {
        cut.iter()
            .map(|pass| Given::of(engine, encoder, pool, walk, pass, verb, mask, starts))
            .collect()
    }

    /// `pass`'s, the copy of its rows of the mask encoded on `encoder`.
    fn of(
        engine: &Engine,
        encoder: &mut wgpu::CommandEncoder,
        pool: usize,
        walk: &[Walked],
        (run, pages): &Run,
        verb: &Verb,
        mask: Option<&Mask>,
        starts: Option<&[(u32, u32)]>,
    ) -> Option<Given> {
        let rows = mask.map_or(0..0, |mask| band(walk, run, mask));
        let table: Vec<u32> = page_table(pages, pool).collect();
        let mut words: Vec<u32> = Vec::with_capacity(run.len() * (TILE_WORDS + 2));
        for (index, tile) in walk.iter().enumerate().take(run.end).skip(run.start) {
            let k = table[usize::from(tile.at.page)];
            let [x, y] = tile.in_mask;
            let slot = u32::from(tile.at.slot);
            let entry: [u32; TILE_WORDS] = [k, slot, index as u32, x, y.wrapping_sub(rows.start)];
            words.extend(entry);
        }
        let tables_at = words.len() as u32;
        if let Some(selector) = &verb.selector {
            words.extend(selector.key.words());
        }
        let incoming_at = words.len() as u32;
        let touched = starts.map(|starts| starts[run.start].0..starts[run.end].0);
        let (touched_first, incoming) = verb.incoming(touched);
        words.extend(incoming);
        let starts_at = words.len() as u32;
        if let Some(starts) = starts {
            words.extend(starts[run.clone()].iter().flat_map(|&(touched, runs)| [touched, runs]));
        }
        let mask_at = words.len() as u32;
        let (stride, band) = mask.map_or((0, 0), |mask| {
            let stride = u64::from(mask.size.stride()) * 4;
            (stride, u64::from(rows.end - rows.start) * stride)
        });
        let size = u64::from(mask_at) * 4 + band;
        fits(engine, &[size], std::iter::empty())?;
        let given = engine.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("cel pixels given"),
            size,
            usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });
        engine.queue.write_buffer(&given, 0, &le_bytes(&words));
        if let Some(mask) = mask {
            let from = u64::from(rows.start) * stride;
            encoder.copy_buffer_to_buffer(mask.plane, from, &given, size - band, band);
        }
        // Going forward, the pass's runs from where a binding may start.
        let runs = starts.filter(|_| !verb.is_undo()).map(|starts| {
            let align = alignment(engine);
            let first = u64::from(starts[run.start].1) * 8 / align * align;
            first..(u64::from(starts[run.end].1) * 8).max(first + 8)
        });
        let shape = mask.map_or([0; 4], |Mask { size, .. }| {
            [1, size.width, rows.end - rows.start, size.stride()]
        });
        let mut uniform = vec![tables_at, incoming_at, starts_at, mask_at, run.start as u32];
        uniform.push(touched_first);
        uniform.push(runs.as_ref().map_or(0, |runs| (runs.start / 4) as u32));
        uniform.extend(verb.words());
        uniform.extend(shape);
        Some(Given {
            words: given,
            uniform: words_buffer(engine, "cel pass", &uniform, wgpu::BufferUsages::UNIFORM),
            runs,
        })
    }
}

fn words(bytes: &[u8]) -> Vec<u32> {
    bytes
        .chunks_exact(4)
        .map(|four| u32::from_le_bytes([four[0], four[1], four[2], four[3]]))
        .collect()
}
