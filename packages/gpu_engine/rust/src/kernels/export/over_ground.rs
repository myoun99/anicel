//! A still's frame over its format's background as RGB24, for the writers
//! that keep no alpha (gpu-export-path ①b), and a GIF's colours with its
//! alpha cut (①c) — `over_ground.wgsl` has the law and why each number is
//! the one it is.

use std::ops::Range;

use super::{Dispatch, Frame, Picture, Pipelines, convert, out_plane};
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
    pub(super) pipelines: Pipelines,
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
        let out = out_plane(engine, "over ground out", picture.rgb_words_bytes())?;
        // A row of invocations asks for its runs' pixels, four a run and
        // three words out, run on across the picture's rows.
        let per_row = u64::from(row_groups);
        let runs = |rows: &Range<u32>| u64::from(rows.start) * per_row..u64::from(rows.end) * per_row;
        let pixels = |runs: Range<u64>| runs.start * 4..(runs.end * 4).min(picture.pixels());
        let puts = |runs: Range<u64>| runs.start * 3..(runs.end * 3).min(out.size() / 4);
        let colour = [
            u32::from_le_bytes([ground[0], ground[1], ground[2], 0]),
            cut.map_or(NO_CUT, u32::from),
        ];
        let dispatch = Dispatch { rows: picture.height, unit: 1, across: row_groups.div_ceil(64) };
        convert(
            engine,
            self.pipelines.of(engine, frame),
            (frame.buffer(), &out),
            dispatch,
            |rows| [frame.words(picture, pixels(runs(&rows))), puts(runs(&rows))],
            |first_row, [frame_base, out_base]| {
                // Inside u32: words of planes the shader indexes.
                let (frame_base, out_base) = (frame_base as u32, out_base as u32);
                let (width, height) = (picture.width, picture.height);
                let [ground, cut] = colour;
                let shape = [frame.stride(picture), width, height, row_groups, ground, cut];
                [&shape[..], &[frame_base, first_row, out_base, 0, 0, 0]].concat()
            },
        )?;
        Some(out)
    }
}
