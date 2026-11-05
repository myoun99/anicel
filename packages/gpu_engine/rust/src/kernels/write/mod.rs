//! The write path (gpu-canonical-store 11-06 03:36): a pass's output tiles
//! — straight RGBA8, tile after tile, as the executor, the blur's finish
//! and the cel pixel verbs put them — back onto the pool's pages. A tile
//! the same in every byte as the one stored where it goes is not written;
//! where none is stored, a tile of nothing is not written and takes no
//! slot. The word each tile leaves (`changed`) is what the app's commit and
//! record read: the paint, the blur, V1, R4 and C pass this one law
//! (관제 03:36 — the bytes asked are what the app asks, "is any pixel
//! unlike the cel's").
//!
//! The test reads the stored tiles from the pool's pages as the verbs do
//! (`Pages`, cut into passes by `runs`): a tile with none stored names no
//! page and is read as nothing, so one comparison asks both.
//!
//! Where a changed tile goes — over the stored one, or a slot of its own
//! that leaves the old one for the record — is the store's to say: `put`
//! copies each where it is told. The pool's pages are made `COPY_DST` for
//! it.

// ⏳Nothing outside the tests runs it until the app's bridge round
// (gpu-canonical-store ⑧).
#![cfg_attr(not(test), allow(dead_code))]

#[cfg(test)]
mod tests;

use crate::device::Engine;
use crate::fail;
use crate::kernels::composite::{TILE_BYTES, TileAt};
use crate::kernels::shared::{
    Encoded, Given, NO_PAGE, Own, Pages, TILE_WGSL, cut_by, encode_on, encoded, fits,
    page_table, pipeline, plane, range, runs, tiles_a_pass,
};

/// The storage buffers a pass binds besides its pages: what it is given,
/// the tiles put and the changed words — and the pass's words, a uniform
/// one. A device that binds sixteen pages past them binds them past one
/// fewer as well, so no test here tells the uniform from none (mutant m17,
/// 11-06), as in the cel pixel passes (d02 · d03).
const OWN_BUFFERS: u32 = 3;

/// The write path's test, compiled once for as many pages as the device
/// lets it bind.
pub(crate) struct Write {
    changed: wgpu::ComputePipeline,
    pages: Pages,
}

impl Write {
    pub(crate) fn new(engine: &Engine) -> Option<Self> {
        let own = Own { storage: OWN_BUFFERS, uniform: 1 };
        let pages = Pages::new(engine, own, OWN_BUFFERS + 1)?;
        let read = pages.source();
        let sources = [TILE_WGSL, &read, include_str!("write.wgsl")];
        Some(Self { changed: pipeline(engine, &sources, "write_changed"), pages })
    }

    /// Whether each of `put`'s tiles differs from what is stored where it
    /// goes — `places`, a tile's place on the pool's `pool` pages, or none
    /// where nothing is stored. Waits for the GPU.
    pub(crate) fn changed(
        &self,
        engine: &Engine,
        pool: &[wgpu::Buffer],
        put: &wgpu::Buffer,
        places: &[Option<TileAt>],
    ) -> Option<Vec<bool>> {
        // A pass binds its tiles put, a tile's bytes each. No test puts tiles
        // past a binding (2 GB here, 32,768 tiles), so none tells a tile's
        // bytes from a word in this line (mutant m14, 11-06).
        let most = tiles_a_pass(engine, TILE_BYTES, 0)?;
        self.changed_by(engine, pool, put, places, (self.pages.per_pass(), most))
    }

    /// `changed`, its passes binding `per_pass` pages and taking `most`
    /// tiles at most — a smaller device's passes, which the tests take.
    fn changed_by(
        &self,
        engine: &Engine,
        pool: &[wgpu::Buffer],
        put: &wgpu::Buffer,
        places: &[Option<TileAt>],
        (per_pass, most): (usize, usize),
    ) -> Option<Vec<bool>> {
        cut_by(&self.pages, (per_pass, most))?;
        holds(put, places.len())?;
        for at in places.iter().flatten() {
            stored(pool, at)?;
        }
        // A write of no tiles asks the GPU nothing. Without the return, wgpu
        // makes, copies and maps a buffer of nothing and answers the same, so
        // no test tells the two apart (mutant m13, 11-06).
        if places.is_empty() {
            return Some(Vec::new());
        }
        let changed_bytes = places.len() as u64 * 4;
        fits(engine, &[changed_bytes], std::iter::empty())?;
        let changed = plane(engine, "write changed", changed_bytes);
        let cut = runs(places.iter().map(|place| place.map(|at| at.page)), per_pass, most);
        let mut encoder = engine
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor::default());
        let given = cut
            .iter()
            .map(|(run, pages)| {
                let table: Vec<u32> = page_table(pages, pool.len()).collect();
                let words: Vec<u32> = places[run.clone()]
                    .iter()
                    .flat_map(|place| match place {
                        Some(at) => [table[usize::from(at.page)], u32::from(at.slot)],
                        None => [NO_PAGE, 0],
                    })
                    .collect();
                Given::new(engine, &mut encoder, &words, None, &[run.start as u32, 0, 0, 0])
            })
            .collect::<Option<Vec<Given>>>()?;
        let dispatches: Vec<Encoded> = cut
            .iter()
            .zip(&given)
            .map(|(pass, given)| {
                let (run, _) = pass;
                let tiles = range(put, run.start as u64 * TILE_BYTES..run.end as u64 * TILE_BYTES);
                let own = [Some(tiles), Some(changed.as_entire_binding())];
                encoded(&self.pages, &self.changed, pool, pass, given, own)
            })
            .collect();
        encode_on(engine, &mut encoder, &dispatches);
        engine.queue.submit([encoder.finish()]);
        let words = engine.read_buffer(&changed)?;
        Some(words.chunks_exact(4).map(|word| word != [0; 4]).collect())
    }

    /// Copies each of `put`'s tiles that `writes` names — by its place
    /// among them — to where it says, on the pool's `pool` pages. Submits
    /// the work; the caller waits.
    pub(crate) fn put(
        engine: &Engine,
        pool: &[wgpu::Buffer],
        put: &wgpu::Buffer,
        writes: &[(usize, TileAt)],
    ) -> Option<()> {
        if !put.usage().contains(wgpu::BufferUsages::COPY_SRC) {
            return fail("the tiles put are no copy's source");
        }
        for &(index, at) in writes {
            holds(put, index + 1)?;
            stored(pool, &at)?;
            if !pool[usize::from(at.page)].usage().contains(wgpu::BufferUsages::COPY_DST) {
                return fail(format!("page {} is no copy's destination", at.page));
            }
        }
        let mut encoder = engine
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor::default());
        for &(index, at) in writes {
            let page = &pool[usize::from(at.page)];
            let to = u64::from(at.slot) * TILE_BYTES;
            encoder.copy_buffer_to_buffer(put, index as u64 * TILE_BYTES, page, to, TILE_BYTES);
        }
        engine.queue.submit([encoder.finish()]);
        Some(())
    }
}

/// Fails unless `put` holds `tiles` tiles.
fn holds(put: &wgpu::Buffer, tiles: usize) -> Option<()> {
    if put.size() < tiles as u64 * TILE_BYTES {
        return fail(format!("{} bytes put hold no {tiles} tiles", put.size()));
    }
    Some(())
}

/// Fails unless `at` is a tile's place on one of the pool's `pool` pages.
fn stored(pool: &[wgpu::Buffer], at: &TileAt) -> Option<()> {
    let Some(page) = pool.get(usize::from(at.page)) else {
        return fail(format!("page {} of a pool of {}", at.page, pool.len()));
    };
    if (u64::from(at.slot) + 1) * TILE_BYTES > page.size() {
        return fail(format!("slot {} past page {}'s {} bytes", at.slot, at.page, page.size()));
    }
    Some(())
}
