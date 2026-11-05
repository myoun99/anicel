//! R3, a mesh warp's integer parts (gpu-int-spec-canvas 1b R3) — the app's
//! `transformStampDabMesh` and `selectionTriangleResampleTransform` — with
//! no CPU copy of a GPU formula (`kernels/mod.rs`): which triangle paints
//! each pixel (`MeshOwners`, mesh.wgsl) and each triangle's destination to
//! source map (`affines`, once a triangle on the CPU, exact in i128 as the
//! spec puts it). ⏳The pass reading the picture through them — each pixel
//! by its triangle's map, through R1 — comes with the pool
//! (gpu-canonical-store, 11-06 01:00).

// ⏳Nothing outside the tests reads a mesh until the canvas's verbs come to
// the engine (gpu-canonical-store, stage 4).
#![cfg_attr(not(test), allow(dead_code))]

#[cfg(test)]
mod tests;

use crate::device::Engine;
use crate::fail;
use crate::kernels::shared::{
    Encoded, ResampleMap, ResampleMode, WIDE_WGSL, encode, fits, pipeline, plane, q, words_buffer,
};

/// mesh.wgsl's workgroup side.
const GROUP: u32 = 8;
/// How far from the canvas's origin a point and the output reach, in
/// pixels: the spec's ±2^15, where a centre's sums fit their words.
const REACH: i64 = 1 << 15;
/// 1 in Q.20, the map's scale.
const Q20: i128 = 1 << 20;

/// A mesh as the app holds it: `columns` × `rows` cells, and the points of
/// its corners row after row — `(columns + 1) · (rows + 1)` of them — where
/// they rest on the picture (`source`, the app's base grid) and where they
/// were dragged to (`destination`), each (x, y) in canvas pixels.
pub(crate) struct MeshGrid {
    pub(crate) columns: u32,
    pub(crate) rows: u32,
    pub(crate) source: Vec<[f64; 2]>,
    pub(crate) destination: Vec<[f64; 2]>,
}

/// A triangle in Q.8: its order, its first corner, the edges to the other
/// two, and their cross product den (Q.16) — 0 for one with no area.
struct Triangle {
    order: u32,
    d0: [i64; 2],
    e1: [i64; 2],
    e2: [i64; 2],
    den: i64,
}

impl MeshGrid {
    /// Each triangle's three corners as indices of the points, in the app's
    /// order: row, column, then (TL, TR, BL) before (TR, BR, BL).
    fn corners(&self) -> Vec<[usize; 3]> {
        let across = self.columns as usize + 1;
        let mut corners = Vec::with_capacity(self.columns as usize * self.rows as usize * 2);
        for row in 0..self.rows as usize {
            for column in 0..self.columns as usize {
                let top_left = row * across + column;
                let (top_right, bottom_left) = (top_left + 1, top_left + across);
                corners.push([top_left, top_right, bottom_left]);
                corners.push([top_right, bottom_left + 1, bottom_left]);
            }
        }
        corners
    }

    /// `points` in Q.8, or none when the grid has no cell, a point is
    /// missing or one is past the reach.
    fn quantized(&self, points: &[[f64; 2]]) -> Option<Vec<[i64; 2]>> {
        let count = (self.columns as usize + 1) * (self.rows as usize + 1);
        if self.columns == 0 || self.rows == 0 || points.len() != count {
            return fail(format!(
                "a {}x{} mesh has {count} points, not {}",
                self.columns,
                self.rows,
                points.len()
            ));
        }
        points
            .iter()
            .map(|&[x, y]| Some([quantized(x, 8)?, quantized(y, 8)?]))
            .collect()
    }

    /// The destination's triangles in Q.8, in order.
    fn triangles(&self) -> Option<Vec<Triangle>> {
        let points = self.quantized(&self.destination)?;
        let triangles = self.corners().into_iter().zip(0..).map(|([p0, p1, p2], order)| {
            let d0 = points[p0];
            let e1 = [points[p1][0] - d0[0], points[p1][1] - d0[1]];
            let e2 = [points[p2][0] - d0[0], points[p2][1] - d0[1]];
            let den = e1[0] * e2[1] - e2[0] * e1[1];
            Triangle {
                order,
                d0,
                e1,
                e2,
                den,
            }
        });
        Some(triangles.collect())
    }
}

/// The pass, compiled once.
pub(crate) struct MeshOwners {
    clear: wgpu::ComputePipeline,
    own: wgpu::ComputePipeline,
}

impl MeshOwners {
    pub(crate) fn new(engine: &Engine) -> Self {
        let source = [WIDE_WGSL, include_str!("mesh.wgsl")];
        Self {
            clear: pipeline(engine, &source, "mesh_clear"),
            own: pipeline(engine, &source, "mesh_own"),
        }
    }

    /// Each pixel of the output `width` × `height` whose top-left pixel is
    /// (`left`, `top`) on the canvas: the order of the triangle of `mesh`
    /// that paints it, or `u32::MAX` where none does — a word a pixel, row
    /// after row. None when the output or a point is past the reach. Submits
    /// the work; the caller waits.
    pub(crate) fn owners(
        &self,
        engine: &Engine,
        mesh: &MeshGrid,
        (left, top): (i32, i32),
        (width, height): (u32, u32),
    ) -> Option<wgpu::Buffer> {
        let spans = |from: i32, length: u32| {
            length > 0
                && -REACH <= i64::from(from)
                && i64::from(from) + i64::from(length) <= REACH
        };
        if !spans(left, width) || !spans(top, height) {
            return fail(format!("({left}, {top}) {width}x{height} is no output in reach"));
        }
        let triangles = mesh.triangles()?;
        let output = [i64::from(left), i64::from(top), i64::from(width), i64::from(height)];
        // Each triangle with area, and the box of its pixels within the
        // output: a centre it holds lies between its corners' floor and
        // ceiling.
        let boxes: Vec<(&Triangle, [i64; 4])> = triangles
            .iter()
            .filter(|triangle| triangle.den != 0)
            .filter_map(|triangle| Some((triangle, within(triangle, output)?)))
            .collect();
        let groups = |[_, _, width, height]: [i64; 4]| {
            ((width as u32).div_ceil(GROUP), (height as u32).div_ceil(GROUP))
        };
        let all = boxes.iter().map(|&(_, reach)| groups(reach)).chain([groups(output)]);
        let bytes = u64::from(width) * u64::from(height) * 4;
        fits(engine, &[bytes], all)?;
        let owners = plane(engine, "mesh owners", bytes);
        let uniform = |order: u32, [x, y, w, h]: [i64; 4], triangle: Option<&Triangle>| {
            let (d0, e1, e2, den) = triangle.map_or(([0; 2], [0; 2], [0; 2], 0), |t| {
                (t.d0, t.e1, t.e2, t.den)
            });
            let words = [
                left as u32,
                top as u32,
                width,
                order,
                x as u32,
                y as u32,
                w as u32,
                h as u32,
                d0[0] as u32,
                d0[1] as u32,
                e1[0] as u32,
                e1[1] as u32,
                e2[0] as u32,
                e2[1] as u32,
                den as u32,
                (den >> 32) as u32,
            ];
            words_buffer(engine, "mesh triangle", &words, wgpu::BufferUsages::UNIFORM)
        };
        let cleared = uniform(0, output, None);
        let words: Vec<wgpu::Buffer> = boxes
            .iter()
            .map(|&(triangle, reach)| uniform(triangle.order, reach, Some(triangle)))
            .collect();
        let mut encoded = vec![Encoded {
            pipeline: &self.clear,
            bound: vec![(0, &cleared), (1, &owners)],
            groups: groups(output),
        }];
        encoded.extend(boxes.iter().zip(&words).map(|(&(_, reach), words)| Encoded {
            pipeline: &self.own,
            bound: vec![(0, words), (1, &owners)],
            groups: groups(reach),
        }));
        encode(engine, &encoded);
        Some(owners)
    }
}

/// The pixels of `output` — left, top, width, height — that may hold a
/// centre of `triangle`: between the floor and the ceiling of its corners,
/// or none when that misses the output.
fn within(triangle: &Triangle, [left, top, width, height]: [i64; 4]) -> Option<[i64; 4]> {
    let corners = [
        triangle.d0,
        [triangle.d0[0] + triangle.e1[0], triangle.d0[1] + triangle.e1[1]],
        [triangle.d0[0] + triangle.e2[0], triangle.d0[1] + triangle.e2[1]],
    ];
    let span = |axis: usize, from: i64, length: i64| {
        let low = corners.iter().map(|corner| corner[axis]).min()? >> 8;
        let high = (corners.iter().map(|corner| corner[axis]).max()? + 255) >> 8;
        let (low, high) = (low.max(from), high.min(from + length));
        // An empty span would dispatch no workgroup all the same; leaving
        // the triangle out spares its words.
        (low < high).then_some((low, high - low))
    };
    let (x, w) = span(0, left, width)?;
    let (y, h) = span(1, top, height)?;
    Some([x, y, w, h])
}

/// Each triangle's map, in the mesh's order, as R1 reads it with
/// `radius_floor` and `mode` — none for a triangle with no area, and for one
/// past R1's ranges, which lands nothing ([`ResampleMap::affine`] holds
/// them). The source is counted from (`left`, `top`) on the canvas, which
/// takes any value within the reach. None when a point or the source's
/// corner is past the reach.
///
/// 1b R3, exact: with e1 = d1 − d0, e2 = d2 − d0, f1 = s1 − s0 and
/// f2 = s2 − s0 in Q.8 and den = e1 × e2 (Q.16), a = divr(±(e2y·f1x −
/// e1y·f2x)·2^20, |den|) and b, d, e likewise, the sign den's; and
/// c = s0x·2^12 − rnd(a·d0x + b·d0y, 8) − q(left, 20), f likewise — the
/// app's `selectionTriangleResampleTransform` measured from the canvas's
/// origin rather than the triangle's box.
pub(crate) fn affines(
    mesh: &MeshGrid,
    (left, top): (f64, f64),
    radius_floor: f64,
    mode: ResampleMode,
) -> Option<Vec<Option<ResampleMap>>> {
    let source = mesh.quantized(&mesh.source)?;
    let origin = [i128::from(quantized(left, 20)?), i128::from(quantized(top, 20)?)];
    let triangles = mesh.triangles()?;
    let maps = mesh.corners().into_iter().zip(&triangles).map(|([p0, p1, p2], triangle)| {
        if triangle.den == 0 {
            return None;
        }
        let s0 = source[p0];
        let f1 = [source[p1][0] - s0[0], source[p1][1] - s0[1]];
        let f2 = [source[p2][0] - s0[0], source[p2][1] - s0[1]];
        let ([e1x, e1y], [e2x, e2y]) = (triangle.e1, triangle.e2);
        let [d0x, d0y] = triangle.d0.map(i128::from);
        let den = i128::from(triangle.den);
        let scaled = |n: i64| divr(i128::from(n) * Q20 * den.signum(), den.abs());
        let row = |f1: i64, f2: i64, s0: i64, origin: i128| {
            let along = scaled(e2y * f1 - e1y * f2);
            let down = scaled(e1x * f2 - e2x * f1);
            let moved = along * d0x + down * d0y;
            (along, down, (i128::from(s0) << 12) - rnd(moved, 8) - origin)
        };
        let (a, b, c) = row(f1[0], f2[0], s0[0], origin[0]);
        let (d, e, f) = row(f1[1], f2[1], s0[1], origin[1]);
        ResampleMap::affine([a, b, c, d, e, f], radius_floor, mode)
    });
    Some(maps.collect())
}

/// divr(n, d) = ⌊(2n + d) / (2d)⌋ for d > 0 (1b 공통) — a half goes up.
fn divr(n: i128, d: i128) -> i128 {
    (2 * n + d).div_euclid(2 * d)
}

/// rnd(x, k) = (x + 2^(k−1)) >> k, arithmetic (1b 공통).
fn rnd(x: i128, k: u32) -> i128 {
    (x + (1 << (k - 1))) >> k
}

/// A canvas value in Q.`k`, or none past the reach.
fn quantized(value: f64, k: u32) -> Option<i64> {
    match q(value, k, (REACH << k) as f64) {
        Some(value) => Some(value),
        None => fail(format!("{value} is past the canvas's reach of {REACH}")),
    }
}
