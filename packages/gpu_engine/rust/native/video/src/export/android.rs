//! Android: NDK AMediaCodec (H.264 + AAC) and AMediaMuxer, through `ndk-sys`
//! — the NDK's own headers, never a hand table (media's `served_span.rs`).
//! Color conversion RGBA → YUV420 happens here, in the app's colour law
//! (`crate::colour`) — hardware encoders overwhelmingly accept
//! COLOR_FormatYUV420SemiPlanar; the planar variant is the fallback.
//!
//! 🪦The C once resolved its own NDK table, and its constants were wrong
//! where it mattered: 「output format changed」 was spelled -1012 and
//! 「buffers changed」 -1014, where the NDK says -2 and -3. A format change is
//! the moment a codec's track can be ADDED to the muxer, so no track was ever
//! added and the muxer never started — Android export had not been able to
//! finish a file since that backend was written (#646).

use std::collections::VecDeque;
use std::ffi::c_int;
use std::ptr::null_mut;
use std::sync::Mutex;

use ndk_sys::{
    AMEDIACODEC_BUFFER_FLAG_CODEC_CONFIG, AMEDIACODEC_BUFFER_FLAG_END_OF_STREAM, AMEDIACODEC_CONFIGURE_FLAG_ENCODE,
    AMEDIACODEC_INFO_OUTPUT_BUFFERS_CHANGED, AMEDIACODEC_INFO_OUTPUT_FORMAT_CHANGED, AMEDIACODEC_INFO_TRY_AGAIN_LATER,
    AMEDIAFORMAT_KEY_AAC_PROFILE, AMEDIAFORMAT_KEY_BIT_RATE, AMEDIAFORMAT_KEY_CHANNEL_COUNT,
    AMEDIAFORMAT_KEY_COLOR_FORMAT, AMEDIAFORMAT_KEY_FRAME_RATE, AMEDIAFORMAT_KEY_HEIGHT,
    AMEDIAFORMAT_KEY_I_FRAME_INTERVAL, AMEDIAFORMAT_KEY_MIME, AMEDIAFORMAT_KEY_SAMPLE_RATE, AMEDIAFORMAT_KEY_WIDTH,
    AMediaCodec, AMediaCodec_configure, AMediaCodec_createEncoderByType, AMediaCodec_delete,
    AMediaCodec_dequeueInputBuffer, AMediaCodec_dequeueOutputBuffer, AMediaCodec_getInputBuffer,
    AMediaCodec_getOutputBuffer, AMediaCodec_getOutputFormat, AMediaCodec_queueInputBuffer,
    AMediaCodec_releaseOutputBuffer, AMediaCodec_start, AMediaCodec_stop, AMediaCodecBufferInfo, AMediaFormat_delete,
    AMediaFormat_new, AMediaFormat_setInt32, AMediaFormat_setString, AMediaMuxer, AMediaMuxer_addTrack,
    AMediaMuxer_delete, AMediaMuxer_new, AMediaMuxer_start, AMediaMuxer_stop, AMediaMuxer_writeSampleData,
    OutputFormat, media_status_t,
};

use super::{BAD_OPEN, CODEC_H264, CODEC_HEVC, CONTAINER_MP4, Job, bitrate, lock, set_error};
use crate::colour::{self, Picture, Planes};

const AMEDIA_OK: media_status_t = media_status_t::AMEDIA_OK;

/// What a codec has not filled in yet.
const NO_INFO: AMediaCodecBufferInfo = AMediaCodecBufferInfo { offset: 0, size: 0, presentationTimeUs: 0, flags: 0 };

pub const SUPPORTED: bool = true;

/// COLOR_FormatYUV420SemiPlanar (NV12) — what hardware encoders
/// overwhelmingly take — and COLOR_FormatYUV420Planar (I420), the fallback.
const SEMI_PLANAR: i32 = 21;
const PLANAR: i32 = 19;

/// How long a codec may keep us waiting for an input buffer, in µs.
const INPUT_WAIT_US: i64 = 100_000;

#[derive(Clone, Copy, PartialEq)]
enum Track {
    Video,
    Audio,
}

/// One deferred encoder sample: output that arrived before the muxer had
/// every track and could start.
struct Pending {
    track: Track,
    info: AMediaCodecBufferInfo,
    data: Vec<u8>,
}

struct Writer {
    video_codec: *mut AMediaCodec,
    audio_codec: *mut AMediaCodec,
    muxer: *mut AMediaMuxer,
    fd: c_int,
    muxer_started: bool,
    /// The muxer's index of each track, -1 until its format is known.
    video_track: isize,
    audio_track: isize,
    pending: VecDeque<Pending>,
    /// The conversion buffer, reused frame to frame, and which layout the
    /// codec took.
    yuv: Vec<u8>,
    semi_planar: bool,
    src_width: usize,
    src_height: usize,
    width: usize,
    height: usize,
    fps_num: i64,
    fps_den: i64,
    frame_index: i64,
    audio_samples: i64,
    sample_rate: i64,
    channels: usize,
}

// SAFETY: the codecs and the muxer are called one call at a time under the
// lock, from whichever thread Dart is on — as the C's process global was.
unsafe impl Send for Writer {}

impl Drop for Writer {
    fn drop(&mut self) {
        // SAFETY: each handle is null or ours, and released once.
        unsafe {
            for codec in [self.video_codec, self.audio_codec] {
                if !codec.is_null() {
                    AMediaCodec_stop(codec);
                    AMediaCodec_delete(codec);
                }
            }
            if !self.muxer.is_null() {
                if self.muxer_started {
                    AMediaMuxer_stop(self.muxer);
                }
                AMediaMuxer_delete(self.muxer);
            }
            if self.fd >= 0 {
                libc::close(self.fd);
            }
        }
    }
}

static WRITER: Mutex<Option<Writer>> = Mutex::new(None);

/// MP4 only (AMediaMuxer's one format here); HEVC answered by actually
/// asking the codec list — a missing encoder is a capability answer.
pub fn probe(container: i32, codec: i32) -> bool {
    if container != CONTAINER_MP4 {
        return false;
    }
    if codec == CODEC_H264 {
        return true;
    }
    if codec != CODEC_HEVC {
        return false;
    }
    // SAFETY: a codec made only to be asked about, then deleted.
    unsafe {
        let probe = AMediaCodec_createEncoderByType(c"video/hevc".as_ptr());
        if probe.is_null() {
            return false;
        }
        AMediaCodec_delete(probe);
    }
    true
}

impl Writer {
    fn open_video_codec(&self, mime: &std::ffi::CStr, color_format: i32, bitrate_bps: i32) -> *mut AMediaCodec {
        let bitrate = bitrate(bitrate_bps, self.width as i32, self.height as i32, self.fps_num as i32, self.fps_den as i32);
        // SAFETY: a codec and a format of our own; the format is deleted
        // once the codec took it, the codec when it would not start.
        unsafe {
            let codec = AMediaCodec_createEncoderByType(mime.as_ptr());
            if codec.is_null() {
                return null_mut();
            }
            let format = AMediaFormat_new();
            AMediaFormat_setString(format, AMEDIAFORMAT_KEY_MIME, mime.as_ptr());
            AMediaFormat_setInt32(format, AMEDIAFORMAT_KEY_WIDTH, self.width as i32);
            AMediaFormat_setInt32(format, AMEDIAFORMAT_KEY_HEIGHT, self.height as i32);
            AMediaFormat_setInt32(format, AMEDIAFORMAT_KEY_BIT_RATE, bitrate as i32);
            AMediaFormat_setInt32(
                format,
                AMEDIAFORMAT_KEY_FRAME_RATE,
                ((self.fps_num + self.fps_den / 2) / self.fps_den) as i32,
            );
            AMediaFormat_setInt32(format, AMEDIAFORMAT_KEY_I_FRAME_INTERVAL, 1);
            AMediaFormat_setInt32(format, AMEDIAFORMAT_KEY_COLOR_FORMAT, color_format);
            let configured =
                AMediaCodec_configure(codec, format, null_mut(), null_mut(), AMEDIACODEC_CONFIGURE_FLAG_ENCODE as u32);
            AMediaFormat_delete(format);
            if configured != AMEDIA_OK || AMediaCodec_start(codec) != AMEDIA_OK {
                AMediaCodec_delete(codec);
                return null_mut();
            }
            codec
        }
    }

    /// The AAC encoder for the mix, or null.
    fn open_audio_codec(&self) -> *mut AMediaCodec {
        // SAFETY: as open_video_codec.
        unsafe {
            let codec = AMediaCodec_createEncoderByType(c"audio/mp4a-latm".as_ptr());
            if codec.is_null() {
                return null_mut();
            }
            let format = AMediaFormat_new();
            AMediaFormat_setString(format, AMEDIAFORMAT_KEY_MIME, c"audio/mp4a-latm".as_ptr());
            AMediaFormat_setInt32(format, AMEDIAFORMAT_KEY_SAMPLE_RATE, self.sample_rate as i32);
            AMediaFormat_setInt32(format, AMEDIAFORMAT_KEY_CHANNEL_COUNT, self.channels as i32);
            AMediaFormat_setInt32(format, AMEDIAFORMAT_KEY_BIT_RATE, 192_000);
            // 2 = AAC LC.
            AMediaFormat_setInt32(format, AMEDIAFORMAT_KEY_AAC_PROFILE, 2);
            let configured =
                AMediaCodec_configure(codec, format, null_mut(), null_mut(), AMEDIACODEC_CONFIGURE_FLAG_ENCODE as u32);
            AMediaFormat_delete(format);
            if configured != AMEDIA_OK || AMediaCodec_start(codec) != AMEDIA_OK {
                AMediaCodec_delete(codec);
                return null_mut();
            }
            codec
        }
    }

    fn muxer_track(&self, track: Track) -> usize {
        (if track == Track::Video { self.video_track } else { self.audio_track }) as usize
    }

    /// Queues `info` + `data` for the muxer, writing immediately once it has
    /// started — which it does the moment it knows every track.
    fn emit(&mut self, track: Track, data: &[u8], info: &AMediaCodecBufferInfo) -> bool {
        let want_tracks = if self.channels > 0 { 2 } else { 1 };
        let have_tracks = usize::from(self.video_track >= 0) + usize::from(self.audio_track >= 0);
        if !self.muxer_started && have_tracks == want_tracks {
            // SAFETY: our muxer, every track added.
            if unsafe { AMediaMuxer_start(self.muxer) } != AMEDIA_OK {
                set_error("video export: the MP4 muxer refused to start");
                return false;
            }
            self.muxer_started = true;
            // Flush everything that queued while tracks were still being
            // added.
            while let Some(pending) = self.pending.pop_front() {
                let muxer_track = self.muxer_track(pending.track);
                // SAFETY: a started muxer; the data is the sample's own.
                unsafe { AMediaMuxer_writeSampleData(self.muxer, muxer_track, pending.data.as_ptr(), &pending.info) };
            }
        }
        let info = AMediaCodecBufferInfo { offset: 0, ..*info };
        if self.muxer_started {
            // SAFETY: a started muxer; `data` holds `info.size` bytes.
            return unsafe { AMediaMuxer_writeSampleData(self.muxer, self.muxer_track(track), data.as_ptr(), &info) }
                == AMEDIA_OK;
        }
        self.pending.push_back(Pending { track, info, data: data.to_vec() });
        true
    }

    /// Drains one codec's ready output into the muxer (or the pending queue).
    fn drain(&mut self, track: Track) -> bool {
        let codec = if track == Track::Video { self.video_codec } else { self.audio_codec };
        loop {
            let mut info = NO_INFO;
            // SAFETY: our codec; `info` is a local.
            let index = unsafe { AMediaCodec_dequeueOutputBuffer(codec, &mut info, 0) };
            if index == AMEDIACODEC_INFO_TRY_AGAIN_LATER as isize {
                return true;
            }
            if index == AMEDIACODEC_INFO_OUTPUT_FORMAT_CHANGED as isize {
                // SAFETY: the codec's format, handed to the muxer and deleted.
                let added = unsafe {
                    let format = AMediaCodec_getOutputFormat(codec);
                    let added = AMediaMuxer_addTrack(self.muxer, format);
                    AMediaFormat_delete(format);
                    added
                };
                if added < 0 {
                    set_error("video export: the muxer rejected a track");
                    return false;
                }
                if track == Track::Video {
                    self.video_track = added;
                } else {
                    self.audio_track = added;
                }
                continue;
            }
            if index == AMEDIACODEC_INFO_OUTPUT_BUFFERS_CHANGED as isize || index < 0 {
                continue;
            }
            if !self.take_output(codec, track, index as usize, &info) {
                return false;
            }
        }
    }

    /// Emits output buffer `index` — not a codec-config one, which the
    /// muxer learns from the format — and gives it back.
    fn take_output(&mut self, codec: *mut AMediaCodec, track: Track, index: usize, info: &AMediaCodecBufferInfo) -> bool {
        let mut capacity = 0usize;
        // SAFETY: an index the codec just handed out; its bytes are read
        // before it is given back.
        let data = unsafe { AMediaCodec_getOutputBuffer(codec, index, &mut capacity) };
        let mut ok = true;
        if !data.is_null() && info.size > 0 && info.flags & AMEDIACODEC_BUFFER_FLAG_CODEC_CONFIG == 0 {
            // SAFETY: the codec says `size` bytes from `offset`.
            let bytes = unsafe { std::slice::from_raw_parts(data.add(info.offset as usize), info.size as usize) };
            ok = self.emit(track, bytes, info);
        }
        // SAFETY: given back once.
        unsafe { AMediaCodec_releaseOutputBuffer(codec, index, false) };
        ok
    }
}

pub fn open(job: &Job) -> bool {
    let mut held = lock(&WRITER);
    let Some(path) = job.path.filter(|_| held.is_none() && job.well_formed()) else {
        set_error(BAD_OPEN);
        return false;
    };
    if job.container != CONTAINER_MP4 || (job.codec != CODEC_H264 && job.codec != CODEC_HEVC) {
        set_error("video export: Android writes MP4 H.264/H.265 only");
        return false;
    }
    let (width, height) = ((job.width + (job.width & 1)) as usize, (job.height + (job.height & 1)) as usize);
    let mut writer = Writer {
        video_codec: null_mut(),
        audio_codec: null_mut(),
        muxer: null_mut(),
        fd: -1,
        muxer_started: false,
        video_track: -1,
        audio_track: -1,
        pending: VecDeque::new(),
        yuv: vec![0; width * height * 3 / 2],
        semi_planar: true,
        src_width: job.width as usize,
        src_height: job.height as usize,
        width,
        height,
        fps_num: i64::from(job.fps_num),
        fps_den: i64::from(job.fps_den),
        frame_index: 0,
        audio_samples: 0,
        sample_rate: i64::from(job.sample_rate),
        channels: job.channels as usize,
    };
    // SAFETY: a NUL-terminated path; the fd is the writer's to close.
    writer.fd = unsafe { libc::open(path.as_ptr(), libc::O_CREAT | libc::O_TRUNC | libc::O_RDWR, 0o644 as libc::c_uint) };
    if writer.fd < 0 {
        set_error("video export: the output file could not be created");
        return false;
    }
    // SAFETY: an open fd, which the muxer writes and the writer closes.
    writer.muxer = unsafe { AMediaMuxer_new(writer.fd, OutputFormat::AMEDIAMUXER_OUTPUT_FORMAT_MPEG_4) };
    if writer.muxer.is_null() {
        set_error("video export: the MP4 muxer could not be created");
        return false;
    }
    let mime = if job.codec == CODEC_HEVC { c"video/hevc" } else { c"video/avc" };
    writer.video_codec = writer.open_video_codec(mime, SEMI_PLANAR, job.bitrate_bps);
    if writer.video_codec.is_null() {
        writer.video_codec = writer.open_video_codec(mime, PLANAR, job.bitrate_bps);
        writer.semi_planar = false;
    }
    if writer.video_codec.is_null() {
        set_error(if job.codec == CODEC_HEVC {
            "video export: no H.265 encoder on this device"
        } else {
            "video export: no H.264 encoder accepted the frames"
        });
        return false;
    }
    if job.channels > 0 {
        writer.audio_codec = writer.open_audio_codec();
        if writer.audio_codec.is_null() {
            set_error("video export: no AAC encoder accepted the mix");
            return false;
        }
    }
    *held = Some(writer);
    true
}

/// # Safety
/// `rgba` is null or holds the frame `open` was given.
pub unsafe fn write_frame(rgba: *const u8) -> bool {
    let mut held = lock(&WRITER);
    let Some(writer) = held.as_mut().filter(|_| !rgba.is_null()) else {
        return false;
    };
    let luma = writer.width * writer.height;
    let frame_bytes = luma * 3 / 2;
    // RGBA → YUV420 in the app's colour law (BT.601 studio range — the
    // convention H.264 players assume for unflagged content). Pad pixels
    // render white.
    // SAFETY: the caller's contract.
    let rgba = unsafe { std::slice::from_raw_parts(rgba, writer.src_width * writer.src_height * 4) };
    let picture = Picture { rgba, width: writer.src_width, height: writer.src_height };
    let (y, chroma) = writer.yuv.split_at_mut(luma);
    let mut planes = if writer.semi_planar {
        Planes { y, y_stride: writer.width, chroma, cb: 0, cr: 1, chroma_stride: writer.width, chroma_step: 2 }
    } else {
        Planes { y, y_stride: writer.width, chroma, cb: 0, cr: luma / 4, chroma_stride: writer.width / 2, chroma_step: 1 }
    };
    colour::from_rgba(&picture, writer.width, writer.height, &mut planes);

    // SAFETY: our codec; an input buffer is filled within its capacity and
    // queued once.
    unsafe {
        let input = AMediaCodec_dequeueInputBuffer(writer.video_codec, INPUT_WAIT_US);
        if input < 0 {
            set_error("video export: the encoder stopped taking frames");
            return false;
        }
        let mut capacity = 0usize;
        let target = AMediaCodec_getInputBuffer(writer.video_codec, input as usize, &mut capacity);
        if target.is_null() || capacity < frame_bytes {
            return false;
        }
        target.copy_from_nonoverlapping(writer.yuv.as_ptr(), frame_bytes);
        let time_us = writer.frame_index * 1_000_000 * writer.fps_den / writer.fps_num;
        if AMediaCodec_queueInputBuffer(writer.video_codec, input as usize, 0, frame_bytes, time_us as u64, 0)
            != AMEDIA_OK
        {
            return false;
        }
    }
    writer.frame_index += 1;
    writer.drain(Track::Video)
}

/// # Safety
/// `interleaved` is null or holds `frames` × the channels `open` was given.
pub unsafe fn write_audio(interleaved: *const i16, frames: i32) -> bool {
    let mut held = lock(&WRITER);
    let Some(writer) =
        held.as_mut().filter(|writer| !writer.audio_codec.is_null() && !interleaved.is_null() && frames > 0)
    else {
        return false;
    };
    let frame_bytes = writer.channels * 2;
    // SAFETY: the caller's contract.
    let mut pcm = unsafe { std::slice::from_raw_parts(interleaved.cast::<u8>(), frames as usize * frame_bytes) };
    while !pcm.is_empty() {
        // SAFETY: our codec; an input buffer is filled within its capacity
        // and queued once.
        let queued = unsafe {
            let input = AMediaCodec_dequeueInputBuffer(writer.audio_codec, INPUT_WAIT_US);
            if input < 0 {
                set_error("video export: the AAC encoder stopped taking audio");
                return false;
            }
            let mut capacity = 0usize;
            let target = AMediaCodec_getInputBuffer(writer.audio_codec, input as usize, &mut capacity);
            if target.is_null() || capacity == 0 {
                return false;
            }
            // Whole PCM frames only, so channel alignment never shifts.
            let mut chunk = pcm.len().min(capacity);
            chunk -= chunk % frame_bytes;
            target.copy_from_nonoverlapping(pcm.as_ptr(), chunk);
            let time_us = writer.audio_samples * 1_000_000 / writer.sample_rate;
            if AMediaCodec_queueInputBuffer(writer.audio_codec, input as usize, 0, chunk, time_us as u64, 0) != AMEDIA_OK {
                return false;
            }
            chunk
        };
        writer.audio_samples += (queued / frame_bytes) as i64;
        pcm = &pcm[queued..];
        if !writer.drain(Track::Audio) {
            return false;
        }
    }
    true
}

fn signal_end(codec: *mut AMediaCodec) {
    // SAFETY: our codec; an empty buffer marks the end.
    unsafe {
        let input = AMediaCodec_dequeueInputBuffer(codec, INPUT_WAIT_US);
        if input >= 0 {
            AMediaCodec_queueInputBuffer(codec, input as usize, 0, 0, 0, AMEDIACODEC_BUFFER_FLAG_END_OF_STREAM);
        }
    }
}

pub fn finish() -> bool {
    let Some(mut writer) = lock(&WRITER).take() else {
        return false;
    };
    signal_end(writer.video_codec);
    if !writer.audio_codec.is_null() {
        signal_end(writer.audio_codec);
    }
    // Bounded drain of both tails: encoders flush within a few dequeues
    // once end-of-stream is queued.
    for _ in 0..1000 {
        if !writer.drain(Track::Video) {
            break;
        }
        if !writer.audio_codec.is_null() && !writer.drain(Track::Audio) {
            break;
        }
        let mut info = NO_INFO;
        // SAFETY: our codec; `info` is a local.
        let index = unsafe { AMediaCodec_dequeueOutputBuffer(writer.video_codec, &mut info, 10_000) };
        if index >= 0 {
            // The C let a failed emit pass here: the tail is best effort.
            writer.take_output(writer.video_codec, Track::Video, index as usize, &info);
            if info.flags & AMEDIACODEC_BUFFER_FLAG_END_OF_STREAM != 0 {
                break;
            }
            continue;
        }
        if index == AMEDIACODEC_INFO_TRY_AGAIN_LATER as isize {
            break;
        }
    }
    let started = writer.muxer_started;
    drop(writer);
    if !started {
        set_error("video export: the encoders never produced a stream");
        return false;
    }
    true
}

pub fn abort() {
    lock(&WRITER).take();
}
