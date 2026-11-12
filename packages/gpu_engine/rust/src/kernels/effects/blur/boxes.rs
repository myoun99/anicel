//! The blur brush's box law (I-75 흐리기 — `BrushBlurPicture.blurDab`,
//! its `_box`): three boxes along the rows, then three down
//! the columns, a pass's mean rounded half up (box.wgsl). The dab
//! (kernels/dab/blur.rs) runs them over a window that holds the picture
//! three radii past it each side, so a pass reads real pixels wherever it
//! reads ([`within`]).
//!
//! A way's three passes go in one dispatch, a strip of them a workgroup, in
//! its memory (three.wgsl), where a strip has room; past that room, a pass a
//! dispatch (pass.wgsl, gpu-canonical-store 01:15 (b)). Both put the same
//! pixels.
//!
//! ↩️The fx Gaussian went by these boxes too (gpu-canonical-store ⑦, 관제
//! 11-05 12:19), till the user chose the Gaussian itself for it (🗣️유저
//! gpu-canonical-store-Q2, 2026-11-08 — `gaussian`), and with it went what
//! only it read: an edge a pass reads past the picture by.

use super::{Dispatch, GROUP, Held};

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
pub(crate) const PASS_WORDS: usize = 6;

/// pass.wgsl's BLUR_RUN — the pixels one thread slides its sum along.
const RUN: u32 = 64;
/// three.wgsl's BLUR_ROOM: the pixels a workgroup's strip holds.
const ROOM: i32 = 1024;

/// One pass: along the rows or down the columns, the pixels it writes —
/// [first, end) along, lines [line_first, line_end) across.
struct Pass {
    down: bool,
    radius: u32,
    along: [i32; 2],
    lines: [i32; 2],
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

/// The passes blurring `picture`, [left, top, right, bottom), by `radius`
/// across and down: three along the rows, then three down the columns, a
/// way of radius 0 taking none. The k-th of a way writes (3 − k) radii past
/// the picture each side, all the k + 1-th reads. The first of all reads
/// the tiles, the last puts them; between, the planes hold the 16-bit
/// pixels.
fn passes(picture: [i32; 4], radius: (u32, u32)) -> Vec<Pass> {
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
    let columns = passes(picture, (0, radius));
    let [top, bottom] = columns.first()?.reads();
    let rows = passes([left, top, right, bottom], (radius, 0));
    Some(Within {
        rows: strips(&rows),
        columns: strips(&columns),
        words: rows.iter().chain(&columns).flat_map(Pass::words).collect(),
        groups: rows.iter().chain(&columns).map(|pass| pass.dispatch().groups).collect(),
    })
}
