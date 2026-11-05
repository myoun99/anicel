//! A movie's frame as NV12, for its encoder (gpu-export-path ①a) —
//! `nv12.wgsl` has the law and why each number is the one it is.

use wgpu::util::DeviceExt;

use super::FRAME_WGSL;
use crate::device::Engine;
use crate::fail;
use crate::kernels::composite::{TILE, TILE_TEXELS};
use crate::kernels::shared::TILE_WGSL;

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
    /// The frame's tiles a row and its rows of tiles.
    fn tiles(&self) -> (u32, u32) {
        (self.src_width.div_ceil(TILE), self.src_height.div_ceil(TILE))
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
        let source = [TILE_WGSL, FRAME_WGSL, include_str!("nv12.wgsl")].join("\n");
        let module = engine
            .device
            .create_shader_module(wgpu::ShaderModuleDescriptor {
                label: Some("nv12"),
                source: wgpu::ShaderSource::Wgsl(source.into()),
            });
        let pipeline = engine
            .device
            .create_compute_pipeline(&wgpu::ComputePipelineDescriptor {
                label: Some("nv12"),
                layout: None,
                module: &module,
                entry_point: Some("nv12_pass"),
                compilation_options: Default::default(),
                cache: None,
            });
        Self { pipeline }
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
        let (columns, rows) = shape.tiles();
        let needed = u64::from(columns * rows) * TILE_TEXELS * 4;
        if frame.size() < needed {
            return fail(format!(
                "{columns}x{rows} tiles take {needed} bytes; the frame has {}",
                frame.size()
            ));
        }
        let words = [
            columns,
            shape.src_width,
            shape.src_height,
            shape.width,
            shape.height,
            shape.y_stride,
            0,
            0,
        ];
        let params = engine
            .device
            .create_buffer_init(&wgpu::util::BufferInitDescriptor {
                label: Some("nv12 params"),
                contents: &words.iter().flat_map(|word| word.to_le_bytes()).collect::<Vec<_>>(),
                usage: wgpu::BufferUsages::UNIFORM,
            });
        let out = engine.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("nv12 out"),
            size: shape.bytes(),
            usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
            mapped_at_creation: false,
        });
        let bind_group = engine.device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("nv12"),
            layout: &self.pipeline.get_bind_group_layout(0),
            entries: &[
                wgpu::BindGroupEntry {
                    binding: 0,
                    resource: params.as_entire_binding(),
                },
                wgpu::BindGroupEntry {
                    binding: 1,
                    resource: frame.as_entire_binding(),
                },
                wgpu::BindGroupEntry {
                    binding: 2,
                    resource: out.as_entire_binding(),
                },
            ],
        });
        let mut encoder = engine
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor::default());
        {
            let mut pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor::default());
            pass.set_pipeline(&self.pipeline);
            pass.set_bind_group(0, &bind_group, &[]);
            pass.dispatch_workgroups(
                (shape.y_stride / 4).div_ceil(16),
                (shape.height / 2).div_ceil(8),
                1,
            );
        }
        engine.queue.submit([encoder.finish()]);
        Some(out)
    }
}
