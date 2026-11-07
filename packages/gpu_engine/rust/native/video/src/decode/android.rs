//! Android: the NDK's MediaExtractor and MediaCodec, through `ndk-sys`.
//! The colour conversion is ours ([`colour::to_rgba`]) — a decoder hands
//! back YUV in whichever layout the vendor's hardware likes, described by
//! STRIDE, SLICE HEIGHT and a colour format, easy to assume and wrong to.
//! Planar I420 and semi-planar NV12 are read; anything else is refused by
//! name instead of drawn as noise.
//!
//! ⚠️Not run on a device by these tests, as the C's was not: the law and
//! the colour arithmetic are what the bench proves.

use std::ffi::{CStr, c_char};
use std::fs::File;
use std::os::fd::AsRawFd;

use media::ndk::{Codec, Extractor, Format, ok};
use media::served_span::ServedSpan;
use media::span::Span;
use ndk_sys::{
    AMEDIACODEC_BUFFER_FLAG_END_OF_STREAM, AMEDIAFORMAT_KEY_COLOR_FORMAT,
    AMEDIAFORMAT_KEY_DURATION, AMEDIAFORMAT_KEY_FRAME_RATE, AMEDIAFORMAT_KEY_HEIGHT, AMEDIAFORMAT_KEY_MIME,
    AMEDIAFORMAT_KEY_ROTATION, AMEDIAFORMAT_KEY_SLICE_HEIGHT, AMEDIAFORMAT_KEY_STRIDE, AMEDIAFORMAT_KEY_WIDTH,
    AMediaCodec_configure, AMediaCodec_createDecoderByType, AMediaCodec_dequeueInputBuffer,
    AMediaCodec_dequeueOutputBuffer, AMediaCodec_flush, AMediaCodec_getInputBuffer, AMediaCodec_getOutputBuffer,
    AMediaCodec_getOutputFormat, AMediaCodec_queueInputBuffer, AMediaCodec_releaseOutputBuffer, AMediaCodec_start,
    AMediaCodecBufferInfo, AMediaExtractor_advance, AMediaExtractor_getSampleTime, AMediaExtractor_getTrackCount,
    AMediaExtractor_getTrackFormat, AMediaExtractor_new, AMediaExtractor_readSampleData, AMediaExtractor_seekTo,
    AMediaExtractor_selectTrack, AMediaExtractor_setDataSourceCustom, AMediaExtractor_setDataSourceFd,
    AMediaFormat_getFloat, AMediaFormat_getInt32, AMediaFormat_getInt64, AMediaFormat_getString, SeekMode,
};

use super::{Opened, Rate, Why, frame_ticks, sample_reaches, ticks_at};
use crate::colour;

pub const SUPPORTED: bool = true;

/// MediaCodec's ticks: µs.
const TICKS: i64 = 1_000_000;
/// How many rounds a read walks toward its frame, each dequeue waiting this
/// long in µs — the C's.
const WALK: usize = 900;
const WAIT_US: i64 = 2000;

// MediaCodecInfo.CodecCapabilities — no NDK header carries these.
const PLANAR: i32 = 19;
const SEMI_PLANAR: i32 = 21;
const FLEXIBLE: i32 = 0x7F42_0888;

/// ⚠️FIELDS DROP IN ORDER, and the order is the C's close: the codec, the
/// extractor — and only then what the extractor reads through for as long
/// as it lives, the served span.
pub struct Reader {
    codec: Codec,
    extractor: Extractor,
    _served: Option<ServedSpan>,
    stored: (usize, usize),
}

// SAFETY: the NDK's media objects belong to no thread; a movie's is called
// from whichever thread an isolate is on, one call at a time under its
// slot's lock — as the C's slot was.
unsafe impl Send for Reader {}

impl Reader {
    pub fn open(path: &CStr, span: Option<(i64, i64, bool)>) -> Result<(Reader, Opened), Why> {
        // SAFETY: no arguments.
        let extractor = Extractor(unsafe { AMediaExtractor_new() });
        if extractor.0.is_null() {
            return Err("could not open the container".into());
        }
        // A FRAMED span is served through a source of our own; anything else
        // opens by descriptor — a plain span over its range, a whole file over
        // all of it. 🐞⛔NOT by path (`setDataSource`): it makes an HTTP
        // service through JNI, which only a thread the JVM knows can, and
        // every decode runs on a Dart worker's — every movie picked as a file
        // failed to open (build 1084, API 37; 유저 10-30, Galaxy Tab).
        let served = match span {
            Some((offset, length, true)) => {
                let served = Span::open(path, offset, length, true)
                    .and_then(ServedSpan::open)
                    .ok_or("that span does not hold a readable movie")?;
                // SAFETY: a live extractor and source; the source outlives it.
                ok(unsafe { AMediaExtractor_setDataSourceCustom(extractor.0, served.source()) })
                    .ok_or("could not open the container")?;
                Some(served)
            }
            plain => {
                let file = media::path::file(path).and_then(|path| File::open(path).ok());
                let file = file.ok_or("could not open the container")?;
                let (offset, length) = match plain {
                    Some((offset, length, _)) => (offset, length),
                    None => (0, file.metadata().map_or(0, |file| file.len() as i64)),
                };
                if length <= 0 {
                    return Err("could not open the container".into());
                }
                // SAFETY: a live extractor and descriptor. ⚠️The file closes
                // as this ends: `setDataSourceFd` dups what it needs.
                ok(unsafe { AMediaExtractor_setDataSourceFd(extractor.0, file.as_raw_fd(), offset, length) })
                    .ok_or("could not open the container")?;
                None
            }
        };
        let (index, track, mime) = video_track(&extractor).ok_or("this file has no readable video stream")?;
        let (mut width, mut height, mut rate, mut rate_f, mut duration, mut rotation) = (0, 0, 0, 0.0f32, 0i64, 0);
        // SAFETY: a live format; the keys are the NDK's own statics. ⚠️Read
        // BEFORE the format goes, and the rotation off the EXTRACTOR's track —
        // the codec's output has forgotten it.
        unsafe {
            AMediaFormat_getInt32(track.0, AMEDIAFORMAT_KEY_WIDTH, &mut width);
            AMediaFormat_getInt32(track.0, AMEDIAFORMAT_KEY_HEIGHT, &mut height);
            AMediaFormat_getInt32(track.0, AMEDIAFORMAT_KEY_FRAME_RATE, &mut rate);
            AMediaFormat_getFloat(track.0, AMEDIAFORMAT_KEY_FRAME_RATE, &mut rate_f);
            AMediaFormat_getInt64(track.0, AMEDIAFORMAT_KEY_DURATION, &mut duration);
            AMediaFormat_getInt32(track.0, AMEDIAFORMAT_KEY_ROTATION, &mut rotation);
        }
        // SAFETY: plain NDK calls on live objects; `mime` points into `track`.
        let codec = unsafe {
            let mut codec = Codec { codec: AMediaCodec_createDecoderByType(mime), started: false };
            let started = !codec.codec.is_null()
                && ok(AMediaCodec_configure(codec.codec, track.0, std::ptr::null_mut(), std::ptr::null_mut(), 0))
                    .is_some()
                && ok(AMediaCodec_start(codec.codec)).is_some();
            if !started {
                return Err("no decoder for this codec".into());
            }
            codec.started = true;
            AMediaExtractor_selectTrack(extractor.0, index);
            codec
        };
        let opened = Opened {
            stored_width: width,
            stored_height: height,
            rotation,
            // 🚨★★★**29.97 IS NOT 30**: read as a FLOAT; some extractors store
            // the key as an int32 and the float getter refuses it, and the
            // integer is the honest answer for those.
            rate: Rate::Nominal(if rate_f > 0.0 { f64::from(rate_f) } else { f64::from(rate) }),
            length: (duration, TICKS),
        };
        let stored = (width.max(0) as usize, height.max(0) as usize);
        Ok((Reader { codec, extractor, _served: served, stored }, opened))
    }

    /// ⛔The flush goes WITH the seek: flushing without seeking would throw
    /// away the very frames the codec holds for us.
    pub fn reposition(&mut self, index: i64, rate: (i32, i32)) -> Result<(), Why> {
        // SAFETY: plain NDK calls on the live extractor and codec.
        unsafe {
            let at = ticks_at(index, TICKS, rate);
            AMediaExtractor_seekTo(self.extractor.0, at, SeekMode::AMEDIAEXTRACTOR_SEEK_PREVIOUS_SYNC);
            AMediaCodec_flush(self.codec.codec);
        }
        Ok(())
    }

    pub fn read(&mut self, index: i64, rate: (i32, i32), rgba: &mut [u8]) -> Result<(), Why> {
        let target = ticks_at(index, TICKS, rate);
        let frame = frame_ticks(TICKS, rate);
        // Each read starts feeding afresh, as the C's did.
        let mut input_done = false;
        for _ in 0..WALK {
            if !input_done {
                input_done = self.feed();
            }
            let mut info = AMediaCodecBufferInfo { offset: 0, size: 0, presentationTimeUs: 0, flags: 0 };
            // SAFETY: a plain NDK call; `info` is a local.
            let out = unsafe { AMediaCodec_dequeueOutputBuffer(self.codec.codec, &mut info, WAIT_US) };
            // Below 0: try again, or a format change read below.
            let Ok(out) = usize::try_from(out) else { continue };
            let wrote = sample_reaches(info.presentationTimeUs, target, frame).then(|| self.copy(out, rgba));
            // SAFETY: the buffer just dequeued, handed back once.
            unsafe { AMediaCodec_releaseOutputBuffer(self.codec.codec, out, false) };
            if let Some(wrote) = wrote {
                return wrote;
            }
        }
        Err("that frame could not be read".into())
    }

    /// Feeds the codec one sample from the extractor, when it has room:
    /// whether that was the end.
    fn feed(&mut self) -> bool {
        // SAFETY: plain NDK calls on the live codec and extractor; the input
        // buffer is the codec's, `capacity` bytes.
        unsafe {
            let Ok(index) = usize::try_from(AMediaCodec_dequeueInputBuffer(self.codec.codec, WAIT_US)) else {
                return false;
            };
            let mut capacity = 0;
            let buffer = AMediaCodec_getInputBuffer(self.codec.codec, index, &mut capacity);
            let size =
                if buffer.is_null() { -1 } else { AMediaExtractor_readSampleData(self.extractor.0, buffer, capacity) };
            if size <= 0 {
                AMediaCodec_queueInputBuffer(self.codec.codec, index, 0, 0, 0, AMEDIACODEC_BUFFER_FLAG_END_OF_STREAM);
                true
            } else {
                let time = AMediaExtractor_getSampleTime(self.extractor.0) as u64;
                AMediaCodec_queueInputBuffer(self.codec.codec, index, 0, size as usize, time, 0);
                AMediaExtractor_advance(self.extractor.0);
                false
            }
        }
    }

    /// Output buffer `out` as RGBA at the stored size.
    fn copy(&self, out: usize, rgba: &mut [u8]) -> Result<(), Why> {
        let (width, height) = self.stored;
        let mut size = 0;
        // SAFETY: plain NDK calls on the live codec; the format handed over
        // is deleted as it drops.
        let (bytes, format) = unsafe {
            let bytes = AMediaCodec_getOutputBuffer(self.codec.codec, out, &mut size);
            (bytes, Format(AMediaCodec_getOutputFormat(self.codec.codec)))
        };
        let (mut colour, mut stride, mut slice) = (FLEXIBLE, width as i32, height as i32);
        if !format.0.is_null() {
            // SAFETY: a live format; the keys are the NDK's own statics.
            unsafe {
                AMediaFormat_getInt32(format.0, AMEDIAFORMAT_KEY_COLOR_FORMAT, &mut colour);
                AMediaFormat_getInt32(format.0, AMEDIAFORMAT_KEY_STRIDE, &mut stride);
                AMediaFormat_getInt32(format.0, AMEDIAFORMAT_KEY_SLICE_HEIGHT, &mut slice);
            }
        }
        let (stride, slice) = ((stride.max(0) as usize).max(width), (slice.max(0) as usize).max(height));
        if bytes.is_null() || ![PLANAR, SEMI_PLANAR, FLEXIBLE].contains(&colour) {
            return Err("this device's decoder uses a colour format we do not read".into());
        }
        // SAFETY: the codec's buffer holds `size` bytes until it is released.
        let data = unsafe { std::slice::from_raw_parts(bytes, size) };
        // ⚠️Measured, not assumed: the C read as far as stride and slice said,
        // whatever the buffer held.
        if !colour::to_rgba(data, width, height, stride, slice, colour == SEMI_PLANAR, rgba) {
            return Err("the decoded frame was short".into());
        }
        Ok(())
    }
}

/// The extractor's first video track: its index, its format, and its MIME
/// type — which points into that format, so the format is kept.
fn video_track(extractor: &Extractor) -> Option<(usize, Format, *const c_char)> {
    // SAFETY: a live extractor.
    let tracks = unsafe { AMediaExtractor_getTrackCount(extractor.0) };
    (0..tracks).find_map(|index| {
        // SAFETY: a live extractor and a track it has.
        let format = Format(unsafe { AMediaExtractor_getTrackFormat(extractor.0, index) });
        if format.0.is_null() {
            return None;
        }
        let mut mime: *const c_char = std::ptr::null();
        // SAFETY: a live format; the key is the NDK's own static; what it
        // hands back is a string inside the format.
        let video = unsafe {
            AMediaFormat_getString(format.0, AMEDIAFORMAT_KEY_MIME, &mut mime)
                && !mime.is_null()
                && CStr::from_ptr(mime).to_bytes().starts_with(b"video/")
        };
        video.then_some((index, format, mime))
    })
}
