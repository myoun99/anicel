//! A sound row's filters — its equalizers (equalizer.rs), compressors
//! (compressor.rs) and noise removals (denoiser.rs) — through one door:
//! each bakes a span once from its first sample, by settings that take
//! over where they start, a stretch at a time going on from a memory, so
//! playback and export read one bake (boards audio-fx-grows-like-the-pros
//! ③ and audio-fx-second-effect-and-presets ①).
//!
//! ⛔ONE DOOR, NOT ONE A FILTER: the geometry it refuses, the settings it
//! reads and the memory it goes on from are one walk whatever the filter
//! is — two doors would be that walk twice. The kind picks the kernel, and
//! how many doubles a setting and a memory take (↩️the equalizer had a door
//! of its own, `qa_audio_equalize`, till the compressor came, 2026-11-18).

use crate::compressor::{COMPRESSOR_MEMORY, COMPRESSOR_VALUES, Compressor, compress_on};
use crate::denoiser::{DENOISER_LATENCY, DENOISER_VALUES, Denoiser, denoise_on, denoiser_memory};
use crate::equalizer::{EQUALIZER_VALUES, Equalizer, MEMORY_VALUES, equalize_on};

/// A filter's `value` from `start` — a sample of the span, 0 its first —
/// until the next setting's.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Setting<T> {
    pub start: i64,
    pub value: T,
}

/// A span's settings, taken in order of their start as its samples are
/// walked.
pub(crate) struct Walk<'a, T> {
    settings: &'a [Setting<T>],
    next: usize,
}

impl<'a, T> Walk<'a, T> {
    pub(crate) fn new(settings: &'a [Setting<T>]) -> Self {
        Self { settings, next: 0 }
    }

    /// The setting that takes over at the sample `at` — the last of those
    /// starting at or before it not taken yet —, none where none does.
    pub(crate) fn taking_over(&mut self, at: i64) -> Option<&'a T> {
        let mut taken = None;
        while let Some(setting) = self.settings.get(self.next).filter(|setting| setting.start <= at) {
            taken = Some(&setting.value);
            self.next += 1;
        }
        taken
    }
}

/// The filters a span is baked through, by the number the door takes.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Filter {
    Equalizer,
    Compressor,
    Denoiser,
}

impl Filter {
    /// The filter the door's `kind` names: 0 the equalizer, 1 the
    /// compressor, 2 the noise removal.
    pub fn of(kind: i32) -> Option<Self> {
        match kind {
            0 => Some(Self::Equalizer),
            1 => Some(Self::Compressor),
            2 => Some(Self::Denoiser),
            _ => None,
        }
    }

    /// The doubles one of its settings takes.
    pub fn values(self) -> usize {
        match self {
            Self::Equalizer => EQUALIZER_VALUES,
            Self::Compressor => COMPRESSOR_VALUES,
            Self::Denoiser => DENOISER_VALUES,
        }
    }

    /// The doubles its memory takes over `channels`: the equalizer's each
    /// channel's sections, the compressor's one level for them all, the
    /// noise removal's each channel's model and frames.
    pub fn memory(self, channels: usize) -> usize {
        match self {
            Self::Equalizer => channels * MEMORY_VALUES,
            Self::Compressor => COMPRESSOR_MEMORY,
            Self::Denoiser => denoiser_memory(channels),
        }
    }

    /// Samples late what comes out of it is — the span's sample that many
    /// before: the noise removal's frames ([`DENOISER_LATENCY`]), none of
    /// the others'.
    pub fn latency(self) -> usize {
        match self {
            Self::Equalizer | Self::Compressor => 0,
            Self::Denoiser => DENOISER_LATENCY,
        }
    }

    /// Whether it bakes a sound at `rate`: the noise removal at RNNoise's
    /// alone, the others at any.
    pub fn hears(self, rate: i32) -> bool {
        match self {
            Self::Equalizer | Self::Compressor => true,
            Self::Denoiser => rate == audio_denoise::RATE,
        }
    }

    /// `stretch` through this filter by `settings`, each a start and
    /// [`Filter::values`] doubles, going on from `memory`.
    fn run(self, stretch: Stretch<'_>, starts: &[i64], values: &[f64], memory: &mut [f64]) {
        let Stretch { samples, channels, rate, first, out } = stretch;
        let rate = f64::from(rate);
        match self {
            Self::Equalizer => {
                let settings = settings_of(starts, values, EQUALIZER_VALUES, Equalizer::of_values);
                equalize_on(samples, channels, rate, &settings, first, memory, out);
            }
            Self::Compressor => {
                let settings = settings_of(starts, values, COMPRESSOR_VALUES, Compressor::of_values);
                compress_on(samples, channels, rate, &settings, first, memory, out);
            }
            Self::Denoiser => {
                let settings = settings_of(starts, values, DENOISER_VALUES, Denoiser::of_values);
                denoise_on(samples, channels, &settings, first, memory, out);
            }
        }
    }
}

/// The samples a call bakes: `channels` interleaved at `rate`, the span's
/// from its sample `first`, into `out`.
struct Stretch<'a> {
    samples: &'a [f32],
    channels: usize,
    rate: i32,
    first: i64,
    out: &'a mut [f32],
}

/// Each start with the value its `each` doubles say, in order.
fn settings_of<T>(starts: &[i64], values: &[f64], each: usize, of: fn(&[f64]) -> T) -> Vec<Setting<T>> {
    starts.iter().zip(values.chunks_exact(each)).map(|(&start, v)| Setting { start, value: of(v) }).collect()
}

/// The doubles a setting of the filter `kind` takes; 0 for no filter.
#[unsafe(no_mangle)]
pub extern "C" fn qa_audio_filter_values(kind: i32) -> i32 {
    Filter::of(kind).map_or(0, |filter| filter.values() as i32)
}

/// The doubles the filter `kind`'s memory takes over `channels`; 0 for no
/// filter or no channel.
#[unsafe(no_mangle)]
pub extern "C" fn qa_audio_filter_memory(kind: i32, channels: i32) -> i32 {
    match (Filter::of(kind), usize::try_from(channels)) {
        (Some(filter), Ok(channels)) if channels > 0 => filter.memory(channels) as i32,
        _ => 0,
    }
}

/// Samples late what comes out of the filter `kind` is at `rate`
/// ([`Filter::latency`]) — what a bake reads past its span and drops at
/// its front; 0 for no filter, or a rate it does not bake at.
#[unsafe(no_mangle)]
pub extern "C" fn qa_audio_filter_latency(kind: i32, rate: i32) -> i32 {
    match Filter::of(kind) {
        Some(filter) if filter.hears(rate) => filter.latency() as i32,
        _ => 0,
    }
}

/// The filter `kind` for C: `samples` — `frames` x `channels` floats at
/// `rate`, the span's from its sample `first` — into `out`, as many,
/// through `count` settings, each a start in `starts` and
/// [`qa_audio_filter_values`] doubles in `values`, going on from `memory`
/// and leaving it for the next stretch; a null `memory` starts from rest
/// and keeps nothing. 1 when it ran, 0 on a kind it does not know, a rate
/// it does not bake at ([`Filter::hears`]) or geometry it cannot read,
/// `out` and `memory` then untouched.
///
/// # Safety
/// `samples` and `out` are null or point at `frames` x `channels` floats,
/// `starts` at `count` integers, `values` at `count` x
/// [`qa_audio_filter_values`] doubles and `memory`, unless null, at
/// [`qa_audio_filter_memory`] doubles.
#[unsafe(no_mangle)]
#[allow(clippy::too_many_arguments)]
pub unsafe extern "C" fn qa_audio_filter(
    kind: i32,
    samples: *const f32,
    frames: i64,
    channels: i32,
    rate: i32,
    first: i64,
    starts: *const i64,
    values: *const f64,
    count: i32,
    memory: *mut f64,
    out: *mut f32,
) -> i32 {
    let (Some(filter), Ok(frames), Ok(channels), Ok(count)) =
        (Filter::of(kind), usize::try_from(frames), usize::try_from(channels), usize::try_from(count))
    else {
        return 0;
    };
    let unset = samples.is_null() || out.is_null() || (count > 0 && (starts.is_null() || values.is_null()));
    if unset || channels == 0 || rate <= 0 || !filter.hears(rate) {
        return 0;
    }
    // SAFETY: the caller's contract.
    let (samples, out, starts, values) = unsafe {
        (
            std::slice::from_raw_parts(samples, frames * channels),
            std::slice::from_raw_parts_mut(out, frames * channels),
            if count == 0 { &[][..] } else { std::slice::from_raw_parts(starts, count) },
            if count == 0 { &[][..] } else { std::slice::from_raw_parts(values, count * filter.values()) },
        )
    };
    let mut from_rest = Vec::new();
    let memory = if memory.is_null() {
        from_rest.resize(filter.memory(channels), 0.0);
        &mut from_rest[..]
    } else {
        // SAFETY: the caller's contract.
        unsafe { std::slice::from_raw_parts_mut(memory, filter.memory(channels)) }
    };
    filter.run(Stretch { samples, channels, rate, first, out }, starts, values, memory);
    1
}

#[cfg(test)]
#[path = "filter_tests.rs"]
mod tests;
