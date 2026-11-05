//! The Gaussian (fx Gaussian Blur, now Flutter's `ImageFilter.blur`) as the
//! blur brush's integer law: C's `qa_blur_box` (gpu-canonical-store ⑦ — one
//! blur law, 관제 11-05 12:19).
//!
//! The picture is the input past which there is nothing, or — Repeat Edge
//! Pixels — a rectangle of it whose edge repeats outward, cut to that
//! rectangle (subtree_image_composite.dart's `cutAndBlurred`). Either way a
//! pixel's blur is the one the passes would leave on the whole plane: each
//! pass is worked out a radius further out than the next one reads, as C
//! gathers its window three radii out.
//!
//! ⏳The radius is the app's to give: how a Blurriness becomes a box radius
//! is the bridge round's, beside the brush's (`BrushBlurPicture.
//! blurRadiusOf` — three radii are the blur's reach).

#[cfg(test)]
#[path = "gaussian_tests.rs"]
mod tests;

use super::{Dispatch, GROUP, Held, TileRect, compile, run};
use crate::device::Engine;
use crate::fail;

/// The widest box: a pass sums 2·radius + 1 pixels of 65535 at most, and
/// the sum stays a u32.
pub(crate) const MOST_RADIUS: u32 = 32767;
/// gaussian.wgsl's BLUR_RUN — the pixels one thread slides its sum along.
const RUN: u32 = 64;

const EDGE_NONE: u32 = 0;
const EDGE_NOTHING: u32 = 1;
const EDGE_REPEAT: u32 = 2;

/// What a blur reads past its picture.
#[derive(Clone, Copy, Debug)]
pub(crate) enum Edge {
    /// Nothing: the tiles' rectangle is the picture.
    Nothing,
    /// The nearest pixel of these, [left, top, right, bottom) — inside the
    /// tiles —, and nothing is put outside them (Repeat Edge Pixels).
    Repeat([i32; 4]),
}

/// One dispatch of gaussian.wgsl: along the rows or down the columns, the
/// pixels it writes — [first, end) along, lines [line_first, line_end)
/// across — and its edge along.
struct Pass {
    down: bool,
    radius: u32,
    along: [i32; 2],
    lines: [i32; 2],
    edge: u32,
    edge_along: [i32; 2],
    from: Held,
    to: Held,
}

impl Pass {
    fn dispatch(&self) -> Dispatch {
        let runs = ((self.along[1] - self.along[0]) as u32).div_ceil(RUN);
        let lines = (self.lines[1] - self.lines[0]) as u32;
        Dispatch {
            from: self.from,
            to: self.to,
            words: vec![
                u32::from(self.down),
                self.radius,
                self.along[0] as u32,
                self.along[1] as u32,
                self.lines[0] as u32,
                self.lines[1] as u32,
                self.edge,
                self.edge_along[0] as u32,
                self.edge_along[1] as u32,
            ],
            groups: (runs.div_ceil(GROUP), lines.div_ceil(GROUP)),
        }
    }
}

/// The Gaussian's pass, compiled once.
pub(crate) struct BoxBlur {
    pipeline: wgpu::ComputePipeline,
}

impl BoxBlur {
    pub(crate) fn new(engine: &Engine) -> Self {
        Self {
            pipeline: compile(engine, &[], include_str!("gaussian.wgsl"), "box_blur"),
        }
    }

    /// Blurs `tiles` — straight RGBA8 over `rect` — by box passes of
    /// `radius` across and down, three each way, the rows' first, and
    /// returns the blurred tiles over the same rectangle; submits the work,
    /// the caller waits. A radius of 0 leaves its way as it is.
    pub(crate) fn run(
        &self,
        engine: &Engine,
        tiles: &wgpu::Buffer,
        rect: TileRect,
        radius: (u32, u32),
        edge: Edge,
    ) -> Option<wgpu::Buffer> {
        let (across, down) = radius;
        if across == 0 && down == 0 {
            return fail("a blur of no radius changes no pixel — a plan leaves it out");
        }
        if across > MOST_RADIUS || down > MOST_RADIUS {
            return fail(format!("{radius:?}: a box radius is {MOST_RADIUS} at most"));
        }
        let (picture, kind) = match edge {
            // The columns' first pass reads the rows' plane, which ends at
            // the picture: past it is nothing by this edge, not by what a
            // read past a plane happens to give — 0 on the Surface, where
            // no test tells EDGE_NONE from it (mutant b19, 11-05).
            Edge::Nothing => (rect.pixels(), EDGE_NOTHING),
            Edge::Repeat(inside) if rect.holds(inside) => (inside, EDGE_REPEAT),
            Edge::Repeat(inside) => {
                return fail(format!("{inside:?} is no rectangle inside {rect:?}"));
            }
        };
        let dispatches: Vec<Dispatch> =
            passes(picture, radius, kind).iter().map(Pass::dispatch).collect();
        run(engine, &self.pipeline, tiles, rect, planes(picture, radius), &dispatches, None)
    }
}

/// The passes blurring `picture`, [left, top, right, bottom), by `radius`
/// across and down: three along the rows, then three down the columns, a
/// way of radius 0 taking none. The k-th of a way writes (3 − k) radii past
/// the picture each side, all the k + 1-th reads; the first of a way reads
/// past the picture by `edge`. The first of all reads the tiles, the last
/// puts them; between, the planes hold the 16-bit pixels.
fn passes(picture: [i32; 4], radius: (u32, u32), edge: u32) -> Vec<Pass> {
    let [left, top, right, bottom] = picture;
    let (across, down) = radius;
    // A way's plane reaches two radii past the picture along it.
    let rows_plane = Held::Plane {
        x0: left - 2 * across as i32,
        y0: top,
        width: (right - left) as u32 + 4 * across,
    };
    let columns_plane = Held::Plane {
        x0: left,
        y0: top - 2 * down as i32,
        width: (right - left) as u32,
    };
    let ways = [
        (false, across, [left, right], [top, bottom], rows_plane),
        (true, down, [top, bottom], [left, right], columns_plane),
    ];
    let mut passes: Vec<Pass> = Vec::new();
    for (is_down, r, along, lines, plane) in ways {
        if r == 0 {
            continue;
        }
        for k in 1..=3 {
            let past = (3 - k) * r as i32;
            passes.push(Pass {
                down: is_down,
                radius: r,
                along: [along[0] - past, along[1] + past],
                lines,
                edge: if k == 1 { edge } else { EDGE_NONE },
                edge_along: along,
                from: passes.last().map_or(Held::Tiles, |before| before.to),
                to: plane,
            });
        }
    }
    if let Some(last) = passes.last_mut() {
        last.to = Held::Tiles;
    }
    passes
}

/// The bytes a plane holds: the rows' passes' or the columns', whichever
/// is more.
fn planes(picture: [i32; 4], radius: (u32, u32)) -> u64 {
    let [left, top, right, bottom] = picture;
    let (width, height) = (u64::from((right - left) as u32), u64::from((bottom - top) as u32));
    let rows = (width + 4 * u64::from(radius.0)) * height;
    let columns = width * (height + 4 * u64::from(radius.1));
    rows.max(columns) * 8
}
