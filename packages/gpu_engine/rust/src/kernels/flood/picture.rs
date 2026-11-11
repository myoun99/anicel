//! The picture a fill and the eyedropper read (유저 gpu-canonical-store-Q1,
//! 11-06: 「화면과 똑같은 그림을 읽는다」): what the executor shows of a plan
//! over the tiles a box on the canvas meets. The plan is the screen's with
//! the paper left out (유저 I-163-Q6, 11-05: 「지금 합성에서 종이만
//! 뺀다」) — its maker's to leave out, as it is the maker's to build. A fill
//! floods it (`Flood::region`) and the eyedropper reads a pixel of it
//! (`pick`): one picture, made by one road.

#[cfg(test)]
#[path = "picture_tests.rs"]
mod tests;

use crate::device::Engine;
use crate::fail;
use crate::kernels::blend::mode::NORMAL;
use crate::kernels::composite::{Composite, Plan, Step, TILE, TILE_BYTES, TileAt, TileSet, WHOLE};
use crate::kernels::mask::{Mask, MaskBox};
use crate::kernels::shared::{ResampleMap, ResampleMode, fits, tiles_a_page};

use super::{Extent, Finished, Picture};

/// What a plan shows over a box on the canvas: the composite's output
/// tiles over a grid of `across` × `down` tiles from canvas tile column and
/// row `grid`, row after row, and the box in the grid's pixels.
pub(crate) struct Shown {
    out: wgpu::Buffer,
    grid: (i32, i32),
    across: u32,
    down: u32,
    inside: Extent,
}

impl Shown {
    /// What `plan` shows over `extent` — canvas pixels [left, top, right,
    /// bottom), nothing past it — on the tiles it meets. Submits the work;
    /// the caller waits.
    pub(crate) fn of(
        engine: &Engine,
        composite: &Composite,
        plan: &Plan,
        extent: [i32; 4],
    ) -> Option<Shown> {
        let [left, top, right, bottom] = extent.map(i64::from);
        if left >= right || top >= bottom {
            return fail(format!("{extent:?} shows no pixel"));
        }
        let side = i64::from(TILE);
        let (x0, y0) = (left.div_euclid(side), top.div_euclid(side));
        let (x1, y1) = ((right - 1).div_euclid(side) + 1, (bottom - 1).div_euclid(side) + 1);
        // A picture is one buffer the executor puts and one binding of a
        // flood's passes (flood.wgsl): one past what a binding holds is
        // refused here, before a tile of it is counted out.
        let count = ((x1 - x0) as u64).saturating_mul((y1 - y0) as u64);
        fits(engine, &[count.saturating_mul(TILE_BYTES)], std::iter::empty())?;
        // Tiles of whole i32 pixels: a canvas pixel is an i32.
        let tiles: Vec<(i32, i32)> = (y0..y1)
            .flat_map(|row| (x0..x1).map(move |column| (column as i32, row as i32)))
            .collect();
        let inside = Extent {
            left: (left - x0 * side) as u32,
            top: (top - y0 * side) as u32,
            right: (right - x0 * side) as u32,
            bottom: (bottom - y0 * side) as u32,
        };
        let done = composite.run(engine, plan, &tiles, extent, composite.widest())?;
        Some(Shown {
            out: done.out,
            grid: (x0 as i32, y0 as i32),
            across: (x1 - x0) as u32,
            down: (y1 - y0) as u32,
            inside,
        })
    }

    /// What `plan` shows as a space posed on the canvas reads it
    /// ([`Shown::posed`]), over the pixels `extent` of that space: shown
    /// over the canvas pixels the pose can read ([`ResampleMap::reads`])
    /// and none past `within` — [left, top, right, bottom), the world its
    /// maker says the plan draws in: nothing shows past it —, then carried
    /// into the space. A pose that reads nothing of `within` reads a
    /// picture of nothing. Submits the work; the caller waits.
    pub(crate) fn through(
        engine: &Engine,
        composite: &Composite,
        plan: &Plan,
        to_canvas: [f64; 9],
        extent: [i32; 4],
        within: [i32; 4],
    ) -> Option<Shown> {
        let [left, top, right, bottom] = extent.map(i64::from);
        let [x0, y0, x1, y1] = within.map(i64::from);
        // A homography bounds no read: all of `within`, as its row binds
        // all its tiles.
        let read = pose(to_canvas, extent)?.reads(left, top, right, bottom);
        let [x0, y0, x1, y1] = match read {
            Some(read) => [read[0].max(x0), read[1].max(y0), read[2].min(x1), read[3].min(y1)],
            None => [x0, y0, x1, y1],
        };
        if x0 >= x1 || y0 >= y1 {
            let nothing = Plan {
                pages: &[],
                sets: &[],
                keys: &[],
                matrices: &[],
                chains: &[],
                steps: &[],
                mask: None,
            };
            return Shown::of(engine, composite, &nothing, extent);
        }
        // Cut at `within`, whose edges are i32s.
        let on_canvas = [x0, y0, x1, y1].map(|edge| edge as i32);
        let shown = Shown::of(engine, composite, plan, on_canvas)?;
        shown.posed(engine, composite, to_canvas, extent)
    }

    /// What it shows as a space posed on the canvas reads it: over `extent`
    /// — that space's pixels [left, top, right, bottom), nothing past it —
    /// each pixel what this picture shows where `to_canvas` lands it (the
    /// space's pixel to the canvas's, row-major with the homogeneous row
    /// last), by the tent mean on a radius of a pixel at least, as a row
    /// posed on the canvas is read (R1), and nothing where it lands off
    /// this picture. A fill on a posed row floods there: where its pen is
    /// and where its colour lands (the app's I-36, 유저 2026-09-24: 「이
    /// 과정에서 법 다른거 통일」) — the screen's picture still (유저
    /// gpu-canonical-store-Q1), folders, blends and effects as they show,
    /// carried whole into the row's space. Submits the work; the caller
    /// waits.
    pub(crate) fn posed(
        &self,
        engine: &Engine,
        composite: &Composite,
        to_canvas: [f64; 9],
        extent: [i32; 4],
    ) -> Option<Shown> {
        // It is laid as one page of the plan that reads it, a tile a slot.
        let (count, held) = (self.across * self.down, tiles_a_page(engine)?);
        if count as usize > held {
            return fail(format!("a picture of {count} tiles is no page: one holds {held}"));
        }
        let map = pose(to_canvas, extent)?;
        let set = TileSet {
            x0: self.grid.0,
            y0: self.grid.1,
            columns: self.across,
            rows: self.down,
            tiles: (0..count).map(|slot| Some(TileAt { page: 0, slot: slot as u16 })).collect(),
        };
        let steps = [Step::Row {
            set: 0,
            keys: None,
            chain: None,
            map,
            matrix: None,
            opacity: WHOLE,
            mode: NORMAL,
            masked: false,
        }];
        let plan = Plan {
            pages: std::slice::from_ref(&self.out),
            sets: std::slice::from_ref(&set),
            keys: &[],
            matrices: &[],
            chains: &[],
            steps: &steps,
            mask: None,
        };
        Shown::of(engine, composite, &plan, extent)
    }

    /// It as the picture a fill floods, in the grid's pixels.
    pub(crate) fn picture(&self) -> Picture<'_> {
        Picture {
            tiles: &self.out,
            across: self.across,
            down: self.down,
            inside: self.inside,
        }
    }

    /// Canvas pixel `(x, y)` in the grid's pixels — where a press lands on
    /// the picture —, or none off the grid.
    pub(crate) fn on_grid(&self, (x, y): (i32, i32)) -> Option<(u32, u32)> {
        let side = i64::from(TILE);
        let column = i64::from(x) - i64::from(self.grid.0) * side;
        let row = i64::from(y) - i64::from(self.grid.1) * side;
        let (across, down) = (i64::from(self.across) * side, i64::from(self.down) * side);
        ((0..across).contains(&column) && (0..down).contains(&row))
            .then_some((column as u32, row as u32))
    }

    /// A fill `finished` on the picture, laid on the canvas — what its
    /// colour is stamped through (`dab::stamp`).
    pub(crate) fn on_canvas<'a>(&self, finished: &'a Finished) -> Mask<'a> {
        let crop = finished.crop;
        let side = TILE as i32;
        Mask {
            plane: &finished.mask,
            at: (
                self.grid.0 * side + crop.left as i32,
                self.grid.1 * side + crop.top as i32,
            ),
            size: MaskBox {
                width: crop.right - crop.left,
                height: crop.bottom - crop.top,
            },
        }
    }
}

/// The map a space posed on the canvas by `to_canvas` reads the canvas
/// with over its pixels `extent` ([`Shown::posed`]): the tent mean on a
/// radius of a pixel at least — or none, with why, where the pose lands
/// nothing.
fn pose(to_canvas: [f64; 9], extent: [i32; 4]) -> Option<ResampleMap> {
    let [left, top, right, bottom] = extent.map(i64::from);
    let across = u32::try_from(right - left).unwrap_or(0);
    let down = u32::try_from(bottom - top).unwrap_or(0);
    let map = ResampleMap::new(to_canvas, 1.0, ResampleMode::Blend, across, down);
    map.or_else(|| fail("a pose that lands nothing reads nothing of the canvas"))
}

/// The colour the eyedropper picks at canvas pixel `point` of what `plan`
/// shows (`sampleCompositeColor`'s whole-picture read): the pixel's own,
/// straight — or none where nothing is laid, its alpha 0. Waits for the
/// GPU.
// ⏳Nothing outside the tests picks until the eyedropper comes to the
// engine: the app's reads a walk of its own still (`sampleCompositeColor`),
// after the fill (fill-runs-in-the-c-engine).
#[cfg_attr(not(test), allow(dead_code))]
pub(crate) fn pick(
    engine: &Engine,
    composite: &Composite,
    plan: &Plan,
    (x, y): (i32, i32),
) -> Option<Option<[u8; 3]>> {
    let (Some(right), Some(bottom)) = (x.checked_add(1), y.checked_add(1)) else {
        return fail(format!("({x}, {y}) is the canvas's last pixel, past which none shows"));
    };
    let shown = Shown::of(engine, composite, plan, [x, y, right, bottom])?;
    let bytes = engine.read_buffer(&shown.out)?;
    let side = TILE as i32;
    let texel = (y.rem_euclid(side) * side + x.rem_euclid(side)) as usize * 4;
    let [red, green, blue, alpha] = bytes[texel..texel + 4].try_into().unwrap();
    Some((alpha != 0).then_some([red, green, blue]))
}
