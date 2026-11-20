//! Voice-take noise suppression — the engine's `qa_audio_denoise.c` over
//! RNNoise (v0.1.1), in Rust (native-to-rust, 타임라인/콘티). The C was the
//! answer key until the connection round deleted it (H): the tests hold
//! every sample to the ledger rows pinned beside its answers, bit for bit.
//! RNNoise is BSD-3-Clause — its notice (`COPYING`, `PROVENANCE.md` beside
//! this crate) ships with the app.
//!
//! Ported line for line, not swapped for a crate: RNNoise is its model
//! and its float arithmetic, and only the same operations in the same
//! order give the same samples. ⛔Not ported, for the app never reaches
//! them: a model read from a file (`rnn_reader.c` — the app takes the
//! built-in one), the voice probability (the app throws it away), and
//! the training build.
//!
//! The app hears it through a sound row's one filter door (native/audio_mix
//! denoiser.rs): a voice take's noise removal is a row's at its whole
//! amount, read back on time (board voice-take-denoise-lands-late). 🪦The
//! C's door, a take denoised in place, gave each frame back a frame late,
//! and the take was placed that late.

// The checkout this crate is built from, different in each: a build that
// another checkout left in the shared target folder is built again here,
// never run as this one's (gpu_engine's kernels/shared/one_checkout.rs).
const _CHECKOUT: Option<&str> = option_env!("QA_CHECKOUT");

mod fft;
mod frame;
mod model;
mod pitch;
mod rnn;
#[cfg(test)]
mod tests;

use frame::{DenoiseState, FRAME_SIZE};

/// The one rate RNNoise's filterbank and model are built around.
pub const RATE: i32 = 48_000;

/// The samples one frame of RNNoise hears and gives back — 10 ms at
/// [`RATE`].
pub const FRAME: usize = FRAME_SIZE;

/// One channel's RNNoise from frame to frame, for a sound row's noise
/// removal (native/audio_mix denoiser.rs — board
/// audio-fx-second-effect-and-presets, Q1) and so a voice take's: a span
/// is baked a stretch at a time, so it is kept between stretches as
/// doubles ([`Suppressor::keep`]).
///
/// It gives each frame back a frame late — the half of its window the
/// overlap waits for (`a_voice_comes_back_a_frame_late`).
pub struct Suppressor(DenoiseState);

impl Suppressor {
    /// The doubles [`Suppressor::keep`] writes.
    pub const VALUES: usize = DenoiseState::VALUES;

    /// Before its first frame.
    pub fn at_rest() -> Self {
        Self(DenoiseState::new())
    }

    /// The one [`Suppressor::keep`] wrote into `from` — at rest where
    /// `from` is all zeros. `from` holds at least [`Suppressor::VALUES`].
    pub fn kept(from: &[f64]) -> Self {
        Self(DenoiseState::kept(from))
    }

    /// Writes what it carries into `into`, at least
    /// [`Suppressor::VALUES`] long.
    pub fn keep(&self, into: &mut [f64]) {
        self.0.keep(into);
    }

    /// `input`, in ±1.0, through RNNoise — which hears 16-bit range, so
    /// it is scaled in and out: the frame before it comes back, by the
    /// overlap.
    pub fn frame(&mut self, input: &[f32; FRAME]) -> [f32; FRAME] {
        let out = self.0.process_frame(&input.map(|value| value * 32768.0));
        out.map(|value| value * (1.0 / 32768.0))
    }
}
