//! Sample-rate conversion (audio program 2B) — `qa_audio_resample*` and
//! `qa_audio_resampler_*`, the twin of `audio_resampler_reference.dart`.
//!
//! Kaiser-windowed sinc, run in polyphase form, LINEAR PHASE: the constant
//! group delay is cancelled in the index arithmetic, never by trimming
//! afterwards — at these lengths it exceeds a frame at 24fps, and an
//! uncompensated conform would put every resampled clip a frame late.
//! Every expression mirrors the Dart line for line, the Bessel series'
//! termination included, for the parity suite compares them bit for bit.
//!
//! 🚨★★★ONE LOOP, WHOLE OR A PIECE AT A TIME (user 2026-10-10, board
//! long-sound-conform-memory-Q1: 「지금 한다 — 전 플랫폼」). A long sound is
//! conformed as the decoder hands it back, and an output frame reads the
//! inputs it reads either way: the same taps in the same order, so a
//! conversion fed in pieces writes the whole conversion's samples, bit for
//! bit. [`Design::run`] is that loop; ⛔a second loop for the pieces would
//! be the copy that drifts.

use std::f64::consts::PI;
use std::slice;

/// The longest prototype a design makes.
const MAX_TAPS: i64 = 131_071;

fn gcd(a: i64, b: i64) -> i64 {
    let (mut x, mut y) = (a.abs(), b.abs());
    while y != 0 {
        (x, y) = (y, x % y);
    }
    x
}

/// Output frames per input frame as `(interpolation, decimation)`, in
/// lowest terms — none for equal rates, which the caller never converts
/// (it keeps the input bit-exact, the common case).
fn ratio(input_rate: i32, output_rate: i32) -> Option<(i64, i64)> {
    if input_rate <= 0 || output_rate <= 0 || input_rate == output_rate {
        return None;
    }
    let divisor = gcd(i64::from(input_rate), i64::from(output_rate));
    Some((i64::from(output_rate) / divisor, i64::from(input_rate) / divisor))
}

/// The modified Bessel function of the first kind, order 0 — the Kaiser
/// window's kernel. FIXED termination (relative epsilon, hard cap) so both
/// sides run the same number of terms.
fn bessel_i0(x: f64) -> f64 {
    let half = x / 2.0;
    let mut term = 1.0;
    let mut sum = 1.0;
    for k in 1..=64 {
        let ratio = half / f64::from(k);
        term *= ratio * ratio;
        sum += term;
        if term < sum * 1e-16 {
            break;
        }
    }
    sum
}

fn kaiser_beta(stopband_db: f64) -> f64 {
    if stopband_db > 50.0 {
        0.1102 * (stopband_db - 8.7)
    } else if stopband_db >= 21.0 {
        0.5842 * (stopband_db - 21.0).powf(0.4) + 0.07886 * (stopband_db - 21.0)
    } else {
        0.0
    }
}

fn sinc(x: f64) -> f64 {
    if x == 0.0 {
        return 1.0;
    }
    let pix = PI * x;
    pix.sin() / pix
}

/// The prototype's length for a conversion: odd, 15 to 131071, and 0 for
/// equal rates or a rate that is not one.
pub fn resample_taps(input_rate: i32, output_rate: i32, stopband_db: f64, bandwidth: f64) -> i32 {
    let Some((interpolation, decimation)) = ratio(input_rate, output_rate) else {
        return 0;
    };
    let nyquist = 0.5 / interpolation.max(decimation) as f64;
    let transition = nyquist - nyquist * bandwidth;
    let taps = if transition <= 0.0 {
        MAX_TAPS
    } else {
        ((stopband_db - 8.0) / (2.285 * 2.0 * PI * transition)).ceil() as i64
    };
    let taps = taps.clamp(15, MAX_TAPS);
    let odd = if taps % 2 == 0 { taps + 1 } else { taps };
    odd as i32
}

/// How many frames a whole conversion of `input_frames` writes — the
/// caller's allocation, worked out as the conversion works it out.
pub fn resample_frames(input_frames: i64, input_rate: i32, output_rate: i32) -> i64 {
    if input_frames <= 0 || input_rate <= 0 || output_rate <= 0 {
        return 0;
    }
    match ratio(input_rate, output_rate) {
        None => input_frames,
        Some((interpolation, decimation)) => input_frames * interpolation / decimation,
    }
}

/// What a conversion between two rates runs: its polyphase geometry and
/// the prototype's taps.
struct Design {
    interpolation: i64,
    decimation: i64,
    half_length: i64,
    kernel: Vec<f64>,
}

impl Design {
    /// None on bad geometry, equal rates among it, or no room for the taps.
    fn new(input_rate: i32, output_rate: i32, stopband_db: f64, bandwidth: f64) -> Option<Design> {
        let (interpolation, decimation) = ratio(input_rate, output_rate)?;
        let nyquist = 0.5 / interpolation.max(decimation) as f64;
        let passband_edge = nyquist * bandwidth;
        let cutoff = (passband_edge + nyquist) / 2.0;
        let beta = kaiser_beta(stopband_db);
        let taps = i64::from(resample_taps(input_rate, output_rate, stopband_db, bandwidth));
        let mut kernel = Vec::new();
        kernel.try_reserve_exact(taps as usize).ok()?;
        let center = (taps - 1) as f64 / 2.0;
        let denominator = bessel_i0(beta);
        kernel.extend((0..taps).map(|index| {
            let offset = index as f64 - center;
            let ratio = offset / center;
            let inside = 1.0 - ratio * ratio;
            let window = if inside <= 0.0 { 0.0 } else { bessel_i0(beta * inside.sqrt()) / denominator };
            2.0 * cutoff * sinc(2.0 * cutoff * offset) * window * interpolation as f64
        }));
        Some(Design { interpolation, decimation, half_length: (taps - 1) / 2, kernel })
    }

    fn taps(&self) -> i64 {
        self.kernel.len() as i64
    }

    /// One past the last output frame `total` input frames can write:
    /// every one there is once the input has `ended`, and before that only
    /// those whose every input has arrived.
    fn ready_end(&self, total: i64, ended: bool) -> i64 {
        let limit = total * self.interpolation / self.decimation;
        if ended {
            return limit;
        }
        // An output reads back from its base frame, (frame * M + half) / L,
        // so it is complete once that frame has arrived:
        // frame * M + half < total * L.
        let reach = total * self.interpolation - self.half_length;
        let complete = if reach <= 0 { 0 } else { (reach + self.decimation - 1) / self.decimation };
        complete.min(limit)
    }

    /// Writes the output frames from `from` on into `out` (as many as it
    /// holds), reading input frames [`first`, `total`) out of `held`.
    ///
    /// ⚠️Every input those outputs read from `first` on is held, and while
    /// more input may come none reads past `total` ([`Design::ready_end`]):
    /// an input past the end is skipped, which is right only at the
    /// sound's end.
    fn run(&self, channels: usize, held: &[f32], first: i64, total: i64, from: i64, out: &mut [f32]) {
        for (at, frame) in out.chunks_exact_mut(channels).enumerate() {
            // + half_length centres the filter on the output instant: the
            // delay compensation, applied here so it never has to be a
            // whole number of output samples.
            let position = (from + at as i64) * self.decimation + self.half_length;
            let phase = position % self.interpolation;
            let base = position / self.interpolation;
            for (channel, out) in frame.iter_mut().enumerate() {
                let mut sum = 0.0;
                let mut tap = phase;
                let mut source = base;
                while tap < self.taps() && source >= first {
                    if source < total {
                        sum += self.kernel[tap as usize]
                            * f64::from(held[(source - first) as usize * channels + channel]);
                    }
                    tap += self.interpolation;
                    source -= 1;
                }
                *out = sum as f32;
            }
        }
    }
}

/// A conversion fed a piece at a time: the design, and the input the
/// outputs still to come read.
pub struct Resampler {
    design: Design,
    channels: usize,
    /// Input frames [`first`, `first` + held frames), interleaved.
    held: Vec<f32>,
    first: i64,
    /// The next output frame.
    next: i64,
    ended: bool,
}

impl Resampler {
    /// A conversion of `channels` from `input_rate` to `output_rate` —
    /// none on bad geometry, equal rates among it.
    pub fn new(channels: usize, input_rate: i32, output_rate: i32, stopband_db: f64, bandwidth: f64) -> Option<Self> {
        if channels == 0 {
            return None;
        }
        let design = Design::new(input_rate, output_rate, stopband_db, bandwidth)?;
        Some(Resampler { design, channels, held: Vec::new(), first: 0, next: 0, ended: false })
    }

    /// Input frames held now — what tells a conversion that lets go of its
    /// input from one that keeps the whole sound.
    pub fn held_frames(&self) -> i64 {
        (self.held.len() / self.channels) as i64
    }

    /// Lets go of the held input no output still to come reads: output
    /// frame f reads back to input (f * M + half - taps) / L + 1.
    fn let_go(&mut self) {
        let design = &self.design;
        let reach = self.next * design.decimation + design.half_length - design.taps() + design.interpolation;
        let lowest = if reach <= 0 { 0 } else { reach / design.interpolation };
        let drop = (lowest - self.first).min(self.held_frames());
        if drop <= 0 {
            return;
        }
        self.held.drain(..drop as usize * self.channels);
        self.first += drop;
    }

    /// Hands more input over: whole frames. False when the memory ran out
    /// or after [`Resampler::end`].
    pub fn push(&mut self, samples: &[f32]) -> bool {
        if self.ended {
            return false;
        }
        self.let_go();
        if self.held.try_reserve(samples.len()).is_err() {
            return false;
        }
        self.held.extend_from_slice(samples);
        true
    }

    /// No more input comes: the outputs that read past the end are ready.
    pub fn end(&mut self) {
        self.ended = true;
    }

    /// How many output frames [`Resampler::pull`] can write now.
    pub fn ready(&self) -> i64 {
        let end = self.design.ready_end(self.first + self.held_frames(), self.ended);
        (end - self.next).max(0)
    }

    /// Writes as many of the ready output frames as `out` holds; answers
    /// how many.
    pub fn pull(&mut self, out: &mut [f32]) -> i64 {
        let count = self.ready().min((out.len() / self.channels) as i64);
        let total = self.first + self.held_frames();
        let out = &mut out[..count as usize * self.channels];
        self.design.run(self.channels, &self.held, self.first, total, self.next, out);
        self.next += count;
        count
    }
}

/// [`resample_taps`] for C.
#[unsafe(no_mangle)]
pub extern "C" fn qa_audio_resample_taps(input_rate: i32, output_rate: i32, stopband_db: f64, bandwidth: f64) -> i32 {
    resample_taps(input_rate, output_rate, stopband_db, bandwidth)
}

/// [`resample_frames`] for C.
#[unsafe(no_mangle)]
pub extern "C" fn qa_audio_resample_frames(input_frames: i64, input_rate: i32, output_rate: i32) -> i64 {
    resample_frames(input_frames, input_rate, output_rate)
}

/// The whole of `samples` converted into `out` (sized by
/// [`resample_frames`]): the frames written, 0 on bad geometry. Equal
/// rates are not handled here — the caller keeps the input as it is.
///
/// # Safety
/// `samples` is null or points at `input_frames` x `channels` floats, and
/// `out` at the frames [`resample_frames`] answers x `channels`.
#[unsafe(no_mangle)]
#[allow(clippy::too_many_arguments)]
pub unsafe extern "C" fn qa_audio_resample(
    samples: *const f32,
    input_frames: i64,
    channels: i32,
    input_rate: i32,
    output_rate: i32,
    stopband_db: f64,
    bandwidth: f64,
    out: *mut f32,
) -> i64 {
    let (Ok(frames), Ok(channels)) = (usize::try_from(input_frames), usize::try_from(channels)) else {
        return 0;
    };
    if samples.is_null() || out.is_null() || frames == 0 || channels == 0 {
        return 0;
    }
    let Some(design) = Design::new(input_rate, output_rate, stopband_db, bandwidth) else {
        return 0;
    };
    let output_frames = design.ready_end(input_frames, true);
    // SAFETY: the caller's contract.
    let (held, out) = unsafe {
        (
            slice::from_raw_parts(samples, frames * channels),
            slice::from_raw_parts_mut(out, output_frames as usize * channels),
        )
    };
    design.run(channels, held, 0, input_frames, 0, out);
    output_frames
}

/// [`Resampler::new`] for C: null on bad geometry. Let go with
/// [`qa_audio_resampler_close`].
#[unsafe(no_mangle)]
pub extern "C" fn qa_audio_resampler_open(
    channels: i32,
    input_rate: i32,
    output_rate: i32,
    stopband_db: f64,
    bandwidth: f64,
) -> *mut Resampler {
    let Ok(channels) = usize::try_from(channels) else {
        return std::ptr::null_mut();
    };
    match Resampler::new(channels, input_rate, output_rate, stopband_db, bandwidth) {
        Some(resampler) => Box::into_raw(Box::new(resampler)),
        None => std::ptr::null_mut(),
    }
}

/// [`Resampler::push`] for C: 1 taken, 0 not.
///
/// # Safety
/// `resampler` is null or an open one; `samples` is null or points at
/// `frames` x its channels floats.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qa_audio_resampler_push(resampler: *mut Resampler, samples: *const f32, frames: i64) -> i32 {
    // SAFETY: the caller's contract.
    let Some(resampler) = (unsafe { resampler.as_mut() }) else {
        return 0;
    };
    let Ok(frames) = usize::try_from(frames) else {
        return 0;
    };
    if frames > 0 && samples.is_null() {
        return 0;
    }
    let samples = match frames {
        0 => &[][..],
        // SAFETY: the caller's contract.
        _ => unsafe { slice::from_raw_parts(samples, frames * resampler.channels) },
    };
    i32::from(resampler.push(samples))
}

/// [`Resampler::end`] for C.
///
/// # Safety
/// `resampler` is null or an open one.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qa_audio_resampler_end(resampler: *mut Resampler) {
    // SAFETY: the caller's contract.
    if let Some(resampler) = unsafe { resampler.as_mut() } {
        resampler.end();
    }
}

/// [`Resampler::held_frames`] for C.
///
/// # Safety
/// `resampler` is null or an open one.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qa_audio_resampler_held(resampler: *const Resampler) -> i64 {
    // SAFETY: the caller's contract.
    unsafe { resampler.as_ref() }.map_or(0, Resampler::held_frames)
}

/// [`Resampler::ready`] for C.
///
/// # Safety
/// `resampler` is null or an open one.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qa_audio_resampler_ready(resampler: *const Resampler) -> i64 {
    // SAFETY: the caller's contract.
    unsafe { resampler.as_ref() }.map_or(0, Resampler::ready)
}

/// [`Resampler::pull`] for C: up to `capacity` frames into `out`.
///
/// # Safety
/// `resampler` is null or an open one; `out` is null or points at
/// `capacity` x its channels floats.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qa_audio_resampler_pull(resampler: *mut Resampler, out: *mut f32, capacity: i64) -> i64 {
    // SAFETY: the caller's contract.
    let Some(resampler) = (unsafe { resampler.as_mut() }) else {
        return 0;
    };
    let Ok(capacity) = usize::try_from(capacity) else {
        return 0;
    };
    if out.is_null() || capacity == 0 {
        return 0;
    }
    // SAFETY: the caller's contract.
    let out = unsafe { slice::from_raw_parts_mut(out, capacity * resampler.channels) };
    resampler.pull(out)
}

/// Lets go of a resampler [`qa_audio_resampler_open`] made.
///
/// # Safety
/// `resampler` is null or an open one, not used again.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qa_audio_resampler_close(resampler: *mut Resampler) {
    if !resampler.is_null() {
        // SAFETY: the caller's contract — it came from Box::into_raw.
        drop(unsafe { Box::from_raw(resampler) });
    }
}
