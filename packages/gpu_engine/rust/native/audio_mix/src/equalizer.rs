//! A sound row's equalizer (board `audio-fx-grows-like-the-pros` ③ — 유저
//! Q2 「시안 1 + 성격 프리셋」, 11-17: a row's audio effects are added one
//! at a time, and イコライザー is the first): a low cut, a low shelf, a
//! high shelf and a high cut, each a biquad of the RBJ Audio EQ Cookbook,
//! run one after another over a span's samples.
//!
//! ⛔NOT IN THE MIX BUS: a filter remembers the samples before, and the
//! bus mixes each call afresh from wherever it is asked — a seek, a loop's
//! wrap, a scrub backwards, an export on its own axis — so the same sample
//! would come out three ways. A span is baked once from its first sample,
//! and playback and export both read what was baked (that card, 11-17).
//!
//! The coefficients' sine, cosine and power are `libm`'s, the same Rust on
//! every OS (Cargo.toml); the filtering is IEEE's add and multiply in f64,
//! with no fused multiply-add, so a baked span is the same bits on every
//! device.

/// One biquad's coefficients over its a0.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Biquad {
    pub b0: f64,
    pub b1: f64,
    pub b2: f64,
    pub a1: f64,
    pub a2: f64,
}

/// A cut's Q: Butterworth's, flat to its corner and 3 dB down there.
const BUTTERWORTH_Q: f64 = std::f64::consts::FRAC_1_SQRT_2;

impl Biquad {
    /// Divides each coefficient by `a0`.
    fn over(a0: f64, [b0, b1, b2, a1, a2]: [f64; 5]) -> Self {
        Self { b0: b0 / a0, b1: b1 / a0, b2: b2 / a0, a1: a1 / a0, a2: a2 / a0 }
    }

    /// The cookbook's HPF: what lies under `hz` falls away, 12 dB an octave.
    pub fn low_cut(rate: f64, hz: f64) -> Self {
        let (cos, alpha) = corner(rate, hz, BUTTERWORTH_Q);
        let half = (1.0 + cos) / 2.0;
        Self::over(1.0 + alpha, [half, -(1.0 + cos), half, -2.0 * cos, 1.0 - alpha])
    }

    /// The cookbook's LPF: what lies over `hz` falls away, 12 dB an octave.
    pub fn high_cut(rate: f64, hz: f64) -> Self {
        let (cos, alpha) = corner(rate, hz, BUTTERWORTH_Q);
        let half = (1.0 - cos) / 2.0;
        Self::over(1.0 + alpha, [half, 1.0 - cos, half, -2.0 * cos, 1.0 - alpha])
    }

    /// The cookbook's lowShelf at its steepest slope (S = 1): what lies
    /// under `hz` raised or lowered by `db`.
    pub fn low_shelf(rate: f64, hz: f64, db: f64) -> Self {
        let (a, cos, root_alpha) = shelf(rate, hz, db);
        let (plus, minus) = (a + 1.0, a - 1.0);
        Self::over(
            plus + minus * cos + root_alpha,
            [
                a * (plus - minus * cos + root_alpha),
                2.0 * a * (minus - plus * cos),
                a * (plus - minus * cos - root_alpha),
                -2.0 * (minus + plus * cos),
                plus + minus * cos - root_alpha,
            ],
        )
    }

    /// The cookbook's highShelf at its steepest slope (S = 1): what lies
    /// over `hz` raised or lowered by `db`.
    pub fn high_shelf(rate: f64, hz: f64, db: f64) -> Self {
        let (a, cos, root_alpha) = shelf(rate, hz, db);
        let (plus, minus) = (a + 1.0, a - 1.0);
        Self::over(
            plus - minus * cos + root_alpha,
            [
                a * (plus + minus * cos + root_alpha),
                -2.0 * a * (minus + plus * cos),
                a * (plus + minus * cos - root_alpha),
                2.0 * (minus - plus * cos),
                plus - minus * cos - root_alpha,
            ],
        )
    }

    /// `x` through this biquad, `memory` the two samples before on each
    /// side (direct form I).
    fn run(&self, memory: &mut Memory, x: f64) -> f64 {
        let y = self.b0 * x + self.b1 * memory.x1 + self.b2 * memory.x2
            - self.a1 * memory.y1
            - self.a2 * memory.y2;
        memory.push(x, y);
        y
    }
}

/// cos ω and α = sin ω / 2Q at `hz`, ω = 2π·hz / rate.
fn corner(rate: f64, hz: f64, q: f64) -> (f64, f64) {
    let omega = 2.0 * std::f64::consts::PI * hz / rate;
    (libm::cos(omega), libm::sin(omega) / (2.0 * q))
}

/// A shelf's A = 10^(db/40), cos ω and 2√A·α at S = 1, where α is
/// sin ω / 2 · √2.
fn shelf(rate: f64, hz: f64, db: f64) -> (f64, f64, f64) {
    let a = libm::pow(10.0, db / 40.0);
    let (cos, alpha) = corner(rate, hz, BUTTERWORTH_Q);
    (a, cos, 2.0 * a.sqrt() * alpha)
}

/// The two inputs and outputs before, of one section on one channel.
#[derive(Clone, Copy, Debug, Default)]
struct Memory {
    x1: f64,
    x2: f64,
    y1: f64,
    y2: f64,
}

impl Memory {
    fn push(&mut self, x: f64, y: f64) {
        (self.x2, self.x1, self.y2, self.y1) = (self.x1, x, self.y1, y);
    }
}

/// An equalizer's settings at one moment. A cut whose corner is no
/// frequency of the rate — at or under 0 Hz, at or past half the rate —
/// and a shelf of 0 dB are left out, so an equalizer of none of them hands
/// its samples back as they were.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Equalizer {
    /// Hz: the lows under it fall away.
    pub low_cut: f64,
    /// Hz: the highs over it fall away.
    pub high_cut: f64,
    /// The low shelf's corner, Hz, and its gain, dB.
    pub low_shelf: f64,
    pub low_db: f64,
    /// The high shelf's corner, Hz, and its gain, dB.
    pub high_shelf: f64,
    pub high_db: f64,
}

/// What an equalizer runs a sample through at `rate`, in order — low cut,
/// low shelf, high shelf, high cut — `None` where a section is left out.
fn sections(equalizer: &Equalizer, rate: f64) -> [Option<Biquad>; 4] {
    let a_frequency = |hz: f64| hz > 0.0 && hz < rate / 2.0;
    let shelving = |hz: f64, db: f64| db != 0.0 && a_frequency(hz);
    [
        a_frequency(equalizer.low_cut).then(|| Biquad::low_cut(rate, equalizer.low_cut)),
        shelving(equalizer.low_shelf, equalizer.low_db)
            .then(|| Biquad::low_shelf(rate, equalizer.low_shelf, equalizer.low_db)),
        shelving(equalizer.high_shelf, equalizer.high_db)
            .then(|| Biquad::high_shelf(rate, equalizer.high_shelf, equalizer.high_db)),
        a_frequency(equalizer.high_cut).then(|| Biquad::high_cut(rate, equalizer.high_cut)),
    ]
}

/// The settings from `start` — a sample of the span, 0 its first — until
/// the next's.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Setting {
    pub start: i64,
    pub equalizer: Equalizer,
}

/// `samples` — interleaved by `channels`, at `rate` — through the
/// equalizer `settings` give, each channel's sections from rest at the
/// first sample. The settings run in order of `start`; where one starts,
/// its coefficients take over with the memory as it stands, and a section
/// left out passes its sample on and remembers it, so one that comes in
/// later starts from what it would have seen.
pub fn equalize(samples: &[f32], channels: usize, rate: f64, settings: &[Setting]) -> Vec<f32> {
    let mut out = vec![0.0; samples.len()];
    equalize_into(samples, channels, rate, settings, &mut out);
    out
}

/// [`equalize`] written into `out`, as long as `samples`: a long sound is
/// held once more, not twice.
pub fn equalize_into(samples: &[f32], channels: usize, rate: f64, settings: &[Setting], out: &mut [f32]) {
    assert!(channels > 0 && samples.len() % channels == 0, "whole frames of {channels} channels");
    assert_eq!(out.len(), samples.len(), "an out as long as the samples");
    let mut memories = vec![[Memory::default(); 4]; channels];
    let mut next = 0;
    let mut current = [None; 4];
    let frames = samples.chunks_exact(channels).zip(out.chunks_exact_mut(channels));
    for ((frame, written), at) in frames.zip(0_i64..) {
        while next < settings.len() && settings[next].start <= at {
            current = sections(&settings[next].equalizer, rate);
            next += 1;
        }
        for ((&sample, memory), slot) in frame.iter().zip(memories.iter_mut()).zip(written.iter_mut()) {
            let mut x = f64::from(sample);
            for (section, kept) in current.iter().zip(memory.iter_mut()) {
                x = match section {
                    Some(biquad) => biquad.run(kept, x),
                    None => {
                        kept.push(x, x);
                        x
                    }
                };
            }
            *slot = x as f32;
        }
    }
}

/// The floats a setting takes in [`qa_audio_equalize`]'s `values`, in
/// [`Equalizer`]'s order: low cut, high cut, low shelf, low dB, high
/// shelf, high dB.
pub const EQUALIZER_VALUES: usize = 6;

/// [`equalize_into`] for C: `samples` — `frames` x `channels` floats at
/// `rate` — into `out`, as many, through `count` settings, each a start in
/// `starts` and [`EQUALIZER_VALUES`] floats in `values`. 1 when it ran, 0
/// on bad geometry, `out` then untouched.
///
/// # Safety
/// `samples` and `out` are null or point at `frames` x `channels` floats,
/// `starts` at `count` integers and `values` at `count` x
/// [`EQUALIZER_VALUES`] floats.
#[unsafe(no_mangle)]
#[allow(clippy::too_many_arguments)]
pub unsafe extern "C" fn qa_audio_equalize(
    samples: *const f32,
    frames: i64,
    channels: i32,
    rate: i32,
    starts: *const i64,
    values: *const f64,
    count: i32,
    out: *mut f32,
) -> i32 {
    let (Ok(frames), Ok(channels), Ok(count)) =
        (usize::try_from(frames), usize::try_from(channels), usize::try_from(count))
    else {
        return 0;
    };
    let unset = samples.is_null() || out.is_null() || (count > 0 && (starts.is_null() || values.is_null()));
    if unset || channels == 0 || rate <= 0 {
        return 0;
    }
    // SAFETY: the caller's contract.
    let (samples, out, starts, values) = unsafe {
        (
            std::slice::from_raw_parts(samples, frames * channels),
            std::slice::from_raw_parts_mut(out, frames * channels),
            if count == 0 { &[][..] } else { std::slice::from_raw_parts(starts, count) },
            if count == 0 { &[][..] } else { std::slice::from_raw_parts(values, count * EQUALIZER_VALUES) },
        )
    };
    let settings: Vec<Setting> = starts
        .iter()
        .zip(values.chunks_exact(EQUALIZER_VALUES))
        .map(|(&start, v)| Setting {
            start,
            equalizer: Equalizer {
                low_cut: v[0],
                high_cut: v[1],
                low_shelf: v[2],
                low_db: v[3],
                high_shelf: v[4],
                high_db: v[5],
            },
        })
        .collect();
    equalize_into(samples, channels, f64::from(rate), &settings, out);
    1
}

#[cfg(test)]
#[path = "equalizer_tests.rs"]
mod tests;
