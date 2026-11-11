//! A frame straight, for the writers that keep its alpha
//! (gpu-export-path ①⑶) — `straight.wgsl` has the law.

use super::{Frame, Picture, Pipelines, out_plane, submit};
use crate::device::Engine;

impl Picture {
    /// The bytes of its pixels, four each.
    pub(crate) fn rgba_bytes(&self) -> u64 {
        self.pixels() * 4
    }
}

/// The straight pass.
pub(crate) struct Straight {
    pipelines: Pipelines,
}

impl Straight {
    pub(crate) const fn new() -> Self {
        Self {
            pipelines: Pipelines::new(&[include_str!("straight.wgsl")], "straight_pass"),
        }
    }

    /// Makes the picture in `frame` straight, and submits the work; the
    /// caller waits. Returns the buffer of its pixels
    /// ([`Picture::rgba_bytes`] of them), red first.
    pub(crate) fn run(&self, engine: &Engine, frame: Frame, picture: Picture) -> Option<wgpu::Buffer> {
        picture.check()?;
        frame.holds(picture)?;
        let params = [frame.stride(picture), picture.width, picture.height, 0];
        let groups = (picture.width.div_ceil(64), picture.height);
        let out = out_plane(engine, "straight out", picture.rgba_bytes(), groups)?;
        let pipeline = self.pipelines.of(engine, frame);
        submit(engine, pipeline, &params, frame.buffer(), &out, groups);
        Some(out)
    }
}
