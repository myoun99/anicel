//! What the video codecs call of the NDK media API (libmediandk.so) — ONE
//! table for the writer and, as it joins, the reader.
//!
//! 🚨★★★**THERE WERE THREE COPIES OF THE NDK MEDIA TABLE, AND THEY DID NOT
//! AGREE** (`qa_ndk_media.h`, 2026-09-24): `AMediaCodec_queueInputBuffer`
//! takes its offset as `long` (`_off_t_compat`), 32 bits on a 32-bit ARM
//! device, where two tables said 64 and shifted every argument after it;
//! `AMEDIACODEC_INFO_OUTPUT_FORMAT_CHANGED` is -2 and `…BUFFERS_CHANGED` -3,
//! where the encoder said -1012 and -1014 and its muxer never started. The C
//! then took the NDK's own headers so the compiler checked every type.
//!
//! ⚠️Rust has no NDK header to include, so these ARE a copy again — made
//! once, from NDK 30.0.16248370's `media/NdkMediaCodec.h`, `NdkMediaFormat.h`,
//! `NdkMediaMuxer.h` and `NdkMediaError.h`, with exactly the lessons above
//! held: `c_long` for the offset, the INFO values as the header spells them.
//! A second table anywhere is the bug this file's C ancestor was made to end.
//!
//! Linked, like the C: every device the app serves has libmediandk.so — a
//! public NDK library since API 21, and everything here is API 21.

#![allow(non_camel_case_types, non_snake_case, non_upper_case_globals)]

use std::ffi::{c_char, c_int, c_long, c_void};

#[repr(C)]
pub struct AMediaCodec {
    _opaque: [u8; 0],
}

#[repr(C)]
pub struct AMediaFormat {
    _opaque: [u8; 0],
}

#[repr(C)]
pub struct AMediaMuxer {
    _opaque: [u8; 0],
}

#[repr(C)]
#[derive(Clone, Copy, Default)]
pub struct AMediaCodecBufferInfo {
    pub offset: i32,
    pub size: i32,
    pub presentationTimeUs: i64,
    pub flags: u32,
}

/// `media_status_t`, an enum: `AMEDIA_OK` is 0, every error negative.
pub type media_status_t = c_int;
pub const AMEDIA_OK: media_status_t = 0;

pub const AMEDIACODEC_BUFFER_FLAG_CODEC_CONFIG: u32 = 2;
pub const AMEDIACODEC_BUFFER_FLAG_END_OF_STREAM: u32 = 4;
pub const AMEDIACODEC_CONFIGURE_FLAG_ENCODE: u32 = 1;
pub const AMEDIACODEC_INFO_OUTPUT_BUFFERS_CHANGED: isize = -3;
pub const AMEDIACODEC_INFO_OUTPUT_FORMAT_CHANGED: isize = -2;
pub const AMEDIACODEC_INFO_TRY_AGAIN_LATER: isize = -1;

/// `OutputFormat`, an enum.
pub const AMEDIAMUXER_OUTPUT_FORMAT_MPEG_4: c_int = 0;

#[link(name = "mediandk")]
unsafe extern "C" {
    pub fn AMediaCodec_createEncoderByType(mime_type: *const c_char) -> *mut AMediaCodec;
    pub fn AMediaCodec_delete(codec: *mut AMediaCodec) -> media_status_t;
    pub fn AMediaCodec_configure(
        codec: *mut AMediaCodec,
        format: *const AMediaFormat,
        surface: *mut c_void,
        crypto: *mut c_void,
        flags: u32,
    ) -> media_status_t;
    pub fn AMediaCodec_start(codec: *mut AMediaCodec) -> media_status_t;
    pub fn AMediaCodec_stop(codec: *mut AMediaCodec) -> media_status_t;
    pub fn AMediaCodec_dequeueInputBuffer(codec: *mut AMediaCodec, timeoutUs: i64) -> isize;
    pub fn AMediaCodec_getInputBuffer(codec: *mut AMediaCodec, idx: usize, out_size: *mut usize) -> *mut u8;
    pub fn AMediaCodec_queueInputBuffer(
        codec: *mut AMediaCodec,
        idx: usize,
        offset: c_long,
        size: usize,
        time: u64,
        flags: u32,
    ) -> media_status_t;
    pub fn AMediaCodec_dequeueOutputBuffer(
        codec: *mut AMediaCodec,
        info: *mut AMediaCodecBufferInfo,
        timeoutUs: i64,
    ) -> isize;
    pub fn AMediaCodec_getOutputBuffer(codec: *mut AMediaCodec, idx: usize, out_size: *mut usize) -> *mut u8;
    pub fn AMediaCodec_releaseOutputBuffer(codec: *mut AMediaCodec, idx: usize, render: bool) -> media_status_t;
    pub fn AMediaCodec_getOutputFormat(codec: *mut AMediaCodec) -> *mut AMediaFormat;

    pub fn AMediaFormat_new() -> *mut AMediaFormat;
    pub fn AMediaFormat_delete(format: *mut AMediaFormat) -> media_status_t;
    pub fn AMediaFormat_setInt32(format: *mut AMediaFormat, name: *const c_char, value: i32);
    pub fn AMediaFormat_setString(format: *mut AMediaFormat, name: *const c_char, value: *const c_char);

    pub fn AMediaMuxer_new(fd: c_int, format: c_int) -> *mut AMediaMuxer;
    pub fn AMediaMuxer_delete(muxer: *mut AMediaMuxer) -> media_status_t;
    pub fn AMediaMuxer_addTrack(muxer: *mut AMediaMuxer, format: *const AMediaFormat) -> isize;
    pub fn AMediaMuxer_start(muxer: *mut AMediaMuxer) -> media_status_t;
    pub fn AMediaMuxer_stop(muxer: *mut AMediaMuxer) -> media_status_t;
    pub fn AMediaMuxer_writeSampleData(
        muxer: *mut AMediaMuxer,
        trackIdx: usize,
        data: *const u8,
        info: *const AMediaCodecBufferInfo,
    ) -> media_status_t;

    pub static AMEDIAFORMAT_KEY_AAC_PROFILE: *const c_char;
    pub static AMEDIAFORMAT_KEY_BIT_RATE: *const c_char;
    pub static AMEDIAFORMAT_KEY_CHANNEL_COUNT: *const c_char;
    pub static AMEDIAFORMAT_KEY_COLOR_FORMAT: *const c_char;
    pub static AMEDIAFORMAT_KEY_FRAME_RATE: *const c_char;
    pub static AMEDIAFORMAT_KEY_HEIGHT: *const c_char;
    pub static AMEDIAFORMAT_KEY_I_FRAME_INTERVAL: *const c_char;
    pub static AMEDIAFORMAT_KEY_MIME: *const c_char;
    pub static AMEDIAFORMAT_KEY_SAMPLE_RATE: *const c_char;
    pub static AMEDIAFORMAT_KEY_WIDTH: *const c_char;
}
