//! The NDK's MediaExtractor and MediaCodec over the container's bytes — the
//! engine's Android `qa_os_open`, through `ndk-sys`'s bindings of the NDK's
//! own headers (`media::served_span` says why never a table by hand).
//!
//! A plain span opens by descriptor — `AMediaExtractor_setDataSourceFd`
//! takes a RANGE, exactly the shape a container inside the project file
//! needs; a FRAMED span, whose stored bytes are not the container, through
//! the one serving of a span (`media::served_span`).
//!
//! MediaCodec hands back every frame it decoded — it takes nothing off the
//! front: the extractor's `encoder-delay` is a note for the player, not a
//! cut — so where the sound starts is the file's to say
//! (`start::container_start`). ⚠️Not measured on a device, as the C's was
//! not: there is no Android run of these tests.

use std::ffi::{CStr, c_char};
use std::fs::File;
use std::os::fd::AsRawFd;

use media::ndk::{Codec, Extractor, Format, ok};
use media::served_span::ServedSpan;
use ndk_sys::{
    AMEDIACODEC_BUFFER_FLAG_END_OF_STREAM, AMEDIACODEC_INFO_OUTPUT_BUFFERS_CHANGED,
    AMEDIACODEC_INFO_OUTPUT_FORMAT_CHANGED, AMEDIAFORMAT_KEY_CHANNEL_COUNT, AMEDIAFORMAT_KEY_MIME,
    AMEDIAFORMAT_KEY_PCM_ENCODING, AMEDIAFORMAT_KEY_SAMPLE_RATE, AMediaCodec_configure,
    AMediaCodec_createDecoderByType, AMediaCodec_dequeueInputBuffer, AMediaCodec_dequeueOutputBuffer,
    AMediaCodec_getInputBuffer, AMediaCodec_getOutputBuffer, AMediaCodec_getOutputFormat,
    AMediaCodec_queueInputBuffer, AMediaCodec_releaseOutputBuffer, AMediaCodec_start, AMediaCodecBufferInfo,
    AMediaExtractor_advance, AMediaExtractor_getSampleTime, AMediaExtractor_getTrackCount,
    AMediaExtractor_getTrackFormat, AMediaExtractor_new, AMediaExtractor_readSampleData, AMediaExtractor_selectTrack,
    AMediaExtractor_setDataSourceCustom, AMediaExtractor_setDataSourceFd, AMediaFormat_getInt32,
    AMediaFormat_getString,
};

use crate::FORMAT_OS;
use crate::container::Container;
use crate::start::Start;
use crate::stream::{Decode, Opened};

/// How long a dequeue waits, in microseconds — the C's.
const WAIT_US: i64 = 10_000;
/// Rounds in a row where nothing moved before the codec counts as stopped
/// — the C's.
const IDLE_ROUNDS: u32 = 10_000;
/// `AudioFormat.ENCODING_PCM_16BIT` — MediaCodec's default — and `…_FLOAT`.
const PCM_16BIT: i32 = 2;
const PCM_FLOAT: i32 = 4;

/// What the codec last said it hands back.
#[derive(Clone, Copy)]
struct Said {
    channels: i32,
    rate: i32,
    encoding: i32,
}

/// ⚠️FIELDS DROP IN ORDER, and the order is the C's close: the codec, the
/// track's format, the extractor — and only then what the extractor reads
/// through for as long as it lives, the served span or the descriptor.
struct Ndk {
    codec: Codec,
    _track: Format,
    extractor: Extractor,
    _served: Option<ServedSpan>,
    _file: Option<File>,
    said: Said,
    /// The channels and the rate the first block fixed (`Decode::shape`).
    fixed: Option<(usize, i32)>,
    input_done: bool,
    output_done: bool,
}

/// The container read by the NDK, or None when it does not read it.
pub(super) fn open(container: &Container) -> Option<Opened> {
    // ⚠️Before the extractor, so that on every way out it drops after it.
    let mut served = None;
    let mut file = None;
    // SAFETY: no arguments.
    let extractor = Extractor(unsafe { AMediaExtractor_new() });
    if extractor.0.is_null() {
        return None;
    }
    let (path, offset, length, framed) = container.stored();
    if framed {
        let source = ServedSpan::open(container.span_again()?)?;
        // SAFETY: a live extractor and source; the source outlives it.
        ok(unsafe { AMediaExtractor_setDataSourceCustom(extractor.0, source.source()) })?;
        served = Some(source);
    } else {
        let opened = File::open(media::path::file(path)?).ok()?;
        // SAFETY: a live extractor; the descriptor outlives it.
        ok(unsafe { AMediaExtractor_setDataSourceFd(extractor.0, opened.as_raw_fd(), offset, length) })?;
        file = Some(opened);
    }
    let (index, track, mime) = audio_track(&extractor)?;
    let mut said = Said { channels: 0, rate: 0, encoding: PCM_16BIT };
    // SAFETY: a live format; the keys are the NDK's own statics.
    unsafe {
        AMediaFormat_getInt32(track.0, AMEDIAFORMAT_KEY_SAMPLE_RATE, &mut said.rate);
        AMediaFormat_getInt32(track.0, AMEDIAFORMAT_KEY_CHANNEL_COUNT, &mut said.channels);
    }
    // SAFETY: plain NDK calls on live objects; `mime` points into `track`,
    // which lives on.
    let codec = unsafe {
        ok(AMediaExtractor_selectTrack(extractor.0, index))?;
        let mut codec = Codec { codec: AMediaCodec_createDecoderByType(mime), started: false };
        if codec.codec.is_null() {
            return None;
        }
        ok(AMediaCodec_configure(codec.codec, track.0, std::ptr::null_mut(), std::ptr::null_mut(), 0))?;
        ok(AMediaCodec_start(codec.codec))?;
        codec.started = true;
        codec
    };
    let decoder = Ndk {
        codec,
        _track: track,
        extractor,
        _served: served,
        _file: file,
        said,
        fixed: None,
        input_done: false,
        output_done: false,
    };
    // The channels and the rate here are the track's; the first block
    // fixes them (`Decode::shape`).
    Some(Opened {
        decoder: Box::new(decoder),
        format: FORMAT_OS,
        channels: said.channels,
        sample_rate: said.rate,
        start: Start::default(),
    })
}

/// The extractor's first audio track: its index, its format, and its MIME
/// type — which points into that format, so the format is kept.
fn audio_track(extractor: &Extractor) -> Option<(usize, Format, *const c_char)> {
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
        let audio = unsafe {
            AMediaFormat_getString(format.0, AMEDIAFORMAT_KEY_MIME, &mut mime)
                && !mime.is_null()
                && CStr::from_ptr(mime).to_bytes().starts_with(b"audio/")
        };
        audio.then_some((index, format, mime))
    })
}

impl Ndk {
    /// Feeds the codec one sample from the extractor, when it has room:
    /// whether that moved anything.
    fn feed(&mut self) -> bool {
        // SAFETY: plain NDK calls on the live codec and extractor; the input
        // buffer is the codec's, `capacity` bytes.
        unsafe {
            let index = AMediaCodec_dequeueInputBuffer(self.codec.codec, WAIT_US);
            if index < 0 {
                return false;
            }
            let index = index as usize;
            let mut capacity = 0;
            let buffer = AMediaCodec_getInputBuffer(self.codec.codec, index, &mut capacity);
            let size =
                if buffer.is_null() { -1 } else { AMediaExtractor_readSampleData(self.extractor.0, buffer, capacity) };
            if size < 0 {
                AMediaCodec_queueInputBuffer(self.codec.codec, index, 0, 0, 0, AMEDIACODEC_BUFFER_FLAG_END_OF_STREAM as u32);
                self.input_done = true;
            } else {
                let time = AMediaExtractor_getSampleTime(self.extractor.0) as u64;
                AMediaCodec_queueInputBuffer(self.codec.codec, index, 0, size as usize, time, 0);
                AMediaExtractor_advance(self.extractor.0);
            }
        }
        true
    }

    /// What the codec says it hands back now, after it said its output
    /// changed.
    fn hear_output_format(&mut self) {
        // SAFETY: a plain NDK call; the format handed over is deleted here.
        let format = Format(unsafe { AMediaCodec_getOutputFormat(self.codec.codec) });
        if format.0.is_null() {
            return;
        }
        // SAFETY: a live format; the keys are the NDK's own statics.
        unsafe {
            AMediaFormat_getInt32(format.0, AMEDIAFORMAT_KEY_SAMPLE_RATE, &mut self.said.rate);
            AMediaFormat_getInt32(format.0, AMEDIAFORMAT_KEY_CHANNEL_COUNT, &mut self.said.channels);
            AMediaFormat_getInt32(format.0, AMEDIAFORMAT_KEY_PCM_ENCODING, &mut self.said.encoding);
        }
    }

    /// The output buffer at `index` into `block`: how many frames — 0 when it
    /// holds none that can be handed over yet, None where the codec handed
    /// no buffer. Floats pass through; the default 16-bit converts by the
    /// same /32768 every other decode path uses.
    ///
    /// ⚠️The channels and the rate are the codec's last word when the first
    /// block comes, and that block fixes them: what came before them is not
    /// counted, as before the stream.
    fn take(&mut self, index: usize, info: &AMediaCodecBufferInfo, block: &mut Vec<f32>) -> Option<usize> {
        if self.fixed.is_none() {
            if self.said.channels <= 0 || self.said.rate <= 0 {
                return Some(0);
            }
            self.fixed = Some((self.said.channels as usize, self.said.rate));
        }
        let channels = self.fixed?.0;
        let mut capacity = 0;
        // SAFETY: a plain NDK call on the live codec.
        let bytes = unsafe { AMediaCodec_getOutputBuffer(self.codec.codec, index, &mut capacity) };
        if bytes.is_null() {
            return None;
        }
        let float = self.said.encoding == PCM_FLOAT;
        let sample_bytes = if float { size_of::<f32>() } else { size_of::<i16>() };
        let frames = usize::try_from(info.size).unwrap_or(0) / (channels * sample_bytes);
        if frames == 0 {
            return Some(0);
        }
        let samples = frames * channels;
        // SAFETY: the codec's buffer holds `info.size` bytes from `offset`.
        let held = unsafe {
            std::slice::from_raw_parts(bytes.add(usize::try_from(info.offset).unwrap_or(0)), samples * sample_bytes)
        };
        block.clear();
        if float {
            block.extend(held.chunks_exact(4).map(|bytes| f32::from_ne_bytes(bytes.try_into().expect("4 bytes"))));
        } else {
            block.extend(
                held.chunks_exact(2).map(|bytes| f32::from(i16::from_ne_bytes(bytes.try_into().expect("2 bytes"))) / 32768.0),
            );
        }
        Some(frames)
    }
}

impl Decode for Ndk {
    /// ⚠️A codec that stops answering before the end, or hands no buffer,
    /// is the end — as every decoder behind a stream says it; the C failed
    /// the whole decode there.
    fn next(&mut self, block: &mut Vec<f32>) -> usize {
        let mut idle = 0;
        while !self.output_done && idle < IDLE_ROUNDS {
            let mut moved = !self.input_done && self.feed();
            let mut info = AMediaCodecBufferInfo { offset: 0, size: 0, presentationTimeUs: 0, flags: 0 };
            // SAFETY: a plain NDK call; `info` is a local.
            let index = unsafe { AMediaCodec_dequeueOutputBuffer(self.codec.codec, &mut info, WAIT_US) };
            if index >= 0 {
                let frames = if info.size > 0 { self.take(index as usize, &info, block) } else { Some(0) };
                // SAFETY: the buffer just dequeued, handed back once.
                unsafe { AMediaCodec_releaseOutputBuffer(self.codec.codec, index as usize, false) };
                if info.flags & AMEDIACODEC_BUFFER_FLAG_END_OF_STREAM as u32 != 0 {
                    self.output_done = true;
                }
                match frames {
                    None => {
                        self.output_done = true;
                        return 0;
                    }
                    Some(0) => {}
                    Some(frames) => return frames,
                }
                moved = true;
            } else if index == AMEDIACODEC_INFO_OUTPUT_FORMAT_CHANGED as isize {
                self.hear_output_format();
                moved = true;
            } else if index == AMEDIACODEC_INFO_OUTPUT_BUFFERS_CHANGED as isize {
                moved = true;
            }
            idle = if moved { 0 } else { idle + 1 };
        }
        0
    }

    fn shape(&self) -> Option<(i32, i32)> {
        self.fixed.map(|(channels, rate)| (channels as i32, rate))
    }
}
