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

use super::{Dab, Dabs, Paper, Second, StrokeTile};
use crate::device::Engine;
use crate::fail;
use crate::kernels::blend::mode;
use crate::kernels::composite::{
    Composite, Composited, Plan, Step, TILE, TILE_BYTES, TILE_TEXELS, TileAt, TileSet,
};
use crate::kernels::mask::Mask;
use crate::kernels::pool::{Cel, Pool};
use crate::kernels::shared::ResampleMap;
use crate::kernels::write::{Change, Write};

/// The tiles a page of the stroke's holds: its planes' 16 MiB, its view's 8
/// — well under what any device binds, and a pen stroke's dabs reach a page
/// or two. ⏳My number, not measured: settle it where a page's making shows
/// at pen-down on the Surface.
const TILES_A_PAGE: usize = 128;
/// A tile's bytes on the planes: two words a pixel.
const PLANE_TILE_BYTES: u64 = TILE_TEXELS * 8;
/// A row's opacity at whole, the executor's 16-bit scale.
const WHOLE: u32 = 65535;

/// How the stroke lays on a cel: at `opacity` (65535 whole) in `mode`
/// (blend.wgsl's ids), under the selection `mask` if any.
pub(crate) struct Laid<'a> {
    pub(crate) opacity: u32,
    pub(crate) mode: u32,
    pub(crate) mask: Option<&'a Mask<'a>>,
}

/// A coordinate asked of a stroke: its tile's column and row, and the cel's
/// tile there, if it has one.
#[derive(Clone, Copy)]
pub(crate) struct Asked {
    pub(crate) column: i32,
    pub(crate) row: i32,
    pub(crate) under: Option<TileAt>,
}

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

    /// What the stroke makes of the tiles `asked`, tile after tile in their
    /// order: each the cel's with the stroke laid on it as `laid` says.
    /// Submits the work, the caller waits.
    fn made(
        &self,
        engine: &Engine,
        composite: &Composite,
        pool: &[wgpu::Buffer],
        asked: &[Asked],
        laid: &Laid,
    ) -> Option<Composited> {
        let (x0, y0, columns, rows) = box_of(asked)?;
        // The stroke's pages follow the pool's: a plan's tiles name a place
        // on its one list of pages.
        let first = pool.len() as u16;
        let pages: Vec<wgpu::Buffer> = pool.iter().chain(&self.view).cloned().collect();
        let mut under = vec![None; columns as usize * rows as usize];
        let mut view = under.clone();
        for ask in asked {
            let at = (ask.row - y0) as usize * columns as usize + (ask.column - x0) as usize;
            under[at] = ask.under;
            view[at] = self.tiles.get(&(ask.column, ask.row)).map(|&TileAt { page, slot }| {
                TileAt { page: first + page, slot }
            });
        }
        let set = |tiles| TileSet { x0, y0, columns, rows, tiles };
        let sets = [set(under), set(view)];
        let row = |set, opacity, mode, masked| Step::Row {
            set,
            keys: None,
            chain: None,
            map: ResampleMap::moved(0, 0),
            matrix: None,
            opacity,
            mode,
            masked,
        };
        let steps = [
            row(0, WHOLE, mode::NORMAL, false),
            row(1, laid.opacity, laid.mode, laid.mask.is_some()),
        ];
        let plan = Plan {
            pages: &pages,
            sets: &sets,
            keys: &[],
            matrices: &[],
            chains: &[],
            steps: &steps,
            mask: laid.mask,
        };
        let tiles: Vec<(i32, i32)> = asked.iter().map(|ask| (ask.column, ask.row)).collect();
        let side = TILE as i32;
        let extent = [x0 * side, y0 * side, (x0 + columns as i32) * side, (y0 + rows as i32) * side];
        composite.run(engine, &plan, &tiles, extent, composite.widest())
    }

    /// Lays the stroke on the tiles `asked` and puts each result in a fresh
    /// slot of `cel`. Where `compared`, a result compares with the tile
    /// under it first — waiting for the GPU — and takes no slot where it is
    /// that tile (`Change::Same`) or has no ink left (`Change::Cleared`): a
    /// finished stroke's question. Unasked, every result is `Change::Inked`
    /// and a slot — a stroke on its way, whose frame does not wait.
    ///
    /// As many of `asked`, the first, as the pool has room for.
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
        let out = self.made(engine, composite, pool.pages(), asked, laid)?.out;
        let changes = if compared {
            let under: Vec<Option<TileAt>> = asked.iter().map(|ask| ask.under).collect();
            self.write.changed(engine, pool.pages(), &out, &under)?
        } else {
            vec![Change::Inked; asked.len()]
        };
        let mut landed = Vec::with_capacity(asked.len());
        let mut writes = Vec::with_capacity(asked.len());
        for (index, change) in changes.into_iter().enumerate() {
            if change != Change::Inked {
                landed.push((change, None));
                continue;
            }
            let Ok(at) = pool.fresh(engine, cel) else {
                break;
            };
            writes.push((index, at));
            landed.push((change, Some(at)));
        }
        Write::put(engine, pool.pages(), &out, &writes)?;
        Some(landed)
    }

    /// Clears what the stroke wrote and lets its tiles go; the pages stay
    /// for the next. Submits the work.
    pub(crate) fn clear(&mut self, engine: &Engine) {
        let mut encoder =
            engine.device.create_command_encoder(&wgpu::CommandEncoderDescriptor::default());
        clear_written(&mut encoder, &self.planes, self.tiles.len(), PLANE_TILE_BYTES);
        clear_written(&mut encoder, &self.view, self.tiles.len(), TILE_BYTES);
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

/// The top-left column and row of the box of tiles `asked`, and how many of
/// each it takes — or nothing, where it holds more words than one call can.
fn box_of(asked: &[Asked]) -> Option<(i32, i32, u32, u32)> {
    let column = |ask: &Asked| ask.column;
    let row = |ask: &Asked| ask.row;
    let x0 = asked.iter().map(column).min()?;
    let y0 = asked.iter().map(row).min()?;
    let columns = (asked.iter().map(column).max()? - x0 + 1) as u32;
    let rows = (asked.iter().map(row).max()? - y0 + 1) as u32;
    if u64::from(columns) * u64::from(rows) > u64::from(u32::MAX) {
        return fail(format!("a box of {columns} × {rows} tiles"));
    }
    Some((x0, y0, columns, rows))
}
