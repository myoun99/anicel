//! The Rust denoiser against the engine's C (native/oracle), bit for bit:
//! both are asked through their exports, on takes made up here — a voice
//! that glides and pauses, noise, digital silence, a clipped take, a take
//! shorter than one frame, and the refusals.

use super::qa_audio_denoise_f32;

type Denoise = unsafe extern "C" fn(*mut f32, i64, i32, i32) -> i32;

/// What `denoise` makes of `take`, and what it answered.
fn ask(denoise: Denoise, take: &[f32], channels: i32, rate: i32) -> (i32, Vec<f32>) {
    let mut samples = take.to_vec();
    let frames = (samples.len() / channels.max(1) as usize) as i64;
    // SAFETY: `samples` holds `frames` x `channels` floats.
    let ok = unsafe { denoise(samples.as_mut_ptr(), frames, channels, rate) };
    (ok, samples)
}

fn c() -> Denoise {
    // SAFETY: qa_audio_denoise.c's declaration.
    unsafe { oracle::export::<Denoise>("qa_audio_denoise_f32") }
}

/// The take both make the same of, sample for sample, bit for bit — and
/// a denoised one: 1, and not the take it was handed.
fn holds(take: &[f32], channels: i32) {
    let (c_ok, c_out) = ask(c(), take, channels, 48_000);
    let (ok, out) = ask(qa_audio_denoise_f32, take, channels, 48_000);
    assert_eq!((ok, c_ok), (1, 1), "both denoise a 48 kHz take");
    let first = out.iter().zip(&c_out).position(|(a, b)| a.to_bits() != b.to_bits());
    if let Some(at) = first {
        panic!(
            "sample {at} (frame {}, channel {}): rust {} c {} of {}",
            at / channels as usize / 480,
            at % channels as usize,
            out[at],
            c_out[at],
            out.len()
        );
    }
    assert_ne!(out, take, "LIVENESS: the take was denoised");
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
            let f0 = 110.0 + 150.0 * (0.5 + 0.5 * (t * 0.7).sin());
            phase += 2.0 * std::f64::consts::PI * f0 / 48_000.0;
            let syllable = (t * 3.1).fract();
            if (0.8..0.9).contains(&syllable) {
                return 0.0;
            }
            let envelope = (syllable * std::f64::consts::PI).sin().max(0.0);
            let voiced: f64 = (1..=12).map(|h| (phase * h as f64).sin() / h as f64).sum();
            (0.3 * envelope * voiced) as f32 + noise * hiss.next()
        })
        .collect()
}

/// A number in [lo, hi) off `dice`.
fn roll(dice: &mut Noise, lo: f64, hi: f64) -> f64 {
    lo + (hi - lo) * (0.5 + 0.5 * f64::from(dice.next()))
}

/// Syllables whose pitch the octave check has to argue over, each its
/// own: the fundamental and the odd harmonics turned down by chance, and
/// a second voice in unison, a fifth or an octave above.
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
        let hiss = roll(&mut dice, 0.0, 0.1) as f32;
        let (mut low, mut high) = (0.0f64, 0.0f64);
        for n in 0..length {
            low += TAU * f0 / 48_000.0;
            high += TAU * f0 * above / 48_000.0;
            let envelope = (PI * n as f64 / length as f64).sin();
            let voiced: f64 = (1..=10)
                .map(|h| {
                    let weight = match h {
                        1 => fundamental,
                        _ if h % 2 == 1 => odd,
                        _ => 1.0,
                    };
                    let h = h as f64;
                    weight * ((low * h).sin() + 0.5 * (high * h).sin()) / h
                })
                .sum();
            take.push((0.2 * envelope * voiced) as f32 + hiss * dice.next());
        }
    }
    take.truncate(frames);
    take
}

#[test]
fn a_pitch_in_doubt_comes_out_as_the_c_makes_it() {
    holds(&octave_doubts(8 * 48_000, 29), 1);
}

#[test]
fn a_noisy_voice_comes_out_as_the_c_makes_it() {
    // Three seconds and a ragged end: the last frame is padded.
    holds(&voice(3 * 48_000 + 123, 1, 0.05), 1);
}

#[test]
fn noise_alone_comes_out_as_the_c_makes_it() {
    let mut hiss = Noise(7);
    let take: Vec<f32> = (0..2 * 48_000).map(|_| 0.2 * hiss.next()).collect();
    holds(&take, 1);
}

#[test]
fn each_channel_of_a_stereo_take_comes_out_as_the_c_makes_it() {
    let left = voice(48_000 + 480 * 7 + 1, 3, 0.02);
    let mut hiss = Noise(11);
    let take: Vec<f32> = left.iter().flat_map(|&l| [l, 0.1 * hiss.next()]).collect();
    holds(&take, 2);
}

#[test]
fn silence_between_sounds_comes_out_as_the_c_makes_it() {
    // Digital silence and a whisper of noise: the frames with no audio
    // leave the cepstra alone, then the voice comes in on what they left.
    let mut hiss = Noise(5);
    let mut take = vec![0.0f32; 48_000 / 2];
    take.extend((0..48_000 / 2).map(|_| 1e-7 * hiss.next()));
    take.extend(voice(48_000, 9, 0.01));
    take.extend(vec![0.0f32; 4_800]);
    take.extend(voice(48_000 / 2, 13, 0.03));
    holds(&take, 1);
}

#[test]
fn a_clipped_take_comes_out_as_the_c_makes_it() {
    // Loud enough that the network's sums run off the tanh table's ends.
    let take: Vec<f32> = voice(48_000, 17, 0.3).iter().map(|v| (v * 8.0).clamp(-1.0, 1.0)).collect();
    holds(&take, 1);
}

#[test]
fn a_take_shorter_than_a_frame_comes_out_as_the_c_makes_it() {
    holds(&voice(100, 19, 0.1), 1);
}

#[test]
fn both_refuse_the_same_takes_and_leave_them_untouched() {
    let take = voice(4_800, 23, 0.1);
    for (channels, rate) in [(1, 44_100), (1, 16_000), (0, 48_000), (-1, 48_000)] {
        let (c_ok, c_out) = ask(c(), &take, channels, rate);
        let (ok, out) = ask(qa_audio_denoise_f32, &take, channels, rate);
        assert_eq!((ok, c_ok), (0, 0), "{channels} channel(s) at {rate}");
        assert_eq!(out, take, "a refusal touches nothing");
        assert_eq!(c_out, take);
    }
    for denoise in [c(), qa_audio_denoise_f32] {
        // SAFETY: a null take and an empty one are the contract's refusals.
        unsafe {
            assert_eq!(denoise(std::ptr::null_mut(), 480, 1, 48_000), 0);
            let mut one = [0.5f32];
            assert_eq!(denoise(one.as_mut_ptr(), 0, 1, 48_000), 0);
            assert_eq!(one, [0.5]);
        }
    }
}
