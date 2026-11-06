//! A picture of letters — a cel number's, an SE name tag's — as the app's
//! canvas letters paint it (canvas_letter_passes.dart `CanvasLetterPasses`):
//! its layers bottom to top, each one paint's colour over the cover its
//! pass rastered, laid by the executor into straight RGBA8 tiles over one
//! rectangle — a chain's (`effects::blur::TileRect`), for the plan above it
//! to lay as a row (`chain::laid_as`) by copy. The letters are rastered
//! where they stand on the canvas's grid, their row's placement in their
//! own affine, so nothing poses them again (engine-canvas-letters;
//! connection-round-checklist 11-07 00:37 — the canvas grid, 🗣️Q1 of that
//! card, 유저 2026-11-07: 「캔버스 화소로 보인다」).
//!
//! A layer is laid as a row is: its colour, the cover as the row's alpha,
//! at the colour's alpha as the row's opacity. So a pass of translucent
//! letters and the hard letters' layer at its alpha (`_drawHard`) come out
//! of the executor's one formula, and no copy of it.

// ⏳Nothing outside the tests calls it until the connection round (the app's
// layout hands the engine its letters there).
#![cfg_attr(not(test), allow(dead_code))]

pub(crate) mod glyphs;
#[cfg(test)]
mod glyphs_tests;
#[cfg(test)]
mod tests;

use wgpu::util::DeviceExt;

use glyphs::{Affine, Faces, Paint, Shape, covered};

use crate::device::Engine;
use crate::fail;
use crate::kernels::blend::mode::NORMAL;
use crate::kernels::chain::tiles_of;
use crate::kernels::composite::{
    Composite, NO_EDGE, Plan, Step, TILE, TILE_BYTES, TILE_TEXELS, TileAt, TileSet,
};
use crate::kernels::effects::blur::TileRect;
use crate::kernels::shared::ResampleMap;

/// One pass of the letters, as `CanvasLetterPasses` paints them: the box
/// behind, the outlines, the fills — a run's lines with it.
pub(crate) struct Layer {
    /// Straight RGBA8, A<<24|B<<16|G<<8|R: the paint's colour, its alpha
    /// the layer's strength.
    pub(crate) colour: u32,
    /// Whether the letters are hard (`TextLetterStyle.antialias` off): a
    /// pixel the cover holds by half or more is the colour whole, any other
    /// none of it — `_drawHard`'s cliff at 127.5 of 255.
    pub(crate) hard: bool,
    pub(crate) cover: Cover,
}

/// A byte a pixel over the grid's pixels `at`, [left, top, right, bottom),
/// row by row.
pub(crate) struct Cover {
    pub(crate) at: [i32; 4],
    pub(crate) bytes: Vec<u8>,
}

impl Cover {
    fn byte(&self, x: i32, y: i32) -> u8 {
        let [left, top, right, bottom] = self.at;
        if x < left || y < top || x >= right || y >= bottom {
            return 0;
        }
        self.bytes[((y - top) * (right - left) + (x - left)) as usize]
    }
}

impl Layer {
    /// What the layer's row holds at the pixel: its colour, its cover the
    /// alpha — nothing at all where it covers none, as a stored pixel is.
    fn word(&self, x: i32, y: i32) -> u32 {
        let byte = u32::from(self.cover.byte(x, y));
        let cover = match self.hard {
            true if byte >= 128 => 255,
            true => 0,
            false => byte,
        };
        if cover == 0 {
            return 0;
        }
        cover << 24 | (self.colour & 0x00FF_FFFF)
    }

    /// Whether it covers any pixel at all.
    fn covers(&self) -> bool {
        let [left, top, right, bottom] = self.cover.at;
        (top..bottom).any(|y| (left..right).any(|x| self.word(x, y) != 0))
    }
}

/// One pass as the app paints it: its shapes, how, in what colour.
pub(crate) struct Pass {
    /// Straight RGBA8, A<<24|B<<16|G<<8|R.
    pub(crate) colour: u32,
    pub(crate) hard: bool,
    pub(crate) paint: Paint,
    pub(crate) shapes: Vec<Shape>,
}

/// `passes`, bottom to top, set in `faces` and laid on the grid by
/// `to_grid`: each pass's cover ([`covered`]) laid as a layer
/// ([`lettered`]). Submits the work; the caller waits.
pub(crate) fn set(
    engine: &Engine,
    composite: &Composite,
    faces: &Faces,
    to_grid: Affine,
    passes: &[Pass],
) -> Option<Lettered> {
    let layers: Vec<Layer> = passes
        .iter()
        .filter_map(|pass| {
            Some(Layer {
                colour: pass.colour,
                hard: pass.hard,
                cover: covered(faces, &pass.shapes, pass.paint, to_grid)?,
            })
        })
        .collect();
    lettered(engine, composite, &layers)
}

/// The picture of letters: straight RGBA8 tiles over `rect`, tile after
/// tile row by row.
pub(crate) struct Lettered {
    pub(crate) rect: TileRect,
    pub(crate) tiles: wgpu::Buffer,
}

/// `layers`, bottom to top, laid over nothing into the tiles of the one
/// rectangle that holds every pixel they cover. Submits the work; the
/// caller waits.
pub(crate) fn lettered(engine: &Engine, composite: &Composite, layers: &[Layer]) -> Option<Lettered> {
    let Some(rect) = rect_of(layers) else {
        return fail("letters that cover no pixel are no row — a plan leaves them out");
    };
    let tiles = tiles_of(rect);
    let (pages, sets) = paged(engine, layers, rect, &tiles)?;
    let steps: Vec<Step> = layers
        .iter()
        .enumerate()
        .map(|(set, layer)| Step::Row {
            set,
            keys: None,
            chain: None,
            map: ResampleMap::moved(0, 0),
            matrix: None,
            opacity: (layer.colour >> 24) * 257,
            mode: NORMAL,
            masked: false,
        })
        .collect();
    let plan = Plan {
        pages: &pages,
        sets: &sets,
        keys: &[],
        matrices: &[],
        chains: &[],
        steps: &steps,
        mask: None,
    };
    let done = composite.run(engine, &plan, &tiles, NO_EDGE, composite.widest())?;
    Some(Lettered { rect, tiles: done.out })
}

/// The tiles holding every pixel a layer covers, or `None` for none.
fn rect_of(layers: &[Layer]) -> Option<TileRect> {
    let side = TILE as i32;
    let boxes: Vec<[i32; 4]> = layers
        .iter()
        .filter(|layer| layer.covers())
        .map(|layer| layer.cover.at)
        .collect();
    let left = boxes.iter().map(|at| at[0]).min()?.div_euclid(side);
    let top = boxes.iter().map(|at| at[1]).min()?.div_euclid(side);
    let right = (boxes.iter().map(|at| at[2]).max()? - 1).div_euclid(side) + 1;
    let bottom = (boxes.iter().map(|at| at[3]).max()? - 1).div_euclid(side) + 1;
    Some(TileRect {
        x0: left,
        y0: top,
        columns: (right - left) as u32,
        rows: (bottom - top) as u32,
    })
}

/// Each layer's tiles of `tiles` — over `rect` — that it covers, put on as
/// few pages as a binding holds, and each layer's tile set of them.
fn paged(
    engine: &Engine,
    layers: &[Layer],
    rect: TileRect,
    tiles: &[(i32, i32)],
) -> Option<(Vec<wgpu::Buffer>, Vec<TileSet>)> {
    let binding = u64::from(engine.device.limits().max_storage_buffer_binding_size);
    let per_page = (binding / TILE_BYTES).min(u64::from(u16::MAX) + 1) as usize;
    if per_page == 0 {
        return fail(format!("a binding of {binding} bytes holds no tile"));
    }
    let side = TILE as i32;
    let mut pages: Vec<Vec<u32>> = Vec::new();
    let mut sets = Vec::with_capacity(layers.len());
    for layer in layers {
        let mut set = Vec::with_capacity(tiles.len());
        for &(column, row) in tiles {
            let words: Vec<u32> = (0..side)
                .flat_map(|y| (0..side).map(move |x| (column * side + x, row * side + y)))
                .map(|(x, y)| layer.word(x, y))
                .collect();
            if words.iter().all(|&word| word == 0) {
                set.push(None);
                continue;
            }
            if pages.last().is_none_or(|page| page.len() / TILE_TEXELS as usize == per_page) {
                pages.push(Vec::new());
            }
            let page = pages.len() - 1;
            let slot = pages[page].len() / TILE_TEXELS as usize;
            pages[page].extend(words);
            set.push(Some(TileAt {
                page: page as u16,
                slot: slot as u16,
            }));
        }
        sets.push(TileSet {
            x0: rect.x0,
            y0: rect.y0,
            columns: rect.columns,
            rows: rect.rows,
            tiles: set,
        });
    }
    let buffers = pages
        .iter()
        .map(|words| {
            let bytes: Vec<u8> = words.iter().flat_map(|word| word.to_le_bytes()).collect();
            engine.device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
                label: Some("letters page"),
                contents: &bytes,
                usage: wgpu::BufferUsages::STORAGE,
            })
        })
        .collect();
    Some((buffers, sets))
}
