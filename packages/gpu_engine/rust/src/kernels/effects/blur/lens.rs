//! fx Camera Lens Blur's row sums and the light it reads them in — the
//! app's row_sum.frag and lens_light.glsl `lit` (`rowSumPasses`,
//! `LensLight`), by gpu-int-spec-canvas 1b (4/4): every pixel of the picture
//! the exact sum of its row up to it, each pixel read through the light.
//! The iris gathers each of its rows out of two of these.
//!
//! 📐The light is worked on held.wgsl's 16-bit scale, where 1b (4/4) had
//! Q.16: so a pixel read with no light is read as the other blurs read it
//! (캔버스 베이스 11-05 — the threshold is a channel, 65535 at one).
//!
//! ⏳The iris (iris_table and iris_gather) and the light's way back to a
//! stored pixel come next, in a round of their own.

#[cfg(test)]
#[path = "lens_tests.rs"]
mod tests;

use super::{
    Encoded, GROUP, Held, TileRect, checked, compile, encode, held_words, plane, words_buffer,
};
use crate::device::Engine;
use crate::fail;
use crate::kernels::shared::{WIDE_WGSL, q};

/// The most gain a light takes — the app's Highlight Gain's.
pub(crate) const MOST_GAIN: f64 = 100.0;
/// sums.wgsl's SUMS_RUN.
const RUN: u32 = 64;
/// A pixel's sum's bytes: four channels of two words.
const SUM_BYTES: u64 = 32;
/// A run's total's: four channels of a word.
const TOTAL_BYTES: u64 = 16;

/// How a lens blur reads the light it spreads — the app's `LensLight`: its
/// gain (0 to 100), its threshold and saturation (0 to 1), and whether it
/// reads in linear light.
#[derive(Clone, Copy, Debug)]
pub(crate) struct Light {
    pub(crate) gain: f64,
    pub(crate) threshold: f64,
    pub(crate) saturation: f64,
    pub(crate) linear: bool,
}

impl Light {
    /// The light a picture is stored in, nothing boosted.
    pub(crate) const STORED: Light = Light {
        gain: 0.0,
        threshold: 1.0,
        saturation: 0.0,
        linear: false,
    };

    /// light.wgsl's `Light`, or none where a value is out of its range.
    fn words(&self) -> Option<[u32; 4]> {
        let in_range = (0.0..=MOST_GAIN).contains(&self.gain)
            && (0.0..=1.0).contains(&self.threshold)
            && (0.0..=1.0).contains(&self.saturation);
        if !in_range {
            return None;
        }
        Some([
            q(self.gain, 16, f64::MAX)? as u32,
            (self.threshold * 65535.0).round() as u32,
            q(self.saturation, 16, f64::MAX)? as u32,
            u32::from(self.linear),
        ])
    }
}

/// The row sums' two passes, compiled once.
pub(crate) struct LensSums {
    runs: wgpu::ComputePipeline,
    carry: wgpu::ComputePipeline,
}

impl LensSums {
    pub(crate) fn new(engine: &Engine) -> Self {
        let more = [WIDE_WGSL, include_str!("light.wgsl")];
        let own = include_str!("sums.wgsl");
        Self {
            runs: compile(engine, &more, own, "sums_runs"),
            carry: compile(engine, &more, own, "sums_carry"),
        }
    }

    /// The sums of `tiles` — straight RGBA8 over `rect` — read in `light`,
    /// over the `picture`, [left, top, right, bottom) inside them: a plane
    /// of its pixels row after row, each four channels of two words, low
    /// first. Submits the work; the caller waits.
    pub(crate) fn run(
        &self,
        engine: &Engine,
        tiles: &wgpu::Buffer,
        rect: TileRect,
        picture: [i32; 4],
        light: Light,
    ) -> Option<wgpu::Buffer> {
        if !rect.holds(picture) {
            return fail(format!("{picture:?} is no picture inside {rect:?}"));
        }
        let Some(light_words) = light.words() else {
            return fail(format!("{light:?} is past what a light takes"));
        };
        let [left, top, right, bottom] = picture;
        let (width, rows) = ((right - left) as u32, (bottom - top) as u32);
        let runs = width.div_ceil(RUN);
        let groups = (runs.div_ceil(GROUP), rows.div_ceil(GROUP));
        let sums_bytes = u64::from(width) * u64::from(rows) * SUM_BYTES;
        let totals_bytes = u64::from(runs) * u64::from(rows) * TOTAL_BYTES;
        checked(engine, tiles, rect, &[sums_bytes, totals_bytes], [groups].into_iter())?;
        let sums = plane(engine, "lens sums", sums_bytes);
        let totals = plane(engine, "lens run totals", totals_bytes);
        let to = Held::Plane {
            x0: left,
            y0: top,
            width,
        };
        let uniform = wgpu::BufferUsages::UNIFORM;
        let held = words_buffer(engine, "lens held", &held_words(Held::Tiles, to, rect), uniform);
        let mut own = light_words.to_vec();
        own.extend([rows, runs]);
        let own = words_buffer(engine, "lens sums pass", &own, uniform);
        encode(
            engine,
            &[
                Encoded {
                    pipeline: &self.runs,
                    bound: vec![(0, &held), (1, tiles), (2, &sums), (3, &own), (4, &totals)],
                    groups,
                },
                Encoded {
                    pipeline: &self.carry,
                    bound: vec![(0, &held), (2, &sums), (3, &own), (4, &totals)],
                    groups,
                },
            ],
        );
        Some(sums)
    }
}
