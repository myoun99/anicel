//! A still's frame over its format's background as RGB24, for the writers
//! that keep no alpha (gpu-export-path ①b) — `over_ground.wgsl` has the
//! law and why each number is the one it is.

use super::{Picture, compile, holds, submit};
use crate::device::Engine;

impl Picture {
    /// The RGB bytes the writers read: three a pixel, row after row with
    /// nothing between.
    pub(crate) fn rgb_bytes(&self) -> u64 {
        self.pixels() * 3
    }

    /// The bytes the pass writes: whole words of four pixels each, the
    /// last filled out with zeros past [`Self::rgb_bytes`].
    fn rgb_words_bytes(&self) -> u64 {
        self.pixels().div_ceil(4) * 12
    }
}

/// The over-the-ground pass.
pub(crate) struct OverGround {
    pipeline: wgpu::ComputePipeline,
}

impl OverGround {
    pub(crate) fn new(engine: &Engine) -> Self {
        Self {
            pipeline: compile(engine, include_str!("over_ground.wgsl"), "over_ground_pass"),
        }
    }

    /// Lays `frame` — the composite's output tiles for the picture, asked
    /// row by row from its top-left tile — over `ground` (red, green,
    /// blue) and submits the work; the caller waits. Returns the buffer
    /// the RGB bytes are at the start of ([`Picture::rgb_bytes`] of them),
    /// to be copied out for reading.
    pub(crate) fn run(
        &self,
        engine: &Engine,
        frame: &wgpu::Buffer,
        picture: Picture,
        ground: [u8; 3],
    ) -> Option<wgpu::Buffer> {
        picture.check()?;
        holds(frame, picture.tiles())?;
        let row_groups = picture.width.div_ceil(4);
        let params = [
            picture.tiles().0,
            picture.width,
            picture.height,
            row_groups,
            u32::from_le_bytes([ground[0], ground[1], ground[2], 0]),
            0,
            0,
            0,
        ];
        let out = engine.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("over ground out"),
            size: picture.rgb_words_bytes(),
            usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
            mapped_at_creation: false,
        });
        let groups = (row_groups.div_ceil(64), picture.height);
        submit(engine, &self.pipeline, &params, frame, &out, groups);
        Some(out)
    }
}
