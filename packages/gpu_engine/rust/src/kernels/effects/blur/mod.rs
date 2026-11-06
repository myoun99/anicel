//! The blurs an effect runs, each a spatial pass of its own that the
//! executor runs before a plan lays its result as a row: it reads tiles a
//! composite put and puts blurred tiles in their place
//! (gpu-canonical-store ② (a)).
//! - `gaussian` — fx Gaussian Blur, by the blur brush's box passes.
//! - `line` — a blur along a way: fx Directional Blur and Radial Blur.
//! - `lens` — fx Camera Lens Blur: its row sums, its light, and the mean
//!   of each pixel's iris over them.
//! - `iris` — the lens blur's iris, the table its gather reads rows by.
//!
//! They read and store a pixel alike, and keep it premultiplied on the
//! 16-bit scale in planes between their passes (`held.wgsl`) — one way in
//! and one way out, so two blurs of one picture cannot store it apart.

pub(crate) mod gaussian;
pub(crate) mod iris;
pub(crate) mod lens;
pub(crate) mod line;
#[cfg(test)]
mod pictures;

use crate::device::Engine;
use crate::fail;
use crate::kernels::blend::BLEND_WGSL;
use crate::kernels::composite::{TILE, TILE_TEXELS};
use crate::kernels::shared::{
    Encoded, ISQRT_WGSL, TILE_WGSL, encode, fits, flat, pipeline, plane, whole, words_buffer,
};

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
    let sources: Vec<&str> = [ISQRT_WGSL, BLEND_WGSL, TILE_WGSL]
        .iter()
        .chain(more)
        .chain(&[include_str!("held.wgsl"), own])
        .copied()
        .collect();
    pipeline(engine, &sources, entry)
}

/// Whether a blur can lay its passes at all: `tiles` hold `rect`, a
/// binding holds each of `planes` (bytes), and a dispatch reaches each of
/// `groups`.
fn checked(
    engine: &Engine,
    tiles: &wgpu::Buffer,
    rect: TileRect,
    planes: &[u64],
    groups: impl Iterator<Item = (u32, u32)>,
) -> Option<()> {
    if rect.tiles() == 0 || tiles.size() < rect.tiles() * TILE_TEXELS * 4 {
        return fail(format!(
            "{rect:?} is {} tiles; the buffer holds {} bytes",
            rect.tiles(),
            tiles.size()
        ));
    }
    fits(engine, planes, groups)
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
                bound: whole(&bound),
                groups: flat(dispatch.groups),
            }
        })
        .collect();
    encode(engine, &encoded);
    Some(out)
}
