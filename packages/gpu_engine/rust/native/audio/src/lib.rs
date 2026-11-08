//! The engine's sound decoder (native-to-rust, 저장; ↩️the C engine's
//! `qa_audio_decode.c` until the connection round deleted it,
//! connection-round-checklist H, 2026-11-08): the sound of a container in a
//! span of a file — a loose file, a sound carried in
//! the project file, the soundtrack of a movie — decoded once, at import,
//! into interleaved float32 at its own rate. Nothing here is realtime: a
//! variable-length codec cannot promise to finish inside an audio callback,
//! and the callback cannot wait.
//!
//! The bundled decoders are symphonia's (native-to-rust-Q4, the user:
//! 「오디오는 symphonia 하나로」), where the C had dr_wav · dr_flac ·
//! dr_mp3 · stb_vorbis. What stays this engine's own is what the C decided
//! for itself: where a sound starts ([start]), a movie's uncompressed sound
//! ([movie_pcm]), the conversions a WAV's samples get ([convert]), and the
//! order the decoders are tried in ([stream]).
//!
//! 🚨★★★**THE POINT IS WHAT IS NOT HERE: the container in memory.** A
//! three-gigabyte movie whose sound is wanted is read through the one span
//! reader (`media::span`), a block at a time; nothing on this path holds
//! more than a decode block and one span block. 🪦There were two origins
//! until 2026-09-24: the span, and the container assembled in memory, which
//! existed only because a framed entry had no native reader — so Dart
//! decompressed the whole thing and handed it over, and the soundtrack of a
//! carried movie arrived as the whole movie in RAM. The span reader reads
//! framed spans itself, and the memory origin went with its reason. ⛔A
//! `qa_audio_decode_memory` that came back would be the copy this repo
//! keeps deleting.
//!
//! The tests hold every decode the bundled decoders make to the ledger —
//! the C's samples where it read whole numbers, this decoder's where it
//! computes — and what only the OS reads as its stage, channels and rate
//! (유저 connection-round-checklist-Q14). ↩️Until the connection round the C
//! was the answer key: every file was decoded by both.

// The checkout this crate is built from, different in each: a build that
// another checkout left in the shared target folder is built again here,
// never run as this one's (gpu_engine's kernels/shared/one_checkout.rs).
const _CHECKOUT: Option<&str> = option_env!("QA_CHECKOUT");

mod bundled;
mod container;
mod convert;
mod movie_pcm;
mod os;
mod start;
pub mod stream;
mod wav_family;

use std::alloc::{Layout, alloc, dealloc};
use std::ffi::{CStr, c_char};

use stream::{Stream, window};

/// Which decoder produced the samples — reported back so the caller can
/// say so in a log, and so a test can prove the right one was chosen. The
/// C's numbers, which Dart reads.
pub const FORMAT_UNKNOWN: i32 = 0;
pub const FORMAT_WAV: i32 = 1;
pub const FORMAT_FLAC: i32 = 2;
pub const FORMAT_MP3: i32 = 3;
/// The OS's own codec stack — the last stage, for what no bundled decoder
/// reads ([os], native-to-rust-Q6): Media Foundation on Windows, the NDK's
/// MediaCodec on Android, AudioToolbox on Apple's.
pub const FORMAT_OS: i32 = 4;
pub const FORMAT_VORBIS: i32 = 5;
/// A movie's uncompressed sound, read here on every platform.
pub const FORMAT_MOVIE_PCM: i32 = 6;
/// AAC-LC and ALAC, read by the bundled decoder where the C left every AAC
/// to the OS (4, 「the OS's own codec stack carried the file」 — which is what
/// it still means, for what the bundled decoder does not read:
/// native-to-rust-Q6). Dart's `QaAudioFormat` took them up at the connection
/// round.
pub const FORMAT_AAC: i32 = 7;
pub const FORMAT_ALAC: i32 = 8;

/// `qa_audio_stream_open`.
///
/// # Safety
/// `path` is null or a NUL-terminated string; each out pointer null or
/// writable.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qa_audio_stream_open(
    path: *const c_char,
    offset: i64,
    length: i64,
    framed: i32,
    out_format: *mut i32,
    out_channels: *mut i32,
    out_sample_rate: *mut i32,
) -> *mut Stream {
    // SAFETY: the caller's contract.
    let (Some(format), Some(channels), Some(rate)) =
        (unsafe { out_format.as_mut() }, unsafe { out_channels.as_mut() }, unsafe { out_sample_rate.as_mut() })
    else {
        return std::ptr::null_mut();
    };
    *format = FORMAT_UNKNOWN;
    *channels = 0;
    *rate = 0;
    if path.is_null() {
        return std::ptr::null_mut();
    }
    // SAFETY: the caller's contract.
    let path = unsafe { CStr::from_ptr(path) };
    let Some(stream) = Stream::open(path, offset, length, framed != 0) else {
        return std::ptr::null_mut();
    };
    *format = stream.format();
    *channels = stream.channels();
    *rate = stream.sample_rate();
    Box::into_raw(Box::new(stream))
}

/// `qa_audio_stream_read`: up to `frames` more frames of the sound into
/// `out` — how many, short only at the sound's end, 0 past it; -1 for a
/// stream or a buffer that is not there.
///
/// # Safety
/// `stream` is null or one [qa_audio_stream_open] answered and not closed;
/// `out` is null or holds `frames` frames.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qa_audio_stream_read(stream: *mut Stream, out: *mut f32, frames: i64) -> i64 {
    // SAFETY: the caller's contract.
    let Some(stream) = (unsafe { stream.as_mut() }) else { return -1 };
    if out.is_null() || frames < 0 {
        return -1;
    }
    // SAFETY: the caller's contract.
    let out = unsafe { std::slice::from_raw_parts_mut(out, frames as usize * stream.channels() as usize) };
    stream.pass(Some(out), frames)
}

/// `qa_audio_stream_close`.
///
/// # Safety
/// `stream` as for [qa_audio_stream_read]; not used after.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qa_audio_stream_close(stream: *mut Stream) {
    if !stream.is_null() {
        // SAFETY: the caller's contract — one of ours, closed once.
        drop(unsafe { Box::from_raw(stream) });
    }
}

/// Room before a buffer handed over: its sample count, so that
/// [qa_audio_decode_free] — which is handed the samples alone — lets go of
/// what was allocated.
const PREFIX: usize = 16;

fn layout_of(samples: usize) -> Layout {
    Layout::from_size_align(PREFIX + samples * size_of::<f32>(), PREFIX).expect("a buffer the size of a sound")
}

/// `samples` in a buffer of their own, for the caller to hand back to
/// [qa_audio_decode_free].
fn hand_over(samples: &[f32]) -> *mut f32 {
    let layout = layout_of(samples.len());
    // SAFETY: the layout is never zero-sized; the count goes in the prefix,
    // the samples after it, both inside the allocation.
    unsafe {
        let base = alloc(layout);
        if base.is_null() {
            std::alloc::handle_alloc_error(layout);
        }
        base.cast::<usize>().write(samples.len());
        let at = base.add(PREFIX).cast::<f32>();
        at.copy_from_nonoverlapping(samples.as_ptr(), samples.len());
        at
    }
}

/// `qa_audio_decode_span_window`: the container's `window_count` frames of
/// sound from frame `window_start` ([window]). The format that read it, or 0
/// when nothing could; on success the caller owns `*out_samples` (null when
/// no frames came) and lets it go with [qa_audio_decode_free].
///
/// # Safety
/// `path` is null or a NUL-terminated string; each out pointer null or
/// writable.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qa_audio_decode_span_window(
    path: *const c_char,
    offset: i64,
    length: i64,
    framed: i32,
    window_start: i64,
    window_count: i64,
    out_samples: *mut *mut f32,
    out_frame_count: *mut i64,
    out_channels: *mut i32,
    out_sample_rate: *mut i32,
) -> i32 {
    // SAFETY: the caller's contract.
    let outs = unsafe { (out_samples.as_mut(), out_frame_count.as_mut(), out_channels.as_mut(), out_sample_rate.as_mut()) };
    let (Some(samples), Some(frames), Some(channels), Some(rate)) = outs else {
        return FORMAT_UNKNOWN;
    };
    *samples = std::ptr::null_mut();
    *frames = 0;
    *channels = 0;
    *rate = 0;
    if path.is_null() {
        return FORMAT_UNKNOWN;
    }
    // SAFETY: the caller's contract.
    let path = unsafe { CStr::from_ptr(path) };
    let Some(sound) = window(path, offset, length, framed != 0, window_start, window_count) else {
        return FORMAT_UNKNOWN;
    };
    // A window past the sound's end kept nothing, and that is an answer.
    if !sound.samples.is_empty() {
        *samples = hand_over(&sound.samples);
    }
    *frames = (sound.samples.len() / sound.channels as usize) as i64;
    *channels = sound.channels;
    *rate = sound.sample_rate;
    sound.format
}

/// `qa_audio_decode_span`: the whole sound of the container —
/// [qa_audio_decode_span_window] from frame 0 to the end.
///
/// # Safety
/// As for [qa_audio_decode_span_window].
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qa_audio_decode_span(
    path: *const c_char,
    offset: i64,
    length: i64,
    framed: i32,
    out_samples: *mut *mut f32,
    out_frame_count: *mut i64,
    out_channels: *mut i32,
    out_sample_rate: *mut i32,
) -> i32 {
    // SAFETY: the caller's contract, passed on.
    unsafe {
        qa_audio_decode_span_window(
            path,
            offset,
            length,
            framed,
            0,
            -1,
            out_samples,
            out_frame_count,
            out_channels,
            out_sample_rate,
        )
    }
}

/// `qa_audio_decode_free`: lets go of samples [qa_audio_decode_span_window]
/// handed over.
///
/// # Safety
/// `samples` is null or a buffer it handed over, not freed before.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qa_audio_decode_free(samples: *mut f32) {
    if samples.is_null() {
        return;
    }
    // SAFETY: the caller's contract — the prefix [hand_over] wrote sits
    // before the samples, and says the layout it allocated.
    unsafe {
        let base = samples.cast::<u8>().sub(PREFIX);
        let count = base.cast::<usize>().read();
        dealloc(base, layout_of(count));
    }
}

#[cfg(test)]
mod tests;
