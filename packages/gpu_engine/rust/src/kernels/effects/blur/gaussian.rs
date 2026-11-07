//! fx Gaussian Blur — AE's, and the walk's (Flutter's `ImageFilter.blur`):
//! each way one pass of the Gaussian itself, the rows' first (🗣️유저
//! gpu-canonical-store-Q2, 2026-11-08: 「모든 흐림을 진짜 가우시안」 — at
//! every Blurriness, on the picture as it is: Impeller blurs a picture made
//! smaller past a sigma, and that is not done here).
//!
//! ↩️It went by the blur brush's three boxes (gpu-canonical-store ⑦, 관제
//! 11-05 12:19) — the AI's choice, never the user's: three boxes blur no
//! thinner than about two pixels, so a Blurriness under 6 spread a line
//! past what the screen shows (Q2: up to 190 apart). The boxes are the
//! brush's alone now (`boxes`).
//!
//! A way's weights are the Gaussian's at the whole pixels its reach holds,
//! integers summing to 65536 ([`weights`]), and a pass's pixel their sum
//! over the pixels about it on held.wgsl's premultiplied 16-bit scale,
//! rounded half up once: a sum of integers, the same in any order on any
//! device. The plane between the passes holds those 16-bit pixels.
//!
//! What a blur reads is its picture: past it nothing — the walk's decal —
//! or, Repeat Edge Pixels, its nearest pixel — the walk's clamp. What it
//! puts is a rectangle of its own, and nothing outside it: the picture,
//! where the walk's raster is the picture, or the picture grown by the
//! reach, where the walk's filter paints past the image it is drawn from
//! (composite_tree_plan.dart's `_chainOf` says which).

#[cfg(test)]
#[path = "gaussian_tests.rs"]
mod tests;

use super::{Dispatch, GROUP, Held, TileRect, bands, compile, run, words_buffer};
use crate::device::Engine;
use crate::fail;
use crate::kernels::shared::room;

/// The farthest a way's weights reach: the picture's coordinates are i32s,
/// and a reach past this would be a picture no plane holds.
pub(crate) const MOST_REACH: u32 = 32767;
/// The weights' sum: 65535 under each of them is 65535·65536 at most, and
/// with half of one for the rounding it stays a u32 (gaussian.wgsl).
const WHOLE: u32 = 65536;

const EDGE_NOTHING: u32 = 1;
const EDGE_REPEAT: u32 = 2;

/// One way of a Gaussian: its sigma in pixels, and how many pixels either
/// side of a pixel its weights reach — none where the way is not blurred.
#[derive(Clone, Copy, Debug, PartialEq)]
pub(crate) struct Way {
    pub(crate) sigma: f64,
    pub(crate) reach: u32,
}

/// What a blur reads past its picture.
#[derive(Clone, Copy, Debug, PartialEq)]
pub(crate) enum Edge {
    /// Nothing (the walk's decal).
    Nothing,
    /// The nearest pixel inside (Repeat Edge Pixels, the walk's clamp).
    Repeat,
}

/// A Gaussian as a chain runs it: its ways, the picture it reads —
/// [left, top, right, bottom) — and how past it, and the rectangle it
/// puts, nothing outside it.
#[derive(Clone, Copy, Debug, PartialEq)]
pub(crate) struct Blur {
    pub(crate) across: Way,
    pub(crate) down: Way,
    pub(crate) picture: [i32; 4],
    pub(crate) edge: Edge,
    pub(crate) puts: [i32; 4],
}

/// The weights of a way of `sigma` reaching `reach` pixels: e^(−i²/2σ²)
/// at i = 0 ..= reach — `libm`'s, the same Rust on every device, where
/// `f64::exp` is the device's maths library's (shared/one_maths.rs) —
/// scaled so the 2·reach + 1 of them sum to 65536 and taken as integers
/// each within one of its share: the floors, then what they fall short
/// given a pair at a time — a weight stands either side — to the largest
/// remainders, the nearer first among equals, and the odd one left to the
/// middle.
pub(crate) fn weights(sigma: f64, reach: u32) -> Vec<u32> {
    let twice_variance = 2.0 * sigma * sigma;
    let gaussian: Vec<f64> =
        (0..=reach).map(|i| libm::exp(-f64::from(i * i) / twice_variance)).collect();
    let total = gaussian[0] + 2.0 * gaussian[1..].iter().sum::<f64>();
    let shares: Vec<f64> = gaussian.iter().map(|g| g * f64::from(WHOLE) / total).collect();
    let mut weights: Vec<u32> = shares.iter().map(|share| share.floor() as u32).collect();
    let mut short = WHOLE - weights[0] - 2 * weights[1..].iter().sum::<u32>();
    let remainder = |i: usize| shares[i] - f64::from(weights[i]);
    let mut pairs: Vec<usize> = (1..weights.len()).collect();
    pairs.sort_by(|&a, &b| remainder(b).total_cmp(&remainder(a)).then(a.cmp(&b)));
    for i in pairs {
        if short < 2 {
            break;
        }
        weights[i] += 1;
        short -= 2;
    }
    weights[0] += short;
    weights
}

/// One pass: along the rows or down the columns, its weights' reach and
/// where they begin, the pixels it writes — [first, end) along, lines
/// [line_first, line_end) across — and the picture's edge it reads past,
/// along and across.
struct Pass {
    down: bool,
    reach: u32,
    weights: u32,
    along: [i32; 2],
    lines: [i32; 2],
    edge: u32,
    edge_along: [i32; 2],
    edge_across: [i32; 2],
    from: Held,
    to: Held,
}

impl Pass {
    /// gaussian.wgsl's `GaussianPass`.
    fn words(&self) -> Vec<u32> {
        vec![
            u32::from(self.down),
            self.reach,
            self.along[0] as u32,
            self.along[1] as u32,
            self.lines[0] as u32,
            self.lines[1] as u32,
            self.edge,
            self.edge_along[0] as u32,
            self.edge_along[1] as u32,
            self.edge_across[0] as u32,
            self.edge_across[1] as u32,
            self.weights,
        ]
    }

    /// Its dispatch: a thread a pixel, neighbours along a row side by side.
    fn dispatch(&self) -> Dispatch {
        let along = (self.along[1] - self.along[0]) as u32;
        let lines = (self.lines[1] - self.lines[0]) as u32;
        let (x, y) = if self.down { (lines, along) } else { (along, lines) };
        Dispatch {
            from: self.from,
            to: self.to,
            words: self.words(),
            groups: (x.div_ceil(GROUP), y.div_ceil(GROUP)),
        }
    }
}

/// The passes putting rows `band` of `blur`'s rectangle: the rows' along
/// it, then the columns' down it, a way of no reach taking none. Where
/// both go, the rows' put the lines of the picture the columns' read for
/// the band ([`lines_read`]) in a plane as wide as the rectangle — which
/// the columns' read whole, their edge across its own — and the columns'
/// read past the picture by its edge.
fn passes(blur: &Blur, band: [i32; 2]) -> Vec<Pass> {
    let [left, top, right, bottom] = blur.picture;
    let [put_left, _, put_right, _] = blur.puts;
    let edge = match blur.edge {
        Edge::Nothing => EDGE_NOTHING,
        Edge::Repeat => EDGE_REPEAT,
    };
    let rows = |lines, to| Pass {
        down: false,
        reach: blur.across.reach,
        weights: 0,
        along: [put_left, put_right],
        lines,
        edge,
        edge_along: [left, right],
        edge_across: [top, bottom],
        from: Held::Tiles,
        to,
    };
    let columns = |edge_across, from| Pass {
        down: true,
        reach: blur.down.reach,
        weights: blur.across.reach + 1,
        along: band,
        lines: [put_left, put_right],
        edge,
        edge_along: [top, bottom],
        edge_across,
        from,
        to: Held::Tiles,
    };
    match (blur.across.reach, blur.down.reach) {
        (_, 0) => vec![rows(band, Held::Tiles)],
        (0, _) => vec![columns([left, right], Held::Tiles)],
        (_, down) => {
            let lines = lines_read(band, down, [top, bottom]);
            let plane = Held::Plane {
                x0: put_left,
                y0: lines[0],
                width: (put_right - put_left) as u32,
            };
            vec![rows(lines, plane), columns([put_left, put_right], plane)]
        }
    }
}

/// The lines of the picture's `rows` the columns' pass reads putting
/// `band` by weights reaching `down`: the band and `down` past it each
/// side, held to the picture — past it the edge stands in, and nothing
/// still reads its first or its last line.
fn lines_read(band: [i32; 2], down: u32, rows: [i32; 2]) -> [i32; 2] {
    let (reach, last) = (down as i32, rows[1] - 1);
    [(band[0] - reach).clamp(rows[0], last), (band[1] - 1 + reach).clamp(rows[0], last) + 1]
}

/// The bytes the plane holds for `band` of `blur` — none where one way
/// goes alone.
fn planes(blur: &Blur, band: [i32; 2]) -> u64 {
    if blur.across.reach == 0 || blur.down.reach == 0 {
        return 0;
    }
    let [left, _, right, _] = blur.puts;
    let [first, end] = lines_read(band, blur.down.reach, [blur.picture[1], blur.picture[3]]);
    u64::from((right - left) as u32) * u64::from((end - first) as u32) * 8
}

/// The Gaussian's pass, compiled once.
pub(crate) struct Gaussian {
    pipeline: wgpu::ComputePipeline,
}

impl Gaussian {
    pub(crate) fn new(engine: &Engine) -> Self {
        Self {
            pipeline: compile(engine, &[], include_str!("gaussian.wgsl"), "gaussian_blur"),
        }
    }

    /// `tiles` — straight RGBA8 over `rect` — through `blur`: the tiles it
    /// put over the same rectangle. Submits the work; the caller waits.
    pub(crate) fn run(
        &self,
        engine: &Engine,
        tiles: &wgpu::Buffer,
        rect: TileRect,
        blur: &Blur,
    ) -> Option<wgpu::Buffer> {
        self.run_in(engine, tiles, rect, blur, room(engine))
    }

    /// `run`, in bands whose plane a binding of `room` bytes holds
    /// ([`bands`]).
    fn run_in(
        &self,
        engine: &Engine,
        tiles: &wgpu::Buffer,
        rect: TileRect,
        blur: &Blur,
        room: u64,
    ) -> Option<wgpu::Buffer> {
        let ways = [blur.across, blur.down];
        if ways.iter().all(|way| way.reach == 0) {
            return fail("a blur of no reach changes no pixel — a plan leaves it out");
        }
        if let Some(way) = ways.iter().find(|way| way.reach > MOST_REACH) {
            return fail(format!("{way:?}: a way reaches {MOST_REACH} pixels at most"));
        }
        if let Some(way) = ways.iter().find(|way| way.reach > 0 && !(way.sigma > 0.0)) {
            return fail(format!("{way:?}: a way that reaches has a sigma"));
        }
        if ways.iter().any(|way| !way.sigma.is_finite()) {
            return fail(format!("{ways:?}: a sigma is a number"));
        }
        for (name, inside) in [("picture", blur.picture), ("rectangle put", blur.puts)] {
            if !rect.holds(inside) {
                return fail(format!("{inside:?}: the {name} is no rectangle inside {rect:?}"));
            }
        }
        let [_, top, _, bottom] = blur.puts;
        let fits = |band| planes(blur, band) <= room;
        let Some(bands) = bands([top, bottom], fits) else {
            let row = planes(blur, [top, top + 1]);
            return fail(format!("a band of one row holds {row} bytes, past a binding of {room}"));
        };
        let dispatches: Vec<Dispatch> = bands
            .iter()
            .flat_map(|&band| passes(blur, band))
            .map(|pass| pass.dispatch())
            .collect();
        let words: Vec<u32> = ways
            .iter()
            .flat_map(|way| match way.reach {
                0 => vec![WHOLE],
                reach => weights(way.sigma, reach),
            })
            .collect();
        let weights = words_buffer(engine, "gaussian weights", &words, wgpu::BufferUsages::STORAGE);
        let plane = bands.iter().map(|&band| planes(blur, band)).max().unwrap_or(0);
        run(engine, &self.pipeline, (tiles, rect), (plane, room), &dispatches, Some(&weights))
    }
}
