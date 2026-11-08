//! A word of the app's own screens — a frame grid's cell name, a block's
//! narrowed dialogue — as the coverage of its final device pixels: what a
//! frame grid's tile reads its letters from (grid.wgsl's GLYPH) and what a
//! screen draws a narrowed word from (word_bake.dart `paintBakedWord`), one
//! bake for both (gpu-int-spec-word-bake 「결과의 모양 — 소비자 둘」;
//! word-bake-Q1, 유저 2026-11-05: 「엔진이 글자를 직접 그린다」).
//!
//! 🚨★★★THE RASTER IS NEVER ASKED FOR A NARROWED WORD (F-297, 유저
//! 2026-10-05): the word is rastered as its un-narrowed neighbours are —
//! one scale for both axes, `times` whole times its final size — and
//! narrowed after, by the area each final pixel covers of that raster
//! ([`narrowed`]). Why, and what each earlier bake got wrong, word_bake.dart
//! `bakeWordCoverage` says.

#[cfg(test)]
mod tests;

use crate::fail;

use super::Cover;
use super::glyphs::{Affine, Faces, Paint, Placed, covered};

/// A word's coverage: a byte a pixel, `width` × `height` row by row, a
/// pixel of margin round its ink.
pub(crate) struct WordCover {
    pub(crate) width: u32,
    pub(crate) height: u32,
    pub(crate) bytes: Vec<u8>,
}

/// The most times a word is rastered over its final size, and the most
/// 64ths it is narrowed to: past either the bake is refused, and the app
/// paints the word as it always did.
///
/// ⚠️Mine (gpu-int-spec-word-bake, 규격 6): `times` is 1 or 2 at the block
/// words' sizes, and past 64 only under 0.1875 px; a narrowing is k/64,
/// 1 to 64 (`wordCondensation`). Within them a window's sum stays in a
/// u32 (규격 5).
pub(crate) const MOST: u32 = 64;

/// The longest side a word is rastered over, in the raster's pixels.
///
/// ⚠️Mine: a side's pixels and its window's sums are u32s here, and a word
/// is a cell's name or a line of dialogue — a screen across at the most,
/// rastered twice over at 3 pixels a px is under 2^15.
const MOST_RASTER: u32 = 1 << 16;

/// `shapes` — a word as the app's layout set it, its box `size` px of the
/// layout — at `dpr` device pixels a px, rastered `times` times over and
/// narrowed to `narrowed` 64ths along and down its line. None, with the
/// last error, for a word of no size or a scale past [`MOST`].
pub(crate) fn bake(
    faces: &Faces,
    shapes: &[Placed],
    dpr: f64,
    times: u32,
    size: [f64; 2],
    narrowed: [u32; 2],
) -> Option<WordCover> {
    let [width, height] = size;
    if !(width > 0.0 && height > 0.0 && dpr > 0.0) || !(width * height * dpr).is_finite() {
        return fail(format!("a word {width} × {height} px at {dpr} pixels a px has no pixels"));
    }
    if !(1..=MOST).contains(&times) || narrowed.iter().any(|k| !(1..=MOST).contains(k)) {
        return fail(format!("a word rastered {times} times over, narrowed to {narrowed:?} 64ths: each is 1 to {MOST}"));
    }
    // The raster is the word as it stands un-narrowed with one final pixel
    // of margin round it, `times` times over: one final pixel of margin is
    // that many of its own.
    let scale = (dpr * f64::from(times)) as f32;
    let margin = times as f32;
    let to_raster = Affine { a: scale, b: 0.0, c: 0.0, d: scale, e: margin, f: margin };
    let cover = covered(faces, shapes, Paint::Fill, to_raster);
    let raster = [width, height].map(|side| ((side * dpr).ceil() + 2.0) * f64::from(times));
    if raster.iter().any(|&side| side > f64::from(MOST_RASTER)) {
        return fail(format!("a word rastered {raster:?} pixels: a side is {MOST_RASTER} at most"));
    }
    let raster = raster.map(|side| side as u32);
    // The box the word is laid by: its narrowed ink, and a pixel round it.
    let boxed = [0, 1].map(|axis| (size[axis] * (f64::from(narrowed[axis]) / 64.0) * dpr).ceil() as u32 + 2);
    let bytes = match cover {
        Some(cover) => narrowed_cover(&cover, raster, boxed, times, narrowed),
        None => vec![0; boxed[0] as usize * boxed[1] as usize],
    };
    Some(WordCover {
        width: boxed[0],
        height: boxed[1],
        bytes,
    })
}

/// `cover` — ink on the raster's pixels [0, `raster`), none past them —
/// averaged into `boxed` pixels by area (규격 2–4): each final pixel the
/// sum of what it covers of the raster, each raster pixel by the part
/// covered, over the whole of its window.
fn narrowed_cover(cover: &Cover, raster: [u32; 2], boxed: [u32; 2], times: u32, narrowed: [u32; 2]) -> Vec<u8> {
    let columns = narrowed_windows(times, narrowed[0], boxed[0], raster[0]);
    let rows = narrowed_windows(times, narrowed[1], boxed[1], raster[1]);
    let whole = u64::from(64 * times).pow(2);
    let mut bytes = Vec::with_capacity(boxed[0] as usize * boxed[1] as usize);
    for (top, down) in &rows {
        for (left, along) in &columns {
            let mut sum = 0u64;
            for (j, &weight_down) in down.iter().enumerate() {
                let y = (top + j as u32) as i32;
                let line: u64 = along
                    .iter()
                    .enumerate()
                    .map(|(i, &weight)| u64::from(weight) * u64::from(cover.byte((left + i as u32) as i32, y)))
                    .sum();
                sum += u64::from(weight_down) * line;
            }
            bytes.push((sum / whole) as u8);
        }
    }
    bytes
}

/// Along one axis, what each of `count` final pixels covers of a raster
/// `extent` pixels long, a word narrowed to `k` 64ths rastered `times`
/// times over: the first raster pixel it covers, and the part it covers of
/// each from there, in k-ths of a raster pixel.
///
/// Final pixel i's window is [t(64(i − 1) + k), t(64i + k)) and raster
/// pixel p is [pk, (p + 1)k) (규격 2): pixel 1, the first past the margin,
/// begins where the raster's own margin ends, and the windows tile the
/// raster with no gap and no overlap. Every window is 64t long — what lies
/// past the raster's edges counted in, as nothing — so the sum is always
/// over (64t)² whatever the narrowing (규격 4).
fn narrowed_windows(times: u32, k: u32, count: u32, extent: u32) -> Vec<(u32, Vec<u32>)> {
    let (t, k, extent) = (i64::from(times), i64::from(k), i64::from(extent));
    (0..i64::from(count))
        .map(|i| {
            let (start, end) = (t * (64 * (i - 1) + k), t * (64 * i + k));
            let first = start.div_euclid(k).max(0);
            let last = (end - 1).div_euclid(k).min(extent - 1);
            let parts = (first..=last).map(|p| (end.min((p + 1) * k) - start.max(p * k)) as u32).collect();
            (first as u32, parts)
        })
        .collect()
}
