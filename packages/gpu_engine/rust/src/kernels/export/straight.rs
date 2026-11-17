//! A frame straight, for the writers that keep its alpha
//! (gpu-export-path ①⑶) — `straight.wgsl` has the law.

use std::ops::Range;

use super::{Dispatch, Frame, Picture, Pipelines, convert, out_plane};
use crate::device::Engine;

impl Picture {
    /// The bytes of its pixels, four each.
    pub(crate) fn rgba_bytes(&self) -> u64 {
        self.pixels() * 4
    }
}

/// The straight pass.
pub(crate) struct Straight {
    pub(super) pipelines: Pipelines,
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
        let out = out_plane(engine, "straight out", picture.rgba_bytes())?;
        // A row of invocations is a row of the picture, a word a pixel out.
        let width = u64::from(picture.width);
        let pixels = |rows: Range<u32>| u64::from(rows.start) * width..u64::from(rows.end) * width;
        let dispatch = Dispatch { rows: picture.height, unit: 1, across: picture.width.div_ceil(64) };
        convert(
            engine,
            self.pipelines.of(engine, frame),
            (frame.buffer(), &out),
            dispatch,
            |rows| [frame.words(picture, pixels(rows.clone())), pixels(rows)],
            |first_row, [frame_base, out_base]| {
                // Inside u32: words of planes the shader indexes.
                let (frame_base, out_base) = (frame_base as u32, out_base as u32);
                let stride = frame.stride(picture);
                vec![stride, picture.width, picture.height, frame_base, first_row, out_base, 0, 0]
            },
        )?;
        Some(out)
    }
}
