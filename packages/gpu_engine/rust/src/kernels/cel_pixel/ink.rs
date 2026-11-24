//! R4b on the GPU (gpu-census R4b): where each of a cel's tiles holds ink —
//! its pixels whose alpha is not 0 — for 잘라내기 and the whole picture's
//! 변형, as C's `qa_alpha_bounds_tiles` answers the app's
//! `bitmapSurfaceContentBounds` a box a tile, with no CPU copy of the scan
//! (`kernels/mod.rs`); ink.wgsl has it. It walks as the verbs do — the
//! cel's tiles row by row, cut into passes by the pages' law — and a pass
//! is shaped as theirs are (`shared::paged`).
//!
//! The app folds the boxes onto the cel and keeps each on its tile
//! (`BitmapTile.rememberInkBounds`), so it scans only the tiles that owe
//! one: a cel of those tiles alone is what it hands here.

#[cfg(test)]
#[path = "ink_tests.rs"]
mod tests;

use crate::device::Engine;
use crate::kernels::composite::TileSet;
use crate::kernels::mask::BYTE_WGSL;
use crate::kernels::shared::{
    Encoded, Given, Own, Pages, TILE_WGSL, cut_by, encode_on, encoded, fits, le_words, pipeline,
    plane, runs, tiles_a_pass,
};

use super::{TILE_WORDS, WALK_WGSL, entries, walk};

/// The storage buffers a pass binds besides its pages: what it is given and
/// the boxes — and the pass's first tile, a uniform.
const OWN_BUFFERS: u32 = 2;

/// The scan, compiled once for as many pages as the device lets it bind.
pub(crate) struct Ink {
    scan: wgpu::ComputePipeline,
    pages: Pages,
}

/// Where a tile's ink lies in it: the app's `TileInkBounds`, its right and
/// bottom past the last column and row with ink.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct InkBox {
    pub(crate) left: u32,
    pub(crate) top: u32,
    pub(crate) right: u32,
    pub(crate) bottom: u32,
}

/// A walked tile: where it is on the cel's grid, and its ink — none where
/// it holds none.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct TileInk {
    pub(crate) column: i32,
    pub(crate) row: i32,
    pub(crate) ink: Option<InkBox>,
}

impl Ink {
    pub(crate) fn new(engine: &Engine) -> Option<Self> {
        let own = Own { storage: OWN_BUFFERS, uniform: 1 };
        let pages = Pages::new(engine, own, OWN_BUFFERS + 1)?;
        let read = pages.stored();
        let sources = [TILE_WGSL, &read, BYTE_WGSL, WALK_WGSL, include_str!("ink.wgsl")];
        Some(Self {
            scan: pipeline(engine, &sources, "ink_box"),
            pages,
        })
    }

    /// Each of `cel`'s tiles, its tiles on the pool's `pool` pages, in the
    /// walk's order, and where it holds ink. Waits for the GPU.
    ///
    /// ⚠️A pass's tiles end where a dispatch reaches (65,535 workgroups)
    /// long before what they are given fills a binding (1.3 MB of 128 MB at
    /// the least), so no test tells a tile's given bytes from fewer (mutant
    /// i19, 11-06). It stays: it is the bound, as the lift's is.
    pub(crate) fn run(
        &self,
        engine: &Engine,
        pool: &[wgpu::Buffer],
        cel: &TileSet,
    ) -> Option<Vec<TileInk>> {
        let most = tiles_a_pass(engine, TILE_WORDS as u64 * 4, 0)?;
        self.run_by(engine, pool, cel, (self.pages.per_pass(), most))
    }

    /// `run`, its passes binding `per_pass` pages and taking `most` tiles at
    /// most — a smaller device's passes, which the tests take.
    pub(super) fn run_by(
        &self,
        engine: &Engine,
        pool: &[wgpu::Buffer],
        cel: &TileSet,
        cut: (usize, usize),
    ) -> Option<Vec<TileInk>> {
        match self.submitted_by(engine, pool, cel, cut)? {
            None => Some(Vec::new()),
            Some((places, boxes)) => Some(inks_of(&places, &engine.read_buffer(&boxes)?)),
        }
    }

    /// [`Self::run`], the body that asks waiting for no GPU: `then` is
    /// told each tile's ink on a thread of the engine's once the GPU has
    /// written them ([`Engine::read_buffer_then`]) — or nothing where the
    /// scan failed, and at once, here, where the walk met no tile or
    /// nothing was submitted.
    ///
    /// 🗣️관제 2026-11-12 (the UI never waits for the GPU) — card
    /// the-ui-isolate-still-waits-for-the-gpu-in-places W3: the box a
    /// stroke's cel frames is found the moment the move tool asks, and
    /// that scan waited for the GPU on the UI's thread.
    pub(crate) fn scanned_then(
        &self,
        engine: &Engine,
        pool: &[wgpu::Buffer],
        cel: &TileSet,
        then: impl FnOnce(Option<Vec<TileInk>>) + Send + 'static,
    ) {
        let most = tiles_a_pass(engine, TILE_WORDS as u64 * 4, 0);
        let cut = most.map(|most| (self.pages.per_pass(), most));
        match cut.and_then(|cut| self.submitted_by(engine, pool, cel, cut)) {
            None => then(None),
            Some(None) => then(Some(Vec::new())),
            Some(Some((places, boxes))) => engine.read_buffer_then(&boxes, move |read| {
                then(read.map(|boxes| inks_of(&places, boxes)));
            }),
        }
    }

    /// The scan of `cel` submitted, its passes binding `per_pass` pages and
    /// taking `most` tiles at most: each walked tile's place on the cel's
    /// grid, in the walk's order, and the buffer the GPU writes their boxes
    /// to — none where the walk met no tile, and nothing is submitted.
    fn submitted_by(
        &self,
        engine: &Engine,
        pool: &[wgpu::Buffer],
        cel: &TileSet,
        (per_pass, most): (usize, usize),
    ) -> Option<Option<(Vec<(i32, i32)>, wgpu::Buffer)>> {
        cut_by(&self.pages, (per_pass, most))?;
        let walk = walk(cel, pool.len(), None)?;
        // ⚠️DX12 makes a buffer of nothing and reads it back, so no test
        // tells this return from its absence (mutant i23, 11-06); nor does
        // one walk the eight million tiles whose boxes pass a binding of
        // 128 MB (mutant i21). Both stay: the verbs and the lift make no
        // buffer of nothing either, and past the binding a device would
        // refuse it where this refuses the cel.
        if walk.is_empty() {
            return Some(None);
        }
        let bytes = walk.len() as u64 * 16;
        fits(engine, &[bytes], std::iter::empty())?;
        let boxes = plane(engine, "ink boxes", bytes);
        let cut = runs(walk.iter().map(|tile| Some(tile.at.page)), None, per_pass, most);
        let mut encoder = engine
            .device()
            .create_command_encoder(&wgpu::CommandEncoderDescriptor::default());
        let mut given = Vec::with_capacity(cut.len());
        for pass in &cut {
            let words = entries(&walk, pass, pool.len(), 0);
            let first = [pass.0.start as u32, 0, 0, 0];
            given.push(Given::new(engine, &mut encoder, &words, None, &first)?);
        }
        let dispatches: Vec<Encoded> = cut
            .iter()
            .zip(&given)
            .map(|(pass, given)| {
                let own = [Some(boxes.as_entire_binding()), None];
                encoded(&self.pages, &self.scan, pool, pass, given, own)
            })
            .collect();
        encode_on(engine, &mut encoder, &dispatches);
        engine.queue.submit([encoder.finish()]);
        let places = walk.iter().map(|tile| (tile.column, tile.row)).collect();
        Some(Some((places, boxes)))
    }
}

/// Each tile at `places` — the walk's order — and its ink, as `boxes`, the
/// bytes the scan wrote, say it: four words a tile, none where its left
/// passed its right.
fn inks_of(places: &[(i32, i32)], boxes: &[u8]) -> Vec<TileInk> {
    let boxes = le_words(boxes);
    let inks = places.iter().zip(boxes.chunks_exact(4)).map(|(&(column, row), found)| TileInk {
        column,
        row,
        ink: (found[0] <= found[2]).then_some(InkBox {
            left: found[0],
            top: found[1],
            right: found[2] + 1,
            bottom: found[3] + 1,
        }),
    });
    inks.collect()
}
