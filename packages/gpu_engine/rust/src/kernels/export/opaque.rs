//! Whether a frame is opaque, so its PDF picture goes without alpha
//! (gpu-export-path ①d) — `opaque.wgsl` has the law.

use super::{Frame, Picture, Pipelines, submit};
use crate::device::Engine;
use crate::kernels::shared::words_buffer;

/// The opaque pass.
pub(crate) struct Opaque {
    pipelines: Pipelines,
}

impl Opaque {
    pub(crate) const fn new() -> Self {
        Self {
            pipelines: Pipelines::new(&[include_str!("opaque.wgsl")], "opaque_pass"),
        }
    }

    /// Asks whether every pixel of the picture in `frame` is opaque, and
    /// submits the work; the caller waits. Returns the buffer of the
    /// answer, one little-endian u32: 255 when every pixel is, less when
    /// one is not.
    pub(crate) fn run(&self, engine: &Engine, frame: Frame, picture: Picture) -> Option<wgpu::Buffer> {
        picture.check()?;
        frame.holds(picture)?;
        let params = [frame.stride(picture), picture.width, picture.height, 0];
        // No `fits`: the answer is a word, and its groups are the picture's
        // tiles — a frame a binding holds has fewer than a dispatch reaches
        // (2 GB is 32,768 tiles).
        let usage = wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC;
        let answer = words_buffer(engine, "opaque answer", &[255], usage);
        let pipeline = self.pipelines.of(engine, frame);
        submit(engine, pipeline, &params, frame.buffer(), &answer, picture.tiles());
        Some(answer)
    }
}
