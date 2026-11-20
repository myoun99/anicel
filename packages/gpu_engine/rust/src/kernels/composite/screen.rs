//! The editing screen on the engine (screen-on-the-engine c6): the canvas's
//! composite kept on its own grid, made again where the canvas changed, and
//! shown through the camera. The canvas is composited at its own pixels
//! before the camera samples it, so a magnified screen shows the result's
//! pixels and a pan or a zoom shows again what is kept
//! (gpu-canonical-store ④⑤).

#[cfg(test)]
#[path = "screen_tests.rs"]
mod tests;

use crate::device::Engine;
use crate::fail;
use crate::kernels::blend::mode::NORMAL;
use crate::kernels::shared::{ResampleMap, ResampleMode};

use super::kept::{Kept, plan};
use super::{Budget, Composite, Plan, Step, meets};

/// The camera the screen is shown through: `inverse`, screen pixel to
/// canvas pixel (pixel (x, y) spanning x..x+1) — `[a, b, c, d, e, f]`,
/// canvas x = a·x + b·y + c, y = d·x + e·y + f — in `mode`, Nearest at
/// 100% and over and Blend under it (④). Affine: a view pans, zooms, turns
/// and flips, and leans no plane away, so no screen's size bounds its w
/// (M11, 관제 11-08 16:27).
///
/// ↩️It carried the display's scale too till 2026-11-19, read for nothing
/// but which halving stage to show ([`Screen::show`]).
#[derive(Clone, Copy)]
pub(crate) struct Camera {
    pub(crate) inverse: [f64; 6],
    pub(crate) mode: ResampleMode,
}

/// The affine map `[a, b, c, d, e, f]` as a full inverse, its homogeneous
/// row (0, 0, 1).
pub(crate) fn affine([a, b, c, d, e, f]: [f64; 6]) -> [f64; 9] {
    [a, b, c, d, e, f, 0.0, 0.0, 1.0]
}

/// Tiles laid whole in normal over nothing through `map`: the screen's one
/// row.
pub(crate) fn row(map: ResampleMap) -> Step {
    Step::Row {
        set: 0,
        keys: None,
        chain: None,
        map,
        matrix: None,
        opacity: 65535,
        mode: NORMAL,
        masked: false,
    }
}

/// A canvas's screen: its composite over the pixels it covers once one is
/// laid — the page and what lies past it, a frame's world.
pub(crate) struct Screen {
    extent: [i32; 4],
    /// Blend's radius floor the camera samples on.
    floor: f64,
    canvas: Option<Kept>,
}

impl Screen {
    /// Nothing composed yet, for a composite over the pixels `extent`,
    /// [left, top, right, bottom), shown on Blend's radius `floor` at
    /// least. None over no pixel — an extent of no width or no height, or
    /// turned inside out —, saying so.
    pub(crate) fn new(extent: [i32; 4], floor: f64) -> Option<Self> {
        let [left, top, right, bottom] = extent;
        if left >= right || top >= bottom {
            return fail(format!("a screen over {extent:?} holds no pixel"));
        }
        Some(Self { extent, floor, canvas: None })
    }

    /// `plan` composited onto the kept canvas over its tiles that meet the
    /// pixels `changed`, [left, top, right, bottom) — the whole canvas the
    /// first time. Where the composite changed is the caller's to say: the
    /// kept tiles `changed` meets none of are kept as they were. An empty
    /// `changed` composites nothing on a canvas laid already. Submits the
    /// work, and waits for none of it.
    ///
    /// 🚨A CANVAS A COMPOSE FAILED ON IS NONE: made again in part, it would
    /// show a frame that is no frame's — so it is let go of, a show fails
    /// by name till a compose lays it whole again, and a screen's frame is
    /// not put up meanwhile (`ScreenTexture.present`). ↩️Till 2026-11-15 a
    /// compose's failure was thrown where it was asked, before the show
    /// (the-ui-thread-never-enters-the-driver B1-a: a compose is handed
    /// over unwaited now, and the show after it is handed over before its
    /// failure is told).
    pub(crate) fn compose(
        &mut self,
        engine: &Engine,
        composite: &Composite,
        plan: &Plan,
        changed: [i32; 4],
        budget: Budget,
    ) -> Option<()> {
        match &mut self.canvas {
            None => self.canvas = Some(Kept::made(engine, composite, plan, self.extent, budget)?),
            Some(canvas) => {
                let meets = |tile| meets(tile, changed);
                if canvas.made_again(engine, composite, plan, meets, budget).is_none() {
                    self.canvas = None;
                    return None;
                }
            }
        }
        Some(())
    }

    /// `plan` composited onto a canvas nothing is composed on yet, as
    /// [`Screen::compose`] does the first time, but on the tiles that meet
    /// the pixels `fresh` alone — [left, top, right, bottom) —: every other
    /// tile `film`'s canvas keeps is copied from it as it is
    /// ([`Kept::made_over`]). Over a film nothing is composed on, the whole
    /// canvas.
    pub(crate) fn compose_over(
        &mut self,
        engine: &Engine,
        composite: &Composite,
        plan: &Plan,
        film: &Screen,
        fresh: [i32; 4],
        budget: Budget,
    ) -> Option<()> {
        if self.canvas.is_some() {
            return fail("a screen is composed over a film only before anything is composed on it");
        }
        let Some(under) = &film.canvas else {
            return self.compose(engine, composite, plan, self.extent, budget);
        };
        let fresh = |tile| meets(tile, fresh);
        self.canvas = Some(Kept::made_over(engine, composite, plan, self.extent, under, fresh, budget)?);
        Some(())
    }

    /// The bytes it keeps: its canvas's tiles.
    pub(crate) fn bytes(&self) -> u64 {
        self.canvas.as_ref().map_or(0, Kept::bytes)
    }

    /// The kept canvas through `camera` onto the pixels `rect` of `target`
    /// — [left, top, right, bottom) —, the rest of it left as it was;
    /// submits the work and waits for none of it ([`Composite::show`]), and
    /// returns how many passes it took.
    ///
    /// THE ONE COMPOSITE AT EVERY SCALE (F-610-Q4, 🗣️유저 2026-11-19:
    /// 「애초에 12.5%밑에서는 정확도는 의미없어. 안정확해도되 … 6.25밑에서
    /// 두번째소재 만들고 들고있는게 별로잖아」). One read reaches no
    /// further than Blend's ceiling, 16 px a side (`shared::resample`'s
    /// `CEILING`), so under 1/16 a pixel's tent is cut short of what it
    /// spans and the screen aliases there: a line a pixel wide shows
    /// fainter or not at all by where it lies between two screen pixels'
    /// centres. That is the price decided on, not a fault to mend with a
    /// second picture.
    ///
    /// ↩️Under 1/16 it read the composite halved, stage after stage, kept
    /// beside it — ⅓ of its tiles at most — from 2026-11-07
    /// (connection-round-checklist 11-07 02:04 (a), 캔버스 베이스 패널's ①
    /// ②; halvings.rs, gone with this): each stage Blend at a half of the
    /// one above, the screen reading the finest whose scale was back at
    /// 1/16 or over, so a tent stayed whole at any scale — a line at 1/40
    /// held its alpha wherever it lay. 🔬What ruled out the third way, a
    /// ceiling at what each pixel spans (backup `work/gpu-shrink-ceiling`):
    /// each output pixel walks its (2/s)² taps, and a pasteboard of nine S5
    /// canvases took 118 ms at 1/160 and 456 ms at 1/320 on an RTX 4080
    /// (11-07 01:52).
    pub(crate) fn show(
        &self,
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
        let Some(map) = ResampleMap::new(affine(camera.inverse), self.floor, camera.mode, 1, 1) else {
            return fail("the camera lands nothing on the screen");
        };
        let steps = [row(map)];
        composite.show(engine, &plan(canvas.as_tiles(), &steps), target, rect, budget)
    }
}
