//! Which pixels of a GIF are its clear colour (gpu-export-path ①c) —
//! `clear.wgsl` has the law.

use std::ops::Range;

use super::{Dispatch, Frame, Picture, Pipelines, convert, out_plane};
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
    pub(super) pipelines: Pipelines,
}

impl Clear {
    pub(crate) const fn new() -> Self {
        Self {
            pipelines: Pipelines::new(&[include_str!("clear.wgsl")], "clear_pass"),
        }
    }

    /// Marks the pixels of the picture in `frame` whose alpha is under
    /// `cut`, and submits the work; the caller waits. Returns the buffer of
    /// the bits ([`Picture::clear_bytes`] of them), bound whole: a 32nd of
    /// the frame.
    ///
    /// A bake reads a frame of the whole wall for where its ink is
    /// (`inkOfFrame`, baked_frame_ink.dart) — 139,332,960 bytes on the CI,
    /// refused past lavapipe's 128 MiB until a pass bound the rows it reads
    /// ([`convert`]; board conversions-bind-a-frame-past-the-device-limit,
    /// 2026-11-17).
    pub(crate) fn run(&self, engine: &Engine, frame: Frame, picture: Picture, cut: u8) -> Option<wgpu::Buffer> {
        picture.check()?;
        frame.holds(picture)?;
        let row_words = picture.width.div_ceil(32);
        let out = out_plane(engine, "clear out", picture.clear_bytes())?;
        // A row of invocations asks for its words' pixels, 32 a word, run on
        // across the picture's rows.
        let row_pixels = u64::from(row_words) * 32;
        let pixels = |rows: Range<u32>| {
            u64::from(rows.start) * row_pixels..(u64::from(rows.end) * row_pixels).min(picture.pixels())
        };
        let bits = 0..out.size() / 4;
        let dispatch = Dispatch { rows: picture.height, unit: 1, across: row_words.div_ceil(64) };
        convert(
            engine,
            self.pipelines.of(engine, frame),
            (frame.buffer(), &out),
            dispatch,
            |rows| [frame.words(picture, pixels(rows)), bits.clone()],
            |first_row, [frame_base, _]| {
                // Inside u32: a word of a frame the shader indexes.
                let frame_base = frame_base as u32;
                let (stride, cut) = (frame.stride(picture), u32::from(cut));
                vec![stride, picture.width, picture.height, row_words, cut, frame_base, first_row, 0]
            },
        )?;
        Some(out)
    }
}
