//! A sound row's compressor (board audio-fx-second-effect-and-presets ① —
//! 유저 Q2 「시안 3 · 시안 1 + 성격 프리셋」, 11-17: コンプレッサー is the
//! menu's second, after イコライザー): what rises over its threshold is
//! turned down by its ratio, the turning following the level with its
//! attack and letting go with its release, and the whole raised by its
//! makeup gain.
//!
//! The detector hears the frame's loudest channel and turns every channel
//! down alike, so a stereo image stays where it was. The level is turned
//! into decibels before it is smoothed — a hard knee —, by `libm`'s log,
//! exponential and power and IEEE's add and multiply in f64, so a baked
//! span is the same bits on every device, as the equalizer's.
//!
//! ⛔NOT IN THE MIX BUS, for the equalizer's reason: the detector remembers
//! the level it reached, so a span is baked once from its first sample.

use crate::filter::{Setting, Walk};

/// A compressor's settings at one moment.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Compressor {
    /// dB: the level over which it turns the sound down.
    pub threshold_db: f64,
    /// How many dB over the threshold go in for each that comes out — 1
    /// turns nothing down.
    pub ratio: f64,
    /// ms: how long the turning takes to reach two thirds of a rise.
    pub attack_ms: f64,
    /// ms: how long it takes to let go of two thirds of it.
    pub release_ms: f64,
    /// dB: what it raises everything by, turned down or not.
    pub makeup_db: f64,
}

/// The doubles a setting takes at the filter door, in [`Compressor`]'s
/// order: threshold, ratio, attack, release, makeup.
pub const COMPRESSOR_VALUES: usize = 5;

/// The doubles a compressor's memory takes, whatever its channels: the
/// turning down, in dB, the detector had reached.
pub const COMPRESSOR_MEMORY: usize = 1;

impl Compressor {
    /// The compressor a setting's [`COMPRESSOR_VALUES`] doubles say.
    pub(crate) fn of_values(v: &[f64]) -> Self {
        Self { threshold_db: v[0], ratio: v[1], attack_ms: v[2], release_ms: v[3], makeup_db: v[4] }
    }
}

/// A frame's level, dB, where it is silent — under anything a sound
/// file holds, so silence is turned down by nothing.
const SILENT_DB: f64 = -400.0;

/// A compressor's settings as the walk uses them at `rate`.
struct Turning {
    threshold_db: f64,
    /// The share of what is over the threshold turned down: 1 - 1/ratio.
    slope: f64,
    /// The share of the turning kept each sample while it rises and while
    /// it falls: e^(-1/τ), τ the time in samples; 0 where the time is none.
    attack: f64,
    release: f64,
    makeup_db: f64,
}

impl Turning {
    fn of(compressor: &Compressor, rate: f64) -> Self {
        let kept = |ms: f64| if ms > 0.0 { libm::exp(-1_000.0 / (ms * rate)) } else { 0.0 };
        Self {
            threshold_db: compressor.threshold_db,
            slope: 1.0 - 1.0 / compressor.ratio.max(1.0),
            attack: kept(compressor.attack_ms),
            release: kept(compressor.release_ms),
            makeup_db: compressor.makeup_db,
        }
    }

    /// The turning down after a frame whose loudest sample is `peak`, from
    /// `turned` before it, dB.
    fn after(&self, turned: f64, peak: f64) -> f64 {
        let level = if peak > 0.0 { 20.0 * libm::log10(peak) } else { SILENT_DB };
        let wanted = (level - self.threshold_db).max(0.0) * self.slope;
        let kept = if wanted > turned { self.attack } else { self.release };
        kept * turned + (1.0 - kept) * wanted
    }

    /// What a sample is multiplied by while `turned` dB down.
    fn gain(&self, turned: f64) -> f64 {
        libm::pow(10.0, (self.makeup_db - turned) / 20.0)
    }
}

/// `samples` — interleaved by `channels`, at `rate` — through the
/// compressor `settings` give, from rest at the first sample.
pub fn compress(samples: &[f32], channels: usize, rate: f64, settings: &[Setting<Compressor>]) -> Vec<f32> {
    let mut out = vec![0.0; samples.len()];
    let mut memory = [0.0; COMPRESSOR_MEMORY];
    compress_on(samples, channels, rate, settings, 0, &mut memory, &mut out);
    out
}

/// [`compress`] for the stretch of a span that begins at its sample
/// `first`, going on from the turning `memory` holds — 0 at the span's
/// first sample — and leaving it there. Settings take over in order of
/// their start, from the turning as it stands; before the first, the
/// samples pass as they were and the turning stays.
pub fn compress_on(
    samples: &[f32],
    channels: usize,
    rate: f64,
    settings: &[Setting<Compressor>],
    first: i64,
    memory: &mut [f64],
    out: &mut [f32],
) {
    assert!(channels > 0 && samples.len() % channels == 0, "whole frames of {channels} channels");
    assert_eq!(out.len(), samples.len(), "an out as long as the samples");
    assert_eq!(memory.len(), COMPRESSOR_MEMORY, "the one turning");
    let mut turned = memory[0];
    let mut walk = Walk::new(settings);
    let mut current: Option<Turning> = None;
    let frames = samples.chunks_exact(channels).zip(out.chunks_exact_mut(channels));
    for ((frame, written), at) in frames.zip(first..) {
        if let Some(compressor) = walk.taking_over(at) {
            current = Some(Turning::of(compressor, rate));
        }
        let Some(turning) = &current else {
            written.copy_from_slice(frame);
            continue;
        };
        let peak = frame.iter().fold(0.0, |loudest: f64, &sample| loudest.max(f64::from(sample).abs()));
        turned = turning.after(turned, peak);
        let gain = turning.gain(turned);
        for (&sample, slot) in frame.iter().zip(written.iter_mut()) {
            *slot = (f64::from(sample) * gain) as f32;
        }
    }
    memory[0] = turned;
}

#[cfg(test)]
#[path = "compressor_tests.rs"]
mod tests;
