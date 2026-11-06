//! fx Camera Lens Blur — the app's row_sum.frag, iris_table.frag and
//! iris_gather.frag with lens_light.glsl (`rowSumPasses`,
//! `IrisGatherPass`, `LensLight`), by gpu-int-spec-canvas 1b (4/4): every
//! pixel of the picture the exact sum of its row up to it, each read
//! through the light (`LensSums`); the iris's rows (iris.rs); and each
//! pixel the mean of the pixels its iris covers, each row of it two reads
//! of those sums, stored back through the light (`LensBlur`).
//!
//! 📐The light is worked on held.wgsl's 16-bit scale, where 1b (4/4) had
//! Q.16: so a pixel read with no light is read as the other blurs read it
//! (캔버스 베이스 11-05 — the threshold is a channel, 65535 at one).

#[cfg(test)]
#[path = "lens_tests.rs"]
mod tests;
#[cfg(test)]
#[path = "gather_tests.rs"]
mod gather_tests;

use super::iris::{Focus, Iris, IrisTable};
use super::{
    Encoded, GROUP, Held, TileRect, bands, checked, compile, encode, fits, flat, held_words,
    plane, whole, words_buffer,
};
use crate::device::Engine;
use crate::fail;
use crate::kernels::composite::TILE_TEXELS;
use crate::kernels::shared::{PREMULTIPLY_WGSL, WIDE_WGSL, q, room};

/// The most gain a light takes — the app's Highlight Gain's.
pub(crate) const MOST_GAIN: f64 = 100.0;
/// The most fringe a lens takes — the app's Diffraction Fringe's.
pub(crate) const MOST_FRINGE: f64 = 500.0;
/// gather.wgsl's `Gather`: the light's four words and seventeen of its own.
const GATHER_WORDS: usize = 21;
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
        let laid = self.lay(engine, tiles, (rect, room(engine)), picture, light)?;
        let [sums, totals] = sums_planes(engine, laid.bytes);
        encode(engine, &self.passes(tiles, &laid, [&sums, &totals]));
        Some(sums)
    }

    /// The sums' two passes over `picture` as `run` lays them, on bindings
    /// of `room` bytes — none where it refuses them.
    fn lay(
        &self,
        engine: &Engine,
        tiles: &wgpu::Buffer,
        (rect, room): (TileRect, u64),
        picture: [i32; 4],
        light: Light,
    ) -> Option<Sums> {
        let light_words = summed(rect, picture, light)?;
        let [left, top, ..] = picture;
        let (width, rows) = sums_rows(picture);
        let runs = width.div_ceil(RUN);
        let groups = (runs.div_ceil(GROUP), rows.div_ceil(GROUP));
        let bytes = sums_bytes(picture);
        checked(engine, tiles, (rect, room), &bytes, [groups].into_iter())?;
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
        Some(Sums {
            bytes,
            held,
            own,
            groups,
        })
    }

    /// The sums' two passes as `lay` laid them, into `sums` and `totals` —
    /// planes that hold at least its bytes.
    fn passes<'a>(
        &'a self,
        tiles: &'a wgpu::Buffer,
        laid: &'a Sums,
        [sums, totals]: [&'a wgpu::Buffer; 2],
    ) -> [Encoded<'a>; 2] {
        let Sums { held, own, groups, .. } = laid;
        [
            Encoded {
                pipeline: &self.runs,
                bound: whole(&[(0, held), (1, tiles), (2, sums), (3, own), (4, totals)]),
                groups: flat(*groups),
            },
            Encoded {
                pipeline: &self.carry,
                bound: whole(&[(0, held), (2, sums), (3, own), (4, totals)]),
                groups: flat(*groups),
            },
        ]
    }
}

/// A picture's row sums as their passes lay them: the plane's bytes and
/// the totals', and the passes' words and workgroups.
struct Sums {
    bytes: [u64; 2],
    held: wgpu::Buffer,
    own: wgpu::Buffer,
    groups: (u32, u32),
}

/// The light's words where `rect` holds `picture` and the light is in its
/// range — what sums take — or none.
fn summed(rect: TileRect, picture: [i32; 4], light: Light) -> Option<[u32; 4]> {
    if !rect.holds(picture) {
        return fail(format!("{picture:?} is no picture inside {rect:?}"));
    }
    let Some(words) = light.words() else {
        return fail(format!("{light:?} is past what a light takes"));
    };
    Some(words)
}

/// A plane of sums and one of totals, of `bytes` each.
fn sums_planes(engine: &Engine, bytes: [u64; 2]) -> [wgpu::Buffer; 2] {
    [plane(engine, "lens sums", bytes[0]), plane(engine, "lens run totals", bytes[1])]
}

/// A picture's width and rows.
fn sums_rows(picture: [i32; 4]) -> (u32, u32) {
    let [left, top, right, bottom] = picture;
    ((right - left) as u32, (bottom - top) as u32)
}

/// The bytes the sums of `picture` hold, and its runs' totals.
fn sums_bytes(picture: [i32; 4]) -> [u64; 2] {
    let (width, rows) = sums_rows(picture);
    let runs = width.div_ceil(RUN);
    [
        u64::from(width) * u64::from(rows) * SUM_BYTES,
        u64::from(runs) * u64::from(rows) * TOTAL_BYTES,
    ]
}

/// What of a blur map's pixel names its level — the app's
/// `IrisMapChannel`: one of its channels, or its luma. Each is gather.wgsl's
/// word for it (MAP_LUMA).
#[derive(Clone, Copy, Debug)]
pub(crate) enum MapChannel {
    Red = 0,
    Green = 1,
    Blue = 2,
    Alpha = 3,
    Luminance = 4,
}

/// A blur map — the app's `IrisMap`: its tiles — straight RGBA8 over the
/// blur's own rectangle as the kernel reads them, or what a chain draws
/// them from (kernels/chain) —, the channel it is read through, and its
/// focus.
#[derive(Clone, Copy)]
pub(crate) struct BlurMap<T> {
    pub(crate) tiles: T,
    pub(crate) channel: MapChannel,
    pub(crate) focus: Focus,
}

/// A camera lens blur's settings — the app's `IrisGatherPass` but its map:
/// its iris and radius (raster pixels), its fringe (0 to 500), its light,
/// and the paper, [left, top, right, bottom), whose edge pixels it repeats
/// past it — or none, where past the picture there is nothing.
#[derive(Clone, Copy, Debug)]
pub(crate) struct Lens {
    pub(crate) iris: Iris,
    pub(crate) radius: f64,
    pub(crate) fringe: f64,
    pub(crate) light: Light,
    pub(crate) paper: Option<[i32; 4]>,
}

/// fx Camera Lens Blur, whole: its sums, its iris's table and the gather,
/// compiled once.
pub(crate) struct LensBlur {
    sums: LensSums,
    table: IrisTable,
    gather: wgpu::ComputePipeline,
}

impl LensBlur {
    pub(crate) fn new(engine: &Engine) -> Self {
        let more = [WIDE_WGSL, PREMULTIPLY_WGSL, include_str!("light.wgsl")];
        Self {
            sums: LensSums::new(engine),
            table: IrisTable::new(engine),
            gather: compile(engine, &more, include_str!("gather.wgsl"), "iris_gather"),
        }
    }

    /// Blurs `tiles` — straight RGBA8 over `rect` — by `lens` over the
    /// `picture`, [left, top, right, bottom) inside them, each pixel at the
    /// level `map` names where there is one. Returns the blurred tiles over
    /// the same rectangle, nothing outside the picture — or the paper, where
    /// the lens repeats it. Submits the work; the caller waits.
    pub(crate) fn run(
        &self,
        engine: &Engine,
        tiles: &wgpu::Buffer,
        rect: TileRect,
        picture: [i32; 4],
        lens: &Lens,
        map: Option<BlurMap<&wgpu::Buffer>>,
    ) -> Option<wgpu::Buffer> {
        self.run_in(engine, tiles, rect, picture, (lens, map), room(engine))
    }

    /// `run`, in bands whose sums a binding of `room` bytes holds
    /// ([`bands`]): a band's sums are its rows and the iris's reach past
    /// them each side, inside the picture — every row its gather reads —,
    /// one plane of them each band's in turn.
    fn run_in(
        &self,
        engine: &Engine,
        tiles: &wgpu::Buffer,
        rect: TileRect,
        picture: [i32; 4],
        (lens, map): (&Lens, Option<BlurMap<&wgpu::Buffer>>),
        room: u64,
    ) -> Option<wgpu::Buffer> {
        let in_range = (0.0..=MOST_FRINGE).contains(&lens.fringe);
        let fringe = in_range.then(|| q(lens.fringe / MOST_FRINGE, 16, f64::MAX));
        let Some(fringe) = fringe.flatten() else {
            return fail(format!("a fringe of {} is past 0 to {MOST_FRINGE}", lens.fringe));
        };
        let paper = lens.paper.unwrap_or(picture);
        let [left, top, right, bottom] = picture;
        let within = paper[0] >= left && paper[1] >= top && paper[2] <= right && paper[3] <= bottom;
        if paper[0] >= paper[2] || paper[1] >= paper[3] || !within {
            return fail(format!("{paper:?} is no paper inside the picture {picture:?}"));
        }
        if map.is_some_and(|map| map.tiles.size() < rect.tiles() * TILE_TEXELS * 4) {
            return fail(format!("a blur map's tiles hold less than {rect:?}"));
        }
        // Bound whole, as the tiles are ([`checked`]).
        if let Some(map) = map.filter(|map| map.tiles.size() > room) {
            let bytes = map.tiles.size();
            return fail(format!("a blur map's tiles of {bytes} bytes exceed a binding of {room}"));
        }
        let light = summed(rect, picture, lens.light)?;
        let laid = self.table.run(engine, lens.iris, lens.radius, map.map(|map| map.focus))?;
        let reach = laid.reach as i32;
        let sums_over = |[first, end]: [i32; 2]| {
            [left, top.max(first - reach), right, bottom.min(end + reach)]
        };
        let Some(bands) = bands([top, bottom], |band| sums_bytes(sums_over(band))[0] <= room)
        else {
            let row = sums_bytes(sums_over([top, top + 1]))[0];
            return fail(format!("a band of one row sums {row} bytes, past a binding of {room}"));
        };
        let width = (right - left) as u32;
        let groups = |[first, end]: [i32; 2]| {
            (width.div_ceil(GROUP), ((end - first) as u32).div_ceil(GROUP))
        };
        fits(engine, &[], bands.iter().copied().map(groups))?;
        let sums: Vec<Sums> = bands
            .iter()
            .map(|&band| self.sums.lay(engine, tiles, (rect, room), sums_over(band), lens.light))
            .collect::<Option<_>>()?;
        let most = [0, 1].map(|k| sums.iter().map(|laid| laid.bytes[k]).max().unwrap_or(0));
        let planes = sums_planes(engine, most);
        let mut own = light.to_vec();
        own.extend(picture.iter().chain(&paper).map(|&edge| edge as u32));
        own.extend([u32::from(lens.paper.is_some()), fringe as u32, laid.reach, laid.rows]);
        own.extend([laid.levels, map.map_or(0, |map| map.channel as u32)]);
        let uniform = wgpu::BufferUsages::UNIFORM;
        let gathers: Vec<wgpu::Buffer> = bands
            .iter()
            .map(|&band| {
                let mut own = own.clone();
                own.extend([sums_over(band)[1], band[0], band[1]].map(|edge| edge as u32));
                debug_assert_eq!(own.len(), GATHER_WORDS);
                words_buffer(engine, "lens gather", &own, uniform)
            })
            .collect();
        let held = held_words(Held::Tiles, Held::Tiles, rect);
        let held = words_buffer(engine, "lens held", &held, uniform);
        // Nothing outside the pixels the gather puts.
        let out = plane(engine, "lens blur out", rect.tiles() * TILE_TEXELS * 4);
        let map_tiles = map.map_or(tiles, |map| map.tiles);
        // A band's sums, then its gather out of them — the next band's sums
        // go in the same plane after it.
        let encoded: Vec<Encoded> = bands
            .iter()
            .zip(&sums)
            .zip(&gathers)
            .flat_map(|((&band, laid_sums), own)| {
                let bound = [
                    (0, &held),
                    (1, tiles),
                    (2, &out),
                    (3, own),
                    (4, &planes[0]),
                    (5, &laid.table),
                    (6, map_tiles),
                ];
                let gather = Encoded {
                    pipeline: &self.gather,
                    bound: whole(&bound),
                    groups: flat(groups(band)),
                };
                let [runs, carry] = self.sums.passes(tiles, laid_sums, [&planes[0], &planes[1]]);
                [runs, carry, gather]
            })
            .collect();
        encode(engine, &encoded);
        Some(out)
    }
}
