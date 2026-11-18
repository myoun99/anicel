//! The one door the app bakes a span through: each filter's samples as its
//! kernel makes them, from rest and going on from a memory it leaves as
//! the kernel does; how many doubles a setting and a memory take; none on
//! a kind or geometry it cannot read.

use super::{Setting, Walk, qa_audio_filter, qa_audio_filter_latency, qa_audio_filter_memory, qa_audio_filter_values};
use crate::compressor::{COMPRESSOR_MEMORY, Compressor, compress, compress_on};
use crate::denoiser::{Denoiser, denoise, denoise_on, denoiser_latency, denoiser_memory};
use crate::equalizer::{MEMORY_VALUES, Equalizer, equalize, equalize_on};

const RATE: f64 = 48_000.0;
const EQUALIZER: i32 = 0;
const COMPRESSOR: i32 = 1;
const DENOISER: i32 = 2;

fn sound() -> Vec<f32> {
    (0..2 * 6_000).map(|i| ((i * 31) % 997) as f32 / 500.0 - 1.0).collect()
}

/// `samples`, two channels at `rate` from the span's sample `first`,
/// through the door's filter `kind` by `starts` and `values`.
fn door_at(rate: i32, kind: i32, samples: &[f32], first: i64, (starts, values): (&[i64], &[f64]), memory: *mut f64) -> (i32, Vec<f32>) {
    let mut out = vec![0.0_f32; samples.len()];
    // SAFETY: every pointer is to as many as it is said to hold.
    let ran = unsafe {
        qa_audio_filter(
            kind,
            samples.as_ptr(),
            (samples.len() / 2) as i64,
            2,
            rate,
            first,
            starts.as_ptr(),
            values.as_ptr(),
            starts.len() as i32,
            memory,
            out.as_mut_ptr(),
        )
    };
    (ran, out)
}

/// [`door_at`] 48 kHz.
fn door(kind: i32, samples: &[f32], first: i64, at: (&[i64], &[f64]), memory: *mut f64) -> (i32, Vec<f32>) {
    door_at(48_000, kind, samples, first, at, memory)
}

#[test]
fn a_setting_and_a_memory_take_what_each_filter_says() {
    let values = [EQUALIZER, COMPRESSOR, DENOISER].map(|kind| qa_audio_filter_values(kind));
    assert_eq!(values, [6, 5, 1]);
    assert_eq!(qa_audio_filter_memory(EQUALIZER, 2, 48_000), 2 * MEMORY_VALUES as i32);
    assert_eq!(qa_audio_filter_memory(COMPRESSOR, 2, 48_000), COMPRESSOR_MEMORY as i32, "one for every channel");
    for rate in [44_100, 48_000, 96_000] {
        let memory = qa_audio_filter_memory(DENOISER, 2, rate);
        assert_eq!(memory, denoiser_memory(2, rate) as i32, "{rate}: each channel's model and road");
    }
    assert!(denoiser_memory(2, 44_100) > denoiser_memory(2, 48_000), "the conversions hold more");
    let none = [qa_audio_filter_values(3), qa_audio_filter_memory(3, 2, 48_000), qa_audio_filter_memory(EQUALIZER, 0, 48_000)];
    assert_eq!(none, [0; 3]);
    assert_eq!(qa_audio_filter_memory(DENOISER, 2, 0), 0, "no rate");
}

#[test]
fn the_door_bakes_what_the_equalizer_does() {
    let sound = sound();
    let none = Equalizer { low_cut: 0.0, high_cut: 0.0, low_shelf: 250.0, low_db: 0.0, high_shelf: 4_000.0, high_db: 0.0 };
    let settings = [
        Setting { start: 0, value: Equalizer { low_cut: 120.0, high_db: 4.0, ..none } },
        Setting { start: 2_500, value: Equalizer { high_cut: 8_000.0, low_db: -6.0, ..none } },
    ];
    let starts: Vec<i64> = settings.iter().map(|s| s.start).collect();
    let values: Vec<f64> = settings
        .iter()
        .flat_map(|s| {
            let e = s.value;
            [e.low_cut, e.high_cut, e.low_shelf, e.low_db, e.high_shelf, e.high_db]
        })
        .collect();
    let at = (&starts[..], &values[..]);
    assert_eq!(door(EQUALIZER, &sound, 0, at, std::ptr::null_mut()), (1, equalize(&sound, 2, RATE, &settings)));

    // From a memory: the second half of the sound, going on from the first.
    let (head, tail) = sound.split_at(2 * 3_000);
    let mut kept = vec![0.0; 2 * MEMORY_VALUES];
    equalize_on(head, 2, RATE, &settings, 0, &mut kept, &mut vec![0.0; head.len()]);
    let mut by_rust = kept.clone();
    let mut expected = vec![0.0_f32; tail.len()];
    equalize_on(tail, 2, RATE, &settings, 3_000, &mut by_rust, &mut expected);
    let mut by_door = kept;
    assert_eq!(door(EQUALIZER, tail, 3_000, at, by_door.as_mut_ptr()), (1, expected));
    assert_eq!(by_door, by_rust);
}

#[test]
fn the_door_bakes_what_the_compressor_does() {
    let sound = sound();
    let some = Compressor { threshold_db: -12.0, ratio: 4.0, attack_ms: 2.0, release_ms: 60.0, makeup_db: 2.0 };
    let settings = [
        Setting { start: 0, value: some },
        Setting { start: 2_500, value: Compressor { ratio: 8.0, threshold_db: -20.0, ..some } },
    ];
    let starts: Vec<i64> = settings.iter().map(|s| s.start).collect();
    let values: Vec<f64> = settings
        .iter()
        .flat_map(|s| {
            let c = s.value;
            [c.threshold_db, c.ratio, c.attack_ms, c.release_ms, c.makeup_db]
        })
        .collect();
    let at = (&starts[..], &values[..]);
    assert_eq!(door(COMPRESSOR, &sound, 0, at, std::ptr::null_mut()), (1, compress(&sound, 2, RATE, &settings)));

    let (head, tail) = sound.split_at(2 * 3_000);
    let mut kept = [0.0; COMPRESSOR_MEMORY];
    compress_on(head, 2, RATE, &settings, 0, &mut kept, &mut vec![0.0; head.len()]);
    assert_ne!(kept, [0.0], "the head left a turning to go on from");
    let mut by_rust = kept;
    let mut expected = vec![0.0_f32; tail.len()];
    compress_on(tail, 2, RATE, &settings, 3_000, &mut by_rust, &mut expected);
    let mut by_door = kept;
    assert_eq!(door(COMPRESSOR, tail, 3_000, at, by_door.as_mut_ptr()), (1, expected));
    assert_eq!(by_door, by_rust);
}


#[test]
fn the_door_bakes_what_the_noise_removal_does_at_every_rate() {
    let sound = sound();
    let settings = [Setting { start: 0, value: Denoiser { amount: 1.0 } }, Setting { start: 2_500, value: Denoiser { amount: 0.4 } }];
    let starts: Vec<i64> = settings.iter().map(|s| s.start).collect();
    let values: Vec<f64> = settings.iter().map(|s| s.value.amount).collect();
    let at = (&starts[..], &values[..]);
    for rate in [44_100, 48_000, 96_000] {
        let whole = door_at(rate, DENOISER, &sound, 0, at, std::ptr::null_mut());
        assert_eq!(whole, (1, denoise(&sound, 2, rate, &settings)), "{rate}");

        let (head, tail) = sound.split_at(2 * 3_000);
        let mut kept = vec![0.0; denoiser_memory(2, rate)];
        assert!(denoise_on(head, 2, rate, &settings, 0, &mut kept, &mut vec![0.0; head.len()]));
        let mut by_rust = kept.clone();
        let mut expected = vec![0.0_f32; tail.len()];
        assert!(denoise_on(tail, 2, rate, &settings, 3_000, &mut by_rust, &mut expected));
        let mut by_door = kept;
        assert_eq!(door_at(rate, DENOISER, tail, 3_000, at, by_door.as_mut_ptr()), (1, expected), "{rate}");
        assert_eq!(by_door, by_rust, "{rate}");
    }
}

// What a bake reads past its span and drops: the noise removal's two
// frames at RNNoise's rate and its road's reach at another, none for the
// filters that are not late or where there is no rate.
#[test]
fn the_door_says_how_late_each_filter_comes_out() {
    let late = [EQUALIZER, COMPRESSOR, DENOISER, 3].map(|kind| qa_audio_filter_latency(kind, 48_000));
    assert_eq!(late, [0, 0, 960, 0]);
    assert_eq!(qa_audio_filter_latency(DENOISER, 44_100), denoiser_latency(44_100) as i32);
    assert_eq!(qa_audio_filter_latency(DENOISER, 96_000), denoiser_latency(96_000) as i32);
    assert_eq!(qa_audio_filter_latency(DENOISER, 0), 0, "no rate");
    assert_eq!(qa_audio_filter_latency(EQUALIZER, 96_000), 0);
}

#[test]
fn the_door_refuses_what_it_cannot_read() {
    let sound = sound();
    let (starts, values) = ([0_i64], [0.0; 6]);
    let mut out = vec![0.0_f32; sound.len()];
    // SAFETY: null pointers, bad counts and an unknown kind are what it refuses.
    let refused = unsafe {
        let (s, o, m) = (sound.as_ptr(), out.as_mut_ptr(), std::ptr::null_mut());
        let (t, v) = (starts.as_ptr(), values.as_ptr());
        [
            qa_audio_filter(3, s, 6_000, 2, 48_000, 0, t, v, 1, m, o),
            qa_audio_filter(-1, s, 6_000, 2, 48_000, 0, t, v, 1, m, o),
            qa_audio_filter(EQUALIZER, std::ptr::null(), 6_000, 2, 48_000, 0, t, v, 1, m, o),
            qa_audio_filter(EQUALIZER, s, 6_000, 0, 48_000, 0, t, v, 1, m, o),
            qa_audio_filter(EQUALIZER, s, 6_000, 2, 0, 0, t, v, 1, m, o),
            qa_audio_filter(EQUALIZER, s, -1, 2, 48_000, 0, t, v, 1, m, o),
            qa_audio_filter(COMPRESSOR, s, 6_000, 2, 48_000, 0, std::ptr::null(), v, 1, m, o),
            qa_audio_filter(COMPRESSOR, s, 6_000, 2, 48_000, 0, t, v, 1, m, std::ptr::null_mut()),
        ]
    };
    assert_eq!(refused, [0; 8]);
    assert!(out.iter().all(|&s| s == 0.0), "out untouched");
    // No setting: the samples as they were, through either filter.
    for kind in [EQUALIZER, COMPRESSOR] {
        let none = door(kind, &sound, 0, (&[], &[]), std::ptr::null_mut());
        assert_eq!(none, (1, sound.clone()), "kind {kind}");
    }
}

#[test]
fn the_walk_takes_the_last_setting_started_by_each_sample() {
    let settings = [
        Setting { start: 0, value: 'a' },
        Setting { start: 3, value: 'b' },
        Setting { start: 3, value: 'c' },
        Setting { start: 7, value: 'd' },
    ];
    let mut walk = Walk::new(&settings);
    let taken: Vec<Option<char>> = (2..10).map(|at| walk.taking_over(at).copied()).collect();
    assert_eq!(taken, [Some('a'), Some('c'), None, None, None, Some('d'), None, None]);
}
