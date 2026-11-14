//! Media Foundation's source reader over the container's bytes — the
//! engine's Windows `qa_os_open`. MF inserts the codec (AAC, WMA, ...) and
//! its float converter; the output asked for is float PCM and leaves the
//! rate and channels at the source's own, which is exactly the conform
//! contract.
//!
//! 🚨MF opens a URL or a byte stream and nothing else, so the container
//! arrives as the one span stream (`media::media_foundation::span_stream`)
//! — over the same span, plain or framed.
//!
//! It takes nothing off the front: an edit list's 1,024 came back as 1,024
//! frames before the sound (measured 2026-10-09), so where the sound starts
//! is the file's to say (`start::container_start`).

use media::media_foundation::{span_stream, up};
use windows::Win32::Media::MediaFoundation::{
    IMFByteStream, IMFSample, IMFSourceReader, MF_MT_AUDIO_NUM_CHANNELS, MF_MT_AUDIO_SAMPLES_PER_SECOND,
    MF_MT_MAJOR_TYPE, MF_MT_SUBTYPE, MF_SOURCE_READER_ALL_STREAMS, MF_SOURCE_READER_FIRST_AUDIO_STREAM,
    MF_SOURCE_READERF_ENDOFSTREAM, MFAudioFormat_Float, MFCreateMediaType, MFCreateSourceReaderFromByteStream,
    MFMediaType_Audio,
};
use windows::Win32::System::Com::{COINIT_MULTITHREADED, CoInitializeEx, CoUninitialize};

use crate::FORMAT_OS;
use crate::container::Container;
use crate::start::Start;
use crate::stream::{Decode, Opened};

const FIRST_AUDIO: u32 = MF_SOURCE_READER_FIRST_AUDIO_STREAM.0 as u32;

/// The thread's COM, for as long as what was made with it lives.
///
/// ⚠️A stream is read and dropped on the thread that opened it: COM's
/// apartment is the thread's, and the balance is struck on drop. The
/// conform opens, reads and drops one inside a single synchronous build.
struct Com {
    balanced: bool,
}

impl Com {
    fn start() -> Com {
        // Per-thread COM, balanced on drop; RPC_E_CHANGED_MODE means the
        // thread already runs an incompatible apartment — go on without the
        // balance.
        // SAFETY: no pointers.
        Com { balanced: unsafe { CoInitializeEx(None, COINIT_MULTITHREADED) }.is_ok() }
    }
}

impl Drop for Com {
    fn drop(&mut self) {
        if self.balanced {
            // SAFETY: the start this balances.
            unsafe { CoUninitialize() };
        }
    }
}

struct MediaFoundation {
    reader: IMFSourceReader,
    _stream: IMFByteStream,
    channels: usize,
    /// The reader said the stream ended, with the sample handed back last.
    ended: bool,
    /// ⚠️LAST: fields drop in order, and COM goes after what was made with it.
    _com: Com,
}

/// The container read by Media Foundation, or None when it does not read
/// it.
pub(super) fn open(container: &Container) -> Option<Opened> {
    // ⚠️First, so it drops last on every way out.
    let com = Com::start();
    if !up() {
        return None;
    }
    let stream = span_stream::open(container.span_again()?);
    // SAFETY: plain COM calls on live objects.
    let (reader, channels, rate) = unsafe {
        let reader = MFCreateSourceReaderFromByteStream(&stream, None).ok()?;
        reader.SetStreamSelection(MF_SOURCE_READER_ALL_STREAMS.0 as u32, false).ok()?;
        reader.SetStreamSelection(FIRST_AUDIO, true).ok()?;
        let requested = MFCreateMediaType().ok()?;
        requested.SetGUID(&MF_MT_MAJOR_TYPE, &MFMediaType_Audio).ok()?;
        requested.SetGUID(&MF_MT_SUBTYPE, &MFAudioFormat_Float).ok()?;
        reader.SetCurrentMediaType(FIRST_AUDIO, None, &requested).ok()?;
        let actual = reader.GetCurrentMediaType(FIRST_AUDIO).ok()?;
        let channels = actual.GetUINT32(&MF_MT_AUDIO_NUM_CHANNELS).ok()?;
        let rate = actual.GetUINT32(&MF_MT_AUDIO_SAMPLES_PER_SECOND).ok()?;
        (reader, channels, rate)
    };
    let (Ok(channels_said), Ok(sample_rate)) = (i32::try_from(channels), i32::try_from(rate)) else { return None };
    if channels == 0 || rate == 0 {
        return None;
    }
    let decoder = MediaFoundation { reader, _stream: stream, channels: channels as usize, ended: false, _com: com };
    Some(Opened { decoder: Box::new(decoder), format: FORMAT_OS, channels: channels_said, sample_rate, start: Start::default() })
}

impl MediaFoundation {
    /// `sample`'s frames into `block`: how many — 0 when it holds none.
    fn take(&self, sample: &IMFSample, block: &mut Vec<f32>) -> usize {
        let frame_bytes = size_of::<f32>() * self.channels;
        // SAFETY: plain COM calls on a live sample; what the locked buffer
        // holds is `length` bytes at `bytes`, copied out before the unlock.
        unsafe {
            let Ok(buffer) = sample.ConvertToContiguousBuffer() else { return 0 };
            let mut bytes = std::ptr::null_mut();
            let mut length = 0u32;
            if buffer.Lock(&mut bytes, None, Some(&mut length)).is_err() {
                return 0;
            }
            let frames = length as usize / frame_bytes;
            block.resize(frames * self.channels, 0.0);
            // Bytes, not floats: nothing promises the buffer is aligned.
            std::ptr::copy_nonoverlapping(bytes, block.as_mut_ptr().cast::<u8>(), frames * frame_bytes);
            let _ = buffer.Unlock();
            frames
        }
    }
}

impl Decode for MediaFoundation {
    /// ⚠️A sample the reader will not hand over is the end — as every
    /// decoder behind a stream says it; the C failed the whole decode there.
    fn next(&mut self, block: &mut Vec<f32>) -> usize {
        while !self.ended {
            let mut flags = 0u32;
            let mut sample: Option<IMFSample> = None;
            // SAFETY: a plain COM call; the out pointers are locals.
            let read =
                unsafe { self.reader.ReadSample(FIRST_AUDIO, 0, None, Some(&mut flags), None, Some(&mut sample)) };
            if read.is_err() {
                return 0;
            }
            if flags & MF_SOURCE_READERF_ENDOFSTREAM.0 as u32 != 0 {
                self.ended = true;
            }
            let frames = sample.map_or(0, |sample| self.take(&sample, block));
            if frames != 0 {
                return frames;
            }
        }
        0
    }
}
