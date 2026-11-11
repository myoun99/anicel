//! A row's or a folder's effect chain, as the app cuts it
//! (composite_effect_paint.dart `resolveCompositeEffectPlan`): its steps —
//! each a lead (a key run, a blur along a way or about a point, a camera
//! lens blur, a Gaussian repeating the paper's edge) and the painted effects
//! after it, colour folded into one matrix between the Gaussians — then the
//! final paint. Here they are ops run in turn over ONE rectangle of tiles,
//! each reading what the one before put, as every step of the app's chain
//! rasters at one rect ("ONE number for ONE buffer", `outsetPixels`).
//!
//! A colour matrix and a key run are the executor's own row laid over
//! nothing ([`Composite::copied_through`]); a blur is its kernel's
//! (`effects::blur`). A plan names a chain on a row or on a buffer's close
//! ([`Chained`]), and the executor runs it before it walks the steps,
//! laying what it puts as a row ([`laid_as`]): a row's chain runs in the
//! row's own space, before its pose, and a folder's on the canvas
//! (`withLayerPlacement`, layer_stack_paint_pass.dart). A plug-in's step is
//! the host's: a plan reads its chain there ([`Op::Read`]), and the plan
//! that has what the plug-in made lays it ([`Op::Put`]).
//!
//! A chain that is nothing but a key run is the row's own keys
//! (`Step::Row`'s `keys`), and a final paint of colour alone the row's own
//! matrix: a plan lays the row so and runs no chain. That is no second
//! way — the op is that row laid over nothing, the same code, and keys a
//! stored word as R1 then reads it (캔버스 베이스 패널,
//! connection-round-checklist 11-07 00:39).

#[cfg(test)]
pub(crate) mod tests;

use std::sync::{Arc, Mutex, PoisonError};

use crate::device::Engine;
use crate::fail;
use crate::kernels::composite::held::HeldChains;
use crate::kernels::composite::{
    Composite, KeyChain, Step, TILE, TILE_TEXELS, TileAt, TileSet, Through,
};
use crate::kernels::effects::MATRIX_WORDS;
use crate::kernels::effects::blur::TileRect;
use crate::kernels::effects::blur::gaussian::{Blur, Gaussian};
use crate::kernels::effects::blur::lens::{BlurMap, Lens, LensBlur};
use crate::kernels::effects::blur::line::{LineBlur, LinePass};

/// One op of a chain, its kernel's own parameters.
#[derive(Clone)]
pub(crate) enum Op<'a> {
    /// A colour matrix's words (`effects::matrix_words`).
    Matrix([u32; MATRIX_WORDS]),
    /// A run of colour keys, keyed as a row's are (`KeyChain`): every key
    /// against the alpha of what the op reads, a run longer than
    /// `KEYS_PER_RUN` in the executor's runs of it — a key right after a key
    /// joins its run, and a run after anything else reads what that put (the
    /// app's `KeyRun`).
    Keys(KeyChain),
    /// fx Gaussian Blur, the Gaussian itself a way a pass.
    Gaussian(Blur),
    /// fx Directional or Radial Blur's passes over `plate`.
    Line { plate: [i32; 4], passes: Vec<LinePass> },
    /// fx Camera Lens Blur over `picture`, through the blur map where one
    /// is named — its tiles laid, or drawn from the rows it reads
    /// ([`MapTiles`]).
    Lens {
        picture: [i32; 4],
        lens: Lens,
        map: Option<BlurMap<MapTiles<'a>>>,
    },
    /// What the op before it put, handed on as it is and kept for the host
    /// to read: the picture a plug-in's step runs over.
    Read(ChainRead),
    /// What a plug-in made of `picture`, straight RGBA8 row after row, in
    /// place of what the op before it put; nothing outside it.
    Put { picture: [i32; 4], pixels: Arc<[u8]> },
}

/// What [`Op::Read`] kept for the host, once the plan has run through it.
#[derive(Clone, Default)]
pub(crate) struct ChainRead {
    kept: Arc<Mutex<Option<(wgpu::Buffer, TileRect)>>>,
}

impl ChainRead {
    fn keep(&self, tiles: &wgpu::Buffer, rect: TileRect) {
        let mut kept = self.kept.lock().unwrap_or_else(PoisonError::into_inner);
        *kept = Some((tiles.clone(), rect));
    }

    /// The pixels of `picture` the chain had come to, straight RGBA8 row
    /// after row, clear outside its tiles; none where no plan ran through
    /// it — a chain that does not meet the tiles asked is not run.
    pub(crate) fn pixels(&self, engine: &Engine, picture: [i32; 4]) -> Option<Vec<u8>> {
        let kept = self.kept.lock().unwrap_or_else(PoisonError::into_inner).clone();
        let Some((tiles, rect)) = kept else {
            return fail("no plan ran through this read");
        };
        let bytes = engine.read_buffer(&tiles)?;
        let mut out = vec![0u8; picture_bytes(picture)];
        each_pixel(picture, rect, |at, tile| {
            out[at..at + 4].copy_from_slice(&bytes[tile..tile + 4]);
        });
        Some(out)
    }
}

/// The bytes of `picture`, RGBA8.
fn picture_bytes([left, top, right, bottom]: [i32; 4]) -> usize {
    (right - left).max(0) as usize * (bottom - top).max(0) as usize * 4
}

/// For each pixel of `picture` in `rect`'s tiles: its byte in `picture`
/// row after row, and in the tiles laid over `rect` ([`laid_as`]).
fn each_pixel([left, top, right, bottom]: [i32; 4], rect: TileRect, mut pixel: impl FnMut(usize, usize)) {
    let side = TILE as i32;
    let width = (right - left).max(0) as usize;
    for y in top..bottom {
        for x in left..right {
            let (column, row) = (x.div_euclid(side) - rect.x0, y.div_euclid(side) - rect.y0);
            if column < 0 || row < 0 || column >= rect.columns as i32 || row >= rect.rows as i32 {
                continue;
            }
            let at = ((y - top) as usize * width + (x - left) as usize) * 4;
            let slot = row as usize * rect.columns as usize + column as usize;
            let inside = (y.rem_euclid(side) * side + x.rem_euclid(side)) as usize;
            pixel(at, (slot * TILE_TEXELS as usize + inside) * 4);
        }
    }
}

/// What a lens blur's map is read from: tiles laid over the chain's
/// rectangle, or the steps that draw the rows the effect names, which the
/// executor draws alone over that rectangle, where they show by
/// themselves, before the chain runs (`CompositeReadsRows`; the app's
/// `_rowOnTheGrid`, which keeps none). No steps is a row that draws
/// nothing at this frame: a map with nothing on it.
#[derive(Clone, Copy)]
pub(crate) enum MapTiles<'a> {
    Laid(&'a wgpu::Buffer),
    Drawn(&'a [Step]),
}

impl<'a> Op<'a> {
    /// The steps this op's map is drawn from, where it names a map drawn
    /// so.
    pub(crate) fn map_rows(&self) -> Option<&'a [Step]> {
        match self {
            Op::Lens {
                map:
                    Some(BlurMap {
                        tiles: MapTiles::Drawn(rows),
                        ..
                    }),
                ..
            } => Some(rows),
            _ => None,
        }
    }
}

/// `ops` with each map drawn from steps ([`Op::map_rows`]) laid as the
/// tiles `drawn` holds at that op's place.
pub(crate) fn with_drawn<'b>(ops: &[Op<'b>], drawn: &'b [Option<wgpu::Buffer>]) -> Vec<Op<'b>> {
    let laid = |(op, drawn): (&Op<'b>, &'b Option<wgpu::Buffer>)| match (op, drawn) {
        (
            Op::Lens {
                picture,
                lens,
                map: Some(map),
            },
            Some(tiles),
        ) => Op::Lens {
            picture: *picture,
            lens: *lens,
            map: Some(BlurMap {
                tiles: MapTiles::Laid(tiles),
                ..*map
            }),
        },
        (other, _) => other.clone(),
    };
    ops.iter().zip(drawn).map(laid).collect()
}

/// A chain as a plan names it (`Plan`'s `chains`): its ops, in the order
/// the app runs its steps, the ONE rectangle of tiles they all run over
/// — a row's in its own space, a folder's on the canvas — and the hold
/// that keeps what it puts under the number the app gives it, if any
/// ([`HeldChains`]).
pub(crate) struct Chained<'a> {
    pub(crate) ops: Vec<Op<'a>>,
    pub(crate) rect: TileRect,
    pub(crate) held: Option<(&'a HeldChains, u32)>,
}

/// The chain's blurs, compiled once; its colour runs on the executor's.
pub(crate) struct Chain {
    gaussian: Gaussian,
    line: LineBlur,
    lens: LensBlur,
}

impl Chain {
    pub(crate) fn new(engine: &Engine) -> Self {
        Self {
            gaussian: Gaussian::new(engine),
            line: LineBlur::new(engine),
            lens: LensBlur::new(engine),
        }
    }

    /// `tiles` — straight RGBA8 over `rect`, tile after tile row by row —
    /// through `ops` in turn: the tiles the last put over the same
    /// rectangle. Submits the work; the caller waits.
    pub(crate) fn run(
        &self,
        engine: &Engine,
        composite: &Composite,
        tiles: wgpu::Buffer,
        rect: TileRect,
        ops: &[Op],
    ) -> Option<wgpu::Buffer> {
        if ops.is_empty() {
            return fail("a chain of no op changes no pixel — a plan leaves it out");
        }
        let mut put = tiles;
        for op in ops {
            put = self.ran(engine, composite, &put, rect, op)?;
        }
        Some(put)
    }

    fn ran(
        &self,
        engine: &Engine,
        composite: &Composite,
        tiles: &wgpu::Buffer,
        rect: TileRect,
        op: &Op,
    ) -> Option<wgpu::Buffer> {
        let coloured = |through: Through| {
            let (set, pages) = (laid_as(rect, 0), std::slice::from_ref(tiles));
            let budget = composite.widest();
            composite
                .copied_through(engine, pages, &set, &tiles_of(rect), through, budget)
                .map(|done| done.out)
        };
        match op {
            Op::Matrix(matrix) => coloured(Through { keys: None, matrix: Some(matrix) }),
            Op::Keys(keys) => coloured(Through { keys: Some(keys), matrix: None }),
            Op::Gaussian(blur) => self.gaussian.run(engine, tiles, rect, blur),
            Op::Line { plate, passes } => self.line.run(engine, tiles, rect, *plate, passes),
            Op::Lens { picture, lens, map } => {
                let map = match *map {
                    None => None,
                    Some(BlurMap {
                        tiles: MapTiles::Laid(laid),
                        channel,
                        focus,
                    }) => Some(BlurMap {
                        tiles: laid,
                        channel,
                        focus,
                    }),
                    Some(BlurMap {
                        tiles: MapTiles::Drawn(_),
                        ..
                    }) => return fail("a map drawn from rows is the executor's to draw first"),
                };
                self.lens.run(engine, tiles, rect, *picture, lens, map)
            }
            Op::Read(read) => {
                read.keep(tiles, rect);
                Some(tiles.clone())
            }
            Op::Put { picture, pixels } => put_over(engine, rect, *picture, pixels),
        }
    }
}

/// The tiles over `rect` holding `pixels` at `picture`, clear elsewhere.
fn put_over(engine: &Engine, rect: TileRect, picture: [i32; 4], pixels: &[u8]) -> Option<wgpu::Buffer> {
    if pixels.len() != picture_bytes(picture) {
        return fail(format!("{} bytes put over {picture:?}", pixels.len()));
    }
    let mut tiles = vec![0u8; (rect.columns * rect.rows) as usize * TILE_TEXELS as usize * 4];
    each_pixel(picture, rect, |at, tile| {
        tiles[tile..tile + 4].copy_from_slice(&pixels[at..at + 4]);
    });
    Some(engine.filled(
        "chain put",
        &tiles,
        wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::COPY_SRC,
    ))
}

/// `rect`'s tiles, row by row: the order a chain's tiles lie in.
pub(crate) fn tiles_of(rect: TileRect) -> Vec<(i32, i32)> {
    let (columns, rows) = (rect.columns as i32, rect.rows as i32);
    (0..rows)
        .flat_map(|row| (0..columns).map(move |column| (rect.x0 + column, rect.y0 + row)))
        .collect()
}

/// The tile set of a chain's tiles over `rect` on `page`: tile k at slot k.
pub(crate) fn laid_as(rect: TileRect, page: u16) -> TileSet {
    let count = rect.columns * rect.rows;
    TileSet {
        x0: rect.x0,
        y0: rect.y0,
        columns: rect.columns,
        rows: rect.rows,
        tiles: (0..count).map(|slot| Some(TileAt { page, slot: slot as u16 })).collect(),
    }
}

/// The rectangle a chain reaching `reach` pixels runs over for the output
/// `tiles`: theirs, grown by as many whole tiles as `reach` takes each way —
/// what a pixel of them reads, however many ops it passes through.
// ⏳The tests alone ask it until the app cuts its chains into ops and asks
// it for their rectangle (connection-round-checklist 11-06 23:57) — through
// the C ABI, not a copy of it in Dart.
#[cfg_attr(not(test), allow(dead_code))]
pub(crate) fn reaching(tiles: &[(i32, i32)], reach: u32) -> Option<TileRect> {
    let grow = reach.div_ceil(TILE) as i32;
    let left = tiles.iter().map(|&(column, _)| column).min()? - grow;
    let top = tiles.iter().map(|&(_, row)| row).min()? - grow;
    let right = tiles.iter().map(|&(column, _)| column).max()? + grow + 1;
    let bottom = tiles.iter().map(|&(_, row)| row).max()? + grow + 1;
    Some(TileRect {
        x0: left,
        y0: top,
        columns: (right - left) as u32,
        rows: (bottom - top) as u32,
    })
}
