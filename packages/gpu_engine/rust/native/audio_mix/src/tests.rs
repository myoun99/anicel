//! The mix bus and the conversions against the engine's C (native/oracle),
//! bit for bit: both asked through their exports, on schedules and sounds
//! made up here.

use std::ptr;

use crate::bus::{
    Clip, EnvelopeKey, Source, qa_audio_bus_to_float, qa_audio_bus_to_int16, qa_audio_clip_sizeof,
    qa_audio_envelope_key_sizeof, qa_audio_mix, qa_audio_source_sizeof,
};
use crate::resample::{
    Resampler, qa_audio_resample, qa_audio_resample_frames, qa_audio_resample_taps, qa_audio_resampler_close,
    qa_audio_resampler_end, qa_audio_resampler_held, qa_audio_resampler_open, qa_audio_resampler_pull,
    qa_audio_resampler_push, qa_audio_resampler_ready,
};

type Sizeof = extern "C" fn() -> i32;
type Mix =
    unsafe extern "C" fn(*const Clip, i32, *const Source, i32, *const EnvelopeKey, i32, i64, i32, i32, *mut f64);
type ToFloat = unsafe extern "C" fn(*const f64, i32, *mut f32);
type ToInt16 = unsafe extern "C" fn(*const f64, i32, *mut i16);
type Taps = extern "C" fn(i32, i32, f64, f64) -> i32;
type Frames = extern "C" fn(i64, i32, i32) -> i64;
type Resample = unsafe extern "C" fn(*const f32, i64, i32, i32, i32, f64, f64, *mut f32) -> i64;
type Open = extern "C" fn(i32, i32, i32, f64, f64) -> *mut Resampler;
type Push = unsafe extern "C" fn(*mut Resampler, *const f32, i64) -> i32;
type End = unsafe extern "C" fn(*mut Resampler);
type Count = unsafe extern "C" fn(*const Resampler) -> i64;
type Pull = unsafe extern "C" fn(*mut Resampler, *mut f32, i64) -> i64;
type Close = unsafe extern "C" fn(*mut Resampler);

fn c<F: Copy>(name: &str) -> F {
    // SAFETY: each type above is its export's C declaration in qa_engine.c.
    unsafe { oracle::export::<F>(name) }
}

/// The two ends of one export: the C's and the Rust's.
struct Both<F> {
    c: F,
    rust: F,
}

impl<F: Copy> Both<F> {
    fn of(name: &str, rust: F) -> Self {
        Both { c: c(name), rust }
    }
}

/// xorshift32.
struct Dice(u32);

impl Dice {
    fn next(&mut self) -> u32 {
        let mut x = self.0;
        x ^= x << 13;
        x ^= x >> 17;
        x ^= x << 5;
        self.0 = x;
        x
    }

    /// In [lo, hi).
    fn int(&mut self, lo: i64, hi: i64) -> i64 {
        lo + (self.next() as i64) % (hi - lo)
    }

    /// In [-1, 1).
    fn unit(&mut self) -> f64 {
        self.next() as f64 / u32::MAX as f64 * 2.0 - 1.0
    }

    fn one_in(&mut self, n: i64) -> bool {
        self.int(0, n) == 0
    }
}

fn same_bits(rust: &[f64], c: &[f64], what: &str) {
    let first = rust.iter().zip(c).position(|(a, b)| a.to_bits() != b.to_bits());
    if let Some(at) = first {
        panic!("{what}: value {at} — rust {} c {}", rust[at], c[at]);
    }
}

#[test]
fn the_structs_are_laid_out_as_the_c_lays_them() {
    for (name, rust) in [
        ("qa_audio_clip_sizeof", qa_audio_clip_sizeof as Sizeof),
        ("qa_audio_source_sizeof", qa_audio_source_sizeof),
        ("qa_audio_envelope_key_sizeof", qa_audio_envelope_key_sizeof),
    ] {
        let both = Both::of(name, rust);
        assert_eq!((both.rust)(), (both.c)(), "{name}");
    }
    assert_eq!((qa_audio_clip_sizeof(), qa_audio_source_sizeof(), qa_audio_envelope_key_sizeof()), (80, 32, 16));
}

/// A schedule made up from `dice`: the sources' samples, the sources, the
/// clips, the keys.
struct Schedule {
    _samples: Vec<Vec<f32>>,
    sources: Vec<Source>,
    clips: Vec<Clip>,
    keys: Vec<EnvelopeKey>,
}

impl Schedule {
    fn made(dice: &mut Dice) -> Schedule {
        let mut samples = Vec::new();
        let mut sources = Vec::new();
        for _ in 0..dice.int(1, 5) {
            let channels = dice.int(0, 7) as i32;
            let length = dice.int(-1, 2_000);
            let floats = (length.max(0) * i64::from(channels.max(0))) as usize;
            let held: Vec<f32> = (0..floats).map(|_| (1.5 * dice.unit()) as f32).collect();
            let gone = dice.one_in(6);
            sources.push(Source {
                source_start: dice.int(0, 500),
                length,
                channels,
                reserved: 0,
                samples: if gone { ptr::null() } else { held.as_ptr() },
            });
            samples.push(held);
        }
        let mut keys = Vec::new();
        let mut at = dice.int(-50, 50);
        for _ in 0..dice.int(0, 24) {
            keys.push(EnvelopeKey { sample: at, gain: 1.5 * dice.unit() + 1.0 });
            // Now and then a key on the one before, or behind it.
            at += dice.int(-20, 400);
        }
        let mut clips = Vec::new();
        for _ in 0..dice.int(0, 12) {
            let start_sample = dice.int(-300, 3_000);
            clips.push(Clip {
                gain: 2.5 * dice.unit().abs(),
                pan_left: dice.unit().abs(),
                pan_right: dice.unit().abs(),
                start_sample,
                end_sample: start_sample + dice.int(-10, 3_000),
                source_offset: dice.int(-200, 1_500),
                fade_in_samples: if dice.one_in(2) { 0 } else { dice.int(-5, 1_500) },
                fade_out_samples: if dice.one_in(2) { 0 } else { dice.int(-5, 1_500) },
                source_index: dice.int(-1, sources.len() as i64 + 1) as i32,
                fade_curve: dice.int(0, 3) as i32,
                envelope_offset: dice.int(-2, keys.len() as i64 + 2) as i32,
                envelope_count: dice.int(-1, 8) as i32,
            });
        }
        Schedule { _samples: samples, sources, clips, keys }
    }
}

fn mixed(mix: Mix, schedule: &Schedule, start: i64, samples: i32, channels: i32) -> Vec<f64> {
    let mut out = vec![f64::NAN; (samples * channels) as usize];
    // SAFETY: the schedule's sources hold what they say; `out` is sized.
    unsafe {
        mix(
            schedule.clips.as_ptr(),
            schedule.clips.len() as i32,
            schedule.sources.as_ptr(),
            schedule.sources.len() as i32,
            schedule.keys.as_ptr(),
            schedule.keys.len() as i32,
            start,
            samples,
            channels,
            out.as_mut_ptr(),
        )
    };
    out
}

#[test]
fn every_made_up_schedule_mixes_as_the_c_mixes_it() {
    let mix = Both::of("qa_audio_mix", qa_audio_mix as Mix);
    let mut dice = Dice(0x5eed_1234);
    let mut heard = 0;
    for round in 0..600 {
        let schedule = Schedule::made(&mut dice);
        let start = dice.int(-400, 3_000);
        let samples = dice.int(1, 1_500) as i32;
        let channels = [1, 2, 2, 3, 6][dice.int(0, 5) as usize];
        let rust = mixed(mix.rust, &schedule, start, samples, channels);
        same_bits(&rust, &mixed(mix.c, &schedule, start, samples, channels), &format!("round {round}"));
        heard += rust.iter().filter(|v| **v != 0.0).count();
    }
    assert!(heard > 100_000, "LIVENESS: the schedules were heard ({heard} values)");
}

#[test]
fn a_bus_that_cannot_be_written_is_left_alone_and_no_clips_is_silence() {
    let mix = Both::of("qa_audio_mix", qa_audio_mix as Mix);
    let held = [0.5f32; 64];
    let source = Source { source_start: 0, length: 64, channels: 1, reserved: 0, samples: held.as_ptr() };
    let clip = Clip { gain: 1.0, end_sample: 64, pan_left: 1.0, pan_right: 1.0, ..Clip::default() };
    let schedule = Schedule { _samples: Vec::new(), sources: vec![source, source], clips: vec![clip], keys: Vec::new() };
    for f in [mix.c, mix.rust] {
        for (samples, channels) in [(0, 2), (-3, 2), (16, 0), (16, -1)] {
            let mut out = [7.0f64; 4];
            // SAFETY: nothing is written for these counts.
            unsafe { f(ptr::null(), 0, ptr::null(), 0, ptr::null(), 0, 0, samples, channels, out.as_mut_ptr()) };
            assert_eq!(out, [7.0; 4], "{samples} x {channels}");
        }
        // SAFETY: a null bus is refused.
        unsafe { f(ptr::null(), 0, ptr::null(), 0, ptr::null(), 0, 0, 4, 1, ptr::null_mut()) };
        let mut out = [7.0f64; 8];
        let (clips, sources) = (schedule.clips.as_ptr(), schedule.sources.as_ptr());
        for (clips, clip_count, sources, source_count) in [
            (ptr::null(), 3, sources, 2),
            (clips, 1, ptr::null(), 2),
            (clips, 0, sources, 2),
            (clips, 1, sources, -1),
        ] {
            // SAFETY: the counts are within the schedule's.
            unsafe { f(clips, clip_count, sources, source_count, ptr::null(), 0, 0, 4, 2, out.as_mut_ptr()) };
            assert_eq!(out, [0.0; 8]);
            out = [7.0; 8];
        }
    }
}

/// The values a bus reaches, and its edges.
fn bus_values() -> Vec<f64> {
    let mut values = vec![
        0.0, -0.0, 1.0, -1.0, 1.0000001, -1.0000001, 2.5, -7.0, 0.5, -0.5,
        f64::MIN_POSITIVE, 1e-300, -1e-300, 1e300, -1e300, f64::INFINITY, f64::NEG_INFINITY,
    ];
    // Halfway between two 16-bit steps, both ways, and either side of them.
    for step in [-32768i32, -12345, -2, -1, 0, 1, 2, 12345, 32766, 32767] {
        let half = (f64::from(step) + 0.5) / 32768.0;
        values.extend([half, f64::from_bits(half.to_bits() + 1), f64::from_bits(half.to_bits() - 1)]);
    }
    let mut dice = Dice(77);
    values.extend((0..4_000).map(|_| 1.2 * dice.unit()));
    values
}

#[test]
fn the_output_stage_makes_the_c_s_floats_and_shorts() {
    let values = bus_values();
    let count = values.len() as i32;
    let to_float = Both::of("qa_audio_bus_to_float", qa_audio_bus_to_float as ToFloat);
    let to_int16 = Both::of("qa_audio_bus_to_int16", qa_audio_bus_to_int16 as ToInt16);
    let floats = |f: ToFloat| {
        let mut out = vec![0.0f32; values.len()];
        // SAFETY: both hold `count` values.
        unsafe { f(values.as_ptr(), count, out.as_mut_ptr()) };
        out.iter().map(|v| v.to_bits()).collect::<Vec<_>>()
    };
    let shorts = |f: ToInt16| {
        let mut out = vec![0i16; values.len()];
        // SAFETY: both hold `count` values.
        unsafe { f(values.as_ptr(), count, out.as_mut_ptr()) };
        out
    };
    assert_eq!(floats(to_float.rust), floats(to_float.c));
    assert_eq!(shorts(to_int16.rust), shorts(to_int16.c));
    assert_eq!(shorts(to_int16.rust)[..4], [0, 0, 32767, -32768], "LIVENESS: the edges");
    for f in [to_float.c, to_float.rust] {
        let mut out = [7.0f32];
        // SAFETY: nothing is read or written for these.
        unsafe {
            f(ptr::null(), 1, out.as_mut_ptr());
            f(values.as_ptr(), 0, out.as_mut_ptr());
            f(values.as_ptr(), -1, out.as_mut_ptr());
            f(values.as_ptr(), 1, ptr::null_mut());
        }
        assert_eq!(out, [7.0]);
    }
}

#[test]
fn the_filter_lengths_and_frame_counts_are_the_c_s() {
    let taps = Both::of("qa_audio_resample_taps", qa_audio_resample_taps as Taps);
    let frames = Both::of("qa_audio_resample_frames", qa_audio_resample_frames as Frames);
    let rates = [-1, 0, 1, 7, 8_000, 22_050, 44_100, 47_999, 48_000, 96_000, 192_000];
    for input in rates {
        for output in rates {
            // The default, Kaiser's three branches and their seam at 50,
            // the shortest filter (15) and the longest (no transition).
            for (stopband, bandwidth) in [
                (120.0, 0.9),
                (80.0, 0.95),
                (50.0, 0.9),
                (40.0, 0.5),
                (20.0, 0.8),
                (20.0, 0.5),
                (10.0, 0.5),
                (120.0, 1.0),
            ] {
                let asked = (input, output, stopband, bandwidth);
                assert_eq!((taps.rust)(input, output, stopband, bandwidth), (taps.c)(input, output, stopband, bandwidth), "{asked:?}");
            }
            for count in [-5, 0, 1, 7, 44_099, 44_100, 1_000_003] {
                assert_eq!((frames.rust)(count, input, output), (frames.c)(count, input, output), "{count} {input}→{output}");
            }
        }
    }
    assert_eq!(qa_audio_resample_taps(44_100, 48_000, 120.0, 0.9) % 2, 1, "LIVENESS: odd");
    assert_eq!(qa_audio_resample_taps(48_000, 96_000, 20.0, 0.5), 15, "LIVENESS: the shortest");
}

/// A sound of `frames` x `channels`: tones and noise.
fn sound(frames: usize, channels: usize, seed: u32) -> Vec<f32> {
    let mut dice = Dice(seed);
    (0..frames * channels)
        .map(|at| {
            let (frame, channel) = ((at / channels) as f64, (at % channels) as f64);
            (0.5 * (frame * (0.01 + 0.03 * channel)).sin() + 0.2 * dice.unit()) as f32
        })
        .collect()
}

fn resampled(f: Resample, samples: &[f32], channels: i32, input: i32, output: i32) -> Vec<u32> {
    resampled_at(f, samples, channels, (input, output), (120.0, 0.9))
}

/// `samples` converted whole by `f` at `quality` (stopband, bandwidth).
fn resampled_at(f: Resample, samples: &[f32], channels: i32, rates: (i32, i32), quality: (f64, f64)) -> Vec<u32> {
    let frames = samples.len() as i64 / i64::from(channels);
    let mut out = vec![f32::NAN; (qa_audio_resample_frames(frames, rates.0, rates.1) * i64::from(channels)) as usize];
    // SAFETY: `out` is sized by resample_frames.
    let written =
        unsafe { f(samples.as_ptr(), frames, channels, rates.0, rates.1, quality.0, quality.1, out.as_mut_ptr()) };
    assert_eq!(written * i64::from(channels), out.len() as i64);
    out.iter().map(|v| v.to_bits()).collect()
}

#[test]
fn a_filter_of_every_quality_converts_as_the_c_s() {
    let resample = Both::of("qa_audio_resample", qa_audio_resample as Resample);
    let take = sound(9_001, 2, 21);
    // Kaiser's three branches and their seam, and the shortest filter.
    for quality in [(80.0, 0.95), (50.0, 0.9), (40.0, 0.9), (30.0, 0.8), (20.0, 0.5), (10.0, 0.5)] {
        for rates in [(44_100, 48_000), (48_000, 96_000)] {
            let rust = resampled_at(resample.rust, &take, 2, rates, quality);
            assert_eq!(rust, resampled_at(resample.c, &take, 2, rates, quality), "{rates:?} at {quality:?}");
        }
    }
}

#[test]
fn a_whole_sound_converts_as_the_c_converts_it() {
    let resample = Both::of("qa_audio_resample", qa_audio_resample as Resample);
    let pairs = [(44_100, 48_000), (48_000, 44_100), (22_050, 48_000), (8_000, 48_000), (96_000, 48_000), (32_000, 44_100)];
    for (input, output) in pairs {
        for channels in [1, 2] {
            let take = sound(input as usize / 3 + 17, channels as usize, input as u32);
            let rust = resampled(resample.rust, &take, channels, input, output);
            assert_eq!(rust, resampled(resample.c, &take, channels, input, output), "{input}→{output} x {channels}");
        }
    }
}

#[test]
fn both_refuse_the_same_conversions() {
    let resample = Both::of("qa_audio_resample", qa_audio_resample as Resample);
    let open = Both::of("qa_audio_resampler_open", qa_audio_resampler_open as Open);
    let close: Close = c("qa_audio_resampler_close");
    let take = sound(64, 1, 3);
    let mut out = [0.0f32; 256];
    for f in [resample.c, resample.rust] {
        for (samples, frames, channels, input, output) in [
            (ptr::null(), 64, 1, 44_100, 48_000),
            (take.as_ptr(), 0, 1, 44_100, 48_000),
            (take.as_ptr(), -1, 1, 44_100, 48_000),
            (take.as_ptr(), 64, 0, 44_100, 48_000),
            (take.as_ptr(), 64, 1, 48_000, 48_000),
            (take.as_ptr(), 64, 1, 0, 48_000),
            (take.as_ptr(), 64, 1, 44_100, -1),
        ] {
            // SAFETY: refused before anything is read or written.
            assert_eq!(unsafe { f(samples, frames, channels, input, output, 120.0, 0.9, out.as_mut_ptr()) }, 0);
        }
        // SAFETY: as above.
        assert_eq!(unsafe { f(take.as_ptr(), 64, 1, 44_100, 48_000, 120.0, 0.9, ptr::null_mut()) }, 0);
    }
    for (channels, input, output) in [(0, 44_100, 48_000), (-2, 44_100, 48_000), (1, 48_000, 48_000), (1, 0, 48_000)] {
        assert!((open.c)(channels, input, output, 120.0, 0.9).is_null());
        assert!((open.rust)(channels, input, output, 120.0, 0.9).is_null());
    }
    // SAFETY: closing null is nothing, on both.
    unsafe {
        close(ptr::null_mut());
        qa_audio_resampler_close(ptr::null_mut());
    }
    for side in [Stream::c(), Stream::rust()] {
        let resampler = (side.open)(1, 44_100, 48_000, 120.0, 0.9);
        // SAFETY: `resampler` is open; each null below is a refusal.
        unsafe {
            assert_eq!((side.push)(resampler, ptr::null(), 5), 0, "five frames from nowhere");
            assert_eq!((side.push)(resampler, take.as_ptr(), -1), 0);
            assert_eq!((side.push)(ptr::null_mut(), take.as_ptr(), 5), 0);
            assert_eq!((side.push)(resampler, ptr::null(), 0), 1, "nothing, from nowhere, is taken");
            assert_eq!((side.push)(resampler, take.as_ptr(), 64), 1);
            assert_eq!((side.held)(resampler), 64, "LIVENESS: the refused pushes held nothing");
            (side.end)(resampler);
            assert_eq!((side.pull)(resampler, ptr::null_mut(), 8), 0);
            assert_eq!((side.pull)(resampler, out.as_mut_ptr(), 0), 0);
            assert_eq!((side.pull)(ptr::null_mut(), out.as_mut_ptr(), 8), 0);
            assert_eq!(((side.held)(ptr::null()), (side.ready)(ptr::null())), (0, 0));
            (side.end)(ptr::null_mut());
            assert_eq!((side.pull)(resampler, out.as_mut_ptr(), 256), 69, "LIVENESS: what was taken comes out");
            (side.close)(resampler);
        }
    }
}

/// One side's streaming exports.
#[derive(Clone, Copy)]
struct Stream {
    open: Open,
    push: Push,
    end: End,
    held: Count,
    ready: Count,
    pull: Pull,
    close: Close,
}

impl Stream {
    fn c() -> Self {
        Stream {
            open: c("qa_audio_resampler_open"),
            push: c("qa_audio_resampler_push"),
            end: c("qa_audio_resampler_end"),
            held: c("qa_audio_resampler_held"),
            ready: c("qa_audio_resampler_ready"),
            pull: c("qa_audio_resampler_pull"),
            close: c("qa_audio_resampler_close"),
        }
    }

    fn rust() -> Self {
        Stream {
            open: qa_audio_resampler_open,
            push: qa_audio_resampler_push,
            end: qa_audio_resampler_end,
            held: qa_audio_resampler_held,
            ready: qa_audio_resampler_ready,
            pull: qa_audio_resampler_pull,
            close: qa_audio_resampler_close,
        }
    }
}

/// What a side says at every step of feeding `take` in `pieces` and
/// pulling `capacity` at a time: each push's answer, held and ready after
/// it, and each pull's count and samples, then the same after the end.
fn streamed(side: Stream, take: &[f32], channels: usize, rates: (i32, i32), dice: &mut Dice) -> Vec<i64> {
    let mut said = Vec::new();
    let resampler = (side.open)(channels as i32, rates.0, rates.1, 120.0, 0.9);
    assert!(!resampler.is_null());
    let frames = take.len() / channels;
    let mut fed = 0;
    let mut out = vec![0.0f32; 9_000 * channels];
    // SAFETY: `resampler` is open; every piece and `out` hold what is said.
    unsafe {
        let mut drain = |said: &mut Vec<i64>, dice: &mut Dice| {
            let capacity = dice.int(0, 9_000);
            let pulled = (side.pull)(resampler, out.as_mut_ptr(), capacity);
            said.push(pulled);
            said.extend(out[..pulled as usize * channels].iter().map(|v| i64::from(v.to_bits())));
            said.extend([(side.held)(resampler), (side.ready)(resampler)]);
        };
        while fed < frames {
            let piece = (dice.int(0, 6_000) as usize).min(frames - fed);
            said.push(i64::from((side.push)(resampler, take[fed * channels..].as_ptr(), piece as i64)));
            fed += piece;
            said.extend([(side.held)(resampler), (side.ready)(resampler)]);
            drain(&mut said, dice);
        }
        (side.end)(resampler);
        said.push(i64::from((side.push)(resampler, take.as_ptr(), 1)));
        while (side.ready)(resampler) > 0 {
            drain(&mut said, dice);
        }
        (side.close)(resampler);
    }
    said
}

#[test]
fn a_sound_fed_in_pieces_converts_as_the_c_converts_it_step_by_step() {
    for (input, output, channels) in [(44_100, 48_000, 2), (48_000, 44_100, 1), (22_050, 48_000, 2), (96_000, 48_000, 1)] {
        let take = sound(input as usize / 2 + 5, channels, output as u32);
        for seed in [1, 2, 3] {
            let rust = streamed(Stream::rust(), &take, channels, (input, output), &mut Dice(seed));
            let c = streamed(Stream::c(), &take, channels, (input, output), &mut Dice(seed));
            assert_eq!(rust.len(), c.len(), "{input}→{output} seed {seed}");
            let first = rust.iter().zip(&c).position(|(a, b)| a != b);
            assert_eq!(first, None, "{input}→{output} seed {seed}: step {first:?}");
        }
    }
}

#[test]
fn a_sound_fed_in_pieces_converts_as_it_converts_whole() {
    let (input, output, channels) = (44_100, 48_000, 2usize);
    let take = sound(30_011, channels, 5);
    let whole = resampled(qa_audio_resample, &take, channels as i32, input, output);
    let mut resampler = Resampler::new(channels, input, output, 120.0, 0.9).expect("a conversion");
    let mut pieces = Vec::new();
    let mut out = vec![0.0f32; 4_096 * channels];
    let mut dice = Dice(8);
    for chunk in take.chunks(channels * 1_237) {
        assert!(resampler.push(chunk));
        let pulled = resampler.pull(&mut out[..dice.int(1, 4_096) as usize * channels]);
        pieces.extend(out[..pulled as usize * channels].iter().map(|v| v.to_bits()));
    }
    resampler.end();
    while resampler.ready() > 0 {
        let pulled = resampler.pull(&mut out);
        pieces.extend(out[..pulled as usize * channels].iter().map(|v| v.to_bits()));
    }
    assert_eq!(pieces, whole);
    // A push lets go of what no output still to come reads — never the
    // whole sound. (How much, step by step, the C comparison holds.)
    assert!(resampler.held_frames() < 30_011 / 2, "LIVENESS: held {} of 30011", resampler.held_frames());
}
