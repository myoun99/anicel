//! A fill's colour stamp (`_colorStampDab`, gpu-canonical-store stage 5):
//! the mask it finished, in its colour, as the tiles of a stroke row —
//! what the executor lays on the cel (R28), the selection's mask and the
//! fill's opacity and mode its row's. stamp.wgsl has why nothing else is
//! needed to land it.
//!
//! The row is every tile the mask's box meets. The app cuts a fill into
//! pieces of the tiles it covers (`_stampPieces`) for its CPU's sake; here
//! a tile it covers none of is laid as nothing, and the write path keeps
//! the cel's tile there (`kernels/write`) — knowing which tiles those are
//! before the plan is made would wait for the GPU to say.

#[cfg(test)]
#[path = "stamp_tests.rs"]
mod tests;

use crate::device::Engine;
use crate::fail;
use crate::kernels::composite::{TILE, TILE_BYTES, TileAt, TileSet};
use crate::kernels::mask::Mask;
use crate::kernels::shared::{Encoded, encode, plane, tiles_a_pass, whole, words_buffer};

use super::Flood;

/// A stamp: its pages, each holding tiles of it slot after slot, and its
/// tiles on the canvas's grid at their pages and slots.
pub(crate) struct Stamped {
    pub(crate) pages: Vec<wgpu::Buffer>,
    pub(crate) set: TileSet,
}

impl Flood {
    /// `mask` — on the canvas — in `colour` (red, green, blue) as the tiles
    /// of a row, on pages the plan will hold from its `first_page` on.
    /// Submits the work; the caller waits.
    pub(crate) fn stamp(
        &self,
        engine: &Engine,
        mask: &Mask,
        colour: [u8; 3],
        first_page: u16,
    ) -> Option<Stamped> {
        // A pass a page, a tile a workgroup deep — and a slot is a u16.
        let most = tiles_a_pass(engine, TILE_BYTES, 0)?.min(usize::from(u16::MAX));
        self.stamp_by(engine, mask, colour, first_page, most)
    }

    /// `stamp`, a page holding no more than `per_page` tiles — a test's
    /// fewer than the device's, to see a stamp go on to its next page.
    fn stamp_by(
        &self,
        engine: &Engine,
        mask: &Mask,
        colour: [u8; 3],
        first_page: u16,
        per_page: usize,
    ) -> Option<Stamped> {
        mask.checked()?;
        let set = tiles_of(mask, first_page, per_page)?;
        let [red, green, blue] = colour.map(u32::from);
        let mut pages = Vec::new();
        let mut first = 0;
        while first < set.tiles.len() {
            let count = per_page.min(set.tiles.len() - first);
            let words = [
                mask.at.0 as u32,
                mask.at.1 as u32,
                mask.size.width,
                mask.size.height,
                mask.size.stride(),
                set.x0 as u32,
                set.y0 as u32,
                set.columns,
                first as u32,
                red | green << 8 | blue << 16,
                0,
                0,
            ];
            let words = &words_buffer(engine, "stamp", &words, wgpu::BufferUsages::UNIFORM);
            let page = plane(engine, "stamp page", count as u64 * TILE_BYTES);
            let side = TILE / 16;
            encode(
                engine,
                &[Encoded {
                    pipeline: &self.stamp,
                    bound: whole(&[(0, words), (1, mask.plane), (2, &page)]),
                    groups: (side, side, count as u32),
                }],
            );
            pages.push(page);
            first += count;
        }
        Some(Stamped { pages, set })
    }
}

/// The tiles `mask`'s box meets, row after row, `per_page` to a page from
/// page `first_page` on.
fn tiles_of(mask: &Mask, first_page: u16, per_page: usize) -> Option<TileSet> {
    let side = i64::from(TILE);
    let (left, top) = (i64::from(mask.at.0), i64::from(mask.at.1));
    let (width, height) = (i64::from(mask.size.width), i64::from(mask.size.height));
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
        return fail("a mask's box lies past the canvas's grid");
    };
    let count = columns as usize * rows as usize;
    let tiles: Option<Vec<Option<TileAt>>> = (0..count)
        .map(|tile| {
            let page = u16::try_from(tile / per_page).ok()?.checked_add(first_page)?;
            let slot = u16::try_from(tile % per_page).ok()?;
            Some(Some(TileAt { page, slot }))
        })
        .collect();
    let Some(tiles) = tiles else {
        return fail("a stamp's pages are past what a plan names");
    };
    Some(TileSet {
        x0,
        y0,
        columns,
        rows,
        tiles,
    })
}
