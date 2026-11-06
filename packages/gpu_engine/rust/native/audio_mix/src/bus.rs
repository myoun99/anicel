//! The mix bus and its output stage — `qa_audio_mix`, `qa_audio_bus_to_*`.
//!
//! The bus is double, not float, on purpose: narrowing after every clip
//! would round dozens of times per sample in an SE-heavy scene, and Dart
//! has only doubles, so a float bus would round where its reference
//! cannot. Clipping is the output stage's, never the mix's: the bus is
//! allowed past unity (that is what headroom is).

use std::slice;

/// One clip on the timeline (AUDIO-PRO R1). Pan arrives as per-side
/// factors Dart works out once — a libm cos/sin here could differ from
/// Dart's by an ulp — and the envelope as a run of the shared key array.
#[repr(C)]
#[derive(Clone, Copy, Debug, Default)]
pub struct Clip {
    pub gain: f64,
    /// The factor for output channel 0 of a stereo bus.
    pub pan_left: f64,
    /// The factor for output channel 1 of a stereo bus.
    pub pan_right: f64,
    /// The timeline position it starts at, inclusive.
    pub start_sample: i64,
    /// The timeline position it ends at, exclusive.
    pub end_sample: i64,
    /// The source sample heard at `start_sample`.
    pub source_offset: i64,
    /// 0 = none.
    pub fade_in_samples: i64,
    /// 0 = none.
    pub fade_out_samples: i64,
    pub source_index: i32,
    /// 1 = equal power (the sqrt ramp), anything else linear.
    pub fade_curve: i32,
    pub envelope_offset: i32,
    /// 0 = unity.
    pub envelope_count: i32,
}

/// A block of decoded samples, interleaved by channel. `source_start` is
/// the source sample `samples[0]` holds, which is what lets a streamed
/// clip present a sliding window through the struct a resident one uses:
/// residency is a policy the mixer never sees.
#[repr(C)]
#[derive(Clone, Copy, Debug)]
pub struct Source {
    pub source_start: i64,
    /// Samples per channel from `source_start`.
    pub length: i64,
    pub channels: i32,
    pub reserved: i32,
    pub samples: *const f32,
}

/// One volume-envelope point: `sample` clip-local, from the clip's start.
/// Linear between points, held past the ends.
#[repr(C)]
#[derive(Clone, Copy, Debug, Default)]
pub struct EnvelopeKey {
    pub sample: i64,
    pub gain: f64,
}

/// The fade ramp's shape: linear, or the equal-power sqrt curve (sum of
/// squares constant across a crossfade). sqrt, not sin: IEEE 754 rounds
/// sqrt correctly, so every side makes the same bits.
fn fade_ramp(ramp: f64, curve: i32) -> f64 {
    let clamped = if ramp < 0.0 { 0.0 } else { ramp };
    if curve == 1 { clamped.sqrt() } else { clamped }
}

/// The envelope at `position` (clip-local): a linear scan, for envelopes
/// carry a handful of keys, mirroring the Dart reference expression for
/// expression. Empty = unity.
fn envelope_at(keys: &[EnvelopeKey], position: i64) -> f64 {
    let (Some(first), Some(last)) = (keys.first(), keys.last()) else {
        return 1.0;
    };
    if position <= first.sample {
        return first.gain;
    }
    if position >= last.sample {
        return last.gain;
    }
    for pair in keys.windows(2) {
        let (a, b) = (pair[0], pair[1]);
        // ⛔The C's `span <= 0` return is not ported: a pair is reached
        // only with a.sample ≤ position < b.sample, so its span is at
        // least one (a mutant returning a's gain there lived, 11-06).
        if position < b.sample {
            let span = (b.sample - a.sample) as f64;
            let t = (position - a.sample) as f64 / span;
            return a.gain + (b.gain - a.gain) * t;
        }
    }
    last.gain
}

/// The clip's run of `keys`, when it names one that is there.
fn envelope_of<'k>(clip: &Clip, keys: &'k [EnvelopeKey]) -> Option<&'k [EnvelopeKey]> {
    let offset = usize::try_from(clip.envelope_offset).ok()?;
    let count = usize::try_from(clip.envelope_count).ok().filter(|&count| count > 0)?;
    keys.get(offset..offset.checked_add(count)?)
}

/// The clip's volume at timeline `position_sample`. ⛔Not clamped to
/// [0, 1]: a boosted clip is mixed as boosted, and only the output stage
/// clips — preview and export hear the same gain.
fn clip_volume(clip: &Clip, keys: &[EnvelopeKey], position_sample: i64) -> f64 {
    let mut volume = clip.gain;
    let position = position_sample - clip.start_sample;
    if let Some(envelope) = envelope_of(clip, keys) {
        volume *= envelope_at(envelope, position);
    }
    if clip.fade_in_samples > 0 && position < clip.fade_in_samples {
        let ramp = position as f64 / clip.fade_in_samples as f64;
        volume *= fade_ramp(ramp, clip.fade_curve);
    }
    let remaining = clip.end_sample - position_sample;
    if clip.fade_out_samples > 0 && remaining < clip.fade_out_samples {
        let ramp = remaining as f64 / clip.fade_out_samples as f64;
        volume *= fade_ramp(ramp, clip.fade_curve);
    }
    volume
}

/// The source channel output channel `out_channel` hears: a mono source
/// feeds every output channel, a wider one maps straight across, holding
/// its last channel under a wider output.
fn source_channel(source_channels: usize, out_channel: usize) -> usize {
    if source_channels <= 1 { 0 } else { out_channel.min(source_channels - 1) }
}

/// Mixes the clips into `out`, an interleaved bus of `out_channels`
/// starting at timeline `start_sample`. A clip whose source is not there,
/// or a position outside its source's window, is silence — never a wait.
///
/// # Safety
/// Each of `sources` holds a null `samples`, or one that points at
/// `length` x `channels` floats.
pub unsafe fn mix(
    clips: &[Clip],
    sources: &[Source],
    keys: &[EnvelopeKey],
    start_sample: i64,
    out_channels: usize,
    out: &mut [f64],
) {
    out.fill(0.0);
    if out_channels == 0 {
        return;
    }
    let block_end = start_sample + (out.len() / out_channels) as i64;
    for clip in clips {
        let Some(source) = usize::try_from(clip.source_index).ok().and_then(|at| sources.get(at)) else {
            continue;
        };
        let (Ok(channels), Ok(length)) = (usize::try_from(source.channels), usize::try_from(source.length)) else {
            continue;
        };
        if source.samples.is_null() || channels == 0 || length == 0 {
            continue;
        }
        // SAFETY: the caller's contract.
        let samples = unsafe { slice::from_raw_parts(source.samples, length * channels) };
        for position in clip.start_sample.max(start_sample)..clip.end_sample.min(block_end) {
            let source_index = clip.source_offset + (position - clip.start_sample);
            let Ok(offset) = usize::try_from(source_index - source.source_start) else {
                continue;
            };
            if offset >= length {
                continue;
            }
            let volume = clip_volume(clip, keys, position);
            let frame = &samples[offset * channels..][..channels];
            let at = (position - start_sample) as usize * out_channels;
            for (channel, destination) in out[at..at + out_channels].iter_mut().enumerate() {
                // Pan applies on a stereo bus only; any other geometry
                // passes through. The order of the products is the Dart
                // reference's.
                let factor = match (out_channels, channel) {
                    (2, 0) => clip.pan_left,
                    (2, _) => clip.pan_right,
                    _ => 1.0,
                };
                *destination += f64::from(frame[source_channel(channels, channel)]) * volume * factor;
            }
        }
    }
}

/// The output stage to float: the bus as it is, narrowed.
pub fn bus_to_float(bus: &[f64], out: &mut [f32]) {
    for (value, out) in bus.iter().zip(out) {
        *out = *value as f32;
    }
}

/// The output stage to 16-bit: clipped to ±1 and scaled by 32768, not
/// 32767 — a decoder hands raw/32768, so unity gain gives back the very
/// int16 the file held, -32768 included; only +1.0 needs the cap.
/// Rounding is half away from zero, as `llround` and Dart's `round()` do.
pub fn bus_to_int16(bus: &[f64], out: &mut [i16]) {
    for (value, out) in bus.iter().zip(out) {
        let clipped = if *value > 1.0 {
            1.0
        } else if *value < -1.0 {
            -1.0
        } else {
            *value
        };
        *out = ((clipped * 32768.0).round() as i64).min(32767) as i16;
    }
}

/// `items` as a slice, empty when null or not positive.
///
/// # Safety
/// `items` is null or points at `count` values.
pub unsafe fn slice_or_empty<'a, T>(items: *const T, count: i32) -> &'a [T] {
    // No slice of nothing: an empty one still wants an aligned pointer,
    // and the C reads none when the count is 0 (so a mutant dropping
    // `count > 0` lives on every aligned pointer — kept on purpose).
    match usize::try_from(count) {
        // SAFETY: the caller's contract.
        Ok(count) if count > 0 && !items.is_null() => unsafe { slice::from_raw_parts(items, count) },
        _ => &[],
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn qa_audio_clip_sizeof() -> i32 {
    size_of::<Clip>() as i32
}

#[unsafe(no_mangle)]
pub extern "C" fn qa_audio_source_sizeof() -> i32 {
    size_of::<Source>() as i32
}

#[unsafe(no_mangle)]
pub extern "C" fn qa_audio_envelope_key_sizeof() -> i32 {
    size_of::<EnvelopeKey>() as i32
}

/// [`mix`] for C: `sample_count` x `out_channels` doubles into `out`,
/// untouched when there is no bus to write.
///
/// # Safety
/// Each pointer is null or points at its count of values; `out` at
/// `sample_count` x `out_channels` doubles; the sources as [`mix`] says.
#[unsafe(no_mangle)]
#[allow(clippy::too_many_arguments)]
pub unsafe extern "C" fn qa_audio_mix(
    clips: *const Clip,
    clip_count: i32,
    sources: *const Source,
    source_count: i32,
    envelope_keys: *const EnvelopeKey,
    envelope_key_count: i32,
    start_sample: i64,
    sample_count: i32,
    out_channels: i32,
    out: *mut f64,
) {
    let (Ok(samples), Ok(channels)) = (usize::try_from(sample_count), usize::try_from(out_channels)) else {
        return;
    };
    // An empty bus is no slice (see `slice_or_empty`).
    if out.is_null() || samples == 0 || channels == 0 {
        return;
    }
    // SAFETY: the caller's contract.
    unsafe {
        let out = slice::from_raw_parts_mut(out, samples * channels);
        let clips = slice_or_empty(clips, clip_count);
        let sources = slice_or_empty(sources, source_count);
        let keys = slice_or_empty(envelope_keys, envelope_key_count);
        mix(clips, sources, keys, start_sample, channels, out);
    }
}

/// [`bus_to_float`] for C.
///
/// # Safety
/// `bus` and `out` are null or point at `count` values.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qa_audio_bus_to_float(bus: *const f64, count: i32, out: *mut f32) {
    // SAFETY: the caller's contract.
    let bus = unsafe { slice_or_empty(bus, count) };
    if out.is_null() || bus.is_empty() {
        return;
    }
    // SAFETY: the caller's contract.
    bus_to_float(bus, unsafe { slice::from_raw_parts_mut(out, bus.len()) });
}

/// [`bus_to_int16`] for C.
///
/// # Safety
/// `bus` and `out` are null or point at `count` values.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qa_audio_bus_to_int16(bus: *const f64, count: i32, out: *mut i16) {
    // SAFETY: the caller's contract.
    let bus = unsafe { slice_or_empty(bus, count) };
    if out.is_null() || bus.is_empty() {
        return;
    }
    // SAFETY: the caller's contract.
    bus_to_int16(bus, unsafe { slice::from_raw_parts_mut(out, bus.len()) });
}
