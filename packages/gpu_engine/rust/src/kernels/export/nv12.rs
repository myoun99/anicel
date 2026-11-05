//! A movie's frame as NV12, for its encoder (gpu-export-path ①a) —
//! `nv12.wgsl` has the law and why each number is the one it is.

use super::{Picture, compile, holds, submit};
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
    /// The picture in the composite's frame.
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
    pipeline: wgpu::ComputePipeline,
}

impl Nv12 {
    pub(crate) fn new(engine: &Engine) -> Self {
        Self {
            pipeline: compile(engine, include_str!("nv12.wgsl"), "nv12_pass"),
        }
    }

    /// Converts `frame` — the composite's output tiles for the picture,
    /// asked row by row from its top-left tile — and submits the work; the
    /// caller waits. Returns the buffer the NV12 bytes are in
    /// ([`Nv12Shape::bytes`] of them), to be copied out for reading.
    pub(crate) fn run(
        &self,
        engine: &Engine,
        frame: &wgpu::Buffer,
        shape: Nv12Shape,
    ) -> Option<wgpu::Buffer> {
        shape.check()?;
        let picture = shape.picture();
        holds(frame, picture.tiles())?;
        let params = [
            picture.tiles().0,
            shape.src_width,
            shape.src_height,
            shape.width,
            shape.height,
            shape.y_stride,
            0,
            0,
        ];
        let out = engine.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("nv12 out"),
            size: shape.bytes(),
            usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
            mapped_at_creation: false,
        });
        let groups = ((shape.y_stride / 4).div_ceil(16), (shape.height / 2).div_ceil(8));
        submit(engine, &self.pipeline, &params, frame, &out, groups);
        Some(out)
    }
}
