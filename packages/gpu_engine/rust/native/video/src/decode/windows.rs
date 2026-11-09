//! Windows: Media Foundation's Source Reader, which also converts to RGB32
//! for us (the advanced video processing attribute) — so the only pixel job
//! here is BGRA → RGBA and the stride. A whole file goes through its URL; a
//! span through media's one byte stream (`span_stream`), plain or framed.

use std::ffi::CStr;

use media::media_foundation::span_stream;
use media::span::Span;
use windows::Win32::Media::MediaFoundation::*;
use windows::Win32::System::Com::StructuredStorage::PROPVARIANT;
use windows::Win32::System::Variant::{VT_I8, VT_UI8};
use windows::core::{GUID, PCWSTR};

use super::{Opened, PAST_THE_END, Rate, Why, frame_ticks, sample_reaches, ticks_at};

pub const SUPPORTED: bool = true;

/// Media Foundation's ticks: 100 ns.
const TICKS: i64 = 10_000_000;

/// How far before the presentation's end the video's last samples are
/// looked for, and how many are read at most before giving up on them.
const TAIL: i64 = 20_000_000;
const TAIL_READS: usize = 100_000;

/// How many samples a read walks toward its frame before it gives up.
const WALK: usize = 600;

const VIDEO: u32 = MF_SOURCE_READER_FIRST_VIDEO_STREAM.0 as u32;

/// The platform's own state for one movie: the reader, and how Media
/// Foundation lays out its rows.
pub struct Reader {
    reader: IMFSourceReader,
    stored: (usize, usize),
    /// The row pitch, whichever way the rows run.
    stride: usize,
    /// A negative stride in the media type: the LAST row is stored first.
    bottom_up: bool,
}

// SAFETY: the source reader is a free-threaded MF object; a movie's is opened
// on the caller's thread and then called only from its reading thread
// (`reading.rs`), one call at a time.
unsafe impl Send for Reader {}

impl Reader {
    pub fn open(path: &CStr, span: Option<(i64, i64, bool)>) -> Result<(Reader, Opened), Why> {
        let Some(wide) = media::path::wide(path) else { return Err("path is not valid UTF-8".into()) };
        if !media::media_foundation::up() {
            return Err("MFStartup failed".into());
        }
        // ENABLE_ADVANCED_VIDEO_PROCESSING is what lets RGB32 be asked of a
        // YUV source — without it the reader refuses, and this would carry a
        // colour converter of its own.
        let mut attributes = None;
        // SAFETY (each MF call below): a plain COM call on live objects.
        unsafe { MFCreateAttributes(&mut attributes, 1) }.map_err(|_| "MFCreateAttributes failed")?;
        let attributes = attributes.ok_or("MFCreateAttributes failed")?;
        let _ = unsafe { attributes.SetUINT32(&MF_SOURCE_READER_ENABLE_ADVANCED_VIDEO_PROCESSING, 1) };
        // ⛔The URL form is not a shortcut kept for its own sake: Media
        // Foundation opening a file itself is faster and better tested than
        // anything wrapped around one. The stream exists where there is no
        // file to name.
        let reader = match span {
            Some((offset, length, framed)) => {
                let span = Span::open(path, offset, length, framed).ok_or("that span does not hold a readable movie")?;
                unsafe { MFCreateSourceReaderFromByteStream(&span_stream::open(span), &attributes) }
            }
            None => unsafe { MFCreateSourceReaderFromURL(PCWSTR(wide.as_ptr()), &attributes) },
        }
        .map_err(|_| "this file has no readable video stream")?;
        // Only the video: audio left selected comes back from every read and
        // is skipped past on every seek.
        let _ = unsafe { reader.SetStreamSelection(MF_SOURCE_READER_ALL_STREAMS.0 as u32, false) };
        let _ = unsafe { reader.SetStreamSelection(VIDEO, true) };
        // Measured while the reader has no output type: a sample read now is
        // the stored bytes, and decodes nothing.
        let presentation = presentation(&reader);
        let video_end = video_end(&reader, presentation);

        let wanted = unsafe { MFCreateMediaType() }.map_err(|_| "MFCreateMediaType failed")?;
        let _ = unsafe { wanted.SetGUID(&MF_MT_MAJOR_TYPE, &MFMediaType_Video) };
        let _ = unsafe { wanted.SetGUID(&MF_MT_SUBTYPE, &MFVideoFormat_RGB32) };
        ask_for_the_stored_rate(&reader, &wanted);
        unsafe { reader.SetCurrentMediaType(VIDEO, None, &wanted) }.map_err(|_| "no RGB conversion for this codec")?;
        let current =
            unsafe { reader.GetCurrentMediaType(VIDEO) }.map_err(|_| "the reader would not describe its output")?;
        let (width, height) = halves(unsafe { current.GetUINT64(&MF_MT_FRAME_SIZE) }.unwrap_or(0));
        let (num, den) = halves(unsafe { current.GetUINT64(&MF_MT_FRAME_RATE) }.unwrap_or(0));
        let stride =
            unsafe { current.GetUINT32(&MF_MT_DEFAULT_STRIDE) }.map_or(width as i32 * 4, |stride| stride as i32);
        // 🚨MF_MT_VIDEO_ROTATION is an MFVideoRotationFormat, whose values ARE
        // the clockwise angle in degrees. Absent is none.
        let rotation = unsafe { current.GetUINT32(&MF_MT_VIDEO_ROTATION) }.unwrap_or(0);

        // 🚨★★★**THE PRESENTATION IS AS LONG AS ITS LONGEST TRACK, AND THAT IS
        // ALMOST NEVER THE VIDEO**: AAC ends tens of ms past the last picture,
        // and counted, that is a frame with no picture in it (유저 2026-08-31
        // 「72프레임짜리 비디오인데 73프레임째의 빈 화면」). The video's own
        // samples say where it ends; ⛔where they do not, the presentation
        // keeps the old count rather than none.
        let length = if video_end > 0 { video_end } else { presentation };
        let opened = Opened {
            stored_width: width as i32,
            stored_height: height as i32,
            rotation: rotation as i32,
            // Media Foundation hands the rate over as a ratio already — the
            // one backend with nothing to reconstruct.
            rate: Rate::Fraction(num as i32, den as i32),
            length: (length, TICKS),
        };
        let stored = (width as usize, height as usize);
        Ok((Reader { reader, stored, stride: stride.unsigned_abs() as usize, bottom_up: stride < 0 }, opened))
    }

    pub fn reposition(&mut self, index: i64, rate: (i32, i32)) -> Result<(), Why> {
        let position = position(ticks_at(index, TICKS, rate));
        // ⚠️Its answer is not asked, as the C did not: a seek Media
        // Foundation refuses leaves the read below to walk from where it is,
        // and that walk says whether the frame was reached.
        // SAFETY: a plain COM call; the position outlives it.
        let _ = unsafe { self.reader.SetCurrentPosition(&GUID::zeroed(), &position) };
        Ok(())
    }

    /// Walks forward to the picture for `index` and writes it, straight RGBA
    /// at the stored size.
    pub fn read(&mut self, index: i64, rate: (i32, i32), rgba: &mut [u8], alive: &dyn Fn()) -> Result<(), Why> {
        let target = ticks_at(index, TICKS, rate);
        let frame = frame_ticks(TICKS, rate);
        for _ in 0..WALK {
            let (mut flags, mut stamp, mut sample) = (0, 0, None);
            // SAFETY: a plain COM call; the out-parameters are this frame's.
            unsafe { self.reader.ReadSample(VIDEO, 0, None, Some(&mut flags), Some(&mut stamp), Some(&mut sample)) }
                .map_err(|_| "the reader failed mid-stream")?;
            alive();
            if flags & MF_SOURCE_READERF_ENDOFSTREAM.0 as u32 != 0 {
                return Err(PAST_THE_END.into());
            }
            // None is a gap or a format change: keep reading.
            let Some(sample) = sample else { continue };
            if sample_reaches(stamp, target, frame) {
                return self.copy(&sample, rgba);
            }
        }
        Err("no picture reached that frame".into())
    }

    fn copy(&self, sample: &IMFSample, rgba: &mut [u8]) -> Result<(), Why> {
        // SAFETY (each): a plain COM call on live objects.
        let buffer = unsafe { sample.ConvertToContiguousBuffer() }.map_err(|_| "the decoded frame has no buffer")?;
        let (mut data, mut length) = (std::ptr::null_mut(), 0);
        unsafe { buffer.Lock(&mut data, None, Some(&mut length)) }.map_err(|_| "the decoded frame would not lock")?;
        let (width, height) = self.stored;
        let wrote = if (length as usize) < self.stride * height {
            Err("the decoded frame was short".into())
        } else {
            // SAFETY: the locked buffer holds `length` bytes until Unlock.
            let source = unsafe { std::slice::from_raw_parts(data, length as usize) };
            for y in 0..height {
                // A bottom-up buffer stores the LAST row first; read forwards
                // it comes out upside down.
                let row = if self.bottom_up { height - 1 - y } else { y } * self.stride;
                let from = &source[row..row + width * 4];
                let into = &mut rgba[y * width * 4..(y + 1) * width * 4];
                for (to, bgra) in into.chunks_exact_mut(4).zip(from.chunks_exact(4)) {
                    // MFVideoFormat_RGB32 is BGRA in memory, its fourth byte unset.
                    to.copy_from_slice(&[bgra[2], bgra[1], bgra[0], 255]);
                }
            }
            Ok(())
        };
        let _ = unsafe { buffer.Unlock() };
        wrote
    }
}

/// A packed attribute's two halves, high word first — what `MFGetAttributeSize`
/// and `MFGetAttributeRatio` unpack.
fn halves(packed: u64) -> (u32, u32) {
    ((packed >> 32) as u32, packed as u32)
}

/// A position in 100 ns, as `SetCurrentPosition` takes one.
fn position(ticks: i64) -> PROPVARIANT {
    let mut position = PROPVARIANT::default();
    // SAFETY: the zeroed variant's tagged member, the one every member but
    // `decVal` sits in; the tag written below names the integer written.
    let fields = unsafe { &mut *position.Anonymous.Anonymous };
    fields.vt = VT_I8;
    fields.Anonymous.hVal = ticks;
    position
}

/// The presentation's length in 100 ns — as long as its LONGEST track,
/// which is seldom the video. 0 when it does not say.
fn presentation(reader: &IMFSourceReader) -> i64 {
    // SAFETY: a plain COM call.
    let source = MF_SOURCE_READER_MEDIASOURCE.0 as u32;
    let Ok(duration) = (unsafe { reader.GetPresentationAttribute(source, &MF_PD_DURATION) }) else { return 0 };
    // SAFETY: reading the member the variant's own tag names.
    unsafe {
        let duration = &duration.Anonymous.Anonymous;
        if duration.vt == VT_UI8 { duration.Anonymous.uhVal as i64 } else { 0 }
    }
}

/// Where the VIDEO ends, in 100 ns: the end of its last sample, read from a
/// little before `presentation`'s end — a seek and a few seconds of samples,
/// none decoded while the reader has no output type. 0 when they do not say.
///
/// 🚨★★★**MEDIA FOUNDATION DOES NOT ANSWER 「HOW LONG IS THE VIDEO」**: no
/// source has ever answered the video stream's `MF_PD_DURATION` (검증
/// 2026-10-23, windows-counts-a-movie-by-its-longest-track — refused for a
/// `.mov` and an `.mp4` alike). The samples are what says.
fn video_end(reader: &IMFSourceReader, presentation: i64) -> i64 {
    let from = position((presentation - TAIL).max(0));
    // SAFETY (each): a plain COM call; the out-parameters are this loop's.
    if unsafe { reader.SetCurrentPosition(&GUID::zeroed(), &from) }.is_err() {
        return 0;
    }
    let mut end = 0;
    for _ in 0..TAIL_READS {
        let (mut flags, mut stamp, mut sample) = (0, 0, None);
        let read = unsafe { reader.ReadSample(VIDEO, 0, None, Some(&mut flags), Some(&mut stamp), Some(&mut sample)) };
        if read.is_err() {
            return 0;
        }
        if let Some(sample) = sample {
            let length = unsafe { sample.GetSampleDuration() }.unwrap_or(0);
            end = end.max(stamp + length);
        }
        if flags & MF_SOURCE_READERF_ENDOFSTREAM.0 as u32 != 0 {
            return end;
        }
    }
    // ⛔Out of reads before the end: what was read is not where it ends.
    0
}

/// Asks the conversion for pictures at the rate the FILE stores, and leaves
/// it to choose where the file names none.
///
/// 🚨★★★**LEFT TO CHOOSE, THE CONVERSION TAKES THE DECODER'S RATE, AND A
/// DECODER MAY WORK ITS OWN OUT**: the MPEG-4 Part 2 decoder calls a stream
/// stored at 23.976 10000000/417188 and the conversion stamps every picture
/// on that clock (검증 2026-10-23, movie-23976-mpeg4-part2-asks-no-speed — a
/// 12-frame movie counted 11). ⚠️0/0 names none: asked for, it comes back
/// 0/0 from the conversion too (measured 2026-10-23).
fn ask_for_the_stored_rate(reader: &IMFSourceReader, wanted: &IMFMediaType) {
    // SAFETY (each): a plain COM call on live objects.
    let Ok(stored) = (unsafe { reader.GetNativeMediaType(VIDEO, 0) }) else { return };
    if let Ok(packed) = unsafe { stored.GetUINT64(&MF_MT_FRAME_RATE) }
        && halves(packed).0 != 0
        && halves(packed).1 != 0
    {
        let _ = unsafe { wanted.SetUINT64(&MF_MT_FRAME_RATE, packed) };
    }
}
