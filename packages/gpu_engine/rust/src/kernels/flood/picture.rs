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
use crate::kernels::composite::{Composite, Plan, TILE};
use crate::kernels::mask::{Mask, MaskBox};

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

/// The colour the eyedropper picks at canvas pixel `point` of what `plan`
/// shows (`sampleCompositeColor`'s whole-picture read): the pixel's own,
/// straight — or none where nothing is laid, its alpha 0. Waits for the
/// GPU.
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
