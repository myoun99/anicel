//! A medium stored in a span of a file, served to MediaExtractor as a
//! source of our own — the engine's `qa_ndk_served_span`
//! (`qa_ndk_media.c`): how a FRAMED span, whose stored bytes are not the
//! container, reaches the extractor at all.
//!
//! ⚠️ONE serving for the video decoder and the audio decoder: each needs
//! exactly this, and the lock below is the part a second copy forgets.
//!
//! 🚨★★★**THE NDK'S API IS `ndk-sys`'s — BINDINGS MADE FROM THE NDK'S OWN
//! HEADERS, NEVER A TABLE WRITTEN BY HAND** (관제 2026-11-07, native-to-rust:
//! 「손 사본 대신 ndk-sys」 — as the C took the headers on 2026-10-24, board
//! ndk-media-table-goes-to-the-headers). Three hand-written tables of
//! 2026-09-24 disagreed where it mattered: an `AMediaDataSource` read is
//! handed an `off64_t`, and the table that said `off_t` read the offset out
//! of the wrong registers on a 32-bit device; `AMediaCodec_queueInputBuffer`
//! takes a `long`, which two said was 64 bits.

use std::ffi::c_void;
use std::sync::{Mutex, PoisonError};

use ndk_sys::{
    AMediaDataSource, AMediaDataSource_delete, AMediaDataSource_new, AMediaDataSource_setGetSize,
    AMediaDataSource_setReadAt, AMediaDataSource_setUserdata, off64_t,
};

use crate::span::Span;

/// What the source's callbacks are handed.
struct Served {
    /// ⚠️LOCKED: the extractor may ask from a thread of its own, and the span
    /// reader is ONE reader — its file position and its cached block are
    /// shared by every read.
    span: Mutex<Span>,
    size: i64,
}

/// A span served as an `AMediaDataSource`.
pub struct ServedSpan {
    source: *mut AMediaDataSource,
    /// Where the source's callbacks point: boxed, so it does not move.
    _served: Box<Served>,
}

impl ServedSpan {
    /// `span` served — None when the NDK makes no source.
    pub fn open(span: Span) -> Option<ServedSpan> {
        let size = span.size();
        let served = Box::new(Served { span: Mutex::new(span), size });
        // SAFETY: no arguments.
        let source = unsafe { AMediaDataSource_new() };
        if source.is_null() {
            return None;
        }
        // SAFETY: a live source; the userdata is the box, which lives as
        // long as the source does (`Drop` deletes the source first).
        unsafe {
            AMediaDataSource_setUserdata(source, std::ptr::from_ref::<Served>(&served).cast_mut().cast());
            AMediaDataSource_setReadAt(source, Some(read_at));
            AMediaDataSource_setGetSize(source, Some(medium_size));
        }
        Some(ServedSpan { source, _served: served })
    }

    /// What to hand `AMediaExtractor_setDataSourceCustom`.
    pub fn source(&self) -> *mut AMediaDataSource {
        self.source
    }
}

/// ⚠️Dropped only AFTER the extractor it was handed to is deleted: the
/// extractor reads through it for as long as it lives.
impl Drop for ServedSpan {
    fn drop(&mut self) {
        // SAFETY: the source this made, deleted once — before the box its
        // callbacks point at, which goes with the fields after this.
        unsafe { AMediaDataSource_delete(self.source) };
    }
}

/// `AMediaDataSourceReadAt`: -1 is BOTH the end and a failure, and 0 is only
/// for a zero-byte ask.
unsafe extern "C" fn read_at(user: *mut c_void, offset: off64_t, buffer: *mut c_void, size: usize) -> isize {
    if size == 0 {
        return 0;
    }
    // SAFETY: the userdata `open` set, alive while the source is; the
    // extractor's buffer of `size` bytes.
    let (served, out) =
        unsafe { (&*user.cast::<Served>(), std::slice::from_raw_parts_mut(buffer.cast::<u8>(), size)) };
    match served.span.lock().unwrap_or_else(PoisonError::into_inner).read(offset, out) {
        Some(read) if read > 0 => read as isize,
        _ => -1,
    }
}

/// `AMediaDataSourceGetSize`: the medium's bytes — decoded, for a framed
/// span.
unsafe extern "C" fn medium_size(user: *mut c_void) -> isize {
    // SAFETY: as for `read_at`.
    unsafe { &*user.cast::<Served>() }.size as isize
}
