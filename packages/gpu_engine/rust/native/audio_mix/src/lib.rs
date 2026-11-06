//! The timeline's sound — `qa_engine.c`'s audio program 2B in Rust
//! (native-to-rust, 타임라인/콘티): the mix bus every clip is summed into,
//! the output stage that turns it into the device's samples, and the
//! sample-rate conversion a sound is conformed with. Until the connection
//! round the C is the answer key: the tests hold every sample to the
//! engine's exports, bit for bit.
//!
//! Each half has a Dart twin it already agrees with bit for bit
//! (`audio_mixer_reference.dart`, `audio_resampler_reference.dart`): the
//! arithmetic here mirrors the C expression for expression, double
//! throughout, so the three keep agreeing.
//!
//! The exports keep the C's names and contracts (`qa_audio_native.dart`
//! binds them unchanged); the device (native/audio_device) calls [`mix`]
//! on its realtime thread, which is why nothing here allocates or locks.

// The checkout this crate is built from, different in each: a build that
// another checkout left in the shared target folder is built again here,
// never run as this one's (gpu_engine's kernels/shared/one_checkout.rs).
const _CHECKOUT: Option<&str> = option_env!("QA_CHECKOUT");

mod bus;
mod resample;
#[cfg(test)]
mod tests;

pub use bus::{Clip, EnvelopeKey, MONO_ON_STEREO, Source, bus_to_float, bus_to_int16, mix, slice_or_empty};
pub use resample::{DEFAULT_BANDWIDTH, DEFAULT_STOPBAND_DB, Resampler, resample_frames, resample_taps};
