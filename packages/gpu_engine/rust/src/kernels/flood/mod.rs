//! A bucket fill's reach on the GPU (gpu-canonical-store stage 5): the
//! pixels a bucket fills — 4-joined to the seed through pixels within the
//! tolerance of the seed's colour — as a plane of bits, and their box;
//! then that finished as the app finishes an area, a mask of bytes over a
//! box of its own (`kernels/mask`'s grow and soften — the app's
//! `test/native/an_area_is_finished_as_the_bucket_is_test.dart` holds the
//! two to one another). A fill that closes gaps floods the same way over
//! what lies past its gap from every barrier, by `kernels/mask`'s
//! distances. ↩️Till 2026-11-12 the app flooded on the CPU as well
//! (`floodFillRegion` · `_gapCloseFloodRegion` · `_cropAndFinishFloodRegion`
//! in lib/src/services/canvas_flood_fill.dart, and qa_engine.c's wave);
//! where a comment here says 「the app's bytes」 it is those it means.
//! flood.wgsl has the planes and why any order of spreading gives the
//! app's bytes. What a fill finished is laid in its colour, or its
//! gradient's, as a stroke row on the stamp path (`dab::stamp`).
//!
//! The picture the fill reads is what the screen shows — the composite's
//! output tiles (유저 gpu-canonical-store-Q1, 11-06): the fill and the
//! eyedropper read one picture with the screen, blend modes, folders and
//! effects as they show, where the app summed the layers by a rule of its
//! own. `picture` makes it, and picks the eyedropper's pixel of it.

pub(crate) mod abi;
pub(crate) mod picture;
#[cfg(test)]
mod tests;

use crate::device::Engine;
use crate::fail;
use crate::kernels::composite::{TILE, TILE_BYTES};
use crate::kernels::mask::{MaskBox, MaskPasses};
use crate::kernels::shared::{Encoded, PREMULTIPLY_WGSL, encode, encode_on, fits};
use crate::kernels::shared::{flat, pipeline, plane, range, whole, words_buffer};

/// The rounds encoded between two looks at whether one moved nothing.
const ROUNDS: usize = 8;
/// The bytes between two rounds' flags: a storage binding's offset steps.
const FLAG_STEP: u64 = 256;
/// The widest gap a fill closes: 3 × it, its threshold, is a word.
const MOST_GAP: u32 = u32::MAX / 3;

/// The picture a fill reads: the composite's output tiles over a grid of
/// `across` × `down` tiles, row after row, and the box in the grid's pixels
/// it covers — a fill reaches nothing past it.
pub(crate) struct Picture<'a> {
    pub(crate) tiles: &'a wgpu::Buffer,
    pub(crate) across: u32,
    pub(crate) down: u32,
    pub(crate) inside: Extent,
}

/// A box of pixels: its left and top, and its right and bottom past it.
#[derive(Clone, Copy, Debug, PartialEq)]
pub(crate) struct Extent {
    pub(crate) left: u32,
    pub(crate) top: u32,
    pub(crate) right: u32,
    pub(crate) bottom: u32,
}

/// The pixels a flood filled: a plane of bits over the picture's grid,
/// `stride` words a row, inside the picture's box.
pub(crate) struct Flooded {
    pub(crate) filled: wgpu::Buffer,
    pub(crate) stride: u32,
    pub(crate) bounds: Bounds,
    pub(crate) inside: Extent,
}

/// A finished fill: the mask it lays its colour through, bytes over
/// `crop` (mask.wgsl's layout) — the app's `FloodFillRegion`.
pub(crate) struct Finished {
    pub(crate) mask: wgpu::Buffer,
    pub(crate) crop: Extent,
}

/// The filled pixels' least and most x and y — the app's `minX`, `maxX`,
/// `minY`, `maxY`. A flood fills its seed at least, so it is never empty.
#[derive(Clone, Copy, Debug, PartialEq)]
pub(crate) struct Bounds {
    pub(crate) left: u32,
    pub(crate) right: u32,
    pub(crate) top: u32,
    pub(crate) bottom: u32,
}

/// The passes, compiled once.
pub(crate) struct Flood {
    tolerance: wgpu::ComputePipeline,
    round: wgpu::ComputePipeline,
    bounds: wgpu::ComputePipeline,
    mask: wgpu::ComputePipeline,
    gap: wgpu::ComputePipeline,
    eroded: wgpu::ComputePipeline,
    regrown: wgpu::ComputePipeline,
}

/// What a flood starts from: its words, the plane of what may fill and
/// the two of what has filled — the first holding the seed —, a plane's
/// row of words and bytes, and the workgroups that put a plane's words.
struct Begun {
    words: wgpu::Buffer,
    fillable: wgpu::Buffer,
    filled: [wgpu::Buffer; 2],
    stride: u32,
    bytes: u64,
    groups: (u32, u32),
}

impl Flood {
    pub(crate) fn new(engine: &Engine) -> Self {
        let source = [PREMULTIPLY_WGSL, include_str!("flood.wgsl")];
        Self {
            tolerance: pipeline(engine, &source, "flood_tolerance"),
            round: pipeline(engine, &source, "flood_round"),
            bounds: pipeline(engine, &source, "flood_bounds"),
            mask: pipeline(engine, &source, "flood_mask"),
            gap: pipeline(engine, &source, "flood_gap"),
            eroded: pipeline(engine, &source, "flood_eroded"),
            regrown: pipeline(engine, &source, "flood_regrown"),
        }
    }

    /// What a fill seeded at `(x, y)` — the grid's pixels — reaches in
    /// `picture`, through pixels whose channels each lie within `tolerance`
    /// of the seed's. Waits for the GPU between rounds.
    pub(crate) fn region(
        &self,
        engine: &Engine,
        picture: &Picture,
        seed: (u32, u32),
        tolerance: u32,
    ) -> Option<Flooded> {
        let Begun {
            words,
            fillable,
            filled,
            stride,
            ..
        } = self.begin(engine, picture, seed, tolerance, 0)?;
        let filled = self.spread(engine, &words, &fillable, filled, picture)?;
        let bounds = self.bounds(engine, &words, &filled, (picture.across, picture.down))?;
        Some(Flooded {
            filled,
            stride,
            bounds,
            inside: picture.inside,
        })
    }

    /// What a fill seeded at `(x, y)` that closes gaps of `gap` pixels
    /// reaches in `picture`: it floods, as
    /// [`Flood::region`] does, only what lies farther than 3 × gap chamfer
    /// units from every pixel off the tolerance — the gap halved until the
    /// seed does —, so it leaks through no gap narrower than about twice
    /// that; then it takes back what may fill within as much of what it
    /// flooded. A gap of 0 floods as [`Flood::region`] does. Waits for the
    /// GPU between rounds.
    pub(crate) fn gap_closed(
        &self,
        engine: &Engine,
        masks: &MaskPasses,
        picture: &Picture,
        seed: (u32, u32),
        tolerance: u32,
        gap: u32,
    ) -> Option<Flooded> {
        if gap > MOST_GAP {
            return fail(format!("a gap of {gap} pixels is past {MOST_GAP}"));
        }
        let Begun {
            words,
            fillable,
            filled,
            stride,
            bytes,
            groups,
        } = self.begin(engine, picture, seed, tolerance, gap)?;
        let inside = picture.inside;
        let (may, size) = self.cropped(engine, &fillable, stride, inside)?;
        let barriers = masks.distances(engine, &may, size, 0, gap)?;
        let storage = wgpu::BufferUsages::STORAGE;
        let erode_past = words_buffer(engine, "flood erode past", &[0], storage);
        let eroded = plane(engine, "flood eroded", bytes);
        encode(
            engine,
            &[
                Encoded {
                    pipeline: &self.gap,
                    bound: whole(&[(0, &words), (10, &barriers), (11, &erode_past)]),
                    groups: (1, 1, 1),
                },
                Encoded {
                    pipeline: &self.eroded,
                    bound: whole(&[
                        (0, &words),
                        (1, &fillable),
                        (6, &eroded),
                        (10, &barriers),
                        (11, &erode_past),
                    ]),
                    groups: flat(groups),
                },
            ],
        );
        let flooded = self.spread(engine, &words, &eroded, filled, picture)?;
        let (reached, _) = self.cropped(engine, &flooded, stride, inside)?;
        let grown = masks.distances(engine, &reached, size, 255, gap)?;
        let filled = plane(engine, "flood filled", bytes);
        encode(
            engine,
            &[Encoded {
                pipeline: &self.regrown,
                bound: whole(&[
                    (0, &words),
                    (1, &fillable),
                    (3, &filled),
                    (10, &grown),
                    (11, &erode_past),
                ]),
                groups: flat(groups),
            }],
        );
        let bounds = self.bounds(engine, &words, &filled, (picture.across, picture.down))?;
        Some(Flooded {
            filled,
            stride,
            bounds,
            inside,
        })
    }

    /// The planes a flood seeded at `(x, y)` within `tolerance` starts
    /// from, its seed filled and what may fill put — where `picture` holds
    /// the seed. `gap` is the gap close's, 0 for a plain flood.
    fn begin(
        &self,
        engine: &Engine,
        picture: &Picture,
        (x, y): (u32, u32),
        tolerance: u32,
        gap: u32,
    ) -> Option<Begun> {
        let Picture {
            tiles,
            across,
            down,
            inside,
        } = *picture;
        let Extent {
            left,
            top,
            right,
            bottom,
        } = inside;
        if right > across * TILE || bottom > down * TILE {
            return fail(format!("{inside:?} is no box of {across} × {down} tiles"));
        }
        // A box that holds the seed holds a pixel at least (mutant r06,
        // 11-06: an empty box was refused twice).
        if x < left || x >= right || y < top || y >= bottom {
            return fail(format!("a seed at ({x}, {y}) is off the picture's {inside:?}"));
        }
        let picture_bytes = u64::from(across * down) * TILE_BYTES;
        if tiles.size() < picture_bytes {
            return fail(format!("{} bytes hold no {across} × {down} tiles", tiles.size()));
        }
        let stride = across * 4;
        let bytes = u64::from(stride) * u64::from(down * TILE) * 4;
        let words_groups = (stride.div_ceil(8), (down * TILE).div_ceil(8));
        let groups = [words_groups, (across, down)].into_iter();
        fits(engine, &[picture_bytes, bytes], groups)?;
        let words = [left, top, right, bottom, x, y, tolerance, across, down, stride, gap, 0];
        let words = words_buffer(engine, "flood", &words, wgpu::BufferUsages::UNIFORM);
        let fillable = plane(engine, "flood fillable", bytes);
        let filled = [0, 1].map(|_| plane(engine, "flood filled", bytes));
        encode(
            engine,
            &[Encoded {
                pipeline: &self.tolerance,
                bound: whole(&[(0, &words), (3, &filled[0]), (5, tiles), (6, &fillable)]),
                groups: flat(words_groups),
            }],
        );
        Some(Begun {
            words,
            fillable,
            filled,
            stride,
            bytes,
            groups: words_groups,
        })
    }

    /// `filled` — the first holding what has filled — spread through
    /// `fillable` round after round until one moves nothing, as `words`
    /// read; the plane the last round put. Waits for the GPU between rounds.
    fn spread(
        &self,
        engine: &Engine,
        words: &wgpu::Buffer,
        fillable: &wgpu::Buffer,
        filled: [wgpu::Buffer; 2],
        picture: &Picture,
    ) -> Option<wgpu::Buffer> {
        let tiles = (picture.across, picture.down);
        let flags = engine.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("flood moved"),
            size: FLAG_STEP * ROUNDS as u64,
            usage: wgpu::BufferUsages::STORAGE
                | wgpu::BufferUsages::COPY_SRC
                | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });
        let mut at = 0;
        loop {
            let mut encoder = engine
                .device
                .create_command_encoder(&wgpu::CommandEncoderDescriptor::default());
            encoder.clear_buffer(&flags, 0, None);
            let rounds: Vec<Encoded> = (0..ROUNDS)
                .map(|round| {
                    let (from, to) = (&filled[(at + round) % 2], &filled[(at + round + 1) % 2]);
                    let step = round as u64 * FLAG_STEP;
                    let mut bound = whole(&[(0, words), (1, fillable), (2, from), (3, to)]);
                    bound.push(wgpu::BindGroupEntry {
                        binding: 4,
                        resource: range(&flags, step..step + 4),
                    });
                    Encoded {
                        pipeline: &self.round,
                        bound,
                        groups: flat(tiles),
                    }
                })
                .collect();
            encode_on(engine, &mut encoder, &rounds);
            engine.queue.submit([encoder.finish()]);
            at = (at + ROUNDS) % 2;
            let moved = engine.read_buffer(&flags)?;
            let still = (0..ROUNDS).any(|round| {
                let step = round * FLAG_STEP as usize;
                moved[step..step + 4] == [0; 4]
            });
            if still {
                break;
            }
        }
        filled.into_iter().nth(at)
    }

    /// `flooded` finished as a fill is: cropped to its box grown by what the
    /// finish reaches (`fillFinishReach` — the expand, and a pixel more
    /// where it anti-aliases: its ramp spreads a pixel past its own edge),
    /// cut at the picture's box, then grown `expand` generations and
    /// softened past its outline where it anti-aliases. Submits the work;
    /// the caller waits.
    pub(crate) fn finish(
        &self,
        engine: &Engine,
        masks: &MaskPasses,
        flooded: &Flooded,
        expand: u32,
        anti_alias: bool,
    ) -> Option<Finished> {
        let (bounds, inside) = (flooded.bounds, flooded.inside);
        let reach = expand.saturating_add(u32::from(anti_alias));
        // The bounds' right and bottom are the last pixels filled; the
        // crop's lie past its own.
        let past = reach.saturating_add(1);
        let crop = Extent {
            left: bounds.left.saturating_sub(reach).max(inside.left),
            top: bounds.top.saturating_sub(reach).max(inside.top),
            right: bounds.right.saturating_add(past).min(inside.right),
            bottom: bounds.bottom.saturating_add(past).min(inside.bottom),
        };
        let (cropped, size) = self.cropped(engine, &flooded.filled, flooded.stride, crop)?;
        let mask = if expand == 0 && !anti_alias {
            cropped
        } else {
            masks.fill(engine, &cropped, size, expand, anti_alias)?
        };
        Some(Finished { mask, crop })
    }

    /// `bits` — a plane of bits, `stride` words a row — as a mask of bytes
    /// over `crop`, 255 where a bit is set and 0 where not: what a fill is
    /// finished from, and what the gap close measures distances over.
    /// Submits the work; the caller waits.
    fn cropped(
        &self,
        engine: &Engine,
        bits: &wgpu::Buffer,
        stride: u32,
        crop: Extent,
    ) -> Option<(wgpu::Buffer, MaskBox)> {
        let size = MaskBox {
            width: crop.right - crop.left,
            height: crop.bottom - crop.top,
        };
        let groups = (size.stride().div_ceil(8), size.height.div_ceil(8));
        fits(engine, &[size.bytes()], [groups].into_iter())?;
        let words = [crop.left, crop.top, size.width, size.height, stride, size.stride(), 0, 0];
        let words = &words_buffer(engine, "flood crop", &words, wgpu::BufferUsages::UNIFORM);
        let cropped = plane(engine, "flood mask", size.bytes());
        encode(
            engine,
            &[Encoded {
                pipeline: &self.mask,
                bound: whole(&[(2, bits), (8, words), (9, &cropped)]),
                groups: flat(groups),
            }],
        );
        Some((cropped, size))
    }

    /// The box of what `filled` holds.
    fn bounds(
        &self,
        engine: &Engine,
        words: &wgpu::Buffer,
        filled: &wgpu::Buffer,
        tiles: (u32, u32),
    ) -> Option<Bounds> {
        let usage = wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC;
        let bounds = words_buffer(engine, "flood bounds", &[u32::MAX, 0, u32::MAX, 0], usage);
        encode(
            engine,
            &[Encoded {
                pipeline: &self.bounds,
                bound: whole(&[(0, words), (2, filled), (7, &bounds)]),
                groups: flat(tiles),
            }],
        );
        let read = engine.read_buffer(&bounds)?;
        let [left, right, top, bottom] =
            [0, 1, 2, 3].map(|k| u32::from_le_bytes(read[k * 4..k * 4 + 4].try_into().unwrap()));
        if left > right {
            return fail("a flood filled nothing, not even its seed");
        }
        Some(Bounds {
            left,
            right,
            top,
            bottom,
        })
    }
}
