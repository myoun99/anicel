//! A still's frame over its format's background as RGB24, for the writers
//! that keep no alpha (gpu-export-path ①b), and a GIF's colours with its
//! alpha cut (①c) — `over_ground.wgsl` has the law and why each number is
//! the one it is.

use super::{Picture, compile, holds, out_plane, submit};
use crate::device::Engine;
use crate::kernels::shared::PREMULTIPLY_WGSL;

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

/// The pass's cut where there is none: past every alpha.
const NO_CUT: u32 = 256;

/// The over-the-ground pass.
pub(crate) struct OverGround {
    pipeline: wgpu::ComputePipeline,
}

impl OverGround {
    pub(crate) fn new(engine: &Engine) -> Self {
        Self {
            pipeline: compile(
                engine,
                &[PREMULTIPLY_WGSL, include_str!("over_ground.wgsl")],
                "over_ground_pass",
            ),
        }
    }

    /// Lays `frame` — the composite's output tiles for the picture, asked
    /// row by row from its top-left tile — over `ground` (red, green,
    /// blue), its alpha `cut` where a GIF cuts it (none: its shades), and
    /// submits the work; the caller waits. Returns the buffer the RGB
    /// bytes are at the start of ([`Picture::rgb_bytes`] of them), to be
    /// copied out for reading.
    pub(crate) fn run(
        &self,
        engine: &Engine,
        frame: &wgpu::Buffer,
        picture: Picture,
        ground: [u8; 3],
        cut: Option<u8>,
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
            cut.map_or(NO_CUT, u32::from),
            0,
            0,
        ];
        let groups = (row_groups.div_ceil(64), picture.height);
        let out = out_plane(engine, "over ground out", picture.rgb_words_bytes(), groups)?;
        submit(engine, &self.pipeline, &params, frame, &out, groups);
        Some(out)
    }
}
