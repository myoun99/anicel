//! A bucket fill's reach on the GPU (gpu-canonical-store stage 5): the
//! pixels the app's `floodFillRegion` fills — 4-joined to the seed through
//! pixels within the tolerance of the seed's colour — as a plane of bits,
//! and their box; then that finished as the app finishes it, a mask of
//! bytes over a box of its own (`kernels/mask`'s grow and soften).
//! flood.wgsl has the planes and why any order of spreading gives the
//! app's bytes.
//!
//! The picture the fill reads is what the screen shows — the composite's
//! output tiles (유저 gpu-canonical-store-Q1, 11-06): the fill and the
//! eyedropper read one picture with the screen, blend modes, folders and
//! effects as they show, where the app summed the layers by a rule of its
//! own.

// ⏳Nothing outside the tests floods until the fill comes to the engine
// (gpu-canonical-store, stage 5's connection).
#![cfg_attr(not(test), allow(dead_code))]

#[cfg(test)]
mod tests;

use crate::device::Engine;
use crate::fail;
use crate::kernels::composite::{TILE, TILE_BYTES};
use crate::kernels::mask::{MaskBox, MaskPasses};
use crate::kernels::shared::{Encoded, PREMULTIPLY_WGSL, encode, encode_on, fits, flat};
use crate::kernels::shared::{pipeline, plane, range, whole, words_buffer};

/// The rounds encoded between two looks at whether one moved nothing.
const ROUNDS: usize = 8;
/// The bytes between two rounds' flags: a storage binding's offset steps.
const FLAG_STEP: u64 = 256;

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
}

impl Flood {
    pub(crate) fn new(engine: &Engine) -> Self {
        let source = [PREMULTIPLY_WGSL, include_str!("flood.wgsl")];
        Self {
            tolerance: pipeline(engine, &source, "flood_tolerance"),
            round: pipeline(engine, &source, "flood_round"),
            bounds: pipeline(engine, &source, "flood_bounds"),
            mask: pipeline(engine, &source, "flood_mask"),
        }
    }

    /// What a fill seeded at `(x, y)` — the grid's pixels — reaches in
    /// `picture`, through pixels whose channels each lie within `tolerance`
    /// of the seed's. Waits for the GPU between rounds.
    pub(crate) fn region(
        &self,
        engine: &Engine,
        picture: &Picture,
        (x, y): (u32, u32),
        tolerance: u32,
    ) -> Option<Flooded> {
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
        let words = [left, top, right, bottom, x, y, tolerance, across, down, stride, 0, 0];
        let words = &words_buffer(engine, "flood", &words, wgpu::BufferUsages::UNIFORM);
        let fillable = plane(engine, "flood fillable", bytes);
        let filled = [0, 1].map(|_| plane(engine, "flood filled", bytes));
        encode(
            engine,
            &[Encoded {
                pipeline: &self.tolerance,
                bound: whole(&[(0, words), (3, &filled[0]), (5, tiles), (6, &fillable)]),
                groups: flat(words_groups),
            }],
        );
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
                    let mut bound = whole(&[(0, words), (1, &fillable), (2, from), (3, to)]);
                    bound.push(wgpu::BindGroupEntry {
                        binding: 4,
                        resource: range(&flags, step..step + 4),
                    });
                    Encoded {
                        pipeline: &self.round,
                        bound,
                        groups: flat((across, down)),
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
        let filled = filled.into_iter().nth(at)?;
        let bounds = self.bounds(engine, words, &filled, (across, down))?;
        Some(Flooded {
            filled,
            stride,
            bounds,
            inside,
        })
    }

    /// `flooded` finished as the app finishes a fill
    /// (`_cropAndFinishFloodRegion`): cropped to its box grown by what the
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
        let size = MaskBox {
            width: crop.right - crop.left,
            height: crop.bottom - crop.top,
        };
        let groups = (size.stride().div_ceil(8), size.height.div_ceil(8));
        fits(engine, &[size.bytes()], [groups].into_iter())?;
        let words = [
            crop.left,
            crop.top,
            size.width,
            size.height,
            flooded.stride,
            size.stride(),
            0,
            0,
        ];
        let words = &words_buffer(engine, "flood crop", &words, wgpu::BufferUsages::UNIFORM);
        let cropped = plane(engine, "flood mask", size.bytes());
        encode(
            engine,
            &[Encoded {
                pipeline: &self.mask,
                bound: whole(&[(2, &flooded.filled), (8, words), (9, &cropped)]),
                groups: flat(groups),
            }],
        );
        let mask = if expand == 0 && !anti_alias {
            cropped
        } else {
            masks.fill(engine, &cropped, size, expand, anti_alias)?
        };
        Some(Finished { mask, crop })
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
