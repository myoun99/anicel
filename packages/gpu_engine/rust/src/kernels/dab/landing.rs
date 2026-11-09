//! What lands on a cel (flip lane ⓒ): a row of tiles over the cel's own — a
//! stroke's view, a stamp's picture — as one plan, which the executor lays
//! and the write path puts in fresh slots of the pool.

use crate::device::Engine;
use crate::fail;
use crate::kernels::blend::mode;
use crate::kernels::composite::{Composite, Composited, Plan, Step, TILE, TileAt, TileSet};
use crate::kernels::mask::Mask;
use crate::kernels::pool::{Cel, Pool};
use crate::kernels::shared::ResampleMap;
use crate::kernels::write::{Change, Write};

/// A row's opacity at whole, the executor's 16-bit scale.
const WHOLE: u32 = 65535;

/// How a row lays on a cel: at `opacity` (65535 whole) in `mode`
/// (blend.wgsl's ids), under the selection `mask` if any.
pub(crate) struct Laid<'a> {
    pub(crate) opacity: u32,
    pub(crate) mode: u32,
    pub(crate) mask: Option<&'a Mask<'a>>,
}

/// A coordinate asked of a landing: its tile's column and row, and the cel's
/// tile there, if it has one.
#[derive(Clone, Copy)]
pub(crate) struct Asked {
    pub(crate) column: i32,
    pub(crate) row: i32,
    pub(crate) under: Option<TileAt>,
}

/// The row laid over the cel's tiles. Its pages follow the pool's — a plan's
/// tiles name a place on its one list of pages —, and `set` names them so.
pub(crate) struct Over<'a> {
    pub(crate) pages: &'a [wgpu::Buffer],
    pub(crate) set: TileSet,
}

/// What `over` makes of the tiles `asked`, tile after tile in their order:
/// each the cel's with the row laid on it as `laid` says. Submits the work,
/// the caller waits.
fn made(
    engine: &Engine,
    composite: &Composite,
    pool: &[wgpu::Buffer],
    over: Over,
    asked: &[Asked],
    laid: &Laid,
) -> Option<Composited> {
    let (x0, y0, columns, rows) = box_of(asked)?;
    let pages: Vec<wgpu::Buffer> = pool.iter().chain(over.pages).cloned().collect();
    let mut under = vec![None; columns as usize * rows as usize];
    for ask in asked {
        under[(ask.row - y0) as usize * columns as usize + (ask.column - x0) as usize] = ask.under;
    }
    let sets = [TileSet { x0, y0, columns, rows, tiles: under }, over.set];
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

/// Lays `over` on the tiles `asked` and puts each result in a fresh slot of
/// `cel`. Where `compared`, a result compares with the tile under it first —
/// waiting for the GPU — and takes no slot where it is that tile
/// (`Change::Same`) or has no ink left (`Change::Cleared`): a finished
/// landing's question. Unasked, every result is `Change::Inked` and a slot —
/// a stroke on its way, whose frame does not wait.
///
/// As many of `asked`, the first, as the pool has room for.
pub(crate) fn land(
    engine: &Engine,
    (composite, write, pool, cel): (&Composite, &Write, &mut Pool, Cel),
    over: Over,
    asked: &[Asked],
    laid: &Laid,
    compared: bool,
) -> Option<Vec<(Change, Option<TileAt>)>> {
    let out = made(engine, composite, pool.pages(), over, asked, laid)?.out;
    let changes = if compared {
        let under: Vec<Option<TileAt>> = asked.iter().map(|ask| ask.under).collect();
        write.changed(engine, pool.pages(), &out, &under)?
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

/// The top-left column and row of the box of tiles `asked`, and how many of
/// each it takes — or nothing, where it holds more words than one call can.
pub(super) fn box_of(asked: &[Asked]) -> Option<(i32, i32, u32, u32)> {
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
