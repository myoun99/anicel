//! fx Camera Lens Blur's iris, row by row — the app's iris_table.frag
//! (`IrisBlurShader.tableFor`), by gpu-int-spec-canvas 1b (4/4): at each
//! level the iris is laid at, the columns about a pixel each row of its
//! outline and its core covers, then the level's head. The CPU works out
//! the iris's words here — its sides, its corners and the way a row runs
//! through it — in doubles with products, sums, divisions and square roots
//! alone, so the same on every device; iris_table.wgsl crosses every row
//! with them in integers.
//!
//! ⏳The turns (its rotation, half a side's and a whole side's) are the
//! app's to give — a cosine and a sine each (대조 필요 ①), as a line
//! blur's maps' starts are.
//!
//! 📐A centre within 2^-10 of a bound is on it, where the app's frag puts
//! one within 10^-3 of a row's ends once its pieces are joined: a power of
//! two, which the integers take exactly, kept by each bound — the two part
//! only within that of an edge, inside the app's own test band.
//!
//! ⏳The gather that reads the table, and the light's way back to a stored
//! pixel, come next — the round after this one.

#[cfg(test)]
#[path = "iris_tests.rs"]
mod tests;

use std::ops::RangeInclusive;

use super::{Encoded, GROUP, encode, fits, pipeline, plane, words_buffer};
use crate::device::Engine;
use crate::fail;
use crate::kernels::shared::{WIDE_WGSL, q};

/// The most radius an iris takes — the app's `irisRowsAtMost`, 2 · 8192 +
/// 1 rows: so a row's line stays within 2^14 pixels of a corner, and its
/// products in iris_table.wgsl inside an i64.
pub(crate) const MOST_RADIUS: f64 = 8192.0;
/// The core: the iris drawn this much as big — the app's kCoreScale.
const CORE_SCALE: f64 = 0.8;
/// A triangle's sides to a decagon's.
const SIDES: RangeInclusive<u32> = 3..=10;
/// The app's Aspect Ratio's: so |D| ≥ 0.1, and 1 / |D| in Q.28 fits a word.
const ASPECTS: RangeInclusive<f64> = 0.1..=10.0;
/// A turn's cosine and sine lie this near the unit circle.
const UNIT: f64 = 1e-6;
/// iris_table.wgsl's IRIS_SHAPE_WORDS, IRIS_POLYGON and IRIS_ROUNDED.
const SHAPE_WORDS: usize = 29;
const POLYGON: u32 = 1;
const ROUNDED: u32 = 2;
/// A blur map's levels: one for each of its values.
const MAP_LEVELS: u32 = 256;
/// A level's head: its reach, what its outline and its core cover, nothing.
const HEAD_WORDS: u64 = 4;
/// iris_heads' workgroup.
const HEADS_GROUP: u32 = 64;
/// What an i32 holds, and what two words do with room to add.
const WORD: f64 = 2_147_483_648.0;
const WIDE: f64 = 4_611_686_018_427_387_904.0;

/// An iris's shape — the app's `IrisRows` but its radius and levels: its
/// sides, roundness (0 to 1) and aspect; then, as cosine and sine, its
/// rotation (clockwise), half a side's turn and a whole side's.
#[derive(Clone, Copy, Debug)]
pub(crate) struct Iris {
    pub(crate) sides: u32,
    pub(crate) roundness: f64,
    pub(crate) aspect: f64,
    pub(crate) turn: [f64; 2],
    pub(crate) half_side: [f64; 2],
    pub(crate) side: [f64; 2],
}

/// A blur map's focus — the app's `IrisRows.levels`: the value (0 to 255)
/// in focus, and whether the map reads inverted.
#[derive(Clone, Copy, Debug)]
pub(crate) struct Focus {
    pub(crate) focal: f64,
    pub(crate) inverts: bool,
}

/// The words a table is laid by: its pass's, its sides' and its shapes'.
struct Words {
    pass: Vec<u32>,
    sides: Vec<u32>,
    shapes: Vec<u32>,
    rows: u32,
    levels: u32,
}

/// `v` turned counterclockwise by the angle whose cosine and sine are `by`.
fn turned(v: [f64; 2], by: [f64; 2]) -> [f64; 2] {
    [by[0] * v[0] - by[1] * v[1], by[1] * v[0] + by[0] * v[1]]
}

fn dot(a: [f64; 2], b: [f64; 2]) -> f64 {
    a[0] * b[0] + a[1] * b[1]
}

/// `x` in Q.`k`, a word as an i32 holds it.
fn word(x: f64, k: u32) -> Option<u32> {
    Some(q(x, k, WORD)? as i32 as u32)
}

impl Iris {
    fn in_range(&self, radius: f64, focus: Option<Focus>) -> bool {
        let on_the_circle = |[c, s]: [f64; 2]| (c * c + s * s - 1.0).abs() <= UNIT;
        SIDES.contains(&self.sides)
            && (0.0..=1.0).contains(&self.roundness)
            && ASPECTS.contains(&self.aspect)
            && (0.0..=MOST_RADIUS).contains(&radius)
            && [self.turn, self.half_side, self.side].into_iter().all(on_the_circle)
            && focus.is_none_or(|focus| (0.0..=255.0).contains(&focus.focal))
    }

    /// The words the table of this iris `radius` out is laid by, at one
    /// level or at each of a blur map's — or none where a value is past what
    /// an iris takes.
    ///
    /// A row dy and a column t lie at P(t) = dy·E + t·D in the iris's own
    /// space, unturned, unsqueezed and scaled by the squeeze A·U — the
    /// app's `at` and `along` without its divisions.
    fn words(&self, radius: f64, focus: Option<Focus>) -> Option<Words> {
        if !self.in_range(radius, focus) {
            return None;
        }
        let across = self.aspect.min(1.0);
        let up_down = (1.0 / self.aspect).min(1.0);
        let squeeze = across * up_down;
        let [c, s] = self.turn;
        let e = [up_down * s, across * c];
        let d = [up_down * c, -across * s];
        let length = dot(d, d).sqrt();
        let along = [d[0] / length, d[1] / length];
        // The bottom edge's normal, a quarter turn; each next edge's a side on.
        let mut normals = vec![[0.0, 1.0]];
        while normals.len() < self.sides as usize {
            normals.push(turned(normals[normals.len() - 1], self.side));
        }
        let mut sides = Vec::with_capacity(normals.len() * 4);
        for &normal in &normals {
            let tangent = [-normal[1], normal[0]];
            for v in [dot(normal, e), dot(normal, d), dot(tangent, e), dot(tangent, d)] {
                sides.push(word(v, 30)?);
            }
        }
        let reach = radius.floor() as u32;
        let levels = focus.map_or(1, |_| MAP_LEVELS);
        let mut shapes = Vec::with_capacity(levels as usize * 2 * SHAPE_WORDS);
        for level in 0..levels {
            // The share first, at most 1: so no level's radius passes the
            // iris's, where (R · 255) / 255 may by a bit.
            let radius = focus.map_or(radius, |focus| {
                let value = if focus.inverts { 255 - level } else { level };
                radius * ((f64::from(value) - focus.focal).abs() / 255.0)
            });
            let reach = radius.floor() as u32;
            for scale in [1.0, CORE_SCALE] {
                shapes.extend(self.shape(radius * scale, reach, squeeze, &normals)?);
            }
        }
        let rows = 2 * reach + 1;
        let mut pass = vec![reach, rows, levels * 2, self.sides, word(squeeze, 30)?];
        pass.push(q(1.0 / length, 28, 2.0 * WORD)? as u32);
        for v in [e[0], e[1], along[0], along[1], -along[1], along[0]] {
            pass.push(word(v, 30)?);
        }
        Some(Words {
            pass,
            sides,
            shapes,
            rows,
            levels,
        })
    }

    /// iris_table.wgsl's words of one shape: the iris `radius` out, whose
    /// rows reach `reach` either way of a pixel.
    fn shape(
        &self,
        radius: f64,
        reach: u32,
        squeeze: f64,
        normals: &[[f64; 2]],
    ) -> Option<Vec<u32>> {
        let corner = (1.0 - self.roundness) * radius;
        let apothem = corner * self.half_side[0];
        let rounding = self.roundness * radius;
        let polygon = if apothem > 0.0 { POLYGON } else { 0 };
        let rounded = if rounding > 0.0 { ROUNDED } else { 0 };
        let mut words = vec![reach, polygon | rounded];
        for bound in [apothem, apothem + rounding, corner * self.half_side[1]] {
            let bound = q(squeeze * bound, 30, WIDE)?;
            words.extend([bound as u32, (bound >> 32) as u32]);
        }
        words.push(word(squeeze * rounding, 16)?);
        for &normal in normals {
            for v in turned(normal, self.half_side) {
                words.push(word(squeeze * corner * v, 16)?);
            }
        }
        words.resize(SHAPE_WORDS, 0);
        Some(words)
    }
}

/// The table's two passes, compiled once.
pub(crate) struct IrisTable {
    rows: wgpu::ComputePipeline,
    heads: wgpu::ComputePipeline,
}

impl IrisTable {
    pub(crate) fn new(engine: &Engine) -> Self {
        let sources = [WIDE_WGSL, include_str!("iris_table.wgsl")];
        Self {
            rows: pipeline(engine, &sources, "iris_rows"),
            heads: pipeline(engine, &sources, "iris_heads"),
        }
    }

    /// The table of `iris` `radius` out, at one level or, with a `focus`,
    /// at each of a blur map's 256: each shape's rows — a level's outline,
    /// then its core — from the farthest reach above a pixel down, each its
    /// left and right column (i32; none where the left is past the right);
    /// then each level's head, its reach and the centres its outline and its
    /// core cover, and a word of nothing. Submits the work; the caller waits.
    pub(crate) fn run(
        &self,
        engine: &Engine,
        iris: Iris,
        radius: f64,
        focus: Option<Focus>,
    ) -> Option<wgpu::Buffer> {
        let Some(words) = iris.words(radius, focus) else {
            return fail(format!(
                "{iris:?} {radius} out, {focus:?}, is past what an iris takes"
            ));
        };
        let shapes = words.levels * 2;
        let rows = u64::from(shapes) * u64::from(words.rows) * 2;
        let bytes = (rows + u64::from(words.levels) * HEAD_WORDS) * 4;
        let row_groups = (words.rows.div_ceil(GROUP), shapes.div_ceil(GROUP));
        let head_groups = (words.levels.div_ceil(HEADS_GROUP), 1);
        fits(engine, &[bytes], [row_groups, head_groups].into_iter())?;
        let table = plane(engine, "iris table", bytes);
        let pass = words_buffer(engine, "iris pass", &words.pass, wgpu::BufferUsages::UNIFORM);
        let storage = wgpu::BufferUsages::STORAGE;
        let sides = words_buffer(engine, "iris sides", &words.sides, storage);
        let shapes = words_buffer(engine, "iris shapes", &words.shapes, storage);
        encode(
            engine,
            &[
                Encoded {
                    pipeline: &self.rows,
                    bound: vec![(0, &pass), (1, &sides), (2, &shapes), (3, &table)],
                    groups: row_groups,
                },
                Encoded {
                    pipeline: &self.heads,
                    bound: vec![(0, &pass), (2, &shapes), (3, &table)],
                    groups: head_groups,
                },
            ],
        );
        Some(table)
    }
}
