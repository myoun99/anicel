//! A plug-in's pictures between a chain's tiles and the plug-in's rows, on
//! the device — `tiles.wgsl` has the law.

use crate::device::Engine;
use crate::fail;
use crate::kernels::composite::{TILE, TILE_TEXELS};
use crate::kernels::effects::blur::TileRect;
use crate::kernels::shared::{Encoded, Kernel, TILE_WGSL, encode, plane, whole, words_buffer};

/// The read of a chain's tiles: one law for where a pixel of them lies.
const FRAME_WGSL: &str = include_str!("frame.wgsl");
const TILES_WGSL: &str = include_str!("tiles.wgsl");

/// The invocations a side of the passes' workgroups.
const GROUP_SIDE: u32 = 16;

/// A picture as a chain holds it: tile after tile over `rect`, row by row
/// of tiles, straight RGBA8 a word a pixel.
#[derive(Clone, Copy)]
pub(crate) struct Tiled<'a> {
    pub(crate) tiles: &'a wgpu::Buffer,
    pub(crate) rect: TileRect,
}

/// The two passes, compiled where the engine first asks one.
pub(crate) struct Tiles {
    rows_of: Kernel,
    tiles_of: Kernel,
}

impl Tiles {
    pub(crate) fn of(engine: &Engine) -> Self {
        let sources = [TILE_WGSL, FRAME_WGSL, TILES_WGSL];
        Self {
            rows_of: Kernel::of(engine, &sources, "plugin_rows_of_tiles"),
            tiles_of: Kernel::of(engine, &sources, "plugin_tiles_of_rows"),
        }
    }

    /// Compiles both where the engine has neither yet.
    pub(crate) fn compile(&self, engine: &Engine) {
        self.rows_of.pipeline(engine);
        self.tiles_of.pipeline(engine);
    }

    /// Lays `picture` — (left, top, width, height), canvas pixels — of
    /// `from`'s tiles into `rows` row after row from its word `first`,
    /// clear past the tiles. Submits the work; the caller waits.
    pub(crate) fn rows_of(&self, engine: &Engine, from: Tiled, picture: [i32; 4], rows: &wgpu::Buffer, first: u32) {
        let [_, _, width, height] = picture;
        let params = words_buffer(engine, "plugin rows params", &params(from.rect, picture, first), wgpu::BufferUsages::UNIFORM);
        let bound = [(0, &params), (1, from.tiles), (2, rows)];
        let groups = (groups_over(width), groups_over(height), 1);
        encode(engine, &[Encoded { pipeline: self.rows_of.pipeline(engine), bound: whole(&bound), groups }]);
    }

    /// The tiles over `rect` holding `picture` — (left, top, width,
    /// height), canvas pixels, row after row in `rows` from its word
    /// `first` — clear past it and wherever its alpha is 0. Submits the
    /// work; the caller waits.
    pub(crate) fn tiles_of(
        &self,
        engine: &Engine,
        rows: &wgpu::Buffer,
        first: u32,
        picture: [i32; 4],
        rect: TileRect,
    ) -> Option<wgpu::Buffer> {
        let count = u64::from(rect.columns) * u64::from(rect.rows);
        if count == 0 {
            return fail(format!("a plug-in's picture put over no tile: {rect:?}"));
        }
        let tiles = plane(engine, "plugin tiles", count * TILE_TEXELS * 4);
        let params = words_buffer(engine, "plugin tiles params", &params(rect, picture, first), wgpu::BufferUsages::UNIFORM);
        let bound = [(0, &params), (2, rows), (3, &tiles)];
        let groups = (groups_over((rect.columns * TILE) as i32), groups_over((rect.rows * TILE) as i32), 1);
        encode(engine, &[Encoded { pipeline: self.tiles_of.pipeline(engine), bound: whole(&bound), groups }]);
        Some(tiles)
    }
}

/// tiles.wgsl's `Params` for `picture` over `rect`'s tiles.
fn params(rect: TileRect, [left, top, width, height]: [i32; 4], first: u32) -> [u32; 8] {
    let side = TILE as i32;
    [
        rect.columns,
        rect.rows,
        (left - rect.x0 * side) as u32,
        (top - rect.y0 * side) as u32,
        width.max(0) as u32,
        height.max(0) as u32,
        first,
        0,
    ]
}

/// The workgroups a side of `pixels` takes.
fn groups_over(pixels: i32) -> u32 {
    (pixels.max(0) as u32).div_ceil(GROUP_SIDE)
}
