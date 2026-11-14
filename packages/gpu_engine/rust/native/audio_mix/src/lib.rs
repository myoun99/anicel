//! The timeline's sound — `qa_engine.c`'s audio program 2B in Rust
//! (native-to-rust, 타임라인/콘티): the mix bus every clip is summed into,
//! the output stage that turns it into the device's samples, and the
//! sample-rate conversion a sound is conformed with. ↩️The C was the
//! answer key of both until each moved — the tests held every sample to
//! the engine's exports, bit for bit — and went in the connection round
//! (H): the app's ledger holds them now.
//!
//! Each half has a Dart twin it already agrees with bit for bit
//! (`audio_mixer_reference.dart`, and the test answer key
//! `test/helpers/audio_resampler_reference.dart`): the arithmetic here
//! mirrors the C expression for expression, double throughout, so they
//! keep agreeing.
//!
//! The exports keep the C's names and contracts: the app asks the
//! conversion through the engine's library (`qa_audio_resampler.dart`) and
//! the mix bus still of the C (`qa_audio_native.dart`); the device
//! (native/audio_device) calls [`mix`] on its realtime thread, which is why
//! nothing here allocates or locks.

// The checkout this crate is built from, different in each: a build that
// another checkout left in the shared target folder is built again here,
// never run as this one's (gpu_engine's kernels/shared/one_checkout.rs).
const _CHECKOUT: Option<&str> = option_env!("QA_CHECKOUT");

mod bus;
mod resample;
#[cfg(test)]
mod tests;

pub use bus::{Clip, EnvelopeKey, MONO_ON_STEREO, Source, bus_to_float, bus_to_int16, mix, slice_or_empty};
// `qa_audio_resample` by its path too: the audio crate's tests convert a
// whole sound through it (타임라인/콘티 2026-11-08), the C's being gone.
pub use resample::{DEFAULT_BANDWIDTH, DEFAULT_STOPBAND_DB, Resampler, qa_audio_resample, resample_frames, resample_taps};
