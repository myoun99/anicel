//! A coverage mask's finishing passes on the GPU, by gpu-int-spec-canvas
//! 1b S2, with no CPU copy of a formula (`kernels/mod.rs`): what the
//! selection does to its hard mask before a verb reads it — grow or shrink
//! (S2a, the app's `dilateMask4` · `erodeMask4`), feather (S2b, its
//! `chamferDistance34` and `_featherMask`'s ramp) and anti-alias inside the
//! outline (S2c, `softenMaskBoundary`), in `buildSelectionMask`'s order.
//! The hard mask itself is `region`'s (S1, the app's `maskFor`). A bucket
//! fill finishes what it flooded with the same grow and soften
//! (gpu-canonical-store stage 5), its soften past the outline as well, and
//! its gap close measures by the feather's distances.
//!
//! A mask is a plane of bytes over its box (`MaskBox`) — the app's
//! `Uint8List` as it is, padded to whole words; mask.wgsl's head has the
//! layout.

// ⏳Nothing outside the tests runs the selection's passes or makes its hard
// mask until the canvas's verbs come to the engine (gpu-canonical-store,
// stage 4): the fill finishes and closes gaps by its own two
// (`kernels/flood/abi.rs`), and the executor reads the fill range's (flip
// lane ⓐ-3).
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
/// The distance the box's edge lies at in the selection's feather — a
/// pixel on it ramps as if the one past it were out (`_featherMask`'s
/// `borderDistance`) — and in the fill's gap close, where the canvas edge
/// is no barrier: none, which no distance passes.
const SELECTION_EDGE: u32 = 3;
const NO_EDGE: u32 = u32::MAX;

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

    /// `bytes` — a byte a pixel, row after row, the app's `Uint8List` as it
    /// is — as the plane holds them: each row padded to whole words with 0.
    pub(crate) fn words_of(&self, bytes: &[u8]) -> Vec<u32> {
        let word = |four: &[u8]| {
            let mut word = [0; 4];
            word[..four.len()].copy_from_slice(four);
            u32::from_le_bytes(word)
        };
        bytes.chunks_exact(self.width as usize).flat_map(|row| row.chunks(4).map(word)).collect()
    }

    /// `plane` — the plane's bytes as a pass put them — row after row
    /// without the padding: the app's `Uint8List` again
    /// ([`Self::words_of`], back).
    pub(crate) fn rows_of<'a>(&self, plane: &'a [u8]) -> impl Iterator<Item = &'a [u8]> {
        let (stride, width) = (self.stride() as usize * 4, self.width as usize);
        plane.chunks_exact(stride).take(self.height as usize).map(move |row| &row[..width])
    }

    /// A distance plane's bytes: two distances to a word.
    fn distance_bytes(&self) -> u64 {
        u64::from(self.width.div_ceil(2)) * u64::from(self.height) * 4
    }

    /// A pass's workgroups over words of `per` pixels.
    fn groups(&self, per: u32) -> (u32, u32) {
        (self.width.div_ceil(per).div_ceil(GROUP), self.height.div_ceil(GROUP))
    }

    /// Fails unless it holds a pixel and `mask` holds its plane.
    fn held_by(&self, mask: &wgpu::Buffer) -> Option<()> {
        if self.width == 0 || self.height == 0 || mask.size() < self.bytes() {
            return fail(format!("{self:?} is no mask of {} bytes", mask.size()));
        }
        Some(())
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
        // An empty run's band, which would otherwise run backward. No run
        // is empty, so no test here reaches this (mutant v24, 11-06).
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

/// What a run's passes read past the box — the app's arguments to the
/// functions they are: the feather's ramp, 3 chamfer units a pixel, Q.8,
/// softenMaskBoundary's `insideOutlineOnly`, and chamferDistance34's
/// `zeroWhen` and `borderDistance`.
#[derive(Clone, Copy)]
struct Knobs {
    ramp: u32,
    inside_outline_only: bool,
    zero_when: u8,
    border: u32,
}

/// What a run put last: its bytes, and its distances where it measured.
struct Put {
    bytes: Option<wgpu::Buffer>,
    distances: Option<wgpu::Buffer>,
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
        size.held_by(mask)?;
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
        let knobs = Knobs {
            ramp: feather.map_or(0, |feather| 3 * feather),
            inside_outline_only: true,
            zero_when: 0,
            border: SELECTION_EDGE,
        };
        self.run(engine, mask, size, &steps, knobs)?.bytes
    }

    /// `mask` — bytes over `size`, 255 where a fill flooded — finished as
    /// the fill finishes it: grown `expand`
    /// generations, then, where it anti-aliases, softened past its outline
    /// as well as in. A new plane — or none where neither runs, whose mask
    /// is finished as it is. Submits the work; the caller waits.
    pub(crate) fn fill(
        &self,
        engine: &Engine,
        mask: &wgpu::Buffer,
        size: MaskBox,
        expand: u32,
        anti_alias: bool,
    ) -> Option<wgpu::Buffer> {
        size.held_by(mask)?;
        let mut steps = vec![Step::Grow; expand as usize];
        if anti_alias {
            steps.push(Step::Soften);
        }
        if steps.is_empty() {
            return fail("a fill neither expanded nor anti-aliased is finished as it is");
        }
        let knobs = Knobs {
            ramp: 0,
            inside_outline_only: false,
            zero_when: 0,
            border: NO_EDGE,
        };
        self.run(engine, mask, size, &steps, knobs)?.bytes
    }

    /// The 3-4 chamfer distance (`chamferDistance34`, in mask.wgsl's layout)
    /// from every pixel of `mask` — bytes over `size` — to the nearest whose
    /// byte is `zero_when`, as the fill's gap close measures it: the box's
    /// edge is no barrier. Relaxed
    /// `generations` times: a distance a path of no more steps reaches —
    /// every one up to 3 × `generations`, a step being 3 or 4 — is the
    /// app's, and the rest lie no nearer than theirs. Submits the work; the
    /// caller waits.
    pub(crate) fn distances(
        &self,
        engine: &Engine,
        mask: &wgpu::Buffer,
        size: MaskBox,
        zero_when: u8,
        generations: u32,
    ) -> Option<wgpu::Buffer> {
        size.held_by(mask)?;
        // A distance travels no more pixels than the box's longer side
        // (the feather's bound, in `selection`).
        let generations = generations.min(size.width.max(size.height));
        let mut steps = vec![Step::Seed];
        steps.extend((0..generations).map(|_| Step::Relax));
        let knobs = Knobs {
            ramp: 0,
            inside_outline_only: false,
            zero_when,
            border: NO_EDGE,
        };
        self.run(engine, mask, size, &steps, knobs)?.distances
    }

    /// Runs `steps` over `mask` in order, each reading what the one before
    /// put and all reading `knobs`, and returns what the last byte pass and
    /// the last distance pass put.
    fn run(
        &self,
        engine: &Engine,
        mask: &wgpu::Buffer,
        size: MaskBox,
        steps: &[Step],
        knobs: Knobs,
    ) -> Option<Put> {
        let puts_bytes = steps.iter().any(|step| step.per_word() == 4);
        let measures = steps.contains(&Step::Seed);
        let byte_bytes = if puts_bytes { size.bytes() } else { 0 };
        let distance_bytes = if measures { size.distance_bytes() } else { 0 };
        let groups = steps.iter().map(|step| size.groups(step.per_word()));
        fits(engine, &[byte_bytes, distance_bytes], groups)?;
        let bytes: Vec<wgpu::Buffer> = (0..if puts_bytes { 2 } else { 0 })
            .map(|_| plane(engine, "mask", byte_bytes))
            .collect();
        let distances: Vec<wgpu::Buffer> = (0..if measures { 2 } else { 0 })
            .map(|_| plane(engine, "mask distances", distance_bytes))
            .collect();
        let inside = u32::from(knobs.inside_outline_only);
        let zero_when = u32::from(knobs.zero_when);
        let words = [
            size.width,
            size.height,
            size.stride(),
            knobs.ramp,
            inside,
            zero_when,
            knobs.border,
            0,
        ];
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
        Some(Put {
            bytes: bytes_at.and_then(|at| bytes.into_iter().nth(at)),
            distances: distances.into_iter().nth(distances_at),
        })
    }
}
