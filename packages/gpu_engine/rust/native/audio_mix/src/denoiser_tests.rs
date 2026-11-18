//! The noise removal against the RNNoise it hears frames through: at no
//! amount the sound as it was, at the whole amount RNNoise's frames —
//! at another rate heard at RNNoise's own and brought back, the conform's
//! conversions bit for bit —, between them the two mixed, every one late
//! by [`denoiser_latency`]; a setting taking over at its own sample, and a
//! span baked a stretch at a time as it is baked at once, at every rate.

use super::{Denoiser, Road, denoise, denoise_on, denoiser_latency, denoiser_memory};
use crate::filter::Setting;
use crate::resample::{DEFAULT_BANDWIDTH, DEFAULT_STOPBAND_DB, Resampler};
use audio_denoise::{FRAME, RATE, Suppressor};

/// The rates a project's sound is at (the app's `audioSampleRatePresets`),
/// RNNoise's among them.
const RATES: [i32; 3] = [44_100, RATE, 96_000];

/// `channels` of a made-up voice in noise: a well-mixed u32 (lowbias32)
/// under a tone that swells and falls, so RNNoise has both to tell apart.
fn sound(frames: usize, channels: usize) -> Vec<f32> {
    let mixed = |mut x: u32| {
        x ^= x >> 16;
        x = x.wrapping_mul(0x7feb_352d);
        x ^= x >> 15;
        x = x.wrapping_mul(0x846c_a68b);
        x ^ (x >> 16)
    };
    (0..frames * channels)
        .map(|i| {
            let t = (i / channels) as f64;
            let swell = 0.5 + 0.5 * libm::sin(t / 3_000.0);
            let tone = 0.4 * swell * libm::sin(t * 0.0418 + (i % channels) as f64);
            let noise = 0.05 * (f64::from(mixed(i as u32)) / 2_147_483_648.0 - 1.0);
            (tone + noise) as f32
        })
        .collect()
}

fn amount(amount: f64) -> [Setting<Denoiser>; 1] {
    [Setting { start: 0, value: Denoiser { amount } }]
}

/// `sound` late by `late` frames of `channels`: silence first.
fn late(sound: &[f32], channels: usize, late: usize) -> Vec<f32> {
    let mut out = vec![0.0; sound.len()];
    out[late * channels..].copy_from_slice(&sound[..sound.len() - late * channels]);
    out
}

/// `samples`, one channel, through RNNoise a frame at a time — the last
/// frame padded with silence — each frame's put back where it was heard:
/// what comes back first, RNNoise's before anything, dropped.
fn cleaned(samples: &[f32]) -> Vec<f32> {
    let mut suppressor = Suppressor::at_rest();
    let mut padded = samples.to_vec();
    padded.resize(samples.len().div_ceil(FRAME) * FRAME, 0.0);
    let back: Vec<f32> = padded
        .chunks_exact(FRAME)
        .flat_map(|frame| suppressor.frame(frame.try_into().unwrap()))
        .collect();
    back[FRAME..].iter().copied().chain(std::iter::repeat(0.0)).take(samples.len()).collect()
}

/// One channel's whole conversion, as the conform makes it.
fn converted(samples: &[f32], from: i32, to: i32) -> Vec<f32> {
    let mut resampler = Resampler::new(1, from, to, DEFAULT_STOPBAND_DB, DEFAULT_BANDWIDTH).unwrap();
    assert!(resampler.push(samples));
    resampler.end();
    let mut out = vec![0.0; resampler.ready() as usize];
    resampler.pull(&mut out);
    out
}

/// Channel `channel` of `channels`.
fn channel_of(samples: &[f32], channels: usize, channel: usize) -> Vec<f32> {
    samples.iter().skip(channel).step_by(channels).copied().collect()
}

#[test]
fn at_no_amount_it_hands_back_the_sound_as_it_was_late() {
    assert_eq!(denoiser_latency(RATE), 2 * FRAME, "two frames at RNNoise's own rate");
    for rate in RATES {
        let sound = sound(12_000, 2);
        let late = late(&sound, 2, denoiser_latency(rate));
        assert_eq!(denoise(&sound, 2, rate, &amount(0.0)), late, "{rate}");
        assert_eq!(denoise(&sound, 2, rate, &[]), late, "{rate}: before any setting, none");
    }
}

// A frame of the sound comes back from RNNoise a frame late, and is heard
// whole a frame after it went in: at the whole amount it is RNNoise's
// frames two frames on — the sound as it was waits with them.
#[test]
fn at_the_whole_amount_it_is_rnnoises_frames_two_frames_on() {
    for channels in [1, 2] {
        let sound = sound(12_000, channels);
        let late = denoiser_latency(RATE);
        let out = denoise(&sound, channels, RATE, &amount(1.0));
        for channel in 0..channels {
            let expected = cleaned(&channel_of(&sound, channels, channel));
            let heard = channel_of(&out, channels, channel);
            assert_eq!(heard[late..], expected[..expected.len() - late], "{channels} channels");
            assert!(heard[..late].iter().all(|&sample| sample == 0.0), "before the first, silence");
        }
        assert_ne!(out, self::late(&sound, channels, late), "it cleaned");
    }
}

// 🗣️audio-fx-second-effect-and-presets-Q2 = 1 (유저 2026-11-18 21:59):
// 「레이트를 바꿔서라도 어디서나」. At another rate the sound is heard at
// RNNoise's own — the conform's conversion up, RNNoise, the conversion
// back — bit for bit as the whole sound converted would be, late by the
// road's reach.
#[test]
fn at_another_rate_it_is_rnnoise_heard_at_its_own_rate_and_brought_back() {
    for rate in [44_100, 96_000] {
        let sound = sound(12_000, 2);
        let late = denoiser_latency(rate);
        let out = denoise(&sound, 2, rate, &amount(1.0));
        for channel in 0..2 {
            let up = converted(&channel_of(&sound, 2, channel), rate, RATE);
            let back = converted(&cleaned(&up), RATE, rate);
            let heard = channel_of(&out, 2, channel);
            assert_eq!(heard[late..], back[..heard.len() - late], "{rate}, channel {channel}");
        }
        assert_ne!(out, self::late(&sound, 2, late), "{rate}: it cleaned");
    }
}

// What comes out at a sample was made before it: the cleaned sound late
// by the latency is there once the sample is heard, at a project's rates
// and others — and what a stretch holds of it reaches back no further than
// its memory keeps.
#[test]
fn what_comes_out_was_made_before_it_at_every_rate() {
    for rate in [8_000, 22_050, 32_000, 44_100, RATE, 88_200, 96_000, 192_000] {
        let road = Road::at(rate);
        let late = road.latency() as i64;
        for heard in 0..20_000 {
            let out = heard - late;
            assert!(out < road.wet(heard + 1), "{rate}: the sample {out} comes out at {heard}");
            assert!(road.wet(heard) <= heard, "{rate}: nothing made ahead of {heard}");
        }
    }
    assert_eq!(denoiser_latency(44_100), 1_039, "two frames, and the conversions' reach");
}

#[test]
fn between_them_it_mixes_the_sound_as_it_was_and_the_cleaned() {
    let sound = sound(9_600, 2);
    for rate in [RATE, 44_100] {
        let (was, cleaned) = (denoise(&sound, 2, rate, &amount(0.0)), denoise(&sound, 2, rate, &amount(1.0)));
        for share in [0.25, 0.8] {
            let expected: Vec<f32> = was
                .iter()
                .zip(&cleaned)
                .map(|(&w, &c)| (f64::from(w) * (1.0 - share) + f64::from(c) * share) as f32)
                .collect();
            assert_eq!(denoise(&sound, 2, rate, &amount(share)), expected, "{rate}: {share}");
        }
    }
}

// A setting is the sound's from its start: it comes out with that sample,
// as late as the sound.
#[test]
fn a_setting_takes_over_at_its_own_sample_and_comes_out_with_it() {
    let sound = sound(9_600, 1);
    let at = 3_000;
    let settings = [Setting { start: 0, value: Denoiser { amount: 0.0 } }, Setting { start: at as i64, value: Denoiser { amount: 1.0 } }];
    for rate in [RATE, 44_100] {
        let late = denoiser_latency(rate);
        let out = denoise(&sound, 1, rate, &settings);
        let (was, cleaned) = (self::late(&sound, 1, late), denoise(&sound, 1, rate, &amount(1.0)));
        assert_eq!(out[..at + late], was[..at + late], "{rate}");
        assert_eq!(out[at + late..], cleaned[at + late..], "{rate}");
    }
}

// An amount past either end is that end: the door takes any double.
#[test]
fn an_amount_past_either_end_is_that_end() {
    let sound = sound(4_800, 1);
    assert_eq!(denoise(&sound, 1, RATE, &amount(-0.5)), denoise(&sound, 1, RATE, &amount(0.0)));
    assert_eq!(denoise(&sound, 1, RATE, &amount(1.5)), denoise(&sound, 1, RATE, &amount(1.0)));
}

// A span baked a stretch at a time, each going on from the memory the one
// before left — what the conversions read back, the frame being heard,
// every channel's model, what is made and waits to come out — is the span
// baked at once, wherever the stretches break: mid frame, on a frame's
// edge, on a setting's start, one sample long.
#[test]
fn a_span_baked_a_stretch_at_a_time_is_the_span_baked_at_once() {
    let sound = sound(12_000, 2);
    let settings = [
        Setting { start: 0, value: Denoiser { amount: 1.0 } },
        Setting { start: 5_000, value: Denoiser { amount: 0.3 } },
        Setting { start: 9_000, value: Denoiser { amount: 0.0 } },
    ];
    for rate in RATES {
        let whole = denoise(&sound, 2, rate, &settings);
        for breaks in [vec![0, 12_000], vec![0, 1, 2, 479, 480, 481, 5_000, 7_777, 12_000], vec![0, 6_000, 11_999, 12_000]] {
            let mut memory = vec![0.0; denoiser_memory(2, rate)];
            let mut stretched = vec![0.0_f32; sound.len()];
            for pair in breaks.windows(2) {
                let (from, to) = (2 * pair[0], 2 * pair[1]);
                let ran = denoise_on(&sound[from..to], 2, rate, &settings, pair[0] as i64, &mut memory, &mut stretched[from..to]);
                assert!(ran);
            }
            assert_eq!(stretched, whole, "{rate}: broken at {breaks:?}");
        }
    }
}
