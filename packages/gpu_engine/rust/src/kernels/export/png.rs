//! A PNG's rows under their filters (gpu-export-path ①e) — `png.wgsl` has
//! the law; `png_rgba.wgsl` and `png_packed.wgsl` where a row's bytes come
//! from.

use std::ops::Range;
use std::sync::OnceLock;

use super::{Dispatch, Picture, Pipelines, Shown, convert, out_plane};
use crate::device::Engine;
use crate::fail;
use crate::kernels::shared::{kept_or_made, pipeline_with};

impl Picture {
    /// Words a row of the filtered out takes, `pixel_bytes` a pixel: its
    /// filter's byte and its own, filled out to a whole word.
    fn png_row_words(&self, pixel_bytes: u32) -> u32 {
        (self.width * pixel_bytes + 1).div_ceil(4)
    }

    /// The bytes of the filtered out: [`Self::png_row_bytes`] a row.
    pub(crate) fn png_bytes(&self, pixel_bytes: u32) -> u64 {
        u64::from(self.height) * self.png_row_bytes(pixel_bytes)
    }

    /// Where each row of the filtered out starts from the last's.
    pub(crate) fn png_row_bytes(&self, pixel_bytes: u32) -> u64 {
        u64::from(self.png_row_words(pixel_bytes)) * 4
    }
}

/// The filter pass, from either source: the frame's pixels straight, or
/// bytes that lie packed — the over-the-ground pass's RGB, a picture's
/// straight RGBA the app hands over — which are no frame, so their
/// pipelines read none.
pub(crate) struct PngFilter {
    rgba: Pipelines,
    /// The packed pass of three bytes a pixel, and of four.
    packed: [OnceLock<wgpu::ComputePipeline>; 2],
}

const PNG_WGSL: &str = include_str!("png.wgsl");

impl PngFilter {
    pub(crate) const fn new() -> Self {
        Self {
            rgba: Pipelines::new(&[include_str!("png_rgba.wgsl"), PNG_WGSL], "png_filter_pass"),
            packed: [OnceLock::new(), OnceLock::new()],
        }
    }

    /// Filters the rows of a PNG of four channels — the picture in
    /// `frame` — and submits the work; the caller waits. Returns the buffer
    /// of the rows, [`Picture::png_row_bytes`] apart, each its filter's
    /// byte and its own under it.
    pub(crate) fn rgba(&self, engine: &Engine, frame: &Shown, picture: Picture) -> Option<wgpu::Buffer> {
        picture.check()?;
        frame.holds(picture)?;
        let pipeline = self.rgba.of(engine, frame);
        let width = u64::from(picture.width);
        let read = |rows: Range<u32>| {
            frame.words(picture, u64::from(rows.start) * width..u64::from(rows.end) * width)
        };
        Self::run(engine, pipeline, (&frame.rows, frame.stride, read), picture, 4)
    }

    /// [`Self::rgba`] for a PNG whose bytes lie packed in `bytes`,
    /// `pixel_bytes` a pixel — three, what the over-the-ground pass
    /// returned for the picture; four, a picture's straight RGBA
    /// ([`Self::rgba`] reads a frame, whose colour is premultiplied: a
    /// picture whose alpha is not whole would not come back as it was).
    pub(crate) fn packed(
        &self,
        engine: &Engine,
        bytes: &wgpu::Buffer,
        picture: Picture,
        pixel_bytes: u32,
    ) -> Option<wgpu::Buffer> {
        picture.check()?;
        let pipeline = self.packed_pipeline(engine, pixel_bytes)?;
        let needed = (picture.pixels() * u64::from(pixel_bytes)).next_multiple_of(4);
        if bytes.size() < needed {
            return fail(format!("its bytes take {needed}; the buffer has {}", bytes.size()));
        }
        let row = u64::from(picture.width) * u64::from(pixel_bytes);
        let read = |rows: Range<u32>| {
            u64::from(rows.start) * row / 4..(u64::from(rows.end) * row).div_ceil(4)
        };
        Self::run(engine, pipeline, (bytes, 0, read), picture, pixel_bytes)
    }

    /// The packed pass of `pixel_bytes` a pixel, compiled once — none for
    /// a count it has none of.
    fn packed_pipeline(&self, engine: &Engine, pixel_bytes: u32) -> Option<&wgpu::ComputePipeline> {
        let Some(kept) = (pixel_bytes.checked_sub(3)).and_then(|at| self.packed.get(at as usize)) else {
            return fail(format!("a packed PNG of {pixel_bytes} bytes a pixel"));
        };
        Some(kept_or_made(kept, || {
            let sources = [include_str!("png_packed.wgsl"), PNG_WGSL];
            pipeline_with(engine, &sources, "png_filter_pass", &[("PIXEL_BYTES", f64::from(pixel_bytes))])
        }))
    }

    /// Compiles every pass a PNG takes: a still's — the one of four
    /// channels as every pass that reads a frame is ([`Pipelines::warm`]),
    /// and its three over the ground — and an animated one's frames,
    /// straight four.
    pub(super) fn warm(&self, engine: &Engine, bgra: bool) {
        self.rgba.warm(engine, bgra);
        self.packed_pipeline(engine, 3);
        self.packed_pipeline(engine, 4);
    }

    /// The filter pass over `picture`, its rows from `source` — `stride`
    /// the frame's, and `read` the words of it a run of rows lies on — at
    /// `pixel_bytes` a pixel. A row's filters read the row above it too, so
    /// a band binds that row with its own.
    fn run(
        engine: &Engine,
        pipeline: &wgpu::ComputePipeline,
        (source, stride, read): (&wgpu::Buffer, u32, impl Fn(Range<u32>) -> Range<u64>),
        picture: Picture,
        pixel_bytes: u32,
    ) -> Option<wgpu::Buffer> {
        let row_words = picture.png_row_words(pixel_bytes);
        let out = out_plane(engine, "png filter out", picture.png_bytes(pixel_bytes))?;
        let per_row = u64::from(row_words);
        let puts = |rows: &Range<u32>| u64::from(rows.start) * per_row..u64::from(rows.end) * per_row;
        convert(
            engine,
            pipeline,
            (source, &out),
            Dispatch { rows: picture.height, unit: 1, across: 1 },
            |rows| [read(rows.start.saturating_sub(1)..rows.end), puts(&rows)],
            |first_row, [read_base, out_base]| {
                // Inside u32: words of planes the shader indexes.
                let (read_base, out_base) = (read_base as u32, out_base as u32);
                vec![stride, picture.width, picture.height, row_words, read_base, first_row, out_base, 0]
            },
        )?;
        Some(out)
    }
}
