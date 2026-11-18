//! The fold (F-610, 2026-11-19): the pool's tiles kept folded — a table of
//! a word for each 8 × 8 block and the words of the blocks that are not of
//! one colour, each in a palette or as it is — and read in place by every
//! pass that reads a stored tile (`shared/stored.wgsl` has the form, and is
//! its one reader).
//!
//! 🗣️유저 2026-11-19 (F-610-Q5, in chat): 「압축은 일단 중복줄이면서 하는데
//! 결국은 3번대로 하자. 결과가 제일 좋으니까. 할수있는거 다하면서」 — 3번:
//! the pictures' tiles and the cels', as far as the palette form.
//!
//! 🚨FOLDED ON THE GPU ALONE: the CPU knows no form — it keeps how many
//! granules a folded tile takes ([`Folded::granules`]) and where they lie
//! ([`TileAt::folded`]). One spelling of the form, the shaders': a second
//! on the CPU would be the same algorithm written twice.
//!
//! A STORED TILE IS NEVER WRITTEN OVER (gpu-canonical-store 1a ①), so a
//! tile is folded once, into a place of its own: the pass says how many
//! words each tile folds to ([`Fold::folded`]), whoever keeps the pages'
//! books gives each a place of that size, and its words are copied there
//! ([`Folded::put`]).

// ⏳What folds a tile at rest is the next lane's — the pool's books of
// folded places, the engine's verbs, and the app's ledger that names the
// tiles: till then the crate's tests are what calls this.
#![cfg_attr(not(test), allow(dead_code))]

#[cfg(test)]
mod cost;
#[cfg(test)]
mod tests;

use crate::device::Engine;
use crate::fail;
use crate::kernels::composite::{GRANULE_BYTES, TILE_BYTES, TileAt};
use crate::kernels::shared::{
    Encoded, Given, Own, Pages, TILE_WGSL, cut_by, encode_on, encoded, fits, page_table,
    pipeline_unzeroed, plane, range, runs, tiles_a_pass,
};

/// The most a folded tile takes (fold.wgsl's FOLD_MOST), in bytes: half a
/// tile's as it is. One that folds to more stays as it is.
pub(crate) const MOST_FOLDED_BYTES: u64 = TILE_BYTES / 2;

/// The storage buffers a pass binds besides its pages: what it is given,
/// the tiles folded and their sizes — and the fold's pass words, a uniform
/// one.
const OWN_BUFFERS: u32 = 3;

/// Tiles folded by a pass, before they have places: each tile's words,
/// [`MOST_FOLDED_BYTES`] apart in `words`, and how many of them are its.
pub(crate) struct Folded {
    pub(crate) words: wgpu::Buffer,
    /// The words each tile folds to — past [`MOST_FOLDED_BYTES`]' words,
    /// it is not folded and what `words` holds for it is no tile.
    pub(crate) sizes: Vec<u32>,
}

impl Folded {
    /// The granules the tile at `index` takes folded, in a place of a
    /// power of two of them — none where it folds to more than a folded
    /// tile takes.
    pub(crate) fn granules(&self, index: usize) -> Option<u16> {
        let bytes = u64::from(self.sizes[index]) * 4;
        let whole = bytes.div_ceil(GRANULE_BYTES) as u16;
        (bytes <= MOST_FOLDED_BYTES).then(|| whole.next_power_of_two())
    }

    /// Copies each folded tile that `writes` names — by its place among
    /// the folded — to the folded place it says, on the pool's `pool`
    /// pages. Submits the work; the caller waits.
    pub(crate) fn put(
        &self,
        engine: &Engine,
        pool: &[wgpu::Buffer],
        writes: &[(usize, TileAt)],
    ) -> Option<()> {
        let mut copies = Vec::with_capacity(writes.len());
        for &(index, at) in writes {
            if index >= self.sizes.len() {
                return fail(format!("tile {index} of {} folded", self.sizes.len()));
            }
            let Some(granules) = self.granules(index) else {
                return fail(format!("tile {index} folds to {} words: it stays as it is", self.sizes[index]));
            };
            let Some(to) = at.folded() else {
                return fail(format!("{at:?} is no folded place"));
            };
            let Some(page) = pool.get(usize::from(at.page)) else {
                return fail(format!("page {} of a pool of {}", at.page, pool.len()));
            };
            if to + u64::from(granules) * GRANULE_BYTES > page.size() {
                return fail(format!("{granules} granules at {to} past page {}'s {} bytes", at.page, page.size()));
            }
            if !page.usage().contains(wgpu::BufferUsages::COPY_DST) {
                return fail(format!("page {} is no copy's destination", at.page));
            }
            copies.push((index as u64 * MOST_FOLDED_BYTES, page, to, u64::from(self.sizes[index]) * 4));
        }
        let mut encoder = engine
            .device()
            .create_command_encoder(&wgpu::CommandEncoderDescriptor::default());
        for (from, page, to, bytes) in copies {
            encoder.copy_buffer_to_buffer(&self.words, from, page, to, bytes);
        }
        engine.queue.submit([encoder.finish()]);
        Some(())
    }
}

/// The fold, compiled once for as many pages as the device lets it bind.
pub(crate) struct Fold {
    fold: wgpu::ComputePipeline,
    pages: Pages,
}

impl Fold {
    pub(crate) fn new(engine: &Engine) -> Option<Self> {
        let own = Own { storage: OWN_BUFFERS, uniform: 1 };
        let pages = Pages::new(engine, own, OWN_BUFFERS + 1)?;
        let read = pages.stored();
        let sources = [TILE_WGSL, &read, include_str!("fold.wgsl")];
        Some(Self { fold: pipeline_unzeroed(engine, &sources, "fold"), pages })
    }

    /// The tiles at `places` — each a tile's place on the pool's `pool`
    /// pages — folded. Waits for the GPU: the sizes are read here.
    pub(crate) fn folded(
        &self,
        engine: &Engine,
        pool: &[wgpu::Buffer],
        places: &[TileAt],
    ) -> Option<Folded> {
        let most = tiles_a_pass(engine, MOST_FOLDED_BYTES, 0)?;
        self.folded_by(engine, pool, places, (self.pages.per_pass(), most))
    }

    /// `folded`, its passes binding `per_pass` pages and taking `most`
    /// tiles at most — a smaller device's passes, which the tests take.
    fn folded_by(
        &self,
        engine: &Engine,
        pool: &[wgpu::Buffer],
        places: &[TileAt],
        (per_pass, most): (usize, usize),
    ) -> Option<Folded> {
        cut_by(&self.pages, (per_pass, most))?;
        if places.is_empty() {
            return fail("no tile to fold");
        }
        if let Some(at) = places.iter().find(|at| usize::from(at.page) >= pool.len()) {
            return fail(format!("page {} of a pool of {}", at.page, pool.len()));
        }
        let words_bytes = places.len() as u64 * MOST_FOLDED_BYTES;
        let sizes_bytes = places.len() as u64 * 4;
        fits(engine, &[sizes_bytes], std::iter::empty())?;
        let words = plane(engine, "tiles folded", words_bytes);
        let sizes = plane(engine, "folded sizes", sizes_bytes);
        let cut = runs(places.iter().map(|at| Some(at.page)), None, per_pass, most);
        let mut encoder = engine
            .device()
            .create_command_encoder(&wgpu::CommandEncoderDescriptor::default());
        let given = cut
            .iter()
            .map(|(run, pages)| {
                let table: Vec<u32> = page_table(pages, pool.len()).collect();
                let given: Vec<u32> = places[run.clone()]
                    .iter()
                    .flat_map(|at| [table[usize::from(at.page)], u32::from(at.slot)])
                    .collect();
                Given::new(engine, &mut encoder, &given, None, &[run.start as u32, 0, 0, 0])
            })
            .collect::<Option<Vec<Given>>>()?;
        let dispatches: Vec<Encoded> = cut
            .iter()
            .zip(&given)
            .map(|(pass, given)| {
                let (run, _) = pass;
                let bytes = run.start as u64 * MOST_FOLDED_BYTES..run.end as u64 * MOST_FOLDED_BYTES;
                let own = [Some(range(&words, bytes)), Some(sizes.as_entire_binding())];
                encoded(&self.pages, &self.fold, pool, pass, given, own)
            })
            .collect();
        encode_on(engine, &mut encoder, &dispatches);
        engine.queue.submit([encoder.finish()]);
        let read = engine.read_buffer(&sizes)?;
        let word = |four: &[u8]| u32::from_le_bytes([four[0], four[1], four[2], four[3]]);
        Some(Folded { words, sizes: read.chunks_exact(4).map(word).collect() })
    }
}
