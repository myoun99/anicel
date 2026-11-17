//! A movie's frame as NV12, for its encoder (gpu-export-path ①a) —
//! `nv12.wgsl` has the law and why each number is the one it is.

use std::ops::Range;

use super::{Dispatch, Frame, Picture, Pipelines, convert, out_plane};
use crate::device::Engine;
use crate::fail;

/// A picture and the encoder's frame it is written into.
#[derive(Clone, Copy, Debug)]
pub(crate) struct Nv12Shape {
    pub(crate) src_width: u32,
    pub(crate) src_height: u32,
    /// The encoder's frame: even sides, at least the picture's.
    pub(crate) width: u32,
    pub(crate) height: u32,
    /// Bytes from one Y row to the next, and one CbCr row to the next: a
    /// multiple of 4, at least `width`.
    pub(crate) y_stride: u32,
}

impl Nv12Shape {
    /// The picture in the frame.
    fn picture(&self) -> Picture {
        Picture {
            width: self.src_width,
            height: self.src_height,
        }
    }

    /// The NV12 bytes: `height` Y rows, then `height / 2` CbCr rows.
    pub(crate) fn bytes(&self) -> u64 {
        u64::from(self.y_stride) * u64::from(self.height) * 3 / 2
    }

    fn check(&self) -> Option<()> {
        let Self {
            src_width,
            src_height,
            width,
            height,
            y_stride,
        } = *self;
        if width == 0 || height == 0 || width % 2 != 0 || height % 2 != 0 {
            return fail(format!("an encoder's frame is even and not empty, not {width}x{height}"));
        }
        if width < src_width || height < src_height {
            return fail(format!(
                "a {src_width}x{src_height} picture does not fit a {width}x{height} frame"
            ));
        }
        if y_stride % 4 != 0 || y_stride < width {
            return fail(format!("rows {y_stride} bytes apart cannot hold {width} in words"));
        }
        Some(())
    }
}

/// The NV12 pass.
pub(crate) struct Nv12 {
    pub(super) pipelines: Pipelines,
}

impl Nv12 {
    pub(crate) const fn new() -> Self {
        Self {
            pipelines: Pipelines::new(&[include_str!("nv12.wgsl")], "nv12_pass"),
        }
    }

    /// Converts the picture in `frame` and submits the work; the caller
    /// waits. Returns the buffer the NV12 bytes are in
    /// ([`Nv12Shape::bytes`] of them), to be copied out for reading.
    pub(crate) fn run(&self, engine: &Engine, frame: Frame, shape: Nv12Shape) -> Option<wgpu::Buffer> {
        shape.check()?;
        let picture = shape.picture();
        frame.holds(picture)?;
        let out = out_plane(engine, "nv12 out", shape.bytes())?;
        // A row of invocations is a row of 2 × 2 blocks: two of the
        // picture's rows, none past its last. Eight rows a workgroup.
        let width = u64::from(picture.width);
        let pixels = |rows: Range<u32>| {
            let row = |block: u32| u64::from(block * 2).min(u64::from(picture.height));
            row(rows.start) * width..row(rows.end) * width
        };
        let whole = 0..out.size() / 4;
        let dispatch = Dispatch { rows: shape.height / 2, unit: 8, across: (shape.y_stride / 4).div_ceil(16) };
        convert(
            engine,
            self.pipelines.of(engine, frame),
            (frame.buffer(), &out),
            dispatch,
            |rows| [frame.words(picture, pixels(rows)), whole.clone()],
            |first_row, [frame_base, _]| {
                // Inside u32: a word of a frame the shader indexes.
                let frame_base = frame_base as u32;
                let Nv12Shape { src_width, src_height, width, height, y_stride } = shape;
                let stride = frame.stride(picture);
                vec![stride, src_width, src_height, width, height, y_stride, frame_base, first_row]
            },
        )?;
        Some(out)
    }
}
