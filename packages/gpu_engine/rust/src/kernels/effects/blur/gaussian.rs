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
//! A way's three passes go in one dispatch, a strip of them a workgroup, in
//! its memory (three.wgsl), where a strip has room; past that room, a pass a
//! dispatch (gpu-canonical-store 01:15 (b)). Both put the same pixels.
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

/// The box law every blur of box passes runs: box.wgsl's `blur_mean` and
/// `blur_slide`, and the `BoxPass` it reads.
pub(crate) const BOX_WGSL: &str = include_str!("box.wgsl");
/// A way's three passes in one dispatch, over strips in a workgroup's
/// memory: three.wgsl's `blur_way`, for what includes it to load and store.
pub(crate) const THREE_WGSL: &str = include_str!("three.wgsl");
/// A pass a dispatch, a thread sliding its sum along a run: pass.wgsl's
/// `blur_run`, for what includes it to tap and put.
pub(crate) const PASS_WGSL: &str = include_str!("pass.wgsl");
/// The words of one `BoxPass`.
pub(crate) const PASS_WORDS: usize = 9;

/// The widest box: a pass sums 2·radius + 1 pixels of 65535 at most, and
/// the sum stays a u32.
pub(crate) const MOST_RADIUS: u32 = 32767;
/// pass.wgsl's BLUR_RUN — the pixels one thread slides its sum along.
const RUN: u32 = 64;
/// three.wgsl's BLUR_ROOM: the pixels a workgroup's strip holds.
const ROOM: i32 = 1024;
/// gaussian_three.wgsl's words: a way's three passes, then its strips'
/// lines and run — whole vec4s, as a uniform holds them.
const THREE_WORDS: usize = 32;
/// The widest box the Gaussian goes by strips. Past it a pass a dispatch is
/// the faster: a strip's lanes each sum 2r + 1 pixels before sliding over a
/// run of a few, and those sums outgrow what one dispatch a way saves
/// (11-06, the main PC's GPU, a 2048² picture, strips against a pass a
/// dispatch — r 50: 1.9 ms, 2.3; r 56: 1.9, 2.4; r 64: 2.5–2.8, 2.3–2.4;
/// r 120: 5.5, 2.7; r 170: 396, 3.4). Lanes summing runs of r or more
/// instead were nowhere faster, and slower from r 32 on.
const MOST_STRIPS_RADIUS: u32 = 56;

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

/// One pass: along the rows or down the columns, the pixels it writes —
/// [first, end) along, lines [line_first, line_end) across — and its edge
/// along.
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
    /// box.wgsl's `BoxPass`.
    fn words(&self) -> [u32; PASS_WORDS] {
        [
            u32::from(self.down),
            self.radius,
            self.along[0] as u32,
            self.along[1] as u32,
            self.lines[0] as u32,
            self.lines[1] as u32,
            self.edge,
            self.edge_along[0] as u32,
            self.edge_along[1] as u32,
        ]
    }

    /// What it reads along: a radius past what it writes, each side.
    fn reads(&self) -> [i32; 2] {
        let r = self.radius as i32;
        [self.along[0] - r, self.along[1] + r]
    }

    /// Its own dispatch (pass.wgsl).
    fn dispatch(&self) -> Dispatch {
        let runs = ((self.along[1] - self.along[0]) as u32).div_ceil(RUN);
        let lines = (self.lines[1] - self.lines[0]) as u32;
        Dispatch {
            from: self.from,
            to: self.to,
            words: self.words().to_vec(),
            groups: (runs.div_ceil(GROUP), lines.div_ceil(GROUP)),
        }
    }
}

/// A way's three passes cut into strips of a workgroup each (three.wgsl's
/// `blur_way`): the lines one takes and the run along, and the workgroups,
/// along by across.
#[derive(Clone, Copy, Debug)]
pub(crate) struct Strips {
    pub(crate) lines: u32,
    pub(crate) run: u32,
    pub(crate) groups: (u32, u32),
}

/// The strips of `way`, its three passes: each runs as far along as its
/// room holds past what the first pass reads beyond what the last puts, on
/// as many lines as fit — none where that leaves no room.
fn strips(way: &[Pass]) -> Option<Strips> {
    let (first, last) = (way.first()?, way.last()?);
    let reads = first.reads();
    let along = last.along[1] - last.along[0];
    let halo = reads[1] - reads[0] - along;
    let run = along.min(ROOM - halo);
    if run < 1 {
        return None;
    }
    let lines = (ROOM / (run + halo)) as u32;
    let across = (first.lines[1] - first.lines[0]) as u32;
    Some(Strips {
        lines,
        run: run as u32,
        groups: ((along as u32).div_ceil(run as u32), across.div_ceil(lines)),
    })
}

/// The one dispatch of `way`'s three passes over `strips`
/// (gaussian_three.wgsl).
fn three(way: &[Pass], strips: Strips) -> Dispatch {
    let mut words: Vec<u32> = way.iter().flat_map(Pass::words).collect();
    words.extend([strips.lines, strips.run]);
    words.resize(THREE_WORDS, 0);
    Dispatch {
        from: way[0].from,
        to: way[2].to,
        words,
        groups: strips.groups,
    }
}

/// How a blur's passes go: a way's three in one dispatch where a strip of
/// them has room and a box is no wider than MOST_STRIPS_RADIUS — a pass a
/// dispatch past that — or every pass a dispatch, as the tests send them
/// too, to see both put the same pixels.
#[derive(Clone, Copy)]
enum Route {
    Strips,
    Passes,
}

/// The Gaussian's passes, compiled once: a pass a dispatch, and a way's
/// three in one.
pub(crate) struct BoxBlur {
    pass: wgpu::ComputePipeline,
    three: wgpu::ComputePipeline,
}

impl BoxBlur {
    pub(crate) fn new(engine: &Engine) -> Self {
        let gaussian = include_str!("gaussian.wgsl");
        Self {
            pass: compile(
                engine,
                &[BOX_WGSL, PASS_WGSL, gaussian],
                include_str!("gaussian_pass.wgsl"),
                "box_blur",
            ),
            three: compile(
                engine,
                &[BOX_WGSL, THREE_WGSL, gaussian],
                include_str!("gaussian_three.wgsl"),
                "box_three",
            ),
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
        self.run_by(engine, tiles, rect, radius, edge, Route::Strips)
    }

    /// `run`, the passes going by `route`.
    fn run_by(
        &self,
        engine: &Engine,
        tiles: &wgpu::Buffer,
        rect: TileRect,
        radius: (u32, u32),
        edge: Edge,
        route: Route,
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
        let passes = passes(picture, radius, kind);
        let ways: Vec<&[Pass]> = passes.chunks(3).collect();
        let strips: Option<Vec<Strips>> = ways
            .iter()
            .map(|way| strips(way).filter(|_| way[0].radius <= MOST_STRIPS_RADIUS))
            .collect();
        let (pipeline, dispatches): (_, Vec<Dispatch>) = match (route, strips) {
            (Route::Strips, Some(strips)) => (
                &self.three,
                ways.iter().zip(strips).map(|(way, strips)| three(way, strips)).collect(),
            ),
            _ => (&self.pass, passes.iter().map(Pass::dispatch).collect()),
        };
        run(engine, pipeline, tiles, rect, planes(picture, radius), &dispatches, None)
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

/// The passes blurring a picture by a radius either way where past it lie
/// real pixels, read as they are: the blur brush's dab (kernels/dab/blur.rs),
/// whose window holds the picture three radii past the dab each side.
pub(crate) struct Within {
    /// box.wgsl's `BoxPass` for each, the rows' three first.
    pub(crate) words: Vec<u32>,
    /// Each way cut into strips — none where a strip has no room.
    pub(crate) rows: Option<Strips>,
    pub(crate) columns: Option<Strips>,
    /// Each pass's workgroups, gone a pass a dispatch (pass.wgsl).
    pub(crate) groups: Vec<(u32, u32)>,
}

/// The passes blurring `picture` by `radius` within real pixels: the
/// columns' three down the picture, and the rows' three along its columns
/// on every line the columns' first reads — none for a radius of 0.
pub(crate) fn within(picture: [i32; 4], radius: u32) -> Option<Within> {
    let [left, _, right, _] = picture;
    let columns = passes(picture, (0, radius), EDGE_NONE);
    let [top, bottom] = columns.first()?.reads();
    let rows = passes([left, top, right, bottom], (radius, 0), EDGE_NONE);
    Some(Within {
        rows: strips(&rows),
        columns: strips(&columns),
        words: rows.iter().chain(&columns).flat_map(Pass::words).collect(),
        groups: rows.iter().chain(&columns).map(|pass| pass.dispatch().groups).collect(),
    })
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
