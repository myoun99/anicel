//! The stamp path (gpu-canonical-store stage 5 and 11-06 05:35): a stamp
//! dab's pixels as the tiles of a stroke row — what the executor lays on
//! the cel (R28), at the row's opacity, in its mode and under its mask.
//! stamp.wgsl has why nothing else is needed to land one: R10's stamp
//! composite is that laying. A stamp is made of
//! - a mask in a paint: a fill's colour stamp (`_colorStampDab`), and a
//!   selection's erase (`selectionEraseDab`, 「⛔ONE ERASE」) — its mask's
//!   bytes for an alpha under a colour the eraser never reads, laid by the
//!   eraser;
//! - or a picture, a box of straight RGBA8 at a place: a lift's
//!   (cel_pixel/lift.rs) landing where it moved, or a warp's window
//!   (kernels/warp — `transformStampDab` · `carryStampDab` · the quad's and
//!   the mesh's).
//!
//! The row is every tile the box meets. The app cuts a fill into pieces of
//! the tiles it covers (`_stampPieces`) for its CPU's sake; here a tile it
//! covers none of is laid as nothing, and the write path keeps the cel's
//! tile there (`kernels/write`) — knowing which tiles those are before the
//! plan is made would wait for the GPU to say. The app clips a landing to
//! the pasteboard's wall: a picture says what the wall left of it (`within`),
//! a mask's box is made to it. ⛔Not the plan's extent, which cuts every row:
//! a cel laid past the wall (`laidBounds`) keeps what lies there.
//!
//! Under a gradient (I-160, `_gradientRgba`) each pixel is the gradient's
//! colour at its centre instead: this file turns the gradient's ends into
//! the integers stamp.wgsl reads — the one place they become integers —,
//! and makes its stops.

#[cfg(test)]
#[path = "stamp_tests.rs"]
pub(crate) mod tests;

use std::sync::OnceLock;

use super::landing::{self, Asked, Laid, Over};
use crate::device::Engine;
use crate::fail;
use crate::kernels::composite::{Composite, TILE, TILE_BYTES, TileAt, TileSet};
use crate::kernels::mask::{BYTE_WGSL, Mask};
use crate::kernels::mesh::{MeshGrid, MeshOwners};
use crate::kernels::pool::{Cel, Pool};
use crate::kernels::shared::{
    Encoded, PREMULTIPLY_WGSL, ResampleMap, ResampleMode, TILE_WGSL, WIDE_WGSL, encode, pipeline,
    plane, tiles_a_page, whole, words_buffer,
};
use crate::kernels::warp::{Boxed, Warp, Window};
use crate::kernels::write::{Change, Write};

/// The stops a gradient is looked up in, `FillGradient.stops`' count
/// (`_gradientStops`): four to each level a channel takes.
const STOPS: i32 = 1024;
/// How far from the canvas's corner a gradient's ends and a graded mask's
/// box may lie, in pixels: a pixel's offset from an end in 1/256 px is then
/// an i32, and stamp.wgsl's sums of two products of them stay under 2^62.
const GRADED_REACH: f64 = 65536.0;
const LINE: u32 = 1;
const CIRCLE: u32 = 2;

/// What a stamp is made of: `mask` in `paint` — a pixel the mask covers at
/// all wholly where `whole` (no feather was asked for: the app's
/// `takeWholePixels`, the erase the twin of the lift's gather), else its
/// byte for an alpha —, or `picture` at `at`.
pub(crate) enum Source<'a> {
    Mask {
        mask: &'a Mask<'a>,
        paint: &'a Paint<'a>,
        whole: bool,
    },
    Picture {
        picture: &'a Boxed<'a>,
        at: (i32, i32),
        /// What of the canvas it lands on — [left, top, right, bottom).
        within: [i32; 4],
    },
}

/// What a stamp lays under its mask: a colour (red, green, blue), or a
/// gradient's colour at each pixel.
pub(crate) enum Paint<'a> {
    Colour([u8; 3]),
    Gradient(&'a Gradient),
}

/// A fill's gradient (`FillGradient`), in canvas pixels: `start` at
/// `from`, `end` at `to` and past it — and, along a line, `start` behind
/// `from` —, each straight RGBA.
pub(crate) struct Gradient {
    pub(crate) shape: Shape,
    pub(crate) from: (f64, f64),
    pub(crate) to: (f64, f64),
    pub(crate) start: [u8; 4],
    pub(crate) end: [u8; 4],
}

/// `FillGradientShape` (유저 I-160-Q4 「직선 + 원형」).
#[derive(Clone, Copy)]
pub(crate) enum Shape {
    Line,
    Circle,
}

/// A stamp: its pages, each holding tiles of it slot after slot, and its
/// tiles on the canvas's grid at their pages and slots.
pub(crate) struct Stamped {
    pub(crate) pages: Vec<wgpu::Buffer>,
    pub(crate) set: TileSet,
}

/// stamp.wgsl's passes, compiled once.
pub(crate) struct Stamps {
    colour: wgpu::ComputePipeline,
    graded: wgpu::ComputePipeline,
    picture: wgpu::ComputePipeline,
}

/// What a stamp's pass reads: where its box lies, the box's words and the
/// pass that reads them, and the words past the tiles' (stamp.wgsl's
/// `Stamp` from `colour` on).
struct Read<'a> {
    at: (i32, i32),
    size: (u32, u32),
    stride: u32,
    given: &'a wgpu::Buffer,
    pipeline: &'a wgpu::ComputePipeline,
    rest: [u32; 8],
    stops: Option<wgpu::Buffer>,
}

impl Stamps {
    pub(crate) fn new(engine: &Engine) -> Self {
        let sources = [
            TILE_WGSL,
            WIDE_WGSL,
            PREMULTIPLY_WGSL,
            BYTE_WGSL,
            include_str!("stamp.wgsl"),
        ];
        Self {
            colour: pipeline(engine, &sources, "stamp_colour"),
            graded: pipeline(engine, &sources, "stamp_graded"),
            picture: pipeline(engine, &sources, "stamp_picture"),
        }
    }

    /// `source` — on the canvas — as the tiles of a row, on pages the plan
    /// will hold from its `first_page` on. Submits the work; the caller
    /// waits.
    pub(crate) fn stamp(
        &self,
        engine: &Engine,
        source: &Source,
        first_page: u16,
    ) -> Option<Stamped> {
        // A pass a page, a tile a workgroup deep.
        let most = tiles_a_page(engine)?;
        self.stamp_by(engine, source, first_page, most)
    }

    /// `stamp`, a page holding no more than `per_page` tiles — a test's
    /// fewer than the device's, to see a stamp go on to its next page.
    fn stamp_by(
        &self,
        engine: &Engine,
        source: &Source,
        first_page: u16,
        per_page: usize,
    ) -> Option<Stamped> {
        let read = self.read(engine, source)?;
        let set = TileSet::paged(read.at, read.size, first_page, per_page)?;
        let mut pages = Vec::new();
        let mut first = 0;
        while first < set.tiles.len() {
            let count = per_page.min(set.tiles.len() - first);
            let mut words = vec![
                read.at.0 as u32,
                read.at.1 as u32,
                read.size.0,
                read.size.1,
                read.stride,
                set.x0 as u32,
                set.y0 as u32,
                set.columns,
                first as u32,
            ];
            words.extend(read.rest);
            let words = &words_buffer(engine, "stamp", &words, wgpu::BufferUsages::UNIFORM);
            let page = plane(engine, "stamp page", count as u64 * TILE_BYTES);
            let side = TILE / 16;
            let mut bound = vec![(0, words), (1, read.given), (2, &page)];
            bound.extend(read.stops.as_ref().map(|stops| (3, stops)));
            encode(
                engine,
                &[Encoded {
                    pipeline: read.pipeline,
                    bound: whole(&bound),
                    groups: (side, side, count as u32),
                }],
            );
            pages.push(page);
            first += count;
        }
        Some(Stamped { pages, set })
    }

    /// What `source`'s passes read, or nothing where its buffer holds less
    /// than its box.
    fn read<'a>(&'a self, engine: &Engine, source: &Source<'a>) -> Option<Read<'a>> {
        match *source {
            Source::Mask { mask, paint, whole } => {
                mask.checked()?;
                let (pipeline, colour, ends, stops) = match paint {
                    Paint::Colour(colour) => (&self.colour, *colour, [0; 5], None),
                    Paint::Gradient(gradient) => {
                        let (ends, stops) = graded(gradient, mask)?;
                        let usage = wgpu::BufferUsages::STORAGE;
                        let stops = words_buffer(engine, "stops", &stops, usage);
                        (&self.graded, [0; 3], ends, Some(stops))
                    }
                };
                let [red, green, blue] = colour.map(u32::from);
                let [shape, from_x, from_y, along_x, along_y] = ends;
                Some(Read {
                    at: mask.at,
                    size: (mask.size.width, mask.size.height),
                    stride: mask.size.stride(),
                    given: mask.plane,
                    pipeline,
                    rest: [
                        red | green << 8 | blue << 16,
                        shape,
                        from_x,
                        from_y,
                        along_x,
                        along_y,
                        u32::from(whole),
                        0,
                    ],
                    stops,
                })
            }
            Source::Picture { picture, at, within } => {
                picture.checked()?;
                let (width, height) = (picture.size.0 as i32, picture.size.1 as i32);
                let left = at.0.max(within[0]);
                let top = at.1.max(within[1]);
                let right = (at.0 + width).min(within[2]);
                let bottom = (at.1 + height).min(within[3]);
                if right <= left || bottom <= top {
                    return fail(format!("nothing of a picture at {at:?} lies in {within:?}"));
                }
                let origin = (top - at.1) as u32 * picture.size.0 + (left - at.0) as u32;
                Some(Read {
                    at: (left, top),
                    size: ((right - left) as u32, (bottom - top) as u32),
                    stride: picture.size.0,
                    given: picture.pixels,
                    pipeline: &self.picture,
                    rest: [0, 0, 0, 0, 0, 0, 0, origin],
                    stops: None,
                })
            }
        }
    }
}

/// What lands a stamp on a cel: the stamp's passes and the write path's, and
/// the warp a picture is carried by on its way to one.
pub(crate) struct StampLanding {
    stamps: Stamps,
    write: Write,
    warp: Warp,
    /// Compiled where a mesh is first carried: the landing is compiled as
    /// the app launches, and a mesh's warp is the one most never make.
    owners: OnceLock<MeshOwners>,
}

impl StampLanding {
    /// Its kernels compiled — or nothing, where the device binds too few
    /// storage buffers a stage for them.
    pub(crate) fn new(engine: &Engine) -> Option<Self> {
        Some(Self {
            stamps: Stamps::new(engine),
            write: Write::new(engine)?,
            warp: Warp::new(engine),
            owners: OnceLock::new(),
        })
    }

    /// `picture` carried through `map`, the `window` of the output it maps
    /// to: what a box's affine or quad makes of a float (the app's
    /// `transformStampDab` · `transformStampDabQuad`, a window of it where
    /// only that much shows) and the picture a posed row's landing lays
    /// (`carryStampDab`), nothing of it where there is no map. Submits the
    /// warp; what lands the picture, or reads it, waits.
    ///
    /// 🗣️gpu-canonical-store ⑪ (관제 2026-11-10 18:14: 「자세 있음 … 선 =
    /// master 이하」): a float carried over a posed row shows as its landing
    /// at each step of the hand, and that landing crossed into the row on
    /// the CPU and came up again whole — 🔬55–68 ms of resample and 32–44 ms
    /// of upload a step for a 26.7 MB stamp, main PC, 2026-11-11. The
    /// float's picture is here once; the crossing is one pass over it.
    pub(crate) fn carried(
        &self,
        engine: &Engine,
        picture: &Boxed,
        map: Option<&ResampleMap>,
        window: Window,
    ) -> Option<wgpu::Buffer> {
        self.warp.one(engine, picture, map, window)
    }

    /// `picture`, its top-left pixel at `source_at` on the canvas, through
    /// `mesh`: the `window` of the canvas its triangles paint, each pixel by
    /// its triangle's map with `radius_floor` and `mode` (the app's
    /// `transformStampDabMesh`). Submits the warp; what lands the picture,
    /// or reads it, waits.
    pub(crate) fn meshed(
        &self,
        engine: &Engine,
        mesh: &MeshGrid,
        (picture, source_at): (&Boxed, (f64, f64)),
        window: Window,
        (radius_floor, mode): (f64, ResampleMode),
    ) -> Option<wgpu::Buffer> {
        let owners = self.owners.get_or_init(|| MeshOwners::new(engine));
        self.warp.mesh(engine, (owners, mesh), picture, source_at, window, radius_floor, mode)
    }

    /// Lays `source` on the tiles `asked`, each result compared with the
    /// tile under it and in a fresh slot of `cel` where it differs: a stamp
    /// is a finished landing (`landing::land`).
    pub(crate) fn land(
        &self,
        engine: &Engine,
        (composite, pool, cel): (&Composite, &mut Pool, Cel),
        source: &Source,
        asked: &[Asked],
        laid: &Laid,
    ) -> Option<Vec<(Change, Option<TileAt>)>> {
        if asked.is_empty() {
            return Some(Vec::new());
        }
        let Stamped { pages, set } = self.stamps.stamp(engine, source, pool.pages().len() as u16)?;
        let over = Over { pages: &pages, set };
        landing::land(engine, (composite, &self.write, pool, cel), over, asked, laid, true)
    }
}

/// `gradient` as stamp.wgsl reads it over `mask`: its shape, its `from` and
/// `to − from` in 1/256 px — each rounded once —, and its stops, each
/// channel start + round((end − start) · i / 1023): 1023 is odd, so no
/// share is a half and the rounding is the app's (`FillGradient.colorAt`).
/// Nothing where an end or the box lies past [`GRADED_REACH`].
fn graded(gradient: &Gradient, mask: &Mask) -> Option<([u32; 5], Vec<u32>)> {
    // No NaN or infinity is within a reach either.
    let fixed = |v: f64| (v.abs() <= GRADED_REACH).then(|| (v * 256.0).round());
    let ends = [gradient.from.0, gradient.from.1, gradient.to.0, gradient.to.1].map(fixed);
    let [Some(from_x), Some(from_y), Some(to_x), Some(to_y)] = ends else {
        return fail("a gradient's end lies past what its sums hold");
    };
    let (left, top) = (f64::from(mask.at.0), f64::from(mask.at.1));
    let (right, bottom) = (left + f64::from(mask.size.width), top + f64::from(mask.size.height));
    if [left, top, right, bottom].iter().any(|edge| edge.abs() > GRADED_REACH) {
        return fail("a graded mask's box lies past what its sums hold");
    }
    let shape = match gradient.shape {
        Shape::Line => LINE,
        Shape::Circle => CIRCLE,
    };
    let word = |v: f64| v as i32 as u32;
    let ends = [shape, word(from_x), word(from_y), word(to_x - from_x), word(to_y - from_y)];
    let stops = (0..STOPS)
        .map(|i| {
            let channel = |k: usize| {
                let (start, end) = (i32::from(gradient.start[k]), i32::from(gradient.end[k]));
                (start + (2 * (end - start) * i + STOPS - 1).div_euclid(2 * (STOPS - 1))) as u32
            };
            channel(0) | channel(1) << 8 | channel(2) << 16 | channel(3) << 24
        })
        .collect();
    Some((ends, stops))
}
