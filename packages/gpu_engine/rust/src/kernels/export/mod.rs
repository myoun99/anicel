//! The export's conversions before the readback (gpu-export-path ①, 저장):
//! a frame the composite left in its output tiles, turned on the GPU into
//! the bytes its writer takes, so fewer cross to the CPU — the readback
//! was the largest single cost (960×540: 27 ms against the encoder's 5.5).
//!
//! - `nv12` — a movie's frame for its encoder (①a).
//! - `over_ground` — a still's frame over its format's background, for the
//!   writers that keep no alpha (①b).
//! - `clear` — a GIF's clear pixels, a bit each; its colours are
//!   `over_ground`'s with the alpha cut (①c).
//! - `opaque` — whether a frame is opaque, so its PDF picture goes without
//!   alpha (①d).
//! - `lay` — a frame the export makes and pictures laid over it, so its
//!   last picture is made on the engine and read back once (①⑵).
//! - `png` — a PNG's rows under their filters, from the frame's RGBA or
//!   from `over_ground`'s RGB (①e).
//!
//! Each kernel reads its picture through three reads — straight,
//! premultiplied, its alpha — that `frame.wgsl` gives on a run's output
//! tiles and `frame_shown.wgsl` on a frame as the screen shows it
//! ([`Frame`]), and runs as one pass over it ([`submit`]).

pub(crate) mod abi;
mod clear;
mod lay;
mod nv12;
mod opaque;
mod over_ground;
mod png;
#[cfg(test)]
mod tests;
#[cfg(test)]
mod shown_tests;
#[cfg(test)]
mod lay_tests;

pub(crate) use clear::Clear;
pub(crate) use lay::{Cover, Lay, Source};
pub(crate) use nv12::{Nv12, Nv12Shape};
pub(crate) use opaque::Opaque;
pub(crate) use over_ground::OverGround;
pub(crate) use png::PngFilter;

use std::sync::OnceLock;

use crate::device::Engine;
use crate::fail;
use crate::kernels::composite::{TILE, TILE_TEXELS};
use crate::kernels::shared::{
    Encoded, PREMULTIPLY_WGSL, TILE_WGSL, encode, fits, flat, pipeline_with, plane, whole,
    words_buffer,
};

/// The three reads on a run's output tiles.
const FRAME_WGSL: &str = include_str!("frame.wgsl");

/// The three reads on a frame as the screen shows it.
const FRAME_SHOWN_WGSL: &str = include_str!("frame_shown.wgsl");

/// The picture a pass converts.
#[derive(Clone, Copy)]
pub(crate) enum Frame<'a> {
    /// A run's output tiles for it, asked row by row from its top-left
    /// tile: straight.
    Tiles(&'a wgpu::Buffer),
    /// A frame as the screen shows it.
    Shown(&'a Shown),
}

/// How a pass reads its picture: each is a pipeline of its own.
#[derive(Clone, Copy)]
enum Read {
    Tiles,
    Shown { bgra: bool },
}

impl Frame<'_> {
    fn read(&self) -> Read {
        match self {
            Self::Tiles(_) => Read::Tiles,
            Self::Shown(shown) => Read::Shown { bgra: shown.bgra },
        }
    }

    /// What the pass binds its picture as.
    fn buffer(&self) -> &wgpu::Buffer {
        match self {
            Self::Tiles(tiles) => tiles,
            Self::Shown(shown) => &shown.rows,
        }
    }

    /// The pass's `stride`: tiles a row, or words.
    fn stride(&self, picture: Picture) -> u32 {
        match self {
            Self::Tiles(_) => picture.tiles().0,
            Self::Shown(shown) => shown.stride,
        }
    }

    /// None, with why, unless the frame holds `picture`.
    fn holds(&self, picture: Picture) -> Option<()> {
        match self {
            Self::Tiles(tiles) => holds(tiles, picture.tiles()),
            Self::Shown(shown) if picture.width > shown.width || picture.height > shown.height => {
                fail(format!(
                    "a {}x{} picture is not in a {}x{} frame",
                    picture.width, picture.height, shown.width, shown.height
                ))
            }
            Self::Shown(_) => Some(()),
        }
    }
}

/// A frame as the screen shows it, for the export's passes
/// (gpu-export-path ①⑴): a surface's texels copied on the GPU into rows a
/// pass reads — premultiplied, `bgra` where the surface is laid so —, so
/// the file a frame makes is the picture the canvas shows and only what a
/// writer takes crosses to the CPU.
pub struct Shown {
    rows: wgpu::Buffer,
    /// Words from one row to the next: a copy's rows start on
    /// `COPY_BYTES_PER_ROW_ALIGNMENT`.
    stride: u32,
    width: u32,
    height: u32,
    bgra: bool,
}

impl Shown {
    /// `picture` of `texture`, from its top-left texel, copied and the copy
    /// submitted — none, with why, unless the texture holds it in 8-bit
    /// RGBA or BGRA texels.
    pub(crate) fn of(engine: &Engine, texture: &wgpu::Texture, picture: Picture) -> Option<Self> {
        picture.check()?;
        let bgra = match texture.format() {
            wgpu::TextureFormat::Rgba8Unorm => false,
            wgpu::TextureFormat::Bgra8Unorm => true,
            other => return fail(format!("a frame shown is 8-bit RGBA or BGRA, not {other:?}")),
        };
        let Picture { width, height } = picture;
        if width > texture.width() || height > texture.height() {
            return fail(format!(
                "a {width}x{height} picture is not in a {}x{} surface",
                texture.width(),
                texture.height()
            ));
        }
        let align = wgpu::COPY_BYTES_PER_ROW_ALIGNMENT;
        let row = (width * 4).div_ceil(align) * align;
        let bytes = u64::from(row) * u64::from(height);
        fits(engine, &[bytes], std::iter::empty())?;
        let rows = engine.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("export shown"),
            size: bytes,
            usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });
        let mut encoder = engine
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor::default());
        encoder.copy_texture_to_buffer(
            texture.as_image_copy(),
            wgpu::TexelCopyBufferInfo {
                buffer: &rows,
                layout: wgpu::TexelCopyBufferLayout {
                    offset: 0,
                    bytes_per_row: Some(row),
                    rows_per_image: Some(height),
                },
            },
            wgpu::Extent3d { width, height, depth_or_array_layers: 1 },
        );
        engine.queue.submit([encoder.finish()]);
        Some(Self { rows, stride: row / 4, width, height, bgra })
    }
}

/// A pass's pipelines, one a [`Read`], each compiled where it is first
/// asked: a device's surfaces are laid one way, so a run reads at most
/// two.
struct Pipelines {
    own: &'static [&'static str],
    entry: &'static str,
    tiles: OnceLock<wgpu::ComputePipeline>,
    rgba: OnceLock<wgpu::ComputePipeline>,
    bgra: OnceLock<wgpu::ComputePipeline>,
}

impl Pipelines {
    const fn new(own: &'static [&'static str], entry: &'static str) -> Self {
        Self {
            own,
            entry,
            tiles: OnceLock::new(),
            rgba: OnceLock::new(),
            bgra: OnceLock::new(),
        }
    }

    /// The pipeline that reads its picture as `frame` is read.
    fn of(&self, engine: &Engine, frame: Frame) -> &wgpu::ComputePipeline {
        self.reading(engine, frame.read())
    }

    /// The pipeline that reads its picture by `read`.
    fn reading(&self, engine: &Engine, read: Read) -> &wgpu::ComputePipeline {
        let (compiled, reads, bgra) = match read {
            Read::Tiles => (&self.tiles, FRAME_WGSL, false),
            Read::Shown { bgra: false } => (&self.rgba, FRAME_SHOWN_WGSL, false),
            Read::Shown { bgra: true } => (&self.bgra, FRAME_SHOWN_WGSL, true),
        };
        compiled.get_or_init(|| {
            let sources = [&[TILE_WGSL, PREMULTIPLY_WGSL, reads], self.own].concat();
            let constants: &[(&str, f64)] = if bgra { &[("FRAME_BGRA", 1.0)] } else { &[] };
            pipeline_with(engine, &sources, self.entry, constants)
        })
    }
}

/// A picture in the frame, from its top-left pixel.
#[derive(Clone, Copy, Debug)]
pub(crate) struct Picture {
    pub(crate) width: u32,
    pub(crate) height: u32,
}

impl Picture {
    /// The frame's tiles a row and its rows of tiles.
    fn tiles(&self) -> (u32, u32) {
        (self.width.div_ceil(TILE), self.height.div_ceil(TILE))
    }

    fn pixels(&self) -> u64 {
        u64::from(self.width) * u64::from(self.height)
    }

    fn check(&self) -> Option<()> {
        let Self { width, height } = *self;
        if width == 0 || height == 0 {
            return fail(format!("a picture is not empty, not {width}x{height}"));
        }
        Some(())
    }
}

/// None, with why, unless `frame` holds the tiles — a row of them, rows —
/// its picture is in.
fn holds(frame: &wgpu::Buffer, (columns, rows): (u32, u32)) -> Option<()> {
    let needed = u64::from(columns * rows) * TILE_TEXELS * 4;
    if frame.size() < needed {
        return fail(format!(
            "{columns}x{rows} tiles take {needed} bytes; the frame has {}",
            frame.size()
        ));
    }
    Some(())
}

/// A new plane of `bytes` for a pass that runs in `groups` (across, down)
/// to put in — none, with why, unless the device binds the one and
/// reaches the other.
fn out_plane(engine: &Engine, label: &str, bytes: u64, groups: (u32, u32)) -> Option<wgpu::Buffer> {
    fits(engine, &[bytes], [groups].into_iter())?;
    Some(plane(engine, label, bytes))
}

/// Runs `pipeline` over `frame` in `groups` (across, down) and submits the
/// work; the caller waits. Its binding 0 is `params`, 1 the frame and 2
/// `out` — the export's own bindings, on the shared plumbing.
fn submit(
    engine: &Engine,
    pipeline: &wgpu::ComputePipeline,
    params: &[u32],
    frame: &wgpu::Buffer,
    out: &wgpu::Buffer,
    groups: (u32, u32),
) {
    let params = words_buffer(engine, "export params", params, wgpu::BufferUsages::UNIFORM);
    encode(
        engine,
        &[Encoded {
            pipeline,
            bound: whole(&[(0, &params), (1, frame), (2, out)]),
            groups: flat(groups),
        }],
    );
}
