//! The compressor against what its knobs say: a level over the threshold
//! settles where the ratio puts it, the turning reaches two thirds of a
//! rise in its attack and lets go of two thirds in its release, the
//! channels are turned down alike — and its samples pinned in the ledger,
//! so another device bakes the same bits.

use super::{COMPRESSOR_MEMORY, Compressor, compress, compress_on};
use crate::filter::Setting;

const RATE: f64 = 48_000.0;

/// Turns nothing down: a ratio of 1, no makeup.
const NONE: Compressor = Compressor { threshold_db: -20.0, ratio: 1.0, attack_ms: 10.0, release_ms: 100.0, makeup_db: 0.0 };

fn from_the_start(compressor: Compressor) -> [Setting<Compressor>; 1] {
    [Setting { start: 0, value: compressor }]
}

/// One channel of `count` samples of `at(i)`.
fn mono(count: usize, at: impl Fn(usize) -> f64) -> Vec<f32> {
    (0..count).map(|i| at(i) as f32).collect()
}

/// The dB a sample `input` came out turned down by, as `output`.
fn turned_down(input: f32, output: f32) -> f64 {
    -20.0 * (f64::from(output) / f64::from(input)).log10()
}

#[test]
fn a_compressor_that_turns_nothing_down_hands_its_samples_back_as_they_were() {
    let sound: Vec<f32> = (0..4_096).map(|i| ((i * 7_919) % 2_001) as f32 / 1_000.0 - 1.0).collect();
    assert_eq!(compress(&sound, 2, RATE, &from_the_start(NONE)), sound);
    assert_eq!(compress(&sound, 2, RATE, &[]), sound, "before any setting, none");
}

#[test]
fn a_level_under_the_threshold_passes_as_it_was() {
    let quiet = mono(9_600, |_| 0.05);
    let compressor = Compressor { ratio: 4.0, ..NONE };
    assert_eq!(compress(&quiet, 1, RATE, &from_the_start(compressor)), quiet, "-26 dB under -20");
}

// 0.5 is -6.02 dB, 13.98 over a threshold of -20: a ratio of 4 lets a
// quarter of that out and turns the rest — 10.49 dB — down.
#[test]
fn a_held_level_over_the_threshold_settles_where_the_ratio_puts_it() {
    let loud = mono(48_000, |_| 0.5);
    for ratio in [2.0, 4.0, 20.0] {
        let compressor = Compressor { ratio, attack_ms: 1.0, ..NONE };
        let out = compress(&loud, 1, RATE, &from_the_start(compressor));
        let over = 20.0 * 0.5_f64.log10() + 20.0;
        let expected = over * (1.0 - 1.0 / ratio);
        let turned = turned_down(0.5, *out.last().unwrap());
        assert!((turned - expected).abs() < 1e-5, "ratio {ratio}: {turned} dB, not {expected}");
    }
}

#[test]
fn the_makeup_raises_everything_by_its_decibels() {
    let sound = mono(4_800, |i| ((i * 31) % 997) as f64 / 2_000.0 - 0.25);
    let out = compress(&sound, 1, RATE, &from_the_start(Compressor { makeup_db: 6.0, ..NONE }));
    let gain = 10_f64.powf(6.0 / 20.0);
    for (&before, &after) in sound.iter().zip(&out) {
        assert!((f64::from(after) - f64::from(before) * gain).abs() < 1e-6, "{before} came out {after}");
    }
}

// The turning follows a rise by e^(-1/t) a sample, t the attack in
// samples: one attack on, it has gone 1 - 1/e of the way.
#[test]
fn the_attack_reaches_two_thirds_of_a_rise_in_its_time() {
    let attack_ms = 10.0;
    let step = 4_800;
    let sound = mono(step + 9_600, |i| if i < step { 0.0 } else { 1.0 });
    let compressor = Compressor { ratio: 20.0, attack_ms, ..NONE };
    let out = compress(&sound, 1, RATE, &from_the_start(compressor));
    let wanted = 20.0 * (1.0 - 1.0 / 20.0);
    let one_attack = (attack_ms * RATE / 1_000.0) as usize;
    let turned = turned_down(1.0, out[step + one_attack - 1]);
    let expected = wanted * (1.0 - (-1.0_f64).exp());
    assert!((turned - expected).abs() < 1e-4, "{turned} dB, not {expected}");
    assert!(turned_down(1.0, out[step]) < turned, "it rises over the attack, not at once");
}

// Settled 15 dB down, the sound drops under the threshold: one release
// on, the turning has let go of 1 - 1/e of what it held.
#[test]
fn the_release_lets_go_of_two_thirds_in_its_time() {
    let release_ms = 50.0;
    let drop = 48_000;
    let sound = mono(drop + 9_600, |i| if i < drop { 1.0 } else { 0.01 });
    let compressor = Compressor { ratio: 4.0, attack_ms: 1.0, release_ms, ..NONE };
    let out = compress(&sound, 1, RATE, &from_the_start(compressor));
    let held = turned_down(1.0, out[drop - 1]);
    let one_release = (release_ms * RATE / 1_000.0) as usize;
    let turned = turned_down(0.01, out[drop + one_release - 1]);
    let expected = held * (-1.0_f64).exp();
    assert!((held - 15.0).abs() < 1e-5, "settled at {held} dB");
    assert!((turned - expected).abs() < 1e-4, "{turned} dB, not {expected}");
}

// The detector hears the louder channel and turns both down by one gain,
// so the quieter is turned down too and the image stays.
#[test]
fn the_channels_are_turned_down_alike() {
    let stereo: Vec<f32> = (0..2 * 9_600).map(|i| if i % 2 == 0 { 0.8 } else { 0.1 }).collect();
    let out = compress(&stereo, 2, RATE, &from_the_start(Compressor { ratio: 4.0, attack_ms: 1.0, ..NONE }));
    let (left, right) = (out[out.len() - 2], out[out.len() - 1]);
    let (on_left, on_right) = (turned_down(0.8, left), turned_down(0.1, right));
    assert!(on_left > 1.0, "the loud one is over the threshold: {on_left} dB");
    assert!((on_left - on_right).abs() < 1e-5, "{on_left} dB and {on_right} dB");
}

// Before its start a setting turns nothing, and from it on the turning
// goes on from where it stood.
#[test]
fn a_setting_takes_over_at_its_start() {
    let sound = mono(9_600, |_| 0.5);
    let settings = [Setting { start: 1_000, value: Compressor { ratio: 4.0, attack_ms: 1.0, ..NONE } }];
    let out = compress(&sound, 1, RATE, &settings);
    assert_eq!(out[..1_000], sound[..1_000]);
    assert!(out[1_000] < sound[1_000]);
}

/// Two channels of a made-up sound — a well-mixed u32 (lowbias32) to
/// [-1, 1), swelling and falling every 2,000 frames so the turning moves —
/// through settings that change three times; its bytes as the ledger
/// holds them.
#[test]
fn a_made_up_sound_is_baked_as_pinned() {
    let mixed = |mut x: u32| {
        x ^= x >> 16;
        x = x.wrapping_mul(0x7feb_352d);
        x ^= x >> 15;
        x = x.wrapping_mul(0x846c_a68b);
        x ^ (x >> 16)
    };
    let sound: Vec<f32> = (0..2 * 20_000)
        .map(|i| {
            let swell = 0.1 + 0.9 * f64::from((i / 2) % 2_000) / 2_000.0;
            (swell * (f64::from(mixed(i)) / 2_147_483_648.0 - 1.0)) as f32
        })
        .collect();
    let some = Compressor { threshold_db: -18.0, ratio: 4.0, attack_ms: 5.0, release_ms: 80.0, makeup_db: 3.0 };
    let settings = [
        Setting { start: 0, value: some },
        Setting { start: 4_800, value: Compressor { ratio: 10.0, attack_ms: 0.0, ..some } },
        Setting { start: 9_600, value: NONE },
        Setting { start: 14_400, value: Compressor { threshold_db: -30.0, release_ms: 400.0, ..some } },
    ];
    for rate in [44_100.0, 48_000.0, 96_000.0] {
        let baked = compress(&sound, 2, rate, &settings);
        let bytes: Vec<u8> = baked.iter().flat_map(|s| s.to_le_bytes()).collect();
        ledger::assert_pinned(&format!("audio_mix/compressor-at-{}", rate as u32), &bytes);
    }
}

// A span baked a stretch at a time, each stretch going on from the turning
// the one before left, is the span baked at once — wherever the stretches
// break, a setting's start among them.
#[test]
fn a_span_baked_a_stretch_at_a_time_is_the_span_baked_at_once() {
    let sound: Vec<f32> = (0..2 * 20_000).map(|i| ((i * 7_919) % 2_001) as f32 / 1_000.0 - 1.0).collect();
    let settings = [
        Setting { start: 0, value: Compressor { ratio: 4.0, attack_ms: 3.0, ..NONE } },
        Setting { start: 7_000, value: Compressor { threshold_db: -30.0, ratio: 8.0, ..NONE } },
        Setting { start: 13_000, value: NONE },
        Setting { start: 13_001, value: Compressor { ratio: 2.0, makeup_db: 4.0, ..NONE } },
    ];
    let whole = compress(&sound, 2, RATE, &settings);
    for breaks in [vec![0, 20_000], vec![0, 1, 6_999, 7_000, 13_000, 13_001, 20_000], vec![0, 9_999, 19_999, 20_000]] {
        let mut memory = [0.0; COMPRESSOR_MEMORY];
        let mut stretched = vec![0.0_f32; sound.len()];
        for pair in breaks.windows(2) {
            let (from, to) = (2 * pair[0], 2 * pair[1]);
            compress_on(&sound[from..to], 2, RATE, &settings, pair[0] as i64, &mut memory, &mut stretched[from..to]);
        }
        assert_eq!(stretched, whole, "broken at {breaks:?}");
    }
}

// The door takes any double: a ratio under one is none, as one is, never
// a compressor that raises what rises over its threshold.
#[test]
fn a_ratio_under_one_turns_nothing_down() {
    let loud = mono(4_800, |_| 0.5);
    for ratio in [0.0, 0.5] {
        assert_eq!(compress(&loud, 1, RATE, &from_the_start(Compressor { ratio, ..NONE })), loud, "ratio {ratio}");
    }
}
