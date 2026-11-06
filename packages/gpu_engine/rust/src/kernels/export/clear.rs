//! Which pixels of a GIF are its clear colour (gpu-export-path ①c) —
//! `clear.wgsl` has the law.

use super::{Picture, compile, holds, out_plane, submit};
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
    pipeline: wgpu::ComputePipeline,
}

impl Clear {
    pub(crate) fn new(engine: &Engine) -> Self {
        Self {
            pipeline: compile(engine, &[include_str!("clear.wgsl")], "clear_pass"),
        }
    }

    /// Marks the pixels of the picture in `frame` — the composite's output
    /// tiles for it, asked row by row from its top-left tile — whose alpha
    /// is under `cut`, and submits the work; the caller waits. Returns the
    /// buffer of the bits ([`Picture::clear_bytes`] of them).
    pub(crate) fn run(
        &self,
        engine: &Engine,
        frame: &wgpu::Buffer,
        picture: Picture,
        cut: u8,
    ) -> Option<wgpu::Buffer> {
        picture.check()?;
        holds(frame, picture.tiles())?;
        let row_words = picture.width.div_ceil(32);
        let params = [
            picture.tiles().0,
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
        submit(engine, &self.pipeline, &params, frame, &out, groups);
        Some(out)
    }
}
