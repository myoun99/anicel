//! A still's frame over its format's background as RGB24, for the writers
//! that keep no alpha (gpu-export-path ①b), and a GIF's colours with its
//! alpha cut (①c) — `over_ground.wgsl` has the law and why each number is
//! the one it is.

use super::{Frame, Picture, Pipelines, out_plane, submit};
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

/// The pass's cut where there is none: past every alpha.
const NO_CUT: u32 = 256;

/// The over-the-ground pass.
pub(crate) struct OverGround {
    pipelines: Pipelines,
}

impl OverGround {
    pub(crate) const fn new() -> Self {
        Self {
            pipelines: Pipelines::new(&[include_str!("over_ground.wgsl")], "over_ground_pass"),
        }
    }

    /// Lays the picture in `frame` over `ground` (red, green, blue), its
    /// alpha `cut` where a GIF cuts it (none: its shades), and submits the
    /// work; the caller waits. Returns the buffer the RGB bytes are at the
    /// start of ([`Picture::rgb_bytes`] of them), to be copied out for
    /// reading.
    pub(crate) fn run(
        &self,
        engine: &Engine,
        frame: Frame,
        picture: Picture,
        ground: [u8; 3],
        cut: Option<u8>,
    ) -> Option<wgpu::Buffer> {
        picture.check()?;
        frame.holds(picture)?;
        let row_groups = picture.width.div_ceil(4);
        let params = [
            frame.stride(picture),
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
        let pipeline = self.pipelines.of(engine, frame);
        submit(engine, pipeline, &params, frame.buffer(), &out, groups);
        Some(out)
    }
}
