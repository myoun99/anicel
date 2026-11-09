//! A stroke as the app draws it (flip lane ⓒ): the pages its dabs pile on,
//! tiles taken on them as the dabs reach them, and the tiles it makes of a
//! cel.
//!
//! What it makes of a cel is one plan — the cel's tile, and over it the
//! stroke's view at the stroke's opacity, in its mode, under the selection —
//! which the executor lays and the write path puts in fresh slots of the
//! pool. The same call shows a stroke and finishes it: what is on screen
//! with the pen down is what lands when it lifts (유저 09-17).
//!
//! The stroke's pages are kept for the next stroke, cleared where it wrote:
//! a page takes a device tens of ms to make (11-08), a pause at each
//! pen-down were they made anew.

#[cfg(test)]
#[path = "stroke_tests.rs"]
mod tests;

use std::collections::HashMap;

use super::landing::{self, Asked, Laid, Over, box_of};
use super::{Dab, Dabs, Paper, Second, StrokeTile};
use crate::device::Engine;
use crate::kernels::composite::{Composite, TILE, TILE_BYTES, TILE_TEXELS, TileAt, TileSet};
use crate::kernels::pool::{Cel, Pool};
use crate::kernels::write::{Change, Write};

/// The tiles a page of the stroke's holds: its planes' 16 MiB, its view's 8
/// — well under what any device binds, and a pen stroke's dabs reach a page
/// or two. ⏳My number, not measured: settle it where a page's making shows
/// at pen-down on the Surface.
const TILES_A_PAGE: usize = 128;
/// A tile's bytes on the planes: two words a pixel.
const PLANE_TILE_BYTES: u64 = TILE_TEXELS * 8;
/// The kernels a stroke runs and the pages it has made, its tiles on them.
pub(crate) struct Stroke {
    dabs: Dabs,
    write: Write,
    planes: Vec<wgpu::Buffer>,
    view: Vec<wgpu::Buffer>,
    /// The second plane's — none till a stroke with a second tip comes.
    levels: Vec<wgpu::Buffer>,
    /// Each tile reached, in the slot the count made it: the slots are taken
    /// in order, so the count says where each page's written ones end.
    tiles: HashMap<(i32, i32), TileAt>,
}

impl Stroke {
    /// A stroke of no tiles — or nothing, where the device binds too few
    /// storage buffers a stage for its kernels.
    pub(crate) fn new(engine: &Engine) -> Option<Self> {
        Some(Self {
            dabs: Dabs::new(engine)?,
            write: Write::new(engine)?,
            planes: Vec::new(),
            view: Vec::new(),
            levels: Vec::new(),
            tiles: HashMap::new(),
        })
    }

    /// The bytes of the pages made.
    pub(crate) fn bytes(&self) -> u64 {
        let of = |pages: &[wgpu::Buffer]| pages.iter().map(wgpu::Buffer::size).sum::<u64>();
        of(&self.planes) + of(&self.view) + of(&self.levels)
    }

    /// Piles `dabs`, in their order, over `paper`, with a second tip shown
    /// by `second` — its mode and density — where the stroke has one.
    /// Submits the work, the caller waits.
    pub(crate) fn pile(
        &mut self,
        engine: &Engine,
        dabs: &[Dab],
        paper: Option<&Paper>,
        second: Option<(u32, f64)>,
    ) -> Option<()> {
        self.reach(engine, dabs);
        if second.is_some() {
            make_pages(engine, &mut self.levels, self.planes.len(), TILE_BYTES, "stroke levels");
        }
        let tiles = reached_by(&self.tiles, dabs);
        let plane = self.levels.as_slice();
        let second = second.map(|(mode, density)| Second { plane, mode, density });
        let pages = (self.planes.as_slice(), self.view.as_slice());
        self.dabs.pile(engine, &tiles, dabs, paper, second.as_ref(), pages)
    }

    /// Gives a tile to every coordinate `dabs` reach that has none, making
    /// the pages they take.
    fn reach(&mut self, engine: &Engine, dabs: &[Dab]) {
        for dab in dabs {
            for coordinate in tiles_of(dab.region) {
                let next = self.tiles.len();
                self.tiles.entry(coordinate).or_insert(TileAt {
                    page: (next / TILES_A_PAGE) as u16,
                    slot: (next % TILES_A_PAGE) as u16,
                });
            }
        }
        let pages = self.tiles.len().div_ceil(TILES_A_PAGE);
        make_pages(engine, &mut self.planes, pages, PLANE_TILE_BYTES, "stroke planes");
        make_pages(engine, &mut self.view, pages, TILE_BYTES, "stroke view");
    }

    /// The stroke's tiles at the coordinates `asked`, in their box, on a
    /// plan's pages from `first` on.
    fn view_of(&self, asked: &[Asked], first: u16) -> Option<TileSet> {
        let (x0, y0, columns, rows) = box_of(asked)?;
        let mut tiles = vec![None; columns as usize * rows as usize];
        for ask in asked {
            let at = (ask.row - y0) as usize * columns as usize + (ask.column - x0) as usize;
            tiles[at] = self.tiles.get(&(ask.column, ask.row)).map(|&TileAt { page, slot }| {
                TileAt { page: first + page, slot }
            });
        }
        Some(TileSet { x0, y0, columns, rows, tiles })
    }

    /// Lays the stroke on the tiles `asked`, each result in a fresh slot of
    /// `cel`: `landing::land`.
    pub(crate) fn land(
        &self,
        engine: &Engine,
        (composite, pool, cel): (&Composite, &mut Pool, Cel),
        asked: &[Asked],
        laid: &Laid,
        compared: bool,
    ) -> Option<Vec<(Change, Option<TileAt>)>> {
        if asked.is_empty() {
            return Some(Vec::new());
        }
        let set = self.view_of(asked, pool.pages().len() as u16)?;
        let over = Over { pages: &self.view, set };
        landing::land(engine, (composite, &self.write, pool, cel), over, asked, laid, compared)
    }

    /// Clears what the stroke wrote and lets its tiles go; the pages stay
    /// for the next. Submits the work. Its view needs none: a pile writes
    /// the whole of it on every tile it reaches, before anything reads it.
    pub(crate) fn clear(&mut self, engine: &Engine) {
        let mut encoder =
            engine.device.create_command_encoder(&wgpu::CommandEncoderDescriptor::default());
        clear_written(&mut encoder, &self.planes, self.tiles.len(), PLANE_TILE_BYTES);
        clear_written(&mut encoder, &self.levels, self.tiles.len(), TILE_BYTES);
        engine.queue.submit([encoder.finish()]);
        self.tiles.clear();
    }
}

/// Makes `pages` of `tile_bytes` tiles, those not made yet.
fn make_pages(
    engine: &Engine,
    made: &mut Vec<wgpu::Buffer>,
    pages: usize,
    tile_bytes: u64,
    label: &str,
) {
    while made.len() < pages {
        made.push(engine.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some(label),
            size: TILES_A_PAGE as u64 * tile_bytes,
            usage: wgpu::BufferUsages::STORAGE
                | wgpu::BufferUsages::COPY_DST
                | wgpu::BufferUsages::COPY_SRC,
            mapped_at_creation: false,
        }));
    }
}

/// Zeroes the first `tiles` tiles of `pages`, in slot order; a page not made
/// has none.
fn clear_written(
    encoder: &mut wgpu::CommandEncoder,
    pages: &[wgpu::Buffer],
    tiles: usize,
    tile_bytes: u64,
) {
    for (page, buffer) in pages.iter().enumerate() {
        let written = tiles.saturating_sub(page * TILES_A_PAGE).min(TILES_A_PAGE);
        if written > 0 {
            encoder.clear_buffer(buffer, 0, Some(written as u64 * tile_bytes));
        }
    }
}

/// The tiles `region`'s pixels are on, [left, top, right, bottom); none for
/// an empty one.
fn tiles_of([left, top, right, bottom]: [i32; 4]) -> impl Iterator<Item = (i32, i32)> {
    let side = TILE as i32;
    let empty = right <= left || bottom <= top;
    let rows = if empty { 0..0 } else { top.div_euclid(side)..(bottom - 1).div_euclid(side) + 1 };
    let columns = left.div_euclid(side)..(right - 1).div_euclid(side) + 1;
    rows.flat_map(move |row| columns.clone().map(move |column| (column, row)))
}

/// The stroke's tiles `dabs` reach, each once, in the order of their places:
/// a run of them on a page is what a pass binds (`shared::runs`).
fn reached_by(tiles: &HashMap<(i32, i32), TileAt>, dabs: &[Dab]) -> Vec<StrokeTile> {
    let reached: std::collections::HashSet<(i32, i32)> =
        dabs.iter().flat_map(|dab| tiles_of(dab.region)).collect();
    let mut made: Vec<StrokeTile> = reached
        .into_iter()
        .map(|(column, row)| StrokeTile { column, row, at: tiles[&(column, row)] })
        .collect();
    made.sort_by_key(|tile| (tile.at.page, tile.at.slot));
    made
}
