//! A word of a frame grid's tile — a cell's name, a block's narrowed
//! dialogue — as the raster its bake is made of: the word as the app's
//! layout set it, its coverage a byte a pixel over the box the app says
//! (word_bake.dart `bakeWordOnEngine`). The app averages that raster into
//! the word's own box (`boxFilterA8`) and a tile reads its letters from it
//! (grid.wgsl's GLYPH).
//!
//! 🗣️A GRID TILE'S WORD IS THE ENGINE'S (a-grid-row-paints-its-cells-on-a-
//! canvas-beside-its-tiles-Q3 · Q4, 유저 2026-11-15: 「(다) 글자도 엔진이 그
//! 자리에서 굽는다」 · 「그대로 간다 — 격자 칸 글자는 엔진이 굽는다」): a word
//! Flutter rasters is read back, which a paint cannot wait for, and this
//! one is rastered where it is asked — on the CPU, of no device. Every
//! other word of a screen is Flutter's (connection-round-checklist-Q30,
//! 유저 2026-11-09).
//!
//! ↩️From 2026-11-08 to 11-09 the whole bake was here, a screen's narrowed
//! word's too: the box, the times over and the average (`narrowed_cover`,
//! 8a36e35c7 to d81273818). The average is the app's one (`boxFilterA8`),
//! which a screen's bake goes through as well — a second here would be
//! the same windows written twice —, so the engine is handed the raster's
//! box and where the word stands in it, and knows neither a narrowing nor
//! a ratio.

#[cfg(test)]
mod tests;

use crate::fail;

use super::glyphs::{Affine, Faces, Paint, Placed, Shape, covered};

/// Whether every letter of `shapes` is one some family of `faces` has, in
/// its run's weight and slant: false for a word a letter of which would be
/// set as the first family's empty box (`Faces::of`).
///
/// ⏳What the app asks before it has the engine raster a word: Flutter
/// sets a letter none of the bundled faces has — an emoji, a script they
/// do not hold — in the machine's own face, which the engine never sees,
/// so such a word stays Flutter's to raster till the person says what it
/// is to be (a-grid-row-paints-its-cells-on-a-canvas-beside-its-tiles-Q5).
pub(crate) fn whole(faces: &Faces, shapes: &[Placed]) -> bool {
    shapes.iter().all(|placed| match &placed.shape {
        Shape::Letters(run) => run
            .clusters
            .iter()
            .flat_map(|cluster| cluster.text.chars())
            .all(|letter| faces.having(letter, run.weight, run.italic).is_some()),
        Shape::Rect(_) => true,
    })
}

/// The longest side a word is rastered over, in the raster's pixels: past
/// it the raster is refused, and the tile leaves the word out.
///
/// ⚠️Mine (11-08): the bake on Flutter's raster failed past the GPU's
/// largest texture — `toImageSync` threw. A CPU raster has no such wall;
/// this is one, past any word the app sets — a cell's name, a line of
/// dialogue, a screen across at the most, twice over at 3 pixels a px, is
/// under 2^15.
const MOST_RASTER: u32 = 1 << 16;

/// How many pixels a raster `size` across and down holds — None, with the
/// last error, for a raster of no pixel, one past [`MOST_RASTER`] a side,
/// or one this machine cannot count the bytes of.
pub(crate) fn pixels([width, height]: [u32; 2]) -> Option<usize> {
    if width == 0 || height == 0 {
        return fail(format!("a word rastered over {width} × {height} pixels has none"));
    }
    if width > MOST_RASTER || height > MOST_RASTER {
        return fail(format!(
            "a word rastered over {width} × {height} pixels: a side is {MOST_RASTER} at most"
        ));
    }
    match usize::try_from(u64::from(width) * u64::from(height)) {
        Ok(count) => Some(count),
        Err(_) => fail(format!("a word rastered over {width} × {height} pixels: past what the machine counts")),
    }
}

/// `shapes` — a word as the app's layout set it — laid by `to_raster` and
/// written over `bytes`, the raster's `width` pixels a row: a pixel no ink
/// reaches is 0, and ink past the raster's edges is cut off.
///
/// `bytes` holds whole rows — [`pixels`] of the raster's size.
pub(crate) fn rastered(faces: &Faces, shapes: &[Placed], to_raster: Affine, width: u32, bytes: &mut [u8]) {
    bytes.fill(0);
    let Some(cover) = covered(faces, shapes, Paint::Fill, to_raster) else {
        return;
    };
    // The ink's own rectangle, and the part of it that lies on the raster.
    let [left, top, right, bottom] = cover.at;
    let (width, height) = (width as usize, bytes.len() / width as usize);
    let (from_x, to_x) = (left.max(0), right.min(width as i32));
    let (from_y, to_y) = (top.max(0), bottom.min(height as i32));
    if from_x >= to_x {
        return;
    }
    let (across, kept) = ((right - left) as usize, (to_x - from_x) as usize);
    for y in from_y..to_y {
        let ink = (y - top) as usize * across + (from_x - left) as usize;
        let at = y as usize * width + from_x as usize;
        bytes[at..at + kept].copy_from_slice(&cover.bytes[ink..ink + kept]);
    }
}
