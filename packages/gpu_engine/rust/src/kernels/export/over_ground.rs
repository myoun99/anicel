//! A still's frame over its format's background as RGB24, for the writers
//! that keep no alpha (gpu-export-path ①b) — `over_ground.wgsl` has the
//! law and why each number is the one it is.

use wgpu::util::DeviceExt;

use super::FRAME_WGSL;
use crate::device::Engine;
use crate::fail;
use crate::kernels::composite::{TILE, TILE_TEXELS};
use crate::kernels::shared::TILE_WGSL;

/// The picture laid over the ground.
#[derive(Clone, Copy, Debug)]
pub(crate) struct OverGroundShape {
    pub(crate) width: u32,
    pub(crate) height: u32,
}

impl OverGroundShape {
    /// The frame's tiles a row and its rows of tiles.
    fn tiles(&self) -> (u32, u32) {
        (self.width.div_ceil(TILE), self.height.div_ceil(TILE))
    }

    fn pixels(&self) -> u64 {
        u64::from(self.width) * u64::from(self.height)
    }

    /// The RGB bytes the writers read: three a pixel, row after row with
    /// nothing between.
    pub(crate) fn bytes(&self) -> u64 {
        self.pixels() * 3
    }

    /// The bytes the pass writes: whole words of four pixels each, the
    /// last filled out with zeros past [`Self::bytes`].
    fn words_bytes(&self) -> u64 {
        self.pixels().div_ceil(4) * 12
    }

    fn check(&self) -> Option<()> {
        let Self { width, height } = *self;
        if width == 0 || height == 0 {
            return fail(format!("a picture is not empty, not {width}x{height}"));
        }
        // The pass counts a pixel's index, and four past it, in a u32.
        if self.pixels() + 4 > u64::from(u32::MAX) {
            return fail(format!("{width}x{height} pixels are more than a u32 counts"));
        }
        Some(())
    }
}

/// The over-the-ground pass.
pub(crate) struct OverGround {
    pipeline: wgpu::ComputePipeline,
}

impl OverGround {
    pub(crate) fn new(engine: &Engine) -> Self {
        let source = [TILE_WGSL, FRAME_WGSL, include_str!("over_ground.wgsl")].join("\n");
        let module = engine
            .device
            .create_shader_module(wgpu::ShaderModuleDescriptor {
                label: Some("over ground"),
                source: wgpu::ShaderSource::Wgsl(source.into()),
            });
        let pipeline = engine
            .device
            .create_compute_pipeline(&wgpu::ComputePipelineDescriptor {
                label: Some("over ground"),
                layout: None,
                module: &module,
                entry_point: Some("over_ground_pass"),
                compilation_options: Default::default(),
                cache: None,
            });
        Self { pipeline }
    }

    /// Lays `frame` — the composite's output tiles for the picture, asked
    /// row by row from its top-left tile — over `ground` (red, green,
    /// blue) and submits the work; the caller waits. Returns the buffer
    /// the RGB bytes are at the start of ([`OverGroundShape::bytes`] of
    /// them), to be copied out for reading.
    pub(crate) fn run(
        &self,
        engine: &Engine,
        frame: &wgpu::Buffer,
        shape: OverGroundShape,
        ground: [u8; 3],
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
        let row_groups = shape.width.div_ceil(4);
        let words = [
            columns,
            shape.width,
            shape.height,
            row_groups,
            u32::from_le_bytes([ground[0], ground[1], ground[2], 0]),
            0,
            0,
            0,
        ];
        let params = engine
            .device
            .create_buffer_init(&wgpu::util::BufferInitDescriptor {
                label: Some("over ground params"),
                contents: &words.iter().flat_map(|word| word.to_le_bytes()).collect::<Vec<_>>(),
                usage: wgpu::BufferUsages::UNIFORM,
            });
        let out = engine.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("over ground out"),
            size: shape.words_bytes(),
            usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
            mapped_at_creation: false,
        });
        let bind_group = engine.device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("over ground"),
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
            pass.dispatch_workgroups(row_groups.div_ceil(64), shape.height, 1);
        }
        engine.queue.submit([encoder.finish()]);
        Some(out)
    }
}
