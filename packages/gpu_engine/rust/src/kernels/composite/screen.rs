//! The editing screen on the engine (screen-on-the-engine c6): the canvas's
//! composite kept on its own grid, made again where the canvas changed, and
//! shown through the camera — under 1/16 through its halvings
//! (halvings.rs). The canvas is composited at its own pixels before the
//! camera samples it, so a magnified screen shows the result's pixels and a
//! pan or a zoom shows again what is kept (gpu-canonical-store ④⑤).

#[cfg(test)]
#[path = "screen_tests.rs"]
mod tests;

use crate::device::Engine;
use crate::fail;

use super::halvings::{Camera, Halvings, Kept};
use super::{Budget, Composite, Plan, TILE};

/// A canvas's screen: its composite over the pixels it covers once one is
/// laid — the page and what lies past it, a frame's world — and the
/// halvings the screen reads under 1/16.
pub(crate) struct Screen {
    extent: [i32; 4],
    canvas: Option<Kept>,
    halvings: Halvings,
}

impl Screen {
    /// Nothing composed yet, for a composite over the pixels `extent`,
    /// [left, top, right, bottom), shown on Blend's radius `floor` at least.
    pub(crate) fn new(extent: [i32; 4], floor: f64) -> Option<Self> {
        Some(Self { extent, canvas: None, halvings: Halvings::new(extent, floor)? })
    }

    /// `plan` composited onto the kept canvas over its tiles that meet the
    /// pixels `changed`, [left, top, right, bottom) — the whole canvas the
    /// first time — and the halvings told. Where the composite changed is
    /// the caller's to say: the kept tiles `changed` meets none of are kept
    /// as they were. An empty `changed` composites nothing on a canvas laid
    /// already. Submits the work; [`Screen::show`] waits.
    pub(crate) fn compose(
        &mut self,
        engine: &Engine,
        composite: &Composite,
        plan: &Plan,
        changed: [i32; 4],
        budget: Budget,
    ) -> Option<()> {
        match &self.canvas {
            None => self.canvas = Some(Kept::made(engine, composite, plan, self.extent, budget)?),
            Some(canvas) => {
                let meets = |tile| meets(tile, changed);
                canvas.made_again(engine, composite, plan, meets, budget)?;
            }
        }
        self.halvings.changed(changed);
        Some(())
    }

    /// The kept canvas through `camera` onto the pixels `rect` of `target`
    /// — [left, top, right, bottom) —, the rest of it left as it was; waits
    /// for the GPU ([`Composite::show`]) and returns how many passes it
    /// took.
    pub(crate) fn show(
        &mut self,
        engine: &Engine,
        composite: &Composite,
        camera: Camera,
        target: &wgpu::Texture,
        rect: [u32; 4],
        budget: Budget,
    ) -> Option<usize> {
        let Some(canvas) = &self.canvas else {
            return fail("a screen is shown before anything is composed on it");
        };
        self.halvings.show(engine, composite, canvas.as_tiles(), camera, target, rect, budget)
    }
}

/// Whether the tile at `column`, `row` holds a pixel of `rect`, [left, top,
/// right, bottom) — none for an empty one.
fn meets((column, row): (i32, i32), rect: [i32; 4]) -> bool {
    let side = i64::from(TILE);
    let (x, y) = (i64::from(column) * side, i64::from(row) * side);
    let [left, top, right, bottom] = rect.map(i64::from);
    left < right && top < bottom && left < x + side && x < right && top < y + side && y < bottom
}
