//! A sound row's noise removal (board audio-fx-second-effect-and-presets,
//! Q1 = 1, 유저 2026-11-18: 「ノイズ除去 는 다음 라운드에 효과로 지어 セリフ 에
//! 더한다」): RNNoise (native/audio_denoise, [`Suppressor`]) over a span, the
//! cleaned sound mixed into the sound as it was by the setting's amount —
//! and a voice take's, at its whole amount (board
//! voice-take-denoise-lands-late).
//!
//! 🚨LATE BY TWO FRAMES, THE SOUND AS IT WAS WITH IT. A frame comes out of
//! RNNoise as the one before it, once the next is heard — so what comes out
//! at a sample is the span's sample [`DENOISER_LATENCY`] before it, the
//! cleaned and the sound as it was alike. The bake reads that much past the
//! span and drops as much at its front (`FilterStretches`, the app's
//! qa_audio_filter.dart), so a span is late by nothing, and an amount of 0
//! hands back every sample as it was. ↩️A voice take went a road of its own
//! that read nothing past it, and was placed a frame late.
//!
//! Each channel through a model of its own. ⛔At
//! [`audio_denoise::RATE`] alone — RNNoise's bands are built around it — and
//! the door refuses another rate ([`crate::Filter::hears`]; board
//! audio-fx-second-effect-and-presets-Q2 asks whether to convert).

use audio_denoise::{FRAME, Suppressor};

use crate::filter::{Setting, Walk};

/// A noise removal's setting at one moment.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Denoiser {
    /// How much of the cleaned sound is heard, 0 to 1 — at 0 the sound as
    /// it was, at 1 the cleaned sound alone.
    pub amount: f64,
}

/// The doubles a setting takes at the filter door: the amount.
pub const DENOISER_VALUES: usize = 1;

/// Samples a noise removal's sound comes out late by: two frames.
pub const DENOISER_LATENCY: usize = 2 * FRAME;

/// The doubles one channel's memory takes: its suppressor's, then the two
/// frames heard before the one being heard, that one so far, and the
/// cleaned frame coming out.
const CHANNEL_MEMORY: usize = Suppressor::VALUES + 4 * FRAME;

/// The doubles a noise removal's memory takes over `channels`.
pub fn denoiser_memory(channels: usize) -> usize {
    channels * CHANNEL_MEMORY
}

impl Denoiser {
    /// The noise removal a setting's [`DENOISER_VALUES`] doubles say.
    pub(crate) fn of_values(v: &[f64]) -> Self {
        Self { amount: v[0] }
    }
}

/// What one channel carries from sample to sample.
struct Channel {
    /// Only where some setting cleans: none cleans, none is read.
    suppressor: Option<Suppressor>,
    /// The frame heard two frames back — what comes out now as it was.
    older: [f32; FRAME],
    last: [f32; FRAME],
    /// The frame being heard, as far as it is heard.
    hearing: [f32; FRAME],
    /// [`Channel::older`] cleaned — what comes out now cleaned.
    cleaned: [f32; FRAME],
}

impl Channel {
    fn kept(memory: &[f64], cleans: bool) -> Self {
        let (state, frames) = memory.split_at(Suppressor::VALUES);
        let frame = |index: usize| -> [f32; FRAME] {
            std::array::from_fn(|i| frames[index * FRAME + i] as f32)
        };
        Self {
            suppressor: cleans.then(|| Suppressor::kept(state)),
            older: frame(0),
            last: frame(1),
            hearing: frame(2),
            cleaned: frame(3),
        }
    }

    fn keep(&self, memory: &mut [f64]) {
        let (state, frames) = memory.split_at_mut(Suppressor::VALUES);
        if let Some(suppressor) = &self.suppressor {
            suppressor.keep(state);
        }
        let held = self.older.iter().chain(&self.last).chain(&self.hearing).chain(&self.cleaned);
        for (slot, &value) in frames.iter_mut().zip(held) {
            *slot = f64::from(value);
        }
    }

    /// The frame being heard is whole: it is cleaned, which gives back the
    /// last one cleaned, and each frame moves one back.
    fn heard(&mut self) {
        if let Some(suppressor) = &mut self.suppressor {
            self.cleaned = suppressor.frame(&self.hearing);
        }
        self.older = self.last;
        self.last = self.hearing;
    }
}

/// [`denoise_on`] over a whole span, from rest at its first sample — and,
/// like the door's, late by [`DENOISER_LATENCY`].
pub fn denoise(samples: &[f32], channels: usize, settings: &[Setting<Denoiser>]) -> Vec<f32> {
    let mut out = vec![0.0; samples.len()];
    let mut memory = vec![0.0; denoiser_memory(channels)];
    denoise_on(samples, channels, settings, 0, &mut memory, &mut out);
    out
}

/// The stretch of a span that begins at its sample `first` through the
/// noise removal `settings` give, going on from `memory` — all zeros at
/// the span's first sample — and leaving it there. What comes out at a
/// sample is the span's sample [`DENOISER_LATENCY`] before it, by the
/// setting that took over there; before the first, as it was.
pub fn denoise_on(
    samples: &[f32],
    channels: usize,
    settings: &[Setting<Denoiser>],
    first: i64,
    memory: &mut [f64],
    out: &mut [f32],
) {
    assert!(channels > 0 && samples.len() % channels == 0, "whole frames of {channels} channels");
    assert_eq!(out.len(), samples.len(), "an out as long as the samples");
    assert_eq!(memory.len(), denoiser_memory(channels), "each channel's memory");
    // ⚡No setting cleans, no frame is cleaned: what comes out is the sound
    // as it was, and the span's settings are the same in every stretch.
    let cleans = settings.iter().any(|setting| setting.value.amount != 0.0);
    let mut held: Vec<Channel> =
        memory.chunks_exact(CHANNEL_MEMORY).map(|kept| Channel::kept(kept, cleans)).collect();
    let mut walk = Walk::new(settings);
    let mut amount = 0.0;
    let late = DENOISER_LATENCY as i64;
    let frames = samples.chunks_exact(channels).zip(out.chunks_exact_mut(channels));
    for ((frame, written), at) in frames.zip(first..) {
        if let Some(denoiser) = walk.taking_over(at - late) {
            amount = denoiser.amount.clamp(0.0, 1.0);
        }
        let i = at.rem_euclid(FRAME as i64) as usize;
        for ((channel, &sample), slot) in held.iter_mut().zip(frame).zip(written.iter_mut()) {
            let was = channel.older[i];
            *slot = if amount == 0.0 {
                was
            } else {
                (f64::from(was) * (1.0 - amount) + f64::from(channel.cleaned[i]) * amount) as f32
            };
            channel.hearing[i] = sample;
            if i == FRAME - 1 {
                channel.heard();
            }
        }
    }
    for (channel, kept) in held.iter().zip(memory.chunks_exact_mut(CHANNEL_MEMORY)) {
        channel.keep(kept);
    }
}

#[cfg(test)]
#[path = "denoiser_tests.rs"]
mod tests;
