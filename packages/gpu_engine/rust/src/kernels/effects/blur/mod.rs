//! The Gaussian (fx Gaussian Blur, now Flutter's `ImageFilter.blur`) as the
//! blur brush's integer law: C's `qa_blur_box` (gpu-canonical-store ⑦ — one
//! blur law, 관제 11-05 12:19). A spatial pass the executor runs before a
//! plan lays its result as a row: it reads tiles a composite put and puts
//! blurred tiles in their place (gpu-canonical-store ② (a)).
//!
//! The picture is the input past which there is nothing, or — Repeat Edge
//! Pixels — a rectangle of it whose edge repeats outward, cut to that
//! rectangle (subtree_image_composite.dart's `cutAndBlurred`). Either way a
//! pixel's blur is the one the passes would leave on the whole plane: each
//! pass is worked out a radius further out than the next one reads, as C
//! gathers its window three radii out.
//!
//! ⏳The radius is the app's to give: how a Blurriness becomes a box radius
//! is the bridge round's, beside the brush's (`BrushBlurPicture.
//! blurRadiusOf` — three radii are the blur's reach).

#[cfg(test)]
mod tests;

use wgpu::util::DeviceExt;

use crate::device::Engine;
use crate::fail;
use crate::kernels::blend::BLEND_WGSL;
use crate::kernels::composite::{TILE, TILE_TEXELS};
use crate::kernels::shared::{ISQRT_WGSL, TILE_WGSL};

/// The widest box: a pass sums 2·radius + 1 pixels of 65535 at most, and
/// the sum stays a u32.
pub(crate) const MOST_RADIUS: u32 = 32767;
/// blur.wgsl's BLUR_RUN — the pixels one thread slides its sum along.
const RUN: u32 = 64;
/// blur.wgsl's workgroup, a side.
const GROUP: u32 = 8;

const EDGE_NONE: u32 = 0;
const EDGE_NOTHING: u32 = 1;
const EDGE_REPEAT: u32 = 2;

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
}

/// What a blur reads past its picture.
#[derive(Clone, Copy, Debug)]
pub(crate) enum Edge {
    /// Nothing: the tiles' rectangle is the picture.
    Nothing,
    /// The nearest pixel of these, [left, top, right, bottom) — inside the
    /// tiles —, and nothing is put outside them (Repeat Edge Pixels).
    Repeat([i32; 4]),
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

/// One dispatch of blur.wgsl: along the rows or down the columns, the
/// pixels it writes — [first, end) along, lines [line_first, line_end)
/// across — and its edge along.
struct Pass {
    down: bool,
    radius: u32,
    along: [i32; 2],
    lines: [i32; 2],
    edge: u32,
    edge_along: [i32; 2],
    from: Held,
    to: Held,
}

/// The blur pass, compiled once.
pub(crate) struct BoxBlur {
    pipeline: wgpu::ComputePipeline,
}

impl BoxBlur {
    pub(crate) fn new(engine: &Engine) -> Self {
        let source = [ISQRT_WGSL, BLEND_WGSL, TILE_WGSL, include_str!("blur.wgsl")].join("\n");
        let module = engine
            .device
            .create_shader_module(wgpu::ShaderModuleDescriptor {
                label: Some("blur"),
                source: wgpu::ShaderSource::Wgsl(source.into()),
            });
        let pipeline = engine
            .device
            .create_compute_pipeline(&wgpu::ComputePipelineDescriptor {
                label: Some("blur"),
                layout: None,
                module: &module,
                entry_point: Some("blur"),
                compilation_options: Default::default(),
                cache: None,
            });
        Self { pipeline }
    }

    /// Blurs `tiles` — straight RGBA8 over `rect` — by box passes of
    /// `radius` across and down, three each way, the rows' first, and
    /// returns the blurred tiles over the same rectangle; submits the work,
    /// the caller waits. A radius of 0 leaves its way as it is.
    pub(crate) fn run(
        &self,
        engine: &Engine,
        tiles: &wgpu::Buffer,
        rect: TileRect,
        radius: (u32, u32),
        edge: Edge,
    ) -> Option<wgpu::Buffer> {
        let (across, down) = radius;
        if across == 0 && down == 0 {
            return fail("a blur of no radius changes no pixel — a plan leaves it out");
        }
        if across > MOST_RADIUS || down > MOST_RADIUS {
            return fail(format!("{radius:?}: a box radius is {MOST_RADIUS} at most"));
        }
        let bytes = rect.tiles() * TILE_TEXELS * 4;
        if rect.tiles() == 0 || tiles.size() < bytes {
            return fail(format!(
                "{rect:?} is {} tiles; the buffer holds {} bytes",
                rect.tiles(),
                tiles.size()
            ));
        }
        let grid = rect.pixels();
        let (picture, kind) = match edge {
            // The columns' first pass reads the rows' plane, which ends at
            // the picture: past it is nothing by this edge, not by what a
            // read past a plane happens to give — 0 on the Surface, where
            // no test tells EDGE_NONE from it (mutant b19, 11-05).
            Edge::Nothing => (grid, EDGE_NOTHING),
            Edge::Repeat(inside) => {
                let [left, top, right, bottom] = inside;
                if left >= right
                    || top >= bottom
                    || left < grid[0]
                    || top < grid[1]
                    || right > grid[2]
                    || bottom > grid[3]
                {
                    return fail(format!("{inside:?} is no rectangle inside {grid:?}"));
                }
                (inside, EDGE_REPEAT)
            }
        };
        let passes = passes(picture, radius, kind);
        let plane = planes(picture, radius);
        let limits = engine.device.limits();
        let room = u64::from(limits.max_storage_buffer_binding_size).min(limits.max_buffer_size);
        if plane > room {
            return fail(format!(
                "a blur plane of {plane} bytes exceeds a binding of {room} — a picture this \
                 large waits for the round that cuts it into bands"
            ));
        }
        let most_lines = u64::from(limits.max_compute_workgroups_per_dimension) * u64::from(GROUP);
        if passes.iter().any(|pass| (pass.lines[1] - pass.lines[0]) as u64 > most_lines) {
            return fail(format!("{picture:?} has more lines than a dispatch reaches"));
        }
        let planes = [plane, plane].map(|size| {
            engine.device.create_buffer(&wgpu::BufferDescriptor {
                label: Some("blur plane"),
                size,
                usage: wgpu::BufferUsages::STORAGE,
                mapped_at_creation: false,
            })
        });
        // Nothing at first (wgpu zeroes a new buffer) — what Repeat leaves
        // outside its rectangle.
        let out = engine.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("blur out"),
            size: bytes,
            usage: wgpu::BufferUsages::STORAGE
                | wgpu::BufferUsages::COPY_DST
                | wgpu::BufferUsages::COPY_SRC,
            mapped_at_creation: false,
        });
        let layout = self.pipeline.get_bind_group_layout(0);
        let mut encoder = engine
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor::default());
        for (index, pass) in passes.iter().enumerate() {
            let from = match pass.from {
                Held::Tiles => tiles,
                Held::Plane { .. } => &planes[(index + 1) % 2],
            };
            let to = match pass.to {
                Held::Tiles => &out,
                Held::Plane { .. } => &planes[index % 2],
            };
            let mut words = vec![
                u32::from(pass.down),
                pass.radius,
                pass.along[0] as u32,
                pass.along[1] as u32,
                pass.lines[0] as u32,
                pass.lines[1] as u32,
                pass.edge,
                pass.edge_along[0] as u32,
                pass.edge_along[1] as u32,
            ];
            words.extend(pass.from.words());
            words.extend(pass.to.words());
            words.extend([grid[0] as u32, grid[1] as u32, rect.columns, rect.rows]);
            let uniform = engine
                .device
                .create_buffer_init(&wgpu::util::BufferInitDescriptor {
                    label: Some("blur pass"),
                    contents: &words.iter().flat_map(|word| word.to_le_bytes()).collect::<Vec<_>>(),
                    usage: wgpu::BufferUsages::UNIFORM,
                });
            let bind_group = engine.device.create_bind_group(&wgpu::BindGroupDescriptor {
                label: Some("blur"),
                layout: &layout,
                entries: &[
                    wgpu::BindGroupEntry {
                        binding: 0,
                        resource: uniform.as_entire_binding(),
                    },
                    wgpu::BindGroupEntry {
                        binding: 1,
                        resource: from.as_entire_binding(),
                    },
                    wgpu::BindGroupEntry {
                        binding: 2,
                        resource: to.as_entire_binding(),
                    },
                ],
            });
            let runs = ((pass.along[1] - pass.along[0]) as u32).div_ceil(RUN);
            let lines = (pass.lines[1] - pass.lines[0]) as u32;
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor::default());
            compute.set_pipeline(&self.pipeline);
            compute.set_bind_group(0, &bind_group, &[]);
            compute.dispatch_workgroups(runs.div_ceil(GROUP), lines.div_ceil(GROUP), 1);
        }
        engine.queue.submit([encoder.finish()]);
        Some(out)
    }
}

/// The passes blurring `picture`, [left, top, right, bottom), by `radius`
/// across and down: three along the rows, then three down the columns, a
/// way of radius 0 taking none. The k-th of a way writes (3 − k) radii past
/// the picture each side, all the k + 1-th reads; the first of a way reads
/// past the picture by `edge`. The first of all reads the tiles, the last
/// puts them; between, the planes hold the 16-bit pixels.
fn passes(picture: [i32; 4], radius: (u32, u32), edge: u32) -> Vec<Pass> {
    let [left, top, right, bottom] = picture;
    let (across, down) = radius;
    // A way's plane reaches two radii past the picture along it.
    let rows_plane = Held::Plane {
        x0: left - 2 * across as i32,
        y0: top,
        width: (right - left) as u32 + 4 * across,
    };
    let columns_plane = Held::Plane {
        x0: left,
        y0: top - 2 * down as i32,
        width: (right - left) as u32,
    };
    let ways = [
        (false, across, [left, right], [top, bottom], rows_plane),
        (true, down, [top, bottom], [left, right], columns_plane),
    ];
    let mut passes: Vec<Pass> = Vec::new();
    for (is_down, r, along, lines, plane) in ways {
        if r == 0 {
            continue;
        }
        for k in 1..=3 {
            let past = (3 - k) * r as i32;
            passes.push(Pass {
                down: is_down,
                radius: r,
                along: [along[0] - past, along[1] + past],
                lines,
                edge: if k == 1 { edge } else { EDGE_NONE },
                edge_along: along,
                from: passes.last().map_or(Held::Tiles, |before| before.to),
                to: plane,
            });
        }
    }
    if let Some(last) = passes.last_mut() {
        last.to = Held::Tiles;
    }
    passes
}

/// The bytes a plane holds: the rows' passes' or the columns', whichever
/// is more.
fn planes(picture: [i32; 4], radius: (u32, u32)) -> u64 {
    let [left, top, right, bottom] = picture;
    let (width, height) = (u64::from((right - left) as u32), u64::from((bottom - top) as u32));
    let rows = (width + 4 * u64::from(radius.0)) * height;
    let columns = width * (height + 4 * u64::from(radius.1));
    rows.max(columns) * 8
}
