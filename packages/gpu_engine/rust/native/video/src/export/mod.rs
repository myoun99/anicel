//! The OS video encoder (AUDIO-PRO R7): frames + mixed PCM in, an H.264/AAC
//! MP4 out — through the operating system's own codec stack, no ffmpeg.
//!
//! Why this exists: the export pipeline's last external dependency was an
//! ffmpeg binary on PATH, which a tablet does not have and a fresh desktop
//! install often does not either. Every target OS ships hardware-backed
//! H.264+AAC encoding and an MP4 muxer as system API:
//!
//!   Windows  — Media Foundation's Sink Writer
//!   Apple    — AVAssetWriter
//!   Android  — NDK AMediaCodec + AMediaMuxer
//!
//! The contract with Dart (`lib/src/native/qa_video_encoder.dart`) is the
//! C's, unchanged:
//!   - `qa_video_export_supported()` answers whether THIS build/OS can, so
//!     the caller picks the ffmpeg fallback deliberately, never crashes.
//!   - `qa_video_export_probe(container, codec)` answers one PAIR (ABI v21):
//!     whether this platform could take that job — the format picker grays
//!     what the machine cannot write instead of failing at Export.
//!   - `open()` takes the frame geometry, the fps as an exact fraction, the
//!     audio shape (channels 0 = silent video), and the container/codec
//!     pair plus alpha and bitrate knobs (ABI v21). The audio codec follows
//!     the video codec: ProRes carries PCM (the delivery convention),
//!     H.264/H.265 carry AAC.
//!   - `write_frame()` takes top-down RGBA (exactly what the renderer's
//!     rawRgba hands over); any BGRA/NV12 conversion happens HERE, beside
//!     the encoder that wants it.
//!   - `write_audio()` takes interleaved int16 PCM chunks, interleaved with
//!     the frames by the caller so no side buffers the whole track.
//!   - `finish()` finalizes the file (a cancelled run finalizes a playable
//!     partial, matching the ffmpeg path's behavior); `abort()` discards.
//!
//! One export at a time, like the capture device: this is an offline render
//! driven by one dialog.

use std::ffi::{CStr, c_char};
use std::sync::{Mutex, MutexGuard};

#[cfg(target_os = "android")]
#[path = "android.rs"]
mod os;
#[cfg(target_vendor = "apple")]
#[path = "apple.rs"]
mod os;
#[cfg(not(any(windows, target_os = "android", target_vendor = "apple")))]
#[path = "none.rs"]
mod os;
#[cfg(windows)]
#[path = "windows.rs"]
mod os;

// The v10 lineup (ABI v21): MP4 = H.264/H.265, MOV = H.264 + ProRes. The
// Dart enums map 1:1 onto these values. What follows down to `Job` is the
// writers' — a build without one reads none of it.
#[cfg_attr(not(any(windows, target_os = "android", target_vendor = "apple")), allow(dead_code))]
const CONTAINER_MP4: i32 = 0;
#[cfg_attr(not(target_vendor = "apple"), allow(dead_code))]
const CONTAINER_MOV: i32 = 1;
#[cfg_attr(not(any(windows, target_os = "android", target_vendor = "apple")), allow(dead_code))]
const CODEC_H264: i32 = 0;
#[cfg_attr(not(any(windows, target_os = "android", target_vendor = "apple")), allow(dead_code))]
const CODEC_HEVC: i32 = 1;
// ProRes, lightest to heaviest; only Apple writes it.
#[cfg_attr(not(target_vendor = "apple"), allow(dead_code))]
const CODEC_PRORES_PROXY: i32 = 2;
#[cfg_attr(not(target_vendor = "apple"), allow(dead_code))]
const CODEC_PRORES_LT: i32 = 3;
#[cfg_attr(not(target_vendor = "apple"), allow(dead_code))]
const CODEC_PRORES_422: i32 = 4;
#[cfg_attr(not(target_vendor = "apple"), allow(dead_code))]
const CODEC_PRORES_HQ: i32 = 5;
#[cfg_attr(not(target_vendor = "apple"), allow(dead_code))]
const CODEC_PRORES_4444: i32 = 6;

/// What `open` was asked for, as Dart passed it.
#[cfg_attr(not(any(windows, target_os = "android", target_vendor = "apple")), allow(dead_code))]
struct Job<'a> {
    path: &'a CStr,
    width: i32,
    height: i32,
    fps_num: i32,
    fps_den: i32,
    sample_rate: i32,
    channels: i32,
    container: i32,
    codec: i32,
    /// Whether ProRes 4444 keeps the picture's alpha. MF and the NDK write
    /// H.26x, which is opaque: their pad/alpha byte stays 0xFF and YUV420
    /// carries no alpha.
    #[cfg_attr(not(target_vendor = "apple"), allow(dead_code))]
    alpha: bool,
    bitrate_bps: i32,
}

/// What an open says of a job it is not given — one that is no job at all,
/// or one asked for while the writer's other runs.
const BAD_OPEN: &str = "video export: bad open parameters";

impl Job<'_> {
    /// Whether this is a job at all: a picture, a frame rate, and sound —
    /// if any — at a rate. The path is the last of it, and a job without
    /// one is not built ([`qa_video_export_open`]).
    ///
    /// ↩️2026-11-07: ASKED ONCE, before any platform answers. It was asked
    /// inside each writer, the same line three times, and the platform with
    /// no writer (`none.rs`) never asked it: Linux CI said 「no OS encoder
    /// on this platform」 of sound at no rate where the three writers say
    /// 「bad open parameters」 (bundle GPU CI 1cca0c1de,
    /// `sound_at_no_rate_is_no_job`; CLAUDE.md 절대명령 2, 관제 11-07). The
    /// C's Linux stub answered so of every job and is not followed.
    ///
    /// 🚨ONE LAW FOR THE THREE WRITERS. The C spelled it once per platform,
    /// all three born in one commit (000cf76c4, AUDIO-PRO R7, 2026-07-21):
    /// Windows turned away sound at no rate, Android and Apple let it through
    /// to their encoders, and Android said 「unsupported or bad parameters」
    /// for the rest. Apple's writer joining Rust (2026-11-07) made it the
    /// third copy, and the copies became this — Windows's, the one that asks
    /// no encoder for sound it cannot have (관제 took the merge, 11-07). The
    /// app's own jobs never meet the difference: their sound is the mix WAV
    /// the export dialog wrote at the project's rate, and only a WAV whose
    /// header says 0 Hz would reach here (`ConformPcmStreamReader.overWav16`
    /// turns away no channels, not no rate).
    fn well_formed(&self) -> bool {
        self.width > 0
            && self.height > 0
            && self.fps_num > 0
            && self.fps_den > 0
            && self.channels >= 0
            && (self.channels == 0 || self.sample_rate > 0)
    }
}

/// What the C's buffer held: the message's first 255 bytes.
const ERROR_BYTES: usize = 255;

static ERROR: Mutex<Vec<u8>> = Mutex::new(Vec::new());

/// The one export's state, whoever holds it; a panic that poisoned it left
/// nothing half-done that the next caller could not tear down.
fn lock<T>(mutex: &Mutex<T>) -> MutexGuard<'_, T> {
    mutex.lock().unwrap_or_else(|poisoned| poisoned.into_inner())
}

fn set_error(message: &str) {
    let bytes = message.as_bytes();
    let mut error = lock(&ERROR);
    error.clear();
    error.extend_from_slice(&bytes[..bytes.len().min(ERROR_BYTES)]);
}

/// The last failure, UTF-8, for the export dialog to show verbatim: its
/// length, or -1 when there is nowhere to put it.
///
/// # Safety
/// `out` is null or holds `capacity` bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qa_video_export_error(out: *mut c_char, capacity: i32) -> i32 {
    if out.is_null() || capacity <= 1 {
        return -1;
    }
    let error = lock(&ERROR);
    let length = error.len().min(capacity as usize - 1);
    // SAFETY: the caller's contract; length + 1 ≤ capacity.
    unsafe {
        out.cast::<u8>().copy_from_nonoverlapping(error.as_ptr(), length);
        *out.add(length) = 0;
    }
    length as i32
}

#[unsafe(no_mangle)]
pub extern "C" fn qa_video_export_supported() -> i32 {
    os::SUPPORTED as i32
}

#[unsafe(no_mangle)]
pub extern "C" fn qa_video_export_probe(container: i32, codec: i32) -> i32 {
    os::probe(container, codec) as i32
}

/// # Safety
/// `utf8_path` is null or a NUL-terminated string.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qa_video_export_open(
    utf8_path: *const c_char,
    width: i32,
    height: i32,
    fps_num: i32,
    fps_den: i32,
    sample_rate: i32,
    channels: i32,
    container: i32,
    codec: i32,
    alpha: i32,
    bitrate_bps: i32,
) -> i32 {
    // SAFETY: the caller's contract.
    let path = (!utf8_path.is_null()).then(|| unsafe { CStr::from_ptr(utf8_path) });
    let alpha = alpha != 0;
    let job = path.map(|path| Job { path, width, height, fps_num, fps_den, sample_rate, channels, container, codec, alpha, bitrate_bps });
    let Some(job) = job.filter(|job| job.well_formed()) else {
        set_error(BAD_OPEN);
        return 0;
    };
    os::open(&job) as i32
}

/// # Safety
/// `rgba` is null or holds the frame `open` was given, top-down RGBA.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qa_video_export_write_frame(rgba: *const u8) -> i32 {
    // SAFETY: the caller's contract.
    unsafe { os::write_frame(rgba) as i32 }
}

/// # Safety
/// `interleaved` is null or holds `frames` × the channels `open` was given.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qa_video_export_write_audio(interleaved: *const i16, frames: i32) -> i32 {
    // SAFETY: the caller's contract.
    unsafe { os::write_audio(interleaved, frames) as i32 }
}

#[unsafe(no_mangle)]
pub extern "C" fn qa_video_export_finish() -> i32 {
    os::finish() as i32
}

#[unsafe(no_mangle)]
pub extern "C" fn qa_video_export_abort() {
    os::abort();
}

/// Bits per second for a job that names none: bits per pixel per frame in
/// the range screen content wants. 0.12 bpp lands ~7 Mbit/s at 1080p24 —
/// visually clean for line art — clamped so tiny and huge canvases both
/// stay sane.
#[cfg_attr(not(any(windows, target_os = "android")), allow(dead_code))]
fn bitrate(job_bps: i32, width: i32, height: i32, fps_num: i32, fps_den: i32) -> i64 {
    let bitrate = if job_bps > 0 {
        i64::from(job_bps)
    } else {
        (f64::from(width) * f64::from(height) * f64::from(fps_num) / f64::from(fps_den) * 0.12) as i64
    };
    bitrate.clamp(2_000_000, 50_000_000)
}

#[cfg(test)]
mod tests;
