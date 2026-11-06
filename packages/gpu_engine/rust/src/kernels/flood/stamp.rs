//! A fill's colour stamp (`_colorStampDab`, gpu-canonical-store stage 5):
//! the mask it finished, in its colour, as the tiles of a stroke row —
//! what the executor lays on the cel (R28), the selection's mask and the
//! fill's opacity and mode its row's. stamp.wgsl has why nothing else is
//! needed to land it.
//!
//! The row is every tile the mask's box meets. The app cuts a fill into
//! pieces of the tiles it covers (`_stampPieces`) for its CPU's sake; here
//! a tile it covers none of is laid as nothing, and the write path keeps
//! the cel's tile there (`kernels/write`) — knowing which tiles those are
//! before the plan is made would wait for the GPU to say.
//!
//! Under a gradient (I-160, `_gradientRgba`) each pixel is the gradient's
//! colour at its centre instead: this file turns the gradient's ends into
//! the integers stamp.wgsl reads — the one place they become integers —,
//! and makes its stops.

#[cfg(test)]
#[path = "stamp_tests.rs"]
mod tests;

use crate::device::Engine;
use crate::fail;
use crate::kernels::composite::{TILE, TILE_BYTES, TileAt, TileSet};
use crate::kernels::mask::Mask;
use crate::kernels::shared::{Encoded, encode, plane, tiles_a_pass, whole, words_buffer};

use super::Flood;

/// The stops a gradient is looked up in, `FillGradient.stops`' count
/// (`_gradientStops`): four to each level a channel takes.
const STOPS: i32 = 1024;
/// How far from the canvas's corner a gradient's ends and a graded mask's
/// box may lie, in pixels: a pixel's offset from an end in 1/256 px is then
/// an i32, and stamp.wgsl's sums of two products of them stay under 2^62.
const GRADED_REACH: f64 = 65536.0;
const LINE: u32 = 1;
const CIRCLE: u32 = 2;

/// What a stamp lays under its mask: a colour (red, green, blue), or a
/// gradient's colour at each pixel.
pub(crate) enum Paint<'a> {
    Colour([u8; 3]),
    Gradient(&'a Gradient),
}

/// A fill's gradient (`FillGradient`), in canvas pixels: `start` at
/// `from`, `end` at `to` and past it — and, along a line, `start` behind
/// `from` —, each straight RGBA.
pub(crate) struct Gradient {
    pub(crate) shape: Shape,
    pub(crate) from: (f64, f64),
    pub(crate) to: (f64, f64),
    pub(crate) start: [u8; 4],
    pub(crate) end: [u8; 4],
}

/// `FillGradientShape` (유저 I-160-Q4 「직선 + 원형」).
#[derive(Clone, Copy)]
pub(crate) enum Shape {
    Line,
    Circle,
}

/// A stamp: its pages, each holding tiles of it slot after slot, and its
/// tiles on the canvas's grid at their pages and slots.
pub(crate) struct Stamped {
    pub(crate) pages: Vec<wgpu::Buffer>,
    pub(crate) set: TileSet,
}

impl Flood {
    /// `mask` — on the canvas — laid in `paint` as the tiles of a row, on
    /// pages the plan will hold from its `first_page` on. Submits the work;
    /// the caller waits.
    pub(crate) fn stamp(
        &self,
        engine: &Engine,
        mask: &Mask,
        paint: &Paint,
        first_page: u16,
    ) -> Option<Stamped> {
        // A pass a page, a tile a workgroup deep — and a slot is a u16.
        let most = tiles_a_pass(engine, TILE_BYTES, 0)?.min(usize::from(u16::MAX));
        self.stamp_by(engine, mask, paint, first_page, most)
    }

    /// `stamp`, a page holding no more than `per_page` tiles — a test's
    /// fewer than the device's, to see a stamp go on to its next page.
    fn stamp_by(
        &self,
        engine: &Engine,
        mask: &Mask,
        paint: &Paint,
        first_page: u16,
        per_page: usize,
    ) -> Option<Stamped> {
        mask.checked()?;
        let set = tiles_of(mask, first_page, per_page)?;
        let (colour, ends, stops) = match paint {
            Paint::Colour(colour) => (*colour, [0; 5], None),
            Paint::Gradient(gradient) => {
                let (ends, stops) = graded(gradient, mask)?;
                let stops = words_buffer(engine, "stops", &stops, wgpu::BufferUsages::STORAGE);
                ([0; 3], ends, Some(stops))
            }
        };
        let [red, green, blue] = colour.map(u32::from);
        let mut pages = Vec::new();
        let mut first = 0;
        while first < set.tiles.len() {
            let count = per_page.min(set.tiles.len() - first);
            let mut words = vec![
                mask.at.0 as u32,
                mask.at.1 as u32,
                mask.size.width,
                mask.size.height,
                mask.size.stride(),
                set.x0 as u32,
                set.y0 as u32,
                set.columns,
                first as u32,
                red | green << 8 | blue << 16,
            ];
            words.extend(ends);
            words.push(0);
            let words = &words_buffer(engine, "stamp", &words, wgpu::BufferUsages::UNIFORM);
            let page = plane(engine, "stamp page", count as u64 * TILE_BYTES);
            let side = TILE / 16;
            let mut bound = vec![(0, words), (1, mask.plane), (2, &page)];
            bound.extend(stops.as_ref().map(|stops| (3, stops)));
            encode(
                engine,
                &[Encoded {
                    pipeline: if stops.is_some() { &self.graded } else { &self.stamp },
                    bound: whole(&bound),
                    groups: (side, side, count as u32),
                }],
            );
            pages.push(page);
            first += count;
        }
        Some(Stamped { pages, set })
    }
}

/// `gradient` as stamp.wgsl reads it over `mask`: its shape, its `from` and
/// `to − from` in 1/256 px — each rounded once —, and its stops, each
/// channel start + round((end − start) · i / 1023): 1023 is odd, so no
/// share is a half and the rounding is the app's (`FillGradient.colorAt`).
/// Nothing where an end or the box lies past [`GRADED_REACH`].
fn graded(gradient: &Gradient, mask: &Mask) -> Option<([u32; 5], Vec<u32>)> {
    // No NaN or infinity is within a reach either.
    let fixed = |v: f64| (v.abs() <= GRADED_REACH).then(|| (v * 256.0).round());
    let ends = [gradient.from.0, gradient.from.1, gradient.to.0, gradient.to.1].map(fixed);
    let [Some(from_x), Some(from_y), Some(to_x), Some(to_y)] = ends else {
        return fail("a gradient's end lies past what its sums hold");
    };
    let (left, top) = (f64::from(mask.at.0), f64::from(mask.at.1));
    let (right, bottom) = (left + f64::from(mask.size.width), top + f64::from(mask.size.height));
    if [left, top, right, bottom].iter().any(|edge| edge.abs() > GRADED_REACH) {
        return fail("a graded mask's box lies past what its sums hold");
    }
    let shape = match gradient.shape {
        Shape::Line => LINE,
        Shape::Circle => CIRCLE,
    };
    let word = |v: f64| v as i32 as u32;
    let ends = [shape, word(from_x), word(from_y), word(to_x - from_x), word(to_y - from_y)];
    let stops = (0..STOPS)
        .map(|i| {
            let channel = |k: usize| {
                let (start, end) = (i32::from(gradient.start[k]), i32::from(gradient.end[k]));
                (start + (2 * (end - start) * i + STOPS - 1).div_euclid(2 * (STOPS - 1))) as u32
            };
            channel(0) | channel(1) << 8 | channel(2) << 16 | channel(3) << 24
        })
        .collect();
    Some((ends, stops))
}

/// The tiles `mask`'s box meets, row after row, `per_page` to a page from
/// page `first_page` on.
fn tiles_of(mask: &Mask, first_page: u16, per_page: usize) -> Option<TileSet> {
    let side = i64::from(TILE);
    let (left, top) = (i64::from(mask.at.0), i64::from(mask.at.1));
    let (width, height) = (i64::from(mask.size.width), i64::from(mask.size.height));
    // In tiles, ends excluded; an empty box meets none.
    let (x0, y0) = (left.div_euclid(side), top.div_euclid(side));
    let x1 = if width == 0 { x0 } else { (left + width - 1).div_euclid(side) + 1 };
    let y1 = if height == 0 { y0 } else { (top + height - 1).div_euclid(side) + 1 };
    let (Ok(x0), Ok(y0), Ok(columns), Ok(rows)) = (
        i32::try_from(x0),
        i32::try_from(y0),
        u32::try_from(x1 - x0),
        u32::try_from(y1 - y0),
    ) else {
        return fail("a mask's box lies past the canvas's grid");
    };
    let count = columns as usize * rows as usize;
    let tiles: Option<Vec<Option<TileAt>>> = (0..count)
        .map(|tile| {
            let page = u16::try_from(tile / per_page).ok()?.checked_add(first_page)?;
            let slot = u16::try_from(tile % per_page).ok()?;
            Some(Some(TileAt { page, slot }))
        })
        .collect();
    let Some(tiles) = tiles else {
        return fail("a stamp's pages are past what a plan names");
    };
    Some(TileSet {
        x0,
        y0,
        columns,
        rows,
        tiles,
    })
}
