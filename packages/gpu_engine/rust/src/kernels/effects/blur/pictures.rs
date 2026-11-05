//! What the blurs' tests share: a picture put in tiles, and the tiles a
//! blur put, read back by canvas pixel.

use std::ops::Range;

use wgpu::util::DeviceExt;

use super::TileRect;
use crate::device::Engine;
use crate::kernels::composite::{TILE, TILE_TEXELS};
use crate::kernels::effects::tests::rgba;
use crate::testing::read_buffer;

pub(super) const ONE_TILE: TileRect = TileRect {
    x0: 0,
    y0: 0,
    columns: 1,
    rows: 1,
};

pub(super) const WHITE: u32 = rgba(255, 255, 255, 255);

/// White at each of `alphas`, which a blur of white keeps white: every
/// channel is its alpha, premultiplied.
pub(super) fn white(alphas: &[u32]) -> Vec<u32> {
    alphas
        .iter()
        .map(|&a| if a == 0 { 0 } else { rgba(255, 255, 255, a) })
        .collect()
}

/// Where canvas pixel (x, y) is among the words of `rect`'s tiles.
fn word_of(rect: TileRect, x: i32, y: i32) -> usize {
    let side = TILE as i32;
    let (lx, ly) = (x - rect.x0 * side, y - rect.y0 * side);
    let tile = (ly / side) as u64 * u64::from(rect.columns) + (lx / side) as u64;
    (tile * TILE_TEXELS) as usize + (ly % side * side + lx % side) as usize
}

/// `rect`'s tiles holding `pixel(x, y)` at each canvas pixel, on the GPU.
pub(super) fn tiles(
    engine: &Engine,
    rect: TileRect,
    pixel: impl Fn(i32, i32) -> u32,
) -> wgpu::Buffer {
    let [left, top, right, bottom] = rect.pixels();
    let mut words = vec![0u32; (rect.tiles() * TILE_TEXELS) as usize];
    for y in top..bottom {
        for x in left..right {
            words[word_of(rect, x, y)] = pixel(x, y);
        }
    }
    let bytes: Vec<u8> = words.iter().flat_map(|word| word.to_le_bytes()).collect();
    engine
        .device
        .create_buffer_init(&wgpu::util::BufferInitDescriptor {
            label: Some("blur cases"),
            contents: &bytes,
            usage: wgpu::BufferUsages::STORAGE,
        })
}

/// What a blur put over its tiles.
pub(super) struct Blurred {
    rect: TileRect,
    pub(super) words: Vec<u32>,
}

impl Blurred {
    /// `out`, the tiles over `rect` a blur put.
    pub(super) fn read(engine: &Engine, rect: TileRect, out: &wgpu::Buffer) -> Self {
        let words = read_buffer(engine, out)
            .chunks_exact(4)
            .map(|word| u32::from_le_bytes(word.try_into().unwrap()))
            .collect();
        Blurred { rect, words }
    }

    pub(super) fn at(&self, x: i32, y: i32) -> u32 {
        self.words[word_of(self.rect, x, y)]
    }

    pub(super) fn row(&self, y: i32, xs: Range<i32>) -> Vec<u32> {
        xs.map(|x| self.at(x, y)).collect()
    }

    pub(super) fn column(&self, x: i32, ys: Range<i32>) -> Vec<u32> {
        ys.map(|y| self.at(x, y)).collect()
    }
}

/// Blocks of nothing, of opaque and of any alpha, colour in every channel
/// but none where there is no alpha — as a stored pixel never holds.
pub(super) fn pattern(x: i32, y: i32) -> u32 {
    let (u, v) = (x.rem_euclid(256) as u32, y.rem_euclid(256) as u32);
    let alpha = match (u / 16 + v / 16) % 4 {
        0 => 0,
        1 => 255,
        _ => (u * 5 + v * 11) & 255,
    };
    if alpha == 0 {
        return 0;
    }
    rgba((u * 7 + v * 3) & 255, (u * v) & 255, u ^ v, alpha)
}

/// The tiles the ledger's blurs read: wider than tall, so a tile counted
/// by the wrong side lands elsewhere.
pub(super) const LEDGER_TILES: TileRect = TileRect {
    x0: -1,
    y0: 0,
    columns: 3,
    rows: 2,
};
