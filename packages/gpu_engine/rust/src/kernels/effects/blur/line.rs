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

use super::{Dispatch, GROUP, Held, TileRect, bands, compile, run, words_buffer};
use crate::device::Engine;
use crate::fail;
use crate::kernels::shared::{WIDE_WGSL, q, room};

/// The most taps one pass takes — the app's `lineBoxTapsAPass`.
pub(crate) const MOST_TAPS: u32 = 32;
/// A map's entries are under 16 (Q.20 in 24 bits), and the plate, a
/// centre and a shift under 2^15 pixels each way (Q.16 in an i32): the
/// sums line.wgsl makes of them stay inside an i64.
const MAP_LIMIT: f64 = (1u64 << 24) as f64;
const PIXEL_LIMIT: i32 = 1 << 15;
const SHIFT_LIMIT: f64 = (1u64 << 31) as f64;
const IDENTITY: [f64; 4] = [1.0, 0.0, 0.0, 1.0];
/// The rows past where a band's taps land, each side, that the plane its
/// pass reads holds besides: line.wgsl's Q.20 maps and Q.16 shifts land a
/// tap within 1/32 of a pixel of the doubles here (an entry 2^-21 off, a
/// way under 2^15 pixels), so one row would do — two keep clear of it.
const SPARE_ROWS: i32 = 2;

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

    /// Each tap's map M_i and shift o_i, in doubles — what its words hold
    /// and where it lands alike.
    fn maps(&self) -> impl Iterator<Item = ([f64; 4], [f64; 2])> + '_ {
        let middle = (f64::from(self.taps) - 1.0) / 2.0;
        let e = self.each;
        (0..self.taps).scan(self.first, move |m, i| {
            let here = *m;
            *m = [
                e[0] * m[0] + e[2] * m[1],
                e[1] * m[0] + e[3] * m[1],
                e[0] * m[2] + e[2] * m[3],
                e[1] * m[2] + e[3] * m[3],
            ];
            let along = f64::from(i) - middle;
            Some((here, [self.step[0] * along, self.step[1] * along]))
        })
    }

    /// The taps as line.wgsl reads them, six words each — M_i's rows, then
    /// the shift — or none where a value passes what its words hold.
    fn words(&self) -> Option<Vec<u32>> {
        let mut words = Vec::with_capacity(self.taps as usize * 6);
        for (m, shift) in self.maps() {
            for entry in [m[0], m[2], m[1], m[3]] {
                words.push(q(entry, 20, MAP_LIMIT)? as i32 as u32);
            }
            for shift in shift {
                words.push(q(shift, 16, SHIFT_LIMIT)? as i32 as u32);
            }
        }
        Some(words)
    }

    /// The rows of `plate` this pass reads putting its rows `put`, every
    /// column of them: from the row above the highest tap to the row below
    /// the lowest — a map moves a rectangle's corners furthest —, SPARE_ROWS
    /// more each side, inside the plate. None where it puts none.
    fn reads(&self, plate: [i32; 4], put: [i32; 2]) -> [i32; 2] {
        let [left, top, right, bottom] = plate;
        if put[0] >= put[1] {
            return [put[0], put[0]];
        }
        let [cx, cy] = self.centre;
        let rows = [put[0], put[1] - 1];
        let corners = [(left, rows[0]), (right - 1, rows[0]), (left, rows[1]), (right - 1, rows[1])];
        let (mut low, mut high) = (f64::INFINITY, f64::NEG_INFINITY);
        for (m, shift) in self.maps() {
            for (x, y) in corners {
                let (dx, dy) = (f64::from(x) + 0.5 - cx, f64::from(y) + 0.5 - cy);
                let at = cy + m[1] * dx + m[3] * dy + shift[1];
                (low, high) = (low.min(at), high.max(at));
            }
        }
        // A tap at y falls between rows ⌊y − ½⌋ and the one after it.
        let first = ((low - 0.5).floor() as i32 - SPARE_ROWS).clamp(top, bottom);
        let end = ((high - 0.5).floor() as i32 + 2 + SPARE_ROWS).clamp(first, bottom);
        [first, end]
    }
}

/// The rows each of `passes` puts for `band` of `plate`, first to last: the
/// last's the band, each before it what the next reads ([`LinePass::reads`]).
fn puts(passes: &[LinePass], plate: [i32; 4], band: [i32; 2]) -> Vec<[i32; 2]> {
    let mut puts = vec![band];
    for pass in passes.iter().skip(1).rev() {
        let next = puts[puts.len() - 1];
        puts.push(pass.reads(plate, next));
    }
    puts.reverse();
    puts
}

/// The bytes a plane holds for `band` of `plate`: every column of the most
/// rows a pass but the last puts — none for a pass alone.
fn planes(passes: &[LinePass], plate: [i32; 4], band: [i32; 2]) -> u64 {
    let width = u64::from((plate[2] - plate[0]) as u32);
    let puts = puts(passes, plate, band);
    let rows = puts[..puts.len() - 1].iter().map(|put| put[1] - put[0]).max().unwrap_or(0);
    width * u64::from(rows as u32) * 8
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
        self.run_in(engine, tiles, rect, plate, passes, room(engine))
    }

    /// `run`, in bands whose planes a binding of `room` bytes holds
    /// ([`bands`]).
    fn run_in(
        &self,
        engine: &Engine,
        tiles: &wgpu::Buffer,
        rect: TileRect,
        plate: [i32; 4],
        passes: &[LinePass],
        room: u64,
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
        // Each pass's own words but the rows it puts, which are its band's.
        let mut own: Vec<[u32; 8]> = Vec::with_capacity(passes.len());
        for pass in passes {
            let (Some(words), Some(x), Some(y)) = (
                pass.words(),
                q(pass.centre[0], 16, SHIFT_LIMIT),
                q(pass.centre[1], 16, SHIFT_LIMIT),
            ) else {
                return fail(format!("{pass:?} reaches past what its words hold"));
            };
            own.push([
                taps.len() as u32,
                pass.taps,
                x as i32 as u32,
                y as i32 as u32,
                left as u32,
                top as u32,
                right as u32,
                bottom as u32,
            ]);
            taps.extend(words);
        }
        let fits = |band| planes(passes, plate, band) <= room;
        let Some(bands) = bands([top, bottom], fits) else {
            let row = planes(passes, plate, [top, top + 1]);
            return fail(format!("a band of one row holds {row} bytes, past a binding of {room}"));
        };
        let width = (right - left) as u32;
        let plane_of = |put: [i32; 2]| Held::Plane { x0: left, y0: put[0], width };
        let mut dispatches: Vec<Dispatch> = Vec::new();
        for &band in &bands {
            let puts = puts(passes, plate, band);
            for (k, (words, put)) in own.iter().zip(&puts).enumerate() {
                dispatches.push(Dispatch {
                    from: if k == 0 { Held::Tiles } else { plane_of(puts[k - 1]) },
                    to: if k + 1 == puts.len() { Held::Tiles } else { plane_of(*put) },
                    words: [&words[..], &[put[0] as u32, put[1] as u32]].concat(),
                    groups: (width.div_ceil(GROUP), ((put[1] - put[0]) as u32).div_ceil(GROUP)),
                });
            }
        }
        let taps = words_buffer(engine, "line blur taps", &taps, wgpu::BufferUsages::STORAGE);
        let plane = bands.iter().map(|&band| planes(passes, plate, band)).max().unwrap_or(0);
        run(engine, &self.pipeline, (tiles, rect), (plane, room), &dispatches, Some(&taps))
    }
}
