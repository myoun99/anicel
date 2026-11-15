//! Windows: Media Foundation's Sink Writer. The writer owns the H.264 and
//! AAC encoder MFTs AND the MP4 muxing. Its pictures go in as NV12, each
//! padded even as H.264 requires, and its types say what they are: an
//! export's in the app's colour law (`colour`, BT.601 studio range) as the
//! GPU engine made them, a trimmed piece's as its movie's decoder made
//! them, named as that movie names them — both through `write_nv12`.
//! ↩️RGBA was made NV12 here too (`write_frame`) till 2026-11-15.
//!
//! ↩️Till 2026-11-14 the RGBA of both went in as RGB32 — made BGRA here,
//! then YUV by Media Foundation's own converter: two passes on the CPU a
//! frame, after a readback of four bytes a pixel where NV12 is one and a
//! half (board the-video-export-converts-colour-on-the-cpu-off-android-and-
//! apple-h26x). It kept its own conversion because its writer and reader
//! agreed (`colour`); they agree as closely in the app's, once the types
//! name all of it ([`video_type`]) — a flat colour back within 3 a channel
//! at 1920×1080 and 256×144, where its own came back within 2 (measured
//! on Surface that day).

use std::path::PathBuf;
use std::sync::Mutex;

use windows::Win32::Media::MediaFoundation::*;
use windows::Win32::System::Com::CoTaskMemFree;
use windows::core::{GUID, PCWSTR, Result};

use super::nv12::{self, Nv12};
use super::{BAD_OPEN, CODEC_H264, CODEC_HEVC, CONTAINER_MP4, H26X_TAKES_NV12, Job, bitrate, edit_list, lock, set_error};
use crate::colour::{Planes, media_foundation};
use crate::hardware_law;

pub const SUPPORTED: bool = true;

/// 100 ns units per second, Media Foundation's clock.
const TICKS: i64 = 10_000_000;

struct Writer {
    writer: IMFSinkWriter,
    /// Where the movie is written: its boxes are gone back to once the sink
    /// has finished ([finish]).
    path: PathBuf,
    video_stream: u32,
    audio_stream: u32,
    /// Padded even.
    width: usize,
    height: usize,
    fps_num: i64,
    fps_den: i64,
    frame_index: i64,
    audio_samples: i64,
    sample_rate: i64,
    channels: usize,
}

// SAFETY: the sink writer is a free-threaded MF object, and the one export
// is called from whichever thread Dart is on, one call at a time under the
// lock — as the C's process global was.
unsafe impl Send for Writer {}

static WRITER: Mutex<Option<Writer>> = Mutex::new(None);

/// Media Foundation writes MP4; H.264 always ships, HEVC only where an
/// encoder MFT exists (usually hardware). MOV/ProRes have no MF story — the
/// ffmpeg fallback carries those on desktop.
pub fn probe(container: i32, codec: i32) -> bool {
    if container != CONTAINER_MP4 {
        return false;
    }
    if codec == CODEC_H264 {
        return true;
    }
    codec == CODEC_HEVC && media::media_foundation::up() && hevc_encoders() > 0
}

fn hevc_encoders() -> u32 {
    let out_type = MFT_REGISTER_TYPE_INFO { guidMajorType: MFMediaType_Video, guidSubtype: MFVideoFormat_HEVC };
    let mut activates: *mut Option<IMFActivate> = std::ptr::null_mut();
    let mut count = 0u32;
    // SAFETY: the out pointers are locals; what comes back is released
    // below, each activate and then the array.
    let found = unsafe {
        MFTEnumEx(
            MFT_CATEGORY_VIDEO_ENCODER,
            MFT_ENUM_FLAG_HARDWARE | MFT_ENUM_FLAG_SYNCMFT | MFT_ENUM_FLAG_ASYNCMFT | MFT_ENUM_FLAG_SORTANDFILTER,
            None,
            Some(&out_type),
            &mut activates,
            &mut count,
        )
    };
    if !activates.is_null() {
        // SAFETY: MFTEnumEx handed back `count` activates in one block.
        unsafe {
            for i in 0..count as usize {
                activates.add(i).drop_in_place();
            }
            CoTaskMemFree(Some(activates.cast_const().cast()));
        }
    }
    if found.is_ok() { count } else { 0 }
}

pub fn open(job: &Job) -> bool {
    let mut held = lock(&WRITER);
    if held.is_some() {
        set_error(BAD_OPEN);
        return false;
    }
    let path = job.path;
    if job.container != CONTAINER_MP4 || (job.codec != CODEC_H264 && job.codec != CODEC_HEVC) {
        set_error("video export: Windows writes MP4 H.264/H.265 here - MOV/ProRes go through FFmpeg");
        return false;
    }
    if !media::media_foundation::up() {
        set_error("video export: Media Foundation failed to start");
        return false;
    }
    let (Some(wide), Some(file)) = (media::path::wide(path), media::path::file(path)) else {
        set_error("video export: the output path did not convert");
        return false;
    };
    let (width, height) = (job.width + (job.width & 1), job.height + (job.height & 1));
    let hevc = job.codec == CODEC_HEVC;
    // SAFETY: `wide` is NUL-terminated.
    let Ok(writer) = (unsafe { sink_writer(PCWSTR(wide.as_ptr()), hardware_law::may_encode(width, height, hevc)) }) else {
        set_error("video export: the MP4 file could not be created");
        return false;
    };
    // The size is named, not that the machine has no encoder: the main PC's
    // H.265 encoder (NVIDIA) turned away 64×48 where `probe` — which asks
    // no size — said it had one (관제 2026-11-15, board
    // trimmed-movie-decodes-to-nv12). ↩️「no H.265 encoder on this machine」.
    let Ok(video_stream) = video_stream(&writer, job, width, height) else {
        let name = if hevc { "H.265" } else { "H.264" };
        set_error(&format!("video export: no {name} encoder accepted {width}x{height} frames"));
        return false;
    };
    let audio_stream = if job.channels > 0 {
        let Ok(stream) = audio_stream(&writer, job) else {
            set_error("video export: no AAC encoder accepted the mix");
            return false;
        };
        stream
    } else {
        0
    };
    // SAFETY: a writer with its streams set.
    if unsafe { writer.BeginWriting() }.is_err() {
        set_error("video export: the writer refused to begin");
        return false;
    }
    *held = Some(Writer {
        writer,
        path: file,
        video_stream,
        audio_stream,
        width: width as usize,
        height: height as usize,
        fps_num: i64::from(job.fps_num),
        fps_den: i64::from(job.fps_den),
        frame_index: 0,
        audio_samples: 0,
        sample_rate: i64::from(job.sample_rate),
        channels: job.channels as usize,
    });
    true
}

/// The writer for `path`.
///
/// Hardware transforms ON: Windows ships NO software HEVC encoder MFT, and
/// the sink writer only reaches the hardware (async) ones through this
/// attribute. H.264 keeps working either way (HW first, the software MFT as
/// ever when there is none).
/// ↩️2026-10-08: 「either way」 was not true of a SMALL H.264 job — an Intel
/// hardware transform takes a 64×48 job and fails it at Finalize. Which jobs
/// may ask is [`hardware_law::may_encode`]'s to say.
///
/// # Safety
/// `path` is NUL-terminated.
unsafe fn sink_writer(path: PCWSTR, hardware: bool) -> Result<IMFSinkWriter> {
    let mut attributes = None;
    // SAFETY: `attributes` is a local; the attribute is set on what came back.
    if hardware && unsafe { MFCreateAttributes(&mut attributes, 1) }.is_ok() {
        if let Some(attributes) = &attributes {
            // The C ignored this answer too: a writer without it is still
            // a writer, in software.
            let _ = unsafe { attributes.SetUINT32(&MF_READWRITE_ENABLE_HARDWARE_TRANSFORMS, 1) };
        }
    }
    // SAFETY: the caller's contract.
    unsafe { MFCreateSinkWriterFromURL(path, None, attributes.as_ref()) }
}

/// A video type of this job's frame size, rate and square pixels, named as
/// its pictures are (`Job::named` — the app's colour law, or a piece's
/// movie's) — and its bitrate, for the encoded one. The attributes go in
/// the C's order, the colours after them.
fn video_type(subtype: &GUID, bitrate: Option<u32>, width: i32, height: i32, job: &Job) -> Result<IMFMediaType> {
    // SAFETY: setting attributes on a type of our own.
    unsafe {
        let media_type = MFCreateMediaType()?;
        // The C set these unchecked: a type that would not take them is
        // turned away by the writer it is offered to.
        let _ = media_type.SetGUID(&MF_MT_MAJOR_TYPE, &MFMediaType_Video);
        let _ = media_type.SetGUID(&MF_MT_SUBTYPE, subtype);
        if let Some(bitrate) = bitrate {
            let _ = media_type.SetUINT32(&MF_MT_AVG_BITRATE, bitrate);
        }
        let _ = media_type.SetUINT64(&MF_MT_FRAME_SIZE, ((width as u64) << 32) | height as u32 as u64);
        let _ = media_type.SetUINT64(&MF_MT_FRAME_RATE, (u64::from(job.fps_num as u32) << 32) | u64::from(job.fps_den as u32));
        let _ = media_type.SetUINT64(&MF_MT_PIXEL_ASPECT_RATIO, (1 << 32) | 1);
        let _ = media_type.SetUINT32(&MF_MT_INTERLACE_MODE, MFVideoInterlace_Progressive.0 as u32);
        // 🚨WHAT THE PICTURES ARE, ALL FOUR NAMED AS EVERY WRITER NAMES
        // THEM (`colour`), OR A READER GUESSES. 🔬Measured on Surface
        // (2026-11-14), the app's reader asking Media Foundation for RGB32:
        // with no transfer named the matrix did not reach the movie, and a
        // 1920×1080 one read as BT.709 — green 200 came back 173. With all
        // four, within 3 (`tests/decode.rs`). SMPTE C's primaries are
        // SMPTE170M here: named SMPTE_C, the muxer wrote 8 — generic film —
        // in the file's `colr` (export tests), and the readers took those
        // two ways: Surface's (Intel) converted from them beside BT.709's
        // transfer, darks 16 brighter; the main PC's (NVIDIA) dropped the
        // colour named and read HD as BT.709's matrix, green +13, whatever
        // the transfer. ↩️So the transfer was sRGB's for a day.
        // A piece names its movie's four instead, and none the movie does
        // not name (`colour`; the table names SMPTE170M, not SMPTE_C).
        media_foundation::name(&media_type, job.named());
        Ok(media_type)
    }
}

fn video_stream(writer: &IMFSinkWriter, job: &Job, width: i32, height: i32) -> Result<u32> {
    let subtype = if job.codec == CODEC_HEVC { MFVideoFormat_HEVC } else { MFVideoFormat_H264 };
    let bitrate = bitrate(job.bitrate_bps, width, height, job.fps_num, job.fps_den) as u32;
    let out = video_type(&subtype, Some(bitrate), width, height, job)?;
    // SAFETY: setting attributes on types of our own, offered to the writer.
    unsafe {
        let stream = writer.AddStream(&out)?;
        let input = video_type(&MFVideoFormat_NV12, None, width, height, job)?;
        // Top-down rows, the frame's width apart ([`planes_of`]).
        let _ = input.SetUINT32(&MF_MT_DEFAULT_STRIDE, width as u32);
        writer.SetInputMediaType(stream, &input, None)?;
        Ok(stream)
    }
}

/// An audio type of this job's rate and channels, 16 bits a sample.
fn audio_type(subtype: &GUID, job: &Job) -> Result<IMFMediaType> {
    // SAFETY: setting attributes on a type of our own.
    unsafe {
        let media_type = MFCreateMediaType()?;
        let _ = media_type.SetGUID(&MF_MT_MAJOR_TYPE, &MFMediaType_Audio);
        let _ = media_type.SetGUID(&MF_MT_SUBTYPE, subtype);
        let _ = media_type.SetUINT32(&MF_MT_AUDIO_BITS_PER_SAMPLE, 16);
        let _ = media_type.SetUINT32(&MF_MT_AUDIO_SAMPLES_PER_SECOND, job.sample_rate as u32);
        let _ = media_type.SetUINT32(&MF_MT_AUDIO_NUM_CHANNELS, job.channels as u32);
        Ok(media_type)
    }
}

fn audio_stream(writer: &IMFSinkWriter, job: &Job) -> Result<u32> {
    let out = audio_type(&MFAudioFormat_AAC, job)?;
    // SAFETY: setting attributes on types of our own, offered to the writer.
    unsafe {
        // 24000 bytes/s = 192 kbit/s — the AAC encoder's highest standard
        // step; a mixed master deserves it.
        let _ = out.SetUINT32(&MF_MT_AUDIO_AVG_BYTES_PER_SECOND, 24000);
        let stream = writer.AddStream(&out)?;
        let input = audio_type(&MFAudioFormat_PCM, job)?;
        let _ = input.SetUINT32(&MF_MT_AUDIO_BLOCK_ALIGNMENT, (job.channels * 2) as u32);
        let _ = input.SetUINT32(&MF_MT_AUDIO_AVG_BYTES_PER_SECOND, (job.sample_rate * job.channels * 2) as u32);
        writer.SetInputMediaType(stream, &input, None)?;
        Ok(stream)
    }
}

/// How far a sample got: the C told each step apart in what it said.
#[derive(PartialEq)]
enum Written {
    NoBuffer,
    NotLocked,
    Refused,
    Taken,
}

/// A buffer of `bytes` filled by `fill`, in a sample at `time` for
/// `duration`, written to `stream`.
fn write_sample(
    writer: &Writer,
    stream: u32,
    bytes: u32,
    (time, duration): (i64, i64),
    fill: impl FnOnce(&mut [u8]),
) -> Written {
    // SAFETY: the buffer is locked while `fill` writes its `bytes`, then
    // handed to a sample of our own.
    unsafe {
        let Ok(buffer) = MFCreateMemoryBuffer(bytes) else {
            return Written::NoBuffer;
        };
        let mut target = std::ptr::null_mut();
        if buffer.Lock(&mut target, None, None).is_err() {
            return Written::NotLocked;
        }
        fill(std::slice::from_raw_parts_mut(target, bytes as usize));
        let _ = buffer.Unlock();
        let _ = buffer.SetCurrentLength(bytes);
        let Ok(sample) = MFCreateSample() else {
            return Written::Refused;
        };
        let _ = sample.AddBuffer(&buffer);
        let _ = sample.SetSampleTime(time);
        let _ = sample.SetSampleDuration(duration);
        if writer.writer.WriteSample(stream, &sample).is_ok() { Written::Taken } else { Written::Refused }
    }
}

/// The frame's timestamp in 100 ns units — integer arithmetic on the exact
/// fps fraction, the same discipline as every frame/sample conversion.
fn frame_time(writer: &Writer, frame: i64) -> i64 {
    frame * TICKS * writer.fps_den / writer.fps_num
}

/// An NV12 buffer of `width` × `height` as `colour` lays a frame: the Y
/// rows, then the CbCr pairs side by side, every row `width` apart.
fn planes_of(width: usize, height: usize, target: &mut [u8]) -> Planes<'_> {
    let (y, chroma) = target.split_at_mut(width * height);
    Planes { y, y_stride: width, chroma, cb: 0, cr: 1, chroma_stride: width, chroma_step: 2 }
}

/// The writer's next frame, its NV12 laid by `fill` into the frame's
/// planes ([`planes_of`]).
fn picture(writer: &mut Writer, fill: impl FnOnce(&mut Planes)) -> bool {
    let time = frame_time(writer, writer.frame_index);
    let next = frame_time(writer, writer.frame_index + 1);
    let (width, height) = (writer.width, writer.height);
    let bytes = Nv12::bytes_of(width, height) as u32;
    match write_sample(writer, writer.video_stream, bytes, (time, next - time), |target| {
        fill(&mut planes_of(width, height, target));
    }) {
        Written::NoBuffer => set_error("video export: out of memory for a frame"),
        Written::NotLocked => {}
        Written::Refused => set_error("video export: a frame failed to encode"),
        Written::Taken => {
            writer.frame_index += 1;
            return true;
        }
    }
    false
}

/// Refused: this writer writes H.264 and H.265 alone, and they come as NV12
/// ([`write_nv12`], `H26X_TAKES_NV12`) — said where a job is open and a
/// frame handed; out of turn, refused without a word, as before. ↩️Till
/// 2026-11-15 RGBA was made NV12 here in the app's colour law, the
/// padding white.
///
/// # Safety
/// Nothing is read of `rgba`.
pub unsafe fn write_frame(rgba: *const u8) -> bool {
    if lock(&WRITER).is_some() && !rgba.is_null() {
        set_error(H26X_TAKES_NV12);
    }
    false
}

/// The frame the open writer takes as NV12: the encoder's, padded even.
pub fn nv12_shape() -> Option<(usize, usize)> {
    lock(&WRITER).as_ref().map(|writer| (writer.width, writer.height))
}

/// An export's frame as the GPU engine made it NV12, laid as it is.
///
/// # Safety
/// `bytes` is null or holds the frame `nv12_shape` says, rows `stride`
/// bytes apart.
pub unsafe fn write_nv12(bytes: *const u8, stride: i64) -> bool {
    let mut held = lock(&WRITER);
    let Some(writer) = held.as_mut().filter(|_| !bytes.is_null() && stride > 0) else {
        return false;
    };
    // SAFETY: the caller's contract.
    let Some(frame) = (unsafe { nv12::handed(bytes, stride as usize, writer.width, writer.height) }) else {
        return false;
    };
    picture(writer, |planes| nv12::lay(&frame, planes))
}

/// The frames this writer puts before the mix: one AAC frame.
///
/// 🚨★A FRAME BEFORE THE SOUND, AND AN EDIT LIST THAT TAKES IT OFF — AS FFMPEG
/// WRITES IT (유저 2026-11-10, board
/// an-mp4-reopened-loses-its-first-9-ms-of-sound-Q2: 「ffmpeg처럼하는게
/// 맘에들긴해. 더 좋기만 한거니까」). Media Foundation puts no AAC frame
/// before the sound (48,000 samples → 47 frames), so the first block's front
/// half has nothing to overlap: a sound that starts on the movie's first
/// sample comes back silent for 448 samples and rising until 576 (48 kHz,
/// measured 2026-11-10). So the first block is one the mix is not in — a
/// frame written as the stream's first sound, the mix after it — and once
/// the sink has finished, the movie is told that its sound starts after the
/// frame (`edit_list`). ⛔Stamped before zero the frame is taken and dropped
/// by the sink writer — the file comes out the same (measured) — so it is
/// written from zero, as sound.
///
/// ⚠️THE COST THE USER TOOK: Media Foundation's own reader ignores an edit
/// list's lead — it hands the first frame back at time 0 (measured on
/// `tone.m4a`) — so Windows' own players sound the whole mix a frame late
/// (21 ms at 48 kHz, half a frame of animation at 24), as they do an MP4
/// ffmpeg wrote. After Effects and Premiere put the frame in and say nothing
/// of it — 1,024 and 1,023 samples late wherever they are read (관제's
/// measurement on the main PC, 2026-11-10, on the same board card).
///
/// ↩️Until this, the same day: no frame and no list — 「그대로 둔다」,
/// 「윈도의 한계」 (-Q1) — for a list meant rewriting the boxes after
/// `Finalize`, which is what `edit_list` does now.
///
/// WHAT THE FRAME HOLDS: the sound just before the mix where the caller has
/// it ([write_lead]) — the option the user took reads 「무음, 범위 앞에 소리가
/// 있으면 그 소리」 — and silence where it has none. A mix that starts in the
/// middle of a wave comes back closer behind its own past than behind
/// silence: a 750 Hz cosine starting on its peak, the error of its first 128
/// samples 0.0045 behind silence and 0.0009 behind itself, its worst sample
/// 0.026 and 0.002 (unit scale, 48 kHz, measured 2026-11-10). A frame that is
/// not the mix's own past costs what silence does.
pub const AUDIO_LEAD: i64 = 1024;

/// `frames` of sound, filled by `fill`, as the stream's next — stamped from
/// how many it has had.
fn feed(writer: &mut Writer, frames: i64, fill: impl FnOnce(&mut [u8])) -> bool {
    let bytes = frames as usize * writer.channels * 2;
    let time = writer.audio_samples * TICKS / writer.sample_rate;
    let duration = frames * TICKS / writer.sample_rate;
    match write_sample(writer, writer.audio_stream, bytes as u32, (time, duration), fill) {
        Written::NoBuffer | Written::NotLocked => {}
        Written::Refused => set_error("video export: an audio chunk failed to encode"),
        Written::Taken => {
            writer.audio_samples += frames;
            return true;
        }
    }
    false
}

/// What a lead that is not the first frame is told: the list takes off
/// [AUDIO_LEAD], no more and no less, from the stream's start.
const NOT_THE_LEAD: &str = "video export: the sound before the mix is one frame, handed before any other";

/// The sound just before the mix, as the frame that goes first — in place
/// of the silence [write_audio] puts there when handed none.
///
/// # Safety
/// `interleaved` is null or holds `frames` × the channels `open` was given.
pub unsafe fn write_lead(interleaved: *const i16, frames: i32) -> bool {
    let mut held = lock(&WRITER);
    let Some(writer) = held.as_mut().filter(|writer| writer.channels > 0 && !interleaved.is_null()) else {
        return false;
    };
    if writer.audio_samples != 0 || i64::from(frames) != AUDIO_LEAD {
        set_error(NOT_THE_LEAD);
        return false;
    }
    // SAFETY: the caller's contract.
    let pcm = unsafe { std::slice::from_raw_parts(interleaved.cast::<u8>(), frames as usize * writer.channels * 2) };
    feed(writer, AUDIO_LEAD, |target| target.copy_from_slice(pcm))
}

/// The mix's next `frames`, as Media Foundation's AAC takes them — behind
/// the frame that goes first ([AUDIO_LEAD]): the caller's ([write_lead]),
/// or silence.
///
/// # Safety
/// `interleaved` is null or holds `frames` × the channels `open` was given.
pub unsafe fn write_audio(interleaved: *const i16, frames: i32) -> bool {
    let mut held = lock(&WRITER);
    let Some(writer) = held.as_mut().filter(|writer| writer.channels > 0 && !interleaved.is_null() && frames > 0)
    else {
        return false;
    };
    // SAFETY: the caller's contract.
    let pcm = unsafe { std::slice::from_raw_parts(interleaved.cast::<u8>(), frames as usize * writer.channels * 2) };
    if writer.audio_samples == 0 && !feed(writer, AUDIO_LEAD, |target| target.fill(0)) {
        return false;
    }
    feed(writer, i64::from(frames), |target| target.copy_from_slice(pcm))
}

/// Finalizes the movie and, where the mix went into it, goes back into the
/// file to say where its sound starts ([AUDIO_LEAD]). A movie that cannot be
/// told is a failed export: left as it is, its sound would play a frame
/// late everywhere with nothing in it to say so.
pub fn finish() -> bool {
    let Some(Writer { writer, path, audio_samples, sample_rate, .. }) = lock(&WRITER).take() else {
        return false;
    };
    // SAFETY: a writer that began.
    if unsafe { writer.Finalize() }.is_err() {
        set_error("video export: the MP4 failed to finalize");
        return false;
    }
    // The sink lets go of the file with its last reference.
    drop(writer);
    let kept = audio_samples - AUDIO_LEAD;
    if kept > 0 && edit_list::mark_the_lead(&path, sample_rate, AUDIO_LEAD, kept).is_none() {
        set_error("video export: the MP4's sound could not be told where it starts");
        return false;
    }
    true
}

pub fn abort() {
    lock(&WRITER).take();
}
