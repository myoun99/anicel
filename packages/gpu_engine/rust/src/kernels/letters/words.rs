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
//! ([`narrowed_cover`]). Why, and what each earlier bake got wrong, word_bake.dart
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

/// A word not narrowed, in the parts the bake counts a narrowing in: a
/// narrowing is 1 to 4096 of them. No word is widened — `wordCondensation`
/// floors a block word's narrowing to 64ths, a 64th the least, and never
/// widens one; a column's glyph is narrowed by that times the uniform scale
/// that fits it across the column (`paintVerticalTextCell`), which is never
/// over 1 either.
///
/// ⚠️Mine (11-08): 4096ths, 64 of 64 — every narrowing of a block word
/// exactly, and a column's, which is any ratio, to the nearest 4096th: the
/// part the app's own average counted a cover in (`_coverUnit`, word_bake
/// .dart until 11-08). ↩️It was 64ths (gpu-int-spec-word-bake 규격 1), on
/// the reading that every narrowed word is `wordCondensation`'s — a
/// column's glyph is not. The sum's whole, (4096 t)² × 255, is a u64 for
/// every `times` a raster of [`MOST_RASTER`] admits (t ≤ 65536 / 3).
pub(crate) const WHOLE: u32 = 4096;

/// The longest side a word is rastered over, in the raster's pixels: past
/// it the bake is refused, and the app paints the word as it always did.
///
/// ⚠️Mine (11-08): the bake on Flutter's raster failed past the GPU's
/// largest texture — `toImageSync` threw, and word_bake.dart `_land`'s
/// refusal arm painted the word as it always was. A CPU raster has no such
/// wall; this is one, past any word the app sets — a cell's name, a line
/// of dialogue, a screen across at the most, twice over at 3 pixels a px,
/// is under 2^15. ⛔No bound on `times` itself: the app's had none
/// (`wordBakeScale`), and the sums are u64s.
const MOST_RASTER: u32 = 1 << 16;

/// `shapes` — a word as the app's layout set it, its box `size` px of the
/// layout — at `dpr` device pixels a px, rastered `times` times over and
/// narrowed to `narrowed` [`WHOLE`]ths along and down its line. None, with the
/// last error, for a word of no size, no raster or no narrowing, or one
/// rastered past [`MOST_RASTER`].
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
    if times == 0 {
        return fail("a word is rastered once over at the least");
    }
    if narrowed.iter().any(|k| !(1..=WHOLE).contains(k)) {
        return fail(format!("a word narrowed to {narrowed:?} {WHOLE}ths: each is 1 to {WHOLE}"));
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
    let boxed = [0, 1].map(|axis| (size[axis] * (f64::from(narrowed[axis]) / f64::from(WHOLE)) * dpr).ceil() as u32 + 2);
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
///
/// ⛔AVERAGE, not sample. Point-sampling a big raster back down would
/// reproduce the blotchiness this exists to remove — the whole gain is
/// that every raster pixel under a final pixel contributes.
///
/// ⛔IN WHOLE NUMBERS (a window is counted in k-ths of a raster pixel): a
/// pixel that covers whole raster pixels is their plain mean, a field of
/// one value stays that value at any narrowing, and the average of ONE
/// pixel is that pixel — which is how a word that needs no average keeps
/// the pixels it has always had (유저 2026-08-28: 「줌인하면 텍스트는 선명하게
/// 보고싶다」).
///
/// ↩️At a ratio that was no whole number it took every raster pixel a
/// window TOUCHED, whole, so neighbouring windows shared pixels — near
/// enough while only whole ratios were asked of it. A word narrowed to 0.85
/// asks for 1.18 pixels a pixel (word_bake.dart `bakeWordCoverage`).
/// ↩️Until 2026-11-08 this was the app's own `boxFilterA8`, in Dart, over a
/// raster Flutter's engine drew and the app read back.
///
/// ⛔NOT THE APP'S ONE RESAMPLER (`services/resample` — `resampleCoverage`
/// is how a brush tip's coverage changes size), and not by oversight. Its
/// Blend weighs under a TENT as wide as the reduction — the pixel's own
/// box, and a reconstruction on top of it — where a baked word is the box
/// alone: how much of THIS pixel is ink. 🧪Measured 2026-10-08 (the app's
/// face on Impeller, one raster through each). Through Blend a 9px name,
/// which is rasterised twice over and shrunk whether it is narrowed or
/// not, spreads onto a row this leaves clear, peaks lower (「3a」 at ratio
/// 1: 149 for 200) and keeps 16–30% less edge contrast; a 12px name
/// narrowed to a half or under keeps 14–32% less along the line; and past
/// sixteen source pixels a pixel (`kResampleRadiusCeiling`) Blend stops
/// averaging, which a narrowing to a twentieth asks of a 9px name — its
/// ink came out from a fifth short to a third over.
///
/// ⛔NOT A PICTURE'S OWN MIP CHAIN EITHER (`display_resample.dart`), which
/// would spare a paint the wait for its bake. A chain halves both axes at
/// once, and a word narrows along its line alone: 🧪measured 2026-10-30
/// (the app's face on Impeller, 52 words × types × narrowings, one raster
/// through each, `medium`), 34 came out on more rows than this leaves — a
/// 12px 「12」 narrowed to a quarter inks all 14 rows of its box for 9, peak
/// 76 for 214, the blur of F-297 back. Even narrowed by a half both ways its
/// levels stand half a texel off these windows, the margin being one pixel.
fn narrowed_cover(cover: &Cover, raster: [u32; 2], boxed: [u32; 2], times: u32, narrowed: [u32; 2]) -> Vec<u8> {
    let columns = narrowed_windows(times, narrowed[0], boxed[0], raster[0]);
    let rows = narrowed_windows(times, narrowed[1], boxed[1], raster[1]);
    let whole = (u64::from(WHOLE) * u64::from(times)).pow(2);
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
/// `extent` pixels long, a word narrowed to `k` [`WHOLE`]ths (W) rastered
/// `times` times over: the first raster pixel it covers, and the part it
/// covers of each from there, in k-ths of a raster pixel.
///
/// Final pixel i's window is [t(W(i − 1) + k), t(Wi + k)) and raster pixel
/// p is [pk, (p + 1)k) (규격 2): pixel 1, the first past the margin, begins
/// where the raster's own margin ends, and the windows tile the raster
/// with no gap and no overlap. Every window is Wt long — what lies past the
/// raster's edges counted in, as nothing — so the sum is always over (Wt)²
/// whatever the narrowing (규격 4).
fn narrowed_windows(times: u32, k: u32, count: u32, extent: u32) -> Vec<(u32, Vec<u32>)> {
    let (t, k, extent, whole) = (i64::from(times), i64::from(k), i64::from(extent), i64::from(WHOLE));
    (0..i64::from(count))
        .map(|i| {
            let (start, end) = (t * (whole * (i - 1) + k), t * (whole * i + k));
            let first = start.div_euclid(k).max(0);
            let last = (end - 1).div_euclid(k).min(extent - 1);
            let parts = (first..=last).map(|p| (end.min((p + 1) * k) - start.max(p * k)) as u32).collect();
            (first as u32, parts)
        })
        .collect()
}
