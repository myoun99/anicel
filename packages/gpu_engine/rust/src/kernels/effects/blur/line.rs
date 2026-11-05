//! A blur along a way — fx Directional Blur's line, Radial Blur's circle or
//! ray: the app's `directional_blur.frag` and its passes
//! (`directionalBlurPasses`, `radialBlurPasses`), by gpu-int-spec-canvas 1b
//! (4/4). The CPU works out every tap's map and shift here, in doubles with
//! products and sums alone — so the same on every device — and line.wgsl
//! takes them as integers.
//!
//! ⏳The turns and scales a pass's maps start from are the app's to give
//! (`DirectionalBlurShader._mapOf` — a cos, a sin and an exp: 대조 필요 ①,
//! the deterministic functions 관제 placed in gpu-same-formula). A
//! directional blur has none.
//!
//! 📐Between passes the pixels stay premultiplied on the 16-bit scale in a
//! plane, as the Gaussian's do — where 1b (4/4) had each pass round to the
//! chain's bytes (캔버스 베이스 11-05: one way in and out for both blurs).

#[cfg(test)]
#[path = "line_tests.rs"]
mod tests;

use wgpu::util::DeviceExt;

use super::{Dispatch, GROUP, Held, TileRect, compile, run};
use crate::device::Engine;
use crate::fail;
use crate::kernels::shared::{WIDE_WGSL, q};

/// The most taps one pass takes — the app's `lineBoxTapsAPass`.
pub(crate) const MOST_TAPS: u32 = 32;
/// A map's entries are under 16 (Q.20 in 24 bits), and the plate, a
/// centre and a shift under 2^15 pixels each way (Q.16 in an i32): the
/// sums line.wgsl makes of them stay inside an i64.
const MAP_LIMIT: f64 = (1u64 << 24) as f64;
const PIXEL_LIMIT: i32 = 1 << 15;
const SHIFT_LIMIT: f64 = (1u64 << 31) as f64;
const IDENTITY: [f64; 4] = [1.0, 0.0, 0.0, 1.0];

/// One pass of a blur along a way — the app's `LineBoxPass` with its maps
/// worked out (`DirectionalBlurShader.shaderFor`'s `first` and `each`):
/// `taps` taps, the i-th at centre + M_i·(at − centre) + step·(i − (taps −
/// 1)/2), M_i = each^i · first. A map is its columns as the app writes
/// them: where x goes, then where y goes.
#[derive(Clone, Copy, Debug)]
pub(crate) struct LinePass {
    pub(crate) taps: u32,
    pub(crate) step: [f64; 2],
    pub(crate) centre: [f64; 2],
    pub(crate) first: [f64; 4],
    pub(crate) each: [f64; 4],
}

impl LinePass {
    /// A directional blur's pass: no turn and no scale.
    pub(crate) fn along(step: [f64; 2], taps: u32) -> Self {
        LinePass {
            taps,
            step,
            centre: [0.0, 0.0],
            first: IDENTITY,
            each: IDENTITY,
        }
    }

    /// The taps as line.wgsl reads them, six words each — M_i's rows, then
    /// the shift — or none where a value passes what its words hold.
    fn words(&self) -> Option<Vec<u32>> {
        let middle = (f64::from(self.taps) - 1.0) / 2.0;
        let e = self.each;
        let mut m = self.first;
        let mut words = Vec::with_capacity(self.taps as usize * 6);
        for i in 0..self.taps {
            for entry in [m[0], m[2], m[1], m[3]] {
                words.push(q(entry, 20, MAP_LIMIT)? as i32 as u32);
            }
            let along = f64::from(i) - middle;
            for shift in [self.step[0] * along, self.step[1] * along] {
                words.push(q(shift, 16, SHIFT_LIMIT)? as i32 as u32);
            }
            m = [
                e[0] * m[0] + e[2] * m[1],
                e[1] * m[0] + e[3] * m[1],
                e[0] * m[2] + e[2] * m[3],
                e[1] * m[2] + e[3] * m[3],
            ];
        }
        Some(words)
    }
}

/// The blur along a way, compiled once.
pub(crate) struct LineBlur {
    pipeline: wgpu::ComputePipeline,
}

impl LineBlur {
    pub(crate) fn new(engine: &Engine) -> Self {
        Self {
            pipeline: compile(engine, &[WIDE_WGSL], include_str!("line.wgsl"), "line_blur"),
        }
    }

    /// Blurs `tiles` — straight RGBA8 over `rect` — by `passes` in turn
    /// over the `plate`, [left, top, right, bottom) inside them: past it a
    /// pass reads nothing, and nothing is put. Returns the blurred tiles over
    /// the same rectangle; submits the work, the caller waits.
    pub(crate) fn run(
        &self,
        engine: &Engine,
        tiles: &wgpu::Buffer,
        rect: TileRect,
        plate: [i32; 4],
        passes: &[LinePass],
    ) -> Option<wgpu::Buffer> {
        if passes.is_empty() {
            return fail("a blur of no pass changes no pixel — a plan leaves it out");
        }
        if let Some(pass) = passes.iter().find(|pass| !(1..=MOST_TAPS).contains(&pass.taps)) {
            return fail(format!("{} taps a pass; one takes 1 to {MOST_TAPS}", pass.taps));
        }
        if !rect.holds(plate) || plate.iter().any(|edge| edge.abs() >= PIXEL_LIMIT) {
            return fail(format!("{plate:?} is no plate inside {rect:?}"));
        }
        let [left, top, right, bottom] = plate;
        let mut taps = Vec::new();
        let mut dispatches: Vec<Dispatch> = Vec::new();
        for pass in passes {
            let at = taps.len() as u32;
            let (Some(words), Some(x), Some(y)) = (
                pass.words(),
                q(pass.centre[0], 16, SHIFT_LIMIT),
                q(pass.centre[1], 16, SHIFT_LIMIT),
            ) else {
                return fail(format!("{pass:?} reaches past what its words hold"));
            };
            taps.extend(words);
            dispatches.push(Dispatch {
                from: dispatches.last().map_or(Held::Tiles, |before| before.to),
                to: Held::Plane {
                    x0: left,
                    y0: top,
                    width: (right - left) as u32,
                },
                words: vec![
                    at,
                    pass.taps,
                    x as i32 as u32,
                    y as i32 as u32,
                    left as u32,
                    top as u32,
                    right as u32,
                    bottom as u32,
                ],
                groups: (
                    ((right - left) as u32).div_ceil(GROUP),
                    ((bottom - top) as u32).div_ceil(GROUP),
                ),
            });
        }
        if let Some(last) = dispatches.last_mut() {
            last.to = Held::Tiles;
        }
        let bytes: Vec<u8> = taps.iter().flat_map(|word| word.to_le_bytes()).collect();
        let taps = engine
            .device
            .create_buffer_init(&wgpu::util::BufferInitDescriptor {
                label: Some("line blur taps"),
                contents: &bytes,
                usage: wgpu::BufferUsages::STORAGE,
            });
        let plane = u64::from((right - left) as u32) * u64::from((bottom - top) as u32) * 8;
        run(engine, &self.pipeline, tiles, rect, plane, &dispatches, Some(&taps))
    }
}
