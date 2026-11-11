//! A PNG's rows under their filters (gpu-export-path ①e) — `png.wgsl` has
//! the law; `png_rgba.wgsl` and `png_rgb.wgsl` where a row's bytes come
//! from.

use std::sync::OnceLock;

use super::{Frame, Picture, Pipelines, out_plane, submit};
use crate::device::Engine;
use crate::fail;
use crate::kernels::shared::pipeline;

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
/// the over-the-ground pass's RGB — which is no frame, so its pipeline
/// reads none.
pub(crate) struct PngFilter {
    rgba: Pipelines,
    rgb: OnceLock<wgpu::ComputePipeline>,
}

const PNG_WGSL: &str = include_str!("png.wgsl");

impl PngFilter {
    pub(crate) const fn new() -> Self {
        Self {
            rgba: Pipelines::new(&[include_str!("png_rgba.wgsl"), PNG_WGSL], "png_filter_pass"),
            rgb: OnceLock::new(),
        }
    }

    /// Filters the rows of a PNG of four channels — the picture in
    /// `frame` — and submits the work; the caller waits. Returns the buffer
    /// of the rows, [`Picture::png_row_bytes`] apart, each its filter's
    /// byte and its own under it.
    pub(crate) fn rgba(&self, engine: &Engine, frame: Frame, picture: Picture) -> Option<wgpu::Buffer> {
        picture.check()?;
        frame.holds(picture)?;
        let pipeline = self.rgba.of(engine, frame);
        Self::run(engine, pipeline, frame.buffer(), frame.stride(picture), picture, 4)
    }

    /// [`Self::rgba`] for a PNG of three channels, from `rgb` — what the
    /// over-the-ground pass returned for the picture.
    pub(crate) fn rgb(&self, engine: &Engine, rgb: &wgpu::Buffer, picture: Picture) -> Option<wgpu::Buffer> {
        picture.check()?;
        let needed = picture.rgb_bytes().next_multiple_of(4);
        if rgb.size() < needed {
            return fail(format!("its RGB takes {needed} bytes; the buffer has {}", rgb.size()));
        }
        let pipeline = self.rgb.get_or_init(|| {
            pipeline(engine, &[include_str!("png_rgb.wgsl"), PNG_WGSL], "png_filter_pass")
        });
        Self::run(engine, pipeline, rgb, 0, picture, 3)
    }

    fn run(
        engine: &Engine,
        pipeline: &wgpu::ComputePipeline,
        source: &wgpu::Buffer,
        stride: u32,
        picture: Picture,
        pixel_bytes: u32,
    ) -> Option<wgpu::Buffer> {
        let params = [stride, picture.width, picture.height, picture.png_row_words(pixel_bytes)];
        let groups = (1, picture.height);
        let out = out_plane(engine, "png filter out", picture.png_bytes(pixel_bytes), groups)?;
        submit(engine, pipeline, &params, source, &out, groups);
        Some(out)
    }
}
