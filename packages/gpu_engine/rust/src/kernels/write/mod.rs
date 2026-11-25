//! The write path (gpu-canonical-store 11-06 03:36): a pass's output tiles
//! — straight RGBA8, tile after tile, as the executor, the blur's finish
//! and the cel pixel verbs put them — back onto the pool's pages. A tile
//! the same in every byte as the one stored where it goes is not written;
//! where none is stored, a tile of nothing is not written and takes no
//! slot. What each tile is (`Change`) is what the app's commit and record
//! read: the paint, the blur, V1, R4 and C pass this one law (관제 03:36 —
//! the bytes asked are what the app asks, "is any pixel unlike the cel's"
//! and "is any ink left").
//!
//! The test reads the stored tiles from the pool's pages as the verbs do
//! (`Pages`, cut into passes by `runs`): a tile with none stored names no
//! page and is read as nothing, so one comparison asks both.
//!
//! Where a changed tile goes is the store's to say — a slot of its own,
//! the old one left to whoever holds it (gpu-canonical-store 1a ①: a
//! stored tile is never written over) —, and `put` copies each where it
//! is told. The pool's pages are made `COPY_DST` for it.

// ⏳`put` is the pool's store's (kernels/pool, the app's tiles put from the
// CPU); the test of what a tile is waits for the flip lane, where a pass's
// output tiles come back to the store (connection-round-checklist B ⓓ).
#![cfg_attr(not(test), allow(dead_code))]

#[cfg(test)]
mod tests;

use crate::device::Engine;
use crate::fail;
use crate::kernels::cel_pixel::ink::InkBox;
use crate::kernels::composite::{TILE_BYTES, TileAt};
use crate::kernels::shared::{
    Encoded, Given, INK_BOX_WGSL, NO_PAGE, Own, Pages, TILE_WGSL, cut_by, encode_on, encoded,
    fits, le_words, page_table, pipeline, plane, range, runs, tiles_a_pass,
};

/// The storage buffers a pass binds besides its pages: what it is given,
/// the tiles put and the changed words — and the pass's words, a uniform
/// one. A device that binds sixteen pages past them binds them past one
/// fewer as well, so no test here tells the uniform from none (mutant m17,
/// 11-06), as in the cel pixel passes (d02 · d03).
const OWN_BUFFERS: u32 = 3;

/// What a tile put is beside the one stored where it goes (write.wgsl's
/// bits).
///
/// ⚠️`Cleared` is its own answer because the app answers it two ways
/// (bitmap_surface.dart `putMaterializedTiles`): a commit — a stroke's, a
/// geometry rebuild's, a plugin pass's — DROPS a tile with no ink left,
/// instead of keeping it as a tile of zeroes the user erased away; the
/// recipe rewrite (`overwriteCelPixels`) keeps it, as its undo walks the
/// tiles that exist. Which is the store's to say; this says which tile.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum Change {
    /// Every byte the stored one's — or, with none stored, every byte 0.
    Same,
    /// Unlike what is stored, with a pixel whose alpha is not 0.
    Inked,
    /// Unlike what is stored, with no pixel whose alpha is not 0.
    Cleared,
}

impl Change {
    /// The answer a tile's word of write.wgsl's bits gives, its ink
    /// `inked` or not.
    fn of(word: u32, inked: bool) -> Self {
        match (word & DIFFERS != 0, inked) {
            (false, _) => Self::Same,
            (true, true) => Self::Inked,
            (true, false) => Self::Cleared,
        }
    }
}

/// write.wgsl's `WRITE_DIFFERS`.
const DIFFERS: u32 = 1;

/// What the write's test says of each tile put, in their order: what it is
/// beside the one stored where it goes, and the box its ink fills — none
/// where it holds none.
///
/// 🗣️유저 2026-11-24 (card the-ui-isolate-still-waits-for-the-gpu-in-places-
/// Q1 「A 를 커널 안에서 — 비교 커널이 상자도 같이 쓴다」): the test reads
/// every word a box is made of, so a landing it tells is told where its ink
/// lies — and the box is the one answer to whether any is left: a tile is
/// `Inked` or `Cleared` by it.
#[derive(Debug, Default, PartialEq, Eq)]
pub(crate) struct Written {
    pub(crate) changes: Vec<Change>,
    pub(crate) inks: Vec<Option<InkBox>>,
}

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
        let read = pages.stored();
        let sources = [TILE_WGSL, &read, INK_BOX_WGSL, include_str!("write.wgsl")];
        Some(Self { changed: pipeline(engine, &sources, "write_changed"), pages })
    }

    /// What each of `put`'s tiles is beside what is stored where it
    /// goes — `places`, a tile's place on the pool's `pool` pages, or none
    /// where nothing is stored — and where its ink lies. Waits for the GPU.
    pub(crate) fn changed(
        &self,
        engine: &Engine,
        pool: &[wgpu::Buffer],
        put: &wgpu::Buffer,
        places: &[Option<TileAt>],
    ) -> Option<Written> {
        // A pass binds its tiles put, a tile's bytes each. No test puts tiles
        // past a binding (2 GB here, 32,768 tiles), so none tells a tile's
        // bytes from a word in this line (mutant m14, 11-06).
        let most = tiles_a_pass(engine, TILE_BYTES, 0)?;
        self.changed_by(engine, pool, put, places, (self.pages.per_pass(), most))
    }

    /// [`Self::changed`], the body that asks waiting for no GPU: `then` is
    /// told what each tile is on a thread of the engine's once the GPU
    /// has said ([`Engine::read_buffer_then`]) — or nothing where the test
    /// failed, and at once, here, where it submitted nothing.
    ///
    /// 🚨WHY (card opening-a-transform-box-holds-the-ui-over-half-a-second,
    /// 2026-11-20): a stamp's landing is a finished landing's question,
    /// and its answer was waited for where it was asked — the UI's
    /// thread, 🔬4 to 18 ms a cel cut by a box at rest and 31 to 63 with
    /// the GPU's queue full (공통, S5_BA cut 352, 메인 PC 테스트 VM). As a
    /// fold's sizes are told (`Fold::folded_then`): the engine's thread
    /// goes on to the job behind this one.
    pub(crate) fn changed_then(
        &self,
        engine: &Engine,
        pool: &[wgpu::Buffer],
        put: &wgpu::Buffer,
        places: &[Option<TileAt>],
        then: impl FnOnce(Option<Written>) + Send + 'static,
    ) {
        let cut = tiles_a_pass(engine, TILE_BYTES, 0).map(|most| (self.pages.per_pass(), most));
        match cut.and_then(|cut| self.submitted_by(engine, pool, put, places, cut)) {
            None => then(None),
            Some(None) => then(Some(Written::default())),
            Some(Some(changed)) => {
                engine.read_buffer_then(&changed, move |read| then(read.map(written_of)));
            }
        }
    }

    /// `changed`, its passes binding `per_pass` pages and taking `most`
    /// tiles at most — a smaller device's passes, which the tests take.
    fn changed_by(
        &self,
        engine: &Engine,
        pool: &[wgpu::Buffer],
        put: &wgpu::Buffer,
        places: &[Option<TileAt>],
        cut: (usize, usize),
    ) -> Option<Written> {
        match self.submitted_by(engine, pool, put, places, cut)? {
            None => Some(Written::default()),
            Some(changed) => Some(written_of(&engine.read_buffer(&changed)?)),
        }
    }

    /// The test of `put`'s tiles beside `places` submitted, its passes
    /// binding `per_pass` pages and taking `most` tiles at most: the
    /// buffer the GPU writes each tile's word to, and then each one's box
    /// ([`TILE_WORDS`] a tile in all) — none where no tile is asked, and
    /// nothing is submitted.
    fn submitted_by(
        &self,
        engine: &Engine,
        pool: &[wgpu::Buffer],
        put: &wgpu::Buffer,
        places: &[Option<TileAt>],
        (per_pass, most): (usize, usize),
    ) -> Option<Option<wgpu::Buffer>> {
        cut_by(&self.pages, (per_pass, most))?;
        holds(put, places.len())?;
        for at in places.iter().flatten() {
            at.stored_on(pool)?;
        }
        // A write of no tiles asks the GPU nothing. Without the return, wgpu
        // makes, copies and maps a buffer of nothing and answers the same, so
        // no test tells the two apart (mutant m13, 11-06).
        if places.is_empty() {
            return Some(None);
        }
        let changed_bytes = places.len() as u64 * TILE_WORDS * 4;
        fits(engine, &[changed_bytes], std::iter::empty())?;
        let changed = plane(engine, "write changed", changed_bytes);
        let cut = runs(places.iter().map(|place| place.map(|at| at.page)), None, per_pass, most);
        let mut encoder = engine
            .device()
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
                let first = [run.start as u32, places.len() as u32, 0, 0];
                Given::new(engine, &mut encoder, &words, None, &first)
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
        Some(Some(changed))
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
        let mut copies = Vec::with_capacity(writes.len());
        for &(index, at) in writes {
            holds(put, index + 1)?;
            at.stored_on(pool)?;
            let Some(to) = at.as_it_is() else {
                return fail(format!("{at:?} is a folded place: it takes no tile as it is"));
            };
            let page = &pool[usize::from(at.page)];
            if !page.usage().contains(wgpu::BufferUsages::COPY_DST) {
                return fail(format!("page {} is no copy's destination", at.page));
            }
            copies.push((index as u64 * TILE_BYTES, page, to));
        }
        let mut encoder = engine
            .device()
            .create_command_encoder(&wgpu::CommandEncoderDescriptor::default());
        for (from, page, to) in copies {
            encoder.copy_buffer_to_buffer(put, from, page, to, TILE_BYTES);
        }
        engine.queue.submit([encoder.finish()]);
        Some(())
    }
}

/// The words the test writes a tile: its bits, then its box.
const TILE_WORDS: u64 = 5;

/// What each tile is, and where its ink lies, by the changed buffer's
/// `bytes`: a word a tile, then four a tile.
fn written_of(bytes: &[u8]) -> Written {
    let words = le_words(bytes);
    let (bits, boxes) = words.split_at(words.len() / TILE_WORDS as usize);
    let inks: Vec<Option<InkBox>> = boxes.chunks_exact(4).map(InkBox::of).collect();
    let changes = bits.iter().zip(&inks).map(|(&word, ink)| Change::of(word, ink.is_some())).collect();
    Written { changes, inks }
}

/// Fails unless `put` holds `tiles` tiles.
fn holds(put: &wgpu::Buffer, tiles: usize) -> Option<()> {
    if put.size() < tiles as u64 * TILE_BYTES {
        return fail(format!("{} bytes put hold no {tiles} tiles", put.size()));
    }
    Some(())
}

