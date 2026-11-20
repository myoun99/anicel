//! The Rust denoiser against the app's ledger, bit for bit: a take run
//! through it frame after frame as the C ran one, on takes made up here —
//! a voice that glides and pauses, noise, digital silence, a clipped take
//! and a take shorter than one frame.
//!
//! Each take's output was pinned beside the C's answer, and so is the C's
//! to the bit (connection-round-checklist A, 관제 2026-11-07); the C went in
//! the connection round (H, 관제 2026-11-08 05:58), and the row is what holds
//! these tests now. It holds on every device because the kernel and these
//! takes call libm, never the device's maths library (Cargo.toml).

use super::{FRAME, Suppressor};

/// `take`, interleaved by `channels`, as the C's door ran one: each
/// channel through a suppressor of its own a frame at a time, its last
/// frame padded with silence, each frame's output written over the frame
/// it heard — a frame late, as the C placed a take
/// (board voice-take-denoise-lands-late).
fn run(take: &[f32], channels: usize) -> Vec<f32> {
    let mut out = take.to_vec();
    let frames = take.len() / channels;
    for channel in 0..channels {
        let mut suppressor = Suppressor::at_rest();
        for start in (0..frames).step_by(FRAME) {
            let valid = (frames - start).min(FRAME);
            let mut input = [0.0f32; FRAME];
            for (i, value) in input.iter_mut().enumerate().take(valid) {
                *value = take[(start + i) * channels + channel];
            }
            let heard = suppressor.frame(&input);
            for (i, &value) in heard.iter().enumerate().take(valid) {
                out[(start + i) * channels + channel] = value;
            }
        }
    }
    out
}

/// The take run — not the take it was handed — sample for sample as the
/// app's ledger pins it as `id`.
fn holds(id: &str, take: &[f32], channels: usize) {
    let out = run(take, channels);
    assert_ne!(out, take, "LIVENESS: the take was denoised");
    let bytes: Vec<u8> = out.iter().flat_map(|sample| sample.to_le_bytes()).collect();
    ledger::assert_pinned(id, &bytes);
}

/// xorshift32, in [-1, 1).
struct Noise(u32);

impl Noise {
    fn next(&mut self) -> f32 {
        let mut x = self.0;
        x ^= x << 13;
        x ^= x >> 17;
        x ^= x << 5;
        self.0 = x;
        (x as f64 / u32::MAX as f64 * 2.0 - 1.0) as f32
    }
}

/// A voice-like take: harmonics over a pitch gliding 110 → 260 Hz in
/// syllables, with gaps of digital silence, under noise at `noise`.
fn voice(frames: usize, seed: u32, noise: f32) -> Vec<f32> {
    let mut hiss = Noise(seed);
    let mut phase = 0.0f64;
    (0..frames)
        .map(|n| {
            let t = n as f64 / 48_000.0;
            let f0 = 110.0 + 150.0 * (0.5 + 0.5 * libm::sin(t * 0.7));
            phase += 2.0 * std::f64::consts::PI * f0 / 48_000.0;
            let syllable = (t * 3.1).fract();
            if (0.8..0.9).contains(&syllable) {
                return 0.0;
            }
            let envelope = libm::sin(syllable * std::f64::consts::PI).max(0.0);
            let voiced: f64 = (1..=12).map(|h| libm::sin(phase * h as f64) / h as f64).sum();
            (0.3 * envelope * voiced) as f32 + noise * hiss.next()
        })
        .collect()
}

/// A number in [lo, hi) off `dice`.
fn roll(dice: &mut Noise, lo: f64, hi: f64) -> f64 {
    lo + (hi - lo) * (0.5 + 0.5 * f64::from(dice.next()))
}

/// Syllables whose pitch the octave check has to argue over, each its
/// own: the fundamental and the odd harmonics turned down by chance, a
/// second voice in unison, a fifth or an octave above, the pitch sliding
/// a little or a lot, the attack soft or sharp, the hiss mostly faint.
fn octave_doubts(frames: usize, seed: u32) -> Vec<f32> {
    use std::f64::consts::{PI, TAU};
    let mut dice = Noise(seed);
    let mut take = Vec::with_capacity(frames);
    while take.len() < frames {
        let f0 = roll(&mut dice, 70.0, 400.0);
        let length = roll(&mut dice, 4_800.0, 14_400.0) as usize;
        let above = [1.0, 1.5, 2.0][roll(&mut dice, 0.0, 3.0) as usize];
        let fundamental = roll(&mut dice, 0.0, 1.0);
        let odd = roll(&mut dice, 0.0, 1.0);
        let slide = roll(&mut dice, 0.8, 1.25);
        let attack = roll(&mut dice, 0.2, 1.0);
        let hiss = (0.1 * roll(&mut dice, 0.0, 1.0).powi(2)) as f32;
        let (mut low, mut high) = (0.0f64, 0.0f64);
        for n in 0..length {
            let at = n as f64 / length as f64;
            let f = f0 * libm::pow(slide, at);
            low += TAU * f / 48_000.0;
            high += TAU * f * above / 48_000.0;
            let envelope = libm::pow(libm::sin(PI * at), attack);
            let voiced: f64 = (1..=10)
                .map(|h| {
                    let weight = match h {
                        1 => fundamental,
                        _ if h % 2 == 1 => odd,
                        _ => 1.0,
                    };
                    let h = h as f64;
                    weight * (libm::sin(low * h) + 0.5 * libm::sin(high * h)) / h
                })
                .sum();
            take.push((0.2 * envelope * voiced) as f32 + hiss * dice.next());
        }
    }
    take.truncate(frames);
    take
}

#[test]
fn a_pitch_in_doubt_comes_out_as_pinned() {
    holds("audio_denoise/pitch-in-doubt", &octave_doubts(20 * 48_000, 29), 1);
}

#[test]
fn a_noisy_voice_comes_out_as_pinned() {
    // Three seconds and a ragged end: the last frame is padded.
    holds("audio_denoise/noisy-voice", &voice(3 * 48_000 + 123, 1, 0.05), 1);
}

#[test]
fn noise_alone_comes_out_as_pinned() {
    let mut hiss = Noise(7);
    let take: Vec<f32> = (0..2 * 48_000).map(|_| 0.2 * hiss.next()).collect();
    holds("audio_denoise/noise-alone", &take, 1);
}

#[test]
fn each_channel_of_a_stereo_take_comes_out_as_pinned() {
    let left = voice(48_000 + 480 * 7 + 1, 3, 0.02);
    let mut hiss = Noise(11);
    let take: Vec<f32> = left.iter().flat_map(|&l| [l, 0.1 * hiss.next()]).collect();
    holds("audio_denoise/stereo-take", &take, 2);
}

#[test]
fn silence_between_sounds_comes_out_as_pinned() {
    // Digital silence and a whisper of noise: the frames with no audio
    // leave the cepstra alone, then the voice comes in on what they left.
    let mut hiss = Noise(5);
    let mut take = vec![0.0f32; 48_000 / 2];
    take.extend((0..48_000 / 2).map(|_| 1e-7 * hiss.next()));
    take.extend(voice(48_000, 9, 0.01));
    take.extend(vec![0.0f32; 4_800]);
    take.extend(voice(48_000 / 2, 13, 0.03));
    holds("audio_denoise/silence-between-sounds", &take, 1);
}

#[test]
fn a_clipped_take_comes_out_as_pinned() {
    // Loud enough that the network's sums run off the tanh table's ends.
    let take: Vec<f32> = voice(48_000, 17, 0.3).iter().map(|v| (v * 8.0).clamp(-1.0, 1.0)).collect();
    holds("audio_denoise/clipped-take", &take, 1);
}

#[test]
fn a_take_shorter_than_a_frame_comes_out_as_pinned() {
    holds("audio_denoise/shorter-than-a-frame", &voice(100, 19, 0.1), 1);
}

// A row's noise removal bakes a span a stretch at a time, keeping each
// channel's model between stretches as doubles: one read back goes on as
// the one that was kept would have — the model, its memories, its
// cepstra's place and its last period alike.
#[test]
fn a_suppressor_kept_and_read_back_goes_on_as_it_would_have() {
    let take = voice(40 * FRAME, 7, 0.03);
    let frames: Vec<[f32; FRAME]> = take.chunks_exact(FRAME).map(|f| f.try_into().unwrap()).collect();
    let mut whole = Suppressor::at_rest();
    let expected: Vec<[f32; FRAME]> = frames.iter().map(|f| whole.frame(f)).collect();
    for cut in [1, 9, 23] {
        let mut first = Suppressor::at_rest();
        let mut out: Vec<[f32; FRAME]> = frames[..cut].iter().map(|f| first.frame(f)).collect();
        let mut kept = vec![0.0; Suppressor::VALUES];
        first.keep(&mut kept);
        assert!(kept.iter().any(|&v| v != 0.0), "LIVENESS: something was kept");
        let mut read_back = Suppressor::kept(&kept);
        out.extend(frames[cut..].iter().map(|f| read_back.frame(f)));
        assert_eq!(out, expected, "kept after {cut} frames");
    }
    let mut zeros = Suppressor::kept(&vec![0.0; Suppressor::VALUES]);
    assert_eq!(frames.iter().map(|f| zeros.frame(f)).collect::<Vec<_>>(), expected, "all zeros is at rest");
}

// 🎯HOW LATE A FRAME COMES BACK (board voice-take-denoise-lands-late — 관제
// asked it measured, not read off the code): a voice through RNNoise lines
// up with itself a frame on — the half of its window the overlap waits
// for, 10 ms at 48 kHz, not two frames. The sample short of the frame is
// the high-pass RNNoise hears through (`mem_hp_x`): a phase lead on the
// voice's lowest harmonics, not a lateness.
#[test]
fn a_voice_comes_back_a_frame_late() {
    let take = voice(48_000, 31, 0.0);
    let mut suppressor = Suppressor::at_rest();
    let out: Vec<f32> = take
        .chunks_exact(FRAME)
        .flat_map(|frame| suppressor.frame(frame.try_into().unwrap()))
        .collect();
    let along = |lag: usize| -> f64 {
        (0..take.len() - 3 * FRAME)
            .map(|t| f64::from(take[t]) * f64::from(out[t + lag]))
            .sum()
    };
    let lag = (0..=3 * FRAME).max_by(|&a, &b| along(a).total_cmp(&along(b)));
    assert_eq!(lag, Some(FRAME - 1));
}
