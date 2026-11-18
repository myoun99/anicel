//! The noise removal against the RNNoise it hears frames through: at no
//! amount the sound as it was, at the whole amount RNNoise's frames,
//! between them the two mixed — every one late by
//! [`DENOISER_LATENCY`] —, a setting taking over at its own sample, and a
//! span baked a stretch at a time as it is baked at once.

use super::{CHANNEL_MEMORY, DENOISER_LATENCY, Denoiser, denoise, denoise_on, denoiser_memory};
use crate::filter::Setting;
use audio_denoise::{FRAME, Suppressor};

const LATE: usize = DENOISER_LATENCY;

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

/// `sound` late by [`LATE`] frames of `channels`: silence first.
fn late(sound: &[f32], channels: usize) -> Vec<f32> {
    let mut out = vec![0.0; sound.len()];
    out[LATE * channels..].copy_from_slice(&sound[..sound.len() - LATE * channels]);
    out
}

#[test]
fn at_no_amount_it_hands_back_the_sound_as_it_was_late_by_two_frames() {
    let sound = sound(12_000, 2);
    assert_eq!(LATE, 2 * FRAME);
    assert_eq!(denoise(&sound, 2, &amount(0.0)), late(&sound, 2));
    assert_eq!(denoise(&sound, 2, &[]), late(&sound, 2), "before any setting, none");
}

// A frame of the sound comes back from RNNoise a frame late, and is heard
// whole a frame after it went in: at the whole amount it is RNNoise's
// frames two frames on — the sound as it was waits with them. (What comes
// out before the span's first sample does is no setting's, and the bake
// drops it.)
#[test]
fn at_the_whole_amount_it_is_rnnoises_frames_two_frames_on() {
    for channels in [1, 2] {
        let sound = sound(12_000, channels);
        let mut frames = vec![0.0; sound.len()];
        for channel in 0..channels {
            let mut suppressor = Suppressor::at_rest();
            for (k, frame) in sound.chunks_exact(FRAME * channels).enumerate() {
                let heard = std::array::from_fn(|i| frame[i * channels + channel]);
                for (i, value) in suppressor.frame(&heard).into_iter().enumerate() {
                    frames[(k * FRAME + i) * channels + channel] = value;
                }
            }
        }
        let out = denoise(&sound, channels, &amount(1.0));
        let (from, on) = (LATE * channels, FRAME * channels);
        assert_eq!(out[from..], frames[from - on..sound.len() - on], "{channels} channels");
        assert_ne!(out[from..], late(&sound, channels)[from..], "it cleaned");
    }
}

#[test]
fn between_them_it_mixes_the_sound_as_it_was_and_the_cleaned() {
    let sound = sound(9_600, 2);
    let (was, cleaned) = (denoise(&sound, 2, &amount(0.0)), denoise(&sound, 2, &amount(1.0)));
    for share in [0.25, 0.8] {
        let expected: Vec<f32> = was
            .iter()
            .zip(&cleaned)
            .map(|(&w, &c)| (f64::from(w) * (1.0 - share) + f64::from(c) * share) as f32)
            .collect();
        assert_eq!(denoise(&sound, 2, &amount(share)), expected, "{share}");
    }
}

// A setting is the sound's from its start: it comes out with that sample,
// two frames on.
#[test]
fn a_setting_takes_over_at_its_own_sample_and_comes_out_with_it() {
    let sound = sound(9_600, 1);
    let at = 3_000;
    let settings = [Setting { start: 0, value: Denoiser { amount: 0.0 } }, Setting { start: at as i64, value: Denoiser { amount: 1.0 } }];
    let out = denoise(&sound, 1, &settings);
    let (was, cleaned) = (late(&sound, 1), denoise(&sound, 1, &amount(1.0)));
    assert_eq!(out[..at + LATE], was[..at + LATE]);
    assert_eq!(out[at + LATE..], cleaned[at + LATE..]);
}

// An amount past either end is that end: the door takes any double.
#[test]
fn an_amount_past_either_end_is_that_end() {
    let sound = sound(4_800, 1);
    assert_eq!(denoise(&sound, 1, &amount(-0.5)), denoise(&sound, 1, &amount(0.0)));
    assert_eq!(denoise(&sound, 1, &amount(1.5)), denoise(&sound, 1, &amount(1.0)));
}

// A span baked a stretch at a time, each going on from the memory the one
// before left — the frame being heard, those before it, every channel's
// model — is the span baked at once, wherever the stretches break: mid
// frame, on a frame's edge, on a setting's start.
#[test]
fn a_span_baked_a_stretch_at_a_time_is_the_span_baked_at_once() {
    let sound = sound(12_000, 2);
    let settings = [
        Setting { start: 0, value: Denoiser { amount: 1.0 } },
        Setting { start: 5_000, value: Denoiser { amount: 0.3 } },
        Setting { start: 9_000, value: Denoiser { amount: 0.0 } },
    ];
    let whole = denoise(&sound, 2, &settings);
    assert_eq!(denoiser_memory(2), 2 * CHANNEL_MEMORY);
    for breaks in [vec![0, 12_000], vec![0, 1, 479, 480, 481, 5_000, 7_777, 12_000], vec![0, 6_000, 11_999, 12_000]] {
        let mut memory = vec![0.0; denoiser_memory(2)];
        let mut stretched = vec![0.0_f32; sound.len()];
        for pair in breaks.windows(2) {
            let (from, to) = (2 * pair[0], 2 * pair[1]);
            denoise_on(&sound[from..to], 2, &settings, pair[0] as i64, &mut memory, &mut stretched[from..to]);
        }
        assert_eq!(stretched, whole, "broken at {breaks:?}");
    }
}
