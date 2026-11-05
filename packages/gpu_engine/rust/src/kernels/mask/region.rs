//! A selection's hard mask on the GPU, by gpu-int-spec-canvas 1b S1 with no
//! CPU copy of a formula (`kernels/mod.rs`): the app's
//! `CanvasSelectionRegion.maskFor` — 255 where a pixel's centre is in the
//! selection, 0 elsewhere — from its steps as the app holds them, each
//! point put in Q.8, the one value the spec changes. region.wgsl's head has
//! how a polygon is laid.

#[cfg(test)]
#[path = "region_tests.rs"]
mod tests;

use super::MaskBox;
use crate::device::Engine;
use crate::fail;
use crate::kernels::shared::{
    Encoded, WIDE_WGSL, encode, fits, flat, pipeline, plane, q, whole, words_buffer,
};

/// region.wgsl's workgroup side, and its scan's rows a workgroup.
const GROUP: u32 = 8;
const ROWS: u32 = 64;
/// How far from the canvas's origin a point and the box reach, in pixels:
/// in Q.8 an i32 with room for the crossing's sums (1b S1).
const REACH: i64 = 1 << 15;
/// The bit plane every act's polygons are joined in before it folds.
const UNION: usize = 0;

/// How a step folds into what the steps before it selected — the app's
/// `SelectionCombineMode`, by its one table (`_fold`); each value is
/// region.wgsl's `op`.
#[derive(Clone, Copy, Debug)]
pub(crate) enum Combine {
    Replace = 0,
    Add = 1,
    Subtract = 2,
    Intersect = 3,
}

/// What a step folds in: the polygons one act drew, as their union — the
/// app's `CanvasSelectionCopies`, each a ring of canvas points (x, y) —, or
/// a whole selection (`CanvasSelectionNested`).
pub(crate) enum Operand {
    Copies(Vec<Vec<[f64; 2]>>),
    Region(Vec<Step>),
}

/// One step of a selection — the app's `CanvasSelectionStep`.
pub(crate) struct Step {
    pub(crate) combine: Combine,
    pub(crate) operand: Operand,
}

/// A pass over the bit planes: plane `UNION`, then one a nesting level.
#[derive(Clone, Copy)]
enum Pass {
    Clear { plane: usize },
    Toggle { first: u32, count: u32 },
    Scan { plane: usize },
    Fold { combine: Combine, into: usize, operand: usize },
}

/// The passes, compiled once.
pub(crate) struct RegionMask {
    toggle: wgpu::ComputePipeline,
    scan: wgpu::ComputePipeline,
    clear: wgpu::ComputePipeline,
    fold: wgpu::ComputePipeline,
    bytes: wgpu::ComputePipeline,
}

impl RegionMask {
    pub(crate) fn new(engine: &Engine) -> Self {
        let source = [WIDE_WGSL, include_str!("region.wgsl")];
        let compile = |entry| pipeline(engine, &source, entry);
        Self {
            toggle: compile("region_toggle"),
            scan: compile("region_scan"),
            clear: compile("region_clear"),
            fold: compile("region_fold"),
            bytes: compile("region_bytes"),
        }
    }

    /// The hard mask of the selection `steps` over the pixel box `size`
    /// whose top-left pixel is (`left`, `top`) on the canvas — the app's
    /// `maskFor` — as a new byte plane (mask.wgsl's layout), or none when
    /// the box or a point is past the reach. Submits the work; the caller
    /// waits.
    pub(crate) fn selection(
        &self,
        engine: &Engine,
        steps: &[Step],
        (left, top): (i32, i32),
        size: MaskBox,
    ) -> Option<wgpu::Buffer> {
        let spans = |from: i32, length: u32| {
            length > 0
                && -REACH <= i64::from(from)
                && i64::from(from) + i64::from(length) <= REACH
        };
        if !spans(left, size.width) || !spans(top, size.height) {
            return fail(format!("({left}, {top}) {size:?} is no box within the canvas's reach"));
        }
        let mut vertices = Vec::new();
        let mut passes = Vec::new();
        let deepest = laid(steps, 1, &mut vertices, &mut passes)?;
        self.run(engine, (left, top), size, &vertices, &passes, deepest + 1)
    }

    /// Runs `passes` over `planes` bit planes, then puts the selection —
    /// plane 1 — as bytes.
    fn run(
        &self,
        engine: &Engine,
        (left, top): (i32, i32),
        size: MaskBox,
        vertices: &[u32],
        passes: &[Pass],
        planes: usize,
    ) -> Option<wgpu::Buffer> {
        let stride = size.width / 32 + 1;
        let bits = u64::from(stride) * u64::from(size.height) * 4;
        let words_across = stride.div_ceil(GROUP);
        let down = size.height.div_ceil(GROUP);
        let groups = |pass: &Pass| match *pass {
            Pass::Toggle { count, .. } => (count.div_ceil(GROUP), down),
            Pass::Scan { .. } => (size.height.div_ceil(ROWS), 1),
            Pass::Clear { .. } | Pass::Fold { .. } => (words_across, down),
        };
        let out = (size.width.div_ceil(4).div_ceil(GROUP), down);
        let all = passes.iter().map(groups).chain([out]);
        let vertex_bytes = vertices.len() as u64 * 4;
        fits(engine, &[bits, vertex_bytes, size.bytes()], all)?;
        let planes: Vec<wgpu::Buffer> =
            (0..planes).map(|_| plane(engine, "region", bits)).collect();
        let toggles = plane(engine, "region toggles", bits);
        // A pass binds a whole buffer: a selection of no polygon still has
        // a vertex.
        let storage = wgpu::BufferUsages::STORAGE;
        let vertices = match vertices {
            [] => words_buffer(engine, "region vertices", &[0, 0], storage),
            _ => words_buffer(engine, "region vertices", vertices, storage),
        };
        let bytes = plane(engine, "region mask", size.bytes());
        let uniform = |first: u32, count: u32, op: u32| {
            let words = [
                left as u32,
                top as u32,
                size.width,
                size.height,
                stride,
                first,
                count,
                op,
            ];
            words_buffer(engine, "region pass", &words, wgpu::BufferUsages::UNIFORM)
        };
        let words: Vec<wgpu::Buffer> = passes
            .iter()
            .map(|pass| match *pass {
                Pass::Toggle { first, count } => uniform(first, count, 0),
                Pass::Fold { combine, .. } => uniform(0, 0, combine as u32),
                Pass::Clear { .. } | Pass::Scan { .. } => uniform(0, 0, 0),
            })
            .chain([uniform(0, 0, 0)])
            .collect();
        let mut encoded: Vec<Encoded> = passes
            .iter()
            .zip(&words)
            .map(|(pass, words)| {
                let (pipeline, bound) = match *pass {
                    Pass::Toggle { .. } => {
                        (&self.toggle, vec![(0, words), (1, &vertices), (2, &toggles)])
                    }
                    Pass::Scan { plane } => {
                        (&self.scan, vec![(0, words), (2, &toggles), (3, &planes[plane])])
                    }
                    Pass::Clear { plane } => (&self.clear, vec![(0, words), (3, &planes[plane])]),
                    Pass::Fold { into, operand, .. } => {
                        let bound = vec![(0, words), (3, &planes[into]), (4, &planes[operand])];
                        (&self.fold, bound)
                    }
                };
                Encoded {
                    pipeline,
                    bound: whole(&bound),
                    groups: flat(groups(pass)),
                }
            })
            .collect();
        encoded.push(Encoded {
            pipeline: &self.bytes,
            bound: whole(&[(0, &words[passes.len()]), (4, &planes[1]), (5, &bytes)]),
            groups: flat(out),
        });
        encode(engine, &encoded);
        Some(bytes)
    }
}

/// The passes that fold `steps` into bit plane `into`, from nothing — as
/// `containsPoint` folds from outside —, each act's polygons joined in
/// plane `UNION` and a nested selection folded first in the plane after
/// `into`; each point joins `vertices` as Q.8 x and y. The deepest plane
/// they use, or none for a point past the reach.
fn laid(
    steps: &[Step],
    into: usize,
    vertices: &mut Vec<u32>,
    passes: &mut Vec<Pass>,
) -> Option<usize> {
    let mut deepest = into;
    passes.push(Pass::Clear { plane: into });
    for step in steps {
        let operand = match &step.operand {
            Operand::Copies(polygons) => {
                passes.push(Pass::Clear { plane: UNION });
                for polygon in polygons {
                    let first = (vertices.len() / 2) as u32;
                    for &point in polygon {
                        for value in point {
                            vertices.push(quantized(value)? as u32);
                        }
                    }
                    let count = polygon.len() as u32;
                    passes.push(Pass::Toggle { first, count });
                    passes.push(Pass::Scan { plane: UNION });
                }
                UNION
            }
            Operand::Region(inner) => {
                deepest = deepest.max(laid(inner, into + 1, vertices, passes)?);
                into + 1
            }
        };
        passes.push(Pass::Fold {
            combine: step.combine,
            into,
            operand,
        });
    }
    Some(deepest)
}

/// A canvas coordinate in Q.8, or none past the reach.
fn quantized(value: f64) -> Option<i32> {
    match q(value, 8, (REACH << 8) as f64) {
        Some(value) => Some(value as i32),
        None => fail(format!("a point at {value} is past the canvas's reach of {REACH}")),
    }
}
