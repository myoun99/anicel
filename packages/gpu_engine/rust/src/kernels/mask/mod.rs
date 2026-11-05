//! A coverage mask's finishing passes on the GPU, by gpu-int-spec-canvas
//! 1b S2, with no CPU copy of a formula (`kernels/mod.rs`): what the
//! selection does to its hard mask before a verb reads it — grow or shrink
//! (S2a, the app's `dilateMask4` · `erodeMask4`), feather (S2b, its
//! `chamferDistance34` and `_featherMask`'s ramp) and anti-alias inside the
//! outline (S2c, `softenMaskBoundary`), in `buildSelectionMask`'s order.
//! The hard mask itself is `region`'s (S1, the app's `maskFor`).
//!
//! A mask is a plane of bytes over its box (`MaskBox`) — the app's
//! `Uint8List` as it is, padded to whole words; mask.wgsl's head has the
//! layout.

// ⏳Nothing outside the tests reads a mask until the canvas's verbs come to
// the engine (gpu-canonical-store, stage 4).
#![cfg_attr(not(test), allow(dead_code))]

pub(crate) mod region;
#[cfg(test)]
pub(crate) mod tests;

use std::ops::Range;

use crate::device::Engine;
use crate::fail;
use crate::kernels::composite::TILE;
use crate::kernels::shared::{
    Encoded, WIDE_WGSL, encode, fits, flat, pipeline, plane, q, whole, words_buffer,
};

/// `mask_byte_of` — a mask's byte at a pixel of its box, as every reader of
/// a selection reads it; its host defines `mask_word`.
pub(crate) const BYTE_WGSL: &str = include_str!("byte.wgsl");

/// mask.wgsl's workgroup side.
const GROUP: u32 = 8;
/// The feather a mask takes is under this, in pixels: its ramp, 3 · Q.8,
/// is a word.
const MOST_FEATHER: f64 = (u32::MAX / 3 / 256) as f64;

/// A mask's box: its pixels across and down.
#[derive(Clone, Copy, Debug)]
pub(crate) struct MaskBox {
    pub(crate) width: u32,
    pub(crate) height: u32,
}

impl MaskBox {
    /// A row's words of bytes.
    pub(crate) fn stride(&self) -> u32 {
        self.width.div_ceil(4)
    }

    /// The plane's bytes: its rows of words.
    pub(crate) fn bytes(&self) -> u64 {
        u64::from(self.stride()) * u64::from(self.height) * 4
    }

    /// A distance plane's bytes: two distances to a word.
    fn distance_bytes(&self) -> u64 {
        u64::from(self.width.div_ceil(2)) * u64::from(self.height) * 4
    }

    /// A pass's workgroups over words of `per` pixels.
    fn groups(&self, per: u32) -> (u32, u32) {
        (self.width.div_ceil(per).div_ceil(GROUP), self.height.div_ceil(GROUP))
    }
}

/// A selection as a pass reads it: a byte plane (mask.wgsl's layout) over
/// the box `size` whose top-left pixel is `at` on the canvas — the app's
/// `selectionMaskOnPasteboard`. A pass is given the rows of it it reads,
/// copied on the GPU. ⛔ONE MASK: the cel pixel verbs and the lift took it
/// from here, and the executor's masked rows came as a third (11-06).
pub(crate) struct Mask<'a> {
    pub(crate) plane: &'a wgpu::Buffer,
    pub(crate) at: (i32, i32),
    pub(crate) size: MaskBox,
}

impl Mask<'_> {
    /// Fails where the plane holds less than its box.
    pub(crate) fn checked(&self) -> Option<()> {
        if self.plane.size() < self.size.bytes() {
            return fail(format!("{:?} is no mask of {} bytes", self.size, self.plane.size()));
        }
        Some(())
    }

    /// The rows of its box that tiles on the canvas's tile `rows` lie on,
    /// from the lowest of them to the highest — what a pass over those
    /// tiles is given of it. ⛔ONE BAND: the cel pixel verbs and the
    /// executor's masked rows took theirs from here, and the blur's finish
    /// came as a third (11-06).
    pub(crate) fn band(&self, rows: impl Iterator<Item = i32>) -> Range<u32> {
        let (low, high) = rows.fold((i32::MAX, i32::MIN), |(low, high), row| {
            (low.min(row), high.max(row))
        });
        if low > high {
            return 0..0;
        }
        let side = i64::from(TILE);
        let box_row = |row: i32| {
            let y = i64::from(row) * side - i64::from(self.at.1);
            y.clamp(0, i64::from(self.size.height)) as u32
        };
        box_row(low)..box_row(high + 1)
    }

    /// The most bytes of its plane a pass is given for each tile it may
    /// take: a tile's rows across the box's whole width, as `runs` reaches
    /// no more tile rows than tiles. ⛔ONE BUDGET: the executor, the cel
    /// pixel verbs and the blur's finish each held a copy (11-06).
    pub(crate) fn per_tile(&self) -> u64 {
        u64::from(self.size.stride()) * 4 * u64::from(TILE)
    }

    /// The bytes of the box's `rows` in its plane, as a pass is given them.
    pub(crate) fn rows(&self, rows: &Range<u32>) -> (&wgpu::Buffer, Range<u64>) {
        let stride = u64::from(self.size.stride()) * 4;
        (self.plane, u64::from(rows.start) * stride..u64::from(rows.end) * stride)
    }
}

/// The selection tool's mask knobs — the app's `SelectionMaskOptions`: a
/// grow (> 0) or shrink (< 0) in pixels, a feather in pixels (none at 0 or
/// less) and whether it anti-aliases.
#[derive(Clone, Copy, Debug)]
pub(crate) struct Finish {
    pub(crate) grow: i32,
    pub(crate) feather: f64,
    pub(crate) anti_alias: bool,
}

impl Finish {
    /// Whether it leaves the hard mask as it is — the app's `isHard`, where
    /// no pass runs.
    pub(crate) fn is_hard(&self) -> bool {
        self.grow == 0 && self.feather <= 0.0 && !self.anti_alias
    }
}

/// A pass: a stencil of a pixel's sides on the bytes, a distance's start
/// or generation, or the feather's ramp over the distances.
#[derive(Clone, Copy, PartialEq)]
enum Step {
    Grow,
    Shrink,
    Soften,
    Seed,
    Relax,
    Feather,
}

impl Step {
    /// The pixels a thread puts: four bytes, or two distances.
    fn per_word(self) -> u32 {
        match self {
            Step::Seed | Step::Relax => 2,
            Step::Grow | Step::Shrink | Step::Soften | Step::Feather => 4,
        }
    }
}

/// The passes, compiled once.
pub(crate) struct MaskPasses {
    grow: wgpu::ComputePipeline,
    shrink: wgpu::ComputePipeline,
    soften: wgpu::ComputePipeline,
    seed: wgpu::ComputePipeline,
    relax: wgpu::ComputePipeline,
    feather: wgpu::ComputePipeline,
}

impl MaskPasses {
    pub(crate) fn new(engine: &Engine) -> Self {
        let source = [WIDE_WGSL, BYTE_WGSL, include_str!("mask.wgsl")];
        let compile = |entry| pipeline(engine, &source, entry);
        Self {
            grow: compile("mask_grow"),
            shrink: compile("mask_shrink"),
            soften: compile("mask_soften"),
            seed: compile("mask_seed"),
            relax: compile("mask_relax"),
            feather: compile("mask_feather"),
        }
    }

    /// `mask` — bytes over `size` — finished as the selection finishes its
    /// hard mask (`buildSelectionMask`): grown or shrunk a generation a
    /// pixel, feathered inward over its edge, then softened inside its
    /// outline. A new plane — or none for a `finish` that `is_hard`, whose
    /// mask is finished as it is. Submits the work; the caller waits.
    pub(crate) fn selection(
        &self,
        engine: &Engine,
        mask: &wgpu::Buffer,
        size: MaskBox,
        finish: Finish,
    ) -> Option<wgpu::Buffer> {
        if size.width == 0 || size.height == 0 || mask.size() < size.bytes() {
            return fail(format!("{size:?} is no mask of {} bytes", mask.size()));
        }
        // In Q.8 pixels.
        let feather = match finish.feather {
            px if px > 0.0 => match q(px, 8, MOST_FEATHER * 256.0) {
                Some(feather) => Some(feather as u32),
                None => return fail(format!("a feather of {px} pixels is past {MOST_FEATHER}")),
            },
            px if px.is_nan() => return fail("a feather of NaN pixels"),
            _ => None,
        };
        if finish.is_hard() {
            return fail("a hard mask has no pass to run: it is finished as it is");
        }
        let way = if finish.grow > 0 { Step::Grow } else { Step::Shrink };
        let mut steps = vec![way; finish.grow.unsigned_abs() as usize];
        if let Some(feather) = feather {
            // A pixel the ramp does not make whole lies under feather / 256
            // pixels from where its distance starts, a pixel nearer each
            // generation: ⌈feather / 256⌉ − 1 settle every one of them, and
            // the rest stay at or past the ramp. And a distance travels no
            // more pixels than the box's longer side, so past that many
            // generations every one has settled, however wide the feather.
            let generations = feather.div_ceil(256).saturating_sub(1);
            let generations = generations.min(size.width.max(size.height));
            steps.push(Step::Seed);
            steps.extend((0..generations).map(|_| Step::Relax));
            steps.push(Step::Feather);
        }
        if finish.anti_alias {
            steps.push(Step::Soften);
        }
        let ramp = feather.map_or(0, |feather| 3 * feather);
        self.run(engine, mask, size, &steps, ramp)
    }

    /// Runs `steps` over `mask` in order, each reading what the one before
    /// put — the feather's over `ramp` —, and returns the bytes the last
    /// byte pass put; `steps` holds one.
    fn run(
        &self,
        engine: &Engine,
        mask: &wgpu::Buffer,
        size: MaskBox,
        steps: &[Step],
        ramp: u32,
    ) -> Option<wgpu::Buffer> {
        let feathers = steps.contains(&Step::Seed);
        let distance_bytes = if feathers { size.distance_bytes() } else { 0 };
        let groups = steps.iter().map(|step| size.groups(step.per_word()));
        fits(engine, &[size.bytes(), distance_bytes], groups)?;
        let bytes = [0, 1].map(|_| plane(engine, "mask", size.bytes()));
        let distances: Vec<wgpu::Buffer> = (0..if feathers { 2 } else { 0 })
            .map(|_| plane(engine, "mask distances", distance_bytes))
            .collect();
        let words = [size.width, size.height, size.stride(), ramp];
        let words = &words_buffer(engine, "mask", &words, wgpu::BufferUsages::UNIFORM);
        // The byte plane the next pass reads — none: `mask` itself — and
        // the distance plane.
        let (mut bytes_at, mut distances_at) = (None, 0);
        let mut encoded = Vec::with_capacity(steps.len());
        for &step in steps {
            let from = bytes_at.map_or(mask, |at: usize| &bytes[at]);
            let to = bytes_at.map_or(0, |at| 1 - at);
            let (pipeline, bound) = match step {
                Step::Grow | Step::Shrink | Step::Soften => {
                    bytes_at = Some(to);
                    let pipeline = match step {
                        Step::Grow => &self.grow,
                        Step::Shrink => &self.shrink,
                        _ => &self.soften,
                    };
                    (pipeline, vec![(0, words), (1, from), (2, &bytes[to])])
                }
                Step::Seed => {
                    let bound = vec![(0, words), (1, from), (4, &distances[distances_at])];
                    (&self.seed, bound)
                }
                Step::Relax => {
                    let (read, put) = (distances_at, 1 - distances_at);
                    distances_at = put;
                    let bound = vec![(0, words), (3, &distances[read]), (4, &distances[put])];
                    (&self.relax, bound)
                }
                Step::Feather => {
                    bytes_at = Some(to);
                    let distances = &distances[distances_at];
                    let bound = vec![(0, words), (1, from), (2, &bytes[to]), (3, distances)];
                    (&self.feather, bound)
                }
            };
            encoded.push(Encoded {
                pipeline,
                bound: whole(&bound),
                groups: flat(size.groups(step.per_word())),
            });
        }
        encode(engine, &encoded);
        let [first, second] = bytes;
        Some(if bytes_at == Some(1) { second } else { first })
    }
}
