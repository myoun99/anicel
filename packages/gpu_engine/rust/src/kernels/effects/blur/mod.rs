//! The blurs an effect runs, each a spatial pass of its own that the
//! executor runs before a plan lays its result as a row: it reads tiles a
//! composite put and puts blurred tiles in their place
//! (gpu-canonical-store ② (a)).
//! - `gaussian` — fx Gaussian Blur, by the blur brush's box passes.
//! - `line` — a blur along a way: fx Directional Blur and Radial Blur.
//! - `lens` — fx Camera Lens Blur, so far its row sums and its light.
//!
//! They read and store a pixel alike, and keep it premultiplied on the
//! 16-bit scale in planes between their passes (`held.wgsl`) — one way in
//! and one way out, so two blurs of one picture cannot store it apart.

pub(crate) mod gaussian;
pub(crate) mod lens;
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

/// Whether a blur can lay its passes at all: `tiles` hold `rect`, a
/// binding holds each of `planes` (bytes), and a dispatch reaches each of
/// `groups`.
fn checked(
    engine: &Engine,
    tiles: &wgpu::Buffer,
    rect: TileRect,
    planes: &[u64],
    mut groups: impl Iterator<Item = (u32, u32)>,
) -> Option<()> {
    if rect.tiles() == 0 || tiles.size() < rect.tiles() * TILE_TEXELS * 4 {
        return fail(format!(
            "{rect:?} is {} tiles; the buffer holds {} bytes",
            rect.tiles(),
            tiles.size()
        ));
    }
    let limits = engine.device.limits();
    let room = u64::from(limits.max_storage_buffer_binding_size).min(limits.max_buffer_size);
    if let Some(plane) = planes.iter().find(|&&plane| plane > room) {
        return fail(format!(
            "a blur plane of {plane} bytes exceeds a binding of {room} — a picture this large \
             waits for the round that cuts it into bands"
        ));
    }
    let most = limits.max_compute_workgroups_per_dimension;
    if groups.any(|(across, down)| across > most || down > most) {
        return fail(format!("{rect:?} has more pixels than a dispatch reaches"));
    }
    Some(())
}

/// A buffer a pass reads or puts, of `bytes` — nothing at first: wgpu
/// zeroes a new buffer.
fn plane(engine: &Engine, label: &str, bytes: u64) -> wgpu::Buffer {
    engine.device.create_buffer(&wgpu::BufferDescriptor {
        label: Some(label),
        size: bytes,
        usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
        mapped_at_creation: false,
    })
}

/// `words` as a buffer a pass reads them from, `usage` its kind.
fn words_buffer(
    engine: &Engine,
    label: &str,
    words: &[u32],
    usage: wgpu::BufferUsages,
) -> wgpu::Buffer {
    let bytes: Vec<u8> = words.iter().flat_map(|word| word.to_le_bytes()).collect();
    engine
        .device
        .create_buffer_init(&wgpu::util::BufferInitDescriptor {
            label: Some(label),
            contents: &bytes,
            usage,
        })
}

/// held.wgsl's `Held` for a pass reading `from` and putting `to` over
/// `rect`'s tiles.
fn held_words(from: Held, to: Held, rect: TileRect) -> Vec<u32> {
    let grid = rect.pixels();
    let mut words = Vec::with_capacity(12);
    words.extend(from.words());
    words.extend(to.words());
    words.extend([grid[0] as u32, grid[1] as u32, rect.columns, rect.rows]);
    words
}

/// One dispatch as it is encoded: its pipeline, each buffer at the binding
/// it is bound to, and its workgroups.
struct Encoded<'a> {
    pipeline: &'a wgpu::ComputePipeline,
    bound: Vec<(u32, &'a wgpu::Buffer)>,
    groups: (u32, u32),
}

/// Encodes `dispatches` in order and submits them; the caller waits.
fn encode(engine: &Engine, dispatches: &[Encoded]) {
    let mut encoder = engine
        .device
        .create_command_encoder(&wgpu::CommandEncoderDescriptor::default());
    for dispatch in dispatches {
        let entries: Vec<wgpu::BindGroupEntry> = dispatch
            .bound
            .iter()
            .map(|&(binding, buffer)| wgpu::BindGroupEntry {
                binding,
                resource: buffer.as_entire_binding(),
            })
            .collect();
        let bind_group = engine.device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("blur"),
            layout: &dispatch.pipeline.get_bind_group_layout(0),
            entries: &entries,
        });
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor::default());
        compute.set_pipeline(dispatch.pipeline);
        compute.set_bind_group(0, &bind_group, &[]);
        compute.dispatch_workgroups(dispatch.groups.0, dispatch.groups.1, 1);
    }
    engine.queue.submit([encoder.finish()]);
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
    plane_bytes: u64,
    dispatches: &[Dispatch],
    taps: Option<&wgpu::Buffer>,
) -> Option<wgpu::Buffer> {
    checked(engine, tiles, rect, &[plane_bytes], dispatches.iter().map(|d| d.groups))?;
    // A pass between two others reads one plane and puts the other.
    let planes: Vec<wgpu::Buffer> = (0..if dispatches.len() > 1 { 2 } else { 0 })
        .map(|_| plane(engine, "blur plane", plane_bytes))
        .collect();
    // Nothing outside the pixels a blur puts.
    let out = plane(engine, "blur out", rect.tiles() * TILE_TEXELS * 4);
    let uniforms: Vec<[wgpu::Buffer; 2]> = dispatches
        .iter()
        .map(|dispatch| {
            [
                held_words(dispatch.from, dispatch.to, rect),
                dispatch.words.clone(),
            ]
            .map(|words| words_buffer(engine, "blur pass", &words, wgpu::BufferUsages::UNIFORM))
        })
        .collect();
    let encoded: Vec<Encoded> = dispatches
        .iter()
        .zip(&uniforms)
        .enumerate()
        .map(|(index, (dispatch, [held, own]))| {
            let from = match dispatch.from {
                Held::Tiles => tiles,
                Held::Plane { .. } => &planes[(index + 1) % 2],
            };
            let to = match dispatch.to {
                Held::Tiles => &out,
                Held::Plane { .. } => &planes[index % 2],
            };
            let mut bound = vec![(0, held), (1, from), (2, to), (3, own)];
            bound.extend(taps.map(|taps| (4, taps)));
            Encoded {
                pipeline,
                bound,
                groups: dispatch.groups,
            }
        })
        .collect();
    encode(engine, &encoded);
    Some(out)
}
