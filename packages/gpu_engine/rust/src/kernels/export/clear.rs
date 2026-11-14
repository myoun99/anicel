//! Which pixels of a GIF are its clear colour (gpu-export-path ①c) —
//! `clear.wgsl` has the law.

use super::{Frame, Picture, Pipelines, out_plane, submit};
use crate::device::Engine;

impl Picture {
    /// The bytes of its clear bits: whole words of 32 pixels each, the
    /// last filled out with 0.
    pub(crate) fn clear_bytes(&self) -> u64 {
        self.pixels().div_ceil(32) * 4
    }
}

/// The clear pass.
pub(crate) struct Clear {
    pipelines: Pipelines,
}

impl Clear {
    pub(crate) const fn new() -> Self {
        Self {
            pipelines: Pipelines::new(&[include_str!("clear.wgsl")], "clear_pass"),
        }
    }

    /// Marks the pixels of the picture in `frame` whose alpha is under
    /// `cut`, and submits the work; the caller waits. Returns the buffer of
    /// the bits ([`Picture::clear_bytes`] of them).
    pub(crate) fn run(
        &self,
        engine: &Engine,
        frame: Frame,
        picture: Picture,
        cut: u8,
    ) -> Option<wgpu::Buffer> {
        picture.check()?;
        frame.holds(picture)?;
        let row_words = picture.width.div_ceil(32);
        let params = [
            frame.stride(picture),
            picture.width,
            picture.height,
            row_words,
            u32::from(cut),
            0,
            0,
            0,
        ];
        let groups = (row_words.div_ceil(64), picture.height);
        let out = out_plane(engine, "clear out", picture.clear_bytes(), groups)?;
        let pipeline = self.pipelines.of(engine, frame);
        submit(engine, pipeline, &params, frame.buffer(), &out, groups);
        Some(out)
    }
}
