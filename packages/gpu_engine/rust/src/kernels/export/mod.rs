//! The export's conversions before the readback (gpu-export-path ①, 저장):
//! a frame the composite left in its output tiles, turned on the GPU into
//! the bytes its writer takes, so fewer cross to the CPU — the readback
//! was the largest single cost (960×540: 27 ms against the encoder's 5.5).
//!
//! - `nv12` — a movie's frame for its encoder (①a).
//! - `over_ground` — a still's frame over its format's background, for the
//!   writers that keep no alpha (①b).
//! - `opaque` — whether a frame is opaque, so its PDF picture goes without
//!   alpha (①d).
//!
//! Each kernel reads the frame through `frame.wgsl`, after the shared
//! `tile.wgsl`, and runs as one pass over it ([`submit`]).

// ⏳Nothing outside the tests calls it until the app's bridge round
// (gpu-export-path, 관제 16:26 — the app connects after the bridges).
#![cfg_attr(not(test), allow(dead_code))]

mod nv12;
mod opaque;
mod over_ground;
#[cfg(test)]
mod tests;

pub(crate) use nv12::{Nv12, Nv12Shape};
pub(crate) use opaque::Opaque;
pub(crate) use over_ground::OverGround;

use wgpu::util::DeviceExt;

use crate::device::Engine;
use crate::fail;
use crate::kernels::composite::{TILE, TILE_TEXELS};
use crate::kernels::shared::{TILE_WGSL, pipeline};

/// The frame read: `frame_word`.
const FRAME_WGSL: &str = include_str!("frame.wgsl");

/// A picture in the frame, from its top-left pixel.
#[derive(Clone, Copy, Debug)]
pub(crate) struct Picture {
    pub(crate) width: u32,
    pub(crate) height: u32,
}

impl Picture {
    /// The frame's tiles a row and its rows of tiles.
    fn tiles(&self) -> (u32, u32) {
        (self.width.div_ceil(TILE), self.height.div_ceil(TILE))
    }

    fn pixels(&self) -> u64 {
        u64::from(self.width) * u64::from(self.height)
    }

    fn check(&self) -> Option<()> {
        let Self { width, height } = *self;
        if width == 0 || height == 0 {
            return fail(format!("a picture is not empty, not {width}x{height}"));
        }
        Some(())
    }
}

/// A kernel's pipeline: `own` after the frame read it calls.
fn compile(engine: &Engine, own: &str, entry: &str) -> wgpu::ComputePipeline {
    pipeline(engine, &[TILE_WGSL, FRAME_WGSL, own], entry)
}

/// None, with why, unless `frame` holds the tiles — a row of them, rows —
/// its picture is in.
fn holds(frame: &wgpu::Buffer, (columns, rows): (u32, u32)) -> Option<()> {
    let needed = u64::from(columns * rows) * TILE_TEXELS * 4;
    if frame.size() < needed {
        return fail(format!(
            "{columns}x{rows} tiles take {needed} bytes; the frame has {}",
            frame.size()
        ));
    }
    Some(())
}

/// Runs `pipeline` over `frame` in `groups` (across, down) and submits the
/// work; the caller waits. Its binding 0 is `params`, 1 the frame and 2
/// `out`.
fn submit(
    engine: &Engine,
    pipeline: &wgpu::ComputePipeline,
    params: &[u32],
    frame: &wgpu::Buffer,
    out: &wgpu::Buffer,
    (across, down): (u32, u32),
) {
    let params = engine
        .device
        .create_buffer_init(&wgpu::util::BufferInitDescriptor {
            label: Some("export params"),
            contents: &params.iter().flat_map(|word| word.to_le_bytes()).collect::<Vec<_>>(),
            usage: wgpu::BufferUsages::UNIFORM,
        });
    let bind_group = engine.device.create_bind_group(&wgpu::BindGroupDescriptor {
        label: Some("export"),
        layout: &pipeline.get_bind_group_layout(0),
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
        pass.set_pipeline(pipeline);
        pass.set_bind_group(0, &bind_group, &[]);
        pass.dispatch_workgroups(across, down, 1);
    }
    engine.queue.submit([encoder.finish()]);
}
