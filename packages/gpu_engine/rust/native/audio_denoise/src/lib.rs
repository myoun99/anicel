//! Voice-take noise suppression — the engine's `qa_audio_denoise.c` over
//! RNNoise (v0.1.1), in Rust (native-to-rust, 타임라인/콘티). Until the
//! connection round the C is the answer key: the tests hold every sample
//! to the engine's `qa_audio_denoise_f32`, bit for bit.
//!
//! Ported line for line, not swapped for a crate: RNNoise is its model
//! and its float arithmetic, and only the same operations in the same
//! order give the same samples. ⛔Not ported, for the app never reaches
//! them: a model read from a file (`rnn_reader.c` — the app takes the
//! built-in one), the voice probability (the app throws it away), and
//! the training build.
//!
//! The contract with Dart (`lib/src/native/qa_audio_native.dart`) is the
//! C's, unchanged: a finished take denoised in place, once, at stop —
//! never on the capture thread.

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

/// Denoises `samples` — interleaved float32 frames of `channels`, in
/// ±1.0 — in place, each channel through a model of its own; false, with
/// nothing touched, when the take is not one this can do (another rate,
/// no channels, no room for the models).
///
/// RNNoise hears 480-sample frames in 16-bit range: each channel is scaled
/// in and out, and its last frame padded with silence, of which only the
/// part the take has is written back.
pub fn denoise(samples: &mut [f32], channels: usize, sample_rate: i32) -> bool {
    if sample_rate != RATE || channels == 0 || samples.is_empty() {
        return false;
    }
    let frames = samples.len() / channels;
    // Every channel's model before the first sample is touched: a failure
    // to make one leaves the take as it was (the C's contract).
    let mut states: Vec<DenoiseState> = Vec::new();
    if states.try_reserve_exact(channels).is_err() {
        return false;
    }
    states.extend((0..channels).map(|_| DenoiseState::new()));
    for (channel, state) in states.iter_mut().enumerate() {
        for start in (0..frames).step_by(FRAME_SIZE) {
            let valid = (frames - start).min(FRAME_SIZE);
            let mut input = [0.0f32; FRAME_SIZE];
            for (i, value) in input.iter_mut().enumerate().take(valid) {
                *value = samples[(start + i) * channels + channel] * 32768.0;
            }
            let out = state.process_frame(&input);
            for (i, value) in out.iter().enumerate().take(valid) {
                samples[(start + i) * channels + channel] = value * (1.0 / 32768.0);
            }
        }
    }
    true
}

/// Suppresses noise in place on an interleaved float32 buffer: `frames`
/// counts per-channel samples. 1 when the buffer was processed, 0 when it
/// is not one this can do — 0 always means untouched, so the caller can
/// fall back to the raw take.
///
/// # Safety
/// `samples` is null or points at `frames` x `channels` writable floats.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qa_audio_denoise_f32(
    samples: *mut f32,
    frames: i64,
    channels: i32,
    sample_rate: i32,
) -> i32 {
    // What the take is and is not is `denoise`'s to say; this door only
    // turns the pointer into a slice — never a null one, nor a negative
    // or overflowing length.
    let (Ok(frames), Ok(channels)) = (usize::try_from(frames), usize::try_from(channels)) else {
        return 0;
    };
    let Some(len) = frames.checked_mul(channels) else {
        return 0;
    };
    if samples.is_null() {
        return 0;
    }
    // SAFETY: the caller's contract.
    let samples = unsafe { std::slice::from_raw_parts_mut(samples, len) };
    i32::from(denoise(samples, channels, sample_rate))
}
