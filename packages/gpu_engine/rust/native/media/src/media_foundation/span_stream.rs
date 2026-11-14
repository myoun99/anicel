//! An `IMFByteStream` over a medium stored in a SPAN of a file — plain or
//! framed — the Windows half of opening a movie or a sound that lives inside
//! the project file. ↩️The C engine's `qa_win_range_stream.c` until the
//! connection round deleted it (connection-round-checklist H, 2026-11-08).
//!
//! ⛔A module of its own rather than more lines inside a decoder that reads
//! through it: a decoder is its law and its backends, and hand-written COM
//! is neither.
//!
//! 🚨★★★**WHY THIS EXISTS AT ALL.** Media Foundation opens a URL or a byte
//! stream, and it ships no stream over a SUB-RANGE: `MFCreateFile` covers the
//! whole thing. A carried medium's bytes are a stretch of the `.anicel`, so
//! 「the whole file」 is a ZIP and the reader would fail somewhere far from
//! the cause.
//!
//! 🚨The BYTES come from [Span], the library's one reader of a span, so a
//! FRAMED span is served too — decompressed a block at a time as Media
//! Foundation asks — and a medium the save compressed opens without its
//! original. ⛔Nothing here reads a file; keep it that way. ⛔And there is
//! ONE of these: the audio decoder's OS stage and the video decoder read
//! through the same stream — two hand-written COM byte streams drift.
//!
//! 🚨★★★**MEDIA FOUNDATION CALLS THIS FROM ITS OWN THREADS**
//! (framed-movie-parity-hangs-under-load, 2026-09-29). The source inside a
//! reader reads on MF's work-queue threads while the caller's thread tears
//! the reader down: in the C, which said 「nothing here is shared between
//! threads」, Close freed the file and the block buffers under a read still
//! using them, the stream could go before a read's callback finished it,
//! and every EndRead reported the LAST read's count — under load (the work
//! queue behind, the teardown on time) the native parity lost its test
//! process mid-suite, twice. So: one lock over the span and the position,
//! and each read carries its own answer and a hold on the stream until its
//! callback has finished it.

use std::sync::{Mutex, MutexGuard, PoisonError};

use windows::Win32::Foundation::{E_FAIL, E_INVALIDARG, E_NOTIMPL, E_POINTER};
use windows::Win32::Media::MediaFoundation::{
    IMFAsyncCallback, IMFAsyncResult, IMFByteStream, IMFByteStream_Impl, MFBYTESTREAM_IS_READABLE,
    MFBYTESTREAM_IS_SEEKABLE, MFBYTESTREAM_SEEK_ORIGIN, MFCreateAsyncResult, MFInvokeCallback, msoCurrent,
};
use windows::core::{BOOL, IUnknown, IUnknownImpl, Interface, Ref, Result, implement};

use crate::span::Span;

/// What a read, a seek and a close each hold for the whole of what they do,
/// so a close waits for the read it meets and a read after it is refused.
struct Held {
    /// The medium — None once closed. Every position here is the MEDIUM's:
    /// for a framed span, a position in the decoded bytes, and nothing above
    /// this stream ever learns that it is not a whole file.
    span: Option<Span>,
    position: i64,
}

#[implement(IMFByteStream)]
struct SpanStream {
    held: Mutex<Held>,
    /// Set once, before anyone else can see the stream.
    length: i64,
}

/// One BeginRead's answer: how many bytes it read, and a hold on the stream
/// its callback will finish it on. The async result carries it to EndRead.
#[implement()]
struct Answer {
    got: u32,
    _stream: IMFByteStream,
}

/// A readable, seekable stream over `span`'s medium. The caller owns one
/// reference.
///
/// ⚠️The file is opened by [Span], which shares it for reading AND writing:
/// it is the project the app is still using, and refusing to share it would
/// make opening a carried medium lock the save out.
pub fn open(span: Span) -> IMFByteStream {
    let length = span.size();
    SpanStream { held: Mutex::new(Held { span: Some(span), position: 0 }), length }.into()
}

impl SpanStream {
    fn hold(&self) -> MutexGuard<'_, Held> {
        self.held.lock().unwrap_or_else(PoisonError::into_inner)
    }

    /// `wanted` clamped into the medium.
    ///
    /// ⚠️CLAMPED, not refused. A reader probing past the end is ordinary — it
    /// is how it finds the end — and an error there reads as a broken file.
    fn place(&self, held: &mut Held, wanted: i64) {
        held.position = wanted.clamp(0, self.length);
    }

    /// The one place bytes actually move: up to `into.len()` of them from
    /// the position — short at the medium's end, which [Span::read] keeps
    /// to. Everything else is bookkeeping.
    fn read_at(&self, into: &mut [u8]) -> Result<u32> {
        let mut held = self.hold();
        let position = held.position;
        // Closed: nothing left to read from.
        let span = held.span.as_mut().ok_or(E_FAIL)?;
        // The file would not read, or a block would not decode: a broken
        // medium, said as one rather than served as whatever the buffer held.
        let read = span.read(position, into).ok_or(E_FAIL)?;
        held.position += read as i64;
        Ok(read as u32)
    }
}

/// `count` bytes at `at`, as Media Foundation hands them over.
///
/// # Safety
/// `at` is non-null and holds `count` writable bytes.
unsafe fn bytes<'a>(at: *mut u8, count: u32) -> &'a mut [u8] {
    // SAFETY: the caller's contract.
    unsafe { std::slice::from_raw_parts_mut(at, count as usize) }
}

impl IMFByteStream_Impl for SpanStream_Impl {
    fn GetCapabilities(&self) -> Result<u32> {
        // ⛔No MFBYTESTREAM_HAS_SLOW_SEEK and no partial-download flags: this
        // is a local file, and claiming otherwise makes the source reader
        // buffer for a network that is not there.
        Ok(MFBYTESTREAM_IS_READABLE | MFBYTESTREAM_IS_SEEKABLE)
    }

    fn GetLength(&self) -> Result<u64> {
        Ok(self.length as u64)
    }

    fn SetLength(&self, _length: u64) -> Result<()> {
        // A span inside somebody else's file does not grow.
        Err(E_NOTIMPL.into())
    }

    fn GetCurrentPosition(&self) -> Result<u64> {
        Ok(self.hold().position as u64)
    }

    fn SetCurrentPosition(&self, position: u64) -> Result<()> {
        // Past what an i64 holds is past the end.
        self.place(&mut self.hold(), i64::try_from(position).unwrap_or(i64::MAX));
        Ok(())
    }

    fn IsEndOfStream(&self) -> Result<BOOL> {
        Ok((self.hold().position >= self.length).into())
    }

    fn Read(&self, into: *mut u8, want: u32, got: *mut u32) -> Result<()> {
        if into.is_null() || got.is_null() {
            return Err(E_POINTER.into());
        }
        // SAFETY: the reader's buffer of `want` bytes, and its count.
        unsafe {
            *got = 0;
            *got = self.read_at(bytes(into, want))?;
        }
        Ok(())
    }

    fn BeginRead(
        &self,
        into: *mut u8,
        want: u32,
        callback: Ref<IMFAsyncCallback>,
        state: Ref<IUnknown>,
    ) -> Result<()> {
        // ⛔NOT E_NOTIMPL. The source reader is free to use the async pair,
        // and a stream that refuses it can fail to open a file it can
        // plainly read. The read happens NOW — a local file has nothing to
        // wait for — and the callback is invoked so the caller's shape is
        // honoured.
        let Some(callback) = callback.as_ref() else { return Err(E_POINTER.into()) };
        if into.is_null() {
            return Err(E_POINTER.into());
        }
        // SAFETY: the reader's buffer of `want` bytes.
        let got = self.read_at(unsafe { bytes(into, want) })?;
        let answer: IUnknown = Answer { got, _stream: self.to_interface() }.into();
        // SAFETY: plain COM calls on live objects.
        unsafe {
            let result = MFCreateAsyncResult(&answer, callback, state.as_ref())?;
            MFInvokeCallback(&result)
        }
    }

    fn EndRead(&self, result: Ref<IMFAsyncResult>) -> Result<u32> {
        let Some(result) = result.as_ref() else { return Err(E_POINTER.into()) };
        // SAFETY: a plain COM call on a live result.
        let object = unsafe { result.GetObject() }?;
        // ⛔Only a result this stream made carries an answer it can read.
        let got = object.cast_object_ref::<Answer>().map_err(|_| E_INVALIDARG)?.got;
        // SAFETY: as above.
        unsafe { result.GetStatus() }?;
        Ok(got)
    }

    fn Write(&self, _from: *const u8, _want: u32) -> Result<u32> {
        Err(E_NOTIMPL.into())
    }

    fn BeginWrite(
        &self,
        _from: *const u8,
        _want: u32,
        _callback: Ref<IMFAsyncCallback>,
        _state: Ref<IUnknown>,
    ) -> Result<()> {
        Err(E_NOTIMPL.into())
    }

    fn EndWrite(&self, _result: Ref<IMFAsyncResult>) -> Result<u32> {
        Err(E_NOTIMPL.into())
    }

    fn Seek(&self, origin: MFBYTESTREAM_SEEK_ORIGIN, by: i64, _flags: u32) -> Result<u64> {
        let mut held = self.hold();
        let from = if origin == msoCurrent { held.position } else { 0 };
        self.place(&mut held, from.saturating_add(by));
        Ok(held.position as u64)
    }

    fn Flush(&self) -> Result<()> {
        Ok(())
    }

    fn Close(&self) -> Result<()> {
        self.hold().span = None;
        Ok(())
    }
}
