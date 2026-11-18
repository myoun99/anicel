//! The one door the app bakes a span through: each filter's samples as its
//! kernel makes them, from rest and going on from a memory it leaves as
//! the kernel does; how many doubles a setting and a memory take; none on
//! a kind or geometry it cannot read.

use super::{Setting, Walk, qa_audio_filter, qa_audio_filter_memory, qa_audio_filter_values};
use crate::compressor::{COMPRESSOR_MEMORY, Compressor, compress, compress_on};
use crate::equalizer::{MEMORY_VALUES, Equalizer, equalize, equalize_on};

const RATE: f64 = 48_000.0;
const EQUALIZER: i32 = 0;
const COMPRESSOR: i32 = 1;

fn sound() -> Vec<f32> {
    (0..2 * 6_000).map(|i| ((i * 31) % 997) as f32 / 500.0 - 1.0).collect()
}

/// `samples`, two channels at 48 kHz from the span's sample `first`,
/// through the door's filter `kind` by `starts` and `values`.
fn door(kind: i32, samples: &[f32], first: i64, (starts, values): (&[i64], &[f64]), memory: *mut f64) -> (i32, Vec<f32>) {
    let mut out = vec![0.0_f32; samples.len()];
    // SAFETY: every pointer is to as many as it is said to hold.
    let ran = unsafe {
        qa_audio_filter(
            kind,
            samples.as_ptr(),
            (samples.len() / 2) as i64,
            2,
            48_000,
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

#[test]
fn a_setting_and_a_memory_take_what_each_filter_says() {
    assert_eq!([qa_audio_filter_values(EQUALIZER), qa_audio_filter_values(COMPRESSOR)], [6, 5]);
    assert_eq!(qa_audio_filter_memory(EQUALIZER, 2), 2 * MEMORY_VALUES as i32);
    assert_eq!(qa_audio_filter_memory(COMPRESSOR, 2), COMPRESSOR_MEMORY as i32, "one for every channel");
    assert_eq!([qa_audio_filter_values(2), qa_audio_filter_memory(2, 2), qa_audio_filter_memory(EQUALIZER, 0)], [0; 3]);
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
fn the_door_refuses_what_it_cannot_read() {
    let sound = sound();
    let (starts, values) = ([0_i64], [0.0; 6]);
    let mut out = vec![0.0_f32; sound.len()];
    // SAFETY: null pointers, bad counts and an unknown kind are what it refuses.
    let refused = unsafe {
        let (s, o, m) = (sound.as_ptr(), out.as_mut_ptr(), std::ptr::null_mut());
        let (t, v) = (starts.as_ptr(), values.as_ptr());
        [
            qa_audio_filter(2, s, 6_000, 2, 48_000, 0, t, v, 1, m, o),
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
