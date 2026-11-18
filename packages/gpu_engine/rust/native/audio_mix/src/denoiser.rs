//! A sound row's noise removal (board audio-fx-second-effect-and-presets,
//! Q1 = 1, 유저 2026-11-18: 「ノイズ除去 는 다음 라운드에 효과로 지어 セリフ 에
//! 더한다」): RNNoise (native/audio_denoise, [`Suppressor`]) over a span, the
//! cleaned sound mixed into the sound as it was by the setting's amount —
//! and a voice take's, at its whole amount (board
//! voice-take-denoise-lands-late).
//!
//! 🚨LATE BY ITS ROAD, THE SOUND AS IT WAS WITH IT. A frame comes out of
//! RNNoise as the one before it, once the next is heard — so what comes out
//! at a sample is the span's sample [`denoiser_latency`] before it, the
//! cleaned and the sound as it was alike: two frames at RNNoise's rate,
//! and the conversions' reach ahead at another. The bake reads that much
//! past the span and drops as much at its front (`FilterStretches`, the
//! app's qa_audio_filter.dart), so a span is late by nothing, and an
//! amount of 0 hands back every sample as it was. ↩️A voice take went a
//! road of its own that read nothing past it, and was placed a frame late.
//!
//! 🗣️AT ANY RATE (board audio-fx-second-effect-and-presets-Q2 = 1, 유저
//! 2026-11-18 21:59: 「레이트를 바꿔서라도 어디서나」): RNNoise hears
//! [`audio_denoise::RATE`] alone — its model, its frames and its bands are
//! built around it — so a span at another rate is converted to it and the
//! cleaned sound back, by the conform's own conversion ([`Design::run`],
//! its quality), and mixed with the sound as it was at the span's rate,
//! never converted. RNNoise's wrappers convert so (OBS, EasyEffects —
//! sources on the board card). Each channel through a model of its own.

use audio_denoise::{FRAME, RATE, Suppressor};

use crate::filter::{Setting, Walk};
use crate::resample::{DEFAULT_BANDWIDTH, DEFAULT_STOPBAND_DB, Design, Geometry};

/// A noise removal's setting at one moment.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Denoiser {
    /// How much of the cleaned sound is heard, 0 to 1 — at 0 the sound as
    /// it was, at 1 the cleaned sound alone.
    pub amount: f64,
}

/// The doubles a setting takes at the filter door: the amount.
pub const DENOISER_VALUES: usize = 1;

impl Denoiser {
    /// The noise removal a setting's [`DENOISER_VALUES`] doubles say.
    pub(crate) fn of_values(v: &[f64]) -> Self {
        Self { amount: v[0] }
    }
}

/// The road a sound at a rate is heard through RNNoise by: converted to
/// [`RATE`] and back, at the conform's quality — no conversion at RNNoise's
/// own rate. Every count on it is of a span's samples from its first, so
/// where a stretch begins tells how far each step has come.
#[derive(Clone, Copy)]
struct Road {
    rate: i32,
    up: Option<Geometry>,
    down: Option<Geometry>,
}

impl Road {
    fn at(rate: i32) -> Self {
        let geometry = |from, to| Geometry::new(from, to, DEFAULT_STOPBAND_DB, DEFAULT_BANDWIDTH);
        Self { rate, up: geometry(rate, RATE), down: geometry(RATE, rate) }
    }

    /// RNNoise's samples made of the span's first `heard`.
    fn made(&self, heard: i64) -> i64 {
        self.up.map_or(heard, |up| up.ready_end(heard, false))
    }

    /// The cleaned samples, put back where they were heard, made of
    /// RNNoise's first `made`: a frame's comes back once it is heard whole,
    /// as the one before it — what comes back first is RNNoise's before
    /// anything, and is dropped.
    fn cleaned(made: i64) -> i64 {
        let frame = FRAME as i64;
        (made / frame - 1).max(0) * frame
    }

    /// The cleaned samples back at the span's rate made of its first
    /// `heard`.
    fn wet(&self, heard: i64) -> i64 {
        let cleaned = Self::cleaned(self.made(heard));
        self.down.map_or(cleaned, |down| down.ready_end(cleaned, false))
    }

    /// Samples late what comes out is: the conversion up's reach ahead,
    /// a frame heard whole and the frame RNNoise gives it back after, the
    /// conversion down's reach ahead — and the sample being heard, which
    /// comes in after what comes out. Two frames at RNNoise's own rate.
    /// 🧪`what_comes_out_was_made_before_it_at_every_rate`.
    fn latency(&self) -> usize {
        let own = |samples: f64| samples * f64::from(self.rate) / f64::from(RATE);
        let ahead = |geometry: Geometry| geometry.half_length as f64 / geometry.interpolation as f64;
        let up = self.up.map_or(0.0, ahead);
        let down = self.down.map_or(0.0, |down| own(ahead(down)));
        (up + own((2 * FRAME - 1) as f64) + down).ceil() as usize + 1
    }

    /// The span's samples one channel holds: what comes out late as it
    /// was — and so what the conversion up still reads back, for it reads
    /// back no further than the two conversions read ahead, both in the
    /// lateness (🧪`what_comes_out_was_made_before_it_at_every_rate`).
    fn held(&self) -> usize {
        self.latency()
    }

    /// The doubles one channel's memory takes: its suppressor's, the
    /// samples it [`Road::held`], the frame RNNoise is hearing, the cleaned
    /// samples the conversion down still reads back, and the cleaned
    /// samples back at the span's rate still to come out.
    fn memory(&self) -> usize {
        Suppressor::VALUES + self.held() + FRAME + self.down.map_or(0, reach) + self.latency()
    }
}

/// The samples below the first it has not had that a conversion's next
/// output reads back to: an output reads `(taps - 1) / interpolation`
/// below its base, and the next one's base is never before that sample.
fn reach(geometry: Geometry) -> usize {
    ((geometry.taps - 1) / geometry.interpolation) as usize
}

/// Samples late a noise removal's sound comes out at `rate`: two frames
/// at RNNoise's own, and the conversions' reach at another.
pub fn denoiser_latency(rate: i32) -> usize {
    Road::at(rate).latency()
}

/// The doubles a noise removal's memory takes over `channels` at `rate`.
pub fn denoiser_memory(channels: usize, rate: i32) -> usize {
    channels * Road::at(rate).memory()
}

/// [`denoise_on`] over a whole span, from rest at its first sample — and,
/// like the door's, late by [`denoiser_latency`].
pub fn denoise(samples: &[f32], channels: usize, rate: i32, settings: &[Setting<Denoiser>]) -> Vec<f32> {
    let mut out = vec![0.0; samples.len()];
    let mut memory = vec![0.0; denoiser_memory(channels, rate)];
    let made = denoise_on(samples, channels, rate, settings, 0, &mut memory, &mut out);
    assert!(made, "room for the conversions' taps");
    out
}

/// The two conversions a cleaning stretch runs: none where the road has
/// none.
type Designs = (Option<Design>, Option<Design>);

/// The stretch of a span at `rate` that begins at its sample `first`
/// through the noise removal `settings` give, going on from `memory` —
/// all zeros at the span's first sample — and leaving it there. What
/// comes out at a sample is the span's sample [`denoiser_latency`] before
/// it, by the setting that took over there; before the first, silence.
/// False, with `out` and `memory` untouched, when there was no room for a
/// conversion's taps.
pub fn denoise_on(
    samples: &[f32],
    channels: usize,
    rate: i32,
    settings: &[Setting<Denoiser>],
    first: i64,
    memory: &mut [f64],
    out: &mut [f32],
) -> bool {
    assert!(channels > 0 && samples.len() % channels == 0, "whole frames of {channels} channels");
    assert_eq!(out.len(), samples.len(), "an out as long as the samples");
    let road = Road::at(rate);
    assert_eq!(memory.len(), channels * road.memory(), "each channel's memory");
    // ⚡No setting cleans, nothing is cleaned: what comes out is the sound
    // as it was, and the span's settings are the same in every stretch.
    let cleans = settings.iter().any(|setting| setting.value.amount != 0.0);
    let designs: Option<Designs> = if cleans {
        let design = |geometry: Option<Geometry>, from, to| match geometry {
            None => Some(None),
            Some(_) => Design::new(from, to, DEFAULT_STOPBAND_DB, DEFAULT_BANDWIDTH).map(Some),
        };
        let (Some(up), Some(down)) = (design(road.up, rate, RATE), design(road.down, RATE, rate)) else {
            return false;
        };
        Some((up, down))
    } else {
        None
    };
    let count = samples.len() / channels;
    let heard: Vec<Heard> = memory
        .chunks_exact_mut(road.memory())
        .enumerate()
        .map(|(channel, kept)| {
            let mine: Vec<f32> = samples.iter().skip(channel).step_by(channels).copied().collect();
            Heard::on(&road, designs.as_ref(), first, &mine, kept)
        })
        .collect();
    let late = road.latency() as i64;
    let mut walk = Walk::new(settings);
    let mut amount = 0.0;
    for ((written, index), at) in out.chunks_exact_mut(channels).zip(0..count).zip(first..) {
        if let Some(denoiser) = walk.taking_over(at - late) {
            amount = denoiser.amount.clamp(0.0, 1.0);
        }
        for (channel, slot) in heard.iter().zip(written.iter_mut()) {
            let was = channel.was(index, count, late as usize);
            *slot = if amount == 0.0 {
                was
            } else {
                (f64::from(was) * (1.0 - amount) + f64::from(channel.wet[index]) * amount) as f32
            };
        }
    }
    true
}

/// One channel of a stretch through the road: its input held back as far
/// as the road reads, and the cleaned sound at the span's rate for each
/// sample to come out, from the stretch's first on.
struct Heard {
    input: Vec<f32>,
    wet: Vec<f32>,
}

impl Heard {
    /// The sound as it was that comes out at the stretch's sample `index`
    /// of `count`: the one `late` before it.
    fn was(&self, index: usize, count: usize, late: usize) -> f32 {
        self.input[self.input.len() - count - late + index]
    }

    /// `samples` — the channel's, from the span's sample `first` — heard
    /// on from `kept`, and `kept` left for the next stretch. Without
    /// `designs`, nothing cleans: only the input is held.
    fn on(road: &Road, designs: Option<&Designs>, first: i64, samples: &[f32], kept: &mut [f64]) -> Self {
        let (state, rest) = kept.split_at_mut(Suppressor::VALUES);
        let (held, rest) = rest.split_at_mut(road.held());
        let (hearing, rest) = rest.split_at_mut(FRAME);
        let (cleaned_held, waiting) = rest.split_at_mut(road.down.map_or(0, reach));
        let input = joined(held, samples);
        keep(held, &input[input.len() - held.len()..]);
        let Some((up, down)) = designs else {
            return Self { input, wet: Vec::new() };
        };
        let last = first + samples.len() as i64;
        let made = Self::made(road, up.as_ref(), first, last, &input, samples);
        let cleaned = Self::cleaned(road.made(first), &made, state, hearing);
        let back = Self::back(road, down.as_ref(), first, last, cleaned, cleaned_held);
        // What was made but has not come out, from the stretch's first
        // sample's own on: the last stretch's, then this one's.
        let late = road.latency() as i64;
        let waited = (road.wet(first) - (first - late)) as usize;
        let mut wet: Vec<f32> = waiting[..waited].iter().map(|&value| value as f32).collect();
        wet.extend_from_slice(&back);
        keep(waiting, &wet[samples.len()..]);
        Self { input, wet }
    }

    /// RNNoise's samples the span's samples up to `last` made whole that
    /// those up to `first` had not: the samples themselves at its rate.
    fn made(road: &Road, up: Option<&Design>, first: i64, last: i64, input: &[f32], samples: &[f32]) -> Vec<f32> {
        let Some(up) = up else {
            return samples.to_vec();
        };
        let (from, to) = (road.made(first), road.made(last));
        let mut made = vec![0.0; (to - from) as usize];
        up.run(1, input, first - (input.len() - samples.len()) as i64, last, from, &mut made);
        made
    }

    /// `made` — RNNoise's samples from its sample `from` — through it a
    /// frame at a time, the frame being heard going on from `hearing`, and
    /// the model from `state`: the cleaned samples, each put back where it
    /// was heard.
    fn cleaned(from: i64, made: &[f32], state: &mut [f64], hearing: &mut [f64]) -> Vec<f32> {
        let so_far = (from % FRAME as i64) as usize;
        let mut frames: Vec<f32> = hearing[..so_far].iter().map(|&value| value as f32).collect();
        frames.extend_from_slice(made);
        let mut suppressor = Suppressor::kept(state);
        let mut cleaned = Vec::new();
        let numbers = (from - so_far as i64) / FRAME as i64..;
        for (frame, number) in frames.chunks_exact(FRAME).zip(numbers) {
            let back = suppressor.frame(frame.try_into().expect("a whole frame"));
            if number > 0 {
                cleaned.extend_from_slice(&back);
            }
        }
        suppressor.keep(state);
        keep(hearing, &frames[frames.len() / FRAME * FRAME..]);
        cleaned
    }

    /// `cleaned` — made of the span's samples from `first` to `last` —
    /// back at the span's rate, the conversion down going on from
    /// `cleaned_held`.
    fn back(road: &Road, down: Option<&Design>, first: i64, last: i64, cleaned: Vec<f32>, cleaned_held: &mut [f64]) -> Vec<f32> {
        let Some(down) = down else {
            return cleaned;
        };
        let (from, to) = (Road::cleaned(road.made(first)), Road::cleaned(road.made(last)));
        let all = joined(cleaned_held, &cleaned);
        let mut back = vec![0.0; (road.wet(last) - road.wet(first)) as usize];
        down.run(1, &all, from - cleaned_held.len() as i64, to, road.wet(first), &mut back);
        keep(cleaned_held, &all[all.len() - cleaned_held.len()..]);
        back
    }
}

/// `held` read back as samples, with `samples` after them.
fn joined(held: &[f64], samples: &[f32]) -> Vec<f32> {
    let mut all: Vec<f32> = held.iter().map(|&value| value as f32).collect();
    all.extend_from_slice(samples);
    all
}

/// Writes `samples` into the front of `kept`, zeros after them.
fn keep(kept: &mut [f64], samples: &[f32]) {
    let values = samples.iter().map(|&value| f64::from(value)).chain(std::iter::repeat(0.0));
    for (slot, value) in kept.iter_mut().zip(values) {
        *slot = value;
    }
}

#[cfg(test)]
#[path = "denoiser_tests.rs"]
mod tests;
