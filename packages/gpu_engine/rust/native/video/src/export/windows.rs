//! Windows: Media Foundation's Sink Writer. The writer owns the H.264 and
//! AAC encoder MFTs AND the MP4 muxing; RGB32 input is converted to the
//! encoder's YUV by MF's own color converter. Our only pixel job is
//! RGBA → BGRA (MFVideoFormat_RGB32 is BGRA in memory) plus the even-size
//! pad H.264 requires.

use std::sync::Mutex;

use windows::Win32::Media::MediaFoundation::*;
use windows::Win32::System::Com::CoTaskMemFree;
use windows::core::{GUID, PCWSTR, Result};

use super::{CODEC_H264, CODEC_HEVC, CONTAINER_MP4, Job, bitrate, lock, set_error};
use crate::hardware_law;

pub const SUPPORTED: bool = true;

/// 100 ns units per second, Media Foundation's clock.
const TICKS: i64 = 10_000_000;

struct Writer {
    writer: IMFSinkWriter,
    video_stream: u32,
    audio_stream: u32,
    src_width: usize,
    src_height: usize,
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
    let Some(path) = job.path.filter(|_| {
        held.is_none()
            && job.width > 0
            && job.height > 0
            && job.fps_num > 0
            && job.fps_den > 0
            && job.channels >= 0
            && (job.channels == 0 || job.sample_rate > 0)
    }) else {
        set_error("video export: bad open parameters");
        return false;
    };
    if job.container != CONTAINER_MP4 || (job.codec != CODEC_H264 && job.codec != CODEC_HEVC) {
        set_error("video export: Windows writes MP4 H.264/H.265 here - MOV/ProRes go through FFmpeg");
        return false;
    }
    if !media::media_foundation::up() {
        set_error("video export: Media Foundation failed to start");
        return false;
    }
    let Some(wide) = media::path::wide(path) else {
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
    let Ok(video_stream) = video_stream(&writer, job, width, height) else {
        set_error(if hevc {
            "video export: no H.265 encoder on this machine"
        } else {
            "video export: no H.264 encoder accepted the frames"
        });
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
        video_stream,
        audio_stream,
        src_width: job.width as usize,
        src_height: job.height as usize,
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

/// A video type of this job's frame size, rate and square pixels — and its
/// bitrate, for the encoded one. The attributes go in the C's order.
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
        let input = video_type(&MFVideoFormat_RGB32, None, width, height, job)?;
        // Positive default stride = top-down rows, which is what the
        // renderer produces; MF's converter handles the flip to whatever
        // the encoder wants.
        let _ = input.SetUINT32(&MF_MT_DEFAULT_STRIDE, (width * 4) as u32);
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

/// RGBA (renderer) → BGRA (MF RGB32), top-down; padding pixels white so an
/// odd canvas gains a hairline of paper, not garbage.
fn bgra(rgba: &[u8], writer: &Writer, target: &mut [u8]) {
    for (y, out_row) in target.chunks_exact_mut(writer.width * 4).enumerate() {
        if y >= writer.src_height {
            out_row.fill(0xFF);
            continue;
        }
        let in_row = &rgba[y * writer.src_width * 4..][..writer.src_width * 4];
        let (picture, pad) = out_row.split_at_mut(writer.src_width * 4);
        for (out, pixel) in picture.chunks_exact_mut(4).zip(in_row.chunks_exact(4)) {
            out.copy_from_slice(&[pixel[2], pixel[1], pixel[0], 0xFF]);
        }
        pad.fill(0xFF);
    }
}

/// The frame's timestamp in 100 ns units — integer arithmetic on the exact
/// fps fraction, the same discipline as every frame/sample conversion.
fn frame_time(writer: &Writer, frame: i64) -> i64 {
    frame * TICKS * writer.fps_den / writer.fps_num
}

/// # Safety
/// `rgba` is null or holds the frame `open` was given.
pub unsafe fn write_frame(rgba: *const u8) -> bool {
    let mut held = lock(&WRITER);
    let Some(writer) = held.as_mut().filter(|_| !rgba.is_null()) else {
        return false;
    };
    // SAFETY: the caller's contract.
    let rgba = unsafe { std::slice::from_raw_parts(rgba, writer.src_width * writer.src_height * 4) };
    let time = frame_time(writer, writer.frame_index);
    let next = frame_time(writer, writer.frame_index + 1);
    let bytes = (writer.width * writer.height * 4) as u32;
    match write_sample(writer, writer.video_stream, bytes, (time, next - time), |target| bgra(rgba, writer, target)) {
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

/// # Safety
/// `interleaved` is null or holds `frames` × the channels `open` was given.
pub unsafe fn write_audio(interleaved: *const i16, frames: i32) -> bool {
    let mut held = lock(&WRITER);
    let Some(writer) = held.as_mut().filter(|writer| writer.channels > 0 && !interleaved.is_null() && frames > 0)
    else {
        return false;
    };
    let bytes = frames as usize * writer.channels * 2;
    // SAFETY: the caller's contract.
    let pcm = unsafe { std::slice::from_raw_parts(interleaved.cast::<u8>(), bytes) };
    let time = writer.audio_samples * TICKS / writer.sample_rate;
    let duration = i64::from(frames) * TICKS / writer.sample_rate;
    match write_sample(writer, writer.audio_stream, bytes as u32, (time, duration), |target| target.copy_from_slice(pcm)) {
        Written::NoBuffer | Written::NotLocked => {}
        Written::Refused => set_error("video export: an audio chunk failed to encode"),
        Written::Taken => {
            writer.audio_samples += i64::from(frames);
            return true;
        }
    }
    false
}

pub fn finish() -> bool {
    let Some(writer) = lock(&WRITER).take() else {
        return false;
    };
    // SAFETY: a writer that began.
    if unsafe { writer.writer.Finalize() }.is_err() {
        set_error("video export: the MP4 failed to finalize");
        return false;
    }
    true
}

pub fn abort() {
    lock(&WRITER).take();
}
