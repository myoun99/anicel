//! The blurs an effect runs, each a spatial pass of its own that the
//! executor runs before a plan lays its result as a row: it reads tiles a
//! composite put and puts blurred tiles in their place
//! (gpu-canonical-store ② (a)).
//! - `gaussian` — fx Gaussian Blur, by the blur brush's box passes.
//! - `line` — a blur along a way: fx Directional Blur and Radial Blur.
//!
//! Both read and store a pixel alike, and keep it premultiplied on the
//! 16-bit scale in planes between their passes (`held.wgsl`) — one way in
//! and one way out, so two blurs of one picture cannot store it apart.

pub(crate) mod gaussian;
pub(crate) mod line;
#[cfg(test)]
mod pictures;

use wgpu::util::DeviceExt;

use crate::device::Engine;
use crate::fail;
use crate::kernels::blend::BLEND_WGSL;
use crate::kernels::composite::{TILE, TILE_TEXELS};
use crate::kernels::shared::{ISQRT_WGSL, TILE_WGSL};

/// The workgroup's side in both passes' shaders.
const GROUP: u32 = 8;

/// A rectangle of the canvas's tiles, its top-left tile at column `x0`, row
/// `y0` — what a blur reads and puts: one straight RGBA8 tile after
/// another, row after row of them.
#[derive(Clone, Copy, Debug)]
pub(crate) struct TileRect {
    pub(crate) x0: i32,
    pub(crate) y0: i32,
    pub(crate) columns: u32,
    pub(crate) rows: u32,
}

impl TileRect {
    /// Its pixels, [left, top, right, bottom).
    fn pixels(&self) -> [i32; 4] {
        let side = TILE as i32;
        [
            self.x0 * side,
            self.y0 * side,
            (self.x0 + self.columns as i32) * side,
            (self.y0 + self.rows as i32) * side,
        ]
    }

    fn tiles(&self) -> u64 {
        u64::from(self.columns) * u64::from(self.rows)
    }

    /// Whether `inside`, [left, top, right, bottom), holds a pixel and lies
    /// within these tiles.
    fn holds(&self, inside: [i32; 4]) -> bool {
        let [left, top, right, bottom] = inside;
        let grid = self.pixels();
        left < right
            && top < bottom
            && left >= grid[0]
            && top >= grid[1]
            && right <= grid[2]
            && bottom <= grid[3]
    }
}

/// Where a pass keeps its pixels: the tiles, or a plane of two words a
/// pixel whose top-left pixel is `x0`, `y0`.
#[derive(Clone, Copy)]
enum Held {
    Tiles,
    Plane { x0: i32, y0: i32, width: u32 },
}

impl Held {
    fn words(self) -> [u32; 4] {
        match self {
            Held::Tiles => [1, 0, 0, 0],
            Held::Plane { x0, y0, width } => [0, x0 as u32, y0 as u32, width],
        }
    }
}

/// One dispatch: where it reads and puts, the words of its own pass
/// (binding 3), and its workgroups.
struct Dispatch {
    from: Held,
    to: Held,
    words: Vec<u32>,
    groups: (u32, u32),
}

/// A blur's pipeline: held.wgsl and what it needs, then `own`, whose entry
/// point is `entry` — after `more`, what `own` alone needs.
fn compile(engine: &Engine, more: &[&str], own: &str, entry: &str) -> wgpu::ComputePipeline {
    let source = [ISQRT_WGSL, BLEND_WGSL, TILE_WGSL]
        .iter()
        .chain(more)
        .chain(&[include_str!("held.wgsl"), own])
        .copied()
        .collect::<Vec<_>>()
        .join("\n");
    let module = engine
        .device
        .create_shader_module(wgpu::ShaderModuleDescriptor {
            label: Some(entry),
            source: wgpu::ShaderSource::Wgsl(source.into()),
        });
    engine
        .device
        .create_compute_pipeline(&wgpu::ComputePipelineDescriptor {
            label: Some(entry),
            layout: None,
            module: &module,
            entry_point: Some(entry),
            compilation_options: Default::default(),
            cache: None,
        })
}

/// Runs `dispatches` of `pipeline` over `tiles` — straight RGBA8 over
/// `rect` — with planes of `plane` bytes between them, and `taps` bound
/// fifth where given; returns the tiles the last one put, nothing where it
/// put none. Submits the work; the caller waits.
fn run(
    engine: &Engine,
    pipeline: &wgpu::ComputePipeline,
    tiles: &wgpu::Buffer,
    rect: TileRect,
    plane: u64,
    dispatches: &[Dispatch],
    taps: Option<&wgpu::Buffer>,
) -> Option<wgpu::Buffer> {
    let bytes = rect.tiles() * TILE_TEXELS * 4;
    if rect.tiles() == 0 || tiles.size() < bytes {
        return fail(format!(
            "{rect:?} is {} tiles; the buffer holds {} bytes",
            rect.tiles(),
            tiles.size()
        ));
    }
    let limits = engine.device.limits();
    let room = u64::from(limits.max_storage_buffer_binding_size).min(limits.max_buffer_size);
    if plane > room {
        return fail(format!(
            "a blur plane of {plane} bytes exceeds a binding of {room} — a picture this large \
             waits for the round that cuts it into bands"
        ));
    }
    let most = limits.max_compute_workgroups_per_dimension;
    if dispatches.iter().any(|dispatch| dispatch.groups.0 > most || dispatch.groups.1 > most) {
        return fail(format!("{rect:?} has more pixels than a dispatch reaches"));
    }
    // A pass between two others reads one plane and puts the other.
    let planes: Vec<wgpu::Buffer> = (0..if dispatches.len() > 1 { 2 } else { 0 })
        .map(|_| {
            engine.device.create_buffer(&wgpu::BufferDescriptor {
                label: Some("blur plane"),
                size: plane,
                usage: wgpu::BufferUsages::STORAGE,
                mapped_at_creation: false,
            })
        })
        .collect();
    // Nothing at first (wgpu zeroes a new buffer) — what a blur leaves
    // outside the pixels it puts.
    let out = engine.device.create_buffer(&wgpu::BufferDescriptor {
        label: Some("blur out"),
        size: bytes,
        usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
        mapped_at_creation: false,
    });
    let grid = rect.pixels();
    let layout = pipeline.get_bind_group_layout(0);
    let mut encoder = engine
        .device
        .create_command_encoder(&wgpu::CommandEncoderDescriptor::default());
    for (index, dispatch) in dispatches.iter().enumerate() {
        let from = match dispatch.from {
            Held::Tiles => tiles,
            Held::Plane { .. } => &planes[(index + 1) % 2],
        };
        let to = match dispatch.to {
            Held::Tiles => &out,
            Held::Plane { .. } => &planes[index % 2],
        };
        let mut held = Vec::with_capacity(12);
        held.extend(dispatch.from.words());
        held.extend(dispatch.to.words());
        held.extend([grid[0] as u32, grid[1] as u32, rect.columns, rect.rows]);
        let uniform = |label, words: &[u32]| {
            let bytes: Vec<u8> = words.iter().flat_map(|word| word.to_le_bytes()).collect();
            engine
                .device
                .create_buffer_init(&wgpu::util::BufferInitDescriptor {
                    label: Some(label),
                    contents: &bytes,
                    usage: wgpu::BufferUsages::UNIFORM,
                })
        };
        let held = uniform("blur held", &held);
        let own = uniform("blur pass", &dispatch.words);
        let mut entries = vec![
            wgpu::BindGroupEntry {
                binding: 0,
                resource: held.as_entire_binding(),
            },
            wgpu::BindGroupEntry {
                binding: 1,
                resource: from.as_entire_binding(),
            },
            wgpu::BindGroupEntry {
                binding: 2,
                resource: to.as_entire_binding(),
            },
            wgpu::BindGroupEntry {
                binding: 3,
                resource: own.as_entire_binding(),
            },
        ];
        if let Some(taps) = taps {
            entries.push(wgpu::BindGroupEntry {
                binding: 4,
                resource: taps.as_entire_binding(),
            });
        }
        let bind_group = engine.device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("blur"),
            layout: &layout,
            entries: &entries,
        });
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor::default());
        compute.set_pipeline(pipeline);
        compute.set_bind_group(0, &bind_group, &[]);
        compute.dispatch_workgroups(dispatch.groups.0, dispatch.groups.1, 1);
    }
    engine.queue.submit([encoder.finish()]);
    Some(out)
}
