//! R4 들어올리기 and C 잘라내기's read on the GPU (gpu-census R4 · C,
//! gpu-canonical-store 11-06 05:35): what a selection takes off a cel, in
//! its mask's box — the app's `gatherMaskedSurfacePixels`, one read for the
//! move's lift and the cut piece (「⛔ONE LIFT」); lift.wgsl has the law. It
//! walks as the verbs do — the cel's tiles the box meets, row by row, cut
//! into passes by the pages' law — and a pass binds the box's rows its
//! tiles lie on.
//!
//! The erase a move or a cut does after it is not here: that is a stamp
//! dab (`selectionEraseDab`, 「⛔ONE ERASE」) on the brush's stamp path.

#[cfg(test)]
#[path = "lift_tests.rs"]
mod tests;

use crate::device::Engine;
use crate::kernels::composite::{TILE, TileSet};
use crate::kernels::mask::{BYTE_WGSL, Mask};
use crate::kernels::shared::{
    Encoded, Given, Own, PREMULTIPLY_WGSL, Pages, TILE_WGSL, cut_by, encode_on, encoded,
    pipeline, plane, range, runs, tiles_a_pass,
};

use super::{TILE_WORDS, WALK_WGSL, alignment, band, entries, made, walk, words};

/// The storage buffers a pass binds besides its pages: what it is given,
/// the box's pixels and the flag — and the lift's words, a uniform one. A
/// device that binds sixteen pages past them binds them past one fewer as
/// well, so no test here tells the uniform from none (mutant d03, 11-06).
const OWN_BUFFERS: u32 = 3;

/// The lift, compiled once for as many pages as the device lets it bind.
pub(crate) struct Lift {
    gather: wgpu::ComputePipeline,
    pages: Pages,
}

/// What a selection took off a cel: its box's pixels, straight RGBA8 row
/// after row, and whether it took any — the app's `liftedAnything`.
pub(crate) struct Lifted {
    pub(crate) rgba: wgpu::Buffer,
    pub(crate) anything: bool,
}

impl Lift {
    pub(crate) fn new(engine: &Engine) -> Option<Self> {
        let own = Own { storage: OWN_BUFFERS, uniform: 1 };
        let pages = Pages::new(engine, own, OWN_BUFFERS + 1)?;
        let read = pages.source();
        let lift = include_str!("lift.wgsl");
        let sources = [TILE_WGSL, PREMULTIPLY_WGSL, &read, BYTE_WGSL, WALK_WGSL, lift];
        Some(Self {
            gather: pipeline(engine, &sources, "lift_gather"),
            pages,
        })
    }

    /// What `mask` takes off `cel`, its tiles on the pool's `pool` pages: a
    /// pixel it covers at all whole where `whole` (no feather was asked
    /// for — the app's `takeWholePixels`), else its alpha scaled by the
    /// coverage. Waits for the GPU.
    pub(crate) fn run(
        &self,
        engine: &Engine,
        pool: &[wgpu::Buffer],
        cel: &TileSet,
        mask: &Mask,
        whole: bool,
    ) -> Option<Lifted> {
        let most = most(engine, mask)?;
        self.run_by(engine, pool, cel, mask, whole, (self.pages.per_pass(), most))
    }

    /// `run`, its passes binding `per_pass` pages and taking `most` tiles at
    /// most — a smaller device's passes, which the tests take.
    pub(super) fn run_by(
        &self,
        engine: &Engine,
        pool: &[wgpu::Buffer],
        cel: &TileSet,
        mask: &Mask,
        whole: bool,
        (per_pass, most): (usize, usize),
    ) -> Option<Lifted> {
        cut_by(&self.pages, (per_pass, most))?;
        let walk = walk(cel, pool.len(), Some(mask))?;
        let row = u64::from(mask.size.width) * 4;
        let bytes = row * u64::from(mask.size.height);
        made(engine, bytes)?;
        // A binding holds something, even over a box of nothing.
        let rgba = plane(engine, "lifted pixels", bytes.max(4));
        let anything = plane(engine, "lifted anything", 4);
        if walk.is_empty() {
            return Some(Lifted { rgba, anything: false });
        }
        let rows: Vec<i32> = walk.iter().map(|tile| tile.row).collect();
        let pages = walk.iter().map(|tile| Some(tile.at.page));
        let cut = runs(pages, Some(rows.as_slice()), per_pass, most);
        let align = alignment(engine);
        let mut encoder = engine
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor::default());
        let mut given = Vec::with_capacity(cut.len());
        let mut lifted = Vec::with_capacity(cut.len());
        for pass in &cut {
            let rows = band(&walk, &pass.0, mask);
            // The box's rows the pass's tiles lie on, from a word a binding
            // may start at.
            let first = u64::from(rows.start) * row / align * align;
            let words = entries(&walk, pass, pool.len(), rows.start);
            let uniform = [
                words.len() as u32,
                mask.size.width,
                rows.end - rows.start,
                mask.size.stride(),
                rows.start,
                (first / 4) as u32,
                u32::from(whole),
            ];
            given.push(Given::new(engine, &mut encoder, &words, Some(mask.rows(&rows)), &uniform)?);
            lifted.push(first..u64::from(rows.end) * row);
        }
        let dispatches: Vec<Encoded> = cut
            .iter()
            .zip(&given)
            .zip(&lifted)
            .map(|((pass, given), lifted)| {
                let own = [Some(range(&rgba, lifted.clone())), Some(anything.as_entire_binding())];
                encoded(&self.pages, &self.gather, pool, pass, given, own)
            })
            .collect();
        encode_on(engine, &mut encoder, &dispatches);
        engine.queue.submit([encoder.finish()]);
        let anything = words(&engine.read_buffer(&anything)?)[0] != 0;
        Some(Lifted { rgba, anything })
    }
}

/// The most walked tiles a pass takes on this device: as many as a binding
/// holds at a tile's worst — the box's rows it lies on, and in what it is
/// given its entry and its rows of the mask — past the box's rows bound
/// from where a binding may start.
///
/// ⚠️What a tile is given passes its rows of the box only under a box one
/// pixel wide (532 bytes to 512), and there a dispatch's reach ends a pass
/// long before a binding does on any device wgpu runs (128 MB over 65,535
/// groups is 2,048 bytes a tile) — so no test tells the `max` from its
/// absence (mutant r06, 11-06). It stays: it is the bound, and `fits`
/// refuses a pass given more than a binding all the same.
fn most(engine: &Engine, mask: &Mask) -> Option<usize> {
    let rows = u64::from(TILE);
    let lifted = rows * u64::from(mask.size.width) * 4;
    let given = TILE_WORDS as u64 * 4 + rows * u64::from(mask.size.stride()) * 4;
    tiles_a_pass(engine, lifted.max(given), alignment(engine))
}
