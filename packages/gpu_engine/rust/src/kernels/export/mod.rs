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
//! - `straight` — a frame straight, for the writers that keep its alpha
//!   (①⑶).
//!
//! Each kernel reads its picture through three reads — straight,
//! premultiplied, its alpha — that `frame.wgsl` gives on a run's output
//! tiles and `frame_shown.wgsl` on a frame as the screen shows it
//! ([`Frame`]), and runs over it a band of rows at a time ([`convert`]).

pub(crate) mod abi;
mod clear;
mod lay;
mod nv12;
mod opaque;
mod over_ground;
mod png;
mod straight;
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
pub(crate) use straight::Straight;

use std::ops::Range;
use std::sync::OnceLock;

use crate::device::Engine;
use crate::fail;
use crate::kernels::composite::{TILE, TILE_TEXELS};
use crate::kernels::shared::{
    Encoded, PREMULTIPLY_WGSL, TILE_WGSL, bands, buffer_holds, encode, fits, flat, kept_or_made, pipeline_with,
    plane, room, whole, words_bound, words_buffer,
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

    /// The words of the frame that `pixels` of `picture` — counted row
    /// after row across it — lie on: a frame shown's rows between, a run's
    /// rows of tiles. None for none.
    fn words(&self, picture: Picture, pixels: Range<u64>) -> Range<u64> {
        if pixels.is_empty() {
            return 0..0;
        }
        let width = u64::from(picture.width);
        let (first, last) = (pixels.start, pixels.end - 1);
        match self {
            Self::Shown(shown) => {
                let word = |at: u64| at / width * u64::from(shown.stride) + at % width;
                word(first)..word(last) + 1
            }
            Self::Tiles(_) => {
                let tile_row = |at: u64| at / width / u64::from(TILE);
                let words = u64::from(picture.tiles().0) * TILE_TEXELS;
                tile_row(first) * words..(tile_row(last) + 1) * words
            }
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
        buffer_holds(engine, bytes)?;
        let rows = engine.device().create_buffer(&wgpu::BufferDescriptor {
            label: Some("export shown"),
            size: bytes,
            usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });
        let mut encoder = engine
            .device()
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

/// A pass's pipelines, one a [`Read`]: compiled ahead for the reads a
/// frame the app hands a pass takes ([`Self::warm`]), and where it is
/// first asked for the rest.
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

    /// Compiles the pass for the frames the export makes and for frames
    /// shown on surfaces laid `bgra` or not, so a frame the app hands it
    /// waits for no compile. ⛔Not for a run's tiles: no verb the app
    /// binds hands a pass those.
    fn warm(&self, engine: &Engine, bgra: bool) {
        self.reading(engine, Read::Shown { bgra: false });
        if bgra {
            self.reading(engine, Read::Shown { bgra: true });
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
        kept_or_made(compiled, || {
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

/// A new plane of `bytes` for a pass to put in, bound a band at a time
/// ([`convert`]) — none, with why, where the device makes no buffer of it.
fn out_plane(engine: &Engine, label: &str, bytes: u64) -> Option<wgpu::Buffer> {
    buffer_holds(engine, bytes)?;
    Some(plane(engine, label, bytes))
}

/// How a conversion's invocations run: their rows, the rows a workgroup
/// takes, and its workgroups across.
#[derive(Clone, Copy)]
struct Dispatch {
    rows: u32,
    unit: u32,
    across: u32,
}

/// Runs a conversion's `pipeline` and submits the work; the caller waits.
/// Binding 0 is its params, 1 the plane it reads — a frame, or bytes that
/// lie packed — and 2 the plane it puts: the export's own bindings, on the
/// shared plumbing. Its rows run in bands ([`bands`]), each binding of the
/// two only the words `words` names for its rows and handed `params` of its
/// first row and the words its two bindings begin on. None, with why, where
/// one workgroup's rows do not fit a binding, or a band's workgroups a
/// dispatch.
///
/// 🚨A CONVERSION BINDS THE ROWS IT READS AND PUTS, NOT ITS PLANES WHOLE
/// (board conversions-bind-a-frame-past-the-device-limit, 2026-11-17): a
/// frame of the user's canvas, 7751×4396, is 136 MB — past the 128 MiB a
/// binding holds on lavapipe, the least a Vulkan device may hold.
fn convert(
    engine: &Engine,
    pipeline: &wgpu::ComputePipeline,
    (read, out): (&wgpu::Buffer, &wgpu::Buffer),
    Dispatch { rows, unit, across }: Dispatch,
    words: impl Fn(Range<u32>) -> [Range<u64>; 2],
    params: impl Fn(u32, [u64; 2]) -> Vec<u32>,
) -> Option<()> {
    let step = u64::from(engine.device().limits().min_storage_buffer_offset_alignment);
    let bands = bands(0..rows, unit, (room(engine), step), |band| words(band).to_vec())?;
    let groups = |band: &Range<u32>| (across, (band.end - band.start).div_ceil(unit));
    fits(engine, &[], bands.iter().map(groups))?;
    // No band reads or puts nothing (mutant V21, 11-17): rows past a
    // picture's pixels add no word to a plane, so `bands` keeps them in the
    // band before them, and the first band begins on the picture's first.
    let mut uniforms = Vec::new();
    let mut bound = Vec::new();
    for band in &bands {
        let [read_words, out_words] = words(band.clone());
        let (read_given, read_base) = words_bound(read, read_words, step);
        let (out_given, out_base) = words_bound(out, out_words, step);
        let words = params(band.start, [read_base, out_base]);
        uniforms.push(words_buffer(engine, "export params", &words, wgpu::BufferUsages::UNIFORM));
        bound.push([(1, read_given), (2, out_given)]);
    }
    let passes: Vec<Encoded> = uniforms
        .iter()
        .zip(bound)
        .zip(&bands)
        .map(|((uniform, planes), band)| {
            let mut entries = whole(&[(0, uniform)]);
            entries.extend(planes.map(|(binding, resource)| wgpu::BindGroupEntry { binding, resource }));
            Encoded { pipeline, bound: entries, groups: flat(groups(band)) }
        })
        .collect();
    encode(engine, &passes);
    Some(())
}
