//! A selection's hard mask on the GPU, by gpu-int-spec-canvas 1b S1 with no
//! CPU copy of a formula (`kernels/mod.rs`): the app's
//! `CanvasSelectionRegion.maskFor` — 255 where a pixel's centre is in the
//! selection, 0 elsewhere — from its steps as the app holds them, each
//! point put in Q.8, the one value the spec changes. region.wgsl's head has
//! how a polygon is laid.

#[cfg(test)]
#[path = "region_tests.rs"]
mod tests;

use std::sync::{Mutex, PoisonError};

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
    Scan { plane: usize, combine: Combine },
    Fold { combine: Combine, into: usize, operand: usize },
}

impl Pass {
    /// Whether the pass reads or writes plane `UNION`.
    fn joins(&self) -> bool {
        match *self {
            Pass::Clear { plane } | Pass::Scan { plane, .. } => plane == UNION,
            Pass::Fold { operand, .. } => operand == UNION,
            Pass::Toggle { .. } => false,
        }
    }
}

/// The passes, compiled once, and the bit planes they work in ([`Kept`]).
pub(crate) struct RegionMask {
    toggle: wgpu::ComputePipeline,
    scan: wgpu::ComputePipeline,
    clear: wgpu::ComputePipeline,
    fold: wgpu::ComputePipeline,
    bytes: wgpu::ComputePipeline,
    kept: Kept,
}

/// The bit planes a fold works in, kept from one fold to the next: a fold
/// takes the kept ones that hold what it needs, makes the rest, and gives
/// them back once the last of its passes that reads them is submitted —
/// whatever takes them next is submitted after, so the GPU runs it after.
/// At most [`KEPT`] planes and the toggles stay.
///
/// ⚠️What a fold reads of a plane is only what it put there: a plane is
/// cleared or replaced whole before anything folds into it ([`laid`]) —
/// but the toggles are read as they were left, so they are kept apart, and
/// every scan leaves the words it read at nothing (region.wgsl).
///
/// ↩️Made for each fold and dropped with it till 2026-11-14 — and a new
/// plane is zeroed by wgpu before it is first used: a simple selection's
/// runs came slower than the CPU's fold (L2e, board
/// `a-selection-mask-is-built-on-the-cpu-at-every-move`).
#[derive(Default)]
struct Kept {
    planes: Mutex<Vec<wgpu::Buffer>>,
    toggles: Mutex<Option<wgpu::Buffer>>,
}

/// How many planes [`Kept`] holds between folds: what a selection with no
/// nesting but what replaces folds in, and its act of many polygons that
/// intersects, needs.
const KEPT: usize = 2;

impl Kept {
    /// A plane of `bits` bytes at least.
    fn plane(&self, engine: &Engine, bits: u64) -> wgpu::Buffer {
        let mut kept = self.planes.lock().unwrap_or_else(PoisonError::into_inner);
        match kept.iter().position(|plane| plane.size() >= bits) {
            Some(at) => kept.swap_remove(at),
            None => plane(engine, "region", bits),
        }
    }

    /// Toggles of `bits` bytes at least, every word nothing.
    fn toggles(&self, engine: &Engine, bits: u64) -> wgpu::Buffer {
        let mut kept = self.toggles.lock().unwrap_or_else(PoisonError::into_inner);
        match kept.take().filter(|toggles| toggles.size() >= bits) {
            Some(toggles) => toggles,
            None => plane(engine, "region toggles", bits),
        }
    }

    /// `planes` given back: the biggest [`KEPT`] of them and the kept stay.
    fn give_back(&self, planes: impl IntoIterator<Item = wgpu::Buffer>) {
        let mut kept = self.planes.lock().unwrap_or_else(PoisonError::into_inner);
        kept.extend(planes);
        kept.sort_by_key(|plane| std::cmp::Reverse(plane.size()));
        kept.truncate(KEPT);
    }

    /// `toggles` given back, every word nothing again: the bigger of them
    /// and the kept stays.
    fn give_back_toggles(&self, toggles: wgpu::Buffer) {
        let mut kept = self.toggles.lock().unwrap_or_else(PoisonError::into_inner);
        if kept.as_ref().is_none_or(|kept| kept.size() < toggles.size()) {
            *kept = Some(toggles);
        }
    }

    /// The bytes kept between folds.
    fn bytes(&self) -> u64 {
        let planes = self.planes.lock().unwrap_or_else(PoisonError::into_inner);
        let toggles = self.toggles.lock().unwrap_or_else(PoisonError::into_inner);
        planes.iter().chain(toggles.as_ref()).map(wgpu::Buffer::size).sum()
    }

    /// What is kept, let go: the next fold makes its own.
    fn let_go(&self) {
        self.planes.lock().unwrap_or_else(PoisonError::into_inner).clear();
        *self.toggles.lock().unwrap_or_else(PoisonError::into_inner) = None;
    }
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
            kept: Kept::default(),
        }
    }

    /// The bytes of the bit planes kept between folds ([`Kept`]).
    pub(crate) fn kept_bytes(&self) -> u64 {
        self.kept.bytes()
    }

    /// The bit planes kept between folds, let go.
    pub(crate) fn let_go(&self) {
        self.kept.let_go();
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
        at: (i32, i32),
        size: MaskBox,
    ) -> Option<wgpu::Buffer> {
        let out = (size.width.div_ceil(4).div_ceil(GROUP), size.height.div_ceil(GROUP));
        fits(engine, &[size.bytes()], std::iter::once(out))?;
        let folded = self.folded(engine, steps, at, size)?;
        let bytes = plane(engine, "region mask", size.bytes());
        let words = region_words(engine, at, size, folded.stride, (0, 0, 0));
        let bound = [(0, &words), (4, &folded.plane), (5, &bytes)];
        encode(engine, &[Encoded { pipeline: &self.bytes, bound: whole(&bound), groups: flat(out) }]);
        Some(bytes)
    }

    /// The selection `steps` over the pixel box `size` whose top-left pixel
    /// is (`left`, `top`) on the canvas, as a bit plane ([`Folded`]), or
    /// none when the box or a point is past the reach. Submits the work.
    pub(crate) fn folded(
        &self,
        engine: &Engine,
        steps: &[Step],
        (left, top): (i32, i32),
        size: MaskBox,
    ) -> Option<Folded<'_>> {
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
        let crossings = crossings(&vertices, &passes, top, size.height);
        let plane = self.run(engine, (left, top), size, &vertices, &passes, deepest + 1)?;
        Some(Folded { plane, stride: stride_of(size), crossings, kept: &self.kept })
    }

    /// Runs `passes` over `planes` bit planes: the selection is plane 1.
    fn run(
        &self,
        engine: &Engine,
        at: (i32, i32),
        size: MaskBox,
        vertices: &[u32],
        passes: &[Pass],
        planes: usize,
    ) -> Option<wgpu::Buffer> {
        let stride = stride_of(size);
        let bits = u64::from(stride) * u64::from(size.height) * 4;
        let words_across = stride.div_ceil(GROUP);
        let down = size.height.div_ceil(GROUP);
        let groups = |pass: &Pass| match *pass {
            Pass::Toggle { count, .. } => (count.div_ceil(GROUP), down),
            Pass::Scan { .. } => (size.height.div_ceil(ROWS), 1),
            Pass::Clear { .. } | Pass::Fold { .. } => (words_across, down),
        };
        let vertex_bytes = vertices.len() as u64 * 4;
        fits(engine, &[bits, vertex_bytes], passes.iter().map(groups))?;
        // Plane `UNION` only where a pass joins in it.
        let joins = passes.iter().any(Pass::joins);
        let mut planes: Vec<Option<wgpu::Buffer>> = (0..planes)
            .map(|at| (at != UNION || joins).then(|| self.kept.plane(engine, bits)))
            .collect();
        let toggles = self.kept.toggles(engine, bits);
        // A pass binds a whole buffer: a selection of no polygon still has
        // a vertex.
        let storage = wgpu::BufferUsages::STORAGE;
        let vertices = match vertices {
            [] => words_buffer(engine, "region vertices", &[0, 0], storage),
            _ => words_buffer(engine, "region vertices", vertices, storage),
        };
        let words: Vec<wgpu::Buffer> = passes
            .iter()
            .map(|pass| {
                let pass_words = match *pass {
                    Pass::Toggle { first, count } => (first, count, 0),
                    Pass::Scan { combine, .. } | Pass::Fold { combine, .. } => {
                        (0, 0, combine as u32)
                    }
                    Pass::Clear { .. } => (0, 0, 0),
                };
                region_words(engine, at, size, stride, pass_words)
            })
            .collect();
        let plane = |at: usize| planes[at].as_ref();
        let encoded: Option<Vec<Encoded>> = passes
            .iter()
            .zip(&words)
            .map(|(pass, words)| {
                let (pipeline, bound) = match *pass {
                    Pass::Toggle { .. } => {
                        (&self.toggle, vec![(0, words), (1, &vertices), (2, &toggles)])
                    }
                    Pass::Scan { plane: into, .. } => {
                        (&self.scan, vec![(0, words), (2, &toggles), (3, plane(into)?)])
                    }
                    Pass::Clear { plane: into } => {
                        (&self.clear, vec![(0, words), (3, plane(into)?)])
                    }
                    Pass::Fold { into, operand, .. } => {
                        let bound = vec![(0, words), (3, plane(into)?), (4, plane(operand)?)];
                        (&self.fold, bound)
                    }
                };
                Some(Encoded {
                    pipeline,
                    bound: whole(&bound),
                    groups: flat(groups(pass)),
                })
            })
            .collect();
        let Some(encoded) = encoded else {
            return fail("a pass of a selection's fold reads a plane it was not given");
        };
        encode(engine, &encoded);
        drop(encoded);
        let folded = planes[1].take();
        self.kept.give_back(planes.into_iter().flatten());
        self.kept.give_back_toggles(toggles);
        folded
    }
}

/// A selection folded into a bit plane: region.wgsl's, a bit a pixel of
/// its box, `stride` words a row and the leftmost pixel the low bit — and
/// as many crossings as its rows can have ([`crossings`]). Its plane goes
/// back to the planes `kept` once it is dropped: after the last pass that
/// reads it is submitted.
pub(crate) struct Folded<'a> {
    pub(crate) plane: wgpu::Buffer,
    pub(crate) stride: u32,
    pub(crate) crossings: u64,
    kept: &'a Kept,
}

impl Drop for Folded<'_> {
    fn drop(&mut self) {
        self.kept.give_back([self.plane.clone()]);
    }
}

/// A bit plane's words a row over `size`: room for a bit past the box,
/// where a crossing right of every centre toggles.
fn stride_of(size: MaskBox) -> u32 {
    size.width / 32 + 1
}

/// A pass's words (region.wgsl's `Region`): the box at `(left, top)`, the
/// planes' `stride`, and the pass's own — the polygon it lays, as its
/// first vertex and their count, and how it folds.
fn region_words(
    engine: &Engine,
    (left, top): (i32, i32),
    size: MaskBox,
    stride: u32,
    (first, count, op): (u32, u32, u32),
) -> wgpu::Buffer {
    let words = [left as u32, top as u32, size.width, size.height, stride, first, count, op];
    words_buffer(engine, "region pass", &words, wgpu::BufferUsages::UNIFORM)
}

/// How many times the rows of the box from `top`, `height` of them, can
/// cross the polygons `passes` lay of `vertices` — which no row's runs
/// outnumber, every run's ends being where an edge crosses it (runs.wgsl).
/// An edge from height A to height B crosses the rows whose scanline,
/// (2r + 1)·128 in Q.8, lies in [A, B): counted here from a row before
/// ⌊A/256⌋ to a row past ⌊B/256⌋, which holds them all.
fn crossings(vertices: &[u32], passes: &[Pass], top: i32, height: u32) -> u64 {
    let (first_row, last_row) = (i64::from(top), i64::from(top) + i64::from(height) - 1);
    let y = |at: u32| i64::from(vertices[at as usize * 2 + 1].cast_signed());
    let rows = |a: i64, b: i64| {
        let from = (a.min(b).div_euclid(256) - 1).max(first_row);
        let to = (a.max(b).div_euclid(256) + 1).min(last_row);
        u64::try_from(to - from + 1).unwrap_or(0)
    };
    let edges = |first: u32, count: u32| {
        (0..count).map(move |i| (y(first + i), y(first + (i + count - 1) % count)))
    };
    passes
        .iter()
        .map(|pass| match *pass {
            Pass::Toggle { first, count } => edges(first, count).map(|(a, b)| rows(a, b)).sum(),
            _ => 0,
        })
        .sum()
}

/// The passes that fold `steps` into bit plane `into`, from nothing — as
/// `containsPoint` folds from outside; a first step that replaces needs no
/// nothing under it —, each act's polygons folded in as [`copies_laid`]
/// says and a nested selection ([`bare`]) folded first in the plane after
/// `into`, or laid in `into` itself where it replaces it; each point joins
/// `vertices` as Q.8 x and y. The deepest plane they use, or none for a
/// point past the reach.
///
/// ↩️Till 2026-11-14 every act was joined in plane `UNION` and folded in
/// after, and every nested selection in a plane of its own: an inverse of
/// one rectangle was 17 passes over four planes, a lasso five over two —
/// where a simple selection's runs came slower than the CPU's fold
/// (board `a-selection-mask-is-built-on-the-cpu-at-every-move`, L2e).
/// Now they are six over one, and two over one.
fn laid(
    steps: &[Step],
    into: usize,
    vertices: &mut Vec<u32>,
    passes: &mut Vec<Pass>,
) -> Option<usize> {
    let mut deepest = into;
    if !matches!(steps.first(), Some(Step { combine: Combine::Replace, .. })) {
        passes.push(Pass::Clear { plane: into });
    }
    for step in steps {
        match bare(&step.operand) {
            Operand::Copies(polygons) => {
                copies_laid(step.combine, polygons, into, vertices, passes)?;
            }
            Operand::Region(inner) if matches!(step.combine, Combine::Replace) => {
                deepest = deepest.max(laid(inner, into, vertices, passes)?);
            }
            Operand::Region(inner) => {
                deepest = deepest.max(laid(inner, into + 1, vertices, passes)?);
                passes.push(Pass::Fold {
                    combine: step.combine,
                    into,
                    operand: into + 1,
                });
            }
        }
    }
    Some(deepest)
}

/// What `operand` holds, a nested selection of one step that replaces read
/// as that step's operand: folded from nothing, it is nothing but that —
/// an inverse's selection is nested so (`invertedWithin`).
fn bare(operand: &Operand) -> &Operand {
    let mut bare = operand;
    while let Operand::Region(inner) = bare
        && let [Step { combine: Combine::Replace, operand }] = inner.as_slice()
    {
        bare = operand;
    }
    bare
}

/// The passes that fold an act's `polygons` — their union — into plane
/// `into` by `combine`: each polygon scanned straight into it, the first by
/// `combine` and the rest by what the union makes of it — a replace adds
/// them after the first, an add adds and a subtract subtracts each. An
/// intersect of more than one is joined in plane `UNION` first and folded
/// in after: a pixel is the act's when ANY of its polygons holds it, and
/// an intersect with each in turn would keep only what all hold. An act
/// holds a polygon at least: one of none is refused before (`steps_of`
/// in abi.rs). None for a point past the reach.
fn copies_laid(
    combine: Combine,
    polygons: &[Vec<[f64; 2]>],
    into: usize,
    vertices: &mut Vec<u32>,
    passes: &mut Vec<Pass>,
) -> Option<()> {
    let joined = matches!(combine, Combine::Intersect) && polygons.len() > 1;
    let plane = if joined { UNION } else { into };
    if joined {
        passes.push(Pass::Clear { plane: UNION });
    }
    for (at, polygon) in polygons.iter().enumerate() {
        let first = (vertices.len() / 2) as u32;
        for &point in polygon {
            for value in point {
                vertices.push(quantized(value)? as u32);
            }
        }
        let count = polygon.len() as u32;
        let combine = match combine {
            _ if joined => Combine::Add,
            Combine::Replace if at > 0 => Combine::Add,
            other => other,
        };
        passes.push(Pass::Toggle { first, count });
        passes.push(Pass::Scan { plane, combine });
    }
    if joined {
        passes.push(Pass::Fold { combine, into, operand: UNION });
    }
    Some(())
}

/// A canvas coordinate in Q.8, or none past the reach.
fn quantized(value: f64) -> Option<i32> {
    match q(value, 8, (REACH << 8) as f64) {
        Some(value) => Some(value as i32),
        None => fail(format!("a point at {value} is past the canvas's reach of {REACH}")),
    }
}
