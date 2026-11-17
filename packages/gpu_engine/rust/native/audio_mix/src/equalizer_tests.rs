//! The equalizer against what the cookbook's filters are: the gain each
//! leaves at the frequencies its formula fixes — steady DC, Nyquist's
//! alternating sign, a sine at a cut's corner — and its samples pinned in
//! the ledger, so another device bakes the same bits.

use super::{EQUALIZER_VALUES, Equalizer, MEMORY_VALUES, Setting, equalize, equalize_on, qa_audio_equalize};

const RATE: f64 = 48_000.0;

/// Every section left out.
const NONE: Equalizer = Equalizer {
    low_cut: 0.0,
    high_cut: 0.0,
    low_shelf: 250.0,
    low_db: 0.0,
    high_shelf: 4_000.0,
    high_db: 0.0,
};

fn from_the_start(equalizer: Equalizer) -> [Setting; 1] {
    [Setting { start: 0, equalizer }]
}

/// One channel of `count` samples of `at(i)`.
fn mono(count: usize, at: impl Fn(usize) -> f64) -> Vec<f32> {
    (0..count).map(|i| at(i) as f32).collect()
}

/// The root mean square of `samples`' last `tail`.
fn rms_of_the_last(samples: &[f32], tail: usize) -> f64 {
    let last = &samples[samples.len() - tail..];
    (last.iter().map(|&s| f64::from(s) * f64::from(s)).sum::<f64>() / tail as f64).sqrt()
}

/// A second of `level` held — DC — or flipped every sample — Nyquist.
fn held(level: f64) -> Vec<f32> {
    mono(48_000, |_| level)
}

fn flipped(level: f64) -> Vec<f32> {
    mono(48_000, |i| if i % 2 == 0 { level } else { -level })
}

#[test]
fn an_equalizer_of_no_section_hands_its_samples_back_as_they_were() {
    let sound: Vec<f32> = (0..4_096).map(|i| ((i * 7_919) % 2_001) as f32 / 1_000.0 - 1.0).collect();
    let none = from_the_start(NONE);
    assert_eq!(equalize(&sound, 2, RATE, &none), sound);
    assert_eq!(equalize(&sound, 2, RATE, &[]), sound, "before any setting, none");
    // A cut at or past half the rate is no frequency of it.
    let past = from_the_start(Equalizer { high_cut: RATE / 2.0, low_cut: -5.0, ..NONE });
    assert_eq!(equalize(&sound, 2, RATE, &past), sound);
}

#[test]
fn a_low_cut_takes_the_held_level_away_and_leaves_nyquist() {
    let cut = from_the_start(Equalizer { low_cut: 80.0, ..NONE });
    assert!(rms_of_the_last(&equalize(&held(0.5), 1, RATE, &cut), 4_800) < 1e-9);
    let nyquist = rms_of_the_last(&equalize(&flipped(0.5), 1, RATE, &cut), 4_800);
    assert!((nyquist - 0.5).abs() < 1e-6, "{nyquist}");
}

#[test]
fn a_high_cut_leaves_the_held_level_and_takes_nyquist_away() {
    let cut = from_the_start(Equalizer { high_cut: 12_000.0, ..NONE });
    let dc = rms_of_the_last(&equalize(&held(0.5), 1, RATE, &cut), 4_800);
    assert!((dc - 0.5).abs() < 1e-6, "{dc}");
    assert!(rms_of_the_last(&equalize(&flipped(0.5), 1, RATE, &cut), 4_800) < 1e-6);
}

// Butterworth's corner: 3 dB down, an amplitude of √½. A 1 kHz sine at
// 48 kHz repeats every 48 samples, so 4,800 of them are whole periods.
#[test]
fn a_cut_leaves_a_sine_at_its_corner_three_decibels_down() {
    let sine = mono(48_000, |i| (2.0 * std::f64::consts::PI * 1_000.0 * i as f64 / RATE).sin());
    let half_power = std::f64::consts::FRAC_1_SQRT_2 * std::f64::consts::FRAC_1_SQRT_2;
    for equalizer in [Equalizer { low_cut: 1_000.0, ..NONE }, Equalizer { high_cut: 1_000.0, ..NONE }] {
        let rms = rms_of_the_last(&equalize(&sine, 1, RATE, &from_the_start(equalizer)), 4_800);
        assert!((rms - half_power).abs() < 1e-4, "{equalizer:?}: {rms}");
    }
}

// A low shelf's gain at DC is 10^(dB/20) and 1 at Nyquist; a high shelf's
// the other way about.
#[test]
fn a_shelf_raises_or_lowers_its_side_by_its_decibels() {
    for db in [6.0, -12.0] {
        let gain = 10_f64.powf(db / 20.0);
        let low = from_the_start(Equalizer { low_db: db, ..NONE });
        let high = from_the_start(Equalizer { high_db: db, ..NONE });
        for (setting, dc, nyquist) in [(low, gain, 1.0), (high, 1.0, gain)] {
            let at_dc = rms_of_the_last(&equalize(&held(0.25), 1, RATE, &setting), 4_800);
            let at_nyquist = rms_of_the_last(&equalize(&flipped(0.25), 1, RATE, &setting), 4_800);
            assert!((at_dc - 0.25 * dc).abs() < 1e-5, "{db} dB at DC: {at_dc}");
            assert!((at_nyquist - 0.25 * nyquist).abs() < 1e-5, "{db} dB at Nyquist: {at_nyquist}");
        }
    }
}

// The channels of a frame are filtered apart: a held level on one and
// silence on the other leave the other silent.
#[test]
fn each_channel_keeps_its_own_memory() {
    let stereo: Vec<f32> = (0..9_600).map(|i| if i % 2 == 0 { 0.5 } else { 0.0 }).collect();
    let shelf = from_the_start(Equalizer { low_db: 6.0, low_cut: 20.0, ..NONE });
    let out = equalize(&stereo, 2, RATE, &shelf);
    assert!(out.iter().skip(1).step_by(2).all(|&s| s == 0.0));
    assert!(out.iter().step_by(2).any(|&s| s != 0.5));
}

// Settings change where their start says: before it the samples pass as
// they were, and from it on the filter runs on what it remembered.
#[test]
fn a_setting_takes_over_at_its_start() {
    let sound = flipped(0.5);
    let settings = [
        Setting { start: 0, equalizer: NONE },
        Setting { start: 1_000, equalizer: Equalizer { high_cut: 1_000.0, ..NONE } },
    ];
    let out = equalize(&sound, 1, RATE, &settings);
    assert_eq!(out[..1_000], sound[..1_000]);
    assert_ne!(out[1_000..1_010], sound[1_000..1_010]);
    assert!(rms_of_the_last(&out, 4_800) < 1e-6);
}

/// Two channels of a made-up sound — a well-mixed u32 (lowbias32) to
/// [-1, 1) — through settings that change three times, every section in
/// play; its bytes as the ledger holds them.
#[test]
fn a_made_up_sound_is_baked_as_pinned() {
    let mixed = |mut x: u32| {
        x ^= x >> 16;
        x = x.wrapping_mul(0x7feb_352d);
        x ^= x >> 15;
        x = x.wrapping_mul(0x846c_a68b);
        x ^ (x >> 16)
    };
    let sound: Vec<f32> =
        (0..2 * 20_000).map(|i| (f64::from(mixed(i)) / 2_147_483_648.0 - 1.0) as f32).collect();
    let every = Equalizer {
        low_cut: 80.0,
        high_cut: 12_000.0,
        low_shelf: 250.0,
        low_db: -2.0,
        high_shelf: 4_000.0,
        high_db: 3.0,
    };
    let settings = [
        Setting { start: 0, equalizer: every },
        Setting { start: 4_800, equalizer: Equalizer { low_db: 6.0, high_cut: 6_000.0, ..every } },
        Setting { start: 9_600, equalizer: NONE },
        Setting { start: 14_400, equalizer: Equalizer { low_cut: 300.0, high_db: -9.0, ..every } },
    ];
    for rate in [44_100.0, 48_000.0, 96_000.0] {
        let baked = equalize(&sound, 2, rate, &settings);
        let bytes: Vec<u8> = baked.iter().flat_map(|s| s.to_le_bytes()).collect();
        ledger::assert_pinned(&format!("audio_mix/equalizer-at-{}", rate as u32), &bytes);
    }
}

// A span baked a stretch at a time, each stretch going on from the memory
// the one before left, is the span baked at once — wherever the stretches
// break, a setting's start among them.
#[test]
fn a_span_baked_a_stretch_at_a_time_is_the_span_baked_at_once() {
    let sound: Vec<f32> = (0..2 * 20_000).map(|i| ((i * 7_919) % 2_001) as f32 / 1_000.0 - 1.0).collect();
    let settings = [
        Setting { start: 0, equalizer: Equalizer { low_cut: 80.0, high_db: 3.0, ..NONE } },
        Setting { start: 7_000, equalizer: Equalizer { high_cut: 6_000.0, low_db: 6.0, ..NONE } },
        Setting { start: 13_000, equalizer: NONE },
        Setting { start: 13_001, equalizer: Equalizer { low_cut: 300.0, high_db: -9.0, ..NONE } },
    ];
    let whole = equalize(&sound, 2, RATE, &settings);
    for breaks in [vec![0, 20_000], vec![0, 1, 6_999, 7_000, 13_000, 13_001, 20_000], vec![0, 9_999, 19_999, 20_000]] {
        let mut memory = vec![0.0; 2 * MEMORY_VALUES];
        let mut stretched = vec![0.0_f32; sound.len()];
        for pair in breaks.windows(2) {
            let (from, to) = (2 * pair[0], 2 * pair[1]);
            equalize_on(&sound[from..to], 2, RATE, &settings, pair[0] as i64, &mut memory, &mut stretched[from..to]);
        }
        assert_eq!(stretched, whole, "broken at {breaks:?}");
    }
}

// The door the app calls: the same samples as [`equalize`] from rest, and
// as [`equalize_on`] going on from a memory, which it leaves as that does;
// none on geometry it cannot read.
#[test]
fn the_c_door_bakes_what_equalize_does() {
    let sound: Vec<f32> = (0..2 * 6_000).map(|i| ((i * 31) % 997) as f32 / 500.0 - 1.0).collect();
    let settings = [
        Setting { start: 0, equalizer: Equalizer { low_cut: 120.0, high_db: 4.0, ..NONE } },
        Setting { start: 2_500, equalizer: Equalizer { high_cut: 8_000.0, low_db: -6.0, ..NONE } },
    ];
    let starts: Vec<i64> = settings.iter().map(|s| s.start).collect();
    let values: Vec<f64> = settings
        .iter()
        .flat_map(|s| {
            let e = s.equalizer;
            [e.low_cut, e.high_cut, e.low_shelf, e.low_db, e.high_shelf, e.high_db]
        })
        .collect();
    assert_eq!(values.len(), settings.len() * EQUALIZER_VALUES);
    let door = |samples: &[f32], first: i64, memory: *mut f64, out: &mut [f32]| {
        // SAFETY: every pointer is to as many as it is said to hold.
        unsafe {
            qa_audio_equalize(
                samples.as_ptr(),
                (samples.len() / 2) as i64,
                2,
                48_000,
                first,
                starts.as_ptr(),
                values.as_ptr(),
                2,
                memory,
                out.as_mut_ptr(),
            )
        }
    };
    let mut out = vec![0.0_f32; sound.len()];
    assert_eq!(door(&sound, 0, std::ptr::null_mut(), &mut out), 1);
    assert_eq!(out, equalize(&sound, 2, RATE, &settings));

    // From a memory: the second half of the sound, going on from the first.
    let (head, tail) = sound.split_at(2 * 3_000);
    let mut kept = vec![0.0; 2 * MEMORY_VALUES];
    equalize_on(head, 2, RATE, &settings, 0, &mut kept, &mut vec![0.0; head.len()]);
    let mut by_rust = kept.clone();
    let mut expected = vec![0.0_f32; tail.len()];
    equalize_on(tail, 2, RATE, &settings, 3_000, &mut by_rust, &mut expected);
    let mut by_door = kept.clone();
    let mut through = vec![0.0_f32; tail.len()];
    assert_eq!(door(tail, 3_000, by_door.as_mut_ptr(), &mut through), 1);
    assert_eq!((through, by_door), (expected, by_rust));

    // SAFETY: null pointers and bad counts are what it refuses.
    let refused = unsafe {
        let s = sound.as_ptr();
        let o = out.as_mut_ptr();
        let m = std::ptr::null_mut();
        [
            qa_audio_equalize(std::ptr::null(), 6_000, 2, 48_000, 0, starts.as_ptr(), values.as_ptr(), 2, m, o),
            qa_audio_equalize(s, 6_000, 0, 48_000, 0, starts.as_ptr(), values.as_ptr(), 2, m, o),
            qa_audio_equalize(s, 6_000, 2, 0, 0, starts.as_ptr(), values.as_ptr(), 2, m, o),
            qa_audio_equalize(s, -1, 2, 48_000, 0, starts.as_ptr(), values.as_ptr(), 2, m, o),
            qa_audio_equalize(s, 6_000, 2, 48_000, 0, std::ptr::null(), values.as_ptr(), 2, m, o),
        ]
    };
    assert_eq!(refused, [0; 5]);
    // No setting: the samples as they were.
    let mut plain = vec![0.0_f32; sound.len()];
    // SAFETY: as above, with no settings to read.
    let none = unsafe {
        qa_audio_equalize(
            sound.as_ptr(),
            6_000,
            2,
            48_000,
            0,
            std::ptr::null(),
            std::ptr::null(),
            0,
            std::ptr::null_mut(),
            plain.as_mut_ptr(),
        )
    };
    assert_eq!((none, plain), (1, sound));
}
