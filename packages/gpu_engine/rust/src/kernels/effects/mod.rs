//! The effects a row's chain runs (gpu-canonical-store ⑥, by the integer
//! spec gpu-int-spec-canvas 1b (3/4) (4/4)), with no CPU copy of a formula
//! (`kernels/mod.rs`): a WGSL library the executor's passes prepend where a
//! pixel's effect reads that pixel alone, a pass of its own where it reads
//! its neighbours.
//!
//! So far:
//! - the colour key (`key.wgsl`): the walk C's `qa_key_rgba` makes over a
//!   row's pixels, from the tables the app makes from its one definition
//!   (`CelColorKey`);
//! - the colour matrix (`matrix.wgsl`): fx Brightness & Contrast and
//!   Hue/Saturation and an onion skin's tint, the one 4×5 matrix the app
//!   folds them into, which Flutter's `ColorFilter.matrix` runs now;
//! - the Gaussian (`blur::gaussian`): the blur brush's box passes, C's
//!   `qa_blur_box`;
//! - the blur along a way (`blur::line`): fx Directional and Radial Blur's
//!   taps, the app's `directional_blur.frag`;
//! - the lens blur (`blur::lens`): fx Camera Lens Blur's iris gathered over
//!   its row sums and its light, the app's `iris_gather.frag`.

pub(crate) mod blur;
#[cfg(test)]
pub(crate) mod matrix_tests;
#[cfg(test)]
pub(crate) mod tests;

use crate::kernels::shared::q;

/// The colour key walk; its host defines `key_word` (the file's head has
/// the run's layout).
pub(crate) const KEY_WGSL: &str = include_str!("key.wgsl");

/// The most keys one run names — a bit each in a word.
pub(crate) const KEYS_PER_RUN: usize = 32;

/// One run of colour keys as the app's tables give it: for each channel's
/// byte, which keys are within their tolerance of it (bit k, key k); which
/// keys give back instead of erasing; and each key's 256-byte alpha map.
pub(crate) struct KeyRun<'a> {
    pub red: &'a [u32; 256],
    pub green: &'a [u32; 256],
    pub blue: &'a [u32; 256],
    pub restores: u32,
    pub maps: &'a [u8],
}

impl KeyRun<'_> {
    /// The run as `key.wgsl` reads it: the three channel tables, the
    /// restores word, then each map four bytes a word, low byte first.
    pub(crate) fn words(&self) -> Vec<u32> {
        assert!(
            self.maps.len() % 256 == 0 && self.maps.len() / 256 <= KEYS_PER_RUN,
            "a run's maps are 256 bytes a key, {KEYS_PER_RUN} keys at most"
        );
        let mut words = Vec::with_capacity(769 + self.maps.len() / 4);
        words.extend_from_slice(self.red);
        words.extend_from_slice(self.green);
        words.extend_from_slice(self.blue);
        words.push(self.restores);
        words.extend(
            self.maps
                .chunks_exact(4)
                .map(|bytes| u32::from_le_bytes([bytes[0], bytes[1], bytes[2], bytes[3]])),
        );
        words
    }
}

/// The colour matrix over one straight pixel; its host defines
/// `matrix_word` (the file's head has a matrix's words).
pub(crate) const MATRIX_WGSL: &str = include_str!("matrix.wgsl");

/// The words of one colour matrix.
pub(crate) const MATRIX_WORDS: usize = 20;

/// `matrix` — `ColorFilter.matrix`'s twenty: four rows of four multipliers
/// and a translation in 0…255 units — as `matrix.wgsl` reads it, each
/// q(·, 16) as an i32's bits; `None` where one is not a number below 2^15
/// in magnitude. One effect's matrix stays far inside — Contrast's widest
/// multiplier is 2, Brightness & Contrast's translation under 640 — but a
/// chain folds into one, so fifteen Contrasts at +100 would reach it.
pub(crate) fn matrix_words(matrix: &[f64; MATRIX_WORDS]) -> Option<[u32; MATRIX_WORDS]> {
    let mut words = [0; MATRIX_WORDS];
    for (word, &value) in words.iter_mut().zip(matrix) {
        *word = q(value, 16, 2f64.powi(31))? as i32 as u32;
    }
    Some(words)
}
