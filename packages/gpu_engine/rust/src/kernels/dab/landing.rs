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
pub(crate) fn made(
    engine: &Engine,
    composite: &Composite,
    pool: &[wgpu::Buffer],
    over: Over,
    asked: &[Asked],
    laid: &Laid,
) -> Option<Composited> {
    let under = under_of(asked)?;
    let (x0, y0, columns, rows) = (under.x0, under.y0, under.columns, under.rows);
    let pages: Vec<wgpu::Buffer> = pool.iter().chain(over.pages).cloned().collect();
    let sets = [under, over.set];
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
        stamps: None,
    };
    let tiles: Vec<(i32, i32)> = asked.iter().map(|ask| (ask.column, ask.row)).collect();
    let side = TILE as i32;
    let extent = [x0 * side, y0 * side, (x0 + columns as i32) * side, (y0 + rows as i32) * side];
    composite.run(engine, &plan, &tiles, extent, composite.widest())
}

/// Lays `over` on the tiles `asked` and puts each result in a fresh slot of
/// `cel`: [`put`].
pub(crate) fn land(
    engine: &Engine,
    (composite, pool, cel): (&Composite, &mut Pool, Cel),
    over: Over,
    asked: &[Asked],
    laid: &Laid,
    compared: Option<&Write>,
) -> Option<Vec<(Change, Option<TileAt>)>> {
    let out = made(engine, composite, pool.pages(), over, asked, laid)?.out;
    put(engine, (pool, cel), &out, asked, compared)
}

/// Puts `out`'s tiles — one for each of `asked`, tile after tile in their
/// order, as the executor's output is — each in a fresh slot of `cel`. Where
/// `compared` — the write that compares —, a tile compares with the one
/// under it first — waiting for the GPU — and takes no slot where it is that
/// tile (`Change::Same`) or has no ink left (`Change::Cleared`): a finished
/// landing's question. Unasked, every tile is `Change::Inked` and a slot —
/// a stroke on its way, whose frame does not wait, and a picture the engine
/// drew landed as a cel's own (`gpu_engine_tiles_land`), which nothing
/// waits for.
///
/// ↩️Till 2026-11-16 `compared` was a bool beside a write every caller
/// handed, read only where it was true: the picture's landing has no write
/// to hand (card a-clip-vector-layer-is-read-back-to-be-tiled-again).
///
/// As many of `asked`, the first, as the pool has room for.
pub(crate) fn put(
    engine: &Engine,
    (pool, cel): (&mut Pool, Cel),
    out: &wgpu::Buffer,
    asked: &[Asked],
    compared: Option<&Write>,
) -> Option<Vec<(Change, Option<TileAt>)>> {
    let changes = if let Some(write) = compared {
        let under: Vec<Option<TileAt>> = asked.iter().map(|ask| ask.under).collect();
        write.changed(engine, pool.pages(), out, &under)?
    } else {
        vec![Change::Inked; asked.len()]
    };
    placed(engine, (pool, cel), out, changes.into_iter().enumerate())
}

/// A landing finished and yet to be put: its tiles made — tile after tile
/// in the order they were asked — and what each is beside the tile under
/// it. What takes a slot of it is its caller's to book
/// (`gpu_engine_finished_land_unwaited`): the pool's books are the
/// thread's that asks, and the answer comes on another.
pub struct Finished {
    out: wgpu::Buffer,
    changes: Vec<Change>,
}

impl Finished {
    /// What each tile is, in the order they were asked.
    pub(crate) fn changes(&self) -> &[Change] {
        &self.changes
    }

    /// The tiles made, tile after tile in the order they were asked.
    pub(crate) fn out(&self) -> &wgpu::Buffer {
        &self.out
    }

    /// The tiles that take a slot — the inked —, each by its place among
    /// those asked: as [`placed`] gives one to no other.
    pub(crate) fn inked(&self) -> impl Iterator<Item = usize> + '_ {
        let inked = |(at, change): (usize, &Change)| (*change == Change::Inked).then_some(at);
        self.changes.iter().enumerate().filter_map(inked)
    }
}

/// [`put`]'s question of `out` — the tiles `made` of `asked` —, asked with
/// no wait and no slot taken: `then` is told the landing finished on a
/// thread of the engine's once the GPU has said what each tile is
/// ([`Write::changed_then`]) — or nothing, where nothing was made or the
/// test failed.
///
/// 🗣️opening-a-transform-box-holds-the-ui-over-half-a-second (브러시/렌더링
/// 2026-11-20): a box at rest cuts its cels ahead of the press, and each
/// cut waited for this answer on the UI's thread — where a cut ahead
/// waits for nothing, so it is told.
pub(crate) fn finished_then(
    engine: &Engine,
    pool: &[wgpu::Buffer],
    out: Option<wgpu::Buffer>,
    asked: &[Asked],
    write: &Write,
    then: impl FnOnce(Option<Finished>) + Send + 'static,
) {
    let Some(out) = out else {
        return then(None);
    };
    let under: Vec<Option<TileAt>> = asked.iter().map(|ask| ask.under).collect();
    let made = out.clone();
    write.changed_then(engine, pool, &out, &under, move |changes| {
        then(changes.map(|changes| Finished { out: made, changes }));
    });
}

/// Puts each of `out`'s tiles that `changes` — every one by its index among
/// `out`'s — says is inked in a fresh slot of `cel`, the rest taking none:
/// where a landing that knows what it made ends.
///
/// As many of `changes`, the first, as the pool has room for.
pub(crate) fn placed(
    engine: &Engine,
    (pool, cel): (&mut Pool, Cel),
    out: &wgpu::Buffer,
    changes: impl Iterator<Item = (usize, Change)>,
) -> Option<Vec<(Change, Option<TileAt>)>> {
    let mut landed = Vec::new();
    let mut writes = Vec::new();
    for (index, change) in changes {
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
    Write::put(engine, pool.pages(), out, &writes)?;
    Some(landed)
}

/// The cel's tiles at the coordinates `asked`, in their box.
pub(super) fn under_of(asked: &[Asked]) -> Option<TileSet> {
    let (x0, y0, columns, rows) = box_of(asked)?;
    let mut tiles = vec![None; columns as usize * rows as usize];
    for ask in asked {
        tiles[(ask.row - y0) as usize * columns as usize + (ask.column - x0) as usize] = ask.under;
    }
    Some(TileSet { x0, y0, columns, rows, tiles })
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
