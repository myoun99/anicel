//! Whether a frame is opaque, so its PDF picture goes without alpha
//! (gpu-export-path ①d) — `opaque.wgsl` has the law.

use super::{Picture, compile, holds, submit};
use crate::device::Engine;
use crate::kernels::shared::words_buffer;

/// The opaque pass.
pub(crate) struct Opaque {
    pipeline: wgpu::ComputePipeline,
}

impl Opaque {
    pub(crate) fn new(engine: &Engine) -> Self {
        Self {
            pipeline: compile(engine, &[include_str!("opaque.wgsl")], "opaque_pass"),
        }
    }

    /// Asks whether every pixel of the picture in `frame` — the
    /// composite's output tiles for it, asked row by row from its top-left
    /// tile — is opaque, and submits the work; the caller waits. Returns
    /// the buffer of the answer, one little-endian u32: 255 when every
    /// pixel is, less when one is not.
    pub(crate) fn run(
        &self,
        engine: &Engine,
        frame: &wgpu::Buffer,
        picture: Picture,
    ) -> Option<wgpu::Buffer> {
        picture.check()?;
        let tiles = picture.tiles();
        holds(frame, tiles)?;
        let params = [tiles.0, picture.width, picture.height, 0];
        // No `fits`: the answer is a word, and its groups are the frame's
        // tiles — a frame a binding holds has fewer than a dispatch reaches
        // (2 GB is 32,768 tiles).
        let usage = wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC;
        let answer = words_buffer(engine, "opaque answer", &[255], usage);
        submit(engine, &self.pipeline, &params, frame, &answer, tiles);
        Some(answer)
    }
}
