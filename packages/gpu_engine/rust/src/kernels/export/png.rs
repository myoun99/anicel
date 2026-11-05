//! A PNG's rows under their filters (gpu-export-path ①e) — `png.wgsl` has
//! the law; `png_rgba.wgsl` and `png_rgb.wgsl` where a row's bytes come
//! from.

use super::{Picture, compile, holds, submit};
use crate::device::Engine;
use crate::fail;

impl Picture {
    /// Words a row of the filtered out takes, `pixel_bytes` a pixel: its
    /// filter's byte and its own, filled out to a whole word.
    fn png_row_words(&self, pixel_bytes: u32) -> u32 {
        (self.width * pixel_bytes + 1).div_ceil(4)
    }

    /// The bytes of the filtered out: [`Self::png_row_bytes`] a row.
    fn png_bytes(&self, pixel_bytes: u32) -> u64 {
        u64::from(self.height) * self.png_row_bytes(pixel_bytes)
    }

    /// Where each row of the filtered out starts from the last's.
    pub(crate) fn png_row_bytes(&self, pixel_bytes: u32) -> u64 {
        u64::from(self.png_row_words(pixel_bytes)) * 4
    }
}

/// The filter pass, from either source.
pub(crate) struct PngFilter {
    rgba: wgpu::ComputePipeline,
    rgb: wgpu::ComputePipeline,
}

impl PngFilter {
    pub(crate) fn new(engine: &Engine) -> Self {
        let own = include_str!("png.wgsl");
        Self {
            rgba: compile(engine, &[include_str!("png_rgba.wgsl"), own], "png_filter_pass"),
            rgb: compile(engine, &[include_str!("png_rgb.wgsl"), own], "png_filter_pass"),
        }
    }

    /// Filters the rows of a PNG of four channels: the picture in `frame`
    /// — the composite's output tiles for it, asked row by row from its
    /// top-left tile —, and submits the work; the caller waits. Returns the
    /// buffer of the rows, [`Picture::png_row_bytes`] apart, each its
    /// filter's byte and its own under it.
    pub(crate) fn rgba(
        &self,
        engine: &Engine,
        frame: &wgpu::Buffer,
        picture: Picture,
    ) -> Option<wgpu::Buffer> {
        picture.check()?;
        holds(frame, picture.tiles())?;
        Some(Self::run(engine, &self.rgba, frame, picture, 4))
    }

    /// [`Self::rgba`] for a PNG of three channels, from `rgb` — what the
    /// over-the-ground pass returned for the picture.
    pub(crate) fn rgb(
        &self,
        engine: &Engine,
        rgb: &wgpu::Buffer,
        picture: Picture,
    ) -> Option<wgpu::Buffer> {
        picture.check()?;
        let needed = picture.rgb_bytes().next_multiple_of(4);
        if rgb.size() < needed {
            return fail(format!("its RGB takes {needed} bytes; the buffer has {}", rgb.size()));
        }
        Some(Self::run(engine, &self.rgb, rgb, picture, 3))
    }

    fn run(
        engine: &Engine,
        pipeline: &wgpu::ComputePipeline,
        source: &wgpu::Buffer,
        picture: Picture,
        pixel_bytes: u32,
    ) -> wgpu::Buffer {
        let params = [
            picture.tiles().0,
            picture.width,
            picture.height,
            picture.png_row_words(pixel_bytes),
        ];
        let out = engine.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("png filter out"),
            size: picture.png_bytes(pixel_bytes),
            usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
            mapped_at_creation: false,
        });
        submit(engine, pipeline, &params, source, &out, (1, picture.height));
        out
    }
}
