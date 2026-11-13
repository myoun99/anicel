//! The row composite — 2단계's executor, round E1 (gpu-canonical-store):
//! a plan of rows, folders and clipping groups, composited on the GPU into
//! output tiles in the blend family's one integer formula. Every route that
//! composites rows — the editing screen, a frame's picture, a panel, an
//! export — is to run this one executor, so what is shown while working and
//! what comes out cannot differ.
//!
//! The plan is the composite tree flattened into steps, bottom to top
//! ([`Step`]); the tree itself stays the app's (composite_tree.dart). E1
//! takes the five node kinds that close per pixel: a row in any pose R1
//! takes (a whole-pixel move being its copy), a folder's buffer, a row over
//! its backdrop (its own mode), a clipping group and its base made opaque —
//! and a colour over a rectangle, the paper and a camera render's ground.
//! A row's colour keys run on its stored pixels, before R1 poses them; its
//! colour matrix — the app's colour effects folded into one — on what R1
//! lays, after (캔버스 베이스, gpu-canonical-store 11-06 07:48). A buffer
//! may close through one too — an adjustment's colour-only chain over its
//! scope.
//! A row or a buffer may carry an effect chain past colour — the blurs the
//! app's chain lays before its final paint (kernels/chain). The executor
//! runs each before it walks the steps, the innermost first, as the app
//! rasters a folder's rows before its chain runs on them
//! (`drawSubtreeAsImage`): a row's over its stored tiles in its own space,
//! before its pose; a buffer's over its rows composited alone on the
//! canvas, put as bytes as the app's raster is. What a chain puts is laid
//! as a row in its place — a buffer's at its close's opacity, mode and
//! matrix, which the app's final paint is (`layerCompositePaint`) — so the
//! walk meets no chain.
//!
//! The pages a pass can bind are few — `max_storage_buffers_per_shader_stage`
//! less the plan and the work buffer, 2 where GLES reports 4 — so a plan is
//! cut into passes, each binding the pages of its run of rows. A copied row
//! whose tiles lie on several pages becomes one step per page: a pixel
//! reads one tile of it, so exactly one of them lays it. Any other pose
//! reads around where a pixel lands, so an output tile's pages are never
//! parted: its row is one step binding every page it reaches or, reaching
//! more than a pass binds, a step for each group of output tiles whose
//! pages a pass does bind. An output tile whose pixels alone reach more
//! reads its row's tiles under it gathered first onto a page of their own,
//! as a row copied whole lays them — their stored bytes, so the gathering
//! changes no value (11-06 — it was the last plan refused: a row its pose
//! shrinks reads many tiles under one output tile, and on a device of two
//! pages a pass their pages are soon more). A pass holds a window of the
//! stack in its registers, [`DEPTH`] levels at most, so a tree nested
//! deeper is cut where it leaves the window. Between passes the stack is
//! kept on the 16-bit scale as it was, so the cuts change no value.
//!
//! A row is sampled only on the output tiles where its pose reads a stored
//! tile of it; on any other it would show nothing, so it is skipped there.
//!
//! A row may be laid under the plan's selection (R28 — a stroke landing on
//! its cel under one): its opacity under the mask's cover, by blend.wgsl's
//! `blend_cover`; a row under none takes 255 by the same multiply. The mask
//! is a plane in the row's own space, read as its pixels are — through its
//! map by R1, in its mode, nothing past the box — so a landing, whose map
//! moves nothing, reads the byte at each pixel, and a posed row on the
//! screen reads its selection in its own artwork, as the app does. A pass
//! is given the rows of the mask its masked steps' maps read over its
//! output tiles, copied into `work` on the GPU and not bound on their own,
//! as the cel pixel verbs are given theirs — so a pass's output tiles span
//! no more tile rows than it takes tiles.
//!
//! A run puts its pixels as output tiles — straight, nothing outside the
//! output's extent, a page a later run can lay as a row — or on a surface
//! Flutter shows, premultiplied, inside a rectangle of it
//! ([`Composite::show`]). The screen is the second with one row: the
//! canvas's composite tiles posed by the camera — under 1/16 a halving
//! stage of them ([`halvings`]). The canvas is composited
//! on its own grid first, so a magnified screen shows the canvas's pixels
//! — the result's — and a pan or a zoom runs the screen alone
//! (gpu-canonical-store ④⑤).

pub(crate) mod abi;
#[cfg(test)]
mod chained_tests;
pub(crate) mod halvings;
pub(crate) mod held;
pub(crate) mod screen;
#[cfg(test)]
pub(crate) mod tests;

use std::ops::Range;
use std::sync::{Arc, Mutex, OnceLock, PoisonError};


use crate::device::Engine;
use crate::fail;
use crate::kernels::blend::BLEND_WGSL;
use crate::kernels::blend::mode::{NORMAL, PLUS};
use crate::kernels::chain::{Chain, Chained, laid_as, tiles_of, with_drawn};
use crate::kernels::effects::blur::TileRect;
use crate::kernels::effects::{KEY_WGSL, MATRIX_WGSL, MATRIX_WORDS};
use crate::kernels::mask::{BYTE_WGSL, Mask};
use crate::kernels::shared::{
    Encoded, ISQRT_WGSL, Own, PREMULTIPLY_WGSL, Pages, RESAMPLE_WGSL, ResampleMap, TILE_WGSL,
    ResampleModes, WIDE_WGSL, encode_on, le_bytes, page_table, pipeline_with, room, runs,
    storage_format, tiles_a_page, tiles_a_pass, whole, words_buffer,
};
use crate::platform::stores;

use held::Made;

/// A tile's side in pixels (1a ①).
pub(crate) const TILE: u32 = 128;
/// A tile's pixels — and its words, one RGBA8 pixel to a word.
pub(crate) const TILE_TEXELS: u64 = (TILE * TILE) as u64;
/// A tile's bytes, straight RGBA8 — as the pool stores it and a pass puts
/// it.
pub(crate) const TILE_BYTES: u64 = TILE_TEXELS * 4;
/// The most stack levels a pass holds in its registers. Folders and clips
/// nest deeper by cutting passes where the walk leaves the levels a pass
/// holds; the rest wait in the work buffer. A pass is compiled to hold the
/// levels its plan's passes reach (composite.wgsl's DEPTH), these at most.
pub(crate) const DEPTH: usize = 8;
const STEP_WORDS: usize = 14;
/// The word that names no tile, where a tile's word ([`TileAt::word`])
/// names one.
pub(crate) const NO_TILE: u32 = u32::MAX;
/// A row's matrix place where it runs none (composite.wgsl's NO_MATRIX).
const NO_MATRIX: u32 = u32::MAX;
/// An output with no edge: every pixel of every output tile as it is.
pub(crate) const NO_EDGE: [i32; 4] = [i32::MIN, i32::MIN, i32::MAX, i32::MAX];
/// Whole, on the 16-bit scale of an opacity and a mix.
pub(crate) const WHOLE: u32 = 65535;
/// The plan and the work buffer: the storage buffers a pass binds besides
/// its pages — and its pass's words, a uniform one. A device that binds
/// sixteen pages past them binds them past one fewer as well, so no test
/// here tells a count one short; a device of 19 buffers a stage would
/// compile a pass binding twenty.
const OWN_BUFFERS: u32 = 2;

/// Where a stored tile is: a page of the pool, a slot in it.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub(crate) struct TileAt {
    pub(crate) page: u16,
    pub(crate) slot: u16,
}

impl TileAt {
    /// The one word this tile is named by — `page << 16 | slot` — wherever
    /// a tile set travels as words: from the app over the C ABI
    /// ([`TileSet::from_words`]) and to a pass in its plan (composite.wgsl).
    pub(crate) fn word(self) -> u32 {
        u32::from(self.page) << 16 | u32::from(self.slot)
    }

    /// The tile `word` names ([`Self::word`]) — none for [`NO_TILE`].
    pub(crate) fn of_word(word: u32) -> Option<Self> {
        (word != NO_TILE).then(|| Self { page: (word >> 16) as u16, slot: word as u16 })
    }
}

/// A row's picture on the canvas's tile grid: the tiles of the rectangle
/// whose top-left tile is column `x0`, row `y0`, row by row. `None` is a
/// tile with nothing on it.
#[derive(Clone)]
pub(crate) struct TileSet {
    pub(crate) x0: i32,
    pub(crate) y0: i32,
    pub(crate) columns: u32,
    pub(crate) rows: u32,
    pub(crate) tiles: Vec<Option<TileAt>>,
}

impl TileSet {
    /// The set of `columns` × `rows` tiles whose top-left is column `x0`,
    /// row `y0`, named by `words` row by row — each a tile's
    /// [`TileAt::word`], or [`NO_TILE`] — as the app hands one over the C
    /// ABI: the plan's tile sets and the ink scan's cel alike.
    pub(crate) fn from_words(x0: i32, y0: i32, columns: u32, rows: u32, words: &[u32]) -> Self {
        let tiles = words.iter().copied().map(TileAt::of_word).collect();
        Self { x0, y0, columns, rows, tiles }
    }

    /// The tiles a box `size` across and down from `at` meets, row after
    /// row, `per_page` to a page from page `first_page` on: a stamp's
    /// (dab/stamp.rs).
    pub(crate) fn paged(at: (i32, i32), size: (u32, u32), first_page: u16, per_page: usize) -> Option<Self> {
        let mut set = Self::unplaced(at, size)?;
        let tiles: Option<Vec<Option<TileAt>>> = (0..set.tiles.len())
            .map(|tile| {
                let page = u16::try_from(tile / per_page).ok()?.checked_add(first_page)?;
                let slot = u16::try_from(tile % per_page).ok()?;
                Some(Some(TileAt { page, slot }))
            })
            .collect();
        let Some(tiles) = tiles else {
            return fail("a box's pages are past what a plan names");
        };
        set.tiles = tiles;
        Some(set)
    }

    /// The grid of the tiles a box `size` across and down from `at` meets,
    /// none of them placed yet: a kept picture's, whose tiles the pool it
    /// is kept in places ([`TileSet::place`]; halvings.rs).
    pub(crate) fn unplaced(at: (i32, i32), size: (u32, u32)) -> Option<Self> {
        let side = i64::from(TILE);
        let (left, top) = (i64::from(at.0), i64::from(at.1));
        let (width, height) = (i64::from(size.0), i64::from(size.1));
        // In tiles, ends excluded; an empty box meets none.
        let (x0, y0) = (left.div_euclid(side), top.div_euclid(side));
        let x1 = if width == 0 { x0 } else { (left + width - 1).div_euclid(side) + 1 };
        let y1 = if height == 0 { y0 } else { (top + height - 1).div_euclid(side) + 1 };
        let (Ok(x0), Ok(y0), Ok(columns), Ok(rows)) = (
            i32::try_from(x0),
            i32::try_from(y0),
            u32::try_from(x1 - x0),
            u32::try_from(y1 - y0),
        ) else {
            return fail("a box lies past the canvas's grid");
        };
        let count = columns as usize * rows as usize;
        Some(Self { x0, y0, columns, rows, tiles: vec![None; count] })
    }

    /// Every tile of the grid, placed or not, row after row, each row's
    /// from the left.
    fn grid(&self) -> Vec<(i32, i32)> {
        let (columns, rows) = (self.columns as i32, self.rows as i32);
        (self.y0..self.y0 + rows)
            .flat_map(|row| (self.x0..self.x0 + columns).map(move |column| (column, row)))
            .collect()
    }

    /// The grid's tile at `column`, `row` placed at `at`. Nothing for a
    /// tile past the grid.
    fn place(&mut self, (column, row): (i32, i32), at: TileAt) {
        let (c, r) = (column - self.x0, row - self.y0);
        if c >= 0 && r >= 0 && (c as u32) < self.columns && (r as u32) < self.rows {
            self.tiles[(r as u32 * self.columns + c as u32) as usize] = Some(at);
        }
    }

    fn at(&self, column: i32, row: i32) -> Option<TileAt> {
        let (c, r) = (column - self.x0, row - self.y0);
        if c < 0 || r < 0 || c as u32 >= self.columns || r as u32 >= self.rows {
            return None;
        }
        self.tiles[(r as u32 * self.columns + c as u32) as usize]
    }

    /// The tiles of the set under the pixels `[left, top, right, bottom)`,
    /// or all of them for `None`.
    fn under(&self, pixels: Option<[i64; 4]>) -> impl Iterator<Item = TileAt> + '_ {
        self.placed_under(pixels).map(|(_, at)| at)
    }

    /// `under`'s tiles, each at its column and row, row after row.
    fn placed_under(
        &self,
        pixels: Option<[i64; 4]>,
    ) -> impl Iterator<Item = ((i32, i32), TileAt)> + '_ {
        let side = i64::from(TILE);
        // In tiles, ends excluded.
        let first = (i64::from(self.x0), i64::from(self.y0));
        let end = (first.0 + i64::from(self.columns), first.1 + i64::from(self.rows));
        let [left, top, right, bottom] = match pixels {
            None => [first.0, first.1, end.0, end.1],
            Some([l, t, r, b]) => [
                l.div_euclid(side).max(first.0),
                t.div_euclid(side).max(first.1),
                (r.saturating_sub(1).div_euclid(side) + 1).min(end.0),
                (b.saturating_sub(1).div_euclid(side) + 1).min(end.1),
            ],
        };
        (top..bottom)
            .flat_map(move |row| (left..right).map(move |column| (column as i32, row as i32)))
            .filter_map(|(column, row)| Some(((column, row), self.at(column, row)?)))
    }
}

/// The tile set of `tiles` — row after row, each row's from the left — at
/// slot after slot of `page`.
fn placed_on(page: u16, tiles: &[(i32, i32)]) -> TileSet {
    let x0 = tiles.iter().map(|&(column, _)| column).min().unwrap_or(0);
    let x1 = tiles.iter().map(|&(column, _)| column).max().unwrap_or(x0 - 1);
    let y0 = tiles.first().map_or(0, |&(_, row)| row);
    let y1 = tiles.last().map_or(y0 - 1, |&(_, row)| row);
    let (columns, rows) = ((x1 - x0 + 1) as u32, (y1 - y0 + 1) as u32);
    let mut placed = vec![None; columns as usize * rows as usize];
    for (slot, &(column, row)) in tiles.iter().enumerate() {
        let at = (row - y0) as usize * columns as usize + (column - x0) as usize;
        placed[at] = Some(TileAt {
            page,
            slot: slot as u16,
        });
    }
    TileSet {
        x0,
        y0,
        columns,
        rows,
        tiles: placed,
    }
}

/// A row's colour keys: its runs, `KeyRun::words` each, in the chain's
/// order. They are walked on the row's stored pixels before R1 poses them,
/// as the app keys a cel before it is placed (캔버스 베이스,
/// gpu-canonical-store 11-05 18:24), every run against the pixel's stored
/// alpha.
#[derive(Clone)]
pub(crate) struct KeyChain {
    pub(crate) runs: Vec<Vec<u32>>,
}

/// What a copy is laid through ([`Composite::copied_through`]): a key
/// chain, a colour matrix, either or both.
#[derive(Clone, Copy, Default)]
pub(crate) struct Through<'a> {
    pub(crate) keys: Option<&'a KeyChain>,
    pub(crate) matrix: Option<&'a [u32; MATRIX_WORDS]>,
}

/// One step of a plan, bottom to top. An opacity is on the 16-bit scale
/// (65535 is whole); a mode is blend.wgsl's id, the eraser's and plus
/// among them.
#[derive(Clone, Copy, Debug)]
pub(crate) enum Step {
    /// Tile set `set`, keyed by chain `keys` if any or run through effect
    /// chain `chain` if any, posed by `map` — canvas pixel to the row's
    /// own —, through colour matrix `matrix` if any, laid at `opacity` in
    /// `mode`, under the plan's mask where `masked`. Keys and an effect
    /// chain are not both named: the chain's key runs are its ops.
    Row {
        set: usize,
        keys: Option<usize>,
        chain: Option<usize>,
        map: ResampleMap,
        matrix: Option<usize>,
        opacity: u32,
        mode: u32,
        masked: bool,
    },
    /// Opens a transparent buffer: a folder's, a clip's base or its scope.
    Open,
    /// Opens a buffer holding the one under it with its alpha made whole —
    /// a clip's scope whose rows blend with the base (CompositeOpaque).
    OpenOpaque,
    /// Closes a buffer onto the one under it at `opacity` in `mode`,
    /// through colour matrix `matrix` if any: an adjustment's scope, its
    /// mix folded into the matrix (`resolveAdjustmentScopePass`). The
    /// matrix runs on bytes, so the buffer is rounded to them first, as a
    /// stored pixel is — as the app's scope is, drawn to its layer's
    /// bytes before the filter runs. Through effect chain `chain` before
    /// the matrix, if one is named, at its mix: a folder's or an
    /// adjustment's, on a buffer opened on nothing ([`Step::Open`]).
    Close {
        opacity: u32,
        mode: u32,
        matrix: Option<usize>,
        chain: Option<BufferChain>,
    },
    /// Closes a clip's scope onto its base by the base's alpha (srcATop).
    CloseAtop,
    /// Closes a buffer opened on nothing ([`Step::Open`]) as the row it is
    /// the picture of: its steps, laid in the row's own space, drawn alone
    /// over the tiles `over` names there, and laid as that row is — posed
    /// by `map`, canvas pixel to the row's own, through colour matrix
    /// `matrix` if any, at `opacity` in `mode`. What a hand holds over a
    /// row (a lifted selection, a text being set) is drawn so: in the
    /// row's own pixels before its chain, as the canvas's walk draws it,
    /// and as it lies there once it lands (flip lane ⓐ-2).
    CloseRow {
        over: Over,
        map: ResampleMap,
        matrix: Option<usize>,
        opacity: u32,
        mode: u32,
    },
    /// Lays `colour` — straight RGBA8, A<<24|B<<16|G<<8|R, its alpha its
    /// strength — over the canvas pixels `rect`, [left, top, right,
    /// bottom), in normal, as a row of that colour there lays it: the paper
    /// under a cut's rows and a camera render's ground under them, each the
    /// bottom row of the root (`onUnderlay`) that a blend there reads
    /// (gpu-canonical-store 11-05 19:53 ⑦: the solid row's step, made for
    /// the bridge round).
    Solid { colour: u32, rect: [i32; 4] },
    /// The range a fill held down will cover, as the canvas marks it
    /// (fill_range_mark.dart, I-160-Q1 a): a checker of cells of 8 of the
    /// row's pixels, white where column + row is even and black where odd,
    /// each at half alpha, laid in normal under the plan's mask — the
    /// range, in the row's own space, `map` taking canvas pixels there as
    /// the row's does. Right after the row, so the rows above it hide it.
    /// `shift`, Q.16 of the row's pixels, pushes the cells the way the
    /// press moved (F-568-Q1 a).
    Mark { map: ResampleMap, shift: [i32; 2] },
}

/// What a step does to the buffers open: opens one over the one on top,
/// closes the one on top onto the one under it, or draws into it.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
enum Nesting {
    Opens,
    Closes,
    Draws,
}

impl Step {
    /// What the step does to the buffers open — the one place a step is
    /// told as opening or closing one, where six walks each told it.
    fn nesting(&self) -> Nesting {
        match self {
            Step::Open | Step::OpenOpaque => Nesting::Opens,
            Step::Close { .. } | Step::CloseAtop | Step::CloseRow { .. } => Nesting::Closes,
            Step::Row { .. } | Step::Solid { .. } | Step::Mark { .. } => Nesting::Draws,
        }
    }
}

/// What a buffer closed as a row ([`Step::CloseRow`]) is drawn over, in the
/// row's space: tiles of its own — those of them its output reads through
/// the row's pose —, or effect chain `Chain`'s, whose rectangle it runs on
/// whole as a row's chain runs on its picture.
#[derive(Clone, Copy, Debug)]
pub(crate) enum Over {
    Tiles(TileRect),
    Chain(usize),
}

/// A buffer's effect chain: chain `chain` of the plan, and how much of what
/// it puts the close lays against the buffer it ran on — an adjustment's
/// mix, (1−m)·U + m·F in one buffer, the second added by plus
/// (`composeAdjustmentScope`); whole for a folder's, which lays what its
/// chain puts alone. A row has no mix: its chain is an index alone.
#[derive(Clone, Copy, Debug)]
pub(crate) struct BufferChain {
    pub(crate) chain: usize,
    pub(crate) mix: u32,
}

/// What one pass may take: pages to bind, output tiles — as many as the
/// work buffer, stack and all, fits in one binding — and stack levels to
/// hold, 2 (a buffer and the one it closes onto) to [`DEPTH`].
#[derive(Clone, Copy, Debug)]
pub(crate) struct Budget {
    pub(crate) pages: usize,
    pub(crate) tiles: usize,
    pub(crate) levels: usize,
}

/// What a run left: every output tile's pixels, straight RGBA8, tile after
/// tile in the order asked — a page a later run can lay as a row, as the
/// screen lays the canvas's — and how many passes it took.
pub(crate) struct Composited {
    pub(crate) out: wgpu::Buffer,
    // Only the tests count a run's passes; a show returns its own.
    #[cfg_attr(not(test), allow(dead_code))]
    pub(crate) passes: usize,
}

/// What a plan lays: the pool's pages, the rows' tile sets, key chains,
/// colour matrices (`effects::matrix_words`) and effect chains, the steps,
/// bottom to top, and the selection its masked steps are laid
/// under — one a plan: the stroke being drawn is the row there is one for
/// (R28, 11-06 06:51), and a range mark's range is on that row.
pub(crate) struct Plan<'a> {
    pub(crate) pages: &'a [wgpu::Buffer],
    pub(crate) sets: &'a [TileSet],
    pub(crate) keys: &'a [KeyChain],
    pub(crate) matrices: &'a [[u32; MATRIX_WORDS]],
    pub(crate) chains: &'a [Chained<'a>],
    pub(crate) steps: &'a [Step],
    pub(crate) mask: Option<&'a Mask<'a>>,
}

/// Where a run's last pass puts its pixels.
enum Target<'a> {
    Tiles(&'a wgpu::Buffer),
    Placed(Placed<'a>),
    Surface(wgpu::TextureView),
}

/// Where a run puts each of its output tiles, in the order asked: a place
/// on `pages` each — fresh slots of the pool a picture is kept in
/// ([`Composite::run_onto`]).
#[derive(Clone, Copy)]
pub(crate) struct Placed<'a> {
    pub(crate) pages: &'a [wgpu::Buffer],
    pub(crate) at: &'a [TileAt],
}

/// The composite's work buffer, kept from one run to the next on its
/// engine: a run takes the one the last left where it holds what the run
/// needs, else makes one that does and leaves that.
///
/// A pass reads of it only what its own run put there — the mask's rows a
/// run copies in, the stack levels a pass saves for the next, the output
/// tiles the last pass puts whole, nothing where a pixel lies outside
/// (to_tiles.wgsl) — so what an earlier run left is nothing to the next.
/// And a run is one submit, so two runs' uses of it never cross.
///
/// ↩️Made for each run and dropped with it till 2026-11-13: 15 to 22 MiB a
/// picture of S5_BA cut 352, each through the device's allocator (🔬캔버스
/// 베이스, H57 — what [`crate::kernels::pool::Pictures`] says of the stops).
#[derive(Clone, Default)]
pub(crate) struct Work(Arc<Mutex<Option<wgpu::Buffer>>>);

impl Work {
    /// A work buffer of `size` bytes at least.
    fn of(&self, engine: &Engine, size: u64) -> wgpu::Buffer {
        let mut kept = self.0.lock().unwrap_or_else(PoisonError::into_inner);
        if let Some(work) = kept.as_ref().filter(|work| work.size() >= size) {
            return work.clone();
        }
        let work = engine.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("composite work"),
            size,
            usage: wgpu::BufferUsages::STORAGE
                | wgpu::BufferUsages::COPY_SRC
                | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });
        *kept = Some(work.clone());
        work
    }

    /// The buffer kept, let go: the next run makes its own.
    pub(crate) fn let_go(&self) {
        *self.0.lock().unwrap_or_else(PoisonError::into_inner) = None;
    }

    /// The bytes of the buffer kept.
    pub(crate) fn bytes(&self) -> u64 {
        let kept = self.0.lock().unwrap_or_else(PoisonError::into_inner);
        kept.as_ref().map_or(0, wgpu::Buffer::size)
    }
}

/// A step as the GPU reads it, the pages it lays a row from — one for a
/// copied row's step, every one its output tiles reach for any other
/// pose's — and, output
/// tile by output tile, whether it lays anything there: a row only where
/// it reads a stored tile on its pages, any other step everywhere.
struct Laid {
    step: Step,
    pages: Vec<u16>,
    live: Vec<bool>,
}

/// A run of steps one pass takes: the pages it binds, in binding order,
/// the lowest stack level it holds, the depth it starts at, and the highest
/// level it reaches.
struct Batch {
    begin: usize,
    end: usize,
    base: usize,
    depth_in: usize,
    depth_out: usize,
    high: usize,
    pages: Vec<u16>,
}

impl Batch {
    /// The stack levels its pass holds, from its base to the highest.
    fn levels(&self) -> usize {
        self.high + 1 - self.base
    }
}

/// The composite pass, compiled for as many pages as the device lets a pass
/// bind, once for each output and set of R1 modes ([`Compiled`]).
pub(crate) struct Composite {
    /// Shared with the threads that compile passes apart.
    passes: Arc<Mutex<Passes>>,
    /// The pages of the pool a pass binds, past the plan and the work.
    pages: Pages,
    /// The effect chains' blurs: seven kernels, compiled for a chain of any
    /// ops, a row's colour keys alone too. Not where the engine starts —
    /// the project an app starts on names no chain — and not under the plan
    /// that first names one, on the thread the frames are built on: the app
    /// compiles them off it and lays no plan that names a chain before they
    /// stand ([`Composite::chains`]; 🗣️관제 2026-11-10 18:14,
    /// gpu-canonical-store ⑦: 「UI 스레드가 직접 하는 커널 컴파일 0개」 —
    /// 🔬the seven were 6.5 s of a stopped UI where S5 opened on the
    /// Surface Pro 11). ↩️Until then it was compiled where a plan first
    /// named a chain (11-07), and a plan run before they stand still
    /// compiles them where it runs, as this crate's tests do.
    chain: OnceLock<Chain>,
}

/// The app compiles the chains on one thread while its frames run plans on
/// another (`gpu_engine_composite_chains`): that an executor may be shared
/// so is checked here, for the field that comes next.
const _: fn() = || {
    fn shared<T: Sync>() {}
    shared::<Composite>();
};

impl Composite {
    pub(crate) fn new(engine: &Engine) -> Option<Self> {
        Self::showing(engine, None)
    }

    /// [`Composite::new`], and with it the full pass that stores to a
    /// surface of `format`, so that the first [`Composite::show`] onto one
    /// compiles nothing: the app asks where it makes the executor, off the
    /// thread its frames are built on (gpu-canonical-store ⑦, as
    /// [`Composite::chains`]). None where this adapter stores to no such
    /// surface: none is made there (`platform::Surface`).
    ///
    /// The tiles' full pass is compiled here, where the engine starts, not
    /// under a canvas's first composite — as before passes came apart. Only
    /// when the compile is paid changes; no test sees it.
    ///
    /// 🗣️유저 2026-11-13 (the-wait-window-stands-seven-seconds-on-the-surface-Q1,
    /// 「나란히 컴파일」): the two at once, each on a thread of the engine's
    /// for compiling (`CompilerTurn`). 🔬One after the other they were the
    /// app's wait window's last 3.2 s on the Surface Pro 11 with no shader
    /// kept (1.76 s and 1.40 s, 11-13), all else in it through 2.5 s before.
    /// ↩️The surface's was a call of its own after this one till then.
    pub(crate) fn showing(engine: &Engine, format: Option<wgpu::TextureFormat>) -> Option<Self> {
        let own = Own { storage: OWN_BUFFERS, uniform: 1 };
        let pages = Pages::new(engine, own, OWN_BUFFERS + 1)?;
        let composite = Self {
            passes: Arc::default(),
            pages,
            chain: OnceLock::new(),
        };
        let shown = format.filter(|&format| stores(engine, format)).and_then(storage_format);
        let fulls = [Some(Compiled::full(None)), shown.map(|token| Compiled::full(Some(token)))];
        let (source, binding) = (&composite.pages.source(), composite.surface_binding());
        let made: Vec<_> = std::thread::scope(|scope| {
            let compiling: Vec<_> = fulls
                .into_iter()
                .flatten()
                .map(|full| scope.spawn(move || (full, compile(engine, source, binding, full))))
                .collect();
            compiling.into_iter().map(|one| one.join().expect("a full pass compiled")).collect()
        });
        let mut passes = composite.passes.lock().unwrap_or_else(PoisonError::into_inner);
        passes.asked.extend(made.into_iter().map(|(full, pipeline)| (full, Some(pipeline))));
        drop(passes);
        Some(composite)
    }

    /// The effect chains' blurs, compiled where the caller is if they are
    /// not — or waited for, where another thread is at it.
    pub(crate) fn chains(&self, engine: &Engine) -> &Chain {
        self.chain.get_or_init(|| Chain::new(engine))
    }

    /// All this device lets a pass take.
    pub(crate) fn widest(&self) -> Budget {
        Budget {
            pages: self.pages.per_pass(),
            tiles: usize::MAX,
            levels: DEPTH,
        }
    }

    /// Composites `plan` over the output `tiles` (canvas tile columns and
    /// rows), with nothing outside `extent` — the output's pixels, [left,
    /// top, right, bottom): a canvas's picture ends at the canvas — and
    /// submits the work; the caller waits. A `budget` under
    /// [`Composite::widest`] cuts the run where a smaller device would.
    pub(crate) fn run(
        &self,
        engine: &Engine,
        plan: &Plan,
        tiles: &[(i32, i32)],
        extent: [i32; 4],
        budget: Budget,
    ) -> Option<Composited> {
        let out = engine.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("composite out"),
            size: (tiles.len().max(1) as u64) * TILE_TEXELS * 4,
            usage: wgpu::BufferUsages::STORAGE
                | wgpu::BufferUsages::COPY_DST
                | wgpu::BufferUsages::COPY_SRC,
            mapped_at_creation: false,
        });
        let target = Target::Tiles(&out);
        let passes = self.walk(engine, plan, tiles, extent, None, &target, budget)?;
        Some(Composited { out, passes })
    }

    /// [`Composite::run`], each output tile's pixels put at its place in
    /// `onto` — one a tile, in the order asked — and no buffer of the run's
    /// own made for them: how a picture is kept in the pictures' pool
    /// (halvings.rs, `Kept`). Submits the work; returns how many passes it
    /// took.
    ///
    /// ⚠️A place is a FRESH slot: one no pass of this run reads, so the
    /// pages `onto` names may be pages `plan` lays rows from — a halving
    /// stage reads the stage above it off the pool it is kept in.
    pub(crate) fn run_onto(
        &self,
        engine: &Engine,
        plan: &Plan,
        tiles: &[(i32, i32)],
        extent: [i32; 4],
        onto: Placed,
        budget: Budget,
    ) -> Option<usize> {
        if onto.at.len() != tiles.len() {
            return fail(format!("{} places for {} output tiles", onto.at.len(), tiles.len()));
        }
        self.walk(engine, plan, tiles, extent, None, &Target::Placed(onto), budget)
    }

    /// `tiles` of `set` — its tiles on `pages` — as a row copied whole over
    /// nothing lays them: their stored bytes, tile after tile in `tiles`'
    /// order, nothing for a tile the set has none of, and no edge — a
    /// stroke reaches past the canvas onto the pasteboard
    /// (BrushBlurPicture's wall), where a cel has tiles too. The blur
    /// brush's picture is made of it (dab/blur.rs), and a row whose pages
    /// under one output tile a pass cannot bind is read from it
    /// ([`Composite::gathered`]). Submits the work; the caller waits.
    pub(crate) fn copied(
        &self,
        engine: &Engine,
        pages: &[wgpu::Buffer],
        set: &TileSet,
        tiles: &[(i32, i32)],
        budget: Budget,
    ) -> Option<Composited> {
        self.copied_through(engine, pages, set, tiles, Through::default(), budget)
    }

    /// [`Composite::copied`], keyed by `through.keys` and through
    /// `through.matrix` as a row is — an effect chain's colour steps
    /// (kernels/chain).
    pub(crate) fn copied_through(
        &self,
        engine: &Engine,
        pages: &[wgpu::Buffer],
        set: &TileSet,
        tiles: &[(i32, i32)],
        through: Through,
        budget: Budget,
    ) -> Option<Composited> {
        let steps = [Step::Row {
            set: 0,
            keys: through.keys.map(|_| 0),
            chain: None,
            map: ResampleMap::moved(0, 0),
            matrix: through.matrix.map(|_| 0),
            // Whole. 65534 copies the same bytes — a stored byte's step is 257
            // on this scale — so no test tells the two apart (mutant r04, 11-06).
            opacity: 65535,
            mode: NORMAL,
            masked: false,
        }];
        let plan = Plan {
            pages,
            sets: std::slice::from_ref(set),
            keys: through.keys.map_or(&[], std::slice::from_ref),
            matrices: through.matrix.map_or(&[], std::slice::from_ref),
            chains: &[],
            steps: &steps,
            mask: None,
        };
        self.run(engine, &plan, tiles, NO_EDGE, budget)
    }

    /// Composites `plan` onto the pixels `rect` of `surface` — [left, top,
    /// right, bottom), the output's pixels being the surface's own — and
    /// leaves the rest of it as it was, the other panels of an atlas;
    /// submits the work and returns how many passes it took. The screen is
    /// this with one row: the canvas's composite posed by the camera
    /// (gpu-canonical-store ④⑤).
    ///
    /// 🚨IT DOES NOT WAIT — what hands the surface to Flutter does, off the
    /// thread that asked ([`Engine::done_then`], the app's screen texture):
    /// Flutter shows a surface without waiting on the engine's work — on
    /// Windows nothing tells either side the other is done
    /// (gpu-engine-feasibility ⑤), on Apple's Flutter waits on no GPU work
    /// of ours (the Apple bridge's ①), on Android it waits on an image's
    /// fence from API 33 only — so a surface handed over before the GPU is
    /// done shows what it held. What reads the surface back waits as a read
    /// does. ↩️It waited here, as the fill, the grid and the wave do, until
    /// a screen's frame was put up as the GPU finished it (🗣️유저
    /// 2026-11-12, a-float-in-hand-draws-the-frame-as-it-stands-Q2): 🔬on the
    /// Surface Pro 11 the UI thread waited here ≈19 ms of a frame's 22, a
    /// float dragged over the whole of S5 cut 352.
    pub(crate) fn show(
        &self,
        engine: &Engine,
        plan: &Plan,
        surface: &wgpu::Texture,
        rect: [u32; 4],
        budget: Budget,
    ) -> Option<usize> {
        let [left, top, right, bottom] = rect;
        if left >= right || top >= bottom || right > surface.width() || bottom > surface.height() {
            return fail(format!(
                "{rect:?} is no rectangle of a {} × {} surface",
                surface.width(),
                surface.height()
            ));
        }
        let Some(token) = storage_format(surface.format()) else {
            return fail(format!("the composite cannot store to {:?}", surface.format()));
        };
        let tiles: Vec<(i32, i32)> = (top / TILE..bottom.div_ceil(TILE))
            .flat_map(|row| {
                (left / TILE..right.div_ceil(TILE)).map(move |column| (column as i32, row as i32))
            })
            .collect();
        let target = Target::Surface(surface.create_view(&Default::default()));
        let extent = rect.map(|edge| edge as i32);
        self.walk(engine, plan, &tiles, extent, Some(token), &target, budget)
    }

    /// The surface's binding: past the plan, the work buffer and the pages.
    fn surface_binding(&self) -> u32 {
        self.pages.end()
    }

    /// The pass for `wanted`'s output that reads maps of `wanted`'s modes
    /// and holds `wanted`'s levels: the one compiled for those once a thread
    /// has made it, and until then the full one, for every mode and level,
    /// which composites the same bytes, slower. A compile takes seconds
    /// where a frame takes milliseconds (1.7 s to 6 s cold on this PC,
    /// 11-06), so no plan waits on one but an output's first: the full one,
    /// compiled where it is first asked for — the tiles' in `new`, a
    /// surface's in `shows` where the app has said what its screens are —
    /// as before passes came apart.
    fn pass(&self, engine: &Engine, wanted: Compiled) -> wgpu::ComputePipeline {
        let full = Compiled::full(wanted.surface);
        let mut passes = self.passes.lock().unwrap_or_else(PoisonError::into_inner);
        let for_full = passes.made(full).unwrap_or_else(|| {
            let pipeline = compile(engine, &self.pages.source(), self.surface_binding(), full);
            passes.asked.push((full, Some(pipeline.clone())));
            pipeline
        });
        if let Some(pipeline) = passes.made(wanted) {
            return pipeline;
        }
        if !passes.was_asked(wanted) {
            passes.asked.push((wanted, None));
            // One thread at a time (`compile_apart`): a second would take a
            // second core from the frames. No test sees it.
            if !passes.compiling {
                passes.compiling = true;
                self.compile_apart(engine);
            }
        }
        for_full
    }

    /// Compiles the passes asked for and not made, the latest asked first,
    /// on a thread of its own that ends once none is left. One thread, one
    /// pass at a time: it takes one core from the frames, whatever a session
    /// asks for at once — a tablet has few. The latest first, as the plan on
    /// screen now is the one likeliest to be asked again; which goes first
    /// changes only when each is made, and no test sees it.
    ///
    /// Each waits its turn behind what the app compiles ahead for a hand
    /// (`Apart`, in `device.rs`): no one waits for a pass of a plan's own.
    fn compile_apart(&self, engine: &Engine) {
        let (engine, passes) = (engine.clone(), Arc::clone(&self.passes));
        let (pages, surface_binding) = (self.pages.source(), self.surface_binding());
        std::thread::spawn(move || loop {
            engine.apart.wait();
            let mut held = passes.lock().unwrap_or_else(PoisonError::into_inner);
            let next = held.asked.iter().rev().find(|(_, made)| made.is_none());
            let Some(&(wanted, _)) = next else {
                held.compiling = false;
                return;
            };
            drop(held);
            let pipeline = compile(&engine, &pages, surface_binding, wanted);
            let mut held = passes.lock().unwrap_or_else(PoisonError::into_inner);
            let asked = held.asked.iter_mut().find(|(asked, _)| *asked == wanted);
            if let Some((_, made)) = asked {
                *made = Some(pipeline);
            }
        });
    }

    /// Waits for the thread compiling passes apart to end.
    #[cfg(test)]
    pub(crate) fn settle(&self) {
        // Only a thread that never ends should fail here, never a slow one.
        let deadline = std::time::Instant::now() + std::time::Duration::from_secs(600);
        let making = || self.passes.lock().unwrap_or_else(PoisonError::into_inner).compiling;
        while making() {
            assert!(std::time::Instant::now() < deadline, "a pass compiled apart never came");
            std::thread::sleep(std::time::Duration::from_millis(1));
        }
    }

    /// Walks `plan` over the output `tiles` in passes whose last puts each
    /// pixel to `target` — the output tiles, or a surface of the format
    /// `surface` names —, inside `extent` as it is and outside nothing or
    /// nowhere, and submits the work; returns how many passes it took.
    fn walk(
        &self,
        engine: &Engine,
        plan: &Plan,
        tiles: &[(i32, i32)],
        extent: [i32; 4],
        surface: Option<&'static str>,
        target: &Target,
        budget: Budget,
    ) -> Option<usize> {
        let pages_per_pass = budget.pages;
        if pages_per_pass == 0 || pages_per_pass > self.pages.per_pass() {
            return fail(format!(
                "{pages_per_pass} pages a pass; this device binds 1 to {}",
                self.pages.per_pass()
            ));
        }
        if !(2..=DEPTH).contains(&budget.levels) {
            return fail(format!("{} stack levels a pass; one holds 2 to {DEPTH}", budget.levels));
        }
        check_depth(
            plan.steps,
            plan.sets.len(),
            plan.keys.len(),
            plan.matrices.len(),
            plan.chains.len(),
        )?;
        check_mask(plan)?;
        if plan.steps.iter().any(runs_first) {
            let (pages, sets, steps) = self.chained(engine, plan, tiles, budget)?;
            let plan = Plan {
                pages: &pages,
                sets: &sets,
                chains: &[],
                steps: &steps,
                ..*plan
            };
            return self.walk(engine, &plan, tiles, extent, surface, target, budget);
        }
        let laid = lay(plan.steps, plan.sets, tiles, plan.pages.len(), pages_per_pass)?;
        if laid.iter().all(|each| each.pages.len() <= pages_per_pass) {
            return self.walk_laid(engine, plan, &laid, tiles, extent, surface, target, budget);
        }
        let (pages, sets, laid) = self.gathered(engine, plan, laid, tiles, budget)?;
        let plan = Plan {
            pages: &pages,
            sets: &sets,
            ..*plan
        };
        self.walk_laid(engine, &plan, &laid, tiles, extent, surface, target, budget)
    }

    /// `laid` with each step reading more pages than a pass binds — a row
    /// under an output tile reaching them alone, a group of its own
    /// ([`grouped`]) — reading instead its row's tiles under that tile,
    /// gathered by [`Composite::copied`] onto a page past `plan`'s: the
    /// pages, the tile sets and the steps to walk. Nothing where a tile
    /// reaches more tiles than a page holds.
    fn gathered(
        &self,
        engine: &Engine,
        plan: &Plan,
        laid: Vec<Laid>,
        tiles: &[(i32, i32)],
        budget: Budget,
    ) -> Option<(Vec<wgpu::Buffer>, Vec<TileSet>, Vec<Laid>)> {
        let side = i64::from(TILE);
        let held = tiles_a_page(engine)?;
        let (mut pages, mut sets) = (plan.pages.to_vec(), plan.sets.to_vec());
        let mut gathered = Vec::with_capacity(laid.len());
        for mut each in laid {
            if each.pages.len() <= budget.pages {
                gathered.push(each);
                continue;
            }
            let Step::Row { set, map, .. } = &mut each.step else {
                return fail("only a row reads pages");
            };
            let mut live = each.live.iter().zip(tiles).filter(|(live, _)| **live);
            let (Some((_, &(column, row))), None) = (live.next(), live.next()) else {
                return fail("a step past a pass's pages is one output tile's");
            };
            let (x0, y0) = (i64::from(column) * side, i64::from(row) * side);
            let under = plan.sets[*set].placed_under(map.reads(x0, y0, x0 + side, y0 + side));
            // Row after row, as the set they make holds them.
            let read: Vec<(i32, i32)> = under.map(|(place, _)| place).collect();
            // ⚠️No test reaches this refusal (관제 11-06 21:18 asked why): a
            // page holds 2048 tiles at WebGPU's least binding, 128 MiB, more
            // where a device binds more, and no seam gives a pass a smaller
            // one. Past it, one output tile reads that many stored tiles — a
            // reduction past 1/45 a side over as much ink, 128 MiB of pages
            // to make in a test. It stands so such a row is refused, not
            // bound past what a binding holds.
            if read.len() > held {
                let reads = read.len();
                return fail(format!("a row reads {reads} tiles at once; a page holds {held}"));
            }
            let Ok(page) = u16::try_from(pages.len()) else {
                return fail("a gathered page is past what a plan names");
            };
            let copied = self.copied(engine, plan.pages, &plan.sets[*set], &read, budget)?;
            pages.push(copied.out);
            sets.push(placed_on(page, &read));
            *set = sets.len() - 1;
            each.pages = vec![page];
            gathered.push(each);
        }
        Some((pages, sets, gathered))
    }

    /// `plan`'s steps with every effect chain run, the innermost first, and
    /// the pages and tile sets they then lay. A chained row's tiles over its
    /// chain's rectangle, as they are stored ([`Composite::copied`]), go
    /// through the chain and are laid as a set of their own. A chained
    /// buffer's steps — from its open to its close, their own chains run —
    /// are composited alone over its chain's rectangle, through the chain,
    /// and laid as one row in their place, unposed, at the close's opacity,
    /// mode and matrix — or, at a mix under whole, as the app's crossfade
    /// lays an adjustment's scope (`composeAdjustmentScope`): in a buffer
    /// of their own, closed at the close's opacity and mode, the steps' tiles
    /// at the rest of the mix and what the chain put added by plus at the
    /// mix, through the matrix. Alone with no edge: the walk holds a buffer
    /// whole and cuts only what a run puts to its extent. A lens blur's map
    /// drawn from the rows it reads (`MapTiles::Drawn`) is those rows drawn
    /// so over the chain's rectangle first, as they show by themselves.
    ///
    /// A buffer closed as a row ([`Step::CloseRow`]) is one so too, over
    /// its chain's rectangle, or over its own tiles that the output `tiles`
    /// read through its pose where it names no chain — and is laid posed.
    ///
    /// A chain whose hold keeps what it put over its rectangle is not run:
    /// that is laid, and a buffer's steps are not walked ([`held::HeldChains`]).
    /// A chain run under a hold is kept by it.
    fn chained(
        &self,
        engine: &Engine,
        plan: &Plan,
        tiles: &[(i32, i32)],
        budget: Budget,
    ) -> Option<(Vec<wgpu::Buffer>, Vec<TileSet>, Vec<Step>)> {
        let (mut pages, mut sets) = (plan.pages.to_vec(), plan.sets.to_vec());
        let mut steps: Vec<Step> = Vec::with_capacity(plan.steps.len());
        // Where in `steps` each buffer open there was opened, and whether
        // on nothing.
        let mut opens: Vec<(usize, bool)> = Vec::new();
        let closes = closes_of(plan.steps);
        // A buffer whose chain's hold keeps what it put: its close, and that.
        let mut kept: Option<(usize, Made)> = None;
        for (index, step) in plan.steps.iter().enumerate() {
            if kept.as_ref().is_some_and(|&(close, _)| index < close) {
                continue;
            }
            if let (Step::Open, Some(close)) = (step, closes[index])
                && let Some(made) = held_over(plan, &plan.steps[close])
            {
                kept = Some((close, made));
                continue;
            }
            let chained = chain_of(step).map(|at| &plan.chains[at]);
            let rect = match (*step, chained) {
                (_, Some(chained)) => chained.rect,
                (Step::CloseRow { over: Over::Tiles(rect), map, .. }, None) => {
                    read_through(rect, &map, tiles)
                }
                _ => {
                    match step.nesting() {
                        Nesting::Opens => opens.push((steps.len(), matches!(step, Step::Open))),
                        Nesting::Closes => {
                            opens.pop();
                        }
                        Nesting::Draws => {}
                    }
                    steps.push(*step);
                    continue;
                }
            };
            let found = match step {
                Step::Row { .. } => held_over(plan, step),
                _ => kept.take().map(|(_, made)| made),
            };
            let made = match found {
                Some(made) => made,
                None => {
                    let now = Plan { pages: &pages, sets: &sets, ..*plan };
                    let laying = (&mut opens, &mut steps);
                    let made = self.made(engine, &now, (index, step), rect, laying, budget)?;
                    if let Some((held, id)) = chained.and_then(|chained| chained.held) {
                        held.keep(id, rect, made.clone());
                    }
                    made
                }
            };
            let put = laid_on(&mut pages, &mut sets, made.put, rect)?;
            match (*step, made.under) {
                (
                    Step::Close {
                        opacity,
                        mode,
                        matrix,
                        chain: Some(BufferChain { mix, .. }),
                    },
                    Some(under),
                ) if mix < WHOLE => {
                    let read = laid_on(&mut pages, &mut sets, under, rect)?;
                    let laid = |set, opacity, mode, matrix| Step::Row {
                        set,
                        keys: None,
                        chain: None,
                        map: ResampleMap::moved(0, 0),
                        matrix,
                        opacity,
                        mode,
                        masked: false,
                    };
                    steps.extend([
                        Step::Open,
                        laid(read, WHOLE - mix, NORMAL, None),
                        laid(put, mix, PLUS, matrix),
                        Step::Close {
                            opacity,
                            mode,
                            matrix: None,
                            chain: None,
                        },
                    ]);
                }
                _ => steps.push(unchained(*step, put)),
            }
        }
        Some((pages, sets, steps))
    }

    /// What step `index`, `step`, of `plan` puts over `rect`, run
    /// ([`Composite::chained`]): a row's tiles as they are stored, or the
    /// steps of the buffer it closes — taken off the steps laid so far where
    /// the opens say it opened — composited alone, through its chain where
    /// it names one; and those tiles where it is laid crossfaded with them.
    fn made(
        &self,
        engine: &Engine,
        plan: &Plan,
        (index, step): (usize, &Step),
        rect: TileRect,
        (opens, steps): (&mut Vec<(usize, bool)>, &mut Vec<Step>),
        budget: Budget,
    ) -> Option<Made> {
        let read = tiles_of(rect);
        let page = tiles_a_page(engine)?;
        // ⚠️No test reaches this refusal, as none reaches `gathered`'s:
        // a page holds 2048 tiles at WebGPU's least binding.
        if read.len() > page {
            let count = read.len();
            return fail(format!("step {index} runs on {count} tiles; a page holds {page}"));
        }
        let under = match *step {
            Step::Row { set, .. } => self.copied(engine, plan.pages, &plan.sets[set], &read, budget)?,
            _ => {
                // A buffer opened on the one under it holds what is under
                // it, which its steps alone do not lay.
                let Some((open, true)) = opens.pop() else {
                    return fail(format!("step {index} runs a buffer opened on another"));
                };
                let alone = steps.split_off(open + 1);
                steps.truncate(open);
                let plan = Plan {
                    chains: &[],
                    steps: &alone,
                    ..*plan
                };
                self.run(engine, &plan, &read, NO_EDGE, budget)?
            }
        };
        let put = match chain_of(step) {
            Some(at) => {
                let chained = &plan.chains[at];
                self.through(engine, plan, chained, under.out.clone(), &read, budget)?
            }
            None => under.out.clone(),
        };
        let under = mixed(step).then_some(under.out);
        Some(Made { put, under })
    }

    /// `under` — tiles over `chained`'s rectangle, `read` — through its ops:
    /// the tiles the last put. Each map a lens blur reads from rows is
    /// those rows drawn alone over the rectangle first, as they show by
    /// themselves — their own chains run.
    fn through(
        &self,
        engine: &Engine,
        plan: &Plan,
        chained: &Chained,
        under: wgpu::Buffer,
        read: &[(i32, i32)],
        budget: Budget,
    ) -> Option<wgpu::Buffer> {
        let mut drawn = Vec::with_capacity(chained.ops.len());
        for op in &chained.ops {
            let Some(rows) = op.map_rows() else {
                drawn.push(None);
                continue;
            };
            if reads_drawn_maps(rows, plan.chains) {
                return fail("a chain reads a map whose rows read a map");
            }
            let plan = Plan { steps: rows, ..*plan };
            drawn.push(Some(self.run(engine, &plan, read, NO_EDGE, budget)?.out));
        }
        let ops = with_drawn(&chained.ops, &drawn);
        // A chain reads its tiles and puts others: what it read stays.
        self.chains(engine).run(engine, self, under, chained.rect, &ops)
    }

    /// [`Composite::walk`] from the steps as `lay` laid them.
    fn walk_laid(
        &self,
        engine: &Engine,
        plan: &Plan,
        laid: &[Laid],
        tiles: &[(i32, i32)],
        extent: [i32; 4],
        surface: Option<&'static str>,
        target: &Target,
        budget: Budget,
    ) -> Option<usize> {
        let page_count = plan.pages.len();
        let batches = cut(laid, budget.pages, budget.levels)?;
        let written =
            plan_words(laid, &batches, plan.sets, plan.keys, plan.matrices, tiles, page_count);
        // One level at least: a walk starts on one.
        let levels = batches.iter().fold(1, |most, batch| most.max(batch.levels()));
        let masked = laid.iter().any(|each| masked_map(&each.step).is_some());
        let wanted = Compiled { surface, modes: written.modes, levels, masked };
        let pipeline = &self.pass(engine, wanted);
        let steps = engine.filled("composite plan", &written.words, wgpu::BufferUsages::STORAGE);
        // The stack is kept between passes only; one pass keeps none.
        let kept = batches[..batches.len() - 1]
            .iter()
            .map(|batch| batch.depth_out as u64 + 1)
            .max()
            .unwrap_or(0);
        // Output tiles wait in `work` past the stack until they are copied
        // out; a surface takes its pixels from the last pass itself.
        let waiting = u64::from(!matches!(target, Target::Surface(_)));
        let held = (kept * 2 + waiting) * TILE_TEXELS * 4;
        let band = plan.mask.map_or(0, Mask::per_tile);
        let chunk =
            tiles_a_pass(engine, held + band, 0)?.min(budget.tiles).min(tiles.len().max(1));
        if chunk == 0 {
            return fail("a budget of no tiles a pass");
        }
        let rows: Option<Vec<i32>> =
            plan.mask.map(|_| tiles.iter().map(|&(_, row)| row).collect());
        // An output tile binds no page of the pool.
        let runs = runs(tiles.iter().map(|_| None), rows.as_deref(), 1, chunk);
        // The mask's rows each run reads through the maps of the steps laid
        // under it: the rows its tiles span where those maps move nothing —
        // what each tile's share above reserves — and more or fewer under a
        // pose.
        let maps: Vec<ResampleMap> =
            laid.iter().filter_map(|each| masked_map(&each.step)).collect();
        let bands: Vec<Range<u32>> = runs
            .iter()
            .map(|(run, _)| {
                plan.mask.map_or(0..0, |mask| read_band(mask, &maps, &tiles[run.clone()]))
            })
            .collect();
        let banded = plan.mask.map_or(0, |mask| {
            let row_bytes = u64::from(mask.size.stride()) * 4;
            bands.iter().map(|rows| u64::from(rows.end - rows.start) * row_bytes).max().unwrap_or(0)
        });
        let size = chunk as u64 * held + banded;
        // ⚠️No test reaches this: a pose would have to read more of its mask
        // than a binding holds past the stack — a 128 MiB binding is a mask
        // of 128 MiB of rows.
        if size > room(engine) {
            return fail(format!("a pass's masked steps read {banded} bytes of their mask"));
        }
        // A binding holds something, even where nothing waits.
        let work = engine.work.of(engine, size.max(16));
        let mut encoder = engine
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor::default());
        let [left, top, right, bottom] = extent.map(|edge| edge as u32);
        let mut passes = 0;
        for ((run, _), rows) in runs.into_iter().zip(bands) {
            let (first_tile, chunk_tiles) = (run.start, run.len());
            let out_at = kept * 2 * TILE_TEXELS * chunk_tiles as u64;
            let mask_at = out_at + waiting * TILE_TEXELS * chunk_tiles as u64;
            let shape = plan.mask.map_or([0; 6], |mask| {
                let (plane, bytes) = mask.rows(&rows);
                if !bytes.is_empty() {
                    let length = bytes.end - bytes.start;
                    encoder.copy_buffer_to_buffer(plane, bytes.start, &work, mask_at * 4, length);
                }
                [
                    mask_at as u32,
                    mask.size.width,
                    rows.len() as u32,
                    mask.size.stride(),
                    mask.at.0 as u32,
                    (mask.at.1 + rows.start as i32) as u32,
                ]
            });
            let uniforms: Vec<wgpu::Buffer> = batches
                .iter()
                .enumerate()
                .map(|(index, batch)| {
                    let mut words = vec![
                        (batch.begin) as u32,
                        batch.end as u32,
                        batch.depth_in as u32,
                        u32::from(index == 0),
                        u32::from(index == batches.len() - 1),
                        written.tiles_at + written.tile_words * first_tile as u32,
                        written.tile_words,
                        chunk_tiles as u32,
                        out_at as u32,
                        written.tables_at + (index * page_count) as u32,
                        batch.base as u32,
                        left,
                        top,
                        right,
                        bottom,
                    ];
                    words.extend(shape);
                    words_buffer(engine, "composite pass", &words, wgpu::BufferUsages::UNIFORM)
                })
                .collect();
            let dispatches: Vec<Encoded> = batches
                .iter()
                .zip(&uniforms)
                .map(|(batch, uniform)| {
                    let mut bound = whole(&[(0, uniform), (1, &steps), (2, &work)]);
                    let pages = batch.pages.iter().map(|&page| &plan.pages[usize::from(page)]);
                    bound.extend(self.pages.entries(pages));
                    if let Target::Surface(view) = target {
                        bound.push(wgpu::BindGroupEntry {
                            binding: self.surface_binding(),
                            resource: wgpu::BindingResource::TextureView(view),
                        });
                    }
                    let groups = (TILE / 16, TILE / 16, chunk_tiles as u32);
                    Encoded { pipeline, bound, groups }
                })
                .collect();
            encode_on(engine, &mut encoder, &dispatches);
            passes += dispatches.len();
            match target {
                Target::Tiles(out) => encoder.copy_buffer_to_buffer(
                    &work,
                    out_at * 4,
                    out,
                    first_tile as u64 * TILE_BYTES,
                    chunk_tiles as u64 * TILE_BYTES,
                ),
                Target::Placed(onto) => {
                    let places = &onto.at[first_tile..first_tile + chunk_tiles];
                    for (from, at) in (out_at * 4..).step_by(TILE_BYTES as usize).zip(places) {
                        let page = &onto.pages[usize::from(at.page)];
                        let to = u64::from(at.slot) * TILE_BYTES;
                        encoder.copy_buffer_to_buffer(&work, from, page, to, TILE_BYTES);
                    }
                }
                Target::Surface(_) => {}
            }
        }
        engine.queue.submit([encoder.finish()]);
        Some(passes)
    }
}

/// What a composite pass is compiled for: where it puts its pixels — the
/// output tiles, or a surface of the format `surface` names —, the R1
/// modes its plan's maps hold, the rest compiled out (resample.wgsl), the
/// stack levels its plan's passes reach, and whether it lays a step under
/// the plan's mask (composite.wgsl's `composite_with_mask`).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct Compiled {
    surface: Option<&'static str>,
    modes: ResampleModes,
    levels: usize,
    masked: bool,
}

impl Compiled {
    /// The pass for `surface`'s output that takes any plan: every mode,
    /// every level, masked steps.
    fn full(surface: Option<&'static str>) -> Self {
        Self { surface, modes: ResampleModes::ALL, levels: DEPTH, masked: true }
    }
}

/// Every composite pass asked for, with its pipeline once made — none until
/// the thread compiling passes apart gets to it — and whether that thread
/// runs.
#[derive(Default)]
struct Passes {
    asked: Vec<(Compiled, Option<wgpu::ComputePipeline>)>,
    compiling: bool,
}

impl Passes {
    fn was_asked(&self, compiled: Compiled) -> bool {
        self.asked.iter().any(|(asked, _)| *asked == compiled)
    }

    fn made(&self, compiled: Compiled) -> Option<wgpu::ComputePipeline> {
        let asked = self.asked.iter().find(|(asked, _)| *asked == compiled);
        asked.and_then(|(_, made)| made.clone())
    }
}

/// The composite pass binding the pages `pages` declares, reading maps of
/// `compiled`'s modes alone, holding its levels and putting each pixel by
/// its output's `put`: to_tiles.wgsl's, or to_surface.wgsl's for its
/// surface's format, the surface bound at `surface_binding`.
fn compile(
    engine: &Engine,
    pages: &str,
    surface_binding: u32,
    compiled: Compiled,
) -> wgpu::ComputePipeline {
    let output = match compiled.surface {
        None => include_str!("to_tiles.wgsl").to_string(),
        Some(token) => include_str!("to_surface.wgsl")
            .replace("__BINDING__", &surface_binding.to_string())
            .replace("__FORMAT__", token),
    };
    let body = include_str!("composite.wgsl")
        .replace("//__OUTPUT__", &output)
        // Time, not bytes: a walk never reaches past the levels its batches
        // do, so no test sees this; GPU timestamps do (a 1080p composite of
        // one copied row, 11-06: 132 µs of GPU holding 8 levels, 79 one).
        .replace("__DEPTH__", &compiled.levels.to_string());
    let sources = [
        ISQRT_WGSL,
        BLEND_WGSL,
        WIDE_WGSL,
        RESAMPLE_WGSL,
        TILE_WGSL,
        KEY_WGSL,
        MATRIX_WGSL,
        PREMULTIPLY_WGSL,
        BYTE_WGSL,
        pages,
        &body,
    ];
    let [blend, pick, nearest] = compiled.modes.constants();
    let masked = ("composite_with_mask", f64::from(u8::from(compiled.masked)));
    pipeline_with(engine, &sources, "composite", &[blend, pick, nearest, masked])
}

/// Fails where a step is masked and the plan has no mask, or where the
/// mask's plane holds less than its box.
fn check_mask(plan: &Plan) -> Option<()> {
    let masked = plan.steps.iter().position(|step| masked_map(step).is_some());
    match (plan.mask, masked) {
        (Some(mask), _) => mask.checked(),
        (None, Some(index)) => fail(format!("step {index} is masked and the plan has no mask")),
        (None, None) => Some(()),
    }
}

/// The effect chain a step names: a row's, or a buffer's close's.
fn chain_of(step: &Step) -> Option<usize> {
    match *step {
        Step::Row { chain, .. } => chain,
        Step::Close { chain, .. } => chain.map(|named| named.chain),
        Step::CloseRow { over: Over::Chain(chain), .. } => Some(chain),
        _ => None,
    }
}

/// Whether the walk runs `step` before it lays the plan
/// ([`Composite::chained`]): one naming an effect chain, or a buffer
/// closed as a row.
fn runs_first(step: &Step) -> bool {
    chain_of(step).is_some() || matches!(step, Step::CloseRow { .. })
}

/// What the hold of the chain `step` names keeps of it, over the chain's
/// rectangle and — where `step` is laid crossfaded with them — with the
/// tiles it ran on; none where it names no chain or none held.
fn held_over(plan: &Plan, step: &Step) -> Option<Made> {
    let chained = &plan.chains[chain_of(step)?];
    let (held, id) = chained.held?;
    held.over(id, chained.rect, mixed(step))
}

/// Whether `step` closes a chained buffer at a mix under whole: laid as a
/// crossfade of its tiles with what its chain put ([`Composite::chained`]).
fn mixed(step: &Step) -> bool {
    matches!(*step, Step::Close { chain: Some(BufferChain { mix, .. }), .. } if mix < WHOLE)
}

/// For each step that opens a buffer, the step that closes it, if one does.
fn closes_of(steps: &[Step]) -> Vec<Option<usize>> {
    let mut closes = vec![None; steps.len()];
    let mut opens = Vec::new();
    for (index, step) in steps.iter().enumerate() {
        match step.nesting() {
            Nesting::Opens => opens.push(index),
            Nesting::Closes => {
                if let Some(open) = opens.pop() {
                    closes[open] = Some(index);
                }
            }
            Nesting::Draws => {}
        }
    }
    closes
}

/// The tiles of `rect` whose pixels `map` reads for the output `tiles` —
/// every one where it is a homography, which bounds no read; none for no
/// output.
fn read_through(rect: TileRect, map: &ResampleMap, tiles: &[(i32, i32)]) -> TileRect {
    let side = i64::from(TILE);
    let columns = tiles.iter().map(|&(column, _)| i64::from(column));
    let rows = tiles.iter().map(|&(_, row)| i64::from(row));
    let bounds = (columns.clone().min(), columns.max(), rows.clone().min(), rows.max());
    let (Some(x0), Some(x1), Some(y0), Some(y1)) = bounds else {
        return TileRect { columns: 0, rows: 0, ..rect };
    };
    let Some([left, top, right, bottom]) =
        map.reads(x0 * side, y0 * side, (x1 + 1) * side, (y1 + 1) * side)
    else {
        return rect;
    };
    let [x0, y0] = [rect.x0, rect.y0].map(i64::from);
    let (x1, y1) = (x0 + i64::from(rect.columns), y0 + i64::from(rect.rows));
    let (from_x, from_y) = (left.div_euclid(side).max(x0), top.div_euclid(side).max(y0));
    let to_x = (right + side - 1).div_euclid(side).min(x1).max(from_x);
    let to_y = (bottom + side - 1).div_euclid(side).min(y1).max(from_y);
    TileRect {
        x0: from_x as i32,
        y0: from_y as i32,
        columns: (to_x - from_x) as u32,
        rows: (to_y - from_y) as u32,
    }
}

/// Whether `steps` name a chain whose lens blur reads a map drawn from
/// rows — what a map's rows never do: a map's own blur map is not read
/// (🗣️I-132-Q22 a; the app's `namingNoRow` takes it off the rows it
/// draws), and one that were would be drawn again under it, without end
/// where it read its own reader.
fn reads_drawn_maps(steps: &[Step], chains: &[Chained]) -> bool {
    let reads = |chained: &Chained| chained.ops.iter().any(|op| op.map_rows().is_some());
    steps.iter().filter_map(chain_of).filter_map(|at| chains.get(at)).any(reads)
}

/// `put` — tiles over `rect` — on a page past `pages`, laid as a tile set
/// past `sets`: that set. Nothing where the page is past what a plan names.
fn laid_on(
    pages: &mut Vec<wgpu::Buffer>,
    sets: &mut Vec<TileSet>,
    put: wgpu::Buffer,
    rect: TileRect,
) -> Option<usize> {
    let Ok(page) = u16::try_from(pages.len()) else {
        return fail("a chain's page is past what a plan names");
    };
    pages.push(put);
    sets.push(laid_as(rect, page));
    Some(sets.len() - 1)
}

/// What chained `step` lays once its chain has put tile set `set`: a row
/// from that set, as it was posed; a buffer's close a row of it, unposed,
/// at the close's opacity, mode and matrix; a buffer closed as a row that
/// row, posed.
fn unchained(step: Step, set: usize) -> Step {
    match step {
        Step::Row {
            keys,
            map,
            matrix,
            opacity,
            mode,
            masked,
            ..
        } => Step::Row {
            set,
            keys,
            chain: None,
            map,
            matrix,
            opacity,
            mode,
            masked,
        },
        Step::Close {
            opacity,
            mode,
            matrix,
            ..
        } => Step::Row {
            set,
            keys: None,
            chain: None,
            map: ResampleMap::moved(0, 0),
            matrix,
            opacity,
            mode,
            masked: false,
        },
        Step::CloseRow {
            map,
            matrix,
            opacity,
            mode,
            ..
        } => Step::Row {
            set,
            keys: None,
            chain: None,
            map,
            matrix,
            opacity,
            mode,
            masked: false,
        },
        other => other,
    }
}

/// The map of a step laid under the plan's mask — a masked row's, or a
/// range mark's — which takes canvas pixels to where it reads the mask.
fn masked_map(step: &Step) -> Option<ResampleMap> {
    match *step {
        Step::Row { map, masked: true, .. } | Step::Mark { map, .. } => Some(map),
        _ => None,
    }
}

/// The rows of `mask`'s box that `maps` read over the output `tiles`: where
/// each lands those tiles' pixels — in its step's own space, as the app
/// reads a selection on a posed row in the row's artwork (piece_landing.dart
/// `regionInArtworkSpace`, 09-25 a-marquee-on-a-posed-row) — or every row
/// where one lands them by a homography. A copy reads the rows it moves to,
/// so a landing, whose maps take nothing anywhere, reads its tiles' own.
fn read_band(mask: &Mask, maps: &[ResampleMap], tiles: &[(i32, i32)]) -> Range<u32> {
    let side = i64::from(TILE);
    let [mut x0, mut y0, mut x1, mut y1] = [i64::MAX, i64::MAX, i64::MIN, i64::MIN];
    for &(column, row) in tiles {
        let (x, y) = (i64::from(column) * side, i64::from(row) * side);
        [x0, y0, x1, y1] = [x0.min(x), y0.min(y), x1.max(x + side), y1.max(y + side)];
    }
    let (mut top, mut bottom) = (i64::MAX, i64::MIN);
    for map in maps {
        let Some([_, from, _, to]) = map.reads(x0, y0, x1, y1) else {
            return 0..mask.size.height;
        };
        (top, bottom) = (top.min(from), bottom.max(to));
    }
    let row = |y: i64| (y - i64::from(mask.at.1)).clamp(0, i64::from(mask.size.height)) as u32;
    if top >= bottom {
        return 0..0;
    }
    row(top)..row(bottom)
}

/// Fails unless every buffer the steps open is closed, none is closed that
/// was not opened, every step names a tile set, a key chain, a matrix and an
/// effect chain there are, no row names both keys and an effect chain, and
/// no buffer mixes its chain past whole.
fn check_depth(
    steps: &[Step],
    sets: usize,
    keys: usize,
    matrices: usize,
    chains: usize,
) -> Option<()> {
    let mut depth = 0usize;
    for (index, step) in steps.iter().enumerate() {
        match *step {
            Step::Row { set, .. } if set >= sets => {
                return fail(format!("step {index} lays tile set {set} of {sets}"));
            }
            Step::Row {
                keys: Some(chain), ..
            } if chain >= keys => {
                return fail(format!("step {index} keys by chain {chain} of {keys}"));
            }
            Step::Row {
                matrix: Some(matrix), ..
            }
            | Step::Close {
                matrix: Some(matrix), ..
            }
            | Step::CloseRow {
                matrix: Some(matrix), ..
            } if matrix >= matrices => {
                return fail(format!("step {index} runs matrix {matrix} of {matrices}"));
            }
            Step::Row {
                chain: Some(chain), ..
            }
            | Step::Close {
                chain: Some(BufferChain { chain, .. }),
                ..
            }
            | Step::CloseRow {
                over: Over::Chain(chain),
                ..
            } if chain >= chains => {
                return fail(format!("step {index} runs effect chain {chain} of {chains}"));
            }
            Step::Close {
                chain: Some(BufferChain { mix, .. }),
                ..
            } if mix > WHOLE => {
                return fail(format!("step {index} mixes its chain at {mix}, past whole"));
            }
            // Both run on the stored pixels before the pose, so neither
            // order would be the plan's: a chain's key runs are its ops.
            Step::Row {
                keys: Some(_),
                chain: Some(_),
                ..
            } => {
                return fail(format!("step {index} names keys and an effect chain"));
            }
            _ => {}
        }
        match step.nesting() {
            Nesting::Opens => depth += 1,
            Nesting::Closes if depth == 0 => {
                return fail(format!("step {index} closes a buffer that is not open"));
            }
            Nesting::Closes => depth -= 1,
            Nesting::Draws => {}
        }
    }
    if depth != 0 {
        return fail(format!("{depth} buffers are left open"));
    }
    Some(())
}

/// `steps` as the GPU takes them: a row with the pages of the tiles its
/// pose reads for the output tiles — a copied row once for each page, any
/// other pose once for each group of them ([`grouped`]) — and not at all
/// where it reads none; each live on the output tiles where it reads a
/// stored tile on its pages.
fn lay(
    steps: &[Step],
    sets: &[TileSet],
    tiles: &[(i32, i32)],
    page_count: usize,
    pages_per_pass: usize,
) -> Option<Vec<Laid>> {
    let side = i64::from(TILE);
    let mut laid = Vec::new();
    for step in steps {
        let Step::Row { set, map, .. } = *step else {
            laid.push(Laid {
                step: *step,
                pages: Vec::new(),
                live: vec![true; tiles.len()],
            });
            continue;
        };
        // The pages each output tile reads.
        let mut reads: Vec<Vec<u16>> = Vec::with_capacity(tiles.len());
        for &(column, row) in tiles {
            let (x0, y0) = (i64::from(column) * side, i64::from(row) * side);
            let mut read: Vec<u16> = Vec::new();
            for at in sets[set].under(map.reads(x0, y0, x0 + side, y0 + side)) {
                if usize::from(at.page) >= page_count {
                    return fail(format!("tile set {set} names page {}", at.page));
                }
                if !read.contains(&at.page) {
                    read.push(at.page);
                }
            }
            reads.push(read);
        }
        if map.is_copy() {
            let mut pages: Vec<u16> = reads.iter().flatten().copied().collect();
            pages.sort_unstable();
            pages.dedup();
            laid.extend(pages.into_iter().map(|page| Laid {
                step: *step,
                pages: vec![page],
                live: reads.iter().map(|read| read.contains(&page)).collect(),
            }));
        } else {
            laid.extend(grouped(*step, &reads, pages_per_pass));
        }
    }
    Some(laid)
}

/// A row in a pose other than a copy, laid once for each group of the
/// output tiles that read it, `reads` being the pages each reads: a tile
/// joins the first group whose pages and its own a pass of `pages_per_pass`
/// binds, or starts one. A pixel reads around where it lands, so a tile's
/// pages are never parted; one tile reading more than a pass binds is a
/// group of its own, which the walk reads gathered ([`Composite::gathered`]).
fn grouped(step: Step, reads: &[Vec<u16>], pages_per_pass: usize) -> Vec<Laid> {
    let mut groups: Vec<Laid> = Vec::new();
    for (tile, read) in reads.iter().enumerate() {
        if read.is_empty() {
            continue;
        }
        let joins = groups.iter().position(|group| {
            let fresh = read.iter().filter(|page| !group.pages.contains(page)).count();
            group.pages.len() + fresh <= pages_per_pass
        });
        let k = joins.unwrap_or_else(|| {
            groups.push(Laid {
                step,
                pages: Vec::new(),
                live: vec![false; reads.len()],
            });
            groups.len() - 1
        });
        let group = &mut groups[k];
        for &page in read {
            if !group.pages.contains(&page) {
                group.pages.push(page);
            }
        }
        group.live[tile] = true;
    }
    groups
}

/// `laid` cut into passes, in order. A pass ends where the next step would
/// bind more than `pages_per_pass` pages, or reach outside the `levels`
/// stack levels it holds — opening past the top, or closing onto a level
/// under its base. The next pass then holds the levels around the depth
/// there. None where one step reads more pages than a pass binds.
fn cut(laid: &[Laid], pages_per_pass: usize, levels: usize) -> Option<Vec<Batch>> {
    let mut batches = Vec::new();
    let mut batch = Batch {
        begin: 0,
        end: 0,
        base: 0,
        depth_in: 0,
        depth_out: 0,
        high: 0,
        pages: Vec::new(),
    };
    let mut depth = 0usize;
    for (index, each) in laid.iter().enumerate() {
        if each.pages.len() > pages_per_pass {
            return fail(format!(
                "a row reads {} pages at once; a pass binds {pages_per_pass}",
                each.pages.len()
            ));
        }
        let fresh = each.pages.iter().filter(|page| !batch.pages.contains(page)).count();
        // The levels the step reads and writes, lowest and highest.
        let (low, high) = match each.step.nesting() {
            Nesting::Opens => (depth, depth + 1),
            Nesting::Closes => (depth - 1, depth),
            Nesting::Draws => (depth, depth),
        };
        let outside = low < batch.base || high >= batch.base + levels;
        if batch.pages.len() + fresh > pages_per_pass || outside {
            // Half the levels under the depth, but never so low that `high`
            // is past the top. Half is at least one, so `low` is held too.
            let base = if outside {
                depth
                    .saturating_sub(levels / 2)
                    .max((high + 1).saturating_sub(levels))
            } else {
                batch.base
            };
            batch.end = index;
            batch.depth_out = depth;
            let next = Batch {
                begin: index,
                end: index,
                base,
                depth_in: depth,
                depth_out: depth,
                // Its first step reaches this high at least.
                high: depth,
                pages: Vec::new(),
            };
            batches.push(std::mem::replace(&mut batch, next));
        }
        batch.high = batch.high.max(high);
        for &page in &each.pages {
            if !batch.pages.contains(&page) {
                batch.pages.push(page);
            }
        }
        match each.step.nesting() {
            Nesting::Opens => depth += 1,
            Nesting::Closes => depth -= 1,
            Nesting::Draws => {}
        }
    }
    batch.end = laid.len();
    batch.depth_out = depth;
    batches.push(batch);
    Some(batches)
}

/// The plan buffer's words, where its output tiles start and how many words
/// each takes, where its passes' tables of pages start, one after another,
/// and the R1 modes its rows' maps hold.
struct PlanWords {
    words: Vec<u8>,
    tiles_at: u32,
    tile_words: u32,
    tables_at: u32,
    modes: ResampleModes,
}

/// The steps, then each tile set's map, the key chains — an empty list,
/// then each chain's list (how many runs, where each is) and its runs —
/// the colour matrices, each row's R1 map, each pass's table of pages — for every page of the
/// pool the binding holding it, or NO_PAGE — and the output tiles: each its
/// column and row, then a bit a step, step k bit k % 32 of word k / 32,
/// set where the step is live there.
fn plan_words(
    laid: &[Laid],
    batches: &[Batch],
    sets: &[TileSet],
    keys: &[KeyChain],
    matrices: &[[u32; MATRIX_WORDS]],
    tiles: &[(i32, i32)],
    page_count: usize,
) -> PlanWords {
    let mut words: Vec<u32> = Vec::with_capacity(laid.len() * STEP_WORDS);
    let maps_at = (laid.len() * STEP_WORDS) as u32;
    let mut map_at = Vec::with_capacity(sets.len());
    let mut maps: Vec<u32> = Vec::new();
    for set in sets {
        map_at.push(maps_at + maps.len() as u32);
        maps.extend(set.tiles.iter().map(|tile| tile.map_or(NO_TILE, TileAt::word)));
    }
    let chains_at = maps_at + maps.len() as u32;
    // The empty list also keeps the plan from being empty, as a storage
    // binding must hold something.
    let mut chains: Vec<u32> = vec![0];
    let mut chain_at = Vec::with_capacity(keys.len());
    for chain in keys {
        let list_at = chains_at + chains.len() as u32;
        chain_at.push(list_at);
        chains.push(chain.runs.len() as u32);
        let mut run_at = list_at + 1 + chain.runs.len() as u32;
        for run in &chain.runs {
            chains.push(run_at);
            run_at += run.len() as u32;
        }
        for run in &chain.runs {
            chains.extend(run);
        }
    }
    let matrices_at = chains_at + chains.len() as u32;
    let poses_at = matrices_at + (matrices.len() * MATRIX_WORDS) as u32;
    let matrix_at = |matrix: Option<usize>| {
        matrix.map_or(NO_MATRIX, |at| matrices_at + (at * MATRIX_WORDS) as u32)
    };
    let mut poses: Vec<u32> = Vec::new();
    let mut modes = ResampleModes::default();
    // A step's map put among the poses: where it starts there.
    let mut posed = |map: &ResampleMap| {
        let at = poses_at + poses.len() as u32;
        let pose = map.words();
        modes = modes.with(&pose);
        poses.extend(pose);
        at
    };
    for each in laid {
        let step = match each.step {
            Step::Row {
                set,
                keys,
                // Run before the walk ([`Composite::chained`]): none is left.
                chain: _,
                map,
                matrix,
                opacity,
                mode,
                masked,
            } => {
                let pose_at = posed(&map);
                let pages = || each.pages.iter().copied().map(u32::from);
                let tiles = &sets[set];
                [
                    0,
                    mode,
                    opacity,
                    pages().min().expect("a laid row has its pages"),
                    pages().max().expect("a laid row has its pages"),
                    map_at[set],
                    tiles.x0 as u32,
                    tiles.y0 as u32,
                    tiles.columns,
                    tiles.rows,
                    pose_at,
                    keys.map_or(chains_at, |chain| chain_at[chain]),
                    u32::from(masked),
                    matrix_at(matrix),
                ]
            }
            Step::Open => [1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
            Step::OpenOpaque => [2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
            Step::Close {
                opacity,
                mode,
                matrix,
                chain: _,
            } => [3, mode, opacity, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, matrix_at(matrix)],
            Step::CloseAtop => [4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
            Step::CloseRow { .. } => {
                unreachable!("run before the walk ([`Composite::chained`]): none is left")
            }
            Step::Solid {
                colour,
                rect: [left, top, right, bottom],
            } => {
                let [left, top, right, bottom] = [left, top, right, bottom].map(|edge| edge as u32);
                [5, colour, left, top, right, bottom, 0, 0, 0, 0, 0, 0, 0, 0]
            }
            // Its map and its mask where a row keeps them (composite.wgsl's
            // mark_colour and step_sampled read both).
            Step::Mark { map, shift: [x, y] } => {
                [6, x as u32, y as u32, 0, 0, 0, 0, 0, 0, 0, posed(&map), 0, 1, 0]
            }
        };
        words.extend(step);
    }
    words.extend(maps);
    words.extend(chains);
    words.extend(matrices.iter().flatten());
    words.extend(poses);
    let tables_at = words.len() as u32;
    for batch in batches {
        words.extend(page_table(&batch.pages, page_count));
    }
    let tiles_at = words.len() as u32;
    let masks = laid.len().div_ceil(32);
    for (tile, &(column, row)) in tiles.iter().enumerate() {
        words.extend([column as u32, row as u32]);
        let mut mask = vec![0u32; masks];
        for (k, each) in laid.iter().enumerate() {
            mask[k / 32] |= u32::from(each.live[tile]) << (k % 32);
        }
        words.extend(mask);
    }
    PlanWords {
        words: le_bytes(&words),
        tiles_at,
        tile_words: 2 + masks as u32,
        tables_at,
        modes,
    }
}
